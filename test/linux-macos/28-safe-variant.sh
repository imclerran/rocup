#!/bin/bash
# Offline: safe builds (roc_nightly-YYYY-MM-DD-<hash>-safe) are addressed as
# <hash>-safe, live beside the regular build of the same nightly, and +N/-N
# steps within the active build's variant.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

mkdir -p "$ROCUP_HOME"
make_fake_nightly '2026-11-07' 'ad3a5d2' > /dev/null
make_fake_nightly '2026-11-07' 'ad3a5d2-safe' > /dev/null
make_fake_nightly '2026-11-06' '34f137a' > /dev/null
make_fake_nightly '2026-11-06' '34f137a-safe' > /dev/null
make_fake_nightly '2026-11-04' '2622062' > /dev/null
activate_fake 'roc_nightly-2026-11-07-ad3a5d2'

active() { basename "$(readlink "$ROCUP_HOME/roc")"; }

# list shows the token you type to get each build back.
output=$("$ROCUP" list 2>&1)
assert_contains "$output" " -> nightly (11/07/2026) <ad3a5d2>" 'regular build listed and active'
assert_contains "$output" "    nightly (11/07/2026) <ad3a5d2-safe>" 'safe build listed with suffix'
assert_contains "$output" "    nightly (11/06/2026) <34f137a-safe>" 'older safe build listed'

# <hash>-safe activates the installed safe build without touching the network;
# 8-char hashes are accepted like the regular form.
"$ROCUP" ad3a5d2-safe >/dev/null 2>&1
assert_eq 'roc_nightly-2026-11-07-ad3a5d2-safe' "$(active)" '<hash>-safe activates the safe build'
"$ROCUP" ad3a5d2 >/dev/null 2>&1
assert_eq 'roc_nightly-2026-11-07-ad3a5d2' "$(active)" '<hash> activates the regular build'
"$ROCUP" ad3a5d2f-safe >/dev/null 2>&1
assert_eq 'roc_nightly-2026-11-07-ad3a5d2-safe' "$(active)" '8-char <hash>-safe is truncated'

# Offline stepping stays within the variant.
export ROCUP_TEST_OFFLINE=1
"$ROCUP" -1 >/dev/null 2>&1
assert_eq 'roc_nightly-2026-11-06-34f137a-safe' "$(active)" '-1 from safe skips the regular 11-07 build'
output=$("$ROCUP" -1 2>&1) && { echo "FAIL: -1 past oldest safe build should error" >&2; exit 1; }
assert_contains "$output" "only 0 installed safe nightlies older than active" 'oldest-safe edge error'
assert_eq 'roc_nightly-2026-11-06-34f137a-safe' "$(active)" 'failed step leaves active unchanged'
"$ROCUP" +1 >/dev/null 2>&1
assert_eq 'roc_nightly-2026-11-07-ad3a5d2-safe' "$(active)" '+1 from safe lands on the newer safe build'

"$ROCUP" 34f137a >/dev/null 2>&1
"$ROCUP" -1 >/dev/null 2>&1
assert_eq 'roc_nightly-2026-11-04-2622062' "$(active)" '-1 from regular skips the safe 11-06 build'
"$ROCUP" +2 >/dev/null 2>&1
assert_eq 'roc_nightly-2026-11-07-ad3a5d2' "$(active)" '+2 from regular walks regular builds only'
unset ROCUP_TEST_OFFLINE

# Online stepping (stubbed tag list): the safe timeline is shorter than the
# regular one, and running off its end errors with a pointer to the regular
# build instead of silently crossing over.
eval "$(sed -n '/^variant_suffix()/,/^}/p; /^variant_label()/,/^}/p; /^tag_hash()/,/^}/p; /^_step_via_tags()/,/^}/p' "$ROCUP")"
install_nightly() { echo "install $1 ${3:-regular}"; }
detect_platform() { echo "test"; }
safe_tags=$'nightly-2026-11-07-ad3a5d2-safe\nnightly-2026-11-06-34f137a-safe'
regular_tags=$'nightly-2026-11-07-ad3a5d2\nnightly-2026-11-06-34f137a\nnightly-2026-11-04-2622062'
assert_eq $'.. target: nightly-2026-11-06-34f137a-safe\ninstall 34f137a safe' "$(_step_via_tags - 1 ad3a5d2 "$safe_tags" safe)" '-1 along the safe timeline'
output=$(_step_via_tags - 1 34f137a "$safe_tags" safe 2>&1) && { echo "FAIL: -1 past oldest safe tag should error" >&2; exit 1; }
assert_contains "$output" "only 0 safe nightlies older than active" 'oldest-safe tag error'
assert_contains "$output" "Use 'rocup 34f137a' to switch to the regular build" 'error names the regular build'
assert_eq $'.. target: nightly-2026-11-04-2622062\ninstall 2622062 regular' "$(_step_via_tags - 1 34f137a "$regular_tags")" '-1 along the regular timeline'

# remove and freeze treat <hash>-safe as its own entry.
"$ROCUP" ad3a5d2-safe >/dev/null 2>&1
"$ROCUP" remove ad3a5d2-safe >/dev/null 2>&1
[ ! -e "$ROCUP_HOME/roc_nightly-2026-11-07-ad3a5d2-safe" ] || { echo "FAIL: safe build not removed" >&2; exit 1; }
[ -d "$ROCUP_HOME/roc_nightly-2026-11-07-ad3a5d2" ] || { echo "FAIL: regular build removed alongside safe" >&2; exit 1; }
assert_eq 'roc_nightly-2026-11-07-ad3a5d2' "$(active)" 'fallback after removing active safe build'
output=$("$ROCUP" remove ad3a5d2-safe 2>&1) && { echo "FAIL: removing a missing safe build should error" >&2; exit 1; }
assert_contains "$output" "roc_nightly-ad3a5d2-safe does not exist" 'missing safe build error'
"$ROCUP" remove ad3a5d2 >/dev/null 2>&1
[ ! -e "$ROCUP_HOME/roc_nightly-2026-11-07-ad3a5d2" ] || { echo "FAIL: regular build not removed" >&2; exit 1; }
[ -d "$ROCUP_HOME/roc_nightly-2026-11-06-34f137a-safe" ] || { echo "FAIL: safe 11-06 build removed by regular remove" >&2; exit 1; }

eval "$(sed -n '/^find_nightly_dir()/,/^}/p; /^validate_freeze_name()/,/^}/p' "$ROCUP")"
assert_exit_code 1 'freeze name colliding with an installed safe build rejected' -- validate_freeze_name 34f137a-safe
assert_exit_code 0 'freeze name of a safe build that is not installed allowed' -- validate_freeze_name 2622062-safe

# prune counts safe builds as nightlies.
"$ROCUP" 34f137a-safe >/dev/null 2>&1
output=$("$ROCUP" prune 1 2>&1)
assert_contains "$output" "keep roc_nightly-2026-11-06-34f137a-safe (active)" 'prune keeps the active safe build'
assert_contains "$output" "remove roc_nightly-2026-11-04-2622062" 'prune removes the older regular build'
[ ! -d "$ROCUP_HOME/roc_nightly-2026-11-06-34f137a" ] || { echo "FAIL: prune 1 should drop the regular 11-06 build" >&2; exit 1; }

pass
