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

# In CI, a fork PR checks out the base repo but the branch lives on the fork.
if [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ] && command -v jq >/dev/null 2>&1; then
    head_repo=$(jq -r '.pull_request.head.repo.full_name // empty' "$GITHUB_EVENT_PATH")
    [ -z "$head_repo" ] || repo_slug="$head_repo"
fi

# A throwaway HOME so the installer's profile edit lands in the sandbox.
# ROCUP_HOME is set explicitly, so HOME only decides where the profile lives.
fake_home="$TEST_TMPDIR/home"
mkdir -p "$fake_home"
bin="$ROCUP_HOME/bin"

log="$TEST_TMPDIR/install.log"
rc=0
HOME="$fake_home" SHELL=/bin/zsh ROCUP_NO_MODIFY_PATH= \
    ROCUP_REPO="$repo_slug" ROCUP_BRANCH="$branch" ROCUP_ASSUME_YES=1 \
    sh "$repo_root/install.sh" > "$log" 2>&1 || rc=$?
if [ $rc -ne 0 ]; then
    echo "FAIL: install.sh exited $rc. Log:" >&2
    cat "$log" >&2
    exit 1
fi

# Expected post-install state.
[ -x "$ROCUP_HOME/rocup" ] || { echo "FAIL: rocup script not installed at $ROCUP_HOME/rocup" >&2; exit 1; }
[ -L "$ROCUP_HOME/roc" ]   || { echo "FAIL: active-version symlink missing" >&2; exit 1; }
[ -L "$bin/rocup" ] && [ -x "$bin/rocup" ] || { echo "FAIL: $bin/rocup link missing" >&2; exit 1; }
[ -L "$bin/roc" ] && [ -x "$bin/roc" ]     || { echo "FAIL: $bin/roc link missing" >&2; exit 1; }
# roc_language_server is installed as a real shim script (not a symlink).
[ -f "$bin/roc_language_server" ] || { echo "FAIL: roc_language_server shim missing" >&2; exit 1; }
# Nothing went to the legacy location.
[ -z "$(ls -A "$ROCUP_LEGACY_BIN")" ] || { echo "FAIL: installer wrote to $ROCUP_LEGACY_BIN" >&2; exit 1; }

# The profile for the selected shell gained the PATH line behind its marker,
# and the installer did not print the PATH note itself.
path_line="export PATH=\"$bin:\$PATH\""
grep -Fxq "$path_line" "$fake_home/.zshrc" || { echo "FAIL: PATH line missing from .zshrc" >&2; cat "$fake_home/.zshrc" >&2; exit 1; }
grep -Fxq '# rocup' "$fake_home/.zshrc"    || { echo "FAIL: marker missing from .zshrc" >&2; exit 1; }
! grep -q "is not on your PATH" "$log"      || { echo "FAIL: installer printed the PATH note" >&2; exit 1; }

# Now run uninstall.sh with assume-yes.
ulog="$TEST_TMPDIR/uninstall.log"
rc=0
HOME="$fake_home" ROCUP_HOME="$ROCUP_HOME" ROCUP_ASSUME_YES=1 \
    sh "$repo_root/uninstall.sh" > "$ulog" 2>&1 || rc=$?
if [ $rc -ne 0 ]; then
    echo "FAIL: uninstall.sh exited $rc. Log:" >&2
    cat "$ulog" >&2
    exit 1
fi

# Expected post-uninstall state.
[ ! -d "$ROCUP_HOME" ] || { echo "FAIL: $ROCUP_HOME still exists after uninstall" >&2; exit 1; }
! grep -Fq "$bin" "$fake_home/.zshrc"  || { echo "FAIL: PATH line survived uninstall" >&2; exit 1; }
! grep -Fxq '# rocup' "$fake_home/.zshrc" || { echo "FAIL: marker survived uninstall" >&2; exit 1; }

pass
