#!/bin/bash
# End-to-end install.sh + uninstall.sh against real GitHub.
# Gated by ROCUP_TEST_NETWORK=1.
source "$(dirname "$0")/../common/lib.sh"

if [ "${ROCUP_TEST_NETWORK:-0}" != "1" ]; then
    echo "SKIP: 12-install-uninstall.sh (ROCUP_TEST_NETWORK!=1)"
    exit 0
fi

setup_test_env

# Drive install.sh against this branch's working tree by setting ROCUP_BRANCH
# to whatever's in $GITHUB_HEAD_REF / current checkout. For local runs this
# tests against main; in CI it tests the PR's branch via the actions/checkout
# default ref. To be deterministic, point ROCUP_REPO/ROCUP_BRANCH at the
# current repo + branch.
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
# In CI's detached-HEAD checkout, prefer GITHUB_HEAD_REF or fall back to GITHUB_SHA.
if [ "$branch" = "HEAD" ]; then
    branch="${GITHUB_HEAD_REF:-${GITHUB_SHA:-main}}"
fi
remote_url=$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null || echo "")
# Convert https://github.com/owner/repo.git to owner/repo.
repo_slug=$(echo "$remote_url" | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$|\1|')
[ -n "$repo_slug" ] || repo_slug="imclerran/rocup"

# Run installer in an isolated dir. ROCUP_PREFIX overrides /usr/local/bin so
# no sudo is required.
log="$TEST_TMPDIR/install.log"
ROCUP_REPO="$repo_slug" ROCUP_BRANCH="$branch" ROCUP_ASSUME_YES=1 \
    sh "$repo_root/install.sh" > "$log" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "FAIL: install.sh exited $rc. Log:" >&2
    cat "$log" >&2
    exit 1
fi

# Expected post-install state.
[ -x "$ROCUP_HOME/rocup" ] || { echo "FAIL: rocup script not installed at $ROCUP_HOME/rocup" >&2; exit 1; }
[ -L "$ROCUP_HOME/roc" ]   || { echo "FAIL: active-version symlink missing" >&2; exit 1; }
[ -L "$ROCUP_PREFIX/rocup" ] || { echo "FAIL: $ROCUP_PREFIX/rocup symlink missing" >&2; exit 1; }
[ -L "$ROCUP_PREFIX/roc" ]   || { echo "FAIL: $ROCUP_PREFIX/roc symlink missing" >&2; exit 1; }
# roc_language_server is installed as a real shim script (not a symlink).
[ -f "$ROCUP_PREFIX/roc_language_server" ] || { echo "FAIL: roc_language_server shim missing" >&2; exit 1; }

# Now run uninstall.sh with assume-yes.
ulog="$TEST_TMPDIR/uninstall.log"
ROCUP_HOME="$ROCUP_HOME" ROCUP_PREFIX="$ROCUP_PREFIX" ROCUP_ASSUME_YES=1 \
    sh "$repo_root/uninstall.sh" > "$ulog" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "FAIL: uninstall.sh exited $rc. Log:" >&2
    cat "$ulog" >&2
    exit 1
fi

# Expected post-uninstall state.
[ ! -d "$ROCUP_HOME" ] || { echo "FAIL: $ROCUP_HOME still exists after uninstall" >&2; exit 1; }
[ ! -L "$ROCUP_PREFIX/rocup" ] || { echo "FAIL: $ROCUP_PREFIX/rocup symlink survived" >&2; exit 1; }
[ ! -L "$ROCUP_PREFIX/roc" ]   || { echo "FAIL: $ROCUP_PREFIX/roc symlink survived" >&2; exit 1; }
[ ! -f "$ROCUP_PREFIX/roc_language_server" ] || { echo "FAIL: roc_language_server shim survived" >&2; exit 1; }

pass
