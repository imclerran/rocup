#!/bin/bash
# Offline: $ROCUP_HOME/bin links, the PATH note, and cleanup of entries an older
# install left in /usr/local/bin (redirected to a temp dir via ROCUP_LEGACY_BIN).
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

build="$TEST_TMPDIR/build"
mkdir -p "$build"
printf '#!/bin/sh\necho "local roc"\n' > "$build/roc"
chmod +x "$build/roc"
bin="$ROCUP_HOME/bin"

out=$("$ROCUP" "$build" 2>&1)
[ -L "$bin/rocup" ] && [ -x "$bin/rocup" ] || { echo "FAIL: $bin/rocup link missing" >&2; exit 1; }
assert_eq "$ROCUP_HOME/roc/roc" "$(readlink "$bin/roc")" 'bin/roc points at the active roc'
[ -f "$bin/roc_language_server" ] && [ -x "$bin/roc_language_server" ] || { echo "FAIL: LS shim missing" >&2; exit 1; }
assert_eq "local roc" "$("$bin/roc")" 'roc runs through the bin link'
assert_contains "$out" "is not on your PATH" 'PATH note when bin dir is not on PATH'

out=$(PATH="$bin:$PATH" "$ROCUP" local 2>&1)
! printf '%s' "$out" | grep -q "is not on your PATH" || { echo "FAIL: PATH note shown although bin dir is on PATH" >&2; exit 1; }

# Entries from an older install, plus one unrelated entry.
ln -sf "$ROCUP_HOME/rocup" "$ROCUP_LEGACY_BIN/rocup"
ln -sf "$ROCUP_HOME/roc/roc" "$ROCUP_LEGACY_BIN/roc"
printf '#!/bin/sh\nROCUP_HOME=${ROCUP_HOME:-x}\n' > "$ROCUP_LEGACY_BIN/roc_language_server"
ln -sf "$build/roc" "$ROCUP_LEGACY_BIN/other-tool"

# Decline: entries stay, a marker is written, and later runs stay quiet.
out=$(echo n | ROCUP_ASSUME_YES=0 "$ROCUP" local 2>&1)
assert_contains "$out" "older install" 'legacy cleanup offered'
[ -L "$ROCUP_LEGACY_BIN/roc" ] || { echo "FAIL: legacy roc removed after declining" >&2; exit 1; }
[ -e "$ROCUP_HOME/.keep-legacy-links" ] || { echo "FAIL: decline marker not written" >&2; exit 1; }
out=$(echo n | ROCUP_ASSUME_YES=0 "$ROCUP" local 2>&1)
! printf '%s' "$out" | grep -q "older install" || { echo "FAIL: offered again after declining" >&2; exit 1; }

# Accept: rocup-owned entries go, the unrelated one stays.
rm "$ROCUP_HOME/.keep-legacy-links"
"$ROCUP" local >/dev/null 2>&1
for n in rocup roc roc_language_server; do
    [ ! -L "$ROCUP_LEGACY_BIN/$n" ] && [ ! -f "$ROCUP_LEGACY_BIN/$n" ] \
        || { echo "FAIL: legacy $n survived" >&2; exit 1; }
done
[ -L "$ROCUP_LEGACY_BIN/other-tool" ] || { echo "FAIL: unrelated entry removed" >&2; exit 1; }

pass
