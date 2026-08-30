[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
$destination = Assert-ScenarioDestinationHealthy
$selector = Get-ScenarioServiceSelector
$readyEndpoints = Get-ScenarioReadyEndpointCount
$dns = Get-ScenarioDnsResult
$http = Get-ScenarioHttpResult
Write-Host 'Scenario diagnosis:' -ForegroundColor Cyan
Write-Host "  Destination Pod:      $($destination.Name)"
Write-Host "  Pod phase:            $($destination.Phase)"
Write-Host "  Container Running:    $($destination.ContainerRunning)"
Write-Host "  Pod Ready condition:  $($destination.Ready)"
Write-Host "  Service selector:     app=$selector"
Write-Host "  Destination labels:   app=$($destination.AppLabel)"
Write-Host "  Ready endpoints:      $readyEndpoints"
Write-Host "  DNS exit/result:      $($dns.ExitCode) / $($dns.Output)"
Write-Host "  HTTP exit/result:     $($http.ExitCode) / $($http.Output)"
if (-not (Test-ScenarioSelectorMatchesDestination $selector $destination.AppLabel) -and $selector -ceq 'scenario-destination-missing' -and
    $destination.Phase -ceq 'Running' -and $destination.ContainerRunning -and $destination.Ready -ceq 'True' -and
    $readyEndpoints -eq 0 -and $dns.ExitCode -eq 0) {
    Write-Host 'PASS: Root cause is a Service selector mismatch; the destination remains Running and Ready, and readiness is not the failure.' -ForegroundColor Green
} else { Stop-ScenarioValidation 'Inspection evidence does not uniquely identify the expected Service selector mismatch.' }