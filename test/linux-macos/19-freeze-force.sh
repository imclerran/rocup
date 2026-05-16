#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "v1"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1
"$ROCUP" freeze keepme >/dev/null

# Modify the local source to differentiate v1 vs v2.
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "v2"
EOF
chmod +x "$local_dir/roc"
# Active is currently frozen-keepme; switch back to the local before freezing again.
# The bash dispatcher resolves a bare hash via local-<hash> when registered, so
# strip the 'local-' prefix and pass the hash.
local_name=$(find "$ROCUP_HOME" -maxdepth 1 -name 'local-*' -print -quit | xargs -n1 basename)
local_hash="${local_name#local-}"
"$ROCUP" "$local_hash" >/dev/null 2>&1

# Without --force: refused.
assert_exit_code 1 "refuse without --force" -- "$ROCUP" freeze keepme

# The existing frozen entry is untouched (still v1).
output=$("$ROCUP_HOME/frozen-keepme/roc")
assert_eq "v1" "$output" "frozen entry untouched after refused freeze"

# With --force: overwritten.
"$ROCUP" freeze keepme --force >/dev/null
output=$("$ROCUP_HOME/frozen-keepme/roc")
assert_eq "v2" "$output" "frozen entry overwritten with --force"

# Active is frozen-keepme again.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-keepme" "$active" "active switched to frozen-keepme after --force"

pass
