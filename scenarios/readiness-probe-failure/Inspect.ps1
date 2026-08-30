[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
$destination = Get-ScenarioCurrentDestinationEvidence -ExpectedProbePath $script:ScenarioBrokenProbePath
$selector = Get-ScenarioServiceSelector
$readyEndpoints = Get-ScenarioReadyEndpointCount
$dns = Get-ScenarioDnsResult
$http = Get-ScenarioHttpResult
$events = @(Get-ScenarioReadinessEvents -PodName $destination.Name)
Write-Host 'Scenario diagnosis:' -ForegroundColor Cyan
Write-Host "  Destination Pod:      $($destination.Name)"
Write-Host "  Pod phase:            $($destination.Phase)"
Write-Host "  Container Running:    $($destination.ContainerRunning)"
Write-Host "  Pod Ready condition:  $($destination.Ready)"
Write-Host "  Readiness path:       $($destination.ProbePath)"
Write-Host "  Expected healthy path:$script:ScenarioHealthyProbePath"
Write-Host "  Service selector:     app=$selector"
Write-Host "  Destination labels:   app=$($destination.Labels.app)"
Write-Host "  Ready endpoints:      $readyEndpoints"
Write-Host "  DNS exit/result:      $($dns.ExitCode) / $($dns.Output)"
Write-Host "  HTTP exit/result:     $($http.ExitCode) / $($http.Output)"
foreach ($event in $events) { Write-Host "  Readiness event:      $event" }
if ($destination.Phase -ceq 'Running' -and $destination.ContainerRunning -and $destination.Ready -ceq 'False' -and
    $destination.ProbePath -ceq $script:ScenarioBrokenProbePath -and $selector -ceq $script:ScenarioDestination -and
    $readyEndpoints -eq 0 -and $dns.ExitCode -eq 0) {
    Write-Host 'PASS: Root cause is the injected invalid readiness path; the container is Running, the Pod is NotReady, and the Service selector remains correct.' -ForegroundColor Green
} else { Stop-ScenarioValidation 'Inspection evidence does not uniquely identify the expected readiness probe failure.' }
