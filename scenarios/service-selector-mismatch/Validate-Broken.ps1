[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
Assert-ScenarioDeploymentReady 'scenario-source'
Assert-ScenarioDeploymentReady 'scenario-destination'
$destination = Assert-ScenarioDestinationHealthy
$selector = Get-ScenarioServiceSelector
if ($selector -cne 'scenario-destination-missing') { Stop-ScenarioValidation "Injected selector is not present; found '$selector'." }
if (Test-ScenarioSelectorMatchesDestination $selector $destination.AppLabel) { Stop-ScenarioValidation 'Injected Service selector still matches the destination label.' }
$ready = Wait-ScenarioReadyEndpointCount -ExpectedCount 0
$dns = Get-ScenarioDnsResult
if ($dns.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($dns.Output)) { Stop-ScenarioValidation "DNS failed unexpectedly (exit $($dns.ExitCode)): $($dns.Output)" }
$http = Get-ScenarioHttpResult
if ($http.ExitCode -eq 0 -or $http.Output -eq '200') { Stop-ScenarioValidation "HTTP unexpectedly succeeded (exit $($http.ExitCode), result '$($http.Output)')." }
Write-Host "PASS: EXPECTED SCENARIO FAILURE CONFIRMED: pod=$($destination.Name); phase=$($destination.Phase); container Running=$($destination.ContainerRunning); Ready=$($destination.Ready); Pod label=app=$($destination.AppLabel); selector=app=$selector; Ready endpoints=$ready; DNS exit=$($dns.ExitCode); bounded HTTP exit=$($http.ExitCode), result='$($http.Output)'." -ForegroundColor Green