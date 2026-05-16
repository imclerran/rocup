. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

$r = Invoke-Rocup '--help'
Assert-Contains $r.Output 'usage:' 'help shows usage'
Assert-Contains $r.Output 'latest' 'help mentions latest'
Assert-Contains $r.Output 'list'   'help mentions list'
Assert-Contains $r.Output 'local'  'help mentions local'

$r = Invoke-Rocup '--help'
Assert-Contains $r.Output 'freeze <name>' "help lists 'freeze <name>'"
Assert-Contains $r.Output 'snapshot'      "help describes freeze as a snapshot"

Write-TestPass
