. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

New-FakeNightly -DateYmd '2025-10-25' -Hash 'aaaaaaa' | Out-Null
New-FakeNightly -DateYmd '2025-10-20' -Hash 'bbbbbbb' | Out-Null
New-FakeNightly -DateYmd '2025-10-15' -Hash 'ccccccc' | Out-Null
New-FakeNightly -DateYmd '2025-10-10' -Hash 'ddddddd' | Out-Null
Set-FakeActive 'roc_nightly-2025-10-25-aaaaaaa'

$r = Invoke-Rocup prune 2
Assert-Eq 0 $r.ExitCode 'prune succeeded'

$keep1 = Join-Path $env:ROCUP_HOME 'roc_nightly-2025-10-25-aaaaaaa'
$keep2 = Join-Path $env:ROCUP_HOME 'roc_nightly-2025-10-20-bbbbbbb'
$gone1 = Join-Path $env:ROCUP_HOME 'roc_nightly-2025-10-15-ccccccc'
$gone2 = Join-Path $env:ROCUP_HOME 'roc_nightly-2025-10-10-ddddddd'

if (-not (Test-Path -LiteralPath $keep1)) { [Console]::Error.WriteLine('FAIL: newest gone'); exit 1 }
if (-not (Test-Path -LiteralPath $keep2)) { [Console]::Error.WriteLine('FAIL: 2nd-newest gone'); exit 1 }
if (Test-Path -LiteralPath $gone1)        { [Console]::Error.WriteLine('FAIL: 3rd was kept'); exit 1 }
if (Test-Path -LiteralPath $gone2)        { [Console]::Error.WriteLine('FAIL: 4th was kept'); exit 1 }

Write-TestPass
