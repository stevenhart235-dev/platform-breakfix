[CmdletBinding()]
param(
    [ValidatePattern('^(?:[1-9]|1[0-9]|2[0-4])$')]
    [string] $LifetimeHours = '4',
    [string] $TofuPath = 'tofu',
    [string] $PlanPath
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$infrastructureRoot = Join-Path $repositoryRoot 'infrastructure/eks'
. (Join-Path $PSScriptRoot 'EksLifecycleMetadata.ps1')
if ([string]::IsNullOrWhiteSpace($PlanPath)) { $PlanPath = Join-Path $repositoryRoot '.runtime/eks/lab.tfplan' }
$PlanPath = [IO.Path]::GetFullPath($PlanPath)
[IO.Directory]::CreateDirectory((Split-Path -Parent $PlanPath)) | Out-Null

$existingJson = & $TofuPath "-chdir=$infrastructureRoot" output -json eks_lifecycle_metadata 2>$null
$hasExisting = $LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($existingJson -join ''))
if ($hasExisting) {
    $metadata = Assert-EksLifecycleMetadata (($existingJson -join "`n") | ConvertFrom-Json -DateKind String)
    $created = [datetimeoffset]::ParseExact([string]$metadata.CreatedAt, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $expires = [datetimeoffset]::ParseExact([string]$metadata.ExpiresAt, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $existingHours = [int]($expires - $created).TotalHours
    if ($PSBoundParameters.ContainsKey('LifetimeHours') -and $LifetimeHours -ne $existingHours) {
        throw "LifetimeHours is creation-only; the existing EKS lifecycle is fixed at $existingHours hour(s)."
    }
    $LifetimeHours = [string]$existingHours
}

Write-Host "Planning EKS lifecycle with advisory lifetime $LifetimeHours hour(s)."
& $TofuPath "-chdir=$infrastructureRoot" plan "-out=$PlanPath" "-var=eks_lifetime_hours=$LifetimeHours"
if ($LASTEXITCODE -ne 0) { throw 'EKS OpenTofu plan failed.' }
Write-Host "Saved EKS plan: $PlanPath"