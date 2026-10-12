# git-diff-summarizer

Summarizes what a git change does using Gemma 4 E2B running on CPU in Docker. Nothing leaves the machine.

## Run it

Needs Docker (Engine 28 or newer with Compose v2), bash, curl and about 8 GB of free RAM for the container, plus roughly 12 GB of disk for the images.

Build the images. This downloads the llamafile runtime and the 3.3 GB model, and checks both against pinned SHA256 sums:

    ./diffsum build

Summarize a commit, a pair of refs, or a branch against its merge base:

    ./diffsum --repo . --commit HEAD
    ./diffsum --repo https://github.com/sharkdp/fd --base v10.0.0 --head v10.1.0
    ./diffsum --repo . --base main --head my-branch --merge-base --format json

To keep the model loaded between calls:

    ./diffsum serve
    ./diffsum --server --repo . --commit HEAD
    ./diffsum stop

Run the tests (shellcheck and bats, in a container, no model needed):

    bash tests/run.sh

Tear everything down:

    ./diffsum stop
    docker rmi git-diff-summarizer git-diff-summarizer-model

## TODO for the measurement pass

- where it came from (the CS 544 project and what I changed)
- how it works: prompt layout, truncation, skipped files, deterministic settings
- measured results from `bench/bench.sh` with machine and config (5 or more reps, median and range)
- the determinism check across repeated runs and across one-shot vs server mode
- using the PR comment workflow in `examples/pr-summary.yml`
- limitations
