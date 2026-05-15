#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Asserts no line in $1 exceeds $2 cols.
assert_max_line_width() {
    local output="$1" width="$2" label="$3"
    while IFS= read -r line; do
        if [ ${#line} -gt "$width" ]; then
            echo "FAIL: $label: line exceeds $width cols (${#line} chars): $line" >&2
            exit 1
        fi
    done <<< "$output"
}

# Narrow width: every line should fit in 60 cols.
output=$(COLUMNS=60 "$ROCUP" --help 2>&1)
assert_max_line_width "$output" 60 "COLUMNS=60"

# Wide width: no upper cap — output should fit in the requested width.
output=$(COLUMNS=200 "$ROCUP" --help 2>&1)
assert_max_line_width "$output" 200 "COLUMNS=200 (no upper cap)"

# Below-floor width: output should still cap at the 50-col floor.
output=$(COLUMNS=20 "$ROCUP" --help 2>&1)
assert_max_line_width "$output" 50 "COLUMNS=20 (floor)"

# Commands still mentioned at narrow widths.
output=$(COLUMNS=60 "$ROCUP" --help 2>&1)
for cmd in alpha4 latest list local remove prune; do
    assert_contains "$output" "$cmd" "help mentions $cmd at width 60"
done

# Required drift-check phrases still present after wrapping at narrow width.
# These are matched against the flattened (whitespace-collapsed) output, the
# same way test/drift-check.sh does — so word-wrap alone is fine, but any
# accidental word-splitting or reordering would fail.
flatten() { tr -d '\r' | tr '\n' ' ' | tr -s ' '; }
flat=$(COLUMNS=60 "$ROCUP" --help 2>&1 | flatten)
for phrase in \
    "<hash> | <path> | local | +N | -N | list" \
    "install/activate the most recent nightly" \
    "roc-lang/nightlies" \
    "default if no arg" \
    "7- or 8-char hex" \
    "roc --version" \
    "truncated to 7" \
    "If a local install with that hash is registered, activate it" \
    "register a local roc" \
    "activate a registered local roc build" \
    "most recently built one" \
    "Errors if no" \
    "step N nightlies newer" \
    "Requires the active version to be a nightly" \
    "show installed versions" \
    "mark the active" \
    "delete a version" \
    "keep the N most recent nightlies" \
    "delete older"; do
    assert_contains "$flat" "$phrase" "required phrase preserved at width 60: '$phrase'"
done

pass
