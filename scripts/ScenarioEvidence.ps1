Set-StrictMode -Version Latest

$script:ScenarioEvidenceSchemaVersion = 1
$script:ScenarioEvidenceDiagnosticIdentifiers = @('readiness_probe_failure', 'service_selector_mismatch')

function Assert-ScenarioEvidenceKeys {
    param($InputObject, [string[]] $Required, [string] $Context)
    if ($null -eq $InputObject) { throw "$Context must be an object." }
    $actual = @($InputObject.psobject.Properties.Name)
    $missing = @($Required | Where-Object { $_ -notin $actual })
    $unknown = @($actual | Where-Object { $_ -notin $Required })
    if ($missing.Count) { throw "$Context is missing required field(s): $($missing -join ', ')." }
    if ($unknown.Count) { throw "$Context contains unknown field(s): $($unknown -join ', ')." }
}

function Assert-ScenarioEvidenceString {
    param($Value, [string] $Field)
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw "$Field must be a non-empty string." }
}

function Assert-ScenarioEvidenceBoolean {
    param($Value, [string] $Field)
    if ($Value -isnot [bool]) { throw "$Field must be a boolean." }
}

function Test-ScenarioEvidenceInteger {
    param($Value)
    $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

function Assert-ScenarioEvidenceContract {
    param([Parameter(Mandatory)] $Evidence)
    Assert-ScenarioEvidenceKeys $Evidence @('SchemaVersion','Scenario','Provider','Profile','TimestampUtc','Status','Observations','Diagnosis') 'Evidence'
    if (-not (Test-ScenarioEvidenceInteger $Evidence.SchemaVersion) -or $Evidence.SchemaVersion -ne $script:ScenarioEvidenceSchemaVersion) { throw "Evidence SchemaVersion '$($Evidence.SchemaVersion)' is unsupported; expected $script:ScenarioEvidenceSchemaVersion." }
    foreach ($field in @('Scenario','Provider','Profile','TimestampUtc','Status')) { Assert-ScenarioEvidenceString $Evidence.$field "Evidence.$field" }
    $parsedTimestamp = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParseExact($Evidence.TimestampUtc, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedTimestamp)) { throw 'Evidence.TimestampUtc must use the round-trip ISO 8601 format.' }
    if ($Evidence.Status -cne 'expected_failure_confirmed') { throw "Evidence.Status '$($Evidence.Status)' is unsupported." }

    Assert-ScenarioEvidenceKeys $Evidence.Observations @('Workload','Service','Connectivity') 'Evidence.Observations'
    $workload = $Evidence.Observations.Workload
    Assert-ScenarioEvidenceKeys $workload @('DestinationPodExists','Phase','ContainerRunning','Ready','ReadinessProbePath','DestinationLabels') 'Evidence.Observations.Workload'
    Assert-ScenarioEvidenceBoolean $workload.DestinationPodExists 'Evidence.Observations.Workload.DestinationPodExists'
    Assert-ScenarioEvidenceString $workload.Phase 'Evidence.Observations.Workload.Phase'
    Assert-ScenarioEvidenceBoolean $workload.ContainerRunning 'Evidence.Observations.Workload.ContainerRunning'
    Assert-ScenarioEvidenceBoolean $workload.Ready 'Evidence.Observations.Workload.Ready'
    Assert-ScenarioEvidenceString $workload.ReadinessProbePath 'Evidence.Observations.Workload.ReadinessProbePath'
    Assert-ScenarioEvidenceKeys $workload.DestinationLabels @('app') 'Evidence.Observations.Workload.DestinationLabels'
    Assert-ScenarioEvidenceString $workload.DestinationLabels.app 'Evidence.Observations.Workload.DestinationLabels.app'

    $service = $Evidence.Observations.Service
    Assert-ScenarioEvidenceKeys $service @('Exists','Selector','SelectorMatchesDestinationLabel','ReadyEndpointCount') 'Evidence.Observations.Service'
    Assert-ScenarioEvidenceBoolean $service.Exists 'Evidence.Observations.Service.Exists'
    Assert-ScenarioEvidenceKeys $service.Selector @('app') 'Evidence.Observations.Service.Selector'
    Assert-ScenarioEvidenceString $service.Selector.app 'Evidence.Observations.Service.Selector.app'
    Assert-ScenarioEvidenceBoolean $service.SelectorMatchesDestinationLabel 'Evidence.Observations.Service.SelectorMatchesDestinationLabel'
    if (-not (Test-ScenarioEvidenceInteger $service.ReadyEndpointCount) -or $service.ReadyEndpointCount -lt 0) { throw 'Evidence.Observations.Service.ReadyEndpointCount must be a non-negative integer.' }

    $connectivity = $Evidence.Observations.Connectivity
    Assert-ScenarioEvidenceKeys $connectivity @('DnsSuccess','HttpSuccess','HttpStatus') 'Evidence.Observations.Connectivity'
    Assert-ScenarioEvidenceBoolean $connectivity.DnsSuccess 'Evidence.Observations.Connectivity.DnsSuccess'
    Assert-ScenarioEvidenceBoolean $connectivity.HttpSuccess 'Evidence.Observations.Connectivity.HttpSuccess'
    if ($null -ne $connectivity.HttpStatus -and (-not (Test-ScenarioEvidenceInteger $connectivity.HttpStatus) -or $connectivity.HttpStatus -lt 100 -or $connectivity.HttpStatus -gt 599)) { throw 'Evidence.Observations.Connectivity.HttpStatus must be null or an integer from 100 through 599.' }

    Assert-ScenarioEvidenceKeys $Evidence.Diagnosis @('Identifier','Summary') 'Evidence.Diagnosis'
    Assert-ScenarioEvidenceString $Evidence.Diagnosis.Identifier 'Evidence.Diagnosis.Identifier'
    if ($Evidence.Diagnosis.Identifier -cnotin $script:ScenarioEvidenceDiagnosticIdentifiers) { throw "Unknown evidence diagnosis identifier '$($Evidence.Diagnosis.Identifier)'." }
    Assert-ScenarioEvidenceString $Evidence.Diagnosis.Summary 'Evidence.Diagnosis.Summary'
    $Evidence
}

function New-ScenarioEvidenceDocument {
    param(
        [string] $Scenario, [string] $Provider, [string] $Profile,
        [bool] $DestinationPodExists, [string] $Phase, [bool] $ContainerRunning,
        [bool] $Ready, [string] $ReadinessProbePath, [string] $DestinationLabel,
        [bool] $ServiceExists, [string] $Selector, [bool] $SelectorMatches,
        [int] $ReadyEndpointCount, [bool] $DnsSuccess, [bool] $HttpSuccess,
        $HttpStatus, [string] $DiagnosisIdentifier, [string] $DiagnosisSummary,
        [datetimeoffset] $Timestamp = [datetimeoffset]::UtcNow
    )
    [pscustomobject][ordered]@{
        SchemaVersion = 1; Scenario = $Scenario; Provider = $Provider; Profile = $Profile
        TimestampUtc = $Timestamp.ToString('o'); Status = 'expected_failure_confirmed'
        Observations = [pscustomobject][ordered]@{
            Workload = [pscustomobject][ordered]@{ DestinationPodExists=$DestinationPodExists; Phase=$Phase; ContainerRunning=$ContainerRunning; Ready=$Ready; ReadinessProbePath=$ReadinessProbePath; DestinationLabels=[pscustomobject][ordered]@{ app=$DestinationLabel } }
            Service = [pscustomobject][ordered]@{ Exists=$ServiceExists; Selector=[pscustomobject][ordered]@{ app=$Selector }; SelectorMatchesDestinationLabel=$SelectorMatches; ReadyEndpointCount=$ReadyEndpointCount }
            Connectivity = [pscustomobject][ordered]@{ DnsSuccess=$DnsSuccess; HttpSuccess=$HttpSuccess; HttpStatus=$HttpStatus }
        }
        Diagnosis = [pscustomobject][ordered]@{ Identifier=$DiagnosisIdentifier; Summary=$DiagnosisSummary }
    }
}

function ConvertTo-ScenarioEvidenceJson {
    param([Parameter(Mandatory)] $Evidence)
    $validated = Assert-ScenarioEvidenceContract $Evidence
    $validated | ConvertTo-Json -Depth 8
}

function Read-ScenarioEvidence {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Scenario evidence artifact '$Path' does not exist." }
    try { $evidence = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -DateKind String }
    catch { throw "Scenario evidence artifact '$Path' contains malformed JSON: $($_.Exception.Message)" }
    Assert-ScenarioEvidenceContract $evidence
}

function Write-ScenarioEvidence {
    param([Parameter(Mandatory)] $Evidence, [Parameter(Mandatory)][string] $RepositoryRoot)
    $json = ConvertTo-ScenarioEvidenceJson $Evidence
    $directory = Join-Path $RepositoryRoot '.runtime/scenario-evidence'
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $path = Join-Path $directory "$($Evidence.Scenario).json"
    [IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    (Resolve-Path -LiteralPath $path).Path
}
