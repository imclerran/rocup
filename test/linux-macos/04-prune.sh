#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME"
make_fake_nightly '2025-10-25' 'aaaaaaa' > /dev/null
make_fake_nightly '2025-10-20' 'bbbbbbb' > /dev/null
make_fake_nightly '2025-10-15' 'ccccccc' > /dev/null
make_fake_nightly '2025-10-10' 'ddddddd' > /dev/null
activate_fake 'roc_nightly-2025-10-25-aaaaaaa'

"$ROCUP" prune 2 >/dev/null 2>&1

# Top 2 + active kept (active is in top 2, so 2 total).
[ -d "$ROCUP_HOME/roc_nightly-2025-10-25-aaaaaaa" ] || { echo "FAIL: newest gone" >&2; exit 1; }
[ -d "$ROCUP_HOME/roc_nightly-2025-10-20-bbbbbbb" ] || { echo "FAIL: 2nd-newest gone" >&2; exit 1; }
[ ! -d "$ROCUP_HOME/roc_nightly-2025-10-15-ccccccc" ] || { echo "FAIL: 3rd was kept" >&2; exit 1; }
[ ! -d "$ROCUP_HOME/roc_nightly-2025-10-10-ddddddd" ] || { echo "FAIL: 4th was kept" >&2; exit 1; }

pass
