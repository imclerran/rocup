#!/bin/bash
# Common test helpers for rocup bash test suite. Source from each test:
#   source "$(dirname "$0")/../common/lib.sh"

set -euo pipefail

# Each test runs with an isolated $ROCUP_HOME under $TEST_TMPDIR.
# Cleanup happens via trap.
setup_test_env() {
    # On Git Bash for Windows, ln -s falls back to copying without this set.
    # The bash rocup script and these tests both need real symlinks to
    # readlink correctly. No-op on Linux/macOS where the variable is unused.
    # Requires Developer Mode or admin on Windows; otherwise ln still falls back.
    export MSYS=winsymlinks:nativestrict
    # Tests are non-interactive; auto-confirm prefix symlink writes.
    export ROCUP_ASSUME_YES=1
    # Strip any trailing slash from TMPDIR before composing the mktemp template,
    # otherwise macOS produces paths with a literal '//' segment that won't match
    # the canonical form readlink returns later.
    local _tmpdir="${TMPDIR:-/tmp}"
    _tmpdir="${_tmpdir%/}"
    TEST_TMPDIR=$(mktemp -d "$_tmpdir/rocup-test.XXXXXX")
    export TEST_TMPDIR
    export ROCUP_HOME="$TEST_TMPDIR/rocup-home"
    export ROCUP_PREFIX="$TEST_TMPDIR/prefix"
    mkdir -p "$ROCUP_PREFIX"
    # Path to the rocup script under test. Each test must set ROCUP before
    # sourcing this file, or rely on this default (the repo's rocup at root).
    ROCUP="${ROCUP:-$(cd "$(dirname "$0")/../.." && pwd)/rocup}"
    trap 'cleanup_test_env' EXIT
}

cleanup_test_env() {
    if [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# assert_eq <expected> <actual> [message]
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: ${msg:-assert_eq}" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        exit 1
    fi
}

# assert_exit_code <expected-code> <message> -- <command...>
assert_exit_code() {
    local expected="$1" msg="$2"
    shift 2
    if [ "$1" = "--" ]; then shift; fi
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne "$expected" ]; then
        echo "FAIL: $msg (expected exit $expected, got $rc)" >&2
        exit 1
    fi
}

# assert_contains <haystack> <needle> [message]
assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if ! printf '%s' "$haystack" | grep -qF "$needle"; then
        echo "FAIL: ${msg:-assert_contains}" >&2
        echo "  haystack: $haystack" >&2
        echo "  needle:   $needle" >&2
        exit 1
    fi
}

pass() {
    echo "PASS: $(basename "$0")"
}

# make_fake_nightly <date YYYY-MM-DD> <hash> — creates a fake nightly dir
# with a dummy executable 'roc' so activate logic finds it.
make_fake_nightly() {
    local date_ymd="$1" hash="$2"
    local dir="$ROCUP_HOME/roc_nightly-${date_ymd}-${hash}"
    mkdir -p "$dir"
    cat > "$dir/roc" <<'EOF'
#!/bin/sh
echo "fake roc, version $(basename $(dirname $0))"
EOF
    chmod +x "$dir/roc"
    echo "$dir"
}

# activate_fake <dir-name>
activate_fake() {
    local name="$1"
    ln -sfn "$ROCUP_HOME/$name" "$ROCUP_HOME/roc"
}

# make_fake_alpha4 — creates a fake alpha4 dir
make_fake_alpha4() {
    local dir="$ROCUP_HOME/roc-alpha4-rolling"
    mkdir -p "$dir"
    cat > "$dir/roc" <<'EOF'
#!/bin/sh
echo "fake alpha4 roc"
EOF
    chmod +x "$dir/roc"
    echo "$dir"
}
