#!/bin/bash
# Forces fetch_recent_tags to return empty via ROCUP_TEST_OFFLINE=1, exercising
# the installed-only fallback path of step_nightly deterministically.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME"
make_fake_nightly '2025-10-25' 'aaaaaaa' > /dev/null
make_fake_nightly '2025-10-20' 'bbbbbbb' > /dev/null
make_fake_nightly '2025-10-15' 'ccccccc' > /dev/null
activate_fake 'roc_nightly-2025-10-20-bbbbbbb'

export ROCUP_TEST_OFFLINE=1

# -1 from 2025-10-20 should activate 2025-10-15 (next-older among installed).
"$ROCUP" -1 >/dev/null 2>&1
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "roc_nightly-2025-10-15-ccccccc" "$active" "-1 lands on next-older nightly"

# +2 from 2025-10-15 should activate 2025-10-25 (two newer).
"$ROCUP" +2 >/dev/null 2>&1
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "roc_nightly-2025-10-25-aaaaaaa" "$active" "+2 lands two newer"

# Stepping past the edge should error cleanly.
output=$("$ROCUP" +1 2>&1) && { echo "FAIL: +1 past newest should error" >&2; exit 1; }
assert_contains "$output" "only 0 installed nightlies newer than active" "edge error message"

pass
