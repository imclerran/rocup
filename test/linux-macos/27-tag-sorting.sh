#!/bin/bash
# Offline: fetch_recent_tags sorts by tag date rather than trusting GitHub's
# created_at ordering, and honors the requested count after sorting.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

eval "$(sed -n '/^month_name_to_num()/,/^}/p; /^parse_tag_date()/,/^}/p; /^fetch_recent_tags()/,/^}/p; /^sort_tags_by_date()/,/^}/p' "$ROCUP")"

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

pass
