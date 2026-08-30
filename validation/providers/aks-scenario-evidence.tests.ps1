[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $RepositoryRoot 'scripts/ScenarioEvidence.ps1')

function New-TestEvidence {
    param([string]$Scenario, [bool]$Ready, [string]$ProbePath, [string]$Selector, [bool]$SelectorMatches, [string]$Diagnosis)
    New-ScenarioEvidenceDocument -Scenario $Scenario -Provider 'aks' -Profile 'minimal' -DestinationPodExists $true -Phase 'Running' -ContainerRunning $true -Ready $Ready -ReadinessProbePath $ProbePath -DestinationLabel 'scenario-destination' -ServiceExists $true -Selector $Selector -SelectorMatches $SelectorMatches -ReadyEndpointCount 0 -DnsSuccess $true -HttpSuccess $false -HttpStatus $null -DiagnosisIdentifier $Diagnosis -DiagnosisSummary "Deterministic test diagnosis for $Scenario." -Timestamp ([datetimeoffset]'2026-08-30T12:00:00Z')
}

function Assert-Throws([string]$Name, [scriptblock]$Action) {
    try { & $Action | Out-Null } catch { Write-Host "PASS: $Name fails visibly." -ForegroundColor Green; return }
    throw "$Name unexpectedly succeeded."
}

$readiness = New-TestEvidence readiness-probe-failure $false '/platform-breakfix-readiness-failure' 'scenario-destination' $true readiness_probe_failure
$selector = New-TestEvidence service-selector-mismatch $true '/' 'scenario-destination-missing' $false service_selector_mismatch
Assert-ScenarioEvidenceContract $readiness | Out-Null
Assert-ScenarioEvidenceContract $selector | Out-Null
Write-Host 'PASS: Both canonical scenarios satisfy evidence contract version 1.' -ForegroundColor Green

$roundTrip = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
Assert-ScenarioEvidenceContract $roundTrip | Out-Null
if ($roundTrip.Diagnosis.Identifier -cne 'readiness_probe_failure') { throw 'Serialization round-trip changed the diagnosis.' }
Write-Host 'PASS: JSON serialization round-trip preserves structured evidence.' -ForegroundColor Green

$missing = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
$missing.psobject.Properties.Remove('Scenario')
Assert-Throws 'Missing required field' { Assert-ScenarioEvidenceContract $missing }
foreach ($field in @('Provider','Profile')) {
    $invalid = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
    $invalid.psobject.Properties.Remove($field)
    Assert-Throws "Missing $field" { Assert-ScenarioEvidenceContract $invalid }
}
$missingObservations = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
$missingObservations.Observations.psobject.Properties.Remove('Service')
Assert-Throws 'Missing required observation section' { Assert-ScenarioEvidenceContract $missingObservations }
$missingDiagnosis = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
$missingDiagnosis.Diagnosis.psobject.Properties.Remove('Identifier')
Assert-Throws 'Missing diagnosis identifier' { Assert-ScenarioEvidenceContract $missingDiagnosis }
$wrongBoolean = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
$wrongBoolean.Observations.Workload.Ready = 'false'
Assert-Throws 'Invalid boolean type' { Assert-ScenarioEvidenceContract $wrongBoolean }
$wrongCount = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
$wrongCount.Observations.Service.ReadyEndpointCount = '0'
Assert-Throws 'Invalid count type' { Assert-ScenarioEvidenceContract $wrongCount }
$wrongVersion = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
$wrongVersion.SchemaVersion = 2
Assert-Throws 'Unsupported schema version' { Assert-ScenarioEvidenceContract $wrongVersion }
$unknownDiagnosis = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
$unknownDiagnosis.Diagnosis.Identifier = 'unknown_root_cause'
Assert-Throws 'Unknown diagnosis identifier' { Assert-ScenarioEvidenceContract $unknownDiagnosis }
$sensitiveField = (ConvertTo-ScenarioEvidenceJson $readiness) | ConvertFrom-Json -DateKind String
$sensitiveField | Add-Member -NotePropertyName Credential -NotePropertyValue 'must-not-serialize'
Assert-Throws 'Unknown sensitive field' { Assert-ScenarioEvidenceContract $sensitiveField }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "platform-breakfix-evidence-tests-$([guid]::NewGuid().ToString('N'))"
try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    $path = Write-ScenarioEvidence -Evidence $selector -RepositoryRoot $testRoot
    $loaded = Read-ScenarioEvidence $path
    if ($loaded.Scenario -cne 'service-selector-mismatch') { throw 'Artifact read returned the wrong scenario.' }
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'Evidence artifact unexpectedly contains a UTF-8 BOM.' }
    Set-Content -LiteralPath $path -Value '{bad json' -Encoding utf8
    Assert-Throws 'Malformed JSON' { Read-ScenarioEvidence $path }
} finally { if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force } }
Write-Host 'PASS: UTF-8 artifact write/read and malformed JSON behavior are deterministic.' -ForegroundColor Green

$json = ConvertTo-ScenarioEvidenceJson $selector
foreach ($sensitive in @('kubeconfig','token','credential','password','clientSecret','accessKey')) {
    if ($json -match [regex]::Escape($sensitive)) { throw "Evidence contains prohibited sensitive field '$sensitive'." }
}
Write-Host 'PASS: Contract output contains no sensitive fields.' -ForegroundColor Green

if (-not $readiness.Observations.Connectivity.DnsSuccess -or $readiness.Observations.Connectivity.HttpSuccess -or $readiness.Observations.Service.ReadyEndpointCount -ne 0 -or
    -not $selector.Observations.Connectivity.DnsSuccess -or $selector.Observations.Connectivity.HttpSuccess -or $selector.Observations.Service.ReadyEndpointCount -ne 0) { throw 'Same-symptom comparison failed.' }
if ($readiness.Observations.Workload.Ready -or -not $readiness.Observations.Service.SelectorMatchesDestinationLabel -or $readiness.Diagnosis.Identifier -cne 'readiness_probe_failure') { throw 'Readiness diagnostic facts are incorrect.' }
if (-not $selector.Observations.Workload.Ready -or $selector.Observations.Service.SelectorMatchesDestinationLabel -or $selector.Diagnosis.Identifier -cne 'service_selector_mismatch') { throw 'Selector diagnostic facts are incorrect.' }
Write-Host 'PASS: Same external symptoms remain distinguishable by readiness, selector alignment, and stable diagnosis.' -ForegroundColor Green

$inspectExpectations = @{
    'readiness-probe-failure' = @("-Ready `$false", "-SelectorMatches `$true", "-DiagnosisIdentifier 'readiness_probe_failure'")
    'service-selector-mismatch' = @("-Ready `$true", "-SelectorMatches `$false", "-DiagnosisIdentifier 'service_selector_mismatch'")
}
foreach ($scenario in $inspectExpectations.Keys) {
    $inspect = Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot "scenarios/$scenario/Inspect.ps1")
    if ($inspect -notmatch 'Write-ScenarioEvidence' -or $inspect -notmatch 'Structured evidence:') { throw "$scenario Inspect does not preserve human output and add structured evidence." }
    foreach ($expected in $inspectExpectations[$scenario]) { if (-not $inspect.Contains($expected)) { throw "$scenario Inspect is missing production evidence fact: $expected" } }
}
Write-Host 'PASS: Both Inspect hooks retain human output and emit through the generic helper.' -ForegroundColor Green
Write-Host 'PASS: Scenario evidence contract tests completed without Kubernetes or Azure access.' -ForegroundColor Green
