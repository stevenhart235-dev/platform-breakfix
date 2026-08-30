$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repositoryRoot 'scripts/BreakfixOperations.ps1')
. (Join-Path $repositoryRoot 'scripts/ScenarioEvidence.ps1')
. (Join-Path $repositoryRoot 'scripts/ScenarioDiagnosis.ps1')
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-Error($Result,[string]$Code){Assert-True (-not $Result.Success) "Expected $Code failure.";Assert-True ($Result.Error.Code -ceq $Code) "Expected $Code, got $($Result.Error.Code).";Assert-True ($null -eq $Result.Data) 'Failure Data must be null.'}
function New-Observations([string]$Kind){
 if($Kind -ceq 'readiness'){return New-ScenarioObservations $true 'Running' $true $false '/platform-breakfix-readiness-failure' 'scenario-destination' $true 'scenario-destination' $true 0 $true $false $null}
 if($Kind -ceq 'selector'){return New-ScenarioObservations $true 'Running' $true $true '/' 'scenario-destination' $true 'scenario-destination-missing' $false 0 $true $false $null}
 if($Kind -ceq 'healthy'){return New-ScenarioObservations $true 'Running' $true $true '/' 'scenario-destination' $true 'scenario-destination' $true 1 $true $true 200}
 New-ScenarioObservations $true 'Running' $true $false '/platform-breakfix-readiness-failure' 'scenario-destination' $true 'scenario-destination-missing' $false 0 $true $false $null
}
function Write-Evidence([string]$Artifact,[string]$Identity,[string]$Kind){
 $observations=New-Observations $Kind
 $diagnosis=if($Kind -ceq 'selector'){[pscustomobject]@{Identifier='service_selector_mismatch';Summary='selector fixture'}}else{[pscustomobject]@{Identifier='readiness_probe_failure';Summary='readiness fixture'}}
 $document=New-ScenarioEvidenceDocument -Scenario $Identity -Provider aks -Profile minimal -Observations $observations -Diagnosis $diagnosis -Timestamp ([datetimeoffset]'2026-01-01T00:00:00Z')
 $directory=Join-Path $repositoryRoot '.runtime/scenario-evidence';[IO.Directory]::CreateDirectory($directory)|Out-Null
 [IO.File]::WriteAllText((Join-Path $directory "$Artifact.json"),(ConvertTo-ScenarioEvidenceJson $document),[Text.UTF8Encoding]::new($false))
}

$allowlist=@('diagnose_evidence','get_lab_status','list_profiles','list_scenarios','read_evidence')
Assert-True (@(Compare-Object ($script:BreakfixPublicOperations|Sort-Object) $allowlist).Count -eq 0) 'Public operation allowlist changed.'
Assert-True ($script:BreakfixOperationContractVersion -eq 1) 'Operation Contract version changed.'
$profiles=Invoke-BreakfixOperation list_profiles @{}
Assert-True ($profiles.Success -and $profiles.ContractVersion -eq 1 -and $null -eq $profiles.Error) 'Profile success envelope failed.'
Assert-True ((@($profiles.Data.Profiles).Name -join ',') -ceq 'cilium,istio,minimal') 'Profile catalog/order failed.'
Assert-True (@(@($profiles.Data.Profiles)|Where-Object Provider -cne 'aks').Count -eq 0) 'Profile provider failed.'
$eks=Invoke-BreakfixOperation list_profiles @{Provider='eks'}
Assert-True ($eks.Success -and @($eks.Data.Profiles).Count -eq 0) 'EKS profile truth failed.'
$scenarios=Invoke-BreakfixOperation list_scenarios @{}
Assert-True ($scenarios.Success -and ((@($scenarios.Data.Scenarios).Name -join ',') -ceq 'readiness-probe-failure,service-selector-mismatch')) 'Scenario catalog/order failed.'
Assert-True ('bad-service-selector' -cnotin @($scenarios.Data.Scenarios).Name) 'Removed scenario is active.'
foreach($scenario in @($scenarios.Data.Scenarios)){Assert-True (@($scenario.SupportedProviders).Count -gt 0) 'Provider metadata missing.';Assert-True (@($scenario.SupportedProfiles).Count -gt 0) 'Profile metadata missing.'}
$bad=[pscustomobject]@{ContractVersion=1;Operation='list_profiles';Success=$true;Data=@{};Error=$null;Extra=$true}
$rejected=$false;try{Assert-BreakfixOperationResult $bad|Out-Null}catch{$rejected=$true};Assert-True $rejected 'Unknown envelope field accepted.'
Assert-Error (Invoke-BreakfixOperation list_scenarios @{Extra='no'}) INVALID_ARGUMENT
$originalRoot=$script:BreakfixRepositoryRoot;try{$script:BreakfixRepositoryRoot=Join-Path $repositoryRoot 'missing-root';$internal=Invoke-BreakfixOperation list_profiles @{}}finally{$script:BreakfixRepositoryRoot=$originalRoot};Assert-Error $internal INTERNAL_ERROR
Assert-True ($internal.Error.Message -notmatch '[A-Za-z]:\\|missing-root|ScriptStackTrace') 'Internal details leaked.'

$runtime=Join-Path $repositoryRoot '.runtime/scenario-evidence'
try{
 Write-Evidence readiness-probe-failure readiness-probe-failure readiness
 Write-Evidence service-selector-mismatch service-selector-mismatch selector
 $read=Invoke-BreakfixOperation read_evidence @{Scenario='readiness-probe-failure'}
 Assert-True ($read.Success -and $read.Data.SchemaVersion -eq 1) 'Evidence v1 read failed.'
 $d=Invoke-BreakfixOperation diagnose_evidence @{Scenario='readiness-probe-failure'}
 Assert-True ($d.Success -and $d.Data.Identifier -ceq 'readiness_probe_failure') 'Readiness diagnosis failed.'
 $d=Invoke-BreakfixOperation diagnose_evidence @{Scenario='service-selector-mismatch'}
 Assert-True ($d.Success -and $d.Data.Identifier -ceq 'service_selector_mismatch') 'Selector diagnosis failed.'
 foreach($unsafe in @('../readiness-probe-failure','..\readiness-probe-failure','/tmp/evidence','C:\temp\evidence','nested/name')){Assert-Error (Invoke-BreakfixOperation read_evidence @{Scenario=$unsafe}) INVALID_ARGUMENT}
 Remove-Item (Join-Path $runtime 'readiness-probe-failure.json')
 Assert-Error (Invoke-BreakfixOperation read_evidence @{Scenario='readiness-probe-failure'}) NOT_FOUND
 [IO.File]::WriteAllText((Join-Path $runtime 'readiness-probe-failure.json'),'{',[Text.UTF8Encoding]::new($false))
 Assert-Error (Invoke-BreakfixOperation read_evidence @{Scenario='readiness-probe-failure'}) INVALID_EVIDENCE
 [IO.File]::WriteAllText((Join-Path $runtime 'readiness-probe-failure.json'),'{"SchemaVersion":2}',[Text.UTF8Encoding]::new($false))
 Assert-Error (Invoke-BreakfixOperation read_evidence @{Scenario='readiness-probe-failure'}) INVALID_EVIDENCE
 Write-Evidence readiness-probe-failure readiness-probe-failure healthy
 Assert-Error (Invoke-BreakfixOperation diagnose_evidence @{Scenario='readiness-probe-failure'}) DIAGNOSIS_FAILED
 Write-Evidence readiness-probe-failure readiness-probe-failure hybrid
 Assert-Error (Invoke-BreakfixOperation diagnose_evidence @{Scenario='readiness-probe-failure'}) DIAGNOSIS_FAILED
 Write-Evidence service-selector-mismatch service-selector-mismatch readiness
 $d=Invoke-BreakfixOperation diagnose_evidence @{Scenario='service-selector-mismatch'}
 Assert-True ($d.Success -and $d.Data.Identifier -ceq 'readiness_probe_failure') 'Diagnosis depends on scenario identity.'
 Write-Evidence service-selector-mismatch readiness-probe-failure readiness
 Assert-Error (Invoke-BreakfixOperation read_evidence @{Scenario='service-selector-mismatch'}) INVALID_EVIDENCE
}finally{if(Test-Path $runtime){Remove-Item $runtime -Recurse -Force}}

$original=$script:BreakfixStatusReaders.aks
try{
 foreach($fixture in @(
  @{Native=[pscustomobject]@{State='NO LAB'};Expected='NO_LAB'},
  @{Native=[pscustomobject]@{State='ACTIVE';Profile='minimal';CreatedAt=[datetimeoffset]'2026-01-01T00:00:00Z';ExpiresAt=[datetimeoffset]'2026-01-01T04:00:00Z'};Expected='ACTIVE'},
  @{Native=[pscustomobject]@{State='STALE';Profile='cilium';CreatedAt='2026-01-01T00:00:00Z';ExpiresAt='2026-01-01T04:00:00Z'};Expected='STALE'},
  @{Native=[pscustomobject]@{State='EXISTING INVALID'};Expected='UNKNOWN'}
 )){
  $script:statusFixture=$fixture.Native;$script:BreakfixStatusReaders.aks={param($Root)$script:statusFixture}
  $status=Invoke-BreakfixOperation get_lab_status @{Provider='aks'}
  Assert-True ($status.Success -and $status.Data.State -ceq $fixture.Expected) "Status $($fixture.Expected) failed."
  Assert-True ($status.Data.ConnectionState -ceq 'UNKNOWN') 'Connection state mutated.'
 }
 $script:BreakfixStatusReaders.aks={param($Root)throw 'C:\secret\provider failure'}
 $unavailable=Invoke-BreakfixOperation get_lab_status @{Provider='aks'};Assert-Error $unavailable LAB_STATE_UNAVAILABLE
 Assert-True ($unavailable.Error.Message -notmatch 'secret|C:\\') 'Provider details leaked.'
}finally{$script:BreakfixStatusReaders.aks=$original}
Assert-Error (Invoke-BreakfixOperation get_lab_status @{Provider='eks'}) PROVIDER_UNSUPPORTED
Assert-Error (Invoke-BreakfixOperation get_lab_status @{}) INVALID_ARGUMENT
Assert-Error (Invoke-BreakfixOperation list_profiles @{Provider=''}) INVALID_ARGUMENT
$source=Get-Content -Raw (Join-Path $repositoryRoot 'scripts/BreakfixOperations.ps1')
Assert-True ($source -match 'Read-ScenarioEvidence' -and $source -match 'Resolve-ScenarioDiagnosis') 'Evidence or diagnosis does not delegate to accepted primitives.'
foreach($term in @('Test-ReadinessProbeFailureObservations','Test-ServiceSelectorMismatchObservations',"'minimal'","'cilium'","'istio'")){Assert-True ($source -notmatch [regex]::Escape($term)) "Operation layer duplicates catalog or diagnosis logic: $term"}
foreach($term in @('get-credentials','update-kubeconfig','tofu apply','tofu destroy','kubectl apply','kubectl delete')){Assert-True ($source -notmatch [regex]::Escape($term)) "Mutation found: $term"}
Write-Host 'PASS: Breakfix Operations v1 contract tests.' -ForegroundColor Green
