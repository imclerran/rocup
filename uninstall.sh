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
BIN_DIR="${ROCUP_PREFIX:-$ROCUP_HOME/bin}"
# Where installs that predate $ROCUP_HOME/bin put their links.
LEGACY_BIN="${ROCUP_LEGACY_BIN:-/usr/local/bin}"

cat <<MSG
This will uninstall rocup:
  * Delete $ROCUP_HOME (including all installed Roc versions and local-* symlinks;
    'local-*' entries are symlinks, so their source directories are NOT touched)
  * Remove the PATH line rocup added to your shell profile, if any
  * Remove rocup, roc, and roc_language_server from $LEGACY_BIN if an older
    install left them there (only if they point into $ROCUP_HOME; sudo may be required)

MSG

if [ ! -d "$ROCUP_HOME" ]; then
    echo "note: $ROCUP_HOME does not exist; will still clean up any stale links and PATH entries."
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

# 1. Remove a link in a bin dir if it points into $ROCUP_HOME.
# Conservative: only removes entries rocup created. Leaves anything else alone.
remove_bin_link() {
    link="$1"
    if [ ! -L "$link" ] && [ ! -f "$link" ]; then
        return 0
    fi
    # Symlinks must point into $ROCUP_HOME. The roc_language_server shim is a
    # real script, so for a regular file require that it mentions ROCUP_HOME.
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

for dir in "$LEGACY_BIN" "$BIN_DIR"; do
    case "$dir" in "$ROCUP_HOME"/*) continue ;; esac   # deleted with $ROCUP_HOME below
    remove_bin_link "$dir/rocup"
    remove_bin_link "$dir/roc"
    remove_bin_link "$dir/roc_language_server"
done

# 2. Remove the PATH line install.sh added (plus its '# rocup' marker).
if [ "$BIN_DIR" = "$HOME/.rocup/bin" ]; then
    path_dir='$HOME/.rocup/bin'
else
    path_dir="$BIN_DIR"
fi
remove_path_line() {
    file="$1"
    [ -f "$file" ] || return 0
    grep -Fxq "$2" "$file" || return 0
    tmp=$(mktemp "${TMPDIR:-/tmp}/rocup-rc.XXXXXX")
    grep -Fxv -e '# rocup' -e "$2" "$file" > "$tmp" || true
    cat "$tmp" > "$file"
    rm -f "$tmp"
    echo ".. removed PATH entry from $file"
}
sh_line="export PATH=\"$path_dir:\$PATH\""
for f in "$HOME/.bashrc" "$HOME/.bash_profile" "${ZDOTDIR:-$HOME}/.zshrc"; do
    remove_path_line "$f" "$sh_line"
done
remove_path_line "$HOME/.config/fish/config.fish" "set -gx PATH \"$path_dir\" \$PATH"

# 3. Delete $ROCUP_HOME.
# 'rm -rf' on a directory containing symlinks deletes the symlinks themselves,
# not their targets (POSIX behavior). So local-* symlinks pointing at user
# source directories outside $ROCUP_HOME are safe; we only break the link.
if [ -d "$ROCUP_HOME" ] || [ -L "$ROCUP_HOME" ]; then
    rm -rf "$ROCUP_HOME"
    echo ".. deleted $ROCUP_HOME"
fi

echo
echo "Uninstalled."
