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

function Assert-ScenarioObservations {
    param([Parameter(Mandatory)] $Observations)
    Assert-ScenarioEvidenceKeys $Observations @('Workload','Service','Connectivity') 'Observations'
    $workload = $Observations.Workload
    Assert-ScenarioEvidenceKeys $workload @('DestinationPodExists','Phase','ContainerRunning','Ready','ReadinessProbePath','DestinationLabels') 'Observations.Workload'
    Assert-ScenarioEvidenceBoolean $workload.DestinationPodExists 'Observations.Workload.DestinationPodExists'
    Assert-ScenarioEvidenceString $workload.Phase 'Observations.Workload.Phase'
    Assert-ScenarioEvidenceBoolean $workload.ContainerRunning 'Observations.Workload.ContainerRunning'
    Assert-ScenarioEvidenceBoolean $workload.Ready 'Observations.Workload.Ready'
    Assert-ScenarioEvidenceString $workload.ReadinessProbePath 'Observations.Workload.ReadinessProbePath'
    Assert-ScenarioEvidenceKeys $workload.DestinationLabels @('app') 'Observations.Workload.DestinationLabels'
    Assert-ScenarioEvidenceString $workload.DestinationLabels.app 'Observations.Workload.DestinationLabels.app'

    $service = $Observations.Service
    Assert-ScenarioEvidenceKeys $service @('Exists','Selector','SelectorMatchesDestinationLabel','ReadyEndpointCount') 'Observations.Service'
    Assert-ScenarioEvidenceBoolean $service.Exists 'Observations.Service.Exists'
    Assert-ScenarioEvidenceKeys $service.Selector @('app') 'Observations.Service.Selector'
    Assert-ScenarioEvidenceString $service.Selector.app 'Observations.Service.Selector.app'
    Assert-ScenarioEvidenceBoolean $service.SelectorMatchesDestinationLabel 'Observations.Service.SelectorMatchesDestinationLabel'
    if (-not (Test-ScenarioEvidenceInteger $service.ReadyEndpointCount) -or $service.ReadyEndpointCount -lt 0) { throw 'Observations.Service.ReadyEndpointCount must be a non-negative integer.' }
    $selectorActuallyMatches = $service.Selector.app -ceq $workload.DestinationLabels.app
    if ($service.SelectorMatchesDestinationLabel -ne $selectorActuallyMatches) { throw 'Observations.Service.SelectorMatchesDestinationLabel is inconsistent with the selector and destination label.' }

    $connectivity = $Observations.Connectivity
    Assert-ScenarioEvidenceKeys $connectivity @('DnsSuccess','HttpSuccess','HttpStatus') 'Observations.Connectivity'
    Assert-ScenarioEvidenceBoolean $connectivity.DnsSuccess 'Observations.Connectivity.DnsSuccess'
    Assert-ScenarioEvidenceBoolean $connectivity.HttpSuccess 'Observations.Connectivity.HttpSuccess'
    if ($null -ne $connectivity.HttpStatus -and (-not (Test-ScenarioEvidenceInteger $connectivity.HttpStatus) -or $connectivity.HttpStatus -lt 100 -or $connectivity.HttpStatus -gt 599)) { throw 'Observations.Connectivity.HttpStatus must be null or an integer from 100 through 599.' }
    if ($connectivity.HttpSuccess -and $connectivity.HttpStatus -ne 200) { throw 'Observations.Connectivity.HttpSuccess=true requires HttpStatus=200.' }
    if (-not $connectivity.HttpSuccess -and $connectivity.HttpStatus -eq 200) { throw 'Observations.Connectivity.HttpSuccess=false is inconsistent with HttpStatus=200.' }
    $Observations
}

function Assert-ScenarioEvidenceContract {
    param([Parameter(Mandatory)] $Evidence)
    Assert-ScenarioEvidenceKeys $Evidence @('SchemaVersion','Scenario','Provider','Profile','TimestampUtc','Status','Observations','Diagnosis') 'Evidence'
    if (-not (Test-ScenarioEvidenceInteger $Evidence.SchemaVersion) -or $Evidence.SchemaVersion -ne $script:ScenarioEvidenceSchemaVersion) { throw "Evidence SchemaVersion '$($Evidence.SchemaVersion)' is unsupported; expected $script:ScenarioEvidenceSchemaVersion." }
    foreach ($field in @('Scenario','Provider','Profile','TimestampUtc','Status')) { Assert-ScenarioEvidenceString $Evidence.$field "Evidence.$field" }
    $parsedTimestamp = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParseExact($Evidence.TimestampUtc, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedTimestamp)) { throw 'Evidence.TimestampUtc must use the round-trip ISO 8601 format.' }
    if ($Evidence.Status -cne 'expected_failure_confirmed') { throw "Evidence.Status '$($Evidence.Status)' is unsupported." }
    Assert-ScenarioObservations $Evidence.Observations | Out-Null
    Assert-ScenarioEvidenceKeys $Evidence.Diagnosis @('Identifier','Summary') 'Evidence.Diagnosis'
    Assert-ScenarioEvidenceString $Evidence.Diagnosis.Identifier 'Evidence.Diagnosis.Identifier'
    if ($Evidence.Diagnosis.Identifier -cnotin $script:ScenarioEvidenceDiagnosticIdentifiers) { throw "Unknown evidence diagnosis identifier '$($Evidence.Diagnosis.Identifier)'." }
    Assert-ScenarioEvidenceString $Evidence.Diagnosis.Summary 'Evidence.Diagnosis.Summary'
    $Evidence
}

function New-ScenarioObservations {
    param(
        [bool] $DestinationPodExists, [string] $Phase, [bool] $ContainerRunning,
        [bool] $Ready, [string] $ReadinessProbePath, [string] $DestinationLabel,
        [bool] $ServiceExists, [string] $Selector, [bool] $SelectorMatches,
        [int] $ReadyEndpointCount, [bool] $DnsSuccess, [bool] $HttpSuccess,
        $HttpStatus
    )
    $observations = [pscustomobject][ordered]@{
        Workload = [pscustomobject][ordered]@{ DestinationPodExists=$DestinationPodExists; Phase=$Phase; ContainerRunning=$ContainerRunning; Ready=$Ready; ReadinessProbePath=$ReadinessProbePath; DestinationLabels=[pscustomobject][ordered]@{ app=$DestinationLabel } }
        Service = [pscustomobject][ordered]@{ Exists=$ServiceExists; Selector=[pscustomobject][ordered]@{ app=$Selector }; SelectorMatchesDestinationLabel=$SelectorMatches; ReadyEndpointCount=$ReadyEndpointCount }
        Connectivity = [pscustomobject][ordered]@{ DnsSuccess=$DnsSuccess; HttpSuccess=$HttpSuccess; HttpStatus=$HttpStatus }
    }
    Assert-ScenarioObservations $observations
}

function New-ScenarioEvidenceDocument {
    param(
        [string] $Scenario, [string] $Provider, [string] $Profile,
        [Parameter(Mandatory)] $Observations, [Parameter(Mandatory)] $Diagnosis,
        [datetimeoffset] $Timestamp = [datetimeoffset]::UtcNow
    )
    Assert-ScenarioObservations $Observations | Out-Null
    $evidence = [pscustomobject][ordered]@{
        SchemaVersion = 1; Scenario = $Scenario; Provider = $Provider; Profile = $Profile
        TimestampUtc = $Timestamp.ToString('o'); Status = 'expected_failure_confirmed'
        Observations = $Observations; Diagnosis = $Diagnosis
    }
    Assert-ScenarioEvidenceContract $evidence
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
