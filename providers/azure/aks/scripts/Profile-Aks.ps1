Set-StrictMode -Version Latest

# Provider-local AKS profile resolution.

function Test-AksPathWithinRoot {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Root)
    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $prefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
    return $resolvedPath.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase) -or $resolvedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-AksProfile {
    param([Parameter(Mandatory)][string] $Provider, [Parameter(Mandatory)][string] $ProfileName, [Parameter(Mandatory)][string] $ProfilesRoot)
    if ($ProfileName -notmatch '^[a-z][a-z0-9-]*$') { throw "Invalid AKS profile name '$ProfileName'." }
    $profileDirectory = Join-Path $ProfilesRoot $ProfileName
    $manifestPath = Join-Path $profileDirectory 'profile.psd1'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Unknown AKS profile '$ProfileName'." }
    if (-not (Test-AksPathWithinRoot -Path $manifestPath -Root $ProfilesRoot)) { throw "AKS profile manifest resolves outside the provider profile directory: '$manifestPath'." }
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    $allowedKeys = @('SchemaVersion', 'Name', 'Provider', 'InfrastructureInputs', 'BootstrapComposition', 'ValidationScript')
    $unknownKeys = @($manifest.Keys | Where-Object { $_ -notin $allowedKeys })
    if ($unknownKeys.Count -gt 0) { throw "Profile '$ProfileName' contains unknown manifest keys: $($unknownKeys -join ', ')." }
    foreach ($key in @('SchemaVersion', 'Name', 'Provider', 'InfrastructureInputs', 'BootstrapComposition')) {
        if (-not $manifest.ContainsKey($key)) { throw "Profile '$ProfileName' is missing required manifest key '$key'." }
    }
    if ($manifest.SchemaVersion -ne 1) { throw "Profile '$ProfileName' has unsupported SchemaVersion '$($manifest.SchemaVersion)'; expected 1." }
    if ($manifest.Name -cne $ProfileName) { throw "Profile manifest Name '$($manifest.Name)' does not match requested profile '$ProfileName'." }
    if ($manifest.Provider -cne $Provider) { throw "Profile '$ProfileName' belongs to provider '$($manifest.Provider)', not '$Provider'." }
    if ($manifest.InfrastructureInputs -isnot [hashtable]) { throw "Profile '$ProfileName' InfrastructureInputs must be a hashtable." }
    $allowedInputs = @('NetworkDataPlane', 'NodeVmSize', 'NodeCount')
    $unknownInputs = @($manifest.InfrastructureInputs.Keys | Where-Object { $_ -notin $allowedInputs })
    if ($unknownInputs.Count -gt 0) { throw "Profile '$ProfileName' contains unknown InfrastructureInputs: $($unknownInputs -join ', ')." }
    foreach ($inputName in $allowedInputs) {
        if (-not $manifest.InfrastructureInputs.ContainsKey($inputName)) { throw "Profile '$ProfileName' is missing InfrastructureInput '$inputName'." }
    }
    if ($manifest.InfrastructureInputs.NetworkDataPlane -notin @('azure', 'cilium')) { throw "Profile '$ProfileName' has unsupported NetworkDataPlane '$($manifest.InfrastructureInputs.NetworkDataPlane)'." }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.InfrastructureInputs.NodeVmSize)) { throw "Profile '$ProfileName' NodeVmSize must not be empty." }
    if ($manifest.InfrastructureInputs.NodeCount -isnot [int] -or $manifest.InfrastructureInputs.NodeCount -lt 1) { throw "Profile '$ProfileName' NodeCount must be a positive integer." }
    $bootstrapPath = Join-Path $profileDirectory ([string]$manifest.BootstrapComposition)
    if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Container) -or -not (Test-AksPathWithinRoot -Path $bootstrapPath -Root $profileDirectory)) {
        throw "Profile '$ProfileName' BootstrapComposition must reference a directory beneath its profile directory."
    }
    $validationPath = $null
    if ($manifest.ContainsKey('ValidationScript') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.ValidationScript)) {
        $validationPath = Join-Path $profileDirectory ([string]$manifest.ValidationScript)
        if (-not (Test-Path -LiteralPath $validationPath -PathType Leaf) -or -not (Test-AksPathWithinRoot -Path $validationPath -Root $profileDirectory)) {
            throw "Profile '$ProfileName' ValidationScript must reference a file beneath its profile directory."
        }
    }
    [pscustomobject]@{
        SchemaVersion = 1; Name = $ProfileName; Provider = $Provider
        InfrastructureInputs = [hashtable]$manifest.InfrastructureInputs.Clone()
        ProfileDirectory = (Resolve-Path -LiteralPath $profileDirectory).Path
        BootstrapComposition = (Resolve-Path -LiteralPath $bootstrapPath).Path
        ValidationScript = if ($validationPath) { (Resolve-Path -LiteralPath $validationPath).Path } else { $null }
    }
}

function Assert-AksSavedPlanProfile {
    param(
        [Parameter(Mandatory)][string] $MetadataPath,
        [Parameter(Mandatory)][string] $PlanPath,
        [Parameter(Mandatory)][string] $RequestedProfile
    )
    if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) { throw "Saved plan profile metadata is missing; run plan for profile '$RequestedProfile'." }
    $metadata = Get-Content -Raw -LiteralPath $MetadataPath | ConvertFrom-Json
    if ($metadata.Profile -cne $RequestedProfile) { throw "Saved plan profile mismatch: requested '$RequestedProfile', planned '$($metadata.Profile)'. Run plan again." }
    if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "Saved plan '$PlanPath' is missing; run plan for profile '$RequestedProfile'." }
    $planSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PlanPath).Hash
    if ($metadata.PlanSha256 -cne $planSha256) { throw 'Saved plan hash does not match its profile metadata; run plan again.' }
}

function Assert-AksLiveLabProfile {
    param([Parameter(Mandatory)] $Status, [Parameter(Mandatory)][string] $RequestedProfile)
    if ($Status.State -eq 'NO LAB') { return }
    if (-not ($Status.psobject.Properties.Name -contains 'Profile') -or [string]::IsNullOrWhiteSpace([string]$Status.Profile)) { throw "Existing AKS lab has no Profile tag; requested profile is '$RequestedProfile'." }
    if ($Status.Profile -cne $RequestedProfile) { throw "Live AKS lab profile mismatch: requested '$RequestedProfile', detected '$($Status.Profile)'. Destroy and verify-clean before switching profiles." }
}
