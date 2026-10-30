#!/bin/bash
# Offline: install.sh's shell-profile handling across shells and opt-outs.
# ROCUP_SCRIPT copies the repo's rocup instead of downloading it, and
# ROCUP_VERSION points at a fake local build, so nothing touches the network.
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
build="$TEST_TMPDIR/build"
mkdir -p "$build"
printf '#!/bin/sh\necho "local roc"\n' > "$build/roc"
chmod +x "$build/roc"

# install <home> <shell> [VAR=value ...]: runs the installer with its own
# HOME and ROCUP_HOME under <home>, echoing the combined output.
install() {
    local home="$1" shell="$2"
    shift 2
    mkdir -p "$home"
    env HOME="$home" SHELL="$shell" ROCUP_HOME="$home/rocup-home" ROCUP_NO_MODIFY_PATH= \
        ROCUP_SCRIPT="$ROCUP" ROCUP_VERSION="$build" "$@" sh "$repo_root/install.sh" 2>&1
}
sh_line()   { echo "export PATH=\"$1/rocup-home/bin:\$PATH\""; }
fish_line() { echo "set -gx PATH \"$1/rocup-home/bin\" \$PATH"; }

# bash: .bashrc gets the marker and line; .bash_profile only on macOS.
h="$TEST_TMPDIR/h-bash"
out=$(install "$h" /bin/bash)
assert_contains "$out" "Restart your shell" 'bash: restart hint after editing the profile'
grep -Fxq "$(sh_line "$h")" "$h/.bashrc" || { echo "FAIL: bash: PATH line missing" >&2; cat "$h/.bashrc" >&2; exit 1; }
grep -Fxq '# rocup' "$h/.bashrc"          || { echo "FAIL: bash: marker missing" >&2; exit 1; }
if [ "$(uname)" = Darwin ]; then
    grep -Fxq "$(sh_line "$h")" "$h/.bash_profile" || { echo "FAIL: bash on macOS: .bash_profile not updated" >&2; exit 1; }
else
    [ ! -e "$h/.bash_profile" ] || { echo "FAIL: bash on Linux: .bash_profile was created" >&2; exit 1; }
fi

# Repeat install: no duplicate line, no restart hint.
out=$(install "$h" /bin/bash)
assert_eq 1 "$(grep -Fxc "$(sh_line "$h")" "$h/.bashrc")" 'bash: repeat install adds no duplicate'
! printf '%s' "$out" | grep -q "Restart your shell" || { echo "FAIL: bash: restart hint on repeat install" >&2; exit 1; }
assert_contains "$out" "Installed. Run 'rocup' to verify." 'bash: plain done message on repeat'

# fish: its own syntax, in config.fish.
h="$TEST_TMPDIR/h-fish"
out=$(install "$h" /usr/bin/fish)
grep -Fxq "$(fish_line "$h")" "$h/.config/fish/config.fish" || { echo "FAIL: fish: PATH line missing" >&2; exit 1; }
assert_contains "$out" "$(fish_line "$h")" 'fish: restart hint uses fish syntax'

# Unknown shell: instructions only, nothing written.
h="$TEST_TMPDIR/h-tcsh"
out=$(install "$h" /bin/tcsh)
assert_contains "$out" "could not detect your shell" 'unknown shell: warning shown'
assert_contains "$out" "$(sh_line "$h")" 'unknown shell: line to add shown'
[ "$(ls -A "$h")" = "rocup-home" ] || { echo "FAIL: unknown shell: wrote a profile: $(ls -A "$h")" >&2; exit 1; }

# Opt-out: no profile edit.
h="$TEST_TMPDIR/h-optout"
out=$(install "$h" /bin/zsh ROCUP_NO_MODIFY_PATH=1)
[ ! -e "$h/.zshrc" ] || { echo "FAIL: opt-out: .zshrc was written" >&2; exit 1; }
assert_contains "$out" "Installed. Run 'rocup' to verify." 'opt-out: plain done message'

# Already on PATH: no profile edit.
h="$TEST_TMPDIR/h-onpath"
mkdir -p "$h"
out=$(install "$h" /bin/zsh PATH="$h/rocup-home/bin:$PATH")
[ ! -e "$h/.zshrc" ] || { echo "FAIL: already on PATH: .zshrc was written" >&2; exit 1; }
assert_contains "$out" "Installed. Run 'rocup' to verify." 'already on PATH: plain done message'

# Default ROCUP_HOME: the line keeps $HOME symbolic, and uninstall removes it.
h="$TEST_TMPDIR/h-default"
mkdir -p "$h"
env -u ROCUP_HOME HOME="$h" SHELL=/bin/zsh ROCUP_NO_MODIFY_PATH= ROCUP_SCRIPT="$ROCUP" ROCUP_VERSION="$build" \
    sh "$repo_root/install.sh" >/dev/null 2>&1
grep -Fxq 'export PATH="$HOME/.rocup/bin:$PATH"' "$h/.zshrc" || { echo "FAIL: default home: symbolic PATH line missing" >&2; cat "$h/.zshrc" >&2; exit 1; }
[ -L "$h/.rocup/bin/roc" ] || { echo "FAIL: default home: bin/roc missing" >&2; exit 1; }
env -u ROCUP_HOME HOME="$h" sh "$repo_root/uninstall.sh" >/dev/null 2>&1
[ ! -d "$h/.rocup" ] || { echo "FAIL: default home: ~/.rocup survived uninstall" >&2; exit 1; }
! grep -q rocup "$h/.zshrc" || { echo "FAIL: default home: PATH line survived uninstall" >&2; cat "$h/.zshrc" >&2; exit 1; }

pass
