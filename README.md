# rocup

[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

A version manager for the [Roc](https://github.com/roc-lang/roc) compiler — installs, switches between, and prunes Roc releases (`alpha4-rolling`, zig compiler nightlies, and local development builds) under `~/.rocup`, and wires up `roc` and `roc_language_server` so the active version is always on your `PATH`.

## Quick Start
### **Install**

**macOS / Linux**

```sh
curl -fsSL https://raw.githubusercontent.com/imclerran/rocup/main/install.sh | sh
```

**Windows (PowerShell)**

```ps1
iwr -useb https://raw.githubusercontent.com/imclerran/rocup/main/install.ps1 | iex
```

Both installers prompt for confirmation before downloading anything. Set `ROCUP_ASSUME_YES=1` (or `$env:ROCUP_ASSUME_YES = '1'` on Windows) to skip the prompt in CI. On Windows, restart your terminal afterward so PATH updates take effect.

### **Uninstall**

```sh
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/imclerran/rocup/main/uninstall.sh | sh
```

```ps1
# Windows
iwr -useb https://raw.githubusercontent.com/imclerran/rocup/main/uninstall.ps1 | iex
```

Uninstalling removes `rocup`'s install root and PATH entries but does not touch the source directories behind any `local-*` registrations.

## Usage

```
rocup [alpha4 | latest | <hash> | <path> | +N | -N | list | remove <ver> | prune <N>]
```

| Command | What it does |
|---|---|
| `rocup alpha4` | Install/activate the `alpha4-rolling` release from `roc-lang/roc`. |
| `rocup latest` | Install/activate the most recent nightly from `roc-lang/nightlies`. This is the default if no argument is given. |
| `rocup <hash>` | 7- or 8-char hex (8-char matches the output of `roc --version`, and is truncated to 7 to look up GitHub releases). If a local install with that hash is registered, activate it. Otherwise activate the matching nightly (downloading it if necessary). |
| `rocup <path>` | Register a local `roc` build as `local-<hash>` and activate it. Path is a directory containing `roc` (and optionally `roc_language_server`); on macOS/Linux it may also point directly at a `roc` binary. Registration is by symlink (NTFS junction on Windows), not copy. |
| `rocup +N` / `rocup -N` | Step `N` nightlies newer (`+`) or older (`-`) than the active one. Resolves against the `roc-lang/nightlies` release timeline, falling back to installed nightlies only when offline. Requires the active version to be a nightly. |
| `rocup list` | Show installed versions, oldest first, with the active version marked `->`. Local entries also show their resolved path. |
| `rocup remove <ver>` | Delete a version — `alpha4`, a 7- or 8-char hash, or `local-<hash>`. A bare hash resolves to a registered local first, otherwise a nightly. If the removed version was active, the most recent remaining one becomes active. Removing a local only drops the registration; the actual source files are untouched. |
| `rocup prune <N>` | Keep the `N` most recent nightlies; delete older ones. `alpha4` and local registrations are exempt. The active nightly is always kept. |

### Examples

```sh
rocup                        # install/activate the latest nightly
rocup alpha4                 # switch to the alpha4-rolling release
rocup a1b2c3d                # activate (or download) nightly a1b2c3d
rocup ~/src/roc/zig-out/bin  # register and activate a local dev build
rocup -1                     # step back to the previous nightly
rocup +2                     # step forward two nightlies from active
rocup list                   # see what's installed
rocup remove a1b2c3d         # remove a specific version
rocup prune 5                # keep the 5 most recent nightlies
```

## Platform support

- macOS (Apple Silicon and x86_64)
- Linux (x86_64 and arm64/aarch64)
- Windows (x86_64 and arm64)

The Windows port covers nightlies and local-directory builds but diverges from the macOS/Linux build in a couple of places:

| Capability | macOS/Linux | Windows |
|---|:---:|:---:|
| `alpha4` release | yes | no (no Windows binary upstream) |
| Cross-volume local builds | yes | no (junctions require same volume) |

See [FEATURE_MATRIX.md](FEATURE_MATRIX.md) for the full per-platform capability table.

## Manual install (macOS / Linux)

```sh
git clone https://github.com/imclerran/rocup.git
cd rocup
./rocup
```

After a successful install:

- `~/.rocup/` holds every installed version in its own directory.
- `~/.rocup/roc` is a symlink to the currently active version.
- `/usr/local/bin/roc` points at `~/.rocup/roc/roc`.
- `/usr/local/bin/roc_language_server` is a shim that resolves the LS for whichever `roc` is active (either a bundled `roc_language_server` binary, or `roc experimental-lsp` if the active version supports it).

## Credits

Inspired by and adapted from [appblue/rocup](https://github.com/appblue/rocup). Credit to the original for the core idea; this version targets the new Zig-based Roc compiler, adds support for the `alpha4-rolling` release and local development builds, and includes commands for listing, removing, and pruning installed versions.
