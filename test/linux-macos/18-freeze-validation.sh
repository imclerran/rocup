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

# ---- Preconditions ----

# 6. No active version.
rm -f "$ROCUP_HOME/roc"
assert_exit_code 1 "no-active rejected" -- "$ROCUP" freeze test1

# 7. Active is not a local.
make_fake_alpha4 >/dev/null
activate_fake roc-alpha4-rolling
assert_exit_code 1 "non-local-active rejected" -- "$ROCUP" freeze test2

# 8. Active local has dangling resolution.
dangling_src="$TEST_TMPDIR/will-be-deleted"
mkdir -p "$dangling_src"
cat > "$dangling_src/roc" <<'EOF'
#!/bin/sh
echo "doomed roc"
EOF
chmod +x "$dangling_src/roc"
"$ROCUP" "$dangling_src" >/dev/null 2>&1
rm -rf "$dangling_src"
assert_exit_code 1 "dangling-local rejected" -- "$ROCUP" freeze test3

# 9. Active local has no roc binary in the resolved dir.
no_roc_src="$TEST_TMPDIR/no-roc"
mkdir -p "$no_roc_src"
cat > "$no_roc_src/roc" <<'EOF'
#!/bin/sh
echo "ok"
EOF
chmod +x "$no_roc_src/roc"
"$ROCUP" "$no_roc_src" >/dev/null 2>&1
rm -f "$no_roc_src/roc"
assert_exit_code 1 "missing-roc rejected" -- "$ROCUP" freeze test4

pass
