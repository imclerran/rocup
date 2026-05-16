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

Write-TestPass
