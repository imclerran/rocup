. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

New-FakeNightly -DateYmd '2025-10-25' -Hash 'aaaaaaa' | Out-Null
New-FakeNightly -DateYmd '2025-10-01' -Hash 'bbbbbbb' | Out-Null
Set-FakeActive 'roc_nightly-2025-10-25-aaaaaaa'

$r = Invoke-Rocup list
Assert-Contains $r.Output 'nightly (10/25/2025) <aaaaaaa>' 'newer listed'
Assert-Contains $r.Output 'nightly (10/01/2025) <bbbbbbb>' 'older listed'
Assert-Contains $r.Output ' -> nightly (10/25/2025) <aaaaaaa>' 'active marker'

Write-TestPass
