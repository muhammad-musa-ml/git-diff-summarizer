load helper

# filter_diff.awk gets a hand-written diff so each rule is tested alone.

run_filter() {
    LC_ALL=C awk -v budget="$1" -v meta="$BATS_TEST_TMPDIR/meta" -f "$scripts/filter_diff.awk" \
        <"$BATS_TEST_TMPDIR/in" >"$BATS_TEST_TMPDIR/out"
}

setup() {
    : >"$BATS_TEST_TMPDIR/meta"
    cat >"$BATS_TEST_TMPDIR/in" <<'EOF'
diff --git a/src/a.c b/src/a.c
index 111..222 100644
--- a/src/a.c
+++ b/src/a.c
@@ -1 +1 @@
-int a;
+int b;
diff --git a/sub/yarn.lock b/sub/yarn.lock
index 111..222 100644
--- a/sub/yarn.lock
+++ b/sub/yarn.lock
@@ -1 +1 @@
-x
+y
diff --git a/logo.png b/logo.png
index 111..222 100644
Binary files a/logo.png and b/logo.png differ
diff --git a/web/app.min.js b/web/app.min.js
index 111..222 100644
--- a/web/app.min.js
+++ b/web/app.min.js
@@ -1 +1 @@
-q
+r
diff --git a/lib/my file.c b/lib/my file.c
index 111..222 100644
--- a/lib/my file.c
+++ b/lib/my file.c
@@ -1 +1 @@
-int c;
+int d;
EOF
}

@test "keeps source files and drops lockfiles, binaries and minified assets" {
    run_filter 100000
    grep -q 'diff --git a/src/a.c' "$BATS_TEST_TMPDIR/out"
    grep -q 'diff --git a/lib/my file.c' "$BATS_TEST_TMPDIR/out"
    ! grep -q 'yarn.lock' "$BATS_TEST_TMPDIR/out"
    ! grep -q 'logo.png' "$BATS_TEST_TMPDIR/out"
    ! grep -q 'app.min.js' "$BATS_TEST_TMPDIR/out"
}

@test "records why each file was skipped" {
    run_filter 100000
    grep -qP 'skipped\tsub/yarn.lock\tlockfile' "$BATS_TEST_TMPDIR/meta"
    grep -qP 'skipped\tlogo.png\tbinary' "$BATS_TEST_TMPDIR/meta"
    grep -qP 'skipped\tweb/app.min.js\tgenerated' "$BATS_TEST_TMPDIR/meta"
    ! grep -q '^truncated' "$BATS_TEST_TMPDIR/meta"
}

@test "output never exceeds the budget" {
    for budget in 1 50 120 200 333; do
        : >"$BATS_TEST_TMPDIR/meta"
        run_filter "$budget"
        [ "$(wc -c <"$BATS_TEST_TMPDIR/out")" -le "$budget" ]
    done
}

@test "a file that does not fit is cut and the rest are only listed" {
    run_filter 80
    grep -qP '^truncated\t' "$BATS_TEST_TMPDIR/meta"
    grep -qP '^omitted\t' "$BATS_TEST_TMPDIR/meta"
    # whole lines only
    [ "$(tail -c 1 "$BATS_TEST_TMPDIR/out" | od -An -c | tr -d ' ')" = '\n' ]
}

@test "an empty diff gives empty output" {
    : >"$BATS_TEST_TMPDIR/in"
    run_filter 100
    [ ! -s "$BATS_TEST_TMPDIR/out" ]
}

@test "a missing budget is an error" {
    run awk -f "$scripts/filter_diff.awk" </dev/null
    [ "$status" -ne 0 ]
}

@test "bytes, not characters, are counted" {
    printf 'diff --git a/u.txt b/u.txt\n--- a/u.txt\n+++ b/u.txt\n@@ -1 +1 @@\n-a\n+\xc3\xa9\xc3\xa9\xc3\xa9\xc3\xa9\n' >"$BATS_TEST_TMPDIR/in"
    run_filter 60
    [ "$(wc -c <"$BATS_TEST_TMPDIR/out")" -le 60 ]
}
