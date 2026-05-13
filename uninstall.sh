#!/bin/sh
# rocup uninstaller. Designed to be safe to pipe from curl:
#
#   curl -fsSL https://raw.githubusercontent.com/imclerran/rocup/main/uninstall.sh | sh
#
# Mirrors install.sh's prompt behavior: reads from /dev/tty when stdin is a
# pipe, errors if no tty available and ROCUP_ASSUME_YES is not set. Defaults
# to abort on empty reply since uninstall is destructive.

set -eu

ROCUP_HOME="${ROCUP_HOME:-$HOME/.rocup}"
ROCUP_PREFIX="${ROCUP_PREFIX:-/usr/local/bin}"

cat <<EOF
This will uninstall rocup:
  * Remove rocup, roc, and roc_language_server from $ROCUP_PREFIX
    (only if they point into $ROCUP_HOME; sudo may be required)
  * Delete $ROCUP_HOME (including all installed Roc versions and local-* symlinks;
    'local-*' entries are symlinks, so their source directories are NOT touched)

EOF

if [ ! -d "$ROCUP_HOME" ]; then
    echo "note: $ROCUP_HOME does not exist; will still clean up any stale $ROCUP_PREFIX symlinks."
    echo
fi

if [ "${ROCUP_ASSUME_YES:-}" = "1" ]; then
    :
elif [ -r /dev/tty ]; then
    printf "Proceed? [y/N] " > /dev/tty
    reply=""
    read -r reply < /dev/tty || reply=""
    case "$reply" in
        y|Y|yes|YES|Yes) ;;
        *) echo "aborted." >&2; exit 1 ;;
    esac
else
    echo "error: no tty available; set ROCUP_ASSUME_YES=1 to uninstall non-interactively" >&2
    exit 1
fi

# 1. Remove a symlink in $ROCUP_PREFIX if it points into $ROCUP_HOME.
# Conservative: only removes links rocup created. Leaves anything else alone.
remove_prefix_link() {
    link="$1"
    if [ ! -L "$link" ] && [ ! -f "$link" ]; then
        return 0
    fi
    # If it's a symlink, only remove if it points into $ROCUP_HOME.
    # If it's a regular file (the roc_language_server shim is a real script,
    # not a symlink), only remove if it mentions $ROCUP_HOME — meaning rocup
    # installed it.
    if [ -L "$link" ]; then
        target=$(readlink "$link")
        case "$target" in
            "$ROCUP_HOME"/*) ;;
            *) return 0 ;;
        esac
    elif [ -f "$link" ]; then
        if ! grep -q "ROCUP_HOME" "$link" 2>/dev/null; then
            return 0
        fi
    fi
    sudo=sudo
    if [ -w "$(dirname "$link")" ]; then
        sudo=""
    fi
    $sudo rm -f "$link"
    echo ".. removed $link"
}

remove_prefix_link "$ROCUP_PREFIX/rocup"
remove_prefix_link "$ROCUP_PREFIX/roc"
remove_prefix_link "$ROCUP_PREFIX/roc_language_server"

# 2. Delete $ROCUP_HOME.
# 'rm -rf' on a directory containing symlinks deletes the symlinks themselves,
# not their targets (POSIX behavior). So local-* symlinks pointing at user
# source directories outside $ROCUP_HOME are safe; we only break the link.
if [ -d "$ROCUP_HOME" ] || [ -L "$ROCUP_HOME" ]; then
    rm -rf "$ROCUP_HOME"
    echo ".. deleted $ROCUP_HOME"
fi

echo
echo "Uninstalled."
