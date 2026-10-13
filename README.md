# git-diff-summarizer

This repo has a Bash tool that reads a git change (a commit, two refs, or a branch against its merge base) and prints a short plain-English summary of it. The summary comes from Gemma 4 E2B running on the CPU inside Docker, so no API key is needed and the diff never leaves the machine.

## Where it came from

This started as P1 in CS 544 (Big Data Systems) at UW-Madison. In the course version you containerize a small local model, then write a script that clones a repo, diffs the `fix` branch against `main` into a prompt file, and asks the model for a one-sentence summary. The earlier Spring 25 version of P1 was a different exercise: a shell pipeline in Docker that downloaded gzipped mortgage data, decompressed it as a stream and counted matching records.

I rebuilt it from scratch afterwards and added what I needed to actually use it:

- a `diffsum` command that wraps `docker run`, with flags for repo, refs, byte budget and output format
- summaries of a single commit, of two refs, and of a branch against its merge base
- a byte budget on the diff, with binary files, lockfiles and minified files left out and the cut stated in the prompt
- JSON output with the summary plus refs, line counts, truncation, model name and timings
- a server mode that keeps the model loaded, and a compose file for it
- a model fetch script that pins the download URLs and checks SHA256 sums (the streaming-download-with-checksum habit from the S25 pipeline)
- shellcheck and bats tests that run against a stub model, so CI never downloads 3 GB
- a benchmark script and the results below
- an example GitHub Actions workflow that comments a summary on pull requests

## How it works

The model image is ubuntu:24.04 with the llamafile runtime (v0.10.6) and the `gemma-4-E2B-it-Q5_K_M.gguf` weights (3.36 GB, Apache-2.0 per its Hugging Face page). There is no ready-made Gemma 4 llamafile, so the runtime and the GGUF are separate files. The tool image is built on top of the model image through the `BASE` build argument and adds git, curl, jq and the scripts in `scripts/`.

A run goes through these stages:

1. `get_change.sh` resolves the refs. A URL is cloned without a checkout and without blobs (they are fetched on demand), a directory is used as it is. `--commit` compares against the first parent, or against the empty tree for a root commit. `--merge-base` compares the head with its merge base with `--base`.
2. `gen_prompt.sh` writes the prompt file. `filter_diff.awk` streams `git diff` and keeps whole files up to the byte budget (24000 by default, `--max-bytes`). A file that does not fit is cut at a line boundary, files after it are only named, and the prompt says the diff was cut. Lockfiles, binary files, `*.min.js`, `*.min.css` and `*.map` files are dropped and listed by name. The line counts at the top of the prompt come from `git diff --numstat` over the whole change, so they stay correct when the diff is cut.
3. `run_model.sh` sends the prompt to llamafile's HTTP server with temperature 0, seed 0 and thinking turned off. In one-shot mode it starts that server on loopback inside the container for the one request and kills it afterwards. If `DIFFSUM_SERVER` is set it uses a server that is already running. Model logging and stderr are discarded.
4. `summarize.sh` wraps the reply to 80 columns with `fmt`, or builds the JSON.

Two things in there are not obvious. The llamafile is started as `sh /opt/model/llamafile ...`: executing the file directly fails in the container with "not found", because the kernel has no loader for its APE header and only the shell's script fallback runs it. And I use the server's chat endpoint even for one-shot runs, because llamafile 0.10.6 `--cli` ignores every thinking-off switch I tried and prints a `<think>` block.

## Install and run

You need Docker (I used Engine 28.4.0 with Compose v2), bash, curl and git on the host, about 4 GB of free RAM for the container, and about 11 GB of disk (the downloads in `model/cache` plus the images). The wrapper is written for bash. I only ran it from Git Bash on Windows 11; I did not try macOS or Linux.

1. Build the images with `./diffsum build`. This downloads the llamafile runtime and the model into `model/cache`, checks both against the SHA256 sums pinned in `model/fetch.sh`, then builds `git-diff-summarizer-model` and `git-diff-summarizer`.
2. Summarize a commit of the current repository with `./diffsum --repo . --commit HEAD`. This prints a paragraph wrapped to 80 columns.
3. Summarize something else with any of these:

        ./diffsum --repo https://github.com/sharkdp/fd --commit 19a55aa
        ./diffsum --repo . --base v1.0 --head v1.1
        ./diffsum --repo . --base main --head my-branch --merge-base --format json

   A local path is mounted read-only. A URL is cloned inside the container.
4. To keep the model loaded between calls, run `./diffsum serve`, then add `--server` to the commands above, and run `./diffsum stop` when you are done. The server container publishes port 8100 on localhost and is limited to 6 GB.

Flags: `--repo SRC`, `--base REF`, `--head REF` (default `HEAD`), `--merge-base`, `--commit REF`, `--max-bytes N`, `--format text|json`, `--server`. `DIFFSUM_MEMORY` changes the container memory limit (default `6g`).

The JSON has `summary`, `base`, `head`, the two SHAs, `files_changed`, `lines_added`, `lines_removed`, `files_skipped`, `truncated`, `prompt_bytes`, `model`, `seconds`, `peak_memory_bytes` and a `model_timings` object (load seconds, prompt and completion tokens, prompt and generation milliseconds, peak RSS of the model process). `seconds` and the timings change from run to run; the text does not.

To comment a summary on every pull request, copy `examples/pr-summary.yml` into `.github/workflows/` of the repo you want it for. It needs a self-hosted runner with Docker and at least 8 GB of free RAM (the weights are 3.4 GB and the process I measured peaks at about 2.6 GiB resident), and each summary takes from about 15 seconds to a couple of minutes. It skips pull requests from forks. It is not run by this repo's own CI.

Tests: `bash tests/run.sh` builds a small Ubuntu image and runs shellcheck plus the 46 bats tests in it. They use a stub in `tests/stub/` that answers like the model server, so they need Docker but not the model. The CI workflow runs the same checks and also builds the tool image on the stub base.

Teardown: `./diffsum stop`, then `docker rmi git-diff-summarizer git-diff-summarizer-model`, then delete `model/cache` if you want the 3.7 GB back.

## Measurements

I ran the benchmark on 10 commits of `sharkdp/fd`, pinned in `bench/commits.txt` (repo head `14dcd92fb76ca0ebc2e82671a275f67c790d25fc`). `bench/pick_commits.sh` chose them by filtered diff size: four under 2 KB, three between 5 and 9 KB, one of 21 KB, and two over 32 KB that get cut at the 24000-byte budget. Each commit ran 5 times in one-shot mode and 5 times in server mode, which was started once and warmed with one uncounted request. Commands:

    bash bench/bench.sh --mode oneshot --reps 5 --name fd
    bash bench/bench.sh --mode server --reps 5 --name fd
    bash bench/build_times.sh
    python bench/summarize.py

Raw rows are in `bench/results/fd-oneshot.csv` and `fd-server.csv`; every figure below is copied from `bench/results/summary.md`, which `summarize.py` writes from those files. Cells are the median, with min and max in brackets.

Machine: Intel Core i7-13700HX (24 logical CPUs), 30 GB RAM, Windows 11 Home, Docker Engine 28.4.0 with a 15.5 GB VM, CPU only, no limit on threads. It was not idle: other desktop programs were running, and `bench/results/machine-start.txt` shows 54.5% CPU busy over a 3 second sample before the first run, `machine-end.txt` shows 48% after the last; `machine-start-server-pass.txt` shows 25.6% before the second pass. Docker had 9 other containers running at the start, which were idle when I checked, and 19 at the end. So treat the seconds as one noisy machine's numbers, not as a benchmark of the model.

Seconds per summary, measured around the whole `diffsum` call (container start included):

| diff size (commits) | prompt tokens | one-shot | server | server saves |
|---|---|---|---|---|
| under 2 KB (4) | 288 to 504 | 19.7 s (15.6 to 23.8) | 12.3 s (9.4 to 15.1) | 7.4 s |
| 5 to 9 KB (3) | 1897 to 2666 | 47.4 s (37.1 to 51.1) | 40.0 s (32.1 to 42.1) | 7.3 s |
| 21 KB (1) | 7241 | 122.0 s (118.4 to 134.9) | 111.0 s (109.0 to 113.7) | 11.0 s |
| cut at 24 KB (2) | 7693 and 7729 | 126.0 s (115.8 to 135.3) | 127.0 s (108.1 to 131.7) | -0.9 s |

"Saves" is the difference of the two medians. The server saved about 7 s on the smaller diffs, more than the 3.15 s model load (2.60 to 3.68 over the 50 one-shot runs), and nothing on the cut ones. I did not isolate why. The two modes ran at different times on a busy machine, and server runs also generated tokens faster (14.1 against 10.7 per second), so part of the gap may be load rather than the model staying resident.

Throughput: prompt evaluation ran at 78.0 tokens/s one-shot (65.8 to 90.4) and 86.6 tokens/s in server mode (67.2 to 93.7). Generation ran at 10.7 tokens/s one-shot (5.8 to 13.1) and 14.1 in server mode (7.2 to 16.8). Prompt evaluation dominates: the largest prompts spend about 100 of their 120 seconds reading the diff. The server does not report time to first token, so the CSV column `ttft_s` is prompt evaluation time plus the average time of one generated token. It comes to 5.1 s for the small diffs and 106 s for the cut ones.

Memory: the model process peaked at 2103 MiB resident one-shot (2027 to 2371) and 2449 MiB in server mode (2156 to 2701), measured as VmHWM. In server mode that is the high-water mark over everything the server had served so far. I also record the container's cgroup `memory.peak`, but it is not a good number here: the weights are memory-mapped, so the page cache is charged to whichever container touched it first, and the one-shot figure (454 MiB) is far below the process size.

Determinism: all 50 one-shot outputs and all 50 server outputs matched the first run of their commit byte for byte, and the two modes gave the same text for all 10 commits. That holds for this machine, this image and these settings. I did not test other thread counts or CPUs.

Images (`bench/results/image-sizes.txt`): the model image is 3.54 GB and the tool image 3.57 GB by `docker image inspect`; they share the model layers, though `docker images` lists each at about 7.4 GB. The tool image built from scratch with `--no-cache` on top of the cached model image in 52.6, 36.1 and 31.6 s (`bench/results/build-times.csv`). The first run was the slowest and I do not know whether that was the network or the apt cache; the server container was up and idle during these builds.

## What the summaries look like

I compared the summaries of five small and medium commits with their subject lines (`bench/results/quality-samples.txt`). Most are accurate but wordy. One good, for `docs(help): pattern is mandatory for path`:

    This change modifies the documentation for the `path` field within the `Opts`
    struct in the `src/cli.rs` file. Specifically, it updates the help text for
    the `path` argument to clarify that if a value is supplied, the pattern
    must come first. This improves the clarity of the command-line interface
    documentation for users of the CLI.

One weak, for `fix: point cargo-binstall at the fd release asset`. The diff swaps `{ name }` for `fd` in a URL template and adds a changelog line. The summary gets the files right and the substitution backwards:

    This change updates the changelog and the Cargo.toml file to fix an issue
    with the release URL for the `cargo binstall` command. Specifically,
    it corrects the package URL format to correctly name the crate as `fd-v{
    version }-{ target }.{ archive-format }` instead of using the crate name
    in the original format. This adjustment ensures that the `cargo binstall`
    command correctly points to the release files for the `fd` binary.

I did not score the summaries; five commits is only enough to see the style.

## Limits

It is slow. On this CPU a 24 KB diff takes about two minutes, nearly all of it prompt evaluation, so the PR workflow suits a self-hosted runner and not a quick check. Generation is 11 to 14 tokens per second.

The byte budget keeps the first files in diff order and only names the rest, so for a big change the summary describes the beginning of it. The prompt tells the model about the cut, but the model does not always say so. It only sees the diff, not the commit message or the surrounding code, and a 2B-class model sometimes gets the direction of a change wrong, as in the weak sample above.

I measured one repository on one Windows machine, and I only ran the wrapper from Git Bash. Dependency lockfiles are skipped by file name, so a lockfile with an unusual name would eat budget. The example PR workflow was written but I have not run it on GitHub, and the CI workflow in `.github/workflows/` has not run there either; I ran its commands by hand.
