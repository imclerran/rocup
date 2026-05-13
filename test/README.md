# rocup test suite

Integration tests for both the bash and PowerShell implementations.

## Layout

- `test/common/lib.sh` — bash assertion helpers, env isolation.
- `test/linux-macos/` — bash tests (run against `./rocup`).
- `test/windows/` — PowerShell tests (run against `./rocup.ps1`).
- `test/drift-check.sh` — verifies the two implementations advertise the same command surface AND share key usage-text phrasing. Implementation-detail differences (symlink vs junction, file-mode local registration, language-server dispatch) are intentionally not compared. Update `KNOWN_BASH_ONLY` / `KNOWN_PS_ONLY` for command-set divergences and `REQUIRED_PHRASES` for wording.

## Running locally

Linux/macOS:

```sh
for t in test/linux-macos/*.sh; do bash "$t" || exit 1; done
```

Windows (in PowerShell):

```ps1
Get-ChildItem test/windows/*.ps1 | ForEach-Object { & $_.FullName; if ($LASTEXITCODE -ne 0) { throw "FAIL: $($_.Name)" } }
```

Drift check (run from a Unix shell):

```sh
bash test/drift-check.sh
```

## Test conventions

- Each test sources `lib.sh` (bash) or dot-sources `lib.ps1` (PowerShell) and calls `setup_test_env` / `Initialize-TestEnv`.
- Each test runs against an isolated `$ROCUP_HOME` under a temp dir; cleanup happens via `trap`/`finally`.
- Tests that require network access to GitHub are gated by `ROCUP_TEST_NETWORK=1` and self-skip when it's unset. CI sets this in `.github/workflows/ci.yml` so they always run there.
- `ROCUP_TEST_OFFLINE=1` forces `fetch_recent_tags` / `Get-RecentTags` to return empty, exercising the installed-only fallback path in step-nightly. Used by the offline-step tests.
