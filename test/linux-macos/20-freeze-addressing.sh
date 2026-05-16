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

# ---- Activate ----

# Switch to a different version so we can verify activation.
make_fake_alpha4 >/dev/null
"$ROCUP" alpha4 2>/dev/null || activate_fake roc-alpha4-rolling

# Activate by literal frozen-<name>.
"$ROCUP" frozen-myfeature >/dev/null 2>&1
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-myfeature" "$active" "activate by literal frozen-<name>"

# Switch away again.
activate_fake roc-alpha4-rolling

# Activate by bare <name>.
"$ROCUP" myfeature >/dev/null 2>&1
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-myfeature" "$active" "activate by bare <name>"

# ---- Remove ----

# Make another frozen entry for the bare-remove case.
local_name=$(find "$ROCUP_HOME" -maxdepth 1 -name 'local-*' -print -quit | xargs -n1 basename)
local_hash="${local_name#local-}"
"$ROCUP" "$local_hash" >/dev/null 2>&1
"$ROCUP" freeze second >/dev/null

# Remove by literal frozen-<name>.
"$ROCUP" remove frozen-myfeature >/dev/null
[ -e "$ROCUP_HOME/frozen-myfeature" ] && { echo "FAIL: frozen-myfeature still present after remove" >&2; exit 1; }

# Remove by bare <name>.
"$ROCUP" remove second >/dev/null
[ -e "$ROCUP_HOME/frozen-second" ] && { echo "FAIL: frozen-second still present after bare remove" >&2; exit 1; }

pass
