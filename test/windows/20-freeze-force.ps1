. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'v1' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register succeeded'
$r = Invoke-Rocup freeze keepme
Assert-Eq 0 $r.ExitCode 'first freeze succeeded'

# Switch back to the local and bump v1 -> v2 before re-freezing. PS dispatcher
# resolves a bare hash to local-<hash> when registered, so pass the hash.
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'v2' -Encoding Ascii
$localName = (Get-ChildItem -LiteralPath $env:ROCUP_HOME -Filter 'local-*' -Force | Select-Object -First 1).Name
$localHash = $localName.Substring('local-'.Length)
$r = Invoke-Rocup $localHash
Assert-Eq 0 $r.ExitCode 'switch back to local succeeded'

# Refused without --force.
$r = Invoke-Rocup freeze keepme
if ($r.ExitCode -eq 0) { [Console]::Error.WriteLine('FAIL: refuse without --force'); exit 1 }
$existing = (Get-Content -LiteralPath (Join-Path $env:ROCUP_HOME 'frozen-keepme\roc.exe') -Raw).Trim()
Assert-Eq 'v1' $existing 'frozen entry untouched after refused freeze'

# Succeeds with --force.
$r = Invoke-Rocup freeze keepme --force
Assert-Eq 0 $r.ExitCode 'force-freeze succeeded'
$overwritten = (Get-Content -LiteralPath (Join-Path $env:ROCUP_HOME 'frozen-keepme\roc.exe') -Raw).Trim()
Assert-Eq 'v2' $overwritten 'frozen entry overwritten with --force'

$active = Split-Path -Leaf ((Get-Item -LiteralPath (Join-Path $env:ROCUP_HOME 'roc') -Force).Target | Select-Object -First 1)
Assert-Eq 'frozen-keepme' $active 'active switched to frozen-keepme after --force'

Write-TestPass
