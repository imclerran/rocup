#!/bin/bash
# Network test: installing a nightly whose release tag uses a 2-digit month
# number (e.g. nightly-2026-08-06-... ) instead of a month name. Exercises
# parse_tag_date / month_name_to_num against the numeric-month format.
# Gated by ROCUP_TEST_NETWORK=1 like the other network tests.
source "$(dirname "$0")/../common/lib.sh"

if [ "${ROCUP_TEST_NETWORK:-0}" != "1" ]; then
    echo "SKIP: 24-network-numeric-month-tag.sh (ROCUP_TEST_NETWORK!=1)"
    exit 0
fi

setup_test_env

# A known numeric-month release hash. Adjust if this specific nightly is ever
# removed from roc-lang/nightlies; any tag with a numeric month works.
HASH="61bbb59"

log="$TEST_TMPDIR/rocup-hash.log"
if ! "$ROCUP" "$HASH" > "$log" 2>&1; then
    echo "FAIL: 'rocup $HASH' exited non-zero. Log:" >&2
    cat "$log" >&2
    exit 1
fi

# The resulting dir must carry a YYYY-MM-DD numeric-month date and this hash.
nightly_dir=$(basename "$(find "$ROCUP_HOME" -maxdepth 1 -type d -name "roc_nightly-*-${HASH}" -print -quit)")
[ -n "$nightly_dir" ] || { echo "FAIL: no roc_nightly dir for $HASH" >&2; cat "$log" >&2; exit 1; }

[[ "$nightly_dir" =~ ^roc_nightly-([0-9]{4})-([0-9]{2})-([0-9]{2})-${HASH}$ ]] \
    || { echo "FAIL: dir $nightly_dir not numeric-month format" >&2; cat "$log" >&2; exit 1; }

# Spot-check the parsed month is a valid 1-12 and the date makes sense.
month=$((10#${BASH_REMATCH[2]}))
[ "$month" -ge 1 ] && [ "$month" -le 12 ] \
    || { echo "FAIL: parsed month ${BASH_REMATCH[2]} out of range" >&2; exit 1; }

# Active symlink should point at it.
active=$(readlink "$ROCUP_HOME/roc")
assert_eq "$ROCUP_HOME/$nightly_dir" "$active" "active symlink points at numeric-month nightly"

pass
