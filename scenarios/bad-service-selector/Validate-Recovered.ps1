[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
Assert-ScenarioDeploymentReady 'scenario-source'
Assert-ScenarioDeploymentReady 'scenario-destination'
$selector = Get-ScenarioServiceSelector
if ($selector -cne 'scenario-destination') { Stop-ScenarioValidation "Expected healthy selector 'scenario-destination'; found '$selector'." }
$ready = Wait-ScenarioReadyEndpointCount -ExpectedCount 1
$dns = Get-ScenarioDnsResult
if ($dns.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($dns.Output)) { Stop-ScenarioValidation "Healthy Service DNS failed (exit $($dns.ExitCode)): $($dns.Output)" }
$http = Get-ScenarioHttpResult
if ($http.ExitCode -ne 0 -or $http.Output -cne '200') { Stop-ScenarioValidation "Healthy HTTP probe failed (exit $($http.ExitCode), HTTP '$($http.Output)')." }
Write-Host "PASS: Healthy/recovered scenario: workloads Ready; selector=$selector; Ready endpoints=$ready; DNS exit=$($dns.ExitCode); HTTP exit=$($http.ExitCode), status=$($http.Output)." -ForegroundColor Green
