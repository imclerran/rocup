. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Remove the rocup-home dir so it's truly empty (Initialize-TestEnv creates it).
Remove-Item -LiteralPath $env:ROCUP_HOME -Recurse -Force

$r = Invoke-Rocup list
Assert-Contains $r.Output 'no versions installed' 'list reports empty'

Write-TestPass
