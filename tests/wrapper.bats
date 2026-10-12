load helper

# Only the parts of the wrapper that do not need Docker.

@test "help exits cleanly and lists the commands" {
    run "$repo_root/diffsum" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"diffsum serve"* ]]
    [[ "$output" == *"--merge-base"* ]]
}

@test "an unknown option is a usage error" {
    run "$repo_root/diffsum" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage:"* ]]
}
