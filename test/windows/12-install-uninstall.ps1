# End-to-end install.ps1 + uninstall.ps1 against real GitHub.
# Gated by $env:ROCUP_TEST_NETWORK = '1'.
#
# Snapshots the current User PATH before running so cleanup is robust even
# if the installer adds entries we don't fully account for.
. "$PSScriptRoot\..\common\lib.ps1"

if ($env:ROCUP_TEST_NETWORK -ne '1') {
    Write-Host 'SKIP: 12-install-uninstall.ps1 (ROCUP_TEST_NETWORK != 1)'
    exit 0
}

Initialize-TestEnv

# Determine repo + branch to install from. In CI's detached-HEAD checkout,
# prefer GITHUB_HEAD_REF or GITHUB_REF_NAME.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $repoRoot
try {
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($branch -eq 'HEAD') {
        if ($env:GITHUB_HEAD_REF)  { $branch = $env:GITHUB_HEAD_REF }
        elseif ($env:GITHUB_REF_NAME) { $branch = $env:GITHUB_REF_NAME }
        else { $branch = 'main' }
    }
    $remoteUrl = (git config --get remote.origin.url).Trim()
}
finally { Pop-Location }
# Convert https://github.com/owner/repo(.git) to owner/repo.
if ($remoteUrl -match 'github\.com[:/]([^/]+)/([^/.]+)') {
    $repoSlug = "$($Matches[1])/$($Matches[2])"
} else {
    $repoSlug = 'imclerran/rocup'
}

# Snapshot User PATH so we can restore exactly.
$pathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')

$env:ROCUP_REPO    = $repoSlug
$env:ROCUP_BRANCH  = $branch
$env:ROCUP_ASSUME_YES = '1'

$installPs1 = Join-Path $repoRoot 'install.ps1'
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installPs1 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("FAIL: install.ps1 exited $LASTEXITCODE")
        exit 1
    }

    # Verify expected state.
    if (-not (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'rocup.ps1'))) {
        [Console]::Error.WriteLine('FAIL: rocup.ps1 not installed')
        exit 1
    }
    if (-not (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'bin\rocup.cmd'))) {
        [Console]::Error.WriteLine('FAIL: rocup.cmd shim missing')
        exit 1
    }
    if (-not (Test-Path -LiteralPath (Join-Path $env:ROCUP_HOME 'bin\roc_language_server.cmd'))) {
        [Console]::Error.WriteLine('FAIL: LS shim missing')
        exit 1
    }
    $rocLink = Join-Path $env:ROCUP_HOME 'roc'
    if (-not (Test-Path -LiteralPath $rocLink)) {
        [Console]::Error.WriteLine("FAIL: active junction $rocLink missing")
        exit 1
    }
    $pathAfter = [Environment]::GetEnvironmentVariable('Path', 'User')
    Assert-Contains $pathAfter (Join-Path $env:ROCUP_HOME 'bin') 'bin on User PATH'
    Assert-Contains $pathAfter (Join-Path $env:ROCUP_HOME 'roc') 'roc on User PATH'

    # Now run uninstall.
    $uninstallPs1 = Join-Path $repoRoot 'uninstall.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstallPs1 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("FAIL: uninstall.ps1 exited $LASTEXITCODE")
        exit 1
    }

    if (Test-Path -LiteralPath $env:ROCUP_HOME) {
        [Console]::Error.WriteLine("FAIL: $env:ROCUP_HOME survived uninstall")
        exit 1
    }
    $pathFinal = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($pathFinal -match [Regex]::Escape((Join-Path $env:ROCUP_HOME 'bin'))) {
        [Console]::Error.WriteLine('FAIL: bin entry survived uninstall')
        exit 1
    }
    if ($pathFinal -match [Regex]::Escape((Join-Path $env:ROCUP_HOME 'roc'))) {
        [Console]::Error.WriteLine('FAIL: roc entry survived uninstall')
        exit 1
    }
}
finally {
    # Belt-and-suspenders: restore User PATH to the pre-test snapshot, in case
    # the installer or uninstaller left stray entries.
    [Environment]::SetEnvironmentVariable('Path', $pathBefore, 'User')
}

Write-TestPass
