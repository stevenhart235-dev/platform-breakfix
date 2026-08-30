$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$cli = Join-Path $repositoryRoot 'breakfix.ps1'
function Assert-True([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Invoke-TestCli([string[]]$Arguments){
 $output=@(& pwsh -NoProfile -File $cli @Arguments 2>&1)
 [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=($output -join [Environment]::NewLine)}
}
$profiles=Invoke-TestCli @('profiles','list','-Json')
Assert-True ($profiles.ExitCode -eq 0) 'profiles JSON failed.'
$p=$profiles.Output|ConvertFrom-Json
Assert-True ($p.Operation -ceq 'list_profiles' -and $p.Success) 'profiles mapped incorrectly.'
Assert-True ((@($p.Data.Profiles).Name -join ',') -ceq 'cilium,istio,minimal') 'profiles JSON incorrect.'
$scenarios=Invoke-TestCli @('scenarios','list','-Json')
Assert-True ($scenarios.ExitCode -eq 0) 'scenarios JSON failed.'
$s=$scenarios.Output|ConvertFrom-Json
Assert-True ($s.Operation -ceq 'list_scenarios' -and $s.Success) 'scenarios mapped incorrectly.'
. (Join-Path $repositoryRoot 'scripts/ScenarioEvidence.ps1')
. (Join-Path $repositoryRoot 'scripts/ScenarioDiagnosis.ps1')
$observations=New-ScenarioObservations $true 'Running' $true $false '/platform-breakfix-readiness-failure' 'scenario-destination' $true 'scenario-destination' $true 0 $true $false $null
$diagnosis=Resolve-ScenarioDiagnosis $observations
$document=New-ScenarioEvidenceDocument -Scenario readiness-probe-failure -Provider aks -Profile minimal -Observations $observations -Diagnosis $diagnosis -Timestamp ([datetimeoffset]'2026-01-01T00:00:00Z')
$artifact=Write-ScenarioEvidence -Evidence $document -RepositoryRoot $repositoryRoot
try {
 $read=Invoke-TestCli @('evidence','read','readiness-probe-failure','-Json');$readJson=$read.Output|ConvertFrom-Json
 Assert-True ($read.ExitCode -eq 0 -and $readJson.Operation -ceq 'read_evidence') 'evidence read mapped incorrectly.'
 $diagnose=Invoke-TestCli @('evidence','diagnose','readiness-probe-failure','-Json');$diagnoseJson=$diagnose.Output|ConvertFrom-Json
 Assert-True ($diagnose.ExitCode -eq 0 -and $diagnoseJson.Operation -ceq 'diagnose_evidence' -and $diagnoseJson.Data.Identifier -ceq 'readiness_probe_failure') 'evidence diagnose mapped incorrectly.'
} finally { Remove-Item (Split-Path -Parent $artifact) -Recurse -Force }
$status=Invoke-TestCli @('lab','status','-Provider','eks','-Json');$statusJson=$status.Output|ConvertFrom-Json
Assert-True ($status.ExitCode -ne 0 -and $statusJson.Operation -ceq 'get_lab_status' -and $statusJson.Error.Code -ceq 'PROVIDER_UNSUPPORTED') 'lab status mapped incorrectly.'
$human=Invoke-TestCli @('profiles','list')
Assert-True ($human.ExitCode -eq 0 -and $human.Output -match 'minimal\s+aks') 'Human output unreadable.'
$unknown=Invoke-TestCli @('unknown','command','-Json')
Assert-True ($unknown.ExitCode -ne 0) 'Unknown command succeeded.'
Assert-True (($unknown.Output|ConvertFrom-Json).Error.Code -ceq 'INVALID_ARGUMENT') 'Unknown error unbounded.'
$missing=Invoke-TestCli @('evidence','read','-Json')
Assert-True ($missing.ExitCode -ne 0) 'Missing argument succeeded.'
$mutation=Invoke-TestCli @('lab','destroy','-Provider','aks','-Json')
Assert-True ($mutation.ExitCode -ne 0) 'Mutation command exists.'
$notFound=Invoke-TestCli @('evidence','read','readiness-probe-failure','-Json')
Assert-True ($notFound.ExitCode -ne 0) 'Missing evidence succeeded.'
$n=$notFound.Output|ConvertFrom-Json
Assert-True ($n.Operation -ceq 'read_evidence' -and $n.Error.Code -ceq 'NOT_FOUND') 'Evidence failure mapped incorrectly.'
$source=Get-Content -Raw $cli
Assert-True ($source -match 'Invoke-BreakfixOperation') 'CLI does not delegate.'
foreach($mapping in @('list_profiles','list_scenarios','read_evidence','diagnose_evidence','get_lab_status')){Assert-True ($source -match [regex]::Escape($mapping)) "Missing mapping: $mapping"}
foreach($term in @('Get-ChildItem','ConvertFrom-Json','Read-ScenarioEvidence','Resolve-ScenarioDiagnosis','profile.psd1','scenario.psd1','readiness_probe_failure','service_selector_mismatch','az ','aws ','kubectl ','tofu ')){Assert-True ($source -notmatch [regex]::Escape($term)) "CLI business/provider logic found: $term"}
Write-Host 'PASS: Breakfix CLI adapter tests.' -ForegroundColor Green
