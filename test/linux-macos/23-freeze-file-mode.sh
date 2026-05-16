#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# File-mode registration: register a single roc binary (not its parent dir).
# A roc_language_server sitting next to it must NOT be copied — the user
# only registered the binary.
src_dir="$TEST_TMPDIR/src"
mkdir -p "$src_dir"
cat > "$src_dir/roc" <<'EOF'
#!/bin/sh
echo "roc"
EOF
chmod +x "$src_dir/roc"
cat > "$src_dir/roc_language_server" <<'EOF'
#!/bin/sh
echo "ls"
EOF
chmod +x "$src_dir/roc_language_server"

"$ROCUP" "$src_dir/roc" >/dev/null 2>&1

# Sanity: active is a local-* whose roc resolves to the file.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
case "$active" in local-*) ;; *) echo "FAIL: expected local-*, got $active" >&2; exit 1 ;; esac
[ -L "$ROCUP_HOME/$active/roc" ] || { echo "FAIL: expected file-mode wrapper dir" >&2; exit 1; }

"$ROCUP" freeze fm >/dev/null

[ -f "$ROCUP_HOME/frozen-fm/roc" ]                  || { echo "FAIL: roc missing" >&2; exit 1; }
[ -L "$ROCUP_HOME/frozen-fm/roc" ]                  && { echo "FAIL: roc is a symlink" >&2; exit 1; }
[ -e "$ROCUP_HOME/frozen-fm/roc_language_server" ]  && { echo "FAIL: LS should not be copied for file-mode" >&2; exit 1; }

# Source binary gone — frozen copy still works.
rm -rf "$src_dir"
output=$("$ROCUP_HOME/frozen-fm/roc")
assert_eq "roc" "$output" "frozen file-mode roc survives source removal"

pass
