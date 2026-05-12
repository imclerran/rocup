#!/bin/sh
# rocup installer. Downloads the rocup script into $ROCUP_HOME, installs the
# latest Roc nightly, and creates symlinks for rocup, roc, and
# roc_language_server in $ROCUP_PREFIX. Designed to be safe to pipe from curl:
#
#   curl -fsSL https://raw.githubusercontent.com/imclerran/rocup/main/install.sh | sh
#
# Reads the confirmation from /dev/tty so it works even when stdin is a pipe.
# Set ROCUP_ASSUME_YES=1 to skip the prompt (e.g. in CI).

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

cat <<EOF
This will install rocup:
  * Download the latest Roc nightly into $ROCUP_HOME
  * Create symlinks for rocup, roc, and roc_language_server in $ROCUP_PREFIX
    (sudo may be required to write to that directory)

EOF

if [ "${ROCUP_ASSUME_YES:-}" = "1" ]; then
    :
elif [ -r /dev/tty ]; then
    printf "Proceed? [Y/n] " > /dev/tty
    reply=""
    read -r reply < /dev/tty || reply=""
    case "$reply" in
        n|N|no|NO|No) echo "aborted." >&2; exit 1 ;;
        *) ;;
    esac
else
    echo "error: no tty available; set ROCUP_ASSUME_YES=1 to install non-interactively" >&2
    exit 1
fi

mkdir -p "$ROCUP_HOME"
echo ".. downloading rocup from $RAW_URL"
curl -fsSL "$RAW_URL" -o "$ROCUP_HOME/rocup"
chmod +x "$ROCUP_HOME/rocup"
echo ".. installed rocup at $ROCUP_HOME/rocup"

ROCUP_ASSUME_YES=1 ROCUP_HOME="$ROCUP_HOME" ROCUP_PREFIX="$ROCUP_PREFIX" \
    exec "$ROCUP_HOME/rocup" latest
