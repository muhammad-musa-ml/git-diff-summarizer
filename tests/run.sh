#!/usr/bin/env bash
# Lint and unit tests in a throwaway Ubuntu container, so the result
# does not depend on the host git, awk or line endings. The CI workflow runs
# the same two commands directly on its runner.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
docker build -q -t git-diff-summarizer-tests "$root/tests" >/dev/null

mount=$root
if command -v cygpath >/dev/null 2>&1; then
    mount=$(cygpath -w "$root")
fi
export MSYS_NO_PATHCONV=1
exec docker run --rm --memory 1g -v "$mount:/src:ro" git-diff-summarizer-tests \
    bash -c 'cd /src && shellcheck diffsum model/fetch.sh scripts/*.sh bench/bench.sh tests/*.sh tests/stub/llamafile && bats tests/'
