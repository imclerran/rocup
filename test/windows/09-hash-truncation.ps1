. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

New-FakeNightly -DateYmd '2025-10-25' -Hash 'a1b2c3d' | Out-Null
Set-FakeActive 'roc_nightly-2025-10-25-a1b2c3d'

# 8-char hash should truncate and find the same dir.
$r = Invoke-Rocup remove 'a1b2c3d0'
Assert-Eq 0 $r.ExitCode 'remove with 8-char hash succeeded'

$removed = Join-Path $env:ROCUP_HOME 'roc_nightly-2025-10-25-a1b2c3d'
if (Test-Path -LiteralPath $removed) {
    [Console]::Error.WriteLine("FAIL: 8-char hash didn't truncate")
    exit 1
}

Write-TestPass
