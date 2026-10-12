repo_root=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
scripts=$repo_root/scripts

setup_repo() {
    demo=$BATS_TEST_TMPDIR/demo
    bash "$BATS_TEST_DIRNAME/mkrepo.sh" "$demo" >/dev/null 2>&1
}

use_stub_model() {
    export LLAMAFILE=$BATS_TEST_DIRNAME/stub/llamafile
    export MODEL_GGUF=/dev/null
    export DIFFSUM_MODEL_NAME=stub
}

# Runs summarize.sh against the demo repo; extra arguments pass through.
summarize() {
    "$scripts/summarize.sh" --repo "$demo" "$@"
}

# Builds a prompt for two refs of the demo repo into $BATS_TEST_TMPDIR/prompt.
make_prompt() {
    local base=$1 head=$2 max=${3:-24000}
    base=$(git -C "$demo" rev-parse "$base^{commit}")
    head=$(git -C "$demo" rev-parse "$head^{commit}")
    "$scripts/gen_prompt.sh" "$demo" "$base" "$head" "$max" \
        "$BATS_TEST_TMPDIR/prompt" "$BATS_TEST_TMPDIR/stats"
}

stat_value() {
    sed -n "s/^$1=//p" "$BATS_TEST_TMPDIR/stats"
}
