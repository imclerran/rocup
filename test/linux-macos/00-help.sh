#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

output=$("$ROCUP" --help 2>&1)
assert_contains "$output" "usage:" "rocup --help must show usage"
assert_contains "$output" "latest" "rocup --help must mention 'latest'"
assert_contains "$output" "list" "rocup --help must mention 'list'"

pass
