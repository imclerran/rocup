. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Fake local build dir on the same volume as $env:ROCUP_HOME (test tmp dir is).
$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value '@echo off`necho local' -Encoding Ascii

$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register-local succeeded'

# Active should be local-*.
$rocLink = Join-Path $env:ROCUP_HOME 'roc'
$active = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
if ($active -notlike 'local-*') {
    [Console]::Error.WriteLine("FAIL: expected local-* active, got $active")
    exit 1
}

# Junction should resolve back to $localDir.
$entry = Join-Path $env:ROCUP_HOME $active
$resolved = (Get-Item -LiteralPath $entry -Force).Target | Select-Object -First 1
Assert-Eq $localDir $resolved 'local entry resolves to source'

Write-TestPass
