#!/bin/bash
# Hermetic uninstall.sh test: fakes an install (bin links, legacy /usr/local/bin
# entries, a profile PATH line), runs uninstall, and verifies rocup-owned things
# go while everything else stays. No network required.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME/roc-alpha4-rolling" "$ROCUP_HOME/roc_nightly-2025-10-25-abc1234" "$ROCUP_HOME/bin"
ln -sfn "$ROCUP_HOME/roc-alpha4-rolling" "$ROCUP_HOME/roc"
touch "$ROCUP_HOME/rocup"
ln -sf "$ROCUP_HOME/rocup" "$ROCUP_HOME/bin/rocup"
ln -sf "$ROCUP_HOME/roc/roc" "$ROCUP_HOME/bin/roc"

# Entries an older install left in /usr/local/bin (redirected to a temp dir).
ln -sf "$ROCUP_HOME/rocup" "$ROCUP_LEGACY_BIN/rocup"
ln -sf "$ROCUP_HOME/roc/roc" "$ROCUP_LEGACY_BIN/roc"
# LS shim is a real file with ROCUP_HOME mentioned in it.
printf '#!/bin/sh\n# Installed by rocup.\nROCUP_HOME=...\n' > "$ROCUP_LEGACY_BIN/roc_language_server"
chmod +x "$ROCUP_LEGACY_BIN/roc_language_server"
# An unrelated entry there. Must survive.
mkdir -p "$TEST_TMPDIR/elsewhere"
touch "$TEST_TMPDIR/elsewhere/some-other-tool"
ln -sf "$TEST_TMPDIR/elsewhere/some-other-tool" "$ROCUP_LEGACY_BIN/some-other-tool"

# A local-<hash> symlink pointing OUTSIDE $ROCUP_HOME. Must not be followed
# during uninstall.
user_build="$TEST_TMPDIR/user-roc-build"
mkdir -p "$user_build"
touch "$user_build/roc"
ln -sfn "$user_build" "$ROCUP_HOME/local-abcdef0"

# A profile holding the installer's PATH line among unrelated lines.
fake_home="$TEST_TMPDIR/home"
mkdir -p "$fake_home"
printf 'alias ll="ls -l"\n\n# rocup\nexport PATH="%s/bin:$PATH"\nexport EDITOR=vi\n' "$ROCUP_HOME" > "$fake_home/.bashrc"

# Run uninstall.
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
HOME="$fake_home" ROCUP_ASSUME_YES=1 sh "$repo_root/uninstall.sh" >/dev/null 2>&1

# Assert post-state.
[ ! -d "$ROCUP_HOME" ] || { echo "FAIL: $ROCUP_HOME survived" >&2; exit 1; }
[ -f "$user_build/roc" ] || { echo "FAIL: local-* target was followed and deleted" >&2; exit 1; }
for n in rocup roc roc_language_server; do
    [ ! -L "$ROCUP_LEGACY_BIN/$n" ] && [ ! -f "$ROCUP_LEGACY_BIN/$n" ] \
        || { echo "FAIL: legacy $n survived" >&2; exit 1; }
done
[ -L "$ROCUP_LEGACY_BIN/some-other-tool" ] || { echo "FAIL: unrelated entry was removed" >&2; exit 1; }
! grep -q rocup "$fake_home/.bashrc" || { echo "FAIL: PATH line or marker survived" >&2; cat "$fake_home/.bashrc" >&2; exit 1; }
grep -Fxq 'alias ll="ls -l"' "$fake_home/.bashrc" && grep -Fxq 'export EDITOR=vi' "$fake_home/.bashrc" \
    || { echo "FAIL: unrelated profile lines were changed" >&2; cat "$fake_home/.bashrc" >&2; exit 1; }

pass
