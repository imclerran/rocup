#!/bin/sh
# rocup installer. Downloads the rocup script into $ROCUP_HOME, installs the
# latest Roc nightly, and links rocup, roc, and roc_language_server in
# $ROCUP_HOME/bin. Designed to be safe to pipe from curl:
#
#   curl -fsSL https://raw.githubusercontent.com/imclerran/rocup/main/install.sh | sh
#
# Reads confirmations from /dev/tty so it works even when stdin is a pipe.
# Set ROCUP_ASSUME_YES=1 to skip the prompts (e.g. in CI) and
# ROCUP_NO_MODIFY_PATH=1 to leave your shell profile alone.

set -eu

REPO="${ROCUP_REPO:-imclerran/rocup}"
BRANCH="${ROCUP_BRANCH:-main}"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/rocup"

ROCUP_HOME="${ROCUP_HOME:-$HOME/.rocup}"
BIN_DIR="${ROCUP_PREFIX:-$ROCUP_HOME/bin}"

if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is required" >&2
    exit 1
fi

# ask <prompt> <default y|n>: reads from /dev/tty; returns 0 for yes.
ask() {
    if [ "${ROCUP_ASSUME_YES:-}" = "1" ]; then
        return 0
    fi
    if [ ! -r /dev/tty ]; then
        echo "error: no tty available; set ROCUP_ASSUME_YES=1 to install non-interactively" >&2
        exit 1
    fi
    printf "%s " "$1" > /dev/tty
    reply=""
    read -r reply < /dev/tty || reply=""
    case "$reply" in
        y|Y|yes|YES|Yes) return 0 ;;
        n|N|no|NO|No) return 1 ;;
        *) [ "$2" = y ] ;;
    esac
}

cat <<MSG
This will install rocup:
  * Download the latest Roc nightly into $ROCUP_HOME
  * Link rocup, roc, and roc_language_server in $BIN_DIR
  * Offer to add $BIN_DIR to PATH in your shell profile

MSG
ask "Proceed? [Y/n]" y || { echo "aborted." >&2; exit 1; }

mkdir -p "$ROCUP_HOME"
echo ".. downloading rocup from $RAW_URL"
curl -fsSL "$RAW_URL" -o "$ROCUP_HOME/rocup"
chmod +x "$ROCUP_HOME/rocup"
echo ".. installed rocup at $ROCUP_HOME/rocup"

# Profile line. Keep $HOME symbolic when the bin dir is the default so the
# profile stays portable across machines.
if [ "$BIN_DIR" = "$HOME/.rocup/bin" ]; then
    path_dir='$HOME/.rocup/bin'
else
    path_dir="$BIN_DIR"
fi
line="export PATH=\"$path_dir:\$PATH\""

# add_path_line <file> <line>: appends the line behind a marker if missing.
add_path_line() {
    if [ -f "$1" ] && grep -Fxq "$2" "$1"; then
        return 0
    fi
    mkdir -p "$(dirname "$1")"
    printf '\n# rocup\n%s\n' "$2" >> "$1"
    echo ".. added $BIN_DIR to PATH in $1"
}

restart_note=0
case ":$PATH:" in
    *":$BIN_DIR:"*) on_path=1 ;;
    *) on_path=0 ;;
esac
if [ "$on_path" = 0 ] && [ "${ROCUP_NO_MODIFY_PATH:-}" != "1" ]; then
    case "$(basename "${SHELL:-}")" in
        bash)
            files="$HOME/.bashrc"
            # macOS terminals open login shells, which read .bash_profile.
            [ "$(uname)" != Darwin ] || files="$files $HOME/.bash_profile"
            ;;
        zsh)  files="${ZDOTDIR:-$HOME}/.zshrc" ;;
        fish)
            files="$HOME/.config/fish/config.fish"
            line="set -gx PATH \"$path_dir\" \$PATH"
            ;;
        *)    files="" ;;
    esac
    if [ -z "$files" ]; then
        echo ".. could not detect your shell; add $BIN_DIR to PATH yourself:"
        echo "     $line"
    elif ask ".. add $BIN_DIR to PATH in $files? [Y/n]" y; then
        for f in $files; do add_path_line "$f" "$line"; done
        restart_note=1
    else
        echo ".. skipped; add $BIN_DIR to PATH yourself:"
        echo "     $line"
    fi
fi

# Expose the bin dir to this run so rocup itself stays quiet about PATH.
PATH="$BIN_DIR:$PATH"
export PATH
ROCUP_ASSUME_YES=1 ROCUP_HOME="$ROCUP_HOME" ROCUP_PREFIX="$BIN_DIR" "$ROCUP_HOME/rocup" latest

echo
if [ "$restart_note" = 1 ]; then
    echo "Installed. Restart your shell (or run: $line), then run 'rocup' to verify."
else
    echo "Installed. Run 'rocup' to verify."
fi
