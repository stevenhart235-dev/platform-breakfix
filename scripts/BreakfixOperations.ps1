Set-StrictMode -Version Latest

$script:BreakfixRepositoryRoot = Split-Path -Parent $PSScriptRoot
$script:BreakfixOperationContractVersion = 1
$script:BreakfixOperationSets = @{
    1 = @('list_profiles', 'list_scenarios', 'read_evidence', 'diagnose_evidence', 'get_lab_status')
    2 = @('list_profiles', 'list_scenarios', 'read_evidence', 'diagnose_evidence', 'get_lab_status', 'get_lab_health')
}
$script:BreakfixPublicOperations = @($script:BreakfixOperationSets[1])
$script:BreakfixErrorCodes = @(
    'INVALID_ARGUMENT',
    'NOT_FOUND',
    'INVALID_EVIDENCE',
    'DIAGNOSIS_FAILED',
    'PROVIDER_UNSUPPORTED',
    'LAB_STATE_UNAVAILABLE',
    'LAB_NOT_ACTIVE',
    'INTERNAL_ERROR'
)

function New-BreakfixOperationException {
    param(
        [Parameter(Mandatory)][string] $Code,
        [Parameter(Mandatory)][string] $Message
    )
    $exception = [InvalidOperationException]::new($Message)
    $exception.Data['BreakfixErrorCode'] = $Code
    $exception
}

function Assert-BreakfixOperationResult {
    param([Parameter(Mandatory)] $Result)
    $fields = @($Result.psobject.Properties.Name)
    $required = @('ContractVersion', 'Operation', 'Success', 'Data', 'Error')
    $missing = @($required | Where-Object { $_ -notin $fields })
    $unknown = @($fields | Where-Object { $_ -notin $required })
    if ($missing.Count -or $unknown.Count) { throw 'Breakfix operation result has an invalid envelope.' }
    if ($Result.ContractVersion -isnot [int] -or -not $script:BreakfixOperationSets.ContainsKey($Result.ContractVersion)) { throw 'Breakfix operation result has an invalid ContractVersion.' }
    if ($Result.Operation -isnot [string] -or $Result.Operation -cnotin $script:BreakfixOperationSets[$Result.ContractVersion]) { throw 'Breakfix operation result has an invalid Operation.' }
    if ($Result.Success -isnot [bool]) { throw 'Breakfix operation result Success must be boolean.' }
    if ($Result.Success) {
        if ($null -eq $Result.Data -or $null -ne $Result.Error) { throw 'Successful breakfix operation results require Data and prohibit Error.' }
    }
    else {
        if ($null -ne $Result.Data -or $null -eq $Result.Error) { throw 'Failed breakfix operation results require Error and prohibit Data.' }
        $errorFields = @($Result.Error.psobject.Properties.Name)
        if (@(Compare-Object ($errorFields | Sort-Object) @('Code', 'Message')).Count -ne 0) { throw 'Breakfix operation Error has an invalid shape.' }
        if ($Result.Error.Code -cnotin $script:BreakfixErrorCodes) { throw 'Breakfix operation Error has an unsupported code.' }
        if ($Result.Error.Message -isnot [string] -or [string]::IsNullOrWhiteSpace($Result.Error.Message)) { throw 'Breakfix operation Error requires a message.' }
    }
    $Result
}

function New-BreakfixSuccessResult {
    param([Parameter(Mandatory)][string] $Operation, [Parameter(Mandatory)] $Data, [ValidateSet(1, 2)][int] $ContractVersion = 1)
    Assert-BreakfixOperationResult ([pscustomobject][ordered]@{
        ContractVersion = $ContractVersion
        Operation = $Operation
        Success = $true
        Data = $Data
        Error = $null
    })
}

function New-BreakfixFailureResult {
    param(
        [Parameter(Mandatory)][string] $Operation,
        [Parameter(Mandatory)][string] $Code,
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet(1, 2)][int] $ContractVersion = 1
    )
    Assert-BreakfixOperationResult ([pscustomobject][ordered]@{
        ContractVersion = $ContractVersion
        Operation = $Operation
        Success = $false
        Data = $null
        Error = [pscustomobject][ordered]@{ Code = $Code; Message = $Message }
    })
}

function Assert-BreakfixOperationArguments {
    param([hashtable] $Arguments, [string[]] $Allowed)
    if ($null -eq $Arguments) { return }
    $unknown = @($Arguments.Keys | Where-Object { $_ -notin $Allowed })
    if ($unknown.Count) { throw (New-BreakfixOperationException 'INVALID_ARGUMENT' "Unsupported argument(s): $($unknown -join ', ').") }
}

function Test-BreakfixCatalogName {
    param([string] $Name)
    -not [string]::IsNullOrWhiteSpace($Name) -and $Name -cmatch '^[a-z][a-z0-9-]*$'
}

function Get-BreakfixProfiles {
    param([Parameter(Mandatory)][string] $RepositoryRoot, [AllowNull()][string] $Provider)
    $knownProviders = @('aks', 'eks')
    if ($Provider -and $Provider -cnotin $knownProviders) { throw (New-BreakfixOperationException 'PROVIDER_UNSUPPORTED' "Provider '$Provider' is unsupported.") }

    $profiles = @()
    if (-not $Provider -or $Provider -ceq 'aks') {
        $providerRoot = Join-Path $RepositoryRoot 'providers/azure/aks'
        $profilesRoot = Join-Path $providerRoot 'profiles'
        . (Join-Path $providerRoot 'scripts/Profile-Aks.ps1')
        foreach ($manifestPath in @(Get-ChildItem -LiteralPath $profilesRoot -Filter 'profile.psd1' -File -Recurse | Sort-Object FullName)) {
            $name = $manifestPath.Directory.Name
            $resolved = Resolve-AksProfile -Provider 'aks' -ProfileName $name -ProfilesRoot $profilesRoot
            $profiles += [pscustomobject][ordered]@{ Name = $resolved.Name; Provider = $resolved.Provider }
        }
    }
    [pscustomobject][ordered]@{ Profiles = @($profiles | Sort-Object Provider, Name) }
}

function Get-BreakfixScenarios {
    param([Parameter(Mandatory)][string] $RepositoryRoot)
    $scenariosRoot = Join-Path $RepositoryRoot 'scenarios'
    . (Join-Path $RepositoryRoot 'scripts/Scenario.ps1')
    $scenarios = @()
    foreach ($manifestPath in @(Get-ChildItem -LiteralPath $scenariosRoot -Filter 'scenario.psd1' -File -Recurse | Sort-Object FullName)) {
        $name = $manifestPath.Directory.Name
        $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath.FullName
        foreach ($provider in @($manifest.SupportedProviders)) {
            foreach ($profile in @($manifest.SupportedProfiles)) {
                Resolve-LabScenario -Provider $provider -ProfileName $profile -ScenarioName $name -ScenariosRoot $scenariosRoot | Out-Null
            }
        }
        $scenarios += [pscustomobject][ordered]@{
            Name = [string]$manifest.Name
            Description = [string]$manifest.Description
            SupportedProviders = @($manifest.SupportedProviders | Sort-Object)
            SupportedProfiles = @($manifest.SupportedProfiles | Sort-Object)
        }
    }
    [pscustomobject][ordered]@{ Scenarios = @($scenarios | Sort-Object Name) }
}

function Resolve-BreakfixEvidencePath {
    param([Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][string] $Scenario)
    if (-not (Test-BreakfixCatalogName $Scenario)) { throw (New-BreakfixOperationException 'INVALID_ARGUMENT' 'Evidence identifier must be a canonical scenario name.') }
    $scenarioManifest = Join-Path $RepositoryRoot "scenarios/$Scenario/scenario.psd1"
    if (-not (Test-Path -LiteralPath $scenarioManifest -PathType Leaf)) { throw (New-BreakfixOperationException 'INVALID_ARGUMENT' "Scenario '$Scenario' is not an active scenario.") }
    Join-Path $RepositoryRoot ".runtime/scenario-evidence/$Scenario.json"
}

function Get-BreakfixEvidence {
    param([Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][string] $Scenario)
    $path = Resolve-BreakfixEvidencePath -RepositoryRoot $RepositoryRoot -Scenario $Scenario
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (New-BreakfixOperationException 'NOT_FOUND' "Evidence for scenario '$Scenario' was not found.") }
    . (Join-Path $RepositoryRoot 'scripts/ScenarioEvidence.ps1')
    try {
        $evidence = Read-ScenarioEvidence -Path $path
        if ($evidence.Scenario -cne $Scenario) { throw 'Evidence scenario identity does not match its bounded artifact identity.' }
        $evidence
    }
    catch { throw (New-BreakfixOperationException 'INVALID_EVIDENCE' "Evidence for scenario '$Scenario' is malformed or violates Evidence Contract v1.") }
}

function Get-BreakfixDiagnosis {
    param([Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][string] $Scenario)
    $evidence = Get-BreakfixEvidence -RepositoryRoot $RepositoryRoot -Scenario $Scenario
    . (Join-Path $RepositoryRoot 'scripts/ScenarioEvidence.ps1')
    . (Join-Path $RepositoryRoot 'scripts/ScenarioDiagnosis.ps1')
    try {
        $diagnosis = Resolve-ScenarioDiagnosis -Observations $evidence.Observations
        [pscustomobject][ordered]@{ Identifier = $diagnosis.Identifier; Summary = $diagnosis.Summary }
    }
    catch { throw (New-BreakfixOperationException 'DIAGNOSIS_FAILED' 'Evidence did not produce exactly one supported diagnosis.') }
}

$script:BreakfixStatusReaders = @{
    aks = {
        param([string] $RepositoryRoot)
        . (Join-Path $RepositoryRoot 'providers/azure/aks/scripts/Lab-Aks.ps1')
        Get-AksLabStatus
    }
}
$script:BreakfixHealthReaders = @{
    aks = {
        param([string] $RepositoryRoot, [string] $Profile)
        . (Join-Path $RepositoryRoot 'scripts/LabHealth.ps1')
        Get-AksLabHealth -Profile $Profile
    }
}

function ConvertTo-BreakfixTimestamp {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try { ([datetimeoffset]$Value).ToUniversalTime().ToString('o') }
    catch { return $null }
}

function Get-BreakfixLabStatus {
    param([Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][string] $Provider)
    if ($Provider -cne 'aks') {
        throw (New-BreakfixOperationException 'PROVIDER_UNSUPPORTED' "Read-only lab status is not available for provider '$Provider'.")
    }
    try { $native = & $script:BreakfixStatusReaders.aks $RepositoryRoot }
    catch { throw (New-BreakfixOperationException 'LAB_STATE_UNAVAILABLE' "Lab status is currently unavailable for provider '$Provider'.") }
    if ($null -eq $native -or -not ($native.psobject.Properties.Name -contains 'State')) {
        throw (New-BreakfixOperationException 'LAB_STATE_UNAVAILABLE' "Lab status is currently unavailable for provider '$Provider'.")
    }
    $state = if ([string]$native.State -cin @('NO LAB', 'NO_LAB')) { 'NO_LAB' } elseif ([string]$native.State -cin @('ACTIVE', 'STALE')) { [string]$native.State } else { 'UNKNOWN' }
    $profile = if ($native.psobject.Properties.Name -contains 'Profile' -and -not [string]::IsNullOrWhiteSpace([string]$native.Profile)) { [string]$native.Profile } else { $null }
    $createdAt = if ($native.psobject.Properties.Name -contains 'CreatedAt') { ConvertTo-BreakfixTimestamp $native.CreatedAt } else { $null }
    $expiresAt = if ($native.psobject.Properties.Name -contains 'ExpiresAt') { ConvertTo-BreakfixTimestamp $native.ExpiresAt } else { $null }
    if ($state -cin @('ACTIVE', 'STALE') -and ($null -eq $createdAt -or $null -eq $expiresAt)) { $state = 'UNKNOWN' }
    [pscustomobject][ordered]@{
        Provider = 'aks'
        State = $state
        Profile = $profile
        CreatedAt = $createdAt
        ExpiresAt = $expiresAt
        ConnectionState = 'UNKNOWN'
    }
}

function Get-BreakfixLabHealth {
    param([Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][string] $Provider)
    if ($Provider -cne 'aks') {
        throw (New-BreakfixOperationException 'PROVIDER_UNSUPPORTED' "Passive lab health is not available for provider '$Provider'.")
    }
    $status = Get-BreakfixLabStatus -RepositoryRoot $RepositoryRoot -Provider $Provider
    if ($status.State -cne 'ACTIVE' -or [string]::IsNullOrWhiteSpace([string]$status.Profile)) {
        throw (New-BreakfixOperationException 'LAB_NOT_ACTIVE' "Lab health requires an observable active lab for provider '$Provider'.")
    }
    try {
        . (Join-Path $RepositoryRoot 'scripts/LabHealth.ps1')
        $health = & $script:BreakfixHealthReaders.aks $RepositoryRoot $status.Profile
        Assert-LabHealthContract $health | Out-Null
        $health
    }
    catch {
        throw (New-BreakfixOperationException 'LAB_STATE_UNAVAILABLE' "Lab health is currently unavailable for provider '$Provider'.")
    }
}

function Invoke-BreakfixOperation {
    param(
        [Parameter(Mandatory)][string] $Operation,
        [hashtable] $Arguments = @{},
        [ValidateSet(1, 2)][int] $ContractVersion = 1
    )
    $RepositoryRoot = $script:BreakfixRepositoryRoot
    $operations = $script:BreakfixOperationSets[$ContractVersion]
    if ($Operation -cnotin $operations) {
        return [pscustomobject][ordered]@{
            ContractVersion = $ContractVersion; Operation = $Operation; Success = $false; Data = $null
            Error = [pscustomobject][ordered]@{ Code = 'INVALID_ARGUMENT'; Message = "Unknown breakfix operation '$Operation'." }
        }
    }
    try {
        $data = switch ($Operation) {
            'list_profiles' {
                Assert-BreakfixOperationArguments $Arguments @('Provider')
                $provider = if ($Arguments.ContainsKey('Provider')) { [string]$Arguments.Provider } else { $null }
                if ($Arguments.ContainsKey('Provider') -and [string]::IsNullOrWhiteSpace($provider)) { throw (New-BreakfixOperationException 'INVALID_ARGUMENT' 'Provider must not be empty.') }
                Get-BreakfixProfiles -RepositoryRoot $RepositoryRoot -Provider $provider
            }
            'list_scenarios' {
                Assert-BreakfixOperationArguments $Arguments @()
                Get-BreakfixScenarios -RepositoryRoot $RepositoryRoot
            }
            'read_evidence' {
                Assert-BreakfixOperationArguments $Arguments @('Scenario')
                if (-not $Arguments.ContainsKey('Scenario')) { throw (New-BreakfixOperationException 'INVALID_ARGUMENT' 'Scenario is required.') }
                Get-BreakfixEvidence -RepositoryRoot $RepositoryRoot -Scenario ([string]$Arguments.Scenario)
            }
            'diagnose_evidence' {
                Assert-BreakfixOperationArguments $Arguments @('Scenario')
                if (-not $Arguments.ContainsKey('Scenario')) { throw (New-BreakfixOperationException 'INVALID_ARGUMENT' 'Scenario is required.') }
                Get-BreakfixDiagnosis -RepositoryRoot $RepositoryRoot -Scenario ([string]$Arguments.Scenario)
            }
            'get_lab_status' {
                Assert-BreakfixOperationArguments $Arguments @('Provider')
                if (-not $Arguments.ContainsKey('Provider') -or [string]::IsNullOrWhiteSpace([string]$Arguments.Provider)) { throw (New-BreakfixOperationException 'INVALID_ARGUMENT' 'Provider is required.') }
                Get-BreakfixLabStatus -RepositoryRoot $RepositoryRoot -Provider ([string]$Arguments.Provider)
            }
            'get_lab_health' {
                Assert-BreakfixOperationArguments $Arguments @('Provider')
                if (-not $Arguments.ContainsKey('Provider') -or [string]::IsNullOrWhiteSpace([string]$Arguments.Provider)) { throw (New-BreakfixOperationException 'INVALID_ARGUMENT' 'Provider is required.') }
                Get-BreakfixLabHealth -RepositoryRoot $RepositoryRoot -Provider ([string]$Arguments.Provider)
            }
        }
        New-BreakfixSuccessResult -Operation $Operation -Data $data -ContractVersion $ContractVersion
    }
    catch {
        $code = if ($_.Exception.Data.Contains('BreakfixErrorCode')) { [string]$_.Exception.Data['BreakfixErrorCode'] } else { 'INTERNAL_ERROR' }
        $message = if ($code -eq 'INTERNAL_ERROR') { 'The breakfix operation could not be completed.' } else { $_.Exception.Message }
        New-BreakfixFailureResult -Operation $Operation -Code $code -Message $message -ContractVersion $ContractVersion
    }
}
