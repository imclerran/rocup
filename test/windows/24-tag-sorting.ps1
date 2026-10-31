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

Write-TestPass
