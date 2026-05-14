# Error-path coverage. No network needed.
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Invalid hash length.
$r = Invoke-Rocup abc
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine("FAIL: 'abc' should error"); exit 1 }
Assert-Contains $r.Output 'invalid argument' 'short hash rejected'

# Non-hex characters.
$r = Invoke-Rocup zzzzzzz
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine("FAIL: 'zzzzzzz' should error"); exit 1 }
Assert-Contains $r.Output 'invalid argument' 'non-hex rejected'

# 'remove' with no arg.
$r = Invoke-Rocup remove
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine("FAIL: 'remove' no-arg should error"); exit 1 }
Assert-Contains $r.Output 'requires an argument' 'remove no-arg errors'

# 'prune' with no arg.
$r = Invoke-Rocup prune
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine("FAIL: 'prune' no-arg should error"); exit 1 }
Assert-Contains $r.Output 'requires a count' 'prune no-arg errors'

# Step with no active version.
$r = Invoke-Rocup -1
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine("FAIL: -1 with no active should error"); exit 1 }
Assert-Contains $r.Output 'no active version' 'step without active errors'

# Step when active is local-*.
New-FakeNightly -DateYmd '2025-10-25' -Hash 'aaaaaaa' | Out-Null
# Create a fake local-* entry by junctioning to the nightly dir.
$localEntry = Join-Path $env:ROCUP_HOME 'local-1234567'
$nightlyDir = Join-Path $env:ROCUP_HOME 'roc_nightly-2025-10-25-aaaaaaa'
New-Item -ItemType Junction -Path $localEntry -Value $nightlyDir | Out-Null
Set-FakeActive 'local-1234567'

$r = Invoke-Rocup -1
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine("FAIL: -1 with active=local should error"); exit 1 }
Assert-Contains $r.Output 'requires an active nightly' 'step from local errors'

# Remove nonexistent.
$r = Invoke-Rocup remove 9999999
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine("FAIL: remove of nonexistent should error"); exit 1 }
Assert-Contains $r.Output 'does not exist' 'remove nonexistent errors'

Write-TestPass
