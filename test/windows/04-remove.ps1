. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

New-FakeNightly -DateYmd '2025-10-25' -Hash 'aaaaaaa' | Out-Null
New-FakeNightly -DateYmd '2025-10-01' -Hash 'bbbbbbb' | Out-Null
Set-FakeActive 'roc_nightly-2025-10-25-aaaaaaa'

$r = Invoke-Rocup remove aaaaaaa
Assert-Eq 0 $r.ExitCode 'remove succeeded'

$removed = Join-Path $env:ROCUP_HOME 'roc_nightly-2025-10-25-aaaaaaa'
if (Test-Path -LiteralPath $removed) {
    [Console]::Error.WriteLine("FAIL: removed dir still exists")
    exit 1
}

$rocLink = Join-Path $env:ROCUP_HOME 'roc'
$active = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
Assert-Eq 'roc_nightly-2025-10-01-bbbbbbb' $active 'fallback activated'

Write-TestPass
