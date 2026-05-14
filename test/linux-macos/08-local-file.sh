#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Create a fake local roc binary (file, not dir).
local_dir="$TEST_TMPDIR/binaries"
mkdir -p "$local_dir"
roc_file="$local_dir/my-roc"
cat > "$roc_file" <<'EOF'
#!/bin/sh
echo "local roc file"
EOF
chmod +x "$roc_file"

"$ROCUP" "$roc_file" >/dev/null 2>&1

# Active should be a local-* dir containing a 'roc' symlink to the file.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
case "$active" in
    local-*) ;;
    *) echo "FAIL: expected local-* active, got $active" >&2; exit 1 ;;
esac

target_roc="$ROCUP_HOME/$active/roc"
[ -L "$target_roc" ] || { echo "FAIL: $target_roc is not a symlink" >&2; exit 1; }
assert_eq "$roc_file" "$(readlink "$target_roc")" "roc symlink target"

pass
