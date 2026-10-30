# Offline: ConvertFrom-NightlyTag accepts numeric, full-name and abbreviated months.
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Dot-source the script to load its functions without running dispatch.
. $env:ROCUP_PS1

Assert-Eq '2026-10-30' (ConvertFrom-NightlyTag 'nightly-2026-10-30-0602c5f') 'numeric month'
Assert-Eq '2026-01-01' (ConvertFrom-NightlyTag 'nightly-2026-01-01-abcdef0') 'numeric January'
Assert-Eq '2026-12-31' (ConvertFrom-NightlyTag 'nightly-2026-12-31-abcdef0') 'numeric December'
Assert-Eq '2026-08-05' (ConvertFrom-NightlyTag 'nightly-2026-August-05-24f0b47') 'full month name'
Assert-Eq '2026-08-05' (ConvertFrom-NightlyTag 'nightly-2026-Aug-05-24f0b47') 'abbreviated month name'

$malformed = @(
    'nightly-2026-00-05-abcdef0', 'nightly-2026-13-05-abcdef0', 'nightly-2026-8-05-abcdef0',
    'nightly-2026-Foo-05-abcdef0', 'release-2026-08-05-abcdef0', 'nightly-2026-08-05'
)
foreach ($bad in $malformed) {
    $threw = $false
    try { ConvertFrom-NightlyTag $bad | Out-Null } catch { $threw = $true }
    if (-not $threw) {
        [Console]::Error.WriteLine("FAIL: accepted malformed tag '$bad'")
        exit 1
    }
}

Write-TestPass
