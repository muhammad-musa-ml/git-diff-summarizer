#!/usr/bin/env bash
# Measures the summarizer on the latest N non-merge commits of a public repo.
#
#   bench/bench.sh --repo https://github.com/sharkdp/fd --commits 2 --reps 3
#   bench/bench.sh --repo ... --mode server
#
# Writes bench/results/<name>-<mode>.csv (one row per run), -summary.csv (one
# row per commit, including whether repeated runs matched byte for byte) and
# -env.txt (machine, images, exact command).
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo_url=https://github.com/sharkdp/fd
commits=2
reps=3
mode=oneshot
max_bytes=24000
name=
while [ $# -gt 0 ]; do
    case $1 in
    --repo) repo_url=$2; shift 2 ;;
    --commits) commits=$2; shift 2 ;;
    --reps) reps=$2; shift 2 ;;
    --mode) mode=$2; shift 2 ;;
    --max-bytes) max_bytes=$2; shift 2 ;;
    --name) name=$2; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
case $mode in oneshot | server) ;; *) echo "mode must be oneshot or server" >&2; exit 2 ;; esac
name=${name:-$(basename "$repo_url")}

work=$root/bench/work/$name
results=$root/bench/results
mkdir -p "$work" "$results"
csv=$results/$name-$mode.csv
summary_csv=$results/$name-$mode-summary.csv

if [ ! -d "$work/repo/.git" ]; then
    git clone --quiet "$repo_url" "$work/repo"
fi
head_sha=$(git -C "$work/repo" rev-parse HEAD)
mapfile -t shas < <(git -C "$work/repo" rev-list --no-merges -n "$commits" "$head_sha")

started_server=0
server_container=git-diff-summarizer-model-1
if [ "$mode" = server ]; then
    if ! docker inspect "$server_container" >/dev/null 2>&1; then
        "$root/diffsum" serve
        started_server=1
    fi
    until [ "$(docker inspect -f '{{.State.Health.Status}}' "$server_container")" = healthy ]; do
        sleep 2
    done
fi

{
    echo "date: $(date -u +%FT%TZ)"
    echo "command: bench/bench.sh --repo $repo_url --commits $commits --reps $reps --mode $mode --max-bytes $max_bytes"
    echo "repo head: $head_sha"
    echo "commits: ${shas[*]}"
    echo "docker: $(docker version --format '{{.Server.Version}}') $(docker info --format 'cpus={{.NCPU}} mem_bytes={{.MemTotal}}')"
    echo "model image: $(docker image inspect git-diff-summarizer-model:latest --format '{{.Id}} {{.Size}}')"
    echo "tool image: $(docker image inspect git-diff-summarizer:latest --format '{{.Id}} {{.Size}}')"
    echo "host: $(uname -sr)"
} >"$results/$name-$mode-env.txt"

echo "commit,rep,mode,files_changed,truncated,prompt_bytes,prompt_tokens,completion_tokens,load_seconds,prompt_ms,ttft_ms,generation_ms,tool_seconds,wall_seconds,peak_memory_bytes,summary_sha256" >"$csv"

extra=()
if [ "$mode" = server ]; then
    extra+=(--server)
fi

for sha in "${shas[@]}"; do
    for rep in $(seq 1 "$reps"); do
        t0=$(date +%s.%N)
        "$root/diffsum" --repo "$work/repo" --commit "$sha" --max-bytes "$max_bytes" \
            --format json "${extra[@]}" >"$work/out.json"
        t1=$(date +%s.%N)
        peak=$(jq .peak_memory_bytes "$work/out.json")
        if [ "$mode" = server ]; then
            peak=$(MSYS_NO_PATHCONV=1 docker exec "$server_container" cat /sys/fs/cgroup/memory.peak)
        fi
        sum_sha=$(jq -r .summary "$work/out.json" | sha256sum | cut -d' ' -f1)
        # time to first token is not reported by the server, so it is the prompt
        # evaluation time plus one token of generation
        jq -r --arg sha "$sha" --arg rep "$rep" --arg mode "$mode" --arg peak "$peak" \
            --arg sum "$sum_sha" --arg wall "$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", b - a }')" '
            [$sha, $rep, $mode, .files_changed, .truncated, .prompt_bytes,
             .model_timings.prompt_tokens, .model_timings.completion_tokens,
             (.model_timings.load_seconds // ""),
             .model_timings.prompt_ms,
             (.model_timings.prompt_ms + (.model_timings.generation_ms / .model_timings.completion_tokens)),
             .model_timings.generation_ms, .seconds, $wall, $peak, $sum] | @csv' \
            "$work/out.json" | tr -d '"' >>"$csv"
    done
done

echo "commit,runs,distinct_outputs,identical" >"$summary_csv"
for sha in "${shas[@]}"; do
    distinct=$(awk -F, -v c="$sha" '$1 == c { print $16 }' "$csv" | sort -u | wc -l)
    runs=$(awk -F, -v c="$sha" '$1 == c' "$csv" | wc -l)
    echo "$sha,$runs,$distinct,$([ "$distinct" = 1 ] && echo yes || echo no)" >>"$summary_csv"
done

if [ "$started_server" = 1 ]; then
    "$root/diffsum" stop
fi
echo "wrote $csv"
