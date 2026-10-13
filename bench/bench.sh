#!/usr/bin/env bash
# Measures the summarizer on the commits listed in a commits file.
#
#   bench/bench.sh --commits-file bench/commits.txt --mode oneshot --reps 5
#   bench/bench.sh --commits-file bench/commits.txt --mode server --reps 5
#
# The commits file starts with "# repo URL" and "# head SHA" lines, then one
# "sha diff_bytes bucket subject" line per commit (bench/pick_commits.sh
# prints those). Output goes to bench/results/<name>-<mode>.csv, one row per
# run, plus <name>-<mode>-env.txt. Server mode warms the server with one
# uncounted request first.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
commits_file=$root/bench/commits.txt
reps=5
mode=oneshot
max_bytes=24000
name=
while [ $# -gt 0 ]; do
    case $1 in
    --commits-file) commits_file=$2; shift 2 ;;
    --reps) reps=$2; shift 2 ;;
    --mode) mode=$2; shift 2 ;;
    --max-bytes) max_bytes=$2; shift 2 ;;
    --name) name=$2; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
case $mode in oneshot | server) ;; *) echo "mode must be oneshot or server" >&2; exit 2 ;; esac

repo_url=$(sed -n 's/^# repo //p' "$commits_file")
pinned_head=$(sed -n 's/^# head //p' "$commits_file")
name=${name:-$(basename "$repo_url")}

# Local paths and the user name must not reach a committed file.
redact() {
    local win=$root
    if command -v cygpath >/dev/null 2>&1; then
        win=$(cygpath -w "$root")
    fi
    sed -e "s#$root#<repo>#g" -e "s#${win//\\/\\\\}#<repo>#g" \
        -e "s#$HOME#<home>#g" -e 's#[A-Za-z]:\\Users\\[^\\ ]*#<home>#g' \
        -e 's#/[a-z]/Users/[^/ ]*#<home>#g'
}

work=$root/bench/work/$name
results=$root/bench/results
mkdir -p "$work" "$results"
csv=$results/$name-$mode.csv

if [ ! -d "$work/repo/.git" ]; then
    git clone --quiet "$repo_url" "$work/repo"
fi
git -C "$work/repo" cat-file -e "$pinned_head^{commit}"

server_container=git-diff-summarizer-model-1
started_server=0
extra=()
if [ "$mode" = server ]; then
    extra+=(--server)
    if ! docker inspect "$server_container" >/dev/null 2>&1; then
        "$root/diffsum" serve
        started_server=1
    fi
    until [ "$(docker inspect -f '{{.State.Health.Status}}' "$server_container")" = healthy ]; do
        sleep 2
    done
fi

server_hwm() {
    MSYS_NO_PATHCONV=1 docker exec "$server_container" sh -c 'grep -h VmHWM /proc/[0-9]*/status 2>/dev/null; true' |
        awk '{ if ($2 > m) m = $2 } END { print m * 1024 }'
}

{
    echo "date: $(date -u +%FT%TZ)"
    echo "command: bench/bench.sh --commits-file bench/commits.txt --mode $mode --reps $reps --max-bytes $max_bytes"
    echo "repo: $repo_url"
    echo "repo head: $pinned_head"
    echo "docker: $(docker version --format '{{.Server.Version}}') $(docker info --format 'cpus={{.NCPU}} mem_bytes={{.MemTotal}}')"
    echo "model image: $(docker image inspect git-diff-summarizer-model:latest --format '{{.Id}} {{.Size}}')"
    echo "tool image: $(docker image inspect git-diff-summarizer:latest --format '{{.Id}} {{.Size}}')"
    echo "host: $(uname -sr)"
} | redact >"$results/$name-$mode-env.txt"

echo "commit,bucket,diff_bytes,rep,mode,files_changed,truncated,prompt_bytes,prompt_tokens,completion_tokens,load_s,prompt_eval_s,prompt_tok_per_s,gen_s,gen_tok_per_s,ttft_s,tool_s,wall_s,peak_rss_bytes,cgroup_peak_bytes,summary_sha256,same_as_first" >"$csv"

run_one() {
    "$root/diffsum" --repo "$work/repo" --commit "$1" --max-bytes "$max_bytes" \
        --format json "${extra[@]}" </dev/null >"$work/out.json"
}

if [ "$mode" = server ]; then
    first=$(awk '!/^#/ { print $1; exit }' "$commits_file")
    run_one "$first"
fi

while read -r sha size bucket _; do
    first_sum=
    for rep in $(seq 1 "$reps"); do
        t0=$(date +%s.%N)
        run_one "$sha"
        t1=$(date +%s.%N)
        rss=$(jq '.model_timings.peak_rss_bytes // ""' "$work/out.json")
        cg=$(jq '.peak_memory_bytes // ""' "$work/out.json")
        if [ "$mode" = server ]; then
            rss=$(server_hwm)
            cg=$(MSYS_NO_PATHCONV=1 docker exec "$server_container" cat /sys/fs/cgroup/memory.peak)
        fi
        sum_sha=$(jq -r .summary "$work/out.json" | sha256sum | cut -d' ' -f1)
        [ -n "$first_sum" ] || first_sum=$sum_sha
        same=$([ "$sum_sha" = "$first_sum" ] && echo yes || echo no)
        # the server reports no time to first token: prompt evaluation plus
        # one generated token stands in for it
        jq -r --arg sha "$sha" --arg bucket "$bucket" --arg size "$size" --arg rep "$rep" \
            --arg mode "$mode" --arg rss "$rss" --arg cg "$cg" --arg sum "$sum_sha" --arg same "$same" \
            --arg wall "$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", b - a }')" '
            .model_timings as $t |
            [$sha, $bucket, $size, $rep, $mode, .files_changed, .truncated, .prompt_bytes,
             $t.prompt_tokens, $t.completion_tokens, ($t.load_seconds // ""),
             ($t.prompt_ms / 1000), ($t.prompt_tokens / ($t.prompt_ms / 1000)),
             ($t.generation_ms / 1000), ($t.completion_tokens / ($t.generation_ms / 1000)),
             (($t.prompt_ms + $t.generation_ms / $t.completion_tokens) / 1000),
             .seconds, $wall, $rss, $cg, $sum, $same] | @csv' \
            "$work/out.json" | tr -d '"' >>"$csv"
    done
done < <(grep -v '^#' "$commits_file")

if [ "$started_server" = 1 ]; then
    "$root/diffsum" stop
fi
echo "wrote bench/results/$name-$mode.csv"
