#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME"
make_fake_nightly '2025-10-25' 'aaaaaaa' > /dev/null
make_fake_nightly '2025-10-01' 'bbbbbbb' > /dev/null
activate_fake 'roc_nightly-2025-10-25-aaaaaaa'

output=$("$ROCUP" list 2>&1)
assert_contains "$output" "nightly (10/25/2025) <aaaaaaa>" "newer nightly listed"
assert_contains "$output" "nightly (10/01/2025) <bbbbbbb>" "older nightly listed"
assert_contains "$output" " -> nightly (10/25/2025) <aaaaaaa>" "active marker on newer"

pass
