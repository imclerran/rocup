. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'fake v1' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register-local succeeded'

$rocLink = Join-Path $env:ROCUP_HOME 'roc'
$active  = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
$originalLocal = $active

$r = Invoke-Rocup freeze myfeature
Assert-Eq 0 $r.ExitCode 'freeze succeeded'

$active = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
Assert-Eq 'frozen-myfeature' $active 'active is frozen entry after freeze'

# Real directory, not a junction.
$frozen = Join-Path $env:ROCUP_HOME 'frozen-myfeature'
$item = Get-Item -LiteralPath $frozen -Force
if ($item.LinkType) {
    [Console]::Error.WriteLine("FAIL: frozen-myfeature is a $($item.LinkType)")
    exit 1
}
if (-not $item.PSIsContainer) {
    [Console]::Error.WriteLine("FAIL: frozen-myfeature is not a container")
    exit 1
}

# roc.exe is a real file (not a symlink/junction).
$rocExe = Join-Path $frozen 'roc.exe'
$rocItem = Get-Item -LiteralPath $rocExe -Force
if ($rocItem.LinkType) {
    [Console]::Error.WriteLine("FAIL: roc.exe is a $($rocItem.LinkType)")
    exit 1
}

# Contents match (byte-for-byte).
$srcBytes = [IO.File]::ReadAllBytes((Join-Path $localDir 'roc.exe'))
$dstBytes = [IO.File]::ReadAllBytes($rocExe)
if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$srcBytes, [byte[]]$dstBytes)) {
    [Console]::Error.WriteLine("FAIL: copied roc.exe content differs")
    exit 1
}

# Original local registration still present (a junction).
$origJunction = Join-Path $env:ROCUP_HOME $originalLocal
if (-not (Test-Path -LiteralPath $origJunction)) {
    [Console]::Error.WriteLine("FAIL: original local registration was removed")
    exit 1
}

# Removing the source dir doesn't break the frozen copy.
Remove-Item -LiteralPath $localDir -Recurse -Force
if (-not (Test-Path -LiteralPath $rocExe)) {
    [Console]::Error.WriteLine("FAIL: frozen roc.exe missing after source removal")
    exit 1
}

Write-TestPass
