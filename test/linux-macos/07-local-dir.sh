#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Create a fake local roc build dir.
local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "local roc"
EOF
chmod +x "$local_dir/roc"

"$ROCUP" "$local_dir" >/dev/null 2>&1

# Active should be a local-* dir.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
case "$active" in
    local-*) ;;
    *) echo "FAIL: expected local-* active, got $active" >&2; exit 1 ;;
esac

# Resolves back to the source dir.
resolved=$(readlink "$ROCUP_HOME/$active")
assert_eq "$local_dir" "$resolved" "local entry resolves to source"

pass
