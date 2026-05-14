# Common helpers for rocup PowerShell tests. Dot-source from each test:
#   . "$PSScriptRoot\..\common\lib.ps1"
#   Initialize-TestEnv

$script:TestTmpDir = $null

function Initialize-TestEnv {
    $script:TestTmpDir = Join-Path ([IO.Path]::GetTempPath()) ("rocup-test-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TestTmpDir -Force | Out-Null
    $env:ROCUP_HOME = Join-Path $script:TestTmpDir 'rocup-home'
    New-Item -ItemType Directory -Path $env:ROCUP_HOME -Force | Out-Null
    # Path to the script under test. Override with $env:ROCUP_PS1.
    if (-not $env:ROCUP_PS1) {
        $env:ROCUP_PS1 = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'rocup.ps1'
    }
    # Auto-cleanup on script exit.
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
        if ($script:TestTmpDir -and (Test-Path -LiteralPath $script:TestTmpDir)) {
            Remove-Item -LiteralPath $script:TestTmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } | Out-Null
}

function Assert-Eq {
    param($Expected, $Actual, [string] $Message = 'assert_eq')
    if ($Expected -ne $Actual) {
        [Console]::Error.WriteLine("FAIL: $Message")
        [Console]::Error.WriteLine("  expected: $Expected")
        [Console]::Error.WriteLine("  actual:   $Actual")
        exit 1
    }
}

function Assert-Contains {
    param([string] $Haystack, [string] $Needle, [string] $Message = 'assert_contains')
    if (-not $Haystack.Contains($Needle)) {
        [Console]::Error.WriteLine("FAIL: $Message")
        [Console]::Error.WriteLine("  haystack: $Haystack")
        [Console]::Error.WriteLine("  needle:   $Needle")
        exit 1
    }
}

function Invoke-Rocup {
    # Invoke rocup.ps1 in a child PowerShell process, capturing output and exit code.
    # When rocup.ps1 writes to stderr, PowerShell's 2>&1 merge wraps each line as an
    # ErrorRecord. If the test host has $ErrorActionPreference='Stop' set (which
    # CI's `powershell.exe -command ". '{0}'"` invocation effectively does), the
    # merged records re-raise as terminating errors before we can return them.
    # Force Continue inside this helper so the captured output is just text.
    param([Parameter(ValueFromRemainingArguments=$true)][string[]] $Args)
    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoProfile -File $env:ROCUP_PS1 @Args 2>&1
    }
    finally { $ErrorActionPreference = $oldEAP }
    $captured = $LASTEXITCODE
    # Reset $LASTEXITCODE so the caller's environment doesn't see the child's
    # exit code. Tests that intentionally invoke failing commands (e.g. the
    # cross-volume rejection test) would otherwise poison the outer CI harness
    # check 'if ($LASTEXITCODE -ne 0) { throw "FAIL" }' even after the test
    # itself passed its assertions. The actual exit code is exposed via the
    # returned object's ExitCode property.
    $global:LASTEXITCODE = 0
    [PSCustomObject]@{
        Output   = ($output | Out-String)
        ExitCode = $captured
    }
}

function New-FakeNightly {
    param([Parameter(Mandatory)][string] $DateYmd, [Parameter(Mandatory)][string] $Hash)
    $dir = Join-Path $env:ROCUP_HOME "roc_nightly-$DateYmd-$Hash"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    # Create a dummy roc.exe so existence checks pass.
    Set-Content -LiteralPath (Join-Path $dir 'roc.exe') -Value '@echo off`necho fake' -Encoding Ascii
    $dir
}

function Set-FakeActive {
    param([Parameter(Mandatory)][string] $DirName)
    $rocLink = Join-Path $env:ROCUP_HOME 'roc'
    if (Test-Path -LiteralPath $rocLink) {
        # Use .NET API: Remove-Item on a junction with children prompts in PS 5.1
        # even with -Force; .Delete($path, $false) removes the reparse point only.
        [System.IO.Directory]::Delete($rocLink, $false)
    }
    New-Item -ItemType Junction -Path $rocLink -Value (Join-Path $env:ROCUP_HOME $DirName) | Out-Null
}

function Write-TestPass {
    Write-Host "PASS: $(Split-Path -Leaf $MyInvocation.ScriptName)"
}
