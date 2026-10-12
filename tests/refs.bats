load helper

setup() {
    setup_repo
    use_stub_model
}

change() {
    "$scripts/get_change.sh" "$demo" "$@"
}

@test "two refs resolve to their commits" {
    run change --base c1 --head c2
    [ "$status" -eq 0 ]
    [[ "$output" == *"base_sha=$(git -C "$demo" rev-parse c1)"* ]]
    [[ "$output" == *"head_sha=$(git -C "$demo" rev-parse c2)"* ]]
}

@test "head defaults to HEAD" {
    run change --base c1
    [[ "$output" == *"head_sha=$(git -C "$demo" rev-parse HEAD)"* ]]
}

@test "a commit is compared with its first parent" {
    run change --commit c2
    [[ "$output" == *"base_sha=$(git -C "$demo" rev-parse c1)"* ]]
    [[ "$output" == *"head_sha=$(git -C "$demo" rev-parse c2)"* ]]
}

@test "a root commit is compared with the empty tree" {
    run change --commit c1
    [ "$status" -eq 0 ]
    [[ "$output" == *"base_label=(empty tree)"* ]]
    run summarize --commit c1 --format json
    [ "$(jq .files_changed <<<"$output")" = 2 ]
}

@test "--merge-base compares a branch with the point it forked at" {
    run change --base main --head feature --merge-base
    [[ "$output" == *"base_sha=$(git -C "$demo" rev-parse c1)"* ]]
    run summarize --base main --head feature --merge-base --format json
    # only NOTES.md was added on the branch; c2's changes to main are not counted
    [ "$(jq .files_changed <<<"$output")" = 1 ]
}

@test "without --merge-base the branch is compared with main's tip" {
    run summarize --base main --head feature --format json
    [ "$(jq .files_changed <<<"$output")" -gt 1 ]
}

@test "an unknown ref is an error that names the ref" {
    run change --base nope --head c2
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown ref: nope"* ]]
}

@test "a missing base is an error" {
    run change --head c2
    [ "$status" -ne 0 ]
    [[ "$output" == *"--base"* ]]
}

@test "--commit and --base together are refused" {
    run change --commit c2 --base c1
    [ "$status" -ne 0 ]
}

@test "a directory that is not a repository is refused" {
    mkdir "$BATS_TEST_TMPDIR/plain"
    run "$scripts/get_change.sh" "$BATS_TEST_TMPDIR/plain" --commit HEAD
    [ "$status" -ne 0 ]
}

@test "a cloned URL finds a branch by its bare name" {
    export DIFFSUM_WORKDIR=$BATS_TEST_TMPDIR/work
    mkdir -p "$DIFFSUM_WORKDIR"
    run "$scripts/get_change.sh" "file://$demo" --base main --head feature --merge-base
    [ "$status" -eq 0 ]
    [[ "$output" == *"head_sha=$(git -C "$demo" rev-parse feature)"* ]]
    [[ "$output" == *"base_sha=$(git -C "$demo" rev-parse c1)"* ]]
}

@test "identical refs report no changes without calling the model" {
    export LLAMAFILE=/nonexistent
    run summarize --base c2 --head c2
    [ "$status" -eq 0 ]
    [[ "$output" == "No changes between c2 and c2." ]]
}
