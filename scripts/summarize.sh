#!/usr/bin/env bash
# Entry point of the tool image: summarize one git change.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

usage() {
    cat <<'EOF'
usage: summarize.sh [options]
  --repo SRC          git URL or a directory (default: /repo)
  --base REF          older side of the comparison
  --head REF          newer side (default: HEAD)
  --merge-base        compare head against its merge base with --base
  --commit REF        summarize a single commit against its first parent
  --max-bytes N       diff bytes sent to the model (default: 24000)
  --format text|json  output format (default: text)
EOF
}

src=/repo
max_bytes=${DIFFSUM_MAX_BYTES:-24000}
format=text
change_args=()
while [ $# -gt 0 ]; do
    case $1 in
    --repo) src=$2; shift 2 ;;
    --base | --head | --commit) change_args+=("$1" "$2"); shift 2 ;;
    --merge-base) change_args+=("$1"); shift ;;
    --max-bytes) max_bytes=$2; shift 2 ;;
    --format) format=$2; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option $1" ;;
    esac
done
case $format in text | json) ;; *) die "format must be text or json" ;; esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export DIFFSUM_WORKDIR=$work
started=$(now)

declare -A change stats

"$here/get_change.sh" "$src" "${change_args[@]}" >"$work/change"
while IFS='=' read -r key value; do
    change[$key]=$value
done <"$work/change"

"$here/gen_prompt.sh" "${change[repo_dir]}" "${change[base_sha]}" "${change[head_sha]}" \
    "$max_bytes" "$work/prompt.txt" "$work/stats.txt"
while IFS='=' read -r key value; do
    stats[$key]=$value
done <"$work/stats.txt"

raw=
if [ "${stats[files_changed]}" -eq 0 ]; then
    summary="No changes between ${change[base_label]} and ${change[head_label]}."
else
    raw=$("$here/run_model.sh" "$work/prompt.txt")
    [ -n "$raw" ] || die "the model returned nothing"
    summary=$(printf '%s\n' "$raw" | fmt -w 80)
fi

seconds=$(elapsed "$started" "$(now)")

if [ "$format" = text ]; then
    printf '%s\n' "$summary"
    exit 0
fi

# memory.peak only exists on cgroup v2 hosts; null when it cannot be read
peak=null
if [ -r /sys/fs/cgroup/memory.peak ]; then
    peak=$(cat /sys/fs/cgroup/memory.peak)
fi
timings=null
if [ -s "$work/timings.json" ]; then
    timings=$(cat "$work/timings.json")
fi

jq -n \
    --arg summary "${raw:-$summary}" \
    --arg base "${change[base_label]}" --arg head "${change[head_label]}" \
    --arg base_sha "${change[base_sha]}" --arg head_sha "${change[head_sha]}" \
    --arg model "${DIFFSUM_MODEL_NAME:-unknown}" \
    --argjson files "${stats[files_changed]}" --argjson added "${stats[lines_added]}" \
    --argjson removed "${stats[lines_removed]}" --argjson skipped "${stats[files_skipped]}" \
    --argjson truncated "$([ "${stats[truncated]}" = yes ] && echo true || echo false)" \
    --argjson prompt_bytes "$(wc -c <"$work/prompt.txt")" \
    --argjson seconds "$seconds" --argjson peak "$peak" --argjson timings "$timings" \
    '{summary: $summary,
      base: $base, head: $head, base_sha: $base_sha, head_sha: $head_sha,
      files_changed: $files, lines_added: $added, lines_removed: $removed,
      files_skipped: $skipped, truncated: $truncated,
      prompt_bytes: $prompt_bytes, model: $model,
      seconds: $seconds, peak_memory_bytes: $peak, model_timings: $timings}'
