#requires -version 5.1

<#
rocup Windows uninstaller. Designed to be safe to invoke from a one-liner:

    iwr -useb https://raw.githubusercontent.com/imclerran/rocup/main/uninstall.ps1 | iex

Mirrors install.ps1: prompts unless $env:ROCUP_ASSUME_YES = '1', errors if
non-interactive without explicit assume-yes. Defaults to abort on empty reply
since uninstall is destructive.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$RocupHome = if ($env:ROCUP_HOME) { $env:ROCUP_HOME } else { Join-Path $env:USERPROFILE '.rocup' }
$BinDir    = Join-Path $RocupHome 'bin'
$RocDir    = Join-Path $RocupHome 'roc'

Write-Host "This will uninstall rocup:"
Write-Host "  * Remove $BinDir and $RocDir from your User PATH"
Write-Host "  * Delete $RocupHome (including all installed Roc nightlies and local-* junctions)"
Write-Host ""

if (-not (Test-Path -LiteralPath $RocupHome)) {
    Write-Host "note: $RocupHome does not exist; will still clean up any stale PATH entries."
    Write-Host ""
}

if ($env:ROCUP_ASSUME_YES -ne '1') {
    if (-not [Environment]::UserInteractive) {
        [Console]::Error.WriteLine("error: non-interactive session; set `$env:ROCUP_ASSUME_YES = '1' to uninstall non-interactively")
        exit 1
    }
    $reply = Read-Host "Proceed? [y/N]"
    switch -Regex ($reply) {
        '^(y|Y|yes|YES|Yes)$' { }
        default               { Write-Host "aborted."; exit 1 }
    }
}

# 1. Remove PATH entries (idempotent)
function Remove-UserPathEntry {
    param([Parameter(Mandatory)][string] $Dir)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { return $false }
    $entries = @($userPath -split ';' | Where-Object { $_ })
    if ($entries -notcontains $Dir) { return $false }
    $kept = @($entries | Where-Object { $_ -ne $Dir })
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
    Write-Host ".. removed $Dir from User PATH"
    return $true
}

$null = Remove-UserPathEntry $BinDir
$null = Remove-UserPathEntry $RocDir

# 2. Delete any top-level junctions in $RocupHome before recursive removal.
# Remove-Item -Recurse on a junction follows the link target, which for
# 'rocup <dir>' registrations points outside $RocupHome to a user-owned
# directory. .NET Directory.Delete with recursive=$false deletes only the
# reparse-point entry, leaving the target intact.
if (Test-Path -LiteralPath $RocupHome) {
    $junctions = @(Get-ChildItem -LiteralPath $RocupHome -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LinkType -eq 'Junction' })
    foreach ($j in $junctions) {
        [System.IO.Directory]::Delete($j.FullName, $false)
        Write-Host ".. deleted junction $($j.FullName)"
    }

    Remove-Item -LiteralPath $RocupHome -Recurse -Force
    Write-Host ".. deleted $RocupHome"
}

Write-Host ""
Write-Host "Uninstalled. Restart your terminal so PATH updates take effect."
