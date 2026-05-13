#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME"
make_fake_nightly '2025-10-25' 'aaaaaaa' > /dev/null
make_fake_alpha4 > /dev/null
activate_fake 'roc_nightly-2025-10-25-aaaaaaa'

# Remove the only nightly. Fallback should be alpha4 (nightlies first, then alpha4).
"$ROCUP" remove aaaaaaa >/dev/null 2>&1

active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "roc-alpha4-rolling" "$active" "alpha4 fallback when no nightly remains"

pass
