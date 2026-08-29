[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('aks')]
    [string] $Provider,

    [string] $Profile = 'minimal',

    [Parameter(Mandatory)]
    [ValidateSet('doctor', 'plan', 'provision', 'connect', 'bootstrap', 'validate', 'scenario', 'inspect', 'destroy', 'verify-clean', 'full')]
    [string] $Operation,

    [string] $TofuPath = 'tofu',

    [ValidateRange(1, 24)]
    [int] $LabTtlHours = 4
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$InfrastructureRoot = Join-Path $RepositoryRoot 'providers/azure/aks/infrastructure'
$ProviderRoot = Join-Path $RepositoryRoot 'providers/azure/aks'
. (Join-Path $ProviderRoot 'scripts/Profile-Aks.ps1')
$ResolvedProfile = Resolve-AksProfile -Provider $Provider -ProfileName $Profile -ProfilesRoot (Join-Path $ProviderRoot 'profiles')
. (Join-Path $RepositoryRoot 'providers/azure/aks/scripts/Lab-Aks.ps1')
$script:AksDefaults.TtlHours = $LabTtlHours
$script:AksDefaults.VmSize = $ResolvedProfile.InfrastructureInputs.NodeVmSize
$script:AksDefaults.NodeCount = $ResolvedProfile.InfrastructureInputs.NodeCount

$script:AksDefaults.EstimatedNodeHourlyUsd = if ($ResolvedProfile.InfrastructureInputs.NodeVmSize -eq 'Standard_D4as_v7') { [decimal]0.20 } else { [decimal]0.10 }
function Invoke-TimedOperation {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][scriptblock] $Action,
        [Parameter(Mandatory)][hashtable] $Timings
    )
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try { & $Action }
    finally {
        $watch.Stop()
        $Timings[$Name] = $watch.Elapsed
        Write-Host "$Name duration: $($watch.Elapsed.ToString('hh\:mm\:ss'))"
    }
}

function Show-TimingSummary {
    param([hashtable] $Timings)
    Write-Host "`nAKS Milestone 3 ($($ResolvedProfile.Name) profile)" -ForegroundColor Cyan
    $total = [timespan]::Zero
    foreach ($name in @('doctor', 'plan', 'provision', 'connect', 'bootstrap', 'validate', 'scenario', 'inspect', 'destroy', 'verify-clean')) {
        if ($Timings.ContainsKey($name)) {
            $elapsed = [timespan]$Timings[$name]
            $total += $elapsed
            Write-Host ('{0,-14}{1}' -f $name, $elapsed.ToString('hh\:mm\:ss'))
        }
    }
    Write-Host ('{0,-14}{1}' -f 'Total', $total.ToString('hh\:mm\:ss'))
}

$timings = @{}
$actions = @{
    doctor = { Invoke-AksDoctor -TofuPath $TofuPath -Profile $ResolvedProfile }
    plan = { Invoke-AksPlan -TofuPath $TofuPath -InfrastructureRoot $InfrastructureRoot -Profile $ResolvedProfile }
    provision = { Invoke-AksProvision -TofuPath $TofuPath -InfrastructureRoot $InfrastructureRoot -Profile $ResolvedProfile }
    connect = { Invoke-AksConnect -Profile $ResolvedProfile }
    bootstrap = { Invoke-AksBootstrap -Profile $ResolvedProfile }
    validate = {
        & (Join-Path $RepositoryRoot 'scripts/Validate-Lab.ps1') -Provider aks -ProfileName $ResolvedProfile.Name -ProfileValidationScript $ResolvedProfile.ValidationScript
        if ($LASTEXITCODE -ne 0) { throw 'AKS validation failed.' }
    }
    scenario = { Invoke-AksScenario -Profile $ResolvedProfile }
    inspect = { Invoke-AksInspect -Profile $ResolvedProfile }
    destroy = { Invoke-AksDestroy -TofuPath $TofuPath -InfrastructureRoot $InfrastructureRoot -Profile $ResolvedProfile }
    'verify-clean' = { Invoke-AksVerifyClean -Profile $ResolvedProfile }
}

if ($Operation -ne 'full') {
    try {
        Invoke-TimedOperation -Name $Operation -Action $actions[$Operation] -Timings $timings
        Show-TimingSummary -Timings $timings
        exit 0
    }
    catch {
        Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$provisionAttempted = $false
$lifecycleSucceeded = $false
$cleanupSucceeded = $false
try {
    foreach ($name in @('doctor', 'plan')) {
        Invoke-TimedOperation -Name $name -Action $actions[$name] -Timings $timings
    }
    $provisionAttempted = $true
    foreach ($name in @('provision', 'connect', 'bootstrap', 'validate', 'scenario', 'inspect')) {
        Invoke-TimedOperation -Name $name -Action $actions[$name] -Timings $timings
    }
    $lifecycleSucceeded = $true
}
catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $provisionAttempted) {
        Show-TimingSummary -Timings $timings
        exit 1
    }
}
finally {
    if ($provisionAttempted) {
        try {
            Invoke-TimedOperation -Name 'destroy' -Action $actions.destroy -Timings $timings
            Invoke-TimedOperation -Name 'verify-clean' -Action $actions['verify-clean'] -Timings $timings
            $cleanupSucceeded = $true
        }
        catch {
            Write-Host "CLEANUP FAILURE: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Show-TimingSummary -Timings $timings
}

if (-not $lifecycleSucceeded -or -not $cleanupSucceeded) { exit 1 }
exit 0
