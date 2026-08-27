[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $RepositoryRoot 'providers/azure/aks/scripts/Lab-Aks.ps1')

function Assert-Equal {
    param(
        [Parameter(Mandatory)] $Actual,
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)][string] $Message
    )
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$created = '2026-08-27T12:00:00Z'
$expires = '2026-08-27T16:00:00Z'

$active = Get-AksLabTemporalState `
    -CreatedAt $created -ExpiresAt $expires `
    -Now ([datetimeoffset]'2026-08-27T14:00:00Z')
Assert-Equal -Actual $active.State -Expected 'ACTIVE' -Message 'Active classification failed.'
Assert-Equal -Actual $active.Age.TotalHours -Expected 2 -Message 'Active age failed.'
Assert-Equal -Actual $active.Remaining.TotalHours -Expected 2 -Message 'Remaining TTL failed.'

$stale = Get-AksLabTemporalState `
    -CreatedAt $created -ExpiresAt $expires `
    -Now ([datetimeoffset]'2026-08-27T17:30:00Z')
Assert-Equal -Actual $stale.State -Expected 'STALE' -Message 'Stale classification failed.'
Assert-Equal -Actual $stale.Overdue.TotalMinutes -Expected 90 -Message 'Stale overdue duration failed.'

Write-Host 'PASS: ACTIVE and STALE timestamp classification is deterministic.' -ForegroundColor Green
