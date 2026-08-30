[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
Assert-ScenarioDeploymentReady 'scenario-source'
Assert-ScenarioDeploymentReady 'scenario-destination'
$selector = Get-ScenarioServiceSelector
if ($selector -cne 'scenario-destination-missing') { Stop-ScenarioValidation "Injected selector is not present; found '$selector'." }
$ready = Wait-ScenarioReadyEndpointCount -ExpectedCount 0
$dns = Get-ScenarioDnsResult
if ($dns.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($dns.Output)) { Stop-ScenarioValidation "DNS failed unexpectedly (exit $($dns.ExitCode)): $($dns.Output)" }
$http = Get-ScenarioHttpResult
if ($http.ExitCode -eq 0 -or $http.Output -eq '200') { Stop-ScenarioValidation "HTTP unexpectedly succeeded (exit $($http.ExitCode), result '$($http.Output)')." }
Write-Host "PASS: EXPECTED SCENARIO FAILURE CONFIRMED: selector=$selector; zero Ready endpoints; workloads Ready; DNS exit=$($dns.ExitCode); bounded HTTP exit=$($http.ExitCode), result='$($http.Output)'." -ForegroundColor Green
