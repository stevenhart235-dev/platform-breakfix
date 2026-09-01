[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $RepositoryRoot 'scripts/ScenarioEvidence.ps1')
. (Join-Path $RepositoryRoot 'scripts/ScenarioDiagnosis.ps1')

function New-TestObservations {
    param([bool]$Ready=$false,[string]$Path='/platform-breakfix-readiness-failure',[string]$Selector='scenario-destination',[bool]$SelectorMatches=$true)
    New-ScenarioObservations -DestinationPodExists $true -Phase Running -ContainerRunning $true -Ready $Ready -ReadinessProbePath $Path -DestinationLabel scenario-destination -ServiceExists $true -Selector $Selector -SelectorMatches $SelectorMatches -ReadyEndpointCount 0 -DnsSuccess $true -HttpSuccess $false -HttpStatus $null
}
function Copy-TestObservations($Value) { ($Value | ConvertTo-Json -Depth 8) | ConvertFrom-Json }
function Assert-Diagnosis([string]$Name,$Observations,[string]$Expected) { $actual=Resolve-ScenarioDiagnosis $Observations; if($actual.Identifier -cne $Expected){throw "$Name expected $Expected, got $($actual.Identifier)."}; Write-Host "PASS: $Name -> $Expected" -ForegroundColor Green; $actual }
function Assert-Fails([string]$Name,[scriptblock]$Action) { try{& $Action|Out-Null}catch{Write-Host "PASS: $Name fails closed." -ForegroundColor Green;return};throw "$Name unexpectedly produced a diagnosis." }

$readiness=New-TestObservations
$selector=New-TestObservations -Ready $true -Path '/' -Selector 'scenario-destination-missing' -SelectorMatches $false
$readinessDiagnosis=Assert-Diagnosis 'Exact readiness observation set' $readiness readiness_probe_failure
$selectorDiagnosis=Assert-Diagnosis 'Exact selector observation set' $selector service_selector_mismatch
if($readinessDiagnosis.Summary -cne (Resolve-ScenarioDiagnosis $readiness).Summary -or $selectorDiagnosis.Summary -cne (Resolve-ScenarioDiagnosis $selector).Summary){throw 'Diagnosis summary is not deterministic.'}
if ($readinessDiagnosis.Summary -cne 'Destination workload is running but not Ready because the injected readiness probe fails while the Service selector still matches.' -or $selectorDiagnosis.Summary -cne 'Destination workload is running and Ready, but the Service selector does not match the destination workload label.') { throw 'Accepted diagnosis summary changed.' }
Write-Host 'PASS: identifiers and summaries are deterministic and byte-compatible.' -ForegroundColor Green

$renamedReadiness=New-ScenarioEvidenceDocument -Scenario arbitrary-producer -Provider aks -Profile minimal -Observations $readiness -Diagnosis $readinessDiagnosis
$renamedSelector=New-ScenarioEvidenceDocument -Scenario another-producer -Provider aks -Profile minimal -Observations $selector -Diagnosis $selectorDiagnosis
if((Resolve-ScenarioDiagnosis $renamedReadiness.Observations).Identifier -cne 'readiness_probe_failure' -or (Resolve-ScenarioDiagnosis $renamedSelector.Observations).Identifier -cne 'service_selector_mismatch'){throw 'Scenario metadata changed diagnosis.'}
Write-Host 'PASS: scenario identity does not participate in diagnosis.' -ForegroundColor Green

$healthy=Copy-TestObservations $selector; $healthy.Service.Selector.app='scenario-destination'; $healthy.Service.SelectorMatchesDestinationLabel=$true; $healthy.Service.ReadyEndpointCount=1; $healthy.Connectivity.HttpSuccess=$true; $healthy.Connectivity.HttpStatus=200
Assert-Fails 'Healthy observations' { Resolve-ScenarioDiagnosis $healthy }
$hybrid=Copy-TestObservations $readiness; $hybrid.Service.Selector.app='scenario-destination-missing'; $hybrid.Service.SelectorMatchesDestinationLabel=$false
Assert-Fails 'Ready=false selector-mismatch hybrid' { Resolve-ScenarioDiagnosis $hybrid }
$readyCorrect=Copy-TestObservations $selector; $readyCorrect.Service.Selector.app='scenario-destination'; $readyCorrect.Service.SelectorMatchesDestinationLabel=$true
Assert-Fails 'Ready=true with correct selector' { Resolve-ScenarioDiagnosis $readyCorrect }
$notReadyHealthyPath=Copy-TestObservations $readiness; $notReadyHealthyPath.Workload.ReadinessProbePath='/'
Assert-Fails 'Ready=false with healthy readiness path' { Resolve-ScenarioDiagnosis $notReadyHealthyPath }
$readyWrongBrokenPath=Copy-TestObservations $selector; $readyWrongBrokenPath.Workload.ReadinessProbePath='/platform-breakfix-readiness-failure'
Assert-Fails 'Ready=true wrong selector with broken path' { Resolve-ScenarioDiagnosis $readyWrongBrokenPath }
foreach($case in @(
    @('Nonzero endpoint count','Service.ReadyEndpointCount',1),
    @('DNS failure','Connectivity.DnsSuccess',$false),
    @('HTTP success','Connectivity.HttpSuccess',$true),
    @('Pod not Running','Workload.Phase','Pending'),
    @('Container not running','Workload.ContainerRunning',$false),
    @('Pod missing','Workload.DestinationPodExists',$false),
    @('Service missing','Service.Exists',$false)
)){
    $changed=Copy-TestObservations $readiness; $section,$field=$case[1].Split('.'); $changed.$section.$field=$case[2]; Assert-Fails $case[0] { Resolve-ScenarioDiagnosis $changed }
}
$inconsistent=Copy-TestObservations $readiness; $inconsistent.Service.SelectorMatchesDestinationLabel=$false
Assert-Fails 'Internally inconsistent selector evidence' { Resolve-ScenarioDiagnosis $inconsistent }
$inconsistentHttp=Copy-TestObservations $readiness; $inconsistentHttp.Connectivity.HttpStatus=200
Assert-Fails 'Internally inconsistent HTTP evidence' { Resolve-ScenarioDiagnosis $inconsistentHttp }
$missing=Copy-TestObservations $readiness; $missing.Workload.psobject.Properties.Remove('Phase')
Assert-Fails 'Required observation missing' { Resolve-ScenarioDiagnosis $missing }
$invalid=Copy-TestObservations $readiness; $invalid.Workload.Ready='false'
Assert-Fails 'Invalid observation type' { Resolve-ScenarioDiagnosis $invalid }
Assert-Fails 'Zero matching rules' { Resolve-DeterministicSelection -Candidates @() }
Assert-Fails 'Ambiguous multiple matching rules' { Resolve-DeterministicSelection -Candidates @(
    [pscustomobject][ordered]@{Name='readiness';Matches=$true;Value=$readinessDiagnosis},
    [pscustomobject][ordered]@{Name='selector';Matches=$true;Value=$selectorDiagnosis}
) }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "platform-breakfix-diagnosis-tests-$([guid]::NewGuid().ToString('N'))"
try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    foreach ($case in @(
        @('readiness-probe-failure',$readiness,$readinessDiagnosis,'readiness_probe_failure'),
        @('service-selector-mismatch',$selector,$selectorDiagnosis,'service_selector_mismatch')
    )) {
        $document = New-ScenarioEvidenceDocument -Scenario $case[0] -Provider aks -Profile minimal -Observations $case[1] -Diagnosis $case[2]
        $path = Write-ScenarioEvidence -Evidence $document -RepositoryRoot $testRoot
        $loaded = Read-ScenarioEvidence $path
        if ($loaded.SchemaVersion -ne 1 -or $loaded.Diagnosis.Identifier -cne $case[3]) { throw "Derived diagnosis was not preserved in $($case[0]) Evidence Contract v1 JSON." }
    }
} finally { if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force } }
Write-Host 'PASS: both derived diagnoses survive Evidence Contract v1 artifact write/read.' -ForegroundColor Green
$engineSource = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'scripts/ScenarioDiagnosis.ps1')
if ($engineSource -match '(?i)kubectl|kubeconfig|\baz\b|Azure|Invoke-Scenario|patch|repair|ScenarioName|\.Scenario\b|confidence|probab|fuzzy|heuristic|ranking') { throw 'Diagnosis engine crosses a prohibited architecture boundary or uses scenario identity/probabilistic behavior.' }
$foundationSource = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'external/cluster-foundation/src/DeterministicSelection.ps1')
if ($engineSource -notmatch 'Resolve-DeterministicSelection' -or $engineSource -match 'Matches\.Count -ne 1|Assert-SingleScenarioDiagnosisMatch') { throw 'Scenario diagnosis does not delegate exclusively to the foundation selection primitive.' }
if ($foundationSource -notmatch 'matches\.Count -ne 1') { throw 'Foundation primitive lacks the canonical exactly-one-match guard.' }
Write-Host 'PASS: diagnosis rules delegate deterministic exactly-one selection to the sole foundation implementation.' -ForegroundColor Green
Write-Host 'PASS: deterministic diagnosis tests completed without Kubernetes or Azure access.' -ForegroundColor Green
