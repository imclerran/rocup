#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Set up two frozen entries and no other versions. Active is the second
# (newer) frozen. Removing it must fall back to the first frozen rather
# than leaving the install with no active version.

local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "local"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1

# Freeze #1. active -> frozen-keep-me.
"$ROCUP" freeze keep-me >/dev/null

# Switch back to the local by hash (the bash dispatcher resolves a bare hash
# to local-<hash> when one is registered) so we can freeze again.
local_name=$(find "$ROCUP_HOME" -maxdepth 1 -name 'local-*' -print -quit | xargs -n1 basename)
local_hash="${local_name#local-}"
"$ROCUP" "$local_hash" >/dev/null 2>&1

# Freeze #2. active -> frozen-drop-me.
"$ROCUP" freeze drop-me >/dev/null

# Drop the underlying local so only the two frozens remain.
"$ROCUP" remove "$local_name" >/dev/null

# Sanity: active is still frozen-drop-me (removing a non-active version
# doesn't change the active pointer).
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-drop-me" "$active" "active is the newer frozen"

# Remove the active frozen. Fallback should pick the remaining frozen.
"$ROCUP" remove frozen-drop-me >/dev/null
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-keep-me" "$active" "fallback to remaining frozen entry"

pass
