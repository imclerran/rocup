#!/bin/bash
# Coverage for 'rocup local': errors when nothing registered, activates the
# sole local, and picks the newest-mtime local when several are registered.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# ---- no locals registered ------------------------------------------------

# Empty ROCUP_HOME (created by setup) — no locals, should error.
mkdir -p "$ROCUP_HOME"
output=$("$ROCUP" local 2>&1) && { echo "FAIL: 'rocup local' with no locals should error" >&2; exit 1; }
assert_contains "$output" "no local versions registered" "errors when none registered"

# A nightly present, but still no locals — still errors.
make_fake_nightly 2025-10-25 1111111 > /dev/null
output=$("$ROCUP" local 2>&1) && { echo "FAIL: 'rocup local' with only nightlies should error" >&2; exit 1; }
assert_contains "$output" "no local versions registered" "errors when only nightlies present"

# ---- single local registered --------------------------------------------

# Register a local; it should be the one activated.
single_dir="$TEST_TMPDIR/single-local"
mkdir -p "$single_dir"
cat > "$single_dir/roc" <<'EOF'
#!/bin/sh
echo single
EOF
chmod +x "$single_dir/roc"

"$ROCUP" "$single_dir" >/dev/null 2>&1
# Switch off it (back to the nightly) so 'rocup local' has work to do.
"$ROCUP" 1111111 >/dev/null 2>&1 || true
# In case the nightly switch failed (e.g. activate finds no roc), force-pick it.
ln -sfn "$ROCUP_HOME/roc_nightly-2025-10-25-1111111" "$ROCUP_HOME/roc"

"$ROCUP" local >/dev/null 2>&1
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
case "$active" in
    local-*) ;;
    *) echo "FAIL: expected local-* active after 'rocup local', got $active" >&2; exit 1 ;;
esac

# ---- multiple locals: newest mtime wins ---------------------------------

# Register a second local with an OLDER roc-binary mtime, then 'rocup local'
# should still pick the first (newer) one.
older_dir="$TEST_TMPDIR/older-local"
mkdir -p "$older_dir"
cat > "$older_dir/roc" <<'EOF'
#!/bin/sh
echo older
EOF
chmod +x "$older_dir/roc"
# Backdate the binary by a day.
touch -t 202001010000 "$older_dir/roc"

"$ROCUP" "$older_dir" >/dev/null 2>&1

# That activated the older one; flip back to nightly and call 'local'.
ln -sfn "$ROCUP_HOME/roc_nightly-2025-10-25-1111111" "$ROCUP_HOME/roc"
"$ROCUP" local >/dev/null 2>&1

active=$(basename "$(readlink "$ROCUP_HOME/roc")")
resolved=$(readlink "$ROCUP_HOME/$active")
assert_eq "$single_dir" "$resolved" "newest-mtime local wins"

# Now bump the older one's binary to be the newest, run 'local' again,
# and confirm the choice flips. Use a far-future timestamp to avoid
# second-resolution ties with $single_dir/roc.
touch -t 203001010000 "$older_dir/roc"
ln -sfn "$ROCUP_HOME/roc_nightly-2025-10-25-1111111" "$ROCUP_HOME/roc"
"$ROCUP" local >/dev/null 2>&1
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
resolved=$(readlink "$ROCUP_HOME/$active")
assert_eq "$older_dir" "$resolved" "freshly-touched local wins after mtime bump"

pass
