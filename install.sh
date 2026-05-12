#!/bin/sh
# rocup installer. Downloads the rocup script into $ROCUP_HOME and runs it to
# install the latest Roc nightly, optionally wiring up global symlinks in
# $ROCUP_PREFIX. Designed to be safe to pipe from curl:
#
#   curl -fsSL https://raw.githubusercontent.com/imclerran/rocup/main/install.sh | sh
#
# Reads the consent prompt from /dev/tty so it works even when stdin is a pipe.

set -eu

REPO="${ROCUP_REPO:-imclerran/rocup}"
BRANCH="${ROCUP_BRANCH:-main}"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/rocup"

ROCUP_HOME="${ROCUP_HOME:-$HOME/.rocup}"
ROCUP_PREFIX="${ROCUP_PREFIX:-/usr/local/bin}"

if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is required" >&2
    exit 1
fi

# Ask up front (via /dev/tty so curl | sh works). Default to yes — matches the
# tone of similar installers (uv, rustup) where the user opted into a one-liner.
assume_yes=0
if [ "${ROCUP_ASSUME_YES:-}" = "1" ]; then
    assume_yes=1
elif [ -r /dev/tty ]; then
    printf "Install symlinks for rocup, roc, and roc_language_server in %s? [Y/n] " "$ROCUP_PREFIX" > /dev/tty
    reply=""
    read -r reply < /dev/tty || reply=""
    case "$reply" in
        n|N|no|NO|No) assume_yes=0 ;;
        *)            assume_yes=1 ;;
    esac
else
    echo ".. no tty available; skipping global symlinks (set ROCUP_ASSUME_YES=1 to force)"
fi

mkdir -p "$ROCUP_HOME"
echo ".. downloading rocup from $RAW_URL"
curl -fsSL "$RAW_URL" -o "$ROCUP_HOME/rocup"
chmod +x "$ROCUP_HOME/rocup"
echo ".. installed rocup at $ROCUP_HOME/rocup"

ROCUP_ASSUME_YES="$assume_yes" ROCUP_HOME="$ROCUP_HOME" ROCUP_PREFIX="$ROCUP_PREFIX" \
    exec "$ROCUP_HOME/rocup" latest
