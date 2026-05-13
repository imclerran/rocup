#requires -version 5.1

<#
rocup Windows installer. Designed to be safe to invoke from a one-liner:

    iwr -useb https://raw.githubusercontent.com/imclerran/rocup/main/install.ps1 | iex

Mirrors install.sh: prompts unless $env:ROCUP_ASSUME_YES = '1', errors if
non-interactive without explicit assume-yes.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Repo   = if ($env:ROCUP_REPO)   { $env:ROCUP_REPO }   else { 'imclerran/rocup' }
$Branch = if ($env:ROCUP_BRANCH) { $env:ROCUP_BRANCH } else { 'main' }

$RocupHome = if ($env:ROCUP_HOME) { $env:ROCUP_HOME } else { Join-Path $env:USERPROFILE '.rocup' }
$BinDir    = Join-Path $RocupHome 'bin'

$RawBase   = "https://raw.githubusercontent.com/$Repo/$Branch"

Write-Host "This will install rocup:"
Write-Host "  * Download rocup.ps1 into $RocupHome"
Write-Host "  * Install rocup.cmd and roc_language_server.cmd shims into $BinDir"
Write-Host "  * Add $BinDir and $RocupHome\roc to your User PATH"
Write-Host "  * Download the latest Roc nightly into $RocupHome"
Write-Host ""

if ($env:ROCUP_ASSUME_YES -ne '1') {
    if (-not [Environment]::UserInteractive) {
        [Console]::Error.WriteLine("error: non-interactive session; set `$env:ROCUP_ASSUME_YES = '1' to install non-interactively")
        exit 1
    }
    $reply = Read-Host "Proceed? [Y/n]"
    switch -Regex ($reply) {
        '^(n|N|no|NO|No)$' { Write-Host "aborted."; exit 1 }
        default            { }
    }
}

New-Item -ItemType Directory -Path $RocupHome -Force | Out-Null
New-Item -ItemType Directory -Path $BinDir    -Force | Out-Null

# 1. Download rocup.ps1
$rocupPs1 = Join-Path $RocupHome 'rocup.ps1'
Write-Host ".. downloading rocup.ps1 from $RawBase/rocup.ps1"
$oldProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    Invoke-WebRequest -Uri "$RawBase/rocup.ps1" -OutFile $rocupPs1 -UseBasicParsing
}
finally { $ProgressPreference = $oldProgress }
Write-Host ".. installed rocup.ps1 at $rocupPs1"

# 2. Write rocup.cmd shim
$rocupCmd = Join-Path $BinDir 'rocup.cmd'
$rocupCmdContent = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\rocup.ps1" %*
'@
Set-Content -LiteralPath $rocupCmd -Value $rocupCmdContent -Encoding Ascii
Write-Host ".. installed $rocupCmd"

# 3. Write roc_language_server.cmd shim
$lsCmd = Join-Path $BinDir 'roc_language_server.cmd'
$lsCmdContent = @'
@echo off
setlocal
if "%ROCUP_HOME%"=="" set "ROCUP_HOME=%USERPROFILE%\.rocup"
set "ROC=%ROCUP_HOME%\roc\roc.exe"

if not exist "%ROC%" (
    >&2 echo error: no active roc version. Run 'rocup latest' first.
    exit /b 127
)

"%ROC%" experimental-lsp %*
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath $lsCmd -Value $lsCmdContent -Encoding Ascii
Write-Host ".. installed $lsCmd"

# 4. Add PATH entries (idempotent)
function Add-UserPathEntry {
    param([Parameter(Mandatory)][string] $Dir)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = if ($userPath) { $userPath -split ';' | Where-Object { $_ } } else { @() }
    if ($entries -contains $Dir) { return $false }
    $entries += $Dir
    [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
    Write-Host ".. added $Dir to User PATH"
    return $true
}

$null = Add-UserPathEntry $BinDir
$null = Add-UserPathEntry (Join-Path $RocupHome 'roc')

# 5. Run rocup latest with ASSUME_YES so any future prompts (none today) are silenced.
$env:ROCUP_ASSUME_YES = '1'
$env:ROCUP_HOME = $RocupHome
# Set-StrictMode -Version 2.0 errors when reading an unset variable. $LASTEXITCODE
# is only auto-set by native commands or 'exit N', so a successful rocup.ps1 run
# (which returns via Invoke-Rocup, not exit) leaves it unset. Seed it here.
$LASTEXITCODE = 0
& $rocupPs1 latest
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("error: 'rocup latest' failed (exit $LASTEXITCODE).")
    [Console]::Error.WriteLine("       rocup is installed but no Roc nightly was downloaded.")
    [Console]::Error.WriteLine("       Restart your terminal and run 'rocup latest' manually after fixing the issue.")
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Installed. Restart your terminal so PATH updates take effect, then run 'rocup' to verify."
