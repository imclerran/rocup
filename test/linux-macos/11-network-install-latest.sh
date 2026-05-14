#!/bin/bash
# Network test: rocup latest against real GitHub, end-to-end including
# real binary execution. Gated by ROCUP_TEST_NETWORK=1 so it's skipped
# locally for offline devs but always-on in CI.
source "$(dirname "$0")/../common/lib.sh"

if [ "${ROCUP_TEST_NETWORK:-0}" != "1" ]; then
    echo "SKIP: 11-network-install-latest.sh (ROCUP_TEST_NETWORK!=1)"
    exit 0
fi

setup_test_env

# Run 'rocup latest' against the real GitHub API.
# Output goes to a log file so we can inspect on failure without spamming CI.
log="$TEST_TMPDIR/rocup-latest.log"
if ! "$ROCUP" latest > "$log" 2>&1; then
    echo "FAIL: 'rocup latest' exited non-zero. Log:" >&2
    cat "$log" >&2
    exit 1
fi

# A roc_nightly-* dir should exist now.
nightly_dir=$(find "$ROCUP_HOME" -maxdepth 1 -type d -name 'roc_nightly-*' -print -quit)
[ -n "$nightly_dir" ] || { echo "FAIL: no roc_nightly-* dir after install" >&2; cat "$log" >&2; exit 1; }

# The roc binary inside should be executable.
[ -x "$nightly_dir/roc" ] || { echo "FAIL: $nightly_dir/roc not executable" >&2; exit 1; }

# The active-version symlink should point at it.
active=$(readlink "$ROCUP_HOME/roc")
assert_eq "$nightly_dir" "$active" "active symlink points at installed nightly"

# 'roc --version' should run and report a hash that matches the dir name.
roc_version=$("$ROCUP_HOME/roc/roc" --version 2>&1) || { echo "FAIL: roc --version failed" >&2; echo "$roc_version" >&2; exit 1; }
expected_hash=$(basename "$nightly_dir" | grep -oE '[0-9a-f]{7}$')
# 'roc --version' typically reports the 8-char form; first 7 should match.
assert_contains "$roc_version" "$expected_hash" "roc --version reports installed hash"

pass
