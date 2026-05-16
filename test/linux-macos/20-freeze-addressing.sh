#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "local"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1
"$ROCUP" freeze myfeature >/dev/null

# Listing mentions frozen-myfeature with the active marker.
listing=$("$ROCUP" list)
assert_contains "$listing" "frozen" "list mentions frozen"
assert_contains "$listing" "myfeature" "list mentions the frozen name"
assert_contains "$listing" " -> " "list shows the active marker"

# The frozen entry's line carries the active marker.
active_line=$(printf '%s\n' "$listing" | grep '^ -> ' | head -n1)
assert_contains "$active_line" "myfeature" "active marker is on the frozen line"

pass
