. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Create a file (not directory) on the same volume.
$fakeRoc = Join-Path $script:TestTmpDir 'roc.exe'
Set-Content -LiteralPath $fakeRoc -Value '@echo off' -Encoding Ascii

$r = Invoke-Rocup $fakeRoc
if ($r.ExitCode -eq 0) {
    [Console]::Error.WriteLine("FAIL: file-path register should have failed")
    exit 1
}
Assert-Contains $r.Output 'directory' 'error mentions directory requirement'

Write-TestPass
