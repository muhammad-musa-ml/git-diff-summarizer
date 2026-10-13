#!/usr/bin/env bash
# Prints the commit subject next to the model's summary for a few commits of
# the pinned list, so a reader can judge the text by eye.
#   bench/quality_samples.sh SHA... > bench/results/quality-samples.txt
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo=$root/bench/work/fd/repo

for sha in "$@"; do
    echo "commit $sha"
    echo "subject: $(git -C "$repo" log -1 --format=%s "$sha")"
    echo "summary:"
    "$root/diffsum" --repo "$repo" --commit "$sha" </dev/null
    echo
done
