# Offline: Get-RecentTags sorts by tag date rather than trusting GitHub's
# created_at ordering, and honors the requested count after sorting.
. "$PSScriptRoot\..\common\lib.ps1"
Initialize-TestEnv

. $env:ROCUP_PS1

# Real ordering observed from the API in July 2026: June 28-30 listed ahead
# of July 1-7 because they share a created_at.
$apiOrder = @(
    'nightly-2026-June-30-09084da', 'nightly-2026-June-29-2e1efb1', 'nightly-2026-June-28-26ecddf',
    'nightly-2026-July-07-050c697', 'nightly-2026-July-06-17d1197', 'nightly-2026-July-01-7981032',
    'nightly-2026-June-27-127861d'
)

# Stub the network layer.
function Get-UnsortedTags { param($Repo, $Count) $apiOrder }

$expected = @(
    'nightly-2026-July-07-050c697', 'nightly-2026-July-06-17d1197', 'nightly-2026-July-01-7981032',
    'nightly-2026-June-30-09084da', 'nightly-2026-June-29-2e1efb1', 'nightly-2026-June-28-26ecddf',
    'nightly-2026-June-27-127861d'
)
Assert-Eq ($expected -join "`n") (@(Sort-NightlyTags $apiOrder) -join "`n") 'sorted newest first by tag date'
Assert-Eq 'nightly-2026-July-07-050c697' (@(Get-RecentTags -Repo 'roc-lang/nightlies' -Count 1) -join "`n") 'count 1 picks newest'
Assert-Eq "nightly-2026-July-07-050c697`nnightly-2026-July-06-17d1197" (@(Get-RecentTags -Repo 'roc-lang/nightlies' -Count 2) -join "`n") 'count 2 truncates after sorting'

$mixed = @('junk-tag', 'nightly-2026-08-07-8d23662', 'nightly-2026-July-23-306abd6',
           'nightly-2026-July-23-fdd77c3', 'nightly-2026-August-05-24f0b47')
$expectedMixed = @('nightly-2026-08-07-8d23662', 'nightly-2026-August-05-24f0b47',
                   'nightly-2026-July-23-fdd77c3', 'nightly-2026-July-23-306abd6', 'junk-tag')
Assert-Eq ($expectedMixed -join "`n") (@(Sort-NightlyTags $mixed) -join "`n") 'mixed month formats and ties'

# Regular and safe builds (same commit, '-safe' suffixed tag) have separate
# timelines, so a safe tag never becomes plain "latest" or shifts plain +N/-N
# offsets, and vice versa. Observed Nov 2026: nightly-2026-11-07-ad3a5d2-safe
# published alongside nightly-2026-11-07-ad3a5d2.
$withVariant = @('nightly-2026-11-07-ad3a5d2-safe', 'nightly-2026-11-07-ad3a5d2', 'nightly-2026-11-06-34f137a', 'junk-tag')
Assert-Eq "nightly-2026-11-07-ad3a5d2`nnightly-2026-11-06-34f137a" (@(Select-NightlyTags -Tags $withVariant) -join "`n") 'regular timeline drops safe and junk'
Assert-Eq 'nightly-2026-11-07-ad3a5d2-safe' (@(Select-NightlyTags -Tags $withVariant -Variant 'safe') -join "`n") 'safe timeline keeps only safe'
Assert-Eq '' (@(Select-NightlyTags -Tags @('nightly-2026-11-07-ad3a5d2-safe')) -join "`n") 'only-safe list is empty for regular'
Assert-Eq 'ad3a5d2' (Get-TagHash 'nightly-2026-11-07-ad3a5d2-safe') 'Get-TagHash strips the safe suffix'
Assert-Eq 'ad3a5d2' (Get-TagHash 'nightly-2026-11-07-ad3a5d2') 'Get-TagHash on a regular tag'
function Get-UnsortedTags { param($Repo, $Count) $withVariant }
Assert-Eq "nightly-2026-11-07-ad3a5d2`nnightly-2026-11-06-34f137a" (@(Get-RecentTags -Repo 'roc-lang/nightlies' -Count 2) -join "`n") 'Get-RecentTags skips safe'
Assert-Eq 'nightly-2026-11-07-ad3a5d2-safe' (@(Get-RecentTags -Repo 'roc-lang/nightlies' -Count 2 -Variant 'safe') -join "`n") 'Get-RecentTags safe timeline'
Assert-Eq 'ad3a5d2' (Resolve-LatestHash) 'latest resolves to the regular hash'
Assert-Eq 'ad3a5d2' (Resolve-LatestHash -Variant 'safe') 'latest-safe resolves to the hash'
function Get-UnsortedTags { param($Repo, $Count) @('nightly-2026-11-06-34f137a') }
$threw = $false
try { Resolve-LatestHash -Variant 'safe' | Out-Null } catch { $threw = $true; $msg = $_.Exception.Message }
if (-not $threw) { [Console]::Error.WriteLine('FAIL: latest-safe with no safe builds should throw'); exit 1 }
Assert-Contains $msg 'could not find any safe nightlies' 'latest-safe error when none exist'

Write-TestPass
