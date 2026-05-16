#requires -version 5.1

<#
rocup - Roc compiler version manager for Windows.
Mirrors the bash 'rocup' script function-for-function where possible.
See docs/superpowers/specs/2026-05-13-rocup-windows-port-design.md for design notes.
#>

[CmdletBinding()]
param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]] $Args = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# --- Configuration --------------------------------------------------------

$script:RocupHome = if ($env:ROCUP_HOME) {
    $env:ROCUP_HOME
} elseif ($env:USERPROFILE) {
    Join-Path $env:USERPROFILE '.rocup'
} else {
    # Allow the script to load on non-Windows hosts (e.g. CI's drift-check
    # invoking `pwsh --help` to inspect the command surface). Any function
    # that actually touches the filesystem will fail at the operation site
    # rather than crash before usage can print.
    $null
}

# --- Platform detection ---------------------------------------------------

function Get-Platform {
    # PROCESSOR_ARCHITEW6432 is set on WOW64 (32-bit process on 64-bit OS) and
    # holds the OS arch; otherwise PROCESSOR_ARCHITECTURE does. Both are always
    # set by Windows, with no dependency on the .NET Framework version.
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64' { 'windows_x86_64' }
        'ARM64' { 'windows_arm64' }
        default { throw "error: unsupported Windows architecture: $arch" }
    }
}

# --- Core helpers ---------------------------------------------------------

function Resolve-LinkTarget {
    # If $Path is a junction or symlink, return a Get-Item on its target so the
    # caller sees the underlying directory's metadata (e.g. zig-out\bin's
    # LastWriteTime) rather than the reparse point's, which is frozen at the
    # time the link was created.
    param([Parameter(Mandatory)][string] $Path)
    $item = Get-Item -LiteralPath $Path
    if ($item.LinkType -in 'Junction','SymbolicLink') {
        $target = $item.Target | Select-Object -First 1
        if ($target) {
            if (-not [System.IO.Path]::IsPathRooted($target)) {
                $target = Join-Path (Split-Path -Parent $Path) $target
            }
            $resolved = Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
            if ($resolved) { return $resolved }
        }
    }
    $item
}

function Get-Mtime {
    param([Parameter(Mandatory)][string] $Path)
    (Resolve-LinkTarget $Path).LastWriteTime.ToFileTimeUtc()
}

function Convert-MonthNameToNumber {
    param([Parameter(Mandatory)][string] $Name)
    switch ($Name) {
        { $_ -in 'Jan','January' }      { return '01' }
        { $_ -in 'Feb','February' }     { return '02' }
        { $_ -in 'Mar','March' }        { return '03' }
        { $_ -in 'Apr','April' }        { return '04' }
        'May'                           { return '05' }
        { $_ -in 'Jun','June' }         { return '06' }
        { $_ -in 'Jul','July' }         { return '07' }
        { $_ -in 'Aug','August' }       { return '08' }
        { $_ -in 'Sep','September' }    { return '09' }
        { $_ -in 'Oct','October' }      { return '10' }
        { $_ -in 'Nov','November' }     { return '11' }
        { $_ -in 'Dec','December' }     { return '12' }
        default { throw "error: unknown month name '$Name'" }
    }
}

function ConvertFrom-NightlyTag {
    param([Parameter(Mandatory)][string] $Tag)
    # Tag format: nightly-YYYY-Mmm-DD-<hash>
    $parts = $Tag -split '-'
    if ($parts.Count -lt 5 -or $parts[0] -ne 'nightly') {
        throw "error: unexpected nightly tag format: $Tag"
    }
    $year = $parts[1]
    $monName = $parts[2]
    $day = $parts[3]
    $monNum = Convert-MonthNameToNumber $monName
    "$year-$monNum-$day"
}

function Get-DirSortKey {
    param([Parameter(Mandatory)][string] $Dir)
    $name = Split-Path -Leaf $Dir
    if ($name -match '^roc_nightly-([0-9]{4})-([0-9]{2})-([0-9]{2})-[0-9a-f]{7}$') {
        return "$($Matches[1])-$($Matches[2])-$($Matches[3])"
    }
    # Prefer the roc.exe binary's mtime: a dir's mtime only changes when
    # entries are added/removed, so an in-place rebuild that overwrites
    # roc.exe wouldn't bump the dir's mtime.
    $resolved = Resolve-LinkTarget $Dir
    $exe = Join-Path $resolved.FullName 'roc.exe'
    if (Test-Path -LiteralPath $exe) {
        $mtime = (Get-Item -LiteralPath $exe).LastWriteTime
    } else {
        $mtime = $resolved.LastWriteTime
    }
    $mtime.ToString('yyyy-MM-dd')
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string] $Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    }
    finally { $sha.Dispose() }
}

function Find-NightlyDir {
    param([Parameter(Mandatory)][string] $Hash)
    if (-not (Test-Path -LiteralPath $script:RocupHome -PathType Container)) { return '' }
    # Prefer new-format: roc_nightly-YYYY-MM-DD-<hash>
    $found = Get-ChildItem -LiteralPath $script:RocupHome -Directory -Filter "roc_nightly-*-$Hash" -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($found) { return $found.Name }
    # Legacy: roc_nightly-<hash>
    $legacy = Join-Path $script:RocupHome "roc_nightly-$Hash"
    if (Test-Path -LiteralPath $legacy) { return "roc_nightly-$Hash" }
    return ''
}

function Get-LocalInstallPath {
    param([Parameter(Mandatory)][string] $EntryPath)
    $item = Get-Item -LiteralPath $EntryPath -Force -ErrorAction SilentlyContinue
    if (-not $item) { return '' }
    if ($item.LinkType -eq 'Junction' -or $item.LinkType -eq 'SymbolicLink') {
        return $item.Target | Select-Object -First 1
    }
    # File-mode local entries (Unix-style) don't apply on Windows, but if some
    # unusual state exists where local-<hash> is a real dir, return its path.
    return $item.FullName
}

# --- Junction management --------------------------------------------------

function Test-IsJunction {
    param([Parameter(Mandatory)][string] $Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    return $item.LinkType -eq 'Junction'
}

function New-RocupJunction {
    param(
        [Parameter(Mandatory)][string] $LinkPath,
        [Parameter(Mandatory)][string] $TargetDir
    )
    # Cross-volume detection - junctions only work on the same NTFS volume.
    $linkRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($LinkPath))
    $targetRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($TargetDir))
    if ($linkRoot -ne $targetRoot) {
        throw "error: cannot create junction from $LinkPath ($linkRoot) to $TargetDir ($targetRoot): cross-volume junctions are not supported. Set `$env:ROCUP_HOME to a directory on $targetRoot and retry, or move the build to $linkRoot."
    }
    New-Item -ItemType Junction -Path $LinkPath -Value $TargetDir -Force | Out-Null
}

function Remove-Junction {
    param([Parameter(Mandatory)][string] $Path)
    # Remove a junction without prompting and without touching its target.
    # PowerShell 5.1's Remove-Item prompts for confirmation on a junction whose
    # target has children, even with -Force. If the user (or harness) confirms,
    # -Recurse would follow the junction and delete the user's actual build
    # directory contents. The .NET API deletes the reparse-point entry only.
    [System.IO.Directory]::Delete($Path, $false)
}

function Set-ActiveVersion {
    param([Parameter(Mandatory)][string] $DirName)
    $targetDir = Join-Path $script:RocupHome $DirName

    if ((Test-Path -LiteralPath $targetDir) -and -not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        throw "error: $targetDir exists but is not a directory; cannot activate"
    }
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        # Could also be a dangling junction whose target was deleted.
        $item = Get-Item -LiteralPath $targetDir -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'Junction') {
            throw "error: $targetDir is a dangling junction (the local source directory has been moved or deleted)"
        }
        throw "error: $targetDir does not exist; cannot activate"
    }

    $rocLink = Join-Path $script:RocupHome 'roc'

    # Safety: if $rocLink exists and ISN'T a junction, refuse to delete it.
    if (Test-Path -LiteralPath $rocLink) {
        if (-not (Test-IsJunction $rocLink)) {
            throw "error: $rocLink exists but is not a junction - refusing to delete. Remove it manually if you want rocup to manage it."
        }
        Remove-Junction $rocLink
    }

    New-RocupJunction -LinkPath $rocLink -TargetDir $targetDir
    Write-Host ".. active version: $DirName"
    $rocExe = Join-Path $targetDir 'roc.exe'
    if (Test-Path -LiteralPath $rocExe -PathType Leaf) {
        Write-Host ".. roc binary: $rocExe"
    }
}

function Remove-DanglingJunction {
    param([Parameter(Mandatory)][string] $Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return }
    if ($item.LinkType -ne 'Junction') { return }
    # Junction with a missing target is "dangling" - Test-Path on the link returns true,
    # but Test-Path on the target returns false.
    $target = $item.Target | Select-Object -First 1
    if ($target -and -not (Test-Path -LiteralPath $target)) {
        Remove-Junction $Path
        Write-Host ".. cleaned up dangling $Path"
    }
}

function Remove-DanglingJunctions {
    Remove-DanglingJunction (Join-Path $script:RocupHome 'roc')
}

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

function Initialize-RocupShims {
    # Ensure $RocupHome\bin and $RocupHome\roc are on User PATH. Idempotent.
    # Bin shims themselves are installed by install.ps1, not from here.
    $binDir = Join-Path $script:RocupHome 'bin'
    $rocDir = Join-Path $script:RocupHome 'roc'
    $null = Add-UserPathEntry $binDir
    $null = Add-UserPathEntry $rocDir
}

# --- GitHub API ----------------------------------------------------------

# Invoke-GhSafely
# Runs gh with the given argv, isolating the caller from gh's failure modes:
#   - $ErrorActionPreference = 'Stop' (set at top of script) + PS 7.4's
#     $PSNativeCommandUseErrorActionPreference would otherwise turn gh's
#     non-zero exit (e.g. exit 4 when unauthenticated) into a terminating
#     error before our $LASTEXITCODE check fires. We lower the preference
#     locally and wrap in try/catch.
#   - gh's auth-required message goes to stderr; capture it via 2>&1 and
#     filter ErrorRecords out of the result so it can't leak to the user
#     when we fall back. 2>$null alone is unreliable on PS 5.1.
# Returns @{ Output = <stdout string array>; ExitCode = <int> }.
function Invoke-GhSafely {
    param([Parameter(Mandatory)][string[]] $GhArgs)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @()
    $exit   = 1
    try {
        $merged = & gh @GhArgs 2>&1
        $exit = $LASTEXITCODE
        # Keep plain strings (stdout); drop ErrorRecords (stderr lines).
        $output = @($merged | Where-Object { $_ -is [string] })
    }
    catch {
        $exit   = 1
        $output = @()
    }
    finally {
        $ErrorActionPreference = $prevEAP
        $global:LASTEXITCODE   = 0
    }
    [PSCustomObject]@{ Output = $output; ExitCode = $exit }
}

function Get-RecentTags {
    param(
        [Parameter(Mandatory)][string] $Repo,
        [Parameter(Mandatory)][int] $Count
    )
    # Test hook: force the empty-tags response so callers exercise the
    # offline / installed-only fallback path. Used by 11-step-offline.ps1.
    if ($env:ROCUP_TEST_OFFLINE -eq '1') { return @() }

    # Prefer gh — it authenticates via GH_TOKEN/keyring, avoiding the 60-req/hr
    # unauthenticated REST rate limit that bites CI runs from shared IPs.
    # Falls through to Invoke-RestMethod when gh is absent, unauthenticated, or
    # returns no rows. Mirrors fetch_recent_tags() in the bash port.
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $r = Invoke-GhSafely @('release', 'list', '--repo', $Repo,
            '--limit', "$Count", '--json', 'tagName', '--jq', '.[].tagName')
        if ($r.ExitCode -eq 0 -and $r.Output.Count -gt 0) { return $r.Output }
    }

    # GitHub REST silently caps per_page at 100; paginate when count > 100.
    $pagesNeeded = [Math]::Max(1, [Math]::Ceiling($Count / 100.0))
    $tags = @()
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        for ($page = 1; $page -le $pagesNeeded; $page++) {
            $url = "https://api.github.com/repos/$Repo/releases?per_page=100&page=$page"
            try {
                $releases = @(Invoke-RestMethod -Uri $url -UseBasicParsing -Headers @{ 'User-Agent' = 'rocup' })
            }
            catch {
                throw "error: failed to fetch releases for $Repo (gh unavailable or unauthenticated, and REST request failed on page ${page}): $($_.Exception.Message)"
            }
            foreach ($r in $releases) {
                if ($r.tag_name) { $tags += $r.tag_name }
            }
            if ($releases.Count -lt 100) { break }
        }
    }
    finally { $ProgressPreference = $oldProgress }
    $tags
}

function Resolve-LatestHash {
    $tags = @(Get-RecentTags -Repo 'roc-lang/nightlies' -Count 1)
    if (-not $tags -or $tags.Count -eq 0) {
        throw "error: could not find any nightly releases in roc-lang/nightlies"
    }
    $tag = $tags[0]
    $hash = $tag.Split('-')[-1]
    if ($hash -notmatch '^[0-9a-f]{7}$') {
        throw "error: latest release tag '$tag' did not end in a 7-char hash"
    }
    $hash
}

function Get-NightlyAsset {
    param(
        [Parameter(Mandatory)][string] $Tag,
        [Parameter(Mandatory)][string] $Platform,
        [Parameter(Mandatory)][string] $Hash,
        [Parameter(Mandatory)][string] $DestDir
    )
    $dateYmd = ConvertFrom-NightlyTag $Tag
    $tHash = $Tag.Split('-')[-1]
    $asset = "roc_nightly-$Platform-$dateYmd-$tHash.zip"
    $out = Join-Path $DestDir $asset

    # Prefer gh release download — keeps the auth boundary consistent with
    # Get-RecentTags and benefits from gh's transient-retry handling. The
    # CDN-backed direct download is unauthenticated for public releases, so
    # the fallback still works without credentials. Mirrors
    # download_nightly_asset() in the bash port.
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $pattern = "roc_nightly-$Platform-*-$Hash.zip"
        $r = Invoke-GhSafely @('release', 'download', $Tag,
            '--repo', 'roc-lang/nightlies',
            '--pattern', $pattern, '--dir', $DestDir)
        if ($r.ExitCode -eq 0 -and (Test-Path -LiteralPath $out)) { return $out }
    }

    $url = "https://github.com/roc-lang/nightlies/releases/download/$Tag/$asset"
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    }
    catch { throw "error: download failed: $url" }
    finally { $ProgressPreference = $oldProgress }
    if (-not (Test-Path -LiteralPath $out)) { throw "error: download did not produce $out" }
    $out
}

# --- Install ---------------------------------------------------------------

function Expand-RocArchive {
    # Extract $ZipPath into $TargetDir, emulating tar's --strip-components=1.
    # The Roc archive always has a single top-level directory; we want its
    # contents directly inside $TargetDir.
    param(
        [Parameter(Mandatory)][string] $ZipPath,
        [Parameter(Mandatory)][string] $TargetDir
    )
    $tmpExtract = Join-Path ([IO.Path]::GetTempPath()) ("rocup-extract-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpExtract -Force | Out-Null
    try {
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Expand-Archive -LiteralPath $ZipPath -DestinationPath $tmpExtract -Force
        }
        finally { $ProgressPreference = $oldProgress }

        $entries = @(Get-ChildItem -LiteralPath $tmpExtract -Force)
        if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {
            # Single top-level directory - flatten by moving its contents.
            New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
            Get-ChildItem -LiteralPath $entries[0].FullName -Force | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $TargetDir -Force
            }
        } else {
            # Multiple top-level entries - move them all directly.
            New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
            $entries | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination $TargetDir -Force
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmpExtract) {
            Remove-Item -LiteralPath $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-Nightly {
    param(
        [Parameter(Mandatory)][string] $Hash,
        [Parameter(Mandatory)][string] $Platform
    )
    New-Item -ItemType Directory -Path $script:RocupHome -Force | Out-Null

    # Short-circuit if already installed.
    $existing = Find-NightlyDir $Hash
    if ($existing) {
        $existingExe = Join-Path (Join-Path $script:RocupHome $existing) 'roc.exe'
        if (Test-Path -LiteralPath $existingExe) {
            Write-Host ".. nightly $Hash already extracted at $script:RocupHome\$existing; skipping download"
            Set-ActiveVersion $existing
            return
        }
    }

    Write-Host ".. looking up nightly release with hash $Hash"
    $tags = Get-RecentTags -Repo 'roc-lang/nightlies' -Count 200
    $tag = $tags | Where-Object { $_.EndsWith("-$Hash") } | Select-Object -First 1
    if (-not $tag) {
        throw "error: no nightly release with hash '$Hash' found in roc-lang/nightlies"
    }
    Write-Host ".. found release: $tag"

    $dateYmd = ConvertFrom-NightlyTag $tag
    $dirName = "roc_nightly-$dateYmd-$Hash"
    $targetDir = Join-Path $script:RocupHome $dirName

    $downloadDir = Join-Path ([IO.Path]::GetTempPath()) ("rocup-nightly-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
    try {
        Write-Host ".. downloading nightly asset for $Platform"
        $zip = Get-NightlyAsset -Tag $tag -Platform $Platform -Hash $Hash -DestDir $downloadDir

        Write-Host ".. extracting"
        try {
            Expand-RocArchive -ZipPath $zip -TargetDir $targetDir
        }
        catch {
            if (Test-Path -LiteralPath $targetDir) { Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue }
            throw "error: extract failed: $($_.Exception.Message)"
        }
    }
    finally {
        if (Test-Path -LiteralPath $downloadDir) {
            Remove-Item -LiteralPath $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Set-ActiveVersion $dirName
}

# --- Top-level command handlers ------------------------------------------

function Invoke-Latest {
    $platform = Get-Platform
    $hash = Resolve-LatestHash
    Write-Host ".. latest nightly hash: $hash"
    Install-Nightly -Hash $hash -Platform $platform
    Initialize-RocupShims
}

function Invoke-HashDispatch {
    param([Parameter(Mandatory)][string] $RawHash)
    $hash = $RawHash.Substring(0, 7)
    $localDir = Join-Path $script:RocupHome "local-$hash"
    if (Test-Path -LiteralPath $localDir) {
        Write-Host ".. activating local-$hash"
        Set-ActiveVersion "local-$hash"
    } else {
        $platform = Get-Platform
        Install-Nightly -Hash $hash -Platform $platform
    }
    Initialize-RocupShims
}

function Get-FallbackVersion {
    # Pick the most recent nightly; else most recent local; else most recent frozen.
    # Returns the directory name or ''.
    $dirs = @(Get-InstalledVersionDirs)
    if ($dirs.Count -eq 0) { return '' }

    $nightlies = @($dirs | Where-Object { $_.Name -like 'roc_nightly-*' })
    if ($nightlies.Count -gt 0) {
        $best = $nightlies | Sort-Object { Get-DirSortKey $_.FullName } -Descending | Select-Object -First 1
        return $best.Name
    }
    $locals = @($dirs | Where-Object { $_.Name -like 'local-*' })
    if ($locals.Count -gt 0) {
        $best = $locals | Sort-Object { Get-DirSortKey $_.FullName } -Descending | Select-Object -First 1
        return $best.Name
    }
    $frozens = @($dirs | Where-Object { $_.Name -like 'frozen-*' })
    if ($frozens.Count -gt 0) {
        $best = $frozens | Sort-Object { Get-DirSortKey $_.FullName } -Descending | Select-Object -First 1
        return $best.Name
    }
    return ''
}

function Remove-Version {
    param([Parameter(Mandatory)][string] $Ver)

    $dirName = $null
    switch -Regex ($Ver) {
        '^local-[0-9a-f]{7}$' { $dirName = $Ver; break }
        '^frozen-[a-zA-Z0-9._-]+$' { $dirName = $Ver; break }
        '^[0-9a-f]{7,8}$' {
            $hash = $Ver.Substring(0, 7)
            $localDir = Join-Path $script:RocupHome "local-$hash"
            if (Test-Path -LiteralPath $localDir) {
                $dirName = "local-$hash"
            } else {
                $found = Find-NightlyDir $hash
                if ($found) { $dirName = $found }
                else        { $dirName = "roc_nightly-$hash" }
            }
            break
        }
        '^[a-zA-Z0-9._-]+$' {
            $candidate = Join-Path $script:RocupHome "frozen-$Ver"
            if (Test-Path -LiteralPath $candidate) {
                $dirName = "frozen-$Ver"
            } else {
                throw "error: invalid version '$Ver' (expected 7- or 8-char hash, 'local-<hash>', 'frozen-<name>', or a frozen name)"
            }
            break
        }
        default {
            throw "error: invalid version '$Ver' (expected 7- or 8-char hash, 'local-<hash>', 'frozen-<name>', or a frozen name)"
        }
    }

    $targetDir = Join-Path $script:RocupHome $dirName
    if (-not (Test-Path -LiteralPath $targetDir)) {
        $item = Get-Item -LiteralPath $targetDir -Force -ErrorAction SilentlyContinue
        if (-not $item) {
            throw "error: $targetDir does not exist; nothing to remove"
        }
    }

    $rocLink = Join-Path $script:RocupHome 'roc'
    $wasActive = $false
    if (Test-IsJunction $rocLink) {
        $linkTarget = (Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1
        if ($linkTarget -and ((Split-Path -Leaf $linkTarget) -eq $dirName)) {
            $wasActive = $true
        }
    }

    Write-Host ".. removing $targetDir"
    if (Test-IsJunction $targetDir) {
        # local-<hash> entries are junctions; delete the entry only, never
        # follow into the user's source build dir.
        Remove-Junction $targetDir
    } else {
        Remove-Item -LiteralPath $targetDir -Recurse -Force
    }

    if (-not $wasActive) { return }

    $fallback = Get-FallbackVersion
    if ($fallback) {
        Set-ActiveVersion $fallback
    } else {
        if (Test-IsJunction $rocLink) { Remove-Junction $rocLink }
        Write-Host ".. no remaining versions; removed $rocLink junction"
        Remove-DanglingJunctions
    }
}

function Invoke-Prune {
    param([Parameter(Mandatory)][string] $KeepRaw)
    if ($KeepRaw -notmatch '^[0-9]+$') {
        throw "error: prune count must be a non-negative integer (got '$KeepRaw')"
    }
    $keep = [int] $KeepRaw

    if (-not (Test-Path -LiteralPath $script:RocupHome -PathType Container)) {
        Write-Host "no nightlies installed (no $script:RocupHome)"
        return
    }

    $rocLink = Join-Path $script:RocupHome 'roc'
    $active = ''
    if (Test-IsJunction $rocLink) {
        $target = (Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1
        if ($target) { $active = Split-Path -Leaf $target }
    }

    $nightlies = @(Get-InstalledVersionDirs | Where-Object { $_.Name -like 'roc_nightly-*' })
    if ($nightlies.Count -eq 0) {
        Write-Host "no nightlies to prune"
        return
    }

    $sorted = $nightlies | Sort-Object { Get-DirSortKey $_.FullName } -Descending

    $pos = 0
    $removed = 0
    foreach ($n in $sorted) {
        $pos += 1
        if ($pos -le $keep) {
            if ($n.Name -eq $active) { Write-Host "    keep $($n.Name) (active)" }
            else                     { Write-Host "    keep $($n.Name)" }
        } elseif ($n.Name -eq $active) {
            Write-Host "    keep $($n.Name) (active)"
        } else {
            Write-Host "  remove $($n.Name)"
            Remove-Item -LiteralPath $n.FullName -Recurse -Force
            $removed += 1
        }
    }
    Write-Host ".. pruned $removed nightlies"
}

function Step-Nightly {
    param([Parameter(Mandatory)][string] $Raw)
    if ($Raw -notmatch '^[+-][0-9]+$') {
        throw "error: invalid step '$Raw' (expected +N or -N where N > 0)"
    }
    $sign = $Raw.Substring(0, 1)
    $n = [int] $Raw.Substring(1)
    if ($n -eq 0) {
        throw "error: invalid step '$Raw' (N must be a positive integer)"
    }

    $rocLink = Join-Path $script:RocupHome 'roc'
    if (-not (Test-IsJunction $rocLink)) {
        throw "error: no active version; use 'rocup latest' first."
    }
    $activeTarget = (Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1
    $active = Split-Path -Leaf $activeTarget

    if ($active -notlike 'roc_nightly-*') {
        if ($active -like 'local-*') {
            throw "error: +N/-N requires an active nightly; $active is active. Use 'rocup latest' or a specific hash to switch."
        }
        throw "error: +N/-N requires an active nightly; $active is active."
    }

    $activeHash = $active.Split('-')[-1]
    if ($activeHash -notmatch '^[0-9a-f]{7}$') {
        throw "error: could not parse active nightly hash from '$active'"
    }

    Write-Host ".. stepping $Raw from $activeHash"

    try {
        $tags = @(Get-RecentTags -Repo 'roc-lang/nightlies' -Count 200)
        if ($tags.Count -gt 0) {
            Step-NightlyViaTags -Sign $sign -N $n -ActiveHash $activeHash -Tags $tags
            return
        }
    } catch {
        Write-Host ".. network unavailable; using installed nightlies only"
    }

    Step-NightlyViaInstalled -Sign $sign -N $n -Active $active
}

function Step-NightlyViaTags {
    param(
        [Parameter(Mandatory)][string] $Sign,
        [Parameter(Mandatory)][int] $N,
        [Parameter(Mandatory)][string] $ActiveHash,
        [Parameter(Mandatory)][string[]] $Tags
    )
    $i = -1
    for ($idx = 0; $idx -lt $Tags.Count; $idx++) {
        if ($Tags[$idx].EndsWith("-$ActiveHash")) { $i = $idx; break }
    }
    if ($i -lt 0) {
        throw "error: active nightly $ActiveHash is older than the most recent 200 releases; relative navigation is not supported from here. Use 'rocup latest' or a specific hash."
    }

    if ($Sign -eq '+') {
        $targetIdx = $i - $N
        if ($targetIdx -lt 0) { throw "error: only $i nightlies newer than active; cannot step +$N." }
    } else {
        $targetIdx = $i + $N
        if ($targetIdx -ge $Tags.Count) {
            $available = $Tags.Count - $i - 1
            throw "error: only $available nightlies older than active in the most recent 200; cannot step -$N."
        }
    }

    $targetTag = $Tags[$targetIdx]
    Write-Host ".. target: $targetTag"
    $targetHash = $targetTag.Split('-')[-1]
    $platform = Get-Platform
    Install-Nightly -Hash $targetHash -Platform $platform
}

function Step-NightlyViaInstalled {
    param(
        [Parameter(Mandatory)][string] $Sign,
        [Parameter(Mandatory)][int] $N,
        [Parameter(Mandatory)][string] $Active
    )
    if (-not (Test-Path -LiteralPath $script:RocupHome -PathType Container)) {
        throw "error: no installed nightlies (offline; only installed nightlies considered)"
    }
    $nightlies = @(Get-InstalledVersionDirs | Where-Object { $_.Name -like 'roc_nightly-*' })
    if ($nightlies.Count -eq 0) {
        throw "error: no installed nightlies (offline; only installed nightlies considered)"
    }
    $sorted = $nightlies | Sort-Object { Get-DirSortKey $_.FullName } -Descending
    $names = @($sorted | ForEach-Object { $_.Name })

    $i = -1
    for ($idx = 0; $idx -lt $names.Count; $idx++) {
        if ($names[$idx] -eq $Active) { $i = $idx; break }
    }
    if ($i -lt 0) {
        throw "error: active nightly $Active not found among installed dirs"
    }

    if ($Sign -eq '+') {
        $targetIdx = $i - $N
        if ($targetIdx -lt 0) { throw "error: only $i installed nightlies newer than active; cannot step +$N (offline; only installed nightlies considered)." }
    } else {
        $targetIdx = $i + $N
        if ($targetIdx -ge $names.Count) {
            $available = $names.Count - $i - 1
            throw "error: only $available installed nightlies older than active; cannot step -$N (offline; only installed nightlies considered)."
        }
    }

    $target = $names[$targetIdx]
    Write-Host ".. target: $target"
    Set-ActiveVersion $target
}

function Invoke-Local {
    # Activate a registered local roc build. Single registration: pick it.
    # Multiple: pick the one whose roc.exe has the newest mtime. None: error.
    if (-not (Test-Path -LiteralPath $script:RocupHome -PathType Container)) {
        throw "error: no local versions registered. Use 'rocup <path>' to register one."
    }
    $locals = @(Get-InstalledVersionDirs | Where-Object { $_.Name -like 'local-*' })
    if ($locals.Count -eq 0) {
        throw "error: no local versions registered. Use 'rocup <path>' to register one."
    }
    # Prefer roc.exe's mtime over the dir's: an in-place rebuild that overwrites
    # roc.exe won't bump the directory mtime, and matches the bash port.
    $best = $locals | Sort-Object {
        $resolved = Resolve-LinkTarget $_.FullName
        $exe = Join-Path $resolved.FullName 'roc.exe'
        if (Test-Path -LiteralPath $exe) {
            (Get-Item -LiteralPath $exe).LastWriteTime
        } else {
            $resolved.LastWriteTime
        }
    } -Descending | Select-Object -First 1
    Set-ActiveVersion $best.Name
}

function Test-FreezeName {
    # Returns the name on success; throws on failure. Rules per design spec:
    #   - non-empty, matches ^[a-zA-Z0-9._-]+$
    #   - does not start with 'frozen-'
    #   - does not collide with any installed nightly or registered local hash
    param([Parameter(Mandatory=$false)][string] $Name)
    if (-not $Name) {
        throw "freeze: name is required"
    }
    if ($Name -notmatch '^[a-zA-Z0-9._-]+$') {
        throw "freeze: invalid name '$Name'; allowed characters: a-z A-Z 0-9 . _ -"
    }
    if ($Name -like 'frozen-*') {
        throw "freeze: do not include the 'frozen-' prefix in the name"
    }
    if ($Name -match '^[0-9a-f]{7}$') {
        $localPath = Join-Path $script:RocupHome "local-$Name"
        if (Test-Path -LiteralPath $localPath) {
            throw "freeze: name '$Name' conflicts with an existing version hash; choose another name"
        }
        $nightly = Find-NightlyDir $Name
        if ($nightly) {
            throw "freeze: name '$Name' conflicts with an existing version hash; choose another name"
        }
    }
    $Name
}

function Invoke-Freeze {
    param(
        [Parameter(Mandatory)][string[]] $argv
    )
    # argv = the args AFTER 'freeze' (i.e., $name and any flags).
    $force = $false
    $name  = ''
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $a = $argv[$i]
        if ($a -eq '--force') {
            $force = $true
        } elseif ($a.StartsWith('-')) {
            throw "freeze: unknown option '$a'"
        } elseif (-not $name) {
            $name = $a
        } else {
            throw "freeze: too many arguments (already have name '$name', also got '$a')"
        }
    }

    $null = Test-FreezeName $name

    $rocLink = Join-Path $script:RocupHome 'roc'
    if (-not (Test-IsJunction $rocLink)) {
        throw "freeze: no active version"
    }
    $linkTarget = (Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1
    $active = Split-Path -Leaf $linkTarget

    if ($active -notlike 'local-*') {
        throw "freeze: active version is $active; freeze requires an active local build"
    }

    $entry = Join-Path $script:RocupHome $active
    $resolved = Get-LocalInstallPath $entry
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "freeze: cannot resolve active local $active; the source directory may have been moved or deleted"
    }
    $srcExe = Join-Path $resolved 'roc.exe'
    if (-not (Test-Path -LiteralPath $srcExe -PathType Leaf)) {
        throw "freeze: roc binary not found in $resolved"
    }

    $dest = Join-Path $script:RocupHome "frozen-$name"
    if (Test-Path -LiteralPath $dest) {
        if (-not $force) {
            throw "freeze: frozen-$name already exists. Use --force to overwrite."
        }
        Remove-Item -LiteralPath $dest -Recurse -Force
    }

    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -LiteralPath $srcExe -Destination (Join-Path $dest 'roc.exe') -Force

    Write-Host ".. frozen $active as frozen-$name ($resolved)"

    Set-ActiveVersion "frozen-$name"
}

function Register-Local {
    param([Parameter(Mandatory)][string] $InputPath)

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "error: $InputPath does not exist"
    }
    if (-not (Test-Path -LiteralPath $InputPath -PathType Container)) {
        throw "error: Windows port requires a directory; pass the directory containing roc.exe instead of a file path"
    }

    $absPath = (Resolve-Path -LiteralPath $InputPath).Path
    $rocExe = Join-Path $absPath 'roc.exe'
    if (-not (Test-Path -LiteralPath $rocExe -PathType Leaf)) {
        throw "error: no roc.exe found in $absPath"
    }

    New-Item -ItemType Directory -Path $script:RocupHome -Force | Out-Null

    $hash = (Get-Sha256Hex $absPath).Substring(0, 7)
    $dirName = "local-$hash"
    $entry = Join-Path $script:RocupHome $dirName

    if (Test-Path -LiteralPath $entry) {
        Write-Host ".. $dirName already registered ($absPath)"
    } else {
        New-RocupJunction -LinkPath $entry -TargetDir $absPath
        Write-Host ".. registered $dirName -> $absPath"
    }

    Set-ActiveVersion $dirName
}

# --- List -----------------------------------------------------------------

function Get-InstalledVersionDirs {
    # Returns DirectoryInfo objects for everything rocup tracks under $RocupHome.
    # Excludes 'roc' (the active-version junction) and 'bin' (shim dir).
    if (-not (Test-Path -LiteralPath $script:RocupHome -PathType Container)) { return @() }
    Get-ChildItem -LiteralPath $script:RocupHome -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PSIsContainer -or $_.LinkType -eq 'Junction'
        } |
        Where-Object {
            $_.Name -like 'roc_nightly-*' -or $_.Name -like 'local-*' -or $_.Name -like 'frozen-*'
        }
}

function Invoke-List {
    if (-not (Test-Path -LiteralPath $script:RocupHome -PathType Container)) {
        Write-Host "no versions installed (no $script:RocupHome)"
        return
    }

    $rocLink = Join-Path $script:RocupHome 'roc'
    $active = ''
    if (Test-IsJunction $rocLink) {
        $target = (Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1
        if ($target) { $active = Split-Path -Leaf $target }
    }

    $dirs = @(Get-InstalledVersionDirs)
    if ($dirs.Count -eq 0) {
        Write-Host "no versions installed in $script:RocupHome"
        return
    }

    $rows = $dirs | ForEach-Object {
        [PSCustomObject]@{
            SortKey = Get-DirSortKey $_.FullName
            Name    = $_.Name
            Path    = $_.FullName
        }
    } | Sort-Object SortKey

    foreach ($row in $rows) {
        $marker = if ($row.Name -eq $active) { ' -> ' } else { '    ' }
        switch -Regex ($row.Name) {
            '^roc-alpha4-rolling$' {
                Write-Host ("{0}{1,-7} (legacy)" -f $marker, 'alpha4')
                break
            }
            '^roc_nightly-([0-9]{4})-([0-9]{2})-([0-9]{2})-([0-9a-f]{7})$' {
                $mdy = '{0}/{1}/{2}' -f $Matches[2], $Matches[3], $Matches[1]
                Write-Host ("{0}{1,-7} ({2}) <{3}>" -f $marker, 'nightly', $mdy, $Matches[4])
                break
            }
            '^local-([0-9a-f]{7})$' {
                $hash = $Matches[1]
                $target = Get-LocalInstallPath $row.Path
                $resolved = Resolve-LinkTarget $row.Path
                $exe = Join-Path $resolved.FullName 'roc.exe'
                $mtime = if (Test-Path -LiteralPath $exe) {
                    (Get-Item -LiteralPath $exe).LastWriteTime
                } else {
                    $resolved.LastWriteTime
                }
                $mdy = $mtime.ToString('MM/dd/yyyy')
                Write-Host ("{0}{1,-7} ({2}) <{3}>  {4}" -f $marker, 'local', $mdy, $hash, $target)
                break
            }
            '^frozen-(.+)$' {
                $fname = $Matches[1]
                $resolved = Get-Item -LiteralPath $row.Path -Force
                $exe = Join-Path $resolved.FullName 'roc.exe'
                $mtime = if (Test-Path -LiteralPath $exe) {
                    (Get-Item -LiteralPath $exe).LastWriteTime
                } else {
                    $resolved.LastWriteTime
                }
                $mdy = $mtime.ToString('MM/dd/yyyy')
                Write-Host ("{0}{1,-7} ({2}) <{3}>" -f $marker, 'frozen', $mdy, $fname)
                break
            }
            default {
                Write-Host ("{0}{1}" -f $marker, $row.Name)
            }
        }
    }
}

# --- Usage ----------------------------------------------------------------

# Get-TerminalWidth
# Returns the column count to wrap --help output to. $env:COLUMNS always wins
# (lets users and tests override). Otherwise read from $Host.UI.RawUI.WindowSize
# — the PowerShell equivalent of the bash version's '/dev/tty' trick, which
# returns the real console size regardless of whether the caller is capturing
# stdout (Out-String, redirection, etc.). Falls back to 78 (the prior fixed
# layout) when no console is attached. Floored at 50 so the 18-col label
# gutter still leaves room for descriptions; no upper bound — wide terminals
# get a single-line layout.
function Get-TerminalWidth {
    $cols = 0
    if ($env:COLUMNS -and ($env:COLUMNS -match '^\d+$')) {
        $cols = [int] $env:COLUMNS
    } else {
        try { $cols = [int] $Host.UI.RawUI.WindowSize.Width } catch { $cols = 0 }
    }
    if ($cols -le 0)  { $cols = 78 }
    if ($cols -lt 50) { $cols = 50 }
    $cols
}

# Format-Wrapped
# Word-wraps $Text to $Width columns. First line gets $FirstPrefix; subsequent
# lines get $ContPrefix. Splits only on whitespace (never inside a word) so
# multi-word phrases survive intact — required-phrase substring matching in
# drift-check.sh depends on this. Returns a single string with embedded LFs.
function Format-Wrapped {
    param(
        [int]    $Width,
        [string] $FirstPrefix,
        [string] $ContPrefix,
        [string] $Text
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $line = ''
    $prefix = $FirstPrefix
    foreach ($word in ($Text -split '\s+' | Where-Object { $_ -ne '' })) {
        if (-not $line) {
            $line = "$prefix$word"
            $prefix = $ContPrefix
        } elseif (($line.Length + 1 + $word.Length) -le $Width) {
            $line = "$line $word"
        } else {
            $lines.Add($line)
            $line = "$ContPrefix$word"
        }
    }
    if ($line) { $lines.Add($line) }
    $lines -join "`n"
}

function Show-Usage {
    $width = Get-TerminalWidth

    # Each command is rendered as: 2-space indent, label padded to 16 cols,
    # then a description that word-wraps to $width with an 18-space hanging
    # indent. The 16-col label column accommodates the widest label
    # ('remove <ver>' = 12 chars) with breathing room.
    $cont = ' ' * 18
    $cmds = @(
        @{ Label = 'latest';       Desc = "install/activate the most recent nightly from roc-lang/nightlies (default if no arg)" }
        @{ Label = '<hash>';       Desc = "7- or 8-char hex (8-char matches 'roc --version' output, which is then truncated to 7 to look up GitHub releases). If a local install with that hash is registered, activate it. Else if the nightly is already downloaded, activate it. Else fetch the nightly from roc-lang/nightlies and install." }
        @{ Label = '<path>';       Desc = "register a local roc as 'local-<hash>' inside `$env:ROCUP_HOME (via junction, not copy). Path must be a directory containing roc.exe. File paths are not supported on Windows." }
        @{ Label = 'local';        Desc = "activate a registered local roc build. With one local registered, activate it; with several, activate the most recently built one (newest roc.exe mtime). Errors if no locals are registered." }
        @{ Label = '+N | -N';      Desc = "step N nightlies newer (+) or older (-) than the active one. Requires the active version to be a nightly." }
        @{ Label = 'list';         Desc = "show installed versions and mark the active one." }
        @{ Label = 'freeze <name>'; Desc = "snapshot the active local build into `$env:ROCUP_HOME\frozen-<name>\ as real files (not junctions). Requires an active local. <name> matches [a-zA-Z0-9._-] and must not collide with an existing hash. Pass --force to overwrite an existing frozen entry. The original local-<hash> registration is left intact; active becomes frozen-<name>." }
        @{ Label = 'remove <ver>'; Desc = "delete a version (7- or 8-char hash, or local-<hash>)." }
        @{ Label = 'prune <N>';    Desc = "keep the N most recent nightlies; delete older ones." }
    )

    $out = [System.Collections.Generic.List[string]]::new()

    # Synopsis line. 14-space hanging indent so continuation lines align
    # under '[latest'.
    $out.Add( (Format-Wrapped -Width $width -FirstPrefix '' -ContPrefix (' ' * 14) `
        -Text 'usage: rocup [latest | <hash> | <path> | local | +N | -N | list | freeze <name> | remove <ver> | prune <N>]') )
    $out.Add('')

    foreach ($c in $cmds) {
        $first = '  ' + $c.Label.PadRight(16)
        $out.Add( (Format-Wrapped -Width $width -FirstPrefix $first -ContPrefix $cont -Text $c.Desc) )
        $out.Add('')
    }

    # Drop the trailing blank line so output ends with the last command, just
    # like the bash version (and the prior here-string layout).
    if ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') {
        $out.RemoveAt($out.Count - 1)
    }
    $out -join "`n"
}

# --- Dispatch -------------------------------------------------------------

function Invoke-Rocup {
    param([string[]] $argv)

    $cmd = if ($argv.Count -eq 0) { 'latest' } else { $argv[0] }

    switch -Regex ($cmd) {
        '^(-h|--help|help)$' { Show-Usage; return }
        '^list$'             { Invoke-List; return }
        '^local$'            { Invoke-Local; Initialize-RocupShims; return }
        '^remove$' {
            if ($argv.Count -lt 2) {
                throw "error: 'remove' requires an argument (7- or 8-char hash, or local-<hash>)"
            }
            Remove-Version $argv[1]
            return
        }
        '^prune$' {
            if ($argv.Count -lt 2) {
                throw "error: 'prune' requires a count (e.g. 'rocup prune 3')"
            }
            Invoke-Prune $argv[1]
            return
        }
        '^latest$'           { Invoke-Latest; return }
        '^freeze$' {
            if ($argv.Count -lt 2) {
                throw "error: 'freeze' requires a name (e.g. 'rocup freeze myfeature')"
            }
            Invoke-Freeze -argv $argv[1..($argv.Count - 1)]
            Initialize-RocupShims
            return
        }
        '^[+-][0-9]+$'       { Step-Nightly $cmd; Initialize-RocupShims; return }
        '^[0-9a-f]{7,8}$'    { Invoke-HashDispatch $cmd; return }
        '^frozen-[a-zA-Z0-9._-]+$' {
            $candidate = Join-Path $script:RocupHome $cmd
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                Set-ActiveVersion $cmd
                Initialize-RocupShims
                return
            }
            [Console]::Error.WriteLine("error: frozen entry '$cmd' does not exist in $script:RocupHome")
            exit 1
        }
        '^[a-zA-Z0-9._-]+$' {
            $candidate = Join-Path $script:RocupHome "frozen-$cmd"
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                Set-ActiveVersion "frozen-$cmd"
                Initialize-RocupShims
                return
            }
            if (Test-Path -LiteralPath $cmd) {
                Register-Local $cmd
                Initialize-RocupShims
                return
            }
            [Console]::Error.WriteLine("error: invalid argument '$cmd'")
            [Console]::Error.WriteLine((Show-Usage))
            exit 1
        }
        default {
            if (Test-Path -LiteralPath $cmd) {
                Register-Local $cmd
                Initialize-RocupShims
                return
            }
            [Console]::Error.WriteLine("error: invalid argument '$cmd'")
            [Console]::Error.WriteLine((Show-Usage))
            exit 1
        }
    }
}

# --- Entry point ----------------------------------------------------------

# Only run dispatch when invoked as a script, not when dot-sourced for testing.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-Rocup -argv $Args
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}
