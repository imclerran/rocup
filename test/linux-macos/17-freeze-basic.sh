#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Build and register a local roc.
local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "local roc"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1

# Sanity: active should be local-<hash>
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
case "$active" in
    local-*) ;;
    *) echo "FAIL: expected local-* before freeze, got $active" >&2; exit 1 ;;
esac
original_local="$active"

# Freeze it.
"$ROCUP" freeze myfeature >/dev/null

# 1. Active is now frozen-myfeature.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-myfeature" "$active" "active is frozen entry after freeze"

# 2. The frozen entry exists as a real directory (not a symlink).
[ -d "$ROCUP_HOME/frozen-myfeature" ] || { echo "FAIL: frozen-myfeature is not a directory" >&2; exit 1; }
[ -L "$ROCUP_HOME/frozen-myfeature" ] && { echo "FAIL: frozen-myfeature is a symlink" >&2; exit 1; }

# 3. roc inside is a real file (not a symlink) and executable.
[ -f "$ROCUP_HOME/frozen-myfeature/roc" ] || { echo "FAIL: frozen-myfeature/roc missing" >&2; exit 1; }
[ -L "$ROCUP_HOME/frozen-myfeature/roc" ] && { echo "FAIL: frozen-myfeature/roc is a symlink" >&2; exit 1; }
[ -x "$ROCUP_HOME/frozen-myfeature/roc" ] || { echo "FAIL: frozen-myfeature/roc not executable" >&2; exit 1; }

# 4. Contents match the source.
diff "$local_dir/roc" "$ROCUP_HOME/frozen-myfeature/roc" >/dev/null \
    || { echo "FAIL: copied roc differs from source" >&2; exit 1; }

# 5. Original local registration still present.
[ -L "$ROCUP_HOME/$original_local" ] || { echo "FAIL: original local registration was removed" >&2; exit 1; }

# 6. Deleting the source build dir does NOT break the frozen copy.
rm -rf "$local_dir"
[ -x "$ROCUP_HOME/frozen-myfeature/roc" ] || { echo "FAIL: frozen roc broke after source removal" >&2; exit 1; }

pass
