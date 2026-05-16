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

Write-TestPass
