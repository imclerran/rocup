. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$r = Invoke-Rocup '--help'
Assert-Contains $r.Output 'usage:' 'help shows usage'
Assert-Contains $r.Output 'latest' 'help mentions latest'
Assert-Contains $r.Output 'list'   'help mentions list'

Write-TestPass
