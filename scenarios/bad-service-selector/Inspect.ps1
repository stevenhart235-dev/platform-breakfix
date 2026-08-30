[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
$selector = Get-ScenarioServiceSelector
$pods = Invoke-ScenarioKubectlJson -Arguments @('get', 'pods', '-n', $script:ScenarioNamespace, '-o', 'json')
$destination = @($pods.items | Where-Object { $_.metadata.labels.app -eq 'scenario-destination' })[0]
$source = @($pods.items | Where-Object { $_.metadata.labels.app -eq 'scenario-source' })[0]
function Test-PodReady($Pod) { @($Pod.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -eq 1 }
$readyEndpoints = Get-ScenarioReadyEndpointCount
$dns = Get-ScenarioDnsResult
$http = Get-ScenarioHttpResult
Write-Host 'Scenario diagnosis:' -ForegroundColor Cyan
Write-Host "  Service:              $script:ScenarioService"
Write-Host "  Service selector:     app=$selector"
Write-Host "  Destination labels:   app=$($destination.metadata.labels.app)"
Write-Host "  Ready endpoints:      $readyEndpoints"
Write-Host "  Source Ready:         $(Test-PodReady $source)"
Write-Host "  Destination Ready:    $(Test-PodReady $destination)"
Write-Host "  DNS exit/result:      $($dns.ExitCode) / $($dns.Output)"
Write-Host "  HTTP exit/result:     $($http.ExitCode) / $($http.Output)"
if ($selector -cne [string]$destination.metadata.labels.app -and $readyEndpoints -eq 0 -and $dns.ExitCode -eq 0) {
    Write-Host 'PASS: Root cause is a Service selector mismatch; DNS and workloads remain healthy.' -ForegroundColor Green
} else { Stop-ScenarioValidation 'Inspection evidence does not uniquely identify the expected selector mismatch.' }
