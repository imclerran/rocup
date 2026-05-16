# Freeze local builds — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `rocup freeze <name>` which copies the currently-active local Roc build into `~/.rocup/frozen-<name>/` as a real directory, and extend `list`, activation, and `remove` to address frozen entries by `frozen-<name>` or bare `<name>`.

**Architecture:** Both `rocup` (bash) and `rocup.ps1` (PowerShell) gain a new top-level subcommand `freeze`, two new helpers (validation + core freeze), and small extensions to existing list/remove/activate code paths. No new external dependencies. Tests follow the existing `test/linux-macos/*.sh` and `test/windows/*.ps1` per-script convention.

**Tech Stack:** bash 3.2+, PowerShell 5.1+, GNU/BSD coreutils, standard shell test harness already in `test/common/lib.sh` and `test/common/lib.ps1`.

**Spec reference:** `docs/superpowers/specs/2026-05-15-freeze-local-builds-design.md`

---

## File Structure

**Modified:**
- `rocup` — new `validate_freeze_name`, `do_freeze`; extensions to `do_list`, `remove_version`, top-level dispatch, `usage`. (~120 lines added)
- `rocup.ps1` — new `Test-FreezeName`, `Invoke-Freeze`; extensions to `Invoke-List`, `Remove-Version`, `Get-FallbackVersion`, `Invoke-Rocup` dispatch, `Show-Usage`. (~120 lines added)
- `README.md` — add `freeze <name>` row to the command table and one Examples line.
- `FEATURE_MATRIX.md` — add `freeze <name>` row.
- `test/drift-check.sh` — add `REQUIRED_PHRASES` entries for the `freeze` description so future reword drift is caught.

**Created:**
- `test/linux-macos/17-freeze-basic.sh` — happy path; verifies real-file copy, active switch, original local preserved.
- `test/linux-macos/18-freeze-validation.sh` — all error paths (preconditions, name validation, collision-without-force).
- `test/linux-macos/19-freeze-force.sh` — `--force` overwrites an existing frozen entry.
- `test/linux-macos/20-freeze-addressing.sh` — activate and remove via both `frozen-<name>` and bare `<name>`.
- `test/linux-macos/21-freeze-fallback.sh` — fallback chain in `remove_version` includes frozen entries.
- `test/linux-macos/22-freeze-with-ls.sh` — freezing a dir-mode local that has a `roc_language_server` copies both binaries.
- `test/linux-macos/23-freeze-file-mode.sh` — freezing a file-mode local copies only `roc`, even if an LS exists in the source dir.
- `test/windows/18-freeze-basic.ps1` — Windows mirror of basic test (no LS).
- `test/windows/19-freeze-validation.ps1`
- `test/windows/20-freeze-force.ps1`
- `test/windows/21-freeze-addressing.ps1`
- `test/windows/22-freeze-fallback.ps1`

---

## Build order (one phase per file/concept; bash side first, then PowerShell mirror, then docs/drift)

---

### Task 1: Bash — `validate_freeze_name` helper

**Files:**
- Modify: `rocup` (add helper near `register_local`, around line ~924)
- Create: `test/linux-macos/18-freeze-validation.sh` (covers Tasks 1+3+freeze errors)

This task adds *only* the validator function and a minimal test that calls it via a tiny shell harness. (The full `freeze` command lands in Task 3; we don't wire it up here.)

- [ ] **Step 1: Write the failing test (validator-only smoke check inside the freeze validation file)**

Create `test/linux-macos/18-freeze-validation.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Make a fake local active so freeze's preconditions pass.
local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "local roc"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1

# 1. Empty name rejected.
assert_exit_code 1 "empty name rejected" -- "$ROCUP" freeze ""

# 2. Bad characters rejected.
assert_exit_code 1 "spaces rejected"  -- "$ROCUP" freeze "has space"
assert_exit_code 1 "slash rejected"   -- "$ROCUP" freeze "a/b"

# 3. Name starting with frozen- rejected.
assert_exit_code 1 "leading frozen- rejected" -- "$ROCUP" freeze "frozen-foo"

# 4. Name colliding with the active local's hash rejected.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
active_hash="${active#local-}"
assert_exit_code 1 "hash-collision rejected" -- "$ROCUP" freeze "$active_hash"

# 5. Collision-without-force: pre-create the target dir.
mkdir -p "$ROCUP_HOME/frozen-already-there"
touch "$ROCUP_HOME/frozen-already-there/roc"
assert_exit_code 1 "exists-no-force rejected" -- "$ROCUP" freeze "already-there"

pass
```

- [ ] **Step 2: Run test to confirm it fails (freeze subcommand doesn't exist yet)**

Run: `bash test/linux-macos/18-freeze-validation.sh`
Expected: FAIL (one of the early `assert_exit_code` calls reports an unexpected exit code — typically the script falls through to the path-dispatch branch and exits with `error: invalid argument 'freeze'`).

- [ ] **Step 3: Add the validator helper in `rocup`**

Insert this function in `rocup` immediately above `register_local` (so it lives near line 924). Do not yet wire it into a `do_freeze` function — that arrives in Task 3:

```bash
# validate_freeze_name <name>
# Returns 0 if <name> is a legal frozen-<name> suffix. Otherwise echoes an
# error to stderr and returns 1. Rules (per design spec):
#   - non-empty, matches ^[a-zA-Z0-9._-]+$
#   - does not start with 'frozen-' (the prefix is added by rocup)
#   - does not collide with any installed nightly hash or registered local hash
validate_freeze_name() {
    local name="$1"
    if [ -z "$name" ]; then
        echo "freeze: name is required" >&2
        return 1
    fi
    if ! [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "freeze: invalid name '$name'; allowed characters: a-z A-Z 0-9 . _ -" >&2
        return 1
    fi
    case "$name" in
        frozen-*)
            echo "freeze: do not include the 'frozen-' prefix in the name" >&2
            return 1
            ;;
    esac
    # Hash-collision check: only reject names that match an actually-installed
    # 7-char hash (registered local OR installed nightly). 'roc --version'-style
    # 8-char hashes are not rejected here; if a user types an 8-char name, the
    # 7-char prefix is what would collide, but 8-char names with no 7-char
    # equivalent installed pass through. The charset rule already covers
    # everything except hex collisions.
    if [[ "$name" =~ ^[0-9a-f]{7}$ ]]; then
        if [ -e "$ROCUP_HOME/local-$name" ] || [ -L "$ROCUP_HOME/local-$name" ]; then
            echo "freeze: name '$name' conflicts with an existing version hash; choose another name" >&2
            return 1
        fi
        if [ -n "$(find_nightly_dir "$name")" ]; then
            echo "freeze: name '$name' conflicts with an existing version hash; choose another name" >&2
            return 1
        fi
    fi
    return 0
}
```

- [ ] **Step 4: Add a stub `freeze` dispatch case so the test exits 1 cleanly**

Edit the top-level `case "$cmd" in` block in `rocup` (around line 1100). Insert this case **before** the `*)` default branch:

```bash
    freeze)
        shift
        # Detailed implementation lands in Task 3. For now, validator-only stub.
        force=0
        name=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --force) force=1; shift ;;
                --) shift; name="${1:-}"; shift || true ;;
                -*) echo "freeze: unknown option '$1'" >&2; exit 1 ;;
                *) name="$1"; shift ;;
            esac
        done
        validate_freeze_name "$name" || exit 1
        if [ -e "$ROCUP_HOME/frozen-$name" ] && [ "$force" -ne 1 ]; then
            echo "freeze: frozen-$name already exists. Use --force to overwrite." >&2
            exit 1
        fi
        echo "freeze: stub (Task 1) — preconditions ok for '$name'" >&2
        exit 1
        ;;
```

(The stub deliberately still exits 1 — it just gives `assert_exit_code` something predictable while the validator's individual messages are exercised.)

- [ ] **Step 5: Run test to verify it passes**

Run: `bash test/linux-macos/18-freeze-validation.sh`
Expected: `PASS: 18-freeze-validation.sh`

- [ ] **Step 6: Commit**

```bash
git add rocup test/linux-macos/18-freeze-validation.sh
git commit -m "Add validate_freeze_name helper and validation test"
```

---

### Task 2: Bash — verify Task 1 didn't break existing tests

- [ ] **Step 1: Run the full bash test suite**

Run: `for t in test/linux-macos/*.sh; do bash "$t" || exit 1; done`
Expected: all tests print `PASS:` lines; no `FAIL:` lines.

- [ ] **Step 2: If anything failed, fix the regression before continuing**

Most likely culprit: the new `freeze)` case was inserted in the wrong place (e.g., after `*)`) causing it never to match. Move the case branch above `*)`.

---

### Task 3: Bash — `do_freeze` core (resolve active local, copy binaries, activate)

**Files:**
- Modify: `rocup` (add `do_freeze` near the validator; replace the Task-1 stub in the `freeze)` dispatch case)
- Create: `test/linux-macos/17-freeze-basic.sh`

- [ ] **Step 1: Write the failing happy-path test**

Create `test/linux-macos/17-freeze-basic.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Build and register a local roc.
local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "local roc"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1

# Sanity: active should be local-<hash>
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
case "$active" in
    local-*) ;;
    *) echo "FAIL: expected local-* before freeze, got $active" >&2; exit 1 ;;
esac
original_local="$active"

# Freeze it.
"$ROCUP" freeze myfeature >/dev/null

# 1. Active is now frozen-myfeature.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-myfeature" "$active" "active is frozen entry after freeze"

# 2. The frozen entry exists as a real directory (not a symlink).
[ -d "$ROCUP_HOME/frozen-myfeature" ] || { echo "FAIL: frozen-myfeature is not a directory" >&2; exit 1; }
[ -L "$ROCUP_HOME/frozen-myfeature" ] && { echo "FAIL: frozen-myfeature is a symlink" >&2; exit 1; }

# 3. roc inside is a real file (not a symlink) and executable.
[ -f "$ROCUP_HOME/frozen-myfeature/roc" ] || { echo "FAIL: frozen-myfeature/roc missing" >&2; exit 1; }
[ -L "$ROCUP_HOME/frozen-myfeature/roc" ] && { echo "FAIL: frozen-myfeature/roc is a symlink" >&2; exit 1; }
[ -x "$ROCUP_HOME/frozen-myfeature/roc" ] || { echo "FAIL: frozen-myfeature/roc not executable" >&2; exit 1; }

# 4. Contents match the source.
diff "$local_dir/roc" "$ROCUP_HOME/frozen-myfeature/roc" >/dev/null \
    || { echo "FAIL: copied roc differs from source" >&2; exit 1; }

# 5. Original local registration still present.
[ -L "$ROCUP_HOME/$original_local" ] || { echo "FAIL: original local registration was removed" >&2; exit 1; }

# 6. Deleting the source build dir does NOT break the frozen copy.
rm -rf "$local_dir"
[ -x "$ROCUP_HOME/frozen-myfeature/roc" ] || { echo "FAIL: frozen roc broke after source removal" >&2; exit 1; }

pass
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/linux-macos/17-freeze-basic.sh`
Expected: FAIL — `freeze: stub (Task 1) — preconditions ok` appears on stderr and the script exits 1; the very next assertion (active is frozen-myfeature) fails.

- [ ] **Step 3: Add `do_freeze` helper in `rocup`**

Insert in `rocup` immediately below `validate_freeze_name` (so both helpers sit together near line ~960, just above `register_local`):

```bash
# do_freeze <name> [--force]
# Snapshots the currently-active local-<hash> build into $ROCUP_HOME/frozen-<name>/.
# Preconditions: active version exists and is a local-<hash> entry; the local
# entry resolves (not dangling); the resolved dir contains a roc binary.
# Copies roc (and, on macOS/Linux, roc_language_server if present) as real
# files with symlinks dereferenced, then activates frozen-<name>. The original
# local-<hash> registration is left intact.
do_freeze() {
    local name="" force=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1; shift ;;
            --) shift; name="${1:-}"; shift || true ;;
            -*) echo "freeze: unknown option '$1'" >&2; return 1 ;;
            *)
                if [ -n "$name" ]; then
                    echo "freeze: too many arguments (already have name '$name', also got '$1')" >&2
                    return 1
                fi
                name="$1"; shift
                ;;
        esac
    done

    validate_freeze_name "$name" || return 1

    # Precondition: an active version exists.
    if [ ! -L "$ROCUP_HOME/roc" ]; then
        echo "freeze: no active version" >&2
        return 1
    fi
    local active resolved_link
    active=$(basename "$(readlink "$ROCUP_HOME/roc")")

    # Precondition: active is a local-<hash> entry.
    case "$active" in
        local-*) ;;
        *)
            echo "freeze: active version is $active; freeze requires an active local build" >&2
            return 1
            ;;
    esac

    # Resolve through the local registration. Two shapes are possible:
    #   Dir-mode  : $entry is itself a symlink to the build directory.
    #   File-mode : $entry is a real directory containing a 'roc' symlink that
    #               points at a standalone binary in the user's tree. (Unix only.)
    # In both shapes, "$entry/roc" transitively resolves to the binary.
    local entry="$ROCUP_HOME/$active"
    local source_dir
    if [ -L "$entry" ]; then
        # Dir-mode dangling check: -e on a dangling symlink is false.
        if [ ! -e "$entry" ]; then
            echo "freeze: cannot resolve active local $active; the source directory may have been moved or deleted" >&2
            return 1
        fi
        source_dir=$(readlink "$entry")
    elif [ -d "$entry" ] && [ -L "$entry/roc" ]; then
        if [ ! -e "$entry/roc" ]; then
            echo "freeze: cannot resolve active local $active; the source directory may have been moved or deleted" >&2
            return 1
        fi
        source_dir=$(dirname "$(readlink "$entry/roc")")
    else
        echo "freeze: cannot resolve active local $active; unexpected registration shape" >&2
        return 1
    fi
    if [ ! -x "$entry/roc" ]; then
        echo "freeze: roc binary not found in $source_dir" >&2
        return 1
    fi

    # Collision handling.
    local dest="$ROCUP_HOME/frozen-$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ "$force" -ne 1 ]; then
            echo "freeze: frozen-$name already exists. Use --force to overwrite." >&2
            return 1
        fi
        rm -rf "$dest"
    fi

    # Copy. -L dereferences symlinks so the result is a real file even when
    # the source roc was itself a symlink (file-mode registration). -p
    # preserves the executable bit.
    mkdir -p "$dest"
    cp -Lp "$entry/roc" "$dest/roc"
    # Language-server policy:
    #   - dir-mode: copy roc_language_server if it sits next to roc in the build dir.
    #   - file-mode: the user explicitly registered only the roc binary; do not
    #     reach back into the source dir to pick up anything else.
    if [ -L "$entry" ] && [ -e "$entry/roc_language_server" ]; then
        cp -Lp "$entry/roc_language_server" "$dest/roc_language_server"
    fi
    echo ".. frozen $active as frozen-$name ($source_dir)"

    activate "frozen-$name"
}
```

- [ ] **Step 4: Replace the Task-1 stub in the `freeze)` dispatch case with a real call**

Edit `rocup`. Find the `freeze)` case added in Task 1 and replace its body with:

```bash
    freeze)
        shift
        do_freeze "$@"
        ensure_global_symlinks
        ;;
```

- [ ] **Step 5: Run both freeze tests**

Run: `bash test/linux-macos/17-freeze-basic.sh && bash test/linux-macos/18-freeze-validation.sh`
Expected:
```
PASS: 17-freeze-basic.sh
PASS: 18-freeze-validation.sh
```

- [ ] **Step 6: Commit**

```bash
git add rocup test/linux-macos/17-freeze-basic.sh test/linux-macos/18-freeze-validation.sh
git commit -m "Implement do_freeze and wire into rocup freeze dispatch"
```

---

### Task 4: Bash — additional precondition tests (no active, non-local active, dangling local, missing roc)

**Files:**
- Modify: `test/linux-macos/18-freeze-validation.sh`

- [ ] **Step 1: Extend the validation test with precondition cases**

Append to `test/linux-macos/18-freeze-validation.sh`, **before** the final `pass` line:

```bash

# ---- Preconditions ----

# 6. No active version.
rm -f "$ROCUP_HOME/roc"
assert_exit_code 1 "no-active rejected" -- "$ROCUP" freeze test1

# 7. Active is not a local.
make_fake_alpha4 >/dev/null
activate_fake roc-alpha4-rolling
assert_exit_code 1 "non-local-active rejected" -- "$ROCUP" freeze test2

# 8. Active local has dangling resolution.
dangling_src="$TEST_TMPDIR/will-be-deleted"
mkdir -p "$dangling_src"
cat > "$dangling_src/roc" <<'EOF'
#!/bin/sh
echo "doomed roc"
EOF
chmod +x "$dangling_src/roc"
"$ROCUP" "$dangling_src" >/dev/null 2>&1
rm -rf "$dangling_src"
assert_exit_code 1 "dangling-local rejected" -- "$ROCUP" freeze test3

# 9. Active local has no roc binary in the resolved dir.
no_roc_src="$TEST_TMPDIR/no-roc"
mkdir -p "$no_roc_src"
cat > "$no_roc_src/roc" <<'EOF'
#!/bin/sh
echo "ok"
EOF
chmod +x "$no_roc_src/roc"
"$ROCUP" "$no_roc_src" >/dev/null 2>&1
rm -f "$no_roc_src/roc"
assert_exit_code 1 "missing-roc rejected" -- "$ROCUP" freeze test4
```

- [ ] **Step 2: Run the test**

Run: `bash test/linux-macos/18-freeze-validation.sh`
Expected: `PASS: 18-freeze-validation.sh`

If a case fails, debug by running `"$ROCUP" freeze testN` directly inside the test (insert a temporary `set -x`) and confirm `do_freeze` emits the documented error message.

- [ ] **Step 3: Commit**

```bash
git add test/linux-macos/18-freeze-validation.sh
git commit -m "Add freeze precondition tests (no-active, non-local, dangling, missing roc)"
```

---

### Task 5: Bash — `--force` overwrite

**Files:**
- Create: `test/linux-macos/19-freeze-force.sh`
- No code changes — `--force` was implemented in Task 3.

- [ ] **Step 1: Write the test**

Create `test/linux-macos/19-freeze-force.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "v1"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1
"$ROCUP" freeze keepme >/dev/null

# Modify the local source to differentiate v1 vs v2.
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "v2"
EOF
chmod +x "$local_dir/roc"
# Active is currently frozen-keepme; switch back to the local before freezing again.
# The bash dispatcher resolves a bare hash via local-<hash> when registered, so
# strip the 'local-' prefix and pass the hash.
local_name=$(find "$ROCUP_HOME" -maxdepth 1 -name 'local-*' -print -quit | xargs -n1 basename)
local_hash="${local_name#local-}"
"$ROCUP" "$local_hash" >/dev/null 2>&1

# Without --force: refused.
assert_exit_code 1 "refuse without --force" -- "$ROCUP" freeze keepme

# The existing frozen entry is untouched (still v1).
output=$("$ROCUP_HOME/frozen-keepme/roc")
assert_eq "v1" "$output" "frozen entry untouched after refused freeze"

# With --force: overwritten.
"$ROCUP" freeze keepme --force >/dev/null
output=$("$ROCUP_HOME/frozen-keepme/roc")
assert_eq "v2" "$output" "frozen entry overwritten with --force"

# Active is frozen-keepme again.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-keepme" "$active" "active switched to frozen-keepme after --force"

pass
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash test/linux-macos/19-freeze-force.sh`
Expected: `PASS: 19-freeze-force.sh`

- [ ] **Step 3: Commit**

```bash
git add test/linux-macos/19-freeze-force.sh
git commit -m "Add --force overwrite test for rocup freeze"
```

---

### Task 6: Bash — extend `do_list` to recognize `frozen-*`

**Files:**
- Modify: `rocup` (extend `do_list` near lines 153-194)
- Create: `test/linux-macos/20-freeze-addressing.sh` (this task covers list display; the same file is extended in Task 7)

- [ ] **Step 1: Write the failing test (list display)**

Create `test/linux-macos/20-freeze-addressing.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "local"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1
"$ROCUP" freeze myfeature >/dev/null

# Listing mentions frozen-myfeature with the active marker.
listing=$("$ROCUP" list)
assert_contains "$listing" "frozen" "list mentions frozen"
assert_contains "$listing" "myfeature" "list mentions the frozen name"
assert_contains "$listing" "-> " "list shows the active marker"

# The frozen entry's line carries the active marker.
active_line=$(printf '%s\n' "$listing" | grep '^ -> ' | head -n1)
assert_contains "$active_line" "myfeature" "active marker is on the frozen line"

pass
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/linux-macos/20-freeze-addressing.sh`
Expected: FAIL — `do_list`'s `find` filter doesn't include `frozen-*`, so it never appears in the listing.

- [ ] **Step 3: Extend `do_list` in `rocup`**

In `rocup`, find the `find ... \( -name 'roc-alpha4-rolling' -o -name 'roc_nightly-*' -o -name 'local-*' \)` line in `do_list` (line ~155). Add `-o -name 'frozen-*'` to the name filter:

```bash
    find "$ROCUP_HOME" -maxdepth 1 -mindepth 1 \
        \( -type d -o -type l \) \
        \( -name 'roc-alpha4-rolling' -o -name 'roc_nightly-*' -o -name 'local-*' -o -name 'frozen-*' \) -print0 \
```

Then add a `frozen-*)` branch to the per-name `case` inside `do_list` (currently has `roc-alpha4-rolling)`, `roc_nightly-*)`, `local-*)`). Insert this case **before** the catch-all `*)`:

```bash
            frozen-*)
                local fname mdy
                fname="${name#frozen-}"
                mdy=$(local_mdy "$dir")
                printf "%s%-7s (%s) <%s>\n" "$marker" "frozen" "$mdy" "$fname"
                ;;
```

(The `local_mdy` helper already exists and uses the `roc` binary's mtime — reusing it gives frozen entries a consistent build-date column with locals.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash test/linux-macos/20-freeze-addressing.sh`
Expected: `PASS: 20-freeze-addressing.sh`

- [ ] **Step 5: Re-run all bash tests to confirm list output didn't regress**

Run: `for t in test/linux-macos/*.sh; do bash "$t" || exit 1; done`
Expected: every test prints PASS.

- [ ] **Step 6: Commit**

```bash
git add rocup test/linux-macos/20-freeze-addressing.sh
git commit -m "Show frozen-<name> entries in rocup list"
```

---

### Task 7: Bash — activate and remove via `frozen-<name>` literal and bare `<name>`

**Files:**
- Modify: `rocup` (extend `remove_version` and the main dispatcher)
- Modify: `test/linux-macos/20-freeze-addressing.sh` (extend with activate + remove cases)

- [ ] **Step 1: Extend the addressing test**

Append to `test/linux-macos/20-freeze-addressing.sh`, **before** the final `pass` line:

```bash

# ---- Activate ----

# Switch to a different version so we can verify activation.
make_fake_alpha4 >/dev/null
"$ROCUP" alpha4 2>/dev/null || activate_fake roc-alpha4-rolling

# Activate by literal frozen-<name>.
"$ROCUP" frozen-myfeature >/dev/null 2>&1
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-myfeature" "$active" "activate by literal frozen-<name>"

# Switch away again.
activate_fake roc-alpha4-rolling

# Activate by bare <name>.
"$ROCUP" myfeature >/dev/null 2>&1
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-myfeature" "$active" "activate by bare <name>"

# ---- Remove ----

# Make another frozen entry for the bare-remove case.
local_name=$(find "$ROCUP_HOME" -maxdepth 1 -name 'local-*' -print -quit | xargs -n1 basename)
local_hash="${local_name#local-}"
"$ROCUP" "$local_hash" >/dev/null 2>&1
"$ROCUP" freeze second >/dev/null

# Remove by literal frozen-<name>.
"$ROCUP" remove frozen-myfeature >/dev/null
[ -e "$ROCUP_HOME/frozen-myfeature" ] && { echo "FAIL: frozen-myfeature still present after remove" >&2; exit 1; }

# Remove by bare <name>.
"$ROCUP" remove second >/dev/null
[ -e "$ROCUP_HOME/frozen-second" ] && { echo "FAIL: frozen-second still present after bare remove" >&2; exit 1; }
```

- [ ] **Step 2: Run test to confirm new assertions fail**

Run: `bash test/linux-macos/20-freeze-addressing.sh`
Expected: FAIL — the first new `"$ROCUP" frozen-myfeature` invocation falls through to the path branch and errors with `invalid argument 'frozen-myfeature'`.

- [ ] **Step 3: Extend `remove_version` for `frozen-<name>` literal**

In `rocup`, find `remove_version` (line ~229). Add a new case branch **after** the `local-*)` branch and **before** the `*)` branch:

```bash
        frozen-*)
            local fname="${ver#frozen-}"
            if ! [[ "$fname" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                echo "error: invalid frozen entry name '$ver'" >&2
                exit 1
            fi
            dir_name="$ver"
            ;;
```

Then, at the end of the `*)` branch inside `remove_version` (right after the invalid-version error path, around line 263–264), replace:

```bash
            else
                echo "error: invalid version '$ver' (expected 'alpha4', 7- or 8-char hash, or 'local-<hash>')" >&2
                exit 1
            fi
```

with:

```bash
            elif [ -d "$ROCUP_HOME/frozen-$ver" ]; then
                dir_name="frozen-$ver"
            else
                echo "error: invalid version '$ver' (expected 'alpha4', 7- or 8-char hash, 'local-<hash>', 'frozen-<name>', or a frozen name)" >&2
                exit 1
            fi
```

- [ ] **Step 4: Extend the main dispatcher for `frozen-<name>` literal and bare `<name>`**

In `rocup`, find the `*)` branch in the top-level `case "$cmd" in` (line ~1140). Replace the entire `*)` body with this version (note the new `frozen-*` and bare-name branches):

```bash
    *)
        if [[ "$cmd" =~ ^[+-][0-9]+$ ]]; then
            step_nightly "$cmd"
            ensure_global_symlinks
        elif [[ "$cmd" =~ ^[0-9a-f]{7,8}$ ]]; then
            # Hash: try local cache first, otherwise treat as a nightly hash
            # (install_nightly itself short-circuits when already downloaded).
            # 'roc --version' emits the 8-char form of the same hash GitHub
            # uses 7-char tags for; accept either and normalize to 7.
            hash="${cmd:0:7}"
            if [ -e "$ROCUP_HOME/local-$hash" ] || [ -L "$ROCUP_HOME/local-$hash" ]; then
                echo ".. activating local-$hash"
                activate "local-$hash"
                ensure_global_symlinks
            else
                platform=$(detect_platform)
                install_nightly "$hash" "$platform"
                ensure_global_symlinks
            fi
        elif [[ "$cmd" == frozen-* ]] && [ -d "$ROCUP_HOME/$cmd" ]; then
            activate "$cmd"
            ensure_global_symlinks
        elif [[ "$cmd" =~ ^[a-zA-Z0-9._-]+$ ]] && [ -d "$ROCUP_HOME/frozen-$cmd" ]; then
            activate "frozen-$cmd"
            ensure_global_symlinks
        elif [ -e "$cmd" ]; then
            register_local "$cmd"
            ensure_global_symlinks
        else
            echo "error: invalid argument '$cmd'" >&2
            usage >&2
            exit 1
        fi
        ;;
```

- [ ] **Step 5: Run test**

Run: `bash test/linux-macos/20-freeze-addressing.sh`
Expected: `PASS: 20-freeze-addressing.sh`

- [ ] **Step 6: Re-run all bash tests**

Run: `for t in test/linux-macos/*.sh; do bash "$t" || exit 1; done`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add rocup test/linux-macos/20-freeze-addressing.sh
git commit -m "Address frozen entries via literal and bare names in activate/remove"
```

---

### Task 8: Bash — extend fallback chain to consider frozen entries

**Files:**
- Modify: `rocup` (extend `remove_version` fallback block near lines 294-323)
- Create: `test/linux-macos/21-freeze-fallback.sh`

- [ ] **Step 1: Write the failing test**

Create `test/linux-macos/21-freeze-fallback.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# Set up two frozen entries and no other versions. Active is the second
# (newer) frozen. Removing it must fall back to the first frozen rather
# than leaving the install with no active version.

local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "local"
EOF
chmod +x "$local_dir/roc"
"$ROCUP" "$local_dir" >/dev/null 2>&1

# Freeze #1. active -> frozen-keep-me.
"$ROCUP" freeze keep-me >/dev/null

# Switch back to the local by hash (the bash dispatcher resolves a bare hash
# to local-<hash> when one is registered) so we can freeze again.
local_name=$(find "$ROCUP_HOME" -maxdepth 1 -name 'local-*' -print -quit | xargs -n1 basename)
local_hash="${local_name#local-}"
"$ROCUP" "$local_hash" >/dev/null 2>&1

# Freeze #2. active -> frozen-drop-me.
"$ROCUP" freeze drop-me >/dev/null

# Drop the underlying local so only the two frozens remain.
"$ROCUP" remove "$local_name" >/dev/null

# Sanity: active is still frozen-drop-me (removing a non-active version
# doesn't change the active pointer).
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-drop-me" "$active" "active is the newer frozen"

# Remove the active frozen. Fallback should pick the remaining frozen.
"$ROCUP" remove frozen-drop-me >/dev/null
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
assert_eq "frozen-keep-me" "$active" "fallback to remaining frozen entry"

pass
```

- [ ] **Step 2: Run test to verify the last assertion fails**

Run: `bash test/linux-macos/21-freeze-fallback.sh`
Expected: FAIL — the current fallback chain ends at `local-*`; with no remaining locals/nightlies/alpha4 it produces an empty fallback and clears the active symlink, so the final `assert_eq "frozen-keep-me"` fails.

- [ ] **Step 3: Extend `remove_version` fallback chain**

In `rocup`, find the fallback block inside `remove_version` (lines ~294-323). The block has three searches: nightlies, alpha4, then locals. Add a fourth fallback after the locals block (right before `rm -f "$tmp"` at line ~325):

```bash
    if [ -z "$fallback" ]; then
        : > "$tmp"
        find "$ROCUP_HOME" -maxdepth 1 -mindepth 1 \
            \( -type d -o -type l \) \
            -name 'frozen-*' -print0 \
            | while IFS= read -r -d '' dir; do
                printf "%s %s\n" "$(dir_sort_key "$dir")" "$dir" >> "$tmp"
            done
        if [ -s "$tmp" ]; then
            fallback=$(sort "$tmp" | tail -n1 | cut -d' ' -f2-)
        fi
    fi
```

- [ ] **Step 4: Run test**

Run: `bash test/linux-macos/21-freeze-fallback.sh`
Expected: `PASS: 21-freeze-fallback.sh`

- [ ] **Step 5: Re-run full suite**

Run: `for t in test/linux-macos/*.sh; do bash "$t" || exit 1; done`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add rocup test/linux-macos/21-freeze-fallback.sh
git commit -m "Include frozen entries in remove fallback chain"
```

---

### Task 9: Bash — freeze copies `roc_language_server` when present

**Files:**
- Create: `test/linux-macos/22-freeze-with-ls.sh`
- No code changes — `do_freeze` already copies the LS when present.

- [ ] **Step 1: Write the test**

Create `test/linux-macos/22-freeze-with-ls.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

local_dir="$TEST_TMPDIR/my-local-roc"
mkdir -p "$local_dir"
cat > "$local_dir/roc" <<'EOF'
#!/bin/sh
echo "roc"
EOF
chmod +x "$local_dir/roc"
cat > "$local_dir/roc_language_server" <<'EOF'
#!/bin/sh
echo "ls"
EOF
chmod +x "$local_dir/roc_language_server"
"$ROCUP" "$local_dir" >/dev/null 2>&1
"$ROCUP" freeze with-ls >/dev/null

# Both binaries copied as real files.
[ -f "$ROCUP_HOME/frozen-with-ls/roc" ]                    || { echo "FAIL: roc missing" >&2; exit 1; }
[ -f "$ROCUP_HOME/frozen-with-ls/roc_language_server" ]    || { echo "FAIL: roc_language_server missing" >&2; exit 1; }
[ -L "$ROCUP_HOME/frozen-with-ls/roc_language_server" ]    && { echo "FAIL: ls is a symlink, not a real file" >&2; exit 1; }

# Output check.
ls_out=$("$ROCUP_HOME/frozen-with-ls/roc_language_server")
assert_eq "ls" "$ls_out" "frozen LS runs and matches source"

# Source removed — frozen copies still work.
rm -rf "$local_dir"
ls_out=$("$ROCUP_HOME/frozen-with-ls/roc_language_server")
assert_eq "ls" "$ls_out" "frozen LS survives source removal"

pass
```

- [ ] **Step 2: Run test**

Run: `bash test/linux-macos/22-freeze-with-ls.sh`
Expected: `PASS: 22-freeze-with-ls.sh`

- [ ] **Step 3: Commit**

```bash
git add test/linux-macos/22-freeze-with-ls.sh
git commit -m "Test that freeze copies roc_language_server when present"
```

---

### Task 9b: Bash — freeze from a file-mode local copies only `roc`

**Files:**
- Create: `test/linux-macos/23-freeze-file-mode.sh`
- No code changes — `do_freeze`'s mode-aware logic was added in the revised Task 3.

- [ ] **Step 1: Write the test**

Create `test/linux-macos/23-freeze-file-mode.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/../common/lib.sh"
setup_test_env

# File-mode registration: register a single roc binary (not its parent dir).
# A roc_language_server sitting next to it must NOT be copied — the user
# only registered the binary.
src_dir="$TEST_TMPDIR/src"
mkdir -p "$src_dir"
cat > "$src_dir/roc" <<'EOF'
#!/bin/sh
echo "roc"
EOF
chmod +x "$src_dir/roc"
cat > "$src_dir/roc_language_server" <<'EOF'
#!/bin/sh
echo "ls"
EOF
chmod +x "$src_dir/roc_language_server"

"$ROCUP" "$src_dir/roc" >/dev/null 2>&1

# Sanity: active is a local-* whose roc resolves to the file.
active=$(basename "$(readlink "$ROCUP_HOME/roc")")
case "$active" in local-*) ;; *) echo "FAIL: expected local-*, got $active" >&2; exit 1 ;; esac
[ -L "$ROCUP_HOME/$active/roc" ] || { echo "FAIL: expected file-mode wrapper dir" >&2; exit 1; }

"$ROCUP" freeze fm >/dev/null

[ -f "$ROCUP_HOME/frozen-fm/roc" ]                  || { echo "FAIL: roc missing" >&2; exit 1; }
[ -L "$ROCUP_HOME/frozen-fm/roc" ]                  && { echo "FAIL: roc is a symlink" >&2; exit 1; }
[ -e "$ROCUP_HOME/frozen-fm/roc_language_server" ]  && { echo "FAIL: LS should not be copied for file-mode" >&2; exit 1; }

# Source binary gone — frozen copy still works.
rm -rf "$src_dir"
output=$("$ROCUP_HOME/frozen-fm/roc")
assert_eq "roc" "$output" "frozen file-mode roc survives source removal"

pass
```

- [ ] **Step 2: Run test**

Run: `bash test/linux-macos/23-freeze-file-mode.sh`
Expected: `PASS: 23-freeze-file-mode.sh`

- [ ] **Step 3: Commit**

```bash
git add test/linux-macos/23-freeze-file-mode.sh
git commit -m "Test that file-mode freeze copies only roc, not the LS"
```

---

### Task 10: Bash — add `freeze <name>` to `usage()`

**Files:**
- Modify: `rocup` (synopsis and command table in `usage()`, lines 52-112)

- [ ] **Step 1: Write the failing assertion in the existing help test**

Open `test/linux-macos/05-help-mentions-commands.sh`, find its existing assertions (it greps `--help` output for each known subcommand). Append a check **before** its final `pass`:

```bash
help_out=$("$ROCUP" --help 2>&1)
assert_contains "$help_out" "freeze <name>" "help lists 'freeze <name>'"
assert_contains "$help_out" "snapshot"      "help describes freeze as a snapshot"
```

(If your file uses a different captured-output variable name, reuse it. The variable in the existing file is the canonical one; just look at line 1-3.)

- [ ] **Step 2: Run test to confirm it fails**

Run: `bash test/linux-macos/05-help-mentions-commands.sh`
Expected: FAIL — `help lists 'freeze <name>'`.

- [ ] **Step 3: Update the synopsis line in `usage()`**

In `rocup` near line 58-59, replace:

```bash
        "usage: rocup [alpha4 | latest | <hash> | <path> | local | +N | -N | list | remove <ver> | prune <N>]"
```

with:

```bash
        "usage: rocup [alpha4 | latest | <hash> | <path> | local | +N | -N | list | freeze <name> | remove <ver> | prune <N>]"
```

- [ ] **Step 4: Add the `freeze <name>` entry in the command table**

In `rocup` between the `list` block and the `remove <ver>` block (around line 103), insert:

```bash
    first=$(printf "  %-16s" "freeze <name>")
    wrap_text "$width" "$first" "$cont" \
        "snapshot the active local build into \$ROCUP_HOME/frozen-<name>/ as real files (not symlinks). Requires an active local. <name> matches [a-zA-Z0-9._-] and must not collide with an existing hash. Pass --force to overwrite an existing frozen entry. The original local-<hash> registration is left intact; active becomes frozen-<name>."
    echo
```

- [ ] **Step 5: Run test**

Run: `bash test/linux-macos/05-help-mentions-commands.sh`
Expected: `PASS: 05-help-mentions-commands.sh`

- [ ] **Step 6: Run full bash suite once more**

Run: `for t in test/linux-macos/*.sh; do bash "$t" || exit 1; done`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add rocup test/linux-macos/05-help-mentions-commands.sh
git commit -m "Document freeze <name> in rocup --help"
```

---

### Task 11: PowerShell — `Test-FreezeName` helper

**Files:**
- Modify: `rocup.ps1` (add helper near `Register-Local`, around line ~779)
- Create: `test/windows/19-freeze-validation.ps1`

- [ ] **Step 1: Write the failing test**

Create `test/windows/19-freeze-validation.ps1`:

```powershell
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Build a fake local roc.
$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value '@echo off`necho fake' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register-local succeeded'

function Expect-Fail {
    param([string] $Msg, [string[]] $Argv)
    $r = Invoke-Rocup @Argv
    if ($r.ExitCode -eq 0) {
        [Console]::Error.WriteLine("FAIL: $Msg (expected non-zero exit, got 0)")
        [Console]::Error.WriteLine("  output: $($r.Output)")
        exit 1
    }
}

# 1. Empty name rejected.
Expect-Fail 'empty name rejected' @('freeze', '')

# 2. Bad characters rejected.
Expect-Fail 'spaces rejected' @('freeze', 'has space')
Expect-Fail 'slash rejected'  @('freeze', 'a/b')

# 3. Name starting with frozen- rejected.
Expect-Fail 'leading frozen- rejected' @('freeze', 'frozen-foo')

# 4. Name colliding with the active local's hash rejected.
$rocLink = Join-Path $env:ROCUP_HOME 'roc'
$active  = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
$activeHash = $active.Substring('local-'.Length)
Expect-Fail 'hash-collision rejected' @('freeze', $activeHash)

# 5. Collision-without-force.
New-Item -ItemType Directory -Path (Join-Path $env:ROCUP_HOME 'frozen-already-there') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $env:ROCUP_HOME 'frozen-already-there\roc.exe') -Value 'pre' -Encoding Ascii
Expect-Fail 'exists-no-force rejected' @('freeze', 'already-there')

Write-TestPass
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File test/windows/19-freeze-validation.ps1`
Expected: FAIL — `Invoke-Rocup freeze ''` returns `ExitCode = 0` because the dispatcher falls through to the path-existence branch where `Test-Path ''` is false, then to the `invalid argument` error path which DOES exit 1 — so actually the first assertion might pass for the wrong reason. Verify by looking at the captured `Output`. Most assertions still fail because the freeze command itself doesn't exist yet, and the validator-specific messages aren't emitted.

(On macOS/Linux, full execution requires Windows or a PowerShell-on-Unix environment. If you are not on Windows, syntax-check with `pwsh -NoProfile -Command 'Get-Command -ScriptBlock { . "$pwd/test/windows/19-freeze-validation.ps1" }'` and defer execution to CI. The fix is the same either way.)

- [ ] **Step 3: Add `Test-FreezeName` helper**

In `rocup.ps1`, insert this function immediately above `Register-Local` (around line 779):

```powershell
function Test-FreezeName {
    # Returns the name on success; throws on failure. Rules per design spec:
    #   - non-empty, matches ^[a-zA-Z0-9._-]+$
    #   - does not start with 'frozen-'
    #   - does not collide with any installed nightly or registered local hash
    param([Parameter(Mandatory=$false)][string] $Name)
    if (-not $Name) {
        throw "freeze: name is required"
    }
    if ($Name -notmatch '^[a-zA-Z0-9._-]+$') {
        throw "freeze: invalid name '$Name'; allowed characters: a-z A-Z 0-9 . _ -"
    }
    if ($Name -like 'frozen-*') {
        throw "freeze: do not include the 'frozen-' prefix in the name"
    }
    if ($Name -match '^[0-9a-f]{7}$') {
        $localPath = Join-Path $script:RocupHome "local-$Name"
        if (Test-Path -LiteralPath $localPath) {
            throw "freeze: name '$Name' conflicts with an existing version hash; choose another name"
        }
        $nightly = Find-NightlyDir $Name
        if ($nightly) {
            throw "freeze: name '$Name' conflicts with an existing version hash; choose another name"
        }
    }
    $Name
}
```

- [ ] **Step 4: Add a stub `freeze` dispatch case**

In `rocup.ps1`, find the `switch -Regex ($cmd)` inside `Invoke-Rocup` (line ~987). Insert a new case **before** the `'^[+-][0-9]+$'` case:

```powershell
        '^freeze$' {
            if ($argv.Count -lt 2) {
                throw "error: 'freeze' requires a name (e.g. 'rocup freeze myfeature')"
            }
            # Stub for Task 11 — replaced in Task 12.
            $force = $false
            $name  = ''
            for ($i = 1; $i -lt $argv.Count; $i++) {
                if     ($argv[$i] -eq '--force') { $force = $true }
                elseif ($argv[$i].StartsWith('-')) { throw "freeze: unknown option '$($argv[$i])'" }
                elseif (-not $name) { $name = $argv[$i] }
                else  { throw "freeze: too many arguments" }
            }
            $null = Test-FreezeName $name
            $dest = Join-Path $script:RocupHome "frozen-$name"
            if ((Test-Path -LiteralPath $dest) -and -not $force) {
                throw "freeze: frozen-$name already exists. Use --force to overwrite."
            }
            throw "freeze: stub (Task 11) — preconditions ok for '$name'"
        }
```

- [ ] **Step 5: Run test**

Run: `pwsh -NoProfile -File test/windows/19-freeze-validation.ps1`
Expected: `PASS: 19-freeze-validation.ps1`.

- [ ] **Step 6: Commit**

```bash
git add rocup.ps1 test/windows/19-freeze-validation.ps1
git commit -m "Add Test-FreezeName helper and validation test for Windows"
```

---

### Task 12: PowerShell — `Invoke-Freeze` core

**Files:**
- Modify: `rocup.ps1` (add `Invoke-Freeze` near `Test-FreezeName`; replace stub in dispatch case)
- Create: `test/windows/18-freeze-basic.ps1`

- [ ] **Step 1: Write the failing happy-path test**

Create `test/windows/18-freeze-basic.ps1`:

```powershell
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'fake v1' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register-local succeeded'

$rocLink = Join-Path $env:ROCUP_HOME 'roc'
$active  = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
$originalLocal = $active

$r = Invoke-Rocup freeze myfeature
Assert-Eq 0 $r.ExitCode 'freeze succeeded'

$active = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
Assert-Eq 'frozen-myfeature' $active 'active is frozen entry after freeze'

# Real directory, not a junction.
$frozen = Join-Path $env:ROCUP_HOME 'frozen-myfeature'
$item = Get-Item -LiteralPath $frozen -Force
if ($item.LinkType) {
    [Console]::Error.WriteLine("FAIL: frozen-myfeature is a $($item.LinkType)")
    exit 1
}
if (-not $item.PSIsContainer) {
    [Console]::Error.WriteLine("FAIL: frozen-myfeature is not a container")
    exit 1
}

# roc.exe is a real file (not a symlink/junction).
$rocExe = Join-Path $frozen 'roc.exe'
$rocItem = Get-Item -LiteralPath $rocExe -Force
if ($rocItem.LinkType) {
    [Console]::Error.WriteLine("FAIL: roc.exe is a $($rocItem.LinkType)")
    exit 1
}

# Contents match (byte-for-byte).
$srcBytes = [IO.File]::ReadAllBytes((Join-Path $localDir 'roc.exe'))
$dstBytes = [IO.File]::ReadAllBytes($rocExe)
if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$srcBytes, [byte[]]$dstBytes)) {
    [Console]::Error.WriteLine("FAIL: copied roc.exe content differs")
    exit 1
}

# Original local registration still present (a junction).
$origJunction = Join-Path $env:ROCUP_HOME $originalLocal
if (-not (Test-Path -LiteralPath $origJunction)) {
    [Console]::Error.WriteLine("FAIL: original local registration was removed")
    exit 1
}

# Removing the source dir doesn't break the frozen copy.
Remove-Item -LiteralPath $localDir -Recurse -Force
if (-not (Test-Path -LiteralPath $rocExe)) {
    [Console]::Error.WriteLine("FAIL: frozen roc.exe missing after source removal")
    exit 1
}

Write-TestPass
```

- [ ] **Step 2: Run to confirm it fails**

Run: `pwsh -NoProfile -File test/windows/18-freeze-basic.ps1`
Expected: FAIL — stub throws `freeze: stub (Task 11) ...`.

- [ ] **Step 3: Add `Invoke-Freeze`**

In `rocup.ps1`, insert below `Test-FreezeName`:

```powershell
function Invoke-Freeze {
    param(
        [Parameter(Mandatory)][string[]] $argv
    )
    # argv = the args AFTER 'freeze' (i.e., $name and any flags).
    $force = $false
    $name  = ''
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $a = $argv[$i]
        if ($a -eq '--force') {
            $force = $true
        } elseif ($a.StartsWith('-')) {
            throw "freeze: unknown option '$a'"
        } elseif (-not $name) {
            $name = $a
        } else {
            throw "freeze: too many arguments (already have name '$name', also got '$a')"
        }
    }

    $null = Test-FreezeName $name

    $rocLink = Join-Path $script:RocupHome 'roc'
    if (-not (Test-IsJunction $rocLink)) {
        throw "freeze: no active version"
    }
    $linkTarget = (Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1
    $active = Split-Path -Leaf $linkTarget

    if ($active -notlike 'local-*') {
        throw "freeze: active version is $active; freeze requires an active local build"
    }

    $entry = Join-Path $script:RocupHome $active
    $resolved = Get-LocalInstallPath $entry
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "freeze: cannot resolve active local $active; the source directory may have been moved or deleted"
    }
    $srcExe = Join-Path $resolved 'roc.exe'
    if (-not (Test-Path -LiteralPath $srcExe -PathType Leaf)) {
        throw "freeze: roc binary not found in $resolved"
    }

    $dest = Join-Path $script:RocupHome "frozen-$name"
    if (Test-Path -LiteralPath $dest) {
        if (-not $force) {
            throw "freeze: frozen-$name already exists. Use --force to overwrite."
        }
        Remove-Item -LiteralPath $dest -Recurse -Force
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -LiteralPath $srcExe -Destination (Join-Path $dest 'roc.exe') -Force

    Write-Host ".. frozen $active as frozen-$name ($resolved)"

    Set-ActiveVersion "frozen-$name"
}
```

- [ ] **Step 4: Replace the stub case body**

In `rocup.ps1`, find the `'^freeze$'` case added in Task 11. Replace its body with:

```powershell
        '^freeze$' {
            if ($argv.Count -lt 2) {
                throw "error: 'freeze' requires a name (e.g. 'rocup freeze myfeature')"
            }
            Invoke-Freeze -argv $argv[1..($argv.Count - 1)]
            Initialize-RocupShims
            return
        }
```

- [ ] **Step 5: Run both tests**

Run: `pwsh -NoProfile -File test/windows/18-freeze-basic.ps1; pwsh -NoProfile -File test/windows/19-freeze-validation.ps1`
Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add rocup.ps1 test/windows/18-freeze-basic.ps1
git commit -m "Implement Invoke-Freeze and wire into rocup.ps1 freeze dispatch"
```

---

### Task 13: PowerShell — precondition + force tests

**Files:**
- Modify: `test/windows/19-freeze-validation.ps1` (append precondition cases)
- Create: `test/windows/20-freeze-force.ps1`

- [ ] **Step 1: Extend the validation test**

Append to `test/windows/19-freeze-validation.ps1` before the final `Write-TestPass`:

```powershell

# ---- Preconditions ----

# Remove the active junction so there's no active version.
[System.IO.Directory]::Delete((Join-Path $env:ROCUP_HOME 'roc'), $false)
Expect-Fail 'no-active rejected' @('freeze', 'test1')

# Re-register the local, then switch to a fake nightly (non-local active).
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 're-register succeeded'
New-FakeNightly -DateYmd '2025-10-25' -Hash 'abc1234' | Out-Null
Set-FakeActive 'roc_nightly-2025-10-25-abc1234'
Expect-Fail 'non-local-active rejected' @('freeze', 'test2')

# Dangling local: register a path then delete the source.
$danglingSrc = Join-Path $script:TestTmpDir 'will-be-deleted'
New-Item -ItemType Directory -Path $danglingSrc -Force | Out-Null
Set-Content -LiteralPath (Join-Path $danglingSrc 'roc.exe') -Value 'doomed' -Encoding Ascii
$r = Invoke-Rocup $danglingSrc
Assert-Eq 0 $r.ExitCode 'dangling-source register succeeded'
Remove-Item -LiteralPath $danglingSrc -Recurse -Force
Expect-Fail 'dangling-local rejected' @('freeze', 'test3')
```

- [ ] **Step 2: Create the force test**

Create `test/windows/20-freeze-force.ps1`:

```powershell
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'v1' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register succeeded'
$r = Invoke-Rocup freeze keepme
Assert-Eq 0 $r.ExitCode 'first freeze succeeded'

# Switch back to the local and bump v1 -> v2 before re-freezing. PS dispatcher
# resolves a bare hash to local-<hash> when registered, so pass the hash.
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'v2' -Encoding Ascii
$localName = (Get-ChildItem -LiteralPath $env:ROCUP_HOME -Filter 'local-*' -Force | Select-Object -First 1).Name
$localHash = $localName.Substring('local-'.Length)
$r = Invoke-Rocup $localHash
Assert-Eq 0 $r.ExitCode 'switch back to local succeeded'

# Refused without --force.
$r = Invoke-Rocup freeze keepme
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine('FAIL: refuse without --force'); exit 1 }
$existing = (Get-Content -LiteralPath (Join-Path $env:ROCUP_HOME 'frozen-keepme\roc.exe') -Raw).Trim()
Assert-Eq 'v1' $existing 'frozen entry untouched after refused freeze'

# Succeeds with --force.
$r = Invoke-Rocup freeze keepme --force
Assert-Eq 0 $r.ExitCode 'force-freeze succeeded'
$overwritten = (Get-Content -LiteralPath (Join-Path $env:ROCUP_HOME 'frozen-keepme\roc.exe') -Raw).Trim()
Assert-Eq 'v2' $overwritten 'frozen entry overwritten with --force'

$active = Split-Path -Leaf ((Get-Item -LiteralPath (Join-Path $env:ROCUP_HOME 'roc') -Force).Target | Select-Object -First 1)
Assert-Eq 'frozen-keepme' $active 'active switched to frozen-keepme after --force'

Write-TestPass
```

- [ ] **Step 3: Run tests**

Run: `pwsh -NoProfile -File test/windows/19-freeze-validation.ps1; pwsh -NoProfile -File test/windows/20-freeze-force.ps1`
Expected: both PASS.

- [ ] **Step 4: Commit**

```bash
git add test/windows/19-freeze-validation.ps1 test/windows/20-freeze-force.ps1
git commit -m "Add precondition + --force tests for Windows freeze"
```

---

### Task 14: PowerShell — `Invoke-List` recognizes `frozen-*`

**Files:**
- Modify: `rocup.ps1` (`Get-InstalledVersionDirs` filter and `Invoke-List` switch, lines ~813-883)
- Create: `test/windows/21-freeze-addressing.ps1` (covers list + activate + remove in this task and Task 15)

- [ ] **Step 1: Write the failing list test**

Create `test/windows/21-freeze-addressing.ps1`:

```powershell
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'fake' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register succeeded'
$r = Invoke-Rocup freeze myfeature
Assert-Eq 0 $r.ExitCode 'freeze succeeded'

$r = Invoke-Rocup list
Assert-Eq 0 $r.ExitCode 'list succeeded'
Assert-Contains $r.Output 'frozen'    'list mentions frozen'
Assert-Contains $r.Output 'myfeature' 'list mentions the frozen name'
Assert-Contains $r.Output ' -> '      'list shows active marker'

Write-TestPass
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `Get-InstalledVersionDirs` filter does not include `frozen-*`, so the entry is invisible.

- [ ] **Step 3: Extend `Get-InstalledVersionDirs`**

In `rocup.ps1` line ~822, change:

```powershell
            $_.Name -like 'roc_nightly-*' -or $_.Name -like 'local-*'
```

to:

```powershell
            $_.Name -like 'roc_nightly-*' -or $_.Name -like 'local-*' -or $_.Name -like 'frozen-*'
```

- [ ] **Step 4: Add a `frozen-*` case to `Invoke-List`'s switch**

In `rocup.ps1` inside `Invoke-List`, find the `switch -Regex ($row.Name)` (line ~855). Add a case **before** the `default` branch:

```powershell
            '^frozen-(.+)$' {
                $fname = $Matches[1]
                $resolved = Get-Item -LiteralPath $row.Path -Force
                $exe = Join-Path $resolved.FullName 'roc.exe'
                $mtime = if (Test-Path -LiteralPath $exe) {
                    (Get-Item -LiteralPath $exe).LastWriteTime
                } else {
                    $resolved.LastWriteTime
                }
                $mdy = $mtime.ToString('MM/dd/yyyy')
                Write-Host ("{0}{1,-7} ({2}) <{3}>" -f $marker, 'frozen', $mdy, $fname)
                break
            }
```

- [ ] **Step 5: Run test**

Expected: `PASS: 21-freeze-addressing.ps1`.

- [ ] **Step 6: Commit**

```bash
git add rocup.ps1 test/windows/21-freeze-addressing.ps1
git commit -m "Show frozen-<name> entries in PowerShell list output"
```

---

### Task 15: PowerShell — activate and remove for `frozen-<name>` and bare `<name>`

**Files:**
- Modify: `rocup.ps1` (`Remove-Version`, `Invoke-Rocup` dispatcher)
- Modify: `test/windows/21-freeze-addressing.ps1`

- [ ] **Step 1: Extend the addressing test**

Append to `test/windows/21-freeze-addressing.ps1` before the final `Write-TestPass`:

```powershell

# ---- Activate ----

New-FakeNightly -DateYmd '2025-10-25' -Hash 'abc1234' | Out-Null
Set-FakeActive 'roc_nightly-2025-10-25-abc1234'

# Activate by literal frozen-<name>.
$r = Invoke-Rocup 'frozen-myfeature'
Assert-Eq 0 $r.ExitCode 'activate literal frozen-<name> succeeded'
$active = Split-Path -Leaf ((Get-Item -LiteralPath (Join-Path $env:ROCUP_HOME 'roc') -Force).Target | Select-Object -First 1)
Assert-Eq 'frozen-myfeature' $active 'activate by literal frozen-<name>'

# Switch away again.
Set-FakeActive 'roc_nightly-2025-10-25-abc1234'

# Activate by bare <name>.
$r = Invoke-Rocup 'myfeature'
Assert-Eq 0 $r.ExitCode 'activate bare name succeeded'
$active = Split-Path -Leaf ((Get-Item -LiteralPath (Join-Path $env:ROCUP_HOME 'roc') -Force).Target | Select-Object -First 1)
Assert-Eq 'frozen-myfeature' $active 'activate by bare <name>'

# ---- Remove ----

# Make a second frozen entry to exercise both removal paths. Switch to the
# local by hash so the PS hash dispatcher resolves it to local-<hash>.
$localName = (Get-ChildItem -LiteralPath $env:ROCUP_HOME -Filter 'local-*' -Force | Select-Object -First 1).Name
$localHash = $localName.Substring('local-'.Length)
$r = Invoke-Rocup $localHash
Assert-Eq 0 $r.ExitCode 'switch to local succeeded'
$r = Invoke-Rocup freeze second
Assert-Eq 0 $r.ExitCode 'second freeze succeeded'

# Remove by literal frozen-<name>.
$r = Invoke-Rocup remove 'frozen-myfeature'
Assert-Eq 0 $r.ExitCode 'remove literal succeeded'
if (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'frozen-myfeature')) {
    [Console]::Error.WriteLine('FAIL: frozen-myfeature still present after remove')
    exit 1
}

# Remove by bare <name>.
$r = Invoke-Rocup remove 'second'
Assert-Eq 0 $r.ExitCode 'remove bare succeeded'
if (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'frozen-second')) {
    [Console]::Error.WriteLine('FAIL: frozen-second still present after bare remove')
    exit 1
}
```

- [ ] **Step 2: Run to confirm new lines fail**

Expected: FAIL — `& $Rocup 'frozen-myfeature'` falls through to the path branch and errors.

- [ ] **Step 3: Extend `Remove-Version`**

In `rocup.ps1` inside the `switch -Regex ($Ver)` block in `Remove-Version` (line ~536-552), add new cases. Replace the entire switch body with:

```powershell
    switch -Regex ($Ver) {
        '^local-[0-9a-f]{7}$' { $dirName = $Ver }
        '^frozen-[a-zA-Z0-9._-]+$' { $dirName = $Ver }
        '^[0-9a-f]{7,8}$' {
            $hash = $Ver.Substring(0, 7)
            $localDir = Join-Path $script:RocupHome "local-$hash"
            if (Test-Path -LiteralPath $localDir) {
                $dirName = "local-$hash"
            } else {
                $found = Find-NightlyDir $hash
                if ($found) { $dirName = $found }
                else        { $dirName = "roc_nightly-$hash" }
            }
        }
        '^[a-zA-Z0-9._-]+$' {
            $candidate = Join-Path $script:RocupHome "frozen-$Ver"
            if (Test-Path -LiteralPath $candidate) {
                $dirName = "frozen-$Ver"
            } else {
                throw "error: invalid version '$Ver' (expected 7- or 8-char hash, 'local-<hash>', 'frozen-<name>', or a frozen name)"
            }
        }
        default {
            throw "error: invalid version '$Ver' (expected 7- or 8-char hash, 'local-<hash>', 'frozen-<name>', or a frozen name)"
        }
    }
```

- [ ] **Step 4: Extend `Invoke-Rocup` dispatcher**

In `rocup.ps1`'s `Invoke-Rocup` `switch -Regex ($cmd)` (line ~987), add cases for frozen activation **before** the `default` block:

```powershell
        '^frozen-[a-zA-Z0-9._-]+$' {
            $candidate = Join-Path $script:RocupHome $cmd
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                Set-ActiveVersion $cmd
                Initialize-RocupShims
                return
            }
            # else: fall through to default for path-style resolution / error
        }
        '^[a-zA-Z0-9._-]+$' {
            $candidate = Join-Path $script:RocupHome "frozen-$cmd"
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                Set-ActiveVersion "frozen-$cmd"
                Initialize-RocupShims
                return
            }
            # else: fall through to default for path-style resolution / error
        }
```

Note: PowerShell's `switch -Regex` evaluates cases top-to-bottom. The bare-`<name>` regex `^[a-zA-Z0-9._-]+$` also matches things like `latest`, `list`, etc. — but those cases come **earlier** in the switch, so the dispatcher reaches the new bare-name case only for arguments that didn't match any earlier branch. Verify by re-reading the resulting `Invoke-Rocup` top-to-bottom.

- [ ] **Step 5: Run test**

Expected: `PASS: 21-freeze-addressing.ps1`.

- [ ] **Step 6: Commit**

```bash
git add rocup.ps1 test/windows/21-freeze-addressing.ps1
git commit -m "Address frozen entries via literal and bare names in activate/remove (PS)"
```

---

### Task 16: PowerShell — extend fallback chain to consider frozen entries

**Files:**
- Modify: `rocup.ps1` (`Get-FallbackVersion`, line ~514-530)
- Create: `test/windows/22-freeze-fallback.ps1`

- [ ] **Step 1: Write the failing test**

Create `test/windows/22-freeze-fallback.ps1`:

```powershell
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'fake' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register succeeded'

# Make two frozen entries and remove the underlying local so only frozens remain.
$r = Invoke-Rocup freeze keep-me
Assert-Eq 0 $r.ExitCode 'freeze keep-me succeeded'
$localName = (Get-ChildItem -LiteralPath $env:ROCUP_HOME -Filter 'local-*' -Force | Select-Object -First 1).Name
$localHash = $localName.Substring('local-'.Length)
$r = Invoke-Rocup $localHash
Assert-Eq 0 $r.ExitCode 'switch back to local'
$r = Invoke-Rocup freeze drop-me
Assert-Eq 0 $r.ExitCode 'freeze drop-me succeeded'
$r = Invoke-Rocup remove $localName
Assert-Eq 0 $r.ExitCode 'remove local succeeded'

# Active is frozen-drop-me; remove it — fallback should pick frozen-keep-me.
$r = Invoke-Rocup remove 'frozen-drop-me'
Assert-Eq 0 $r.ExitCode 'remove active frozen succeeded'
$active = Split-Path -Leaf ((Get-Item -LiteralPath (Join-Path $env:ROCUP_HOME 'roc') -Force).Target | Select-Object -First 1)
Assert-Eq 'frozen-keep-me' $active 'fallback to remaining frozen entry'

Write-TestPass
```

- [ ] **Step 2: Run to confirm it fails**

Expected: FAIL — `Get-FallbackVersion` only considers nightlies and locals.

- [ ] **Step 3: Extend `Get-FallbackVersion`**

In `rocup.ps1`, replace the body of `Get-FallbackVersion` (lines 514-530) with:

```powershell
function Get-FallbackVersion {
    # Pick the most recent nightly; else most recent local; else most recent frozen.
    # Returns the directory name or ''.
    $dirs = @(Get-InstalledVersionDirs)
    if ($dirs.Count -eq 0) { return '' }

    $nightlies = @($dirs | Where-Object { $_.Name -like 'roc_nightly-*' })
    if ($nightlies.Count -gt 0) {
        $best = $nightlies | Sort-Object { Get-DirSortKey $_.FullName } -Descending | Select-Object -First 1
        return $best.Name
    }
    $locals = @($dirs | Where-Object { $_.Name -like 'local-*' })
    if ($locals.Count -gt 0) {
        $best = $locals | Sort-Object { Get-DirSortKey $_.FullName } -Descending | Select-Object -First 1
        return $best.Name
    }
    $frozens = @($dirs | Where-Object { $_.Name -like 'frozen-*' })
    if ($frozens.Count -gt 0) {
        $best = $frozens | Sort-Object { Get-DirSortKey $_.FullName } -Descending | Select-Object -First 1
        return $best.Name
    }
    return ''
}
```

- [ ] **Step 4: Run test**

Expected: `PASS: 22-freeze-fallback.ps1`.

- [ ] **Step 5: Commit**

```bash
git add rocup.ps1 test/windows/22-freeze-fallback.ps1
git commit -m "Include frozen entries in PowerShell remove fallback chain"
```

---

### Task 17: PowerShell — add `freeze <name>` to `Show-Usage`

**Files:**
- Modify: `rocup.ps1` (`Show-Usage`, lines 939-978)
- Modify: `test/windows/01-help.ps1` (or the closest existing help test) — add an assertion that `freeze <name>` appears.

- [ ] **Step 1: Open the existing help test to see its structure**

Run: `cat test/windows/01-help.ps1`
The file captures `& $Rocup --help` output and runs assertions on it.

- [ ] **Step 2: Append a failing assertion**

Inside `test/windows/01-help.ps1`, before its final `Write-TestPass` call:

```powershell
$r = Invoke-Rocup --help
Assert-Contains $r.Output 'freeze <name>' "help lists 'freeze <name>'"
Assert-Contains $r.Output 'snapshot'      "help describes freeze as a snapshot"
```

(If `01-help.ps1` already captures help output, reuse that variable. Some help tests use `Invoke-Rocup -h` instead of `--help` — match what the file already does.)

- [ ] **Step 3: Run to confirm failure**

Expected: FAIL.

- [ ] **Step 4: Update synopsis line in `Show-Usage`**

In `rocup.ps1` line ~963, change:

```powershell
        -Text 'usage: rocup [latest | <hash> | <path> | local | +N | -N | list | remove <ver> | prune <N>]') )
```

to:

```powershell
        -Text 'usage: rocup [latest | <hash> | <path> | local | +N | -N | list | freeze <name> | remove <ver> | prune <N>]') )
```

- [ ] **Step 5: Add an entry in the `$cmds` array**

In `rocup.ps1` `Show-Usage`'s `$cmds = @( ... )` (line 947-956), insert this entry **between** the `list` and `remove <ver>` rows:

```powershell
        @{ Label = 'freeze <name>'; Desc = "snapshot the active local build into `$env:ROCUP_HOME\frozen-<name>\ as real files (not junctions). Requires an active local. <name> matches [a-zA-Z0-9._-] and must not collide with an existing hash. Pass --force to overwrite an existing frozen entry. The original local-<hash> registration is left intact; active becomes frozen-<name>." }
```

- [ ] **Step 6: Run test**

Expected: PASS.

- [ ] **Step 7: Run all Windows tests**

Run (in PowerShell): `Get-ChildItem test/windows/*.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName }`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add rocup.ps1 test/windows/01-help.ps1
git commit -m "Document freeze <name> in rocup.ps1 --help"
```

---

### Task 18: Docs — README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add `freeze` to the synopsis line**

In `README.md` line 44, change:

```
rocup [alpha4 | latest | <hash> | <path> | local | +N | -N | list | remove <ver> | prune <N>]
```

to:

```
rocup [alpha4 | latest | <hash> | <path> | local | +N | -N | list | freeze <name> | remove <ver> | prune <N>]
```

- [ ] **Step 2: Add a row to the command table**

In `README.md`, insert this row in the command table **between** the `rocup list` row (line 55) and the `rocup remove <ver>` row (line 56):

```
| `rocup freeze <name>` | Snapshot the active local build into `~/.rocup/frozen-<name>/` as real files (binaries are dereferenced and copied, not symlinked). Requires an active `local-<hash>`; the original local registration is preserved and `frozen-<name>` becomes active. Names match `[a-zA-Z0-9._-]` and must not collide with an installed hash. Pass `--force` to overwrite. |
```

- [ ] **Step 3: Add an example**

In `README.md` Examples block (line 60-72), insert this line **between** the `rocup local` line and the `rocup -1` line:

```sh
rocup freeze myfeature       # snapshot the active local build as frozen-myfeature
```

- [ ] **Step 4: Verify rendering**

Run: `grep -n 'freeze' README.md`
Expected: three matches — synopsis, table row, example.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "Document rocup freeze <name> in README"
```

---

### Task 19: Docs — FEATURE_MATRIX

**Files:**
- Modify: `FEATURE_MATRIX.md`

- [ ] **Step 1: Add a row**

In `FEATURE_MATRIX.md`, insert this row **after** `<dir>` and **before** `<file>` (logically grouped with local-related capabilities):

```
| `freeze <name>` — snapshot the active local build               | yes                   | yes                   |
```

- [ ] **Step 2: Verify**

Run: `grep -n 'freeze' FEATURE_MATRIX.md`
Expected: one match.

- [ ] **Step 3: Commit**

```bash
git add FEATURE_MATRIX.md
git commit -m "Add freeze <name> row to feature matrix"
```

---

### Task 20: drift-check — add required phrases

**Files:**
- Modify: `test/drift-check.sh`

- [ ] **Step 1: Add phrases to `REQUIRED_PHRASES`**

In `test/drift-check.sh`, find the `REQUIRED_PHRASES` here-doc (line 36-78). Insert these lines **before** the `# 'remove <ver>' - version deletion.` comment:

```
# 'freeze <name>' - snapshot the active local build.
snapshot the active local build
Requires an active local
--force
```

These three phrases (substrings) appear in both `usage` (bash, Task 10) and `Show-Usage` (PowerShell, Task 17), wrapped or unwrapped.

- [ ] **Step 2: Run drift-check**

Run: `bash test/drift-check.sh`
Expected: `DRIFT CHECK: PASS` with the summary lines listing `freeze` among the commands.

(If a phrase is missing from one side, fix the usage text in `rocup` or `rocup.ps1` to include the phrase exactly — don't relax the required phrase. The whole point of drift-check is to catch this.)

- [ ] **Step 3: Commit**

```bash
git add test/drift-check.sh
git commit -m "Add freeze required phrases to drift-check"
```

---

### Task 21: Final integration check

- [ ] **Step 1: Run the full bash suite**

Run: `for t in test/linux-macos/*.sh; do bash "$t" || { echo "FAIL: $t"; exit 1; }; done`
Expected: every test prints `PASS:`.

- [ ] **Step 2: Run drift-check**

Run: `bash test/drift-check.sh`
Expected: `DRIFT CHECK: PASS`.

- [ ] **Step 3: Run the full Windows suite (if on Windows)**

Run: `Get-ChildItem test/windows/*.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName }`
Expected: every test prints PASS.

(If you are not on Windows, document in the commit message which Windows tests were not executed locally; CI will validate them.)

- [ ] **Step 4: Final summary commit (only if any post-task fixes were needed)**

If everything passed without fixes, no commit is needed. If integration testing surfaced an issue and you patched it, commit the fix with a message like `Fix <issue> surfaced by integration testing`.

---

## Notes for implementers

- **Why `cp -L` not `cp`:** file-mode locals on macOS/Linux register `local-<hash>/roc` as a symlink to the user's binary. Copying without `-L` would preserve the symlink, which becomes dangling the moment the user moves the source. The whole point of `freeze` is to be source-independent.
- **Why frozen entries are exempt from `prune`:** `prune` operates only on `roc_nightly-*` by name pattern. Frozen entries are exempt by virtue of not matching that pattern. No code change is required to enforce this; the existing `find -name 'roc_nightly-*'` in `prune_nightlies` already excludes them. Confirm with a casual reading after Task 6 — no new test required.
- **Why `+N` / `-N` aren't extended:** these commands intentionally operate over the nightly timeline. A frozen active is treated the same as `alpha4` or `local-*` actives — the existing error path already covers this. No change.
- **Bash bare-name dispatch order:** the new bare-`<X>` frozen branch sits **before** `[ -e "$cmd" ]` (path treatment). This is deliberate per the spec's resolution order, so a frozen entry shadows a relative path of the same name. Users who want path treatment can still pass an explicit `./<name>` (which won't match `^[a-zA-Z0-9._-]+$` due to the leading `.`).
