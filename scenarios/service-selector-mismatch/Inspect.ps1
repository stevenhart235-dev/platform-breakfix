[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts/ScenarioEvidence.ps1')
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
Write-Host "  Readiness path:       $($destination.ProbePath)"
Write-Host "  Service selector:     app=$selector"
Write-Host "  Destination labels:   app=$($destination.AppLabel)"
Write-Host "  Ready endpoints:      $readyEndpoints"
Write-Host "  DNS exit/result:      $($dns.ExitCode) / $($dns.Output)"
Write-Host "  HTTP exit/result:     $($http.ExitCode) / $($http.Output)"
if (-not (Test-ScenarioSelectorMatchesDestination $selector $destination.AppLabel) -and $selector -ceq 'scenario-destination-missing' -and
    $destination.Phase -ceq 'Running' -and $destination.ContainerRunning -and $destination.Ready -ceq 'True' -and
    $destination.ProbePath -ceq '/' -and $readyEndpoints -eq 0 -and $dns.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($dns.Output) -and
    $http.ExitCode -ne 0 -and $http.Output -cne '200') {
    Write-Host 'PASS: Root cause is a Service selector mismatch; the destination remains Running and Ready, and readiness is not the failure.' -ForegroundColor Green
    $httpStatus = if ($http.Output -match '^[1-5][0-9]{2}$') { [int]$http.Output } else { $null }
    $evidence = New-ScenarioEvidenceDocument -Scenario 'service-selector-mismatch' -Provider 'aks' -Profile 'minimal' -DestinationPodExists $true -Phase ([string]$destination.Phase) -ContainerRunning ([bool]$destination.ContainerRunning) -Ready $true -ReadinessProbePath $destination.ProbePath -DestinationLabel ([string]$destination.AppLabel) -Selector ([string]$selector) -ServiceExists $true -SelectorMatches $false -ReadyEndpointCount ([int]$readyEndpoints) -DnsSuccess $true -HttpSuccess $false -HttpStatus $httpStatus -DiagnosisIdentifier 'service_selector_mismatch' -DiagnosisSummary 'The Service selector does not match the healthy destination Pod label, leaving the Service without Ready endpoints.'
    $artifact = Write-ScenarioEvidence -Evidence $evidence -RepositoryRoot (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    Write-Host "  Structured evidence:  $artifact"
} else { Stop-ScenarioValidation 'Inspection evidence does not uniquely identify the expected Service selector mismatch.' }
