. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Build a fake local roc.
$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value '@echo off`necho fake' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register-local succeeded'

function Expect-Fail {
    param([string] $Msg, [string[]] $Argv)
    $r = Invoke-Rocup @Argv
    if ($r.ExitCode -eq 0) {
        [Console]::Error.WriteLine("FAIL: $Msg (expected non-zero exit, got 0)")
        [Console]::Error.WriteLine("  output: $($r.Output)")
        exit 1
    }
}

# 1. Empty name rejected.
Expect-Fail 'empty name rejected' @('freeze', '')

# 2. Bad characters rejected.
Expect-Fail 'spaces rejected' @('freeze', 'has space')
Expect-Fail 'slash rejected'  @('freeze', 'a/b')

# 3. Name starting with frozen- rejected.
Expect-Fail 'leading frozen- rejected' @('freeze', 'frozen-foo')

# 4. Name colliding with the active local's hash rejected.
$rocLink = Join-Path $env:ROCUP_HOME 'roc'
$active  = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
$activeHash = $active.Substring('local-'.Length)
Expect-Fail 'hash-collision rejected' @('freeze', $activeHash)

# 5. Collision-without-force.
New-Item -ItemType Directory -Path (Join-Path $env:ROCUP_HOME 'frozen-already-there') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $env:ROCUP_HOME 'frozen-already-there\roc.exe') -Value 'pre' -Encoding Ascii
Expect-Fail 'exists-no-force rejected' @('freeze', 'already-there')


# ---- Preconditions ----

# Remove the active junction so there's no active version.
[System.IO.Directory]::Delete((Join-Path $env:ROCUP_HOME 'roc'), $false)
Expect-Fail 'no-active rejected' @('freeze', 'test1')

# Re-register the local, then switch to a fake nightly (non-local active).
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 're-register succeeded'
New-FakeNightly -DateYmd '2025-10-25' -Hash 'abc1234' | Out-Null
Set-FakeActive 'roc_nightly-2025-10-25-abc1234'
Expect-Fail 'non-local-active rejected' @('freeze', 'test2')

# Dangling local: register a path then delete the source.
$danglingSrc = Join-Path $script:TestTmpDir 'will-be-deleted'
New-Item -ItemType Directory -Path $danglingSrc -Force | Out-Null
Set-Content -LiteralPath (Join-Path $danglingSrc 'roc.exe') -Value 'doomed' -Encoding Ascii
$r = Invoke-Rocup $danglingSrc
Assert-Eq 0 $r.ExitCode 'dangling-source register succeeded'
Remove-Item -LiteralPath $danglingSrc -Recurse -Force
Expect-Fail 'dangling-local rejected' @('freeze', 'test3')

Write-TestPass
