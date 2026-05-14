#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME"
make_fake_nightly '2025-10-25' 'a1b2c3d' > /dev/null

# 8-char input (mimics 'roc --version') should resolve to the 7-char dir.
"$ROCUP" remove a1b2c3d0 >/dev/null 2>&1

[ ! -d "$ROCUP_HOME/roc_nightly-2025-10-25-a1b2c3d" ] || { echo "FAIL: 8-char hash didn't truncate" >&2; exit 1; }

pass
