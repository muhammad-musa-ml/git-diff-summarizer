#!/usr/bin/env bash
# Resolves what to summarize. Prints key=value lines on stdout:
#   repo_dir, base_sha, head_sha, base_label, head_label
# Usage: get_change.sh SRC [--base REF] [--head REF] [--commit REF] [--merge-base]
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

src=$1
shift
base='' head=HEAD commit='' use_merge_base=0
while [ $# -gt 0 ]; do
    case $1 in
    --base) base=$2; shift 2 ;;
    --head) head=$2; shift 2 ;;
    --commit) commit=$2; shift 2 ;;
    --merge-base) use_merge_base=1; shift ;;
    *) die "get_change: unknown option $1" ;;
    esac
done

trust_all_repos

if [ -d "$src" ]; then
    repo=$src
else
    repo=${DIFFSUM_WORKDIR:?DIFFSUM_WORKDIR must be set}/clone
    # No checkout: a diff only needs commits and trees, and the blobs it
    # touches are fetched on demand.
    git clone --quiet --no-checkout --filter=blob:none "$src" "$repo" 2>/dev/null ||
        git clone --quiet --no-checkout "$src" "$repo" ||
        die "could not clone $src"
fi

git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "$src is not a git repository"

# A bare branch name only exists as origin/<name> in a fresh clone.
resolve() {
    local ref=$1 sha
    for cand in "$ref" "origin/$ref"; do
        if sha=$(git -C "$repo" rev-parse --verify --quiet "$cand^{commit}"); then
            echo "$sha"
            return
        fi
    done
    die "unknown ref: $ref"
}

if [ -n "$commit" ]; then
    [ -z "$base" ] || die "--commit cannot be combined with --base"
    head_sha=$(resolve "$commit")
    head=$commit
    if base_sha=$(git -C "$repo" rev-parse --verify --quiet "$head_sha^1^{commit}"); then
        base="$commit^"
    else
        # A root commit is compared against the empty tree.
        base_sha=$(git -C "$repo" hash-object -t tree /dev/null)
        base="(empty tree)"
    fi
else
    [ -n "$base" ] || die "give --base REF or --commit REF"
    head_sha=$(resolve "$head")
    base_sha=$(resolve "$base")
    if [ "$use_merge_base" = 1 ]; then
        base_sha=$(git -C "$repo" merge-base "$base_sha" "$head_sha") ||
            die "no merge base between $base and $head"
        base="merge-base($base, $head)"
    fi
fi

printf 'repo_dir=%s\nbase_sha=%s\nhead_sha=%s\nbase_label=%s\nhead_label=%s\n' \
    "$repo" "$base_sha" "$head_sha" "$base" "$head"
