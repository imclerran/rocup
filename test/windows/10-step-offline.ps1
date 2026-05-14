# Forces Get-RecentTags to return empty via ROCUP_TEST_OFFLINE=1, exercising
# the installed-only fallback path of Step-Nightly deterministically.
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

New-FakeNightly -DateYmd '2025-10-25' -Hash 'aaaaaaa' | Out-Null
New-FakeNightly -DateYmd '2025-10-20' -Hash 'bbbbbbb' | Out-Null
New-FakeNightly -DateYmd '2025-10-15' -Hash 'ccccccc' | Out-Null
Set-FakeActive 'roc_nightly-2025-10-20-bbbbbbb'

$env:ROCUP_TEST_OFFLINE = '1'
try {
    # -1 from 2025-10-20 should activate 2025-10-15.
    $r = Invoke-Rocup -1
    Assert-Eq 0 $r.ExitCode '-1 succeeded'
    $rocLink = Join-Path $env:ROCUP_HOME 'roc'
    $active = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
    Assert-Eq 'roc_nightly-2025-10-15-ccccccc' $active '-1 lands on next-older nightly'

    # +2 from 2025-10-15 should activate 2025-10-25.
    $r = Invoke-Rocup +2
    Assert-Eq 0 $r.ExitCode '+2 succeeded'
    $active = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
    Assert-Eq 'roc_nightly-2025-10-25-aaaaaaa' $active '+2 lands two newer'

    # Stepping past the edge should error.
    $r = Invoke-Rocup +1
    if ($r.ExitCode -eq 0) {
        [Console]::Error.WriteLine('FAIL: +1 past newest should have failed')
        exit 1
    }
    Assert-Contains $r.Output 'only 0 installed nightlies newer than active' 'edge error message'
}
finally {
    Remove-Item Env:\ROCUP_TEST_OFFLINE -ErrorAction SilentlyContinue
}

Write-TestPass
