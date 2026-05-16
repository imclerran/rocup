#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Make a fake local active so freeze's preconditions pass.
local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "local roc"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1

# 1. Empty name rejected.
assert_exit_code 1 "empty name rejected" -- "$ROCUP" freeze ""

# 2. Bad characters rejected.
assert_exit_code 1 "spaces rejected"  -- "$ROCUP" freeze "has space"
assert_exit_code 1 "slash rejected"   -- "$ROCUP" freeze "a/b"

# 3. Name starting with frozen- rejected.
assert_exit_code 1 "leading frozen- rejected" -- "$ROCUP" freeze "frozen-foo"

# 4. Name colliding with the active local's hash rejected.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
active_hash="${active#local-}"
assert_exit_code 1 "hash-collision rejected" -- "$ROCUP" freeze "$active_hash"

# 5. Collision-without-force: pre-create the target dir.
mkdir -p "$ROCUP_HOME/frozen-already-there"
touch "$ROCUP_HOME/frozen-already-there/roc"
assert_exit_code 1 "exists-no-force rejected" -- "$ROCUP" freeze "already-there"

pass
