. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

# ---- no locals registered ------------------------------------------------

$r = Invoke-Rocup local
if ($r.ExitCode -eq 0) {
    [Console]::Error.WriteLine("FAIL: 'rocup local' with no locals should error")
    exit 1
}
Assert-Contains $r.Output 'no local versions registered' 'errors when none registered'

# A nightly present, but still no locals — still errors.
New-FakeNightly -DateYmd '2025-10-25' -Hash '1111111' | Out-Null
$r = Invoke-Rocup local
if ($r.ExitCode -eq 0) {
    [Console]::Error.WriteLine("FAIL: 'rocup local' with only nightlies should error")
    exit 1
}
Assert-Contains $r.Output 'no local versions registered' 'errors when only nightlies present'

# ---- single local registered --------------------------------------------

$singleDir = Join-Path $script:TestTmpDir 'single-local'
New-Item -ItemType Directory -Path $singleDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $singleDir 'roc.exe') -Value '@echo off`necho single' -Encoding Ascii

$r = Invoke-Rocup $singleDir
Assert-Eq 0 $r.ExitCode 'register single local'

# Flip off it onto the nightly so 'rocup local' has work to do.
Set-FakeActive 'roc_nightly-2025-10-25-1111111'

$r = Invoke-Rocup local
Assert-Eq 0 $r.ExitCode "'rocup local' picks single registration"
$rocLink = Join-Path $env:ROCUP_HOME 'roc'
$active = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
if ($active -notlike 'local-*') {
    [Console]::Error.WriteLine("FAIL: expected local-* active, got $active")
    exit 1
}

# ---- multiple locals: newest mtime wins ---------------------------------

$olderDir = Join-Path $script:TestTmpDir 'older-local'
New-Item -ItemType Directory -Path $olderDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $olderDir 'roc.exe') -Value '@echo off`necho older' -Encoding Ascii
# Backdate this binary so $singleDir's is newer.
(Get-Item -LiteralPath (Join-Path $olderDir 'roc.exe')).LastWriteTime = [DateTime]'2020-01-01'

$r = Invoke-Rocup $olderDir
Assert-Eq 0 $r.ExitCode 'register older local'

Set-FakeActive 'roc_nightly-2025-10-25-1111111'
$r = Invoke-Rocup local
Assert-Eq 0 $r.ExitCode "'rocup local' picks newest"

$active = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
$resolved = (Get-Item -LiteralPath (Join-Path $env:ROCUP_HOME $active) -Force).Target | Select-Object -First 1
Assert-Eq $singleDir $resolved 'newest-mtime local wins'

# Bump the older one to a far-future timestamp; it should now win.
(Get-Item -LiteralPath (Join-Path $olderDir 'roc.exe')).LastWriteTime = [DateTime]'2030-01-01'

Set-FakeActive 'roc_nightly-2025-10-25-1111111'
$r = Invoke-Rocup local
Assert-Eq 0 $r.ExitCode "'rocup local' picks freshly-touched"

$active = Split-Path -Leaf ((Get-Item -LiteralPath $rocLink -Force).Target | Select-Object -First 1)
$resolved = (Get-Item -LiteralPath (Join-Path $env:ROCUP_HOME $active) -Force).Target | Select-Object -First 1
Assert-Eq $olderDir $resolved 'freshly-touched local wins after mtime bump'

Write-TestPass
