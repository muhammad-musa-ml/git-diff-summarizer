#!/usr/bin/env bash
# Builds a small repository with a known history under the directory given as
# $1. Used by the tests and for manual runs. Prints nothing.
#
#   c1  add app.py and README.md
#   c2  change app.py, add a lockfile and a binary file
#   main points at c2; branch "feature" forks from c1 with one commit (c3),
#   so merge-base(main, feature) is c1
set -euo pipefail

dir=$1
mkdir -p "$dir"
cd "$dir"
git init -q -b main
git config core.autocrlf false
git config user.name tester
git config user.email tester@example.com
git config commit.gpgsign false

cat >app.py <<'EOF'
def greet(name):
    return "hello " + name


def main():
    print(greet("world"))
EOF
printf '# demo\n' >README.md
git add -A
git commit -q -m c1
git tag c1

cat >app.py <<'EOF'
def greet(name, punctuation="!"):
    return "hello " + name + punctuation


def main():
    print(greet("world"))
    print(greet("again", "?"))
EOF
printf '{"lockfileVersion": 3}\n' >package-lock.json
head -c 64 /dev/zero >blob.bin
git add -A
git commit -q -m c2
git tag c2

git checkout -q -b feature c1
printf 'extra notes\n' >NOTES.md
git add -A
git commit -q -m c3
git tag c3
git checkout -q main
