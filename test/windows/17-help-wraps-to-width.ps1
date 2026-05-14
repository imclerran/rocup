. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# Asserts no line in $Output exceeds $Width cols.
function Assert-MaxLineWidth {
    param([string] $Output, [int] $Width, [string] $Label)
    foreach ($line in ($Output -split "`r?`n")) {
        if ($line.Length -gt $Width) {
            [Console]::Error.WriteLine("FAIL: ${Label}: line exceeds $Width cols ($($line.Length) chars): $line")
            exit 1
        }
    }
}

# Run --help with COLUMNS=$cols and return the captured stdout. The child
# powershell process inherits env vars, so setting $env:COLUMNS here is
# picked up by Get-TerminalWidth inside rocup.ps1.
function Invoke-HelpAtWidth {
    param([int] $Cols)
    $prev = $env:COLUMNS
    $env:COLUMNS = "$Cols"
    try { return (Invoke-Rocup '--help').Output }
    finally { $env:COLUMNS = $prev }
}

# Narrow width: every line should fit in 60 cols.
$output = Invoke-HelpAtWidth 60
Assert-MaxLineWidth $output 60 'COLUMNS=60'

# Very wide width: output should be capped at the 120-col upper bound.
$output = Invoke-HelpAtWidth 200
Assert-MaxLineWidth $output 120 'COLUMNS=200 (cap)'

# Below-floor width: output should still cap at the 50-col floor.
$output = Invoke-HelpAtWidth 20
Assert-MaxLineWidth $output 50 'COLUMNS=20 (floor)'

# Commands still mentioned at narrow widths.
$output = Invoke-HelpAtWidth 60
foreach ($cmd in @('latest', 'list', 'local', 'remove', 'prune')) {
    Assert-Contains $output $cmd "help mentions $cmd at width 60"
}

# Required phrases survive narrow-width wrapping. Match against the flattened
# (whitespace-collapsed) output, the same way the bash drift-check does, so
# word-wrap alone is fine but any word-splitting or reordering would fail.
$flat = (Invoke-HelpAtWidth 60) -replace "`r", '' -replace "\s+", ' '
foreach ($phrase in @(
    '<hash> | <path> | local | +N | -N | list',
    'install/activate the most recent nightly',
    'roc-lang/nightlies',
    'default if no arg',
    '7- or 8-char hex',
    "roc --version",
    'truncated to 7',
    'If a local install with that hash is registered, activate it',
    'register a local roc',
    'activate a registered local roc build',
    'most recently built one',
    'Errors if no',
    'step N nightlies newer',
    'Requires the active version to be a nightly',
    'show installed versions',
    'mark the active',
    'delete a version',
    'keep the N most recent nightlies',
    'delete older'
)) {
    Assert-Contains $flat $phrase "required phrase preserved at width 60: '$phrase'"
}

Write-TestPass
