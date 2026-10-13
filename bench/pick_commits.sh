#!/usr/bin/env bash
# Picks commits of a clone that span small to large filtered diffs and prints
# one line each: sha, filtered diff bytes, bucket, subject.
#   bench/pick_commits.sh CLONE HEAD_SHA [WINDOW]
# Sizes use the same filter the tool applies (no lockfiles, binaries or
# minified files), measured with an effectively unlimited budget.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
clone=$1
head=$2
window=${3:-800}

want_small=4 want_mid=3 want_large=1 want_huge=2
small=0 mid=0 large=0 huge=0

while read -r sha; do
    size=$(git -C "$clone" show --format= -M --unified=3 --no-color "$sha" |
        LC_ALL=C awk -v budget=1000000000 -v meta=/dev/null -f "$root/scripts/filter_diff.awk" | wc -c)
    bucket=
    if [ "$size" -gt 0 ] && [ "$size" -lt 2000 ] && [ "$small" -lt "$want_small" ]; then
        bucket=small small=$((small + 1))
    elif [ "$size" -ge 5000 ] && [ "$size" -le 10000 ] && [ "$mid" -lt "$want_mid" ]; then
        bucket=mid mid=$((mid + 1))
    elif [ "$size" -gt 10000 ] && [ "$size" -le 24000 ] && [ "$large" -lt "$want_large" ]; then
        bucket=large large=$((large + 1))
    elif [ "$size" -gt 30000 ] && [ "$huge" -lt "$want_huge" ]; then
        bucket=huge huge=$((huge + 1))
    fi
    if [ -n "$bucket" ]; then
        printf '%s %s %s %s\n' "$sha" "$size" "$bucket" "$(git -C "$clone" log -1 --format=%s "$sha")"
    fi
    if [ $((small + mid + large + huge)) -eq $((want_small + want_mid + want_large + want_huge)) ]; then
        break
    fi
done < <(git -C "$clone" rev-list --no-merges -n "$window" "$head")
