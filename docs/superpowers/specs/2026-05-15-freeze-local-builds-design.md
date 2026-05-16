# Freeze local builds — design

Date: 2026-05-15
Status: approved (design)

## Problem

`rocup` registers a local Roc build as `local-<hash>`, where the entry under `~/.rocup` is a symlink (junction on Windows) back to the user's build tree. If the user rebuilds, runs `cargo clean`, moves the source directory, or switches branches, the live link breaks — there is no way to preserve a particular local build for later use.

The user wants to snapshot a known-good local build into `~/.rocup` as a real, self-contained directory, and label it with a human-chosen name so it shows up alongside nightlies in `rocup list` with a meaningful identifier instead of just a path hash.

## Goals

- A `rocup freeze <name>` command that copies the currently-active local build's binaries into `~/.rocup/frozen-<name>/` as real files.
- The frozen entry survives changes to the original source directory and is treated as a long-lived, user-curated version (exempt from `prune`).
- The frozen entry is addressable through the existing `rocup <ver>` / `rocup remove <ver>` commands using either its full name (`frozen-<name>`) or, when unambiguous, the bare `<name>`.

## Non-goals

- Renaming an existing frozen entry. (Would need a separate `rocup rename` command.)
- Freezing nightlies or the `alpha4-rolling` release. Only local builds are eligible.
- Capturing build metadata (source path, date, original hash) in a sidecar file. Could be added later if `list` output needs more context.

## Command surface

```
rocup freeze <name> [--force]
```

### Preconditions
- An active version must exist.
- The active version must be a `local-<hash>` entry. Otherwise: error.

### Name validation
- `<name>` matches `^[a-zA-Z0-9._-]+$`.
- `<name>` must not start with `frozen-` (the prefix is added by `rocup`; including it in the user input is rejected).
- `<name>` must not exactly equal the hash of any currently-installed nightly or registered local. (Names that merely *look* like hex but don't collide with anything installed are allowed.)

### Resolution and copy
1. Read the active pointer at `~/.rocup/roc`.
2. Verify the target's basename matches `local-[0-9a-f]{7}`.
3. Resolve the local entry through the existing `local_install_path` / `Get-LocalInstallPath` helper to find the real build directory.
4. Verify `roc` exists in that directory.
5. Create `~/.rocup/frozen-<name>/`.
6. Copy `roc` into the new directory, dereferencing symlinks and preserving the executable bit.
7. On macOS/Linux only: if `roc_language_server` is present alongside `roc`, copy it too (also dereferenced).
8. Activate `frozen-<name>` using the existing `activate` / `Set-ActiveVersion` helper.

The original `local-<hash>` registration is **not** removed. After freeze:
- `~/.rocup/frozen-<name>/` is a real directory with copied binaries.
- `~/.rocup/local-<hash>` is still a symlink/junction to the source tree.
- `~/.rocup/roc` now points at `frozen-<name>`.

### Collision (`frozen-<name>` already exists)
- Without `--force`: error `freeze: frozen-<name> already exists. Use --force to overwrite.` (exit 1)
- With `--force`: remove the existing `frozen-<name>` directory, then proceed.

### Platform notes
- **Windows:** copy only `roc.exe`. There is never a `roc_language_server.exe` to copy; the LS shim invokes `roc experimental-lsp`.
- **macOS/Linux:** copy `roc`, and `roc_language_server` if present.

## Interactions with existing commands

### `rocup list`
Frozen entries display as `frozen-<name>` with build date (mtime of the copied `roc` binary), shown in a separate alphabetical group after nightlies and locals. The active marker `->` works the same way.

### `rocup <ver>` (activate)
Resolution order, in priority:
1. `alpha4` / `latest` / `local` keywords (existing)
2. `local-<hash>` literal prefix (existing)
3. `frozen-<name>` literal prefix *(new)*
4. 7-or-8-char hex hash → local-by-hash, then nightly (existing)
5. Bare `<X>` → try `frozen-<X>` if it exists *(new)*
6. Treat as a path → register and activate (existing fall-through)

### `rocup remove <ver>`
Resolution order:
1. `alpha4` (existing)
2. `local-<hash>` literal prefix (existing)
3. `frozen-<name>` literal prefix *(new)*
4. 7-or-8-char hex hash → local, then nightly (existing)
5. Bare `<X>` → try `frozen-<X>` if it exists *(new)*
6. Else error.

Frozen entries are deleted with a recursive directory remove (`rm -rf` / `Remove-Item -Recurse`) since they are real directories, not symlinks.

If the removed frozen entry was active, the fallback chain becomes:
```
most-recent nightly → alpha4 → most-recent local → most-recent frozen
```

### `rocup prune <N>`
Unchanged in scope: only `roc_nightly-*` entries are eligible. `frozen-*` entries are exempt, identical to how `alpha4` and `local-*` are treated today.

### `rocup +N` / `rocup -N`
Unchanged. Requires the active version to be a nightly; errors if the active version is `alpha4`, `local-*`, or `frozen-*`.

### `rocup local`
Unchanged. Activates a `local-*` entry; ignores `frozen-*`.

## Error cases

| Condition | Exit message |
|---|---|
| No active version | `freeze: no active version` |
| Active not a local | `freeze: active version is <X>; freeze requires an active local build` |
| Local registration dangling | `freeze: cannot resolve active local <X>; the source directory may have been moved or deleted` |
| `roc` not found in resolved dir | `freeze: roc binary not found in <path>` |
| Invalid name characters | `freeze: invalid name '<name>'; allowed characters: a-z A-Z 0-9 . _ -` |
| Name starts with `frozen-` | `freeze: do not include the 'frozen-' prefix in the name` |
| Name equals an installed hash | `freeze: name '<name>' conflicts with an existing version hash; choose another name` |
| Target exists, no `--force` | `freeze: frozen-<name> already exists. Use --force to overwrite.` |

All errors exit 1.

## Implementation sketch

### Bash (`rocup`)

New helpers:
- `validate_freeze_name "$name"` — charset + leading-prefix + hash-collision checks.
- `do_freeze "$@"` — parses `<name>` and optional `--force`; runs the resolve/verify/copy/activate sequence.

Extensions:
- `do_list` regex group extended to recognize `frozen-*` with its own display branch (reuses the `roc`-mtime logic from the local display).
- `remove_version` gets a literal `frozen-<name>` branch (recursive remove) and a "try `frozen-<X>`" fallback at the bottom of its resolution.
- Activation resolver in the main dispatch gets the same "try `frozen-<X>`" fallback before the path-registration fall-through.
- Fallback chain in `remove_version` extended to consider frozen entries last.
- Top-level dispatch gets `freeze) do_freeze "$@";;`.

### PowerShell (`rocup.ps1`)

Mirror set:
- `Test-FreezeName` and `Invoke-Freeze` (parallel to the bash helpers).
- Extensions to `Invoke-List`, `Remove-Version`, `Get-FallbackVersion`, and the `switch -Regex` dispatch in `Invoke-Rocup`.

Copy uses `Copy-Item -LiteralPath <src> -Destination <dst> -Force`. Source resolution goes through the existing junction-target helpers so the copy reads the real source files, not the junction. Only `roc.exe` is copied.

### Help / usage strings

Both scripts' `usage` output gets `freeze <name>` added to the synopsis and the command table. The `--force` flag is mentioned in the long help.

## Documentation updates

- **`README.md`:** Add `freeze <name>` to the command table and add a usage example to the Examples block. Add a short bullet to the post-install layout list noting that frozen entries are real directories under `~/.rocup`.
- **`FEATURE_MATRIX.md`:** Add a row for `freeze <name>` showing `yes` for both macOS/Linux and Windows. (No platform divergence — Windows simply omits the LS copy, which is consistent with the existing "Standalone `roc_language_server` binary dispatch" row.)
- **`test/drift-check.sh`:** No change needed if the command is added to both scripts; the drift check enforces parity automatically.

## Testing

Test cases (mirroring the existing `test/` style):
- Freeze from a directory-mode local; verify `frozen-<name>/roc` is a real file (not a symlink), the active pointer moved, and the original `local-<hash>` registration is still present.
- Freeze from a file-mode local (macOS/Linux only); verify only `roc` was copied (no LS).
- Freeze with `--force` over an existing `frozen-<name>`.
- Activate via `rocup frozen-<name>` and via bare `rocup <name>`.
- Remove via `rocup remove frozen-<name>` and via bare `rocup remove <name>`.
- `rocup list` shows the entry with correct kind label and date.
- `rocup prune 0` leaves frozen entries untouched.
- Error cases: no active version, non-local active, dangling local, invalid name characters, name starting with `frozen-`, name colliding with an installed hash, collision without `--force`.
- Windows: parallel PowerShell coverage; LS copy is not exercised since it doesn't exist on Windows.

## File-level change summary

| File | Change |
|---|---|
| `rocup` | New `do_freeze` + `validate_freeze_name`; extensions to `do_list`, `remove_version`, activate dispatch, fallback chain, usage string, top-level `case` |
| `rocup.ps1` | New `Invoke-Freeze` + `Test-FreezeName`; extensions to `Invoke-List`, `Remove-Version`, `Get-FallbackVersion`, `Invoke-Rocup` dispatch, usage string |
| `README.md` | Add `freeze <name>` row + example |
| `FEATURE_MATRIX.md` | Add `freeze <name>` row |
| `test/` | New test cases per the list above |
