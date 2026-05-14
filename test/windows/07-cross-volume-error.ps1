. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Find a drive different from the one $env:ROCUP_HOME is on.
$homeRoot = [IO.Path]::GetPathRoot($env:ROCUP_HOME)
$otherDrive = Get-PSDrive -PSProvider FileSystem | Where-Object {
    "$($_.Root)" -ne $homeRoot -and (Test-Path -LiteralPath $_.Root)
} | Select-Object -First 1

if (-not $otherDrive) {
    Write-Host "SKIP: 07-cross-volume-error (only one volume available)"
    exit 0
}

$otherLocal = Join-Path $otherDrive.Root "rocup-test-cross-vol-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $otherLocal -Force | Out-Null
Set-Content -LiteralPath (Join-Path $otherLocal 'roc.exe') -Value '@echo off' -Encoding Ascii
try {
    $r = Invoke-Rocup $otherLocal
    if ($r.ExitCode -eq 0) {
        [Console]::Error.WriteLine("FAIL: cross-volume register should have failed")
        exit 1
    }
    Assert-Contains $r.Output 'cross-volume' 'error mentions cross-volume'

    Write-TestPass
}
finally {
    Remove-Item -LiteralPath $otherLocal -Recurse -Force -ErrorAction SilentlyContinue
}
