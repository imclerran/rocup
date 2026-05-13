#!/bin/bash
# Hermetic uninstall.sh test: sets up a fake rocup install, runs uninstall,
# verifies (a) the rocup-owned symlinks in $ROCUP_PREFIX are removed,
# (b) unrelated symlinks in $ROCUP_PREFIX survive,
# (c) $ROCUP_HOME is deleted,
# (d) source directories behind local-* symlinks are NOT followed.
# No network required.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME/roc-alpha4-rolling"
mkdir -p "$ROCUP_HOME/roc_nightly-2025-10-25-abc1234"
ln -sfn "$ROCUP_HOME/roc-alpha4-rolling" "$ROCUP_HOME/roc"

# Fake the script + prefix symlinks the installer would have created.
touch "$ROCUP_HOME/rocup"
ln -sf "$ROCUP_HOME/rocup" "$ROCUP_PREFIX/rocup"
ln -sf "$ROCUP_HOME/roc/roc" "$ROCUP_PREFIX/roc"
# LS shim is a real file with ROCUP_HOME mentioned in it.
printf '#!/bin/sh\n# Installed by rocup.\nROCUP_HOME=...\n' > "$ROCUP_PREFIX/roc_language_server"
chmod +x "$ROCUP_PREFIX/roc_language_server"

# A local-<hash> symlink pointing OUTSIDE $ROCUP_HOME. Must not be followed
# during uninstall.
user_build="$TEST_TMPDIR/user-roc-build"
mkdir -p "$user_build"
touch "$user_build/roc"
ln -sfn "$user_build" "$ROCUP_HOME/local-abcdef0"

# An unrelated symlink in $ROCUP_PREFIX. Must survive.
mkdir -p "$TEST_TMPDIR/elsewhere"
touch "$TEST_TMPDIR/elsewhere/some-other-tool"
ln -sf "$TEST_TMPDIR/elsewhere/some-other-tool" "$ROCUP_PREFIX/some-other-tool"

# Run uninstall.
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
ROCUP_ASSUME_YES=1 sh "$repo_root/uninstall.sh" >/dev/null 2>&1

# Assert post-state.
[ ! -d "$ROCUP_HOME" ] || { echo "FAIL: $ROCUP_HOME survived" >&2; exit 1; }
[ -f "$user_build/roc" ] || { echo "FAIL: local-* target was followed and deleted" >&2; exit 1; }
[ ! -L "$ROCUP_PREFIX/rocup" ] || { echo "FAIL: rocup symlink survived" >&2; exit 1; }
[ ! -L "$ROCUP_PREFIX/roc" ]   || { echo "FAIL: roc symlink survived" >&2; exit 1; }
[ ! -f "$ROCUP_PREFIX/roc_language_server" ] || { echo "FAIL: LS shim survived" >&2; exit 1; }
[ -L "$ROCUP_PREFIX/some-other-tool" ] || { echo "FAIL: unrelated symlink was removed" >&2; exit 1; }

pass
