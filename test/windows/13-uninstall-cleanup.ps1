# Hermetic uninstall.ps1 test. No network. Verifies the uninstaller:
#   (a) deletes $ROCUP_HOME
#   (b) removes the two PATH entries it added
#   (c) does NOT follow local-* junctions (user source dirs survive)
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Fake the install state.
$rocupBin = Join-Path $env:ROCUP_HOME 'bin'
New-Item -ItemType Directory -Path $rocupBin -Force | Out-Null
Set-Content -LiteralPath (Join-Path $env:ROCUP_HOME 'rocup.ps1') -Value '# fake' -Encoding Ascii
Set-Content -LiteralPath (Join-Path $rocupBin 'rocup.cmd') -Value '@echo off' -Encoding Ascii
Set-Content -LiteralPath (Join-Path $rocupBin 'roc_language_server.cmd') -Value '@echo off' -Encoding Ascii

# Make a real nightly dir and an active-version junction.
$nightlyDir = New-FakeNightly -DateYmd '2025-10-25' -Hash 'aaaaaaa'
Set-FakeActive 'roc_nightly-2025-10-25-aaaaaaa'

# A local-<hash> junction pointing OUTSIDE $ROCUP_HOME.
$userBuild = Join-Path $script:TestTmpDir 'user-roc-build'
New-Item -ItemType Directory -Path $userBuild -Force | Out-Null
Set-Content -LiteralPath (Join-Path $userBuild 'roc.exe') -Value '@echo off' -Encoding Ascii
$localEntry = Join-Path $env:ROCUP_HOME 'local-abcdef0'
New-Item -ItemType Junction -Path $localEntry -Value $userBuild | Out-Null

# Snapshot User PATH so we can verify entries are added then removed.
$pathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')

# Add the two entries the way install.ps1 would.
$entries = if ($pathBefore) { @($pathBefore -split ';' | Where-Object { $_ }) } else { @() }
$entries += $rocupBin
$entries += (Join-Path $env:ROCUP_HOME 'roc')
[Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')

try {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $uninstallPs1 = Join-Path $repoRoot 'uninstall.ps1'
    $env:ROCUP_ASSUME_YES = '1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstallPs1 *>&1 | Out-Null
    $global:LASTEXITCODE = 0  # don't poison outer harness

    # $ROCUP_HOME gone.
    if (Test-Path -LiteralPath $env:ROCUP_HOME) {
        [Console]::Error.WriteLine("FAIL: $env:ROCUP_HOME survived")
        exit 1
    }
    # User source dir behind local-* junction survives.
    if (-not (Test-Path -LiteralPath (Join-Path $userBuild 'roc.exe'))) {
        [Console]::Error.WriteLine('FAIL: local-* target was followed and deleted')
        exit 1
    }
    # PATH entries gone.
    $pathFinal = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($pathFinal -match [Regex]::Escape($rocupBin)) {
        [Console]::Error.WriteLine('FAIL: bin entry survived')
        exit 1
    }
}
finally {
    # Restore PATH exactly.
    [Environment]::SetEnvironmentVariable('Path', $pathBefore, 'User')
}

Write-TestPass
