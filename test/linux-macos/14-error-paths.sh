#!/bin/bash
# Error-path coverage: malformed args, missing args, "no active version" etc.
# All offline — no network needed.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME"

# Invalid hash length (6 chars).
output=$("$ROCUP" abc 2>&1) && { echo "FAIL: 'abc' should error" >&2; exit 1; }
assert_contains "$output" "invalid argument" "short hash rejected"

# Non-hex characters in hash.
output=$("$ROCUP" zzzzzzz 2>&1) && { echo "FAIL: 'zzzzzzz' should error" >&2; exit 1; }
assert_contains "$output" "invalid argument" "non-hex hash rejected"

# 'remove' with no arg.
output=$("$ROCUP" remove 2>&1) && { echo "FAIL: 'remove' with no arg should error" >&2; exit 1; }
assert_contains "$output" "requires an argument" "remove without arg errors"

# 'prune' with no arg.
output=$("$ROCUP" prune 2>&1) && { echo "FAIL: 'prune' with no arg should error" >&2; exit 1; }
assert_contains "$output" "requires a count" "prune without arg errors"

# 'prune' with negative.
output=$("$ROCUP" prune -1 2>&1) && { echo "FAIL: 'prune -1' should error" >&2; exit 1; }
# bash version treats -1 as a flag; either it errors as 'invalid step' (because
# -1 matches the step regex) or as an unknown prune count. Both are acceptable
# rejections; assert it didn't silently delete anything.
assert_contains "$output" "error" "prune -1 errors"

# Step with no active version.
output=$("$ROCUP" -1 2>&1) && { echo "FAIL: -1 with no active should error" >&2; exit 1; }
assert_contains "$output" "no active version" "step without active errors"

# Stepping when active is alpha4 (not nightly).
make_fake_alpha4 > /dev/null
activate_fake 'roc-alpha4-rolling'
output=$("$ROCUP" -1 2>&1) && { echo "FAIL: -1 with active=alpha4 should error" >&2; exit 1; }
assert_contains "$output" "requires an active nightly" "step from alpha4 errors"

# Remove of nonexistent hash (in a non-empty home, so the path resolver runs).
output=$("$ROCUP" remove 9999999 2>&1) && { echo "FAIL: remove of nonexistent should error" >&2; exit 1; }
assert_contains "$output" "does not exist" "remove nonexistent errors"

pass
