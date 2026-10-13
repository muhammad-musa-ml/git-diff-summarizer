load helper

setup() {
    setup_repo
    port=$((20000 + RANDOM % 20000))
    python3 "$BATS_TEST_DIRNAME/stub/stub_model.py" --server --port "$port" &
    server_pid=$!
    until curl -sf "http://127.0.0.1:$port/health" >/dev/null; do sleep 0.1; done
    export DIFFSUM_SERVER=http://127.0.0.1:$port
    # proves the one-shot path is not taken
    export LLAMAFILE=/nonexistent
}

teardown() {
    kill "$server_pid" 2>/dev/null || true
}

@test "with a server configured the model is not started" {
    run summarize --commit c2
    [ "$status" -eq 0 ]
    [[ "$output" == "stub summary "* ]]
}

@test "server and one-shot paths give the same summary for the same prompt" {
    via_server=$(summarize --commit c2)
    unset DIFFSUM_SERVER
    use_stub_model
    one_shot=$(summarize --commit c2)
    [ "$via_server" = "$one_shot" ]
}

@test "server mode leaves load_seconds null" {
    run summarize --commit c2 --format json
    [ "$(jq '.model_timings.load_seconds' <<<"$output")" = null ]
}

@test "server mode leaves the model's RSS null" {
    run summarize --commit c2 --format json
    [ "$(jq '.model_timings.peak_rss_bytes' <<<"$output")" = null ]
}

@test "an unreachable server is reported" {
    export DIFFSUM_SERVER=http://127.0.0.1:9
    run summarize --commit c2
    [ "$status" -ne 0 ]
    [[ "$output" == *"model request failed"* ]]
}

@test "requests ask for temperature 0" {
    # the stub answers 400 to anything else, so a changed default would fail here
    run summarize --commit c2
    [ "$status" -eq 0 ]
}
