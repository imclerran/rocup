#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "roc"
EOF
chmod +x "$local_dir/roc"
cat > "$local_dir/roc_language_server" <<'EOF'
#!/bin/sh
echo "ls"
EOF
chmod +x "$local_dir/roc_language_server"
"$ROCUP" "$local_dir" >/dev/null 2>&1
"$ROCUP" freeze with-ls >/dev/null

# Both binaries copied as real files.
[ -f "$ROCUP_HOME/frozen-with-ls/roc" ]                    || { echo "FAIL: roc missing" >&2; exit 1; }
[ -f "$ROCUP_HOME/frozen-with-ls/roc_language_server" ]    || { echo "FAIL: roc_language_server missing" >&2; exit 1; }
[ -L "$ROCUP_HOME/frozen-with-ls/roc_language_server" ]    && { echo "FAIL: ls is a symlink, not a real file" >&2; exit 1; }

# Output check.
ls_out=$("$ROCUP_HOME/frozen-with-ls/roc_language_server")
assert_eq "ls" "$ls_out" "frozen LS runs and matches source"

# Source removed — frozen copies still work.
rm -rf "$local_dir"
ls_out=$("$ROCUP_HOME/frozen-with-ls/roc_language_server")
assert_eq "ls" "$ls_out" "frozen LS survives source removal"

pass
