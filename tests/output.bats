load helper

setup() {
    setup_repo
    use_stub_model
}

@test "text output is the summary, wrapped to 80 columns" {
    run summarize --commit c2
    [ "$status" -eq 0 ]
    [[ "$output" == "stub summary "* ]]
    while IFS= read -r line; do
        [ "${#line}" -le 80 ]
    done <<<"$output"
}

@test "long model output is wrapped" {
    # one 299-character line from the model must come out as several short ones
    export STUB_WORDS=60
    run summarize --commit c2
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 4 ]
    for line in "${lines[@]}"; do
        [ "${#line}" -le 80 ]
    done
}

@test "the same input gives byte-identical text output" {
    summarize --base c1 --head c2 >"$BATS_TEST_TMPDIR/a"
    summarize --base c1 --head c2 >"$BATS_TEST_TMPDIR/b"
    cmp "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"
}

@test "different changes give different summaries" {
    a=$(summarize --commit c2)
    b=$(summarize --commit c3)
    [ "$a" != "$b" ]
}

@test "json output carries the summary and the metadata" {
    run summarize --commit c2 --format json
    [ "$status" -eq 0 ]
    jq -e . <<<"$output" >/dev/null
    [ "$(jq -r .summary <<<"$output")" = "$(summarize --commit c2)" ]
    [ "$(jq -r .model <<<"$output")" = stub ]
    [ "$(jq -r .base <<<"$output")" = "c2^" ]
    [ "$(jq -r .head <<<"$output")" = c2 ]
    [ "$(jq -r .base_sha <<<"$output")" = "$(git -C "$demo" rev-parse c1)" ]
    [ "$(jq .files_changed <<<"$output")" = 3 ]
    [ "$(jq .files_skipped <<<"$output")" = 2 ]
    [ "$(jq .truncated <<<"$output")" = false ]
    jq -e '.lines_added > 0 and .lines_removed > 0' <<<"$output" >/dev/null
    jq -e '(.seconds | type) == "number" and (.prompt_bytes | type) == "number"' <<<"$output" >/dev/null
    jq -e '.model_timings.load_seconds != null' <<<"$output" >/dev/null
    jq -e '.model_timings.peak_rss_bytes > 1000000' <<<"$output" >/dev/null
}

@test "json reports truncation" {
    run summarize --commit c2 --format json --max-bytes 200
    [ "$(jq .truncated <<<"$output")" = true ]
}

@test "json totals are the same whether or not the diff was truncated" {
    full=$(summarize --commit c2 --format json)
    cut=$(summarize --commit c2 --format json --max-bytes 200)
    [ "$(jq .lines_added <<<"$full")" = "$(jq .lines_added <<<"$cut")" ]
}

@test "an unknown format is refused" {
    run summarize --commit c2 --format yaml
    [ "$status" -ne 0 ]
}

@test "an unknown option prints usage and fails" {
    run summarize --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage:"* ]]
}

@test "an empty model reply is an error, not an empty summary" {
    export STUB_WORDS=0
    run summarize --commit c2
    [ "$status" -ne 0 ]
    [[ "$output" == *"returned nothing"* ]]
}
