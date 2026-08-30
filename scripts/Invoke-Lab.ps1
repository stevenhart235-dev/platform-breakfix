[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('aks')]
    [string] $Provider,

    [string] $Profile = 'minimal',

    [string] $Scenario = '',

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
. (Join-Path $RepositoryRoot 'scripts/Scenario.ps1')
$ResolvedScenario = Resolve-LabScenario -Provider $Provider -ProfileName $ResolvedProfile.Name -ScenarioName $Scenario -ScenariosRoot (Join-Path $RepositoryRoot 'scenarios')
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
    Write-Host "`nAKS lifecycle (profile=$($ResolvedProfile.Name), scenario=$($ResolvedScenario.Name))" -ForegroundColor Cyan
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

function Invoke-ResolvedScenario {
    param([Parameter(Mandatory)] $ResolvedScenario)
    if ($ResolvedScenario.IsNone) { Write-Host 'No scenario selected; the validated baseline remains unchanged.'; return }
    Write-Host "Resolved scenario: $($ResolvedScenario.Name)"
    Write-Host "Compatibility: provider=$($ResolvedScenario.Provider), profile=$($ResolvedScenario.Profile)"
    $setupAttempted = $false
    try {
        $setupAttempted = $true
        Invoke-CheckedCommand -Command 'kubectl' -Arguments @('apply', '-k', $ResolvedScenario.KubernetesComposition)
        foreach ($deployment in @('scenario-source', 'scenario-destination')) { Invoke-CheckedCommand -Command 'kubectl' -Arguments @('rollout', 'status', "deployment/$deployment", '-n', 'platform-breakfix-scenario', '--timeout=180s') }
        Write-Host 'Scenario healthy precondition:' -ForegroundColor Cyan
        & $ResolvedScenario.Hooks.ValidateRecovered
        Write-Host 'Scenario inject:' -ForegroundColor Cyan
        & $ResolvedScenario.Hooks.Inject
        Write-Host 'Scenario broken validation:' -ForegroundColor Cyan
        & $ResolvedScenario.Hooks.ValidateBroken
        Write-Host 'Scenario inspect:' -ForegroundColor Cyan
        & $ResolvedScenario.Hooks.Inspect
        Write-Host 'Scenario repair:' -ForegroundColor Cyan
        & $ResolvedScenario.Hooks.Repair
        Write-Host 'Scenario recovered validation:' -ForegroundColor Cyan
        & $ResolvedScenario.Hooks.ValidateRecovered
    }
    finally {
        if ($setupAttempted) { Write-Host 'Scenario cleanup:' -ForegroundColor Cyan; & $ResolvedScenario.Hooks.Cleanup }
    }
}
$timings = @{}
$actions = @{
    doctor = { Invoke-AksDoctor -TofuPath $TofuPath -Profile $ResolvedProfile }
    plan = { Invoke-AksPlan -TofuPath $TofuPath -InfrastructureRoot $InfrastructureRoot -Profile $ResolvedProfile -Scenario $ResolvedScenario }
    provision = { Invoke-AksProvision -TofuPath $TofuPath -InfrastructureRoot $InfrastructureRoot -Profile $ResolvedProfile -Scenario $ResolvedScenario }
    connect = { Invoke-AksConnect -Profile $ResolvedProfile }
    bootstrap = { Invoke-AksBootstrap -Profile $ResolvedProfile }
    validate = {
        & (Join-Path $RepositoryRoot 'scripts/Validate-Lab.ps1') -Provider aks -ProfileName $ResolvedProfile.Name -ProfileValidationScript $ResolvedProfile.ValidationScript
        if ($LASTEXITCODE -ne 0) { throw 'AKS validation failed.' }
    }
    scenario = {
        Invoke-ResolvedScenario -ResolvedScenario $ResolvedScenario
        if (-not $ResolvedScenario.IsNone) {
            Write-Host 'Post-scenario shared baseline validation:' -ForegroundColor Cyan
            & (Join-Path $RepositoryRoot 'scripts/Validate-Lab.ps1') -Provider aks -ProfileName $ResolvedProfile.Name -ProfileValidationScript $ResolvedProfile.ValidationScript
            if ($LASTEXITCODE -ne 0) { throw 'Post-scenario AKS baseline validation failed.' }
        }
    }
    inspect = { Invoke-AksInspect -Profile $ResolvedProfile }
    destroy = { Invoke-AksDestroy -TofuPath $TofuPath -InfrastructureRoot $InfrastructureRoot -Profile $ResolvedProfile -Scenario $ResolvedScenario }
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
