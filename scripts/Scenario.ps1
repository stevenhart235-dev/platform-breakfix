Set-StrictMode -Version Latest

function Test-ScenarioPathWithinRoot {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Root)
    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
    $resolvedPath.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $resolvedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-LabScenario {
    param(
        [Parameter(Mandatory)][string] $Provider,
        [Parameter(Mandatory)][string] $ProfileName,
        [AllowEmptyString()][string] $ScenarioName,
        [Parameter(Mandatory)][string] $ScenariosRoot
    )
    if ([string]::IsNullOrWhiteSpace($ScenarioName)) {
        return [pscustomobject]@{ Name = 'none'; IsNone = $true; Provider = $Provider; Profile = $ProfileName }
    }
    if ($ScenarioName -notmatch '^[a-z][a-z0-9-]*$') { throw "Invalid scenario name '$ScenarioName'." }
    $scenarioDirectory = Join-Path $ScenariosRoot $ScenarioName
    $manifestPath = Join-Path $scenarioDirectory 'scenario.psd1'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Unknown scenario '$ScenarioName'." }
    if (-not (Test-ScenarioPathWithinRoot -Path $manifestPath -Root $ScenariosRoot)) { throw "Scenario manifest resolves outside the scenario root: '$manifestPath'." }
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    $hookKeys = @('Inject', 'ValidateBroken', 'Inspect', 'Repair', 'ValidateRecovered', 'Cleanup')
    $allowedKeys = @('SchemaVersion', 'Name', 'SupportedProviders', 'SupportedProfiles', 'Description', 'KubernetesComposition', 'Hooks')
    $unknownKeys = @($manifest.Keys | Where-Object { $_ -notin $allowedKeys })
    if ($unknownKeys.Count) { throw "Scenario '$ScenarioName' contains unknown manifest keys: $($unknownKeys -join ', ')." }
    foreach ($key in $allowedKeys) {
        if (-not $manifest.ContainsKey($key)) { throw "Scenario '$ScenarioName' is missing required manifest key '$key'." }
    }
    if ($manifest.SchemaVersion -ne 1) { throw "Scenario '$ScenarioName' has unsupported SchemaVersion '$($manifest.SchemaVersion)'; expected 1." }
    if ($manifest.Name -cne $ScenarioName) { throw "Scenario manifest Name '$($manifest.Name)' does not match requested scenario '$ScenarioName'." }
    if ($manifest.SupportedProviders -isnot [object[]] -or @($manifest.SupportedProviders).Count -eq 0) { throw "Scenario '$ScenarioName' SupportedProviders must be a non-empty array." }
    if ($manifest.SupportedProfiles -isnot [object[]] -or @($manifest.SupportedProfiles).Count -eq 0) { throw "Scenario '$ScenarioName' SupportedProfiles must be a non-empty array." }
    if ($Provider -cnotin @($manifest.SupportedProviders)) { throw "Scenario '$ScenarioName' does not support provider '$Provider'." }
    if ($ProfileName -cnotin @($manifest.SupportedProfiles)) { throw "Scenario '$ScenarioName' does not support profile '$ProfileName'." }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.Description)) { throw "Scenario '$ScenarioName' Description must not be empty." }
    if ($manifest.Hooks -isnot [hashtable]) { throw "Scenario '$ScenarioName' Hooks must be a hashtable." }
    $unknownHooks = @($manifest.Hooks.Keys | Where-Object { $_ -notin $hookKeys })
    if ($unknownHooks.Count) { throw "Scenario '$ScenarioName' contains unknown hooks: $($unknownHooks -join ', ')." }
    foreach ($hook in $hookKeys) {
        if (-not $manifest.Hooks.ContainsKey($hook) -or [string]::IsNullOrWhiteSpace([string]$manifest.Hooks[$hook])) { throw "Scenario '$ScenarioName' is missing required hook '$hook'." }
    }
    $composition = Join-Path $scenarioDirectory ([string]$manifest.KubernetesComposition)
    if (-not (Test-Path -LiteralPath $composition -PathType Container) -or -not (Test-ScenarioPathWithinRoot -Path $composition -Root $scenarioDirectory)) {
        throw "Scenario '$ScenarioName' KubernetesComposition must reference a directory beneath its scenario directory."
    }
    $resolvedHooks = @{}
    foreach ($hook in $hookKeys) {
        $hookPath = Join-Path $scenarioDirectory ([string]$manifest.Hooks[$hook])
        if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf) -or [IO.Path]::GetExtension($hookPath) -cne '.ps1' -or
            -not (Test-ScenarioPathWithinRoot -Path $hookPath -Root $scenarioDirectory)) {
            throw "Scenario '$ScenarioName' hook '$hook' must reference a PowerShell script beneath its scenario directory."
        }
        $resolvedHooks[$hook] = (Resolve-Path -LiteralPath $hookPath).Path
    }
    [pscustomobject]@{
        SchemaVersion = 1; Name = $ScenarioName; IsNone = $false
        Provider = $Provider; Profile = $ProfileName; Description = [string]$manifest.Description
        ScenarioDirectory = (Resolve-Path -LiteralPath $scenarioDirectory).Path
        KubernetesComposition = (Resolve-Path -LiteralPath $composition).Path
        Hooks = $resolvedHooks
    }
}

function Assert-AksSavedPlanScenario {
    param(
        [Parameter(Mandatory)][string] $MetadataPath,
        [Parameter(Mandatory)][string] $RequestedScenario
    )
    if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) { throw "Saved plan scenario metadata is missing; run plan for scenario '$RequestedScenario'." }
    $metadata = Get-Content -Raw -LiteralPath $MetadataPath | ConvertFrom-Json
    if (-not ($metadata.psobject.Properties.Name -contains 'Scenario')) { throw 'Saved plan metadata has no Scenario binding; run plan again.' }
    if ([string]$metadata.Scenario -cne $RequestedScenario) { throw "Saved plan scenario mismatch: requested '$RequestedScenario', planned '$($metadata.Scenario)'. Run plan again." }
}
