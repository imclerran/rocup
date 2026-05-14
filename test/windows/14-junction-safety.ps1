# Junction-safety guard test. If $ROCUP_HOME\roc exists but isn't a junction
# (e.g. user manually created a real directory there), Set-ActiveVersion must
# refuse to delete it.
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Create a real directory at the active-version path.
$rocLink = Join-Path $env:ROCUP_HOME 'roc'
New-Item -ItemType Directory -Path $rocLink -Force | Out-Null
Set-Content -LiteralPath (Join-Path $rocLink 'important.txt') -Value 'user data' -Encoding Ascii

# Make a fake nightly to try to activate.
New-FakeNightly -DateYmd '2025-10-25' -Hash 'aaaaaaa' | Out-Null

# Attempting to activate should fail with the safety message.
$r = Invoke-Rocup aaaaaaa
if ($r.ExitCode -eq 0) {
    [Console]::Error.WriteLine('FAIL: activation should refuse to delete real directory')
    exit 1
}
Assert-Contains $r.Output 'refusing to delete' 'safety message present'

# User data must still be on disk.
$important = Join-Path $rocLink 'important.txt'
if (-not (Test-Path -LiteralPath $important)) {
    [Console]::Error.WriteLine('FAIL: user data was deleted')
    exit 1
}

Write-TestPass
