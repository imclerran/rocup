. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'fake' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register succeeded'

# Make two frozen entries and remove the underlying local so only frozens remain.
$r = Invoke-Rocup freeze keep-me
Assert-Eq 0 $r.ExitCode 'freeze keep-me succeeded'
$localName = (Get-ChildItem -LiteralPath $env:ROCUP_HOME -Filter 'local-*' -Force | Select-Object -First 1).Name
$localHash = $localName.Substring('local-'.Length)
$r = Invoke-Rocup $localHash
Assert-Eq 0 $r.ExitCode 'switch back to local'
$r = Invoke-Rocup freeze drop-me
Assert-Eq 0 $r.ExitCode 'freeze drop-me succeeded'
$r = Invoke-Rocup remove $localName
Assert-Eq 0 $r.ExitCode 'remove local succeeded'

# Active is frozen-drop-me; remove it — fallback should pick frozen-keep-me.
$r = Invoke-Rocup remove 'frozen-drop-me'
Assert-Eq 0 $r.ExitCode 'remove active frozen succeeded'
$active = Split-Path -Leaf ((Get-Item -LiteralPath (Join-Path $env:ROCUP_HOME 'roc') -Force).Target | Select-Object -First 1)
Assert-Eq 'frozen-keep-me' $active 'fallback to remaining frozen entry'

Write-TestPass
