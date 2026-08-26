[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('aks')]
    [string] $Provider,

    [Parameter(Mandatory)]
    [ValidateSet('doctor', 'plan', 'provision', 'connect', 'bootstrap', 'validate', 'scenario', 'inspect', 'destroy', 'verify-clean', 'full')]
    [string] $Operation,

    [string] $TofuPath = 'tofu'
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$InfrastructureRoot = Join-Path $RepositoryRoot 'providers/azure/aks/infrastructure'
. (Join-Path $RepositoryRoot 'providers/azure/aks/scripts/Lab-Aks.ps1')

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
    Write-Host "`nAKS Milestone 1" -ForegroundColor Cyan
    $total = [timespan]::Zero
    foreach ($name in @('doctor', 'plan', 'provision', 'connect', 'bootstrap', 'validate', 'destroy', 'verify-clean')) {
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
    doctor = { Invoke-AksDoctor -TofuPath $TofuPath }
    plan = { Invoke-AksPlan -TofuPath $TofuPath -InfrastructureRoot $InfrastructureRoot }
    provision = { Invoke-AksProvision -TofuPath $TofuPath -InfrastructureRoot $InfrastructureRoot }
    connect = { Invoke-AksConnect }
    bootstrap = { Invoke-AksBootstrap -RepositoryRoot $RepositoryRoot }
    validate = { & (Join-Path $RepositoryRoot 'scripts/Validate-Lab.ps1') -Provider aks; if ($LASTEXITCODE -ne 0) { throw 'AKS validation failed.' } }
    scenario = { Write-Host 'No scenario is implemented for Milestone 1; the validated baseline is the scenario starting point.' }
    inspect = { Invoke-AksInspect }
    destroy = { Invoke-AksDestroy -TofuPath $TofuPath -InfrastructureRoot $InfrastructureRoot -RepositoryRoot $RepositoryRoot }
    'verify-clean' = { Invoke-AksVerifyClean }
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
    foreach ($name in @('provision', 'connect', 'bootstrap', 'validate', 'inspect')) {
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
