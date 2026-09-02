[CmdletBinding()]
param(
    [string] $TofuPath = 'tofu',
    [string] $PlanPath
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$infrastructureRoot = Join-Path $repositoryRoot 'infrastructure/eks'
if ([string]::IsNullOrWhiteSpace($PlanPath)) { $PlanPath = Join-Path $repositoryRoot '.runtime/eks/lab.tfplan' }
$PlanPath = [IO.Path]::GetFullPath($PlanPath)
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "Saved EKS plan does not exist: $PlanPath" }
& $TofuPath "-chdir=$infrastructureRoot" apply $PlanPath
if ($LASTEXITCODE -ne 0) { throw 'EKS saved-plan apply failed.' }