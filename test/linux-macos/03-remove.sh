#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME"
make_fake_nightly '2025-10-25' 'aaaaaaa' > /dev/null
make_fake_nightly '2025-10-01' 'bbbbbbb' > /dev/null
activate_fake 'roc_nightly-2025-10-25-aaaaaaa'

# Remove the active version. Fallback should activate the other nightly.
"$ROCUP" remove aaaaaaa >/dev/null 2>&1

if [ -d "$ROCUP_HOME/roc_nightly-2025-10-25-aaaaaaa" ]; then
    echo "FAIL: removed dir still exists" >&2
    exit 1
fi

active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "roc_nightly-2025-10-01-bbbbbbb" "$active" "fallback activated"

pass
