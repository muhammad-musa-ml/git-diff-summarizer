# Reads a unified git diff on stdin and writes at most `budget` bytes of it to
# stdout, always cutting at a line boundary. Whole files are kept in order; a
# file that does not fit is cut short, and everything after it is only listed.
# Binary files and lockfiles/minified assets are dropped. Side facts go to
# `meta` as tab separated records: skipped, omitted, truncated.
#
# Run with LC_ALL=C so length() counts bytes.

function flush(    n, i, room) {
    if (nlines == 0)
        return
    if (skip != "") {
        print "skipped\t" path "\t" skip > meta
    } else if (full) {
        print "omitted\t" path > meta
    } else if (used + size <= budget) {
        for (i = 1; i <= nlines; i++)
            print buf[i]
        used += size
    } else {
        room = budget - used
        for (i = 1; i <= nlines; i++) {
            n = length(buf[i]) + 1
            if (n > room)
                break
            print buf[i]
            room -= n
            used += n
        }
        full = 1
        print "truncated\t" path > meta
    }
    nlines = 0
    size = 0
    skip = ""
}

function lockfile(p,    base) {
    base = p
    sub(/.*\//, "", base)
    return base ~ /^(package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|go\.sum|poetry\.lock|Pipfile\.lock|Gemfile\.lock|composer\.lock|mix\.lock|flake\.lock|uv\.lock)$/
}

BEGIN {
    if (budget == "" || meta == "") {
        print "filter_diff.awk: budget and meta are required" > "/dev/stderr"
        exit 2
    }
}

/^diff --git / {
    flush()
    path = $0
    sub(/^diff --git a\/.* b\//, "", path)
    if (lockfile(path))
        skip = "lockfile"
    else if (path ~ /\.(min\.js|min\.css|map)$/)
        skip = "generated"
}

{
    nlines++
    buf[nlines] = $0
    size += length($0) + 1
    if ($0 ~ /^Binary files .* differ$/ || $0 ~ /^GIT binary patch$/)
        skip = "binary"
}

END { flush() }
