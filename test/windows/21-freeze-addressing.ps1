. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$localDir = Join-Path $script:TestTmpDir 'my-local-roc'
New-Item -ItemType Directory -Path $localDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $localDir 'roc.exe') -Value 'fake' -Encoding Ascii
$r = Invoke-Rocup $localDir
Assert-Eq 0 $r.ExitCode 'register succeeded'
$r = Invoke-Rocup freeze myfeature
Assert-Eq 0 $r.ExitCode 'freeze succeeded'

$r = Invoke-Rocup list
Assert-Eq 0 $r.ExitCode 'list succeeded'
Assert-Contains $r.Output 'frozen'    'list mentions frozen'
Assert-Contains $r.Output 'myfeature' 'list mentions the frozen name'
Assert-Contains $r.Output ' -> '      'list shows active marker'

Write-TestPass
