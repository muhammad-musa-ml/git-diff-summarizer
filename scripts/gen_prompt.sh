#!/usr/bin/env bash
# Builds the model prompt for one change.
# Usage: gen_prompt.sh REPO_DIR BASE_SHA HEAD_SHA MAX_BYTES PROMPT_FILE STATS_FILE
# STATS_FILE gets key=value lines: files_changed, lines_added, lines_removed,
# files_skipped, truncated, diff_bytes.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

[ $# -eq 6 ] || die "usage: gen_prompt.sh REPO BASE HEAD MAX_BYTES PROMPT STATS"
repo=$1 base=$2 head=$3 max_bytes=$4 prompt=$5 stats=$6

case $max_bytes in
'' | *[!0-9]*) die "max bytes must be a number, got '$max_bytes'" ;;
esac
[ "$max_bytes" -gt 0 ] || die "max bytes must be positive"

trust_all_repos
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
meta=$tmp/meta

# Totals come from numstat over the whole change, before any filtering, so a
# truncated or filtered prompt still reports the true size of the change.
git -C "$repo" diff --numstat --no-color "$base" "$head" |
    awk -F'\t' '
        { files++ }
        $1 != "-" { add += $1; del += $2 }
        END { printf "%d %d %d\n", files, add, del }' >"$tmp/totals"
read -r files added removed <"$tmp/totals"

: >"$meta"
git -C "$repo" diff --no-color --no-ext-diff -M --unified=3 "$base" "$head" |
    LC_ALL=C awk -v budget="$max_bytes" -v meta="$meta" -f "$here/filter_diff.awk" >"$tmp/diff"

diff_bytes=$(wc -c <"$tmp/diff")
skipped=$(grep -c '^skipped' "$meta" || true)
truncated=no
if grep -q '^truncated' "$meta"; then
    truncated=yes
fi

{
    echo "Below is the diff of a git change. Read it and explain what the change does."
    echo
    echo "Files changed: $files (+$added -$removed lines)"
    if [ "$skipped" -gt 0 ]; then
        echo "Left out of the diff (binary, lockfile or generated): $(awk -F'\t' '$1 == "skipped" { printf "%s%s", sep, $2; sep = ", " }' "$meta")"
    fi
    if [ "$truncated" = yes ]; then
        echo "The diff was cut at $max_bytes bytes. Files not shown in full: $(awk -F'\t' '$1 == "truncated" || $1 == "omitted" { printf "%s%s", sep, $2; sep = ", " }' "$meta")"
    fi
    echo
    echo "<diff>"
    cat "$tmp/diff"
    echo "</diff>"
    echo
    echo "Summarize this change in two to four sentences of plain prose: what it changes,"
    echo "and what that does for the code. Name the files or functions that matter."
    echo "No headings, no bullet points, no code blocks."
    if [ "$truncated" = yes ]; then
        echo "Say that the diff was truncated and the summary covers only the part shown."
    fi
} >"$prompt"

printf 'files_changed=%s\nlines_added=%s\nlines_removed=%s\nfiles_skipped=%s\ntruncated=%s\ndiff_bytes=%s\n' \
    "$files" "$added" "$removed" "$skipped" "$truncated" "$diff_bytes" >"$stats"
