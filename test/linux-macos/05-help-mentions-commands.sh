#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

output=$("$ROCUP" --help 2>&1)
for cmd in alpha4 latest list local remove prune; do
    assert_contains "$output" "$cmd" "help mentions $cmd"
done

pass
