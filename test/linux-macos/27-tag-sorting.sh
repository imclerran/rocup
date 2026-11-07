#!/bin/bash
# Offline: fetch_recent_tags sorts by tag date rather than trusting GitHub's
# created_at ordering, and honors the requested count after sorting.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

eval "$(sed -n '/^month_name_to_num()/,/^}/p; /^parse_tag_date()/,/^}/p; /^fetch_recent_tags()/,/^}/p; /^select_nightly_tags()/,/^}/p; /^sort_tags_by_date()/,/^}/p; /^resolve_latest_hash()/,/^}/p; /^variant_suffix()/,/^}/p; /^variant_label()/,/^}/p; /^tag_hash()/,/^}/p' "$ROCUP")"

# Real ordering observed from the API in July 2026: June 28-30 listed ahead
# of July 1-7 because they share a created_at.
api_order='nightly-2026-June-30-09084da
nightly-2026-June-29-2e1efb1
nightly-2026-June-28-26ecddf
nightly-2026-July-07-050c697
nightly-2026-July-06-17d1197
nightly-2026-July-01-7981032
nightly-2026-June-27-127861d'

# Stub the network layer.
fetch_tags_unsorted() { echo "$api_order"; }

expected='nightly-2026-July-07-050c697
nightly-2026-July-06-17d1197
nightly-2026-July-01-7981032
nightly-2026-June-30-09084da
nightly-2026-June-29-2e1efb1
nightly-2026-June-28-26ecddf
nightly-2026-June-27-127861d'

assert_eq "$expected" "$(sort_tags_by_date "$api_order")" 'sorted newest first by tag date'
assert_eq 'nightly-2026-July-07-050c697' "$(fetch_recent_tags roc-lang/nightlies 1)" 'count 1 picks newest'
assert_eq $'nightly-2026-July-07-050c697\nnightly-2026-July-06-17d1197' "$(fetch_recent_tags roc-lang/nightlies 2)" 'count 2 truncates after sorting'

# Mixed month formats and same-day ties sort deterministically; junk sorts last.
mixed='junk-tag
nightly-2026-08-07-8d23662
nightly-2026-July-23-306abd6
nightly-2026-July-23-fdd77c3
nightly-2026-August-05-24f0b47'
expected_mixed='nightly-2026-08-07-8d23662
nightly-2026-August-05-24f0b47
nightly-2026-July-23-fdd77c3
nightly-2026-July-23-306abd6
junk-tag'
assert_eq "$expected_mixed" "$(sort_tags_by_date "$mixed")" 'mixed month formats and ties'

# Regular and safe builds (same commit, '-safe' suffixed tag) have separate
# timelines, so a safe tag never becomes plain "latest" or shifts plain +N/-N
# offsets, and vice versa. Observed Nov 2026: nightly-2026-11-07-ad3a5d2-safe
# published alongside nightly-2026-11-07-ad3a5d2.
with_variant='nightly-2026-11-07-ad3a5d2-safe
nightly-2026-11-07-ad3a5d2
nightly-2026-11-06-34f137a
junk-tag'
assert_eq $'nightly-2026-11-07-ad3a5d2\nnightly-2026-11-06-34f137a' "$(select_nightly_tags "$with_variant")" 'regular timeline drops safe and junk'
assert_eq 'nightly-2026-11-07-ad3a5d2-safe' "$(select_nightly_tags "$with_variant" safe)" 'safe timeline keeps only safe'
assert_eq '' "$(select_nightly_tags 'nightly-2026-11-07-ad3a5d2-safe')" 'only-safe list is empty for regular'
assert_eq 'ad3a5d2' "$(tag_hash nightly-2026-11-07-ad3a5d2-safe)" 'tag_hash strips the safe suffix'
assert_eq 'ad3a5d2' "$(tag_hash nightly-2026-11-07-ad3a5d2)" 'tag_hash on a regular tag'
fetch_tags_unsorted() { echo "$with_variant"; }
assert_eq $'nightly-2026-11-07-ad3a5d2\nnightly-2026-11-06-34f137a' "$(fetch_recent_tags roc-lang/nightlies 2)" 'fetch_recent_tags skips safe'
assert_eq 'nightly-2026-11-07-ad3a5d2-safe' "$(fetch_recent_tags roc-lang/nightlies 2 safe)" 'fetch_recent_tags safe timeline'
assert_eq 'ad3a5d2' "$(resolve_latest_hash)" 'latest resolves to the regular hash'
assert_eq 'ad3a5d2' "$(resolve_latest_hash safe)" 'latest-safe resolves to the hash'
fetch_tags_unsorted() { echo 'nightly-2026-11-06-34f137a'; }
output=$(resolve_latest_hash safe 2>&1) && { echo "FAIL: latest-safe with no safe builds should error" >&2; exit 1; }
assert_contains "$output" "could not find any safe nightlies" 'latest-safe error when none exist'

pass
