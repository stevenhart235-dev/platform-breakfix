[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
Assert-ScenarioDeploymentReady 'scenario-source'
$destination = Wait-ScenarioDestinationState -ProbePath $script:ScenarioBrokenProbePath -Ready 'False'
$selector = Get-ScenarioServiceSelector
if ($selector -cne $script:ScenarioDestination) { Stop-ScenarioValidation "Service selector changed unexpectedly; found '$selector'." }
$ready = Wait-ScenarioReadyEndpointCount -ExpectedCount 0
$dns = Get-ScenarioDnsResult
if ($dns.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($dns.Output)) { Stop-ScenarioValidation "DNS failed unexpectedly (exit $($dns.ExitCode)): $($dns.Output)" }
$http = Get-ScenarioHttpResult
if ($http.ExitCode -eq 0 -or $http.Output -eq '200') { Stop-ScenarioValidation "HTTP unexpectedly succeeded (exit $($http.ExitCode), result '$($http.Output)')." }
$events = @(Get-ScenarioReadinessEvents -PodName $destination.Name)
Write-Host "PASS: EXPECTED SCENARIO FAILURE CONFIRMED: pod=$($destination.Name); phase=$($destination.Phase); container Running=$($destination.ContainerRunning); Ready=$($destination.Ready); readiness path=$($destination.ProbePath); selector=app=$selector; Ready endpoints=$ready; DNS exit=$($dns.ExitCode); bounded HTTP exit=$($http.ExitCode), result='$($http.Output)'; readiness events=$($events.Count)." -ForegroundColor Green
