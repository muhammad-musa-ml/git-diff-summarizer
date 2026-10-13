#!/usr/bin/env bash
# Cold builds of the tool image on top of the cached model image, plus image
# sizes. Writes bench/results/build-times.csv and image-sizes.txt.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
results=$root/bench/results
mkdir -p "$results"

echo "run,seconds" >"$results/build-times.csv"
for run in 1 2 3; do
    start=$(date +%s.%N)
    # --no-cache re-runs the apt layer; the model image is only referenced
    docker build -q --no-cache -t git-diff-summarizer:buildtime \
        --build-arg BASE=git-diff-summarizer-model:latest "$root" >/dev/null
    end=$(date +%s.%N)
    echo "$run,$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.1f", b - a }')" >>"$results/build-times.csv"
done
docker rmi git-diff-summarizer:buildtime >/dev/null

{
    for img in git-diff-summarizer-model:latest git-diff-summarizer:latest; do
        size=$(docker image inspect "$img" --format '{{.Size}}')
        echo "$img $size bytes ($(awk -v s="$size" 'BEGIN { printf "%.2f", s / 1e9 }') GB)"
    done
} >"$results/image-sizes.txt"
cat "$results/build-times.csv" "$results/image-sizes.txt"
