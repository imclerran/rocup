#!/bin/bash
# Offline: parse_tag_date accepts numeric, full-name and abbreviated months.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Load just the parsing functions so the script's dispatch doesn't run.
eval "$(sed -n '/^month_name_to_num()/,/^}/p; /^parse_tag_date()/,/^}/p' "$ROCUP")"

assert_eq '2026-10-30' "$(parse_tag_date nightly-2026-10-30-0602c5f)" 'numeric month'
assert_eq '2026-01-01' "$(parse_tag_date nightly-2026-01-01-abcdef0)" 'numeric January'
assert_eq '2026-12-31' "$(parse_tag_date nightly-2026-12-31-abcdef0)" 'numeric December'
assert_eq '2026-08-05' "$(parse_tag_date nightly-2026-August-05-24f0b47)" 'full month name'
assert_eq '2026-08-05' "$(parse_tag_date nightly-2026-Aug-05-24f0b47)" 'abbreviated month name'

for bad in nightly-2026-00-05-abcdef0 nightly-2026-13-05-abcdef0 nightly-2026-8-05-abcdef0 \
           nightly-2026-Foo-05-abcdef0 release-2026-08-05-abcdef0 nightly-2026-08-05; do
    assert_exit_code 1 "rejects $bad" -- parse_tag_date "$bad"
done

pass
