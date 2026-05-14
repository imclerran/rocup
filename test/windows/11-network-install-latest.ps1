# Network test: rocup latest against real GitHub, end-to-end including
# real binary execution. Gated by $env:ROCUP_TEST_NETWORK = '1'.
. "$PSScriptRoot\..\common\lib.ps1"

if ($env:ROCUP_TEST_NETWORK -ne '1') {
    Write-Host 'SKIP: 11-network-install-latest.ps1 (ROCUP_TEST_NETWORK != 1)'
    exit 0
}

Initialize-TestEnv

$r = Invoke-Rocup latest
if ($r.ExitCode -ne 0) {
    [Console]::Error.WriteLine("FAIL: 'rocup latest' exited $($r.ExitCode)")
    [Console]::Error.WriteLine($r.Output)
    exit 1
}

# A roc_nightly-* directory should exist now.
$nightlyDir = Get-ChildItem -LiteralPath $env:ROCUP_HOME -Directory -Filter 'roc_nightly-*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $nightlyDir) {
    [Console]::Error.WriteLine('FAIL: no roc_nightly-* directory after install')
    [Console]::Error.WriteLine($r.Output)
    exit 1
}

# roc.exe should be present and executable.
$rocExe = Join-Path $nightlyDir.FullName 'roc.exe'
if (-not (Test-Path -LiteralPath $rocExe -PathType Leaf)) {
    [Console]::Error.WriteLine("FAIL: $rocExe missing")
    exit 1
}

# Active junction should point at it.
$rocLink = Join-Path $env:ROCUP_HOME 'roc'
$linkTarget = (Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1
Assert-Eq $nightlyDir.FullName $linkTarget 'active junction targets installed nightly'

# Run roc.exe --version and verify it reports a hash matching the dir.
$rocVersion = & $rocExe --version 2>&1 | Out-String
$expectedHash = ($nightlyDir.Name -split '-')[-1]
Assert-Contains $rocVersion $expectedHash 'roc --version reports installed hash'

Write-TestPass
