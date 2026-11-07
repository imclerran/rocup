# Offline: safe builds (roc_nightly-YYYY-MM-DD-<hash>-safe) are addressed as
# <hash>-safe, live beside the regular build of the same nightly, and +N/-N
# steps within the active build's variant.
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

New-FakeNightly -DateYmd '2026-11-07' -Hash 'ad3a5d2' | Out-Null
New-FakeNightly -DateYmd '2026-11-07' -Hash 'ad3a5d2-safe' | Out-Null
New-FakeNightly -DateYmd '2026-11-06' -Hash '34f137a' | Out-Null
New-FakeNightly -DateYmd '2026-11-06' -Hash '34f137a-safe' | Out-Null
New-FakeNightly -DateYmd '2026-11-04' -Hash '2622062' | Out-Null
Set-FakeActive 'roc_nightly-2026-11-07-ad3a5d2'

$rocLink = Join-Path $env:ROCUP_HOME 'roc'
function Get-Active { Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1) }

# list shows the token you type to get each build back.
$r = Invoke-Rocup list
Assert-Eq 0 $r.ExitCode 'list succeeded'
Assert-Contains $r.Output ' -> nightly (11/07/2026) <ad3a5d2>' 'regular build listed and active'
Assert-Contains $r.Output '    nightly (11/07/2026) <ad3a5d2-safe>' 'safe build listed with suffix'
Assert-Contains $r.Output '    nightly (11/06/2026) <34f137a-safe>' 'older safe build listed'

# <hash>-safe activates the installed safe build without touching the network;
# 8-char hashes are accepted like the regular form.
$r = Invoke-Rocup ad3a5d2-safe
Assert-Eq 0 $r.ExitCode '<hash>-safe succeeded'
Assert-Eq 'roc_nightly-2026-11-07-ad3a5d2-safe' (Get-Active) '<hash>-safe activates the safe build'
$r = Invoke-Rocup ad3a5d2
Assert-Eq 'roc_nightly-2026-11-07-ad3a5d2' (Get-Active) '<hash> activates the regular build'
$r = Invoke-Rocup ad3a5d2f-safe
Assert-Eq 'roc_nightly-2026-11-07-ad3a5d2-safe' (Get-Active) '8-char <hash>-safe is truncated'

# Offline stepping stays within the variant.
$env:ROCUP_TEST_OFFLINE = '1'
try {
    $r = Invoke-Rocup -1
    Assert-Eq 0 $r.ExitCode '-1 from safe succeeded'
    Assert-Eq 'roc_nightly-2026-11-06-34f137a-safe' (Get-Active) '-1 from safe skips the regular 11-07 build'

    $r = Invoke-Rocup -1
    if ($r.ExitCode -eq 0) {
        [Console]::Error.WriteLine('FAIL: -1 past oldest safe build should have failed')
        exit 1
    }
    Assert-Contains $r.Output 'only 0 installed safe nightlies older than active' 'oldest-safe edge error'
    Assert-Eq 'roc_nightly-2026-11-06-34f137a-safe' (Get-Active) 'failed step leaves active unchanged'

    $r = Invoke-Rocup +1
    Assert-Eq 'roc_nightly-2026-11-07-ad3a5d2-safe' (Get-Active) '+1 from safe lands on the newer safe build'

    $r = Invoke-Rocup 34f137a
    $r = Invoke-Rocup -1
    Assert-Eq 'roc_nightly-2026-11-04-2622062' (Get-Active) '-1 from regular skips the safe 11-06 build'
    $r = Invoke-Rocup +2
    Assert-Eq 'roc_nightly-2026-11-07-ad3a5d2' (Get-Active) '+2 from regular walks regular builds only'
}
finally {
    Remove-Item Env:\ROCUP_TEST_OFFLINE -ErrorAction SilentlyContinue
}

# remove and freeze treat <hash>-safe as its own entry.
$r = Invoke-Rocup ad3a5d2-safe
$r = Invoke-Rocup remove ad3a5d2-safe
Assert-Eq 0 $r.ExitCode 'remove <hash>-safe succeeded'
if (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'roc_nightly-2026-11-07-ad3a5d2-safe')) {
    [Console]::Error.WriteLine('FAIL: safe build not removed'); exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'roc_nightly-2026-11-07-ad3a5d2'))) {
    [Console]::Error.WriteLine('FAIL: regular build removed alongside safe'); exit 1
}
Assert-Eq 'roc_nightly-2026-11-07-ad3a5d2' (Get-Active) 'fallback after removing active safe build'
$r = Invoke-Rocup remove ad3a5d2-safe
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine('FAIL: removing a missing safe build should fail'); exit 1 }
Assert-Contains $r.Output 'roc_nightly-ad3a5d2-safe does not exist' 'missing safe build error'
$r = Invoke-Rocup remove ad3a5d2
if (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'roc_nightly-2026-11-07-ad3a5d2')) {
    [Console]::Error.WriteLine('FAIL: regular build not removed'); exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'roc_nightly-2026-11-06-34f137a-safe'))) {
    [Console]::Error.WriteLine('FAIL: safe 11-06 build removed by regular remove'); exit 1
}

# prune counts safe builds as nightlies.
$r = Invoke-Rocup 34f137a-safe
$r = Invoke-Rocup prune 1
Assert-Eq 0 $r.ExitCode 'prune succeeded'
Assert-Contains $r.Output 'keep roc_nightly-2026-11-06-34f137a-safe (active)' 'prune keeps the active safe build'
Assert-Contains $r.Output 'remove roc_nightly-2026-11-04-2622062' 'prune removes the older regular build'
if (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'roc_nightly-2026-11-06-34f137a')) {
    [Console]::Error.WriteLine('FAIL: prune 1 should drop the regular 11-06 build'); exit 1
}

# Function-level checks. Dot-sourcing rocup.ps1 replaces the test helper
# Invoke-Rocup with rocup's own dispatcher, so everything that drives rocup as
# a child process has to come before this point.
. $env:ROCUP_PS1

# Online stepping (stubbed tag list): the safe timeline is shorter than the
# regular one, and running off its end errors with a pointer to the regular
# build instead of silently crossing over.
function Install-Nightly { param($Hash, $Platform, $Variant = '') Write-Output "install $Hash $(if ($Variant) { $Variant } else { 'regular' })" }
function Get-Platform { 'test' }
$safeTags = @('nightly-2026-11-07-ad3a5d2-safe', 'nightly-2026-11-06-34f137a-safe')
$regularTags = @('nightly-2026-11-07-ad3a5d2', 'nightly-2026-11-06-34f137a', 'nightly-2026-11-04-2622062')
$out = @(Step-NightlyViaTags -Sign '-' -N 1 -ActiveHash 'ad3a5d2' -Tags $safeTags -Variant 'safe' 6>&1) -join "`n"
Assert-Contains $out 'install 34f137a safe' '-1 along the safe timeline'
$threw = $false
try { Step-NightlyViaTags -Sign '-' -N 1 -ActiveHash '34f137a' -Tags $safeTags -Variant 'safe' 6>&1 | Out-Null } catch { $threw = $true; $msg = $_.Exception.Message }
if (-not $threw) { [Console]::Error.WriteLine('FAIL: -1 past oldest safe tag should throw'); exit 1 }
Assert-Contains $msg 'only 0 safe nightlies older than active' 'oldest-safe tag error'
Assert-Contains $msg "Use 'rocup 34f137a' to switch to the regular build" 'error names the regular build'
$out = @(Step-NightlyViaTags -Sign '-' -N 1 -ActiveHash '34f137a' -Tags $regularTags 6>&1) -join "`n"
Assert-Contains $out 'install 2622062 regular' '-1 along the regular timeline'

# Freeze names cannot collide with an installed safe build (34f137a-safe is
# still installed after the prune above; 2622062-safe never was).
$threw = $false
try { Test-FreezeName '34f137a-safe' | Out-Null } catch { $threw = $true }
if (-not $threw) { [Console]::Error.WriteLine('FAIL: freeze name colliding with an installed safe build should be rejected'); exit 1 }
Assert-Eq '2622062-safe' (Test-FreezeName '2622062-safe') 'freeze name of a safe build that is not installed allowed'

Write-TestPass
