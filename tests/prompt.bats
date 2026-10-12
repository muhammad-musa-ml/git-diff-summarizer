load helper

setup() {
    setup_repo
}

@test "prompt holds the instruction, the totals and the text diff" {
    make_prompt c1 c2
    run cat "$BATS_TEST_TMPDIR/prompt"
    [[ "$output" == *"Below is the diff of a git change"* ]]
    [[ "$output" == *"<diff>"* ]]
    [[ "$output" == *'+def greet(name, punctuation="!"):'* ]]
    [[ "$output" == *"two to four sentences"* ]]
}

@test "totals count the whole change, filtered files included" {
    make_prompt c1 c2
    [ "$(stat_value files_changed)" = 3 ]
    [ "$(stat_value lines_added)" = 4 ]
    [ "$(stat_value lines_removed)" = 2 ]
    [ "$(stat_value files_skipped)" = 2 ]
}

@test "lockfiles and binary files stay out of the diff and are named in the note" {
    make_prompt c1 c2
    run cat "$BATS_TEST_TMPDIR/prompt"
    [[ "$output" != *"lockfileVersion"* ]]
    [[ "$output" != *"diff --git a/blob.bin"* ]]
    [[ "$output" != *"diff --git a/package-lock.json"* ]]
    [[ "$output" == *"Left out of the diff"*"package-lock.json"* ]]
    [[ "$output" == *"blob.bin"* ]]
}

@test "a small change is not marked truncated" {
    make_prompt c1 c2
    [ "$(stat_value truncated)" = no ]
    run cat "$BATS_TEST_TMPDIR/prompt"
    [[ "$output" != *"The diff was cut"* ]]
}

@test "a tight budget truncates on a line boundary and says so" {
    make_prompt c1 c2 150
    [ "$(stat_value truncated)" = yes ]
    [ "$(stat_value diff_bytes)" -le 150 ]
    run cat "$BATS_TEST_TMPDIR/prompt"
    [[ "$output" == *"The diff was cut at 150 bytes"* ]]
    [[ "$output" == *"Say that the diff was truncated"* ]]
    # the diff block ends with a whole line, not a half one
    last=$(sed -n '/^<diff>$/,/^<\/diff>$/p' "$BATS_TEST_TMPDIR/prompt" | tail -2 | head -1)
    git -C "$demo" diff c1 c2 -- app.py | grep -qxF -- "$last"
}

@test "files that no longer fit are listed by name" {
    git -C "$demo" checkout -q main
    for i in 1 2 3; do seq 1 200 >"$demo/file$i.txt"; done
    git -C "$demo" add -A
    git -C "$demo" commit -q -m many
    make_prompt c2 main 2000
    run cat "$BATS_TEST_TMPDIR/prompt"
    [[ "$output" == *"Files not shown in full:"*"file"* ]]
    [ "$(stat_value diff_bytes)" -le 2000 ]
}

@test "the same change gives a byte-identical prompt" {
    make_prompt c1 c2
    cp "$BATS_TEST_TMPDIR/prompt" "$BATS_TEST_TMPDIR/first"
    make_prompt c1 c2
    cmp "$BATS_TEST_TMPDIR/prompt" "$BATS_TEST_TMPDIR/first"
}

@test "a non-numeric budget is refused" {
    run make_prompt c1 c2 lots
    [ "$status" -ne 0 ]
    [[ "$output" == *"max bytes must be a number"* ]]
}

@test "a zero budget is refused" {
    run make_prompt c1 c2 0
    [ "$status" -ne 0 ]
}
