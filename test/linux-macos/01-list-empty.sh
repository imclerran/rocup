#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Empty $ROCUP_HOME should report "no versions installed".
output=$("$ROCUP" list 2>&1)
assert_contains "$output" "no versions installed" "list with empty home"

pass
