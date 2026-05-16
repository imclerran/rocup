#!/bin/bash
# Asserts that rocup (bash) and rocup.ps1 (PowerShell) stay in sync along
# two axes:
#
#   1. Command surface: both implementations advertise the same set of
#      subcommands, modulo KNOWN_BASH_ONLY / KNOWN_PS_ONLY divergences.
#
#   2. Usage text content: both implementations describe each shared command
#      using a common vocabulary (REQUIRED_PHRASES). Catches accidental
#      rewordings where the two scripts drift in described behavior.
#
# Implementation-detail differences (symlink vs junction, '/usr/local/bin'
# vs User PATH, $ROCUP_HOME vs $env:ROCUP_HOME, file-mode local registration,
# language server dispatch) are intentionally NOT compared - they're listed
# in FEATURE_MATRIX.md and are platform-essential.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASH_SCRIPT="$ROOT/rocup"
PS_SCRIPT="$ROOT/rocup.ps1"

# Commands intentionally absent from the Windows port. Update this when the
# Windows port gains support for one of them.
KNOWN_BASH_ONLY="alpha4"

# Commands intentionally absent from the bash version. Currently none.
KNOWN_PS_ONLY=""

# Phrases that must appear (case-sensitive, substring match) in BOTH the bash
# `usage` text and the PowerShell `Show-Usage` text. These are the load-bearing
# behavioral promises of each command; if either side rewords them, the user
# experience has drifted even if the command name is still present.
#
# Format: one per line, blank lines and '#'-prefixed comments ignored.
REQUIRED_PHRASES=$(cat <<'EOF'
# Synopsis - the canonical command-list fragment shown at the top of --help.
# Both implementations expand to '[ ... | <hash> | <path> | local | +N | -N | list | ...]'.
# Bash's includes 'alpha4 |' as an extra leading option; the fragment below
# starts at <hash> to match both.
<hash> | <path> | local | +N | -N | list

# 'latest' - default install/activate action.
install/activate the most recent nightly
roc-lang/nightlies
default if no arg

# '<hash>' - the hash dispatch rules.
7- or 8-char hex
roc --version
truncated to 7
If a local install with that hash is registered, activate it

# '<path>' - local registration.
register a local roc

# 'local' - activates the newest-mtime registered local build.
activate a registered local roc build
most recently built one
Errors if no

# '+N | -N' - relative stepping.
step N nightlies newer
older
Requires the active version to be a nightly

# 'list' - inventory display.
show installed versions
mark the active

# 'freeze <name>' - snapshot the active local build.
snapshot the active local build
Requires an active local
--force

# 'remove <ver>' - version deletion.
delete a version

# 'prune <N>' - bulk cleanup.
keep the N most recent nightlies
delete older
EOF
)

# Extract command names from bash `usage()` output. Relies on the stable
# format: each command line starts with two spaces, the command, then
# padded spaces.
extract_bash_cmds() {
    "$BASH_SCRIPT" --help 2>&1 \
        | awk '/^  [a-z+-]/ { print $1 }' \
        | grep -E '^[a-z+-]' \
        | sort -u
}

# Same for Show-Usage. Prefer pwsh and fall back to powershell.exe on Git
# Bash for Windows developers without pwsh.
ps_exe() {
    if command -v pwsh >/dev/null 2>&1; then
        echo pwsh
    elif command -v powershell >/dev/null 2>&1; then
        echo powershell
    elif command -v powershell.exe >/dev/null 2>&1; then
        echo powershell.exe
    else
        echo "drift-check: neither 'pwsh' nor 'powershell' is on PATH" >&2
        exit 2
    fi
}

extract_ps_cmds() {
    "$(ps_exe)" -NoProfile -File "$PS_SCRIPT" --help 2>&1 \
        | awk '/^  [a-z+-]/ { print $1 }' \
        | grep -E '^[a-z+-]' \
        | sort -u
}

# Capture full --help output for content checks. Strip Windows CRLF, then
# collapse all whitespace runs (including newlines) to single spaces so
# substring matches work across line-wrapped descriptions.
flatten() {
    tr -d '\r' | tr '\n' ' ' | tr -s ' '
}
bash_help=$("$BASH_SCRIPT" --help 2>&1 | flatten)
ps_help=$("$(ps_exe)" -NoProfile -File "$PS_SCRIPT" --help 2>&1 | flatten)

bash_cmds=$(extract_bash_cmds)
ps_cmds=$(extract_ps_cmds)

fail=0

# ---- 1. Command surface ------------------------------------------------

bash_only=$(comm -23 <(echo "$bash_cmds") <(echo "$ps_cmds"))
ps_only=$(comm -13 <(echo "$bash_cmds") <(echo "$ps_cmds"))

unexpected_bash_only=$(echo "$bash_only" | grep -vxF "$KNOWN_BASH_ONLY" || true)
unexpected_ps_only=$(echo "$ps_only" | grep -vxF "$KNOWN_PS_ONLY" || true)

if [ -n "$unexpected_bash_only" ]; then
    echo "DRIFT (commands): in bash rocup but missing from rocup.ps1:" >&2
    echo "$unexpected_bash_only" >&2
    echo "If intentional, add to KNOWN_BASH_ONLY in test/drift-check.sh." >&2
    fail=1
fi
if [ -n "$unexpected_ps_only" ]; then
    echo "DRIFT (commands): in rocup.ps1 but missing from bash rocup:" >&2
    echo "$unexpected_ps_only" >&2
    echo "If intentional, add to KNOWN_PS_ONLY in test/drift-check.sh." >&2
    fail=1
fi

# ---- 2. Usage text content --------------------------------------------

missing_in_bash=""
missing_in_ps=""

# Read phrases, skipping blanks and comments.
while IFS= read -r phrase; do
    case "$phrase" in
        ''|'#'*) continue ;;
    esac
    if ! printf '%s' "$bash_help" | grep -qF -- "$phrase"; then
        missing_in_bash="${missing_in_bash}${phrase}"$'\n'
    fi
    if ! printf '%s' "$ps_help" | grep -qF -- "$phrase"; then
        missing_in_ps="${missing_in_ps}${phrase}"$'\n'
    fi
done <<< "$REQUIRED_PHRASES"

if [ -n "$missing_in_bash" ]; then
    echo "DRIFT (usage text): required phrases missing from bash rocup --help:" >&2
    printf '%s' "$missing_in_bash" | sed 's/^/  - /' >&2
    echo "If the phrasing changed intentionally, update REQUIRED_PHRASES in test/drift-check.sh." >&2
    fail=1
fi
if [ -n "$missing_in_ps" ]; then
    echo "DRIFT (usage text): required phrases missing from rocup.ps1 --help:" >&2
    printf '%s' "$missing_in_ps" | sed 's/^/  - /' >&2
    echo "If the phrasing changed intentionally, update REQUIRED_PHRASES in test/drift-check.sh." >&2
    fail=1
fi

# ---- Summary ---------------------------------------------------------

if [ $fail -ne 0 ]; then
    exit 1
fi

echo "DRIFT CHECK: PASS"
echo "  commands  bash: $(echo "$bash_cmds" | tr '\n' ' ')"
echo "  commands  ps:   $(echo "$ps_cmds" | tr '\n' ' ')"
phrase_count=$(printf '%s' "$REQUIRED_PHRASES" | grep -cvE '^(#|$)')
echo "  required phrases: $phrase_count (all present in both --help outputs)"
