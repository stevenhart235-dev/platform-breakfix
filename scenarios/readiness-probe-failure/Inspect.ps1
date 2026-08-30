[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repositoryRoot 'scripts/ScenarioEvidence.ps1')
. (Join-Path $repositoryRoot 'scripts/ScenarioDiagnosis.ps1')
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
$httpStatus = if ($http.Output -match '^[1-5][0-9]{2}$') { [int]$http.Output } else { $null }
$observations = New-ScenarioObservations -DestinationPodExists $true -Phase ([string]$destination.Phase) -ContainerRunning ([bool]$destination.ContainerRunning) -Ready ($destination.Ready -ceq 'True') -ReadinessProbePath $destination.ProbePath -DestinationLabel ([string]$destination.Labels.app) -ServiceExists $true -Selector ([string]$selector) -SelectorMatches ($selector -ceq [string]$destination.Labels.app) -ReadyEndpointCount ([int]$readyEndpoints) -DnsSuccess ($dns.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($dns.Output)) -HttpSuccess ($http.ExitCode -eq 0 -and $http.Output -ceq '200') -HttpStatus $httpStatus
$diagnosis = Resolve-ScenarioDiagnosis -Observations $observations
$evidence = New-ScenarioEvidenceDocument -Scenario 'readiness-probe-failure' -Provider 'aks' -Profile 'minimal' -Observations $observations -Diagnosis $diagnosis
$artifact = Write-ScenarioEvidence -Evidence $evidence -RepositoryRoot $repositoryRoot
Write-Host "PASS: Diagnosis: $($diagnosis.Identifier) — $($diagnosis.Summary)" -ForegroundColor Green
Write-Host "  Structured evidence:  $artifact"
