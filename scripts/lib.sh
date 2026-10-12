# shellcheck shell=bash
# Sourced by the other scripts.

die() {
    echo "diffsum: $*" >&2
    exit 1
}

# Wall clock in seconds with millisecond resolution.
now() {
    date +%s.%N
}

elapsed() {
    awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b - a }'
}

# Read-only mounts are owned by someone else, so tell git to trust them
# without touching any config file.
trust_all_repos() {
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0=safe.directory
    export GIT_CONFIG_VALUE_0='*'
}
