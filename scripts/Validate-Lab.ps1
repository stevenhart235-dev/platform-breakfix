[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('eks', 'aks')]
    [string] $Provider,

    [string] $ClusterName,
    [string] $CloudLocation,
    [int] $ExpectedNodeCount,
    [string] $ExpectedContext,
    [string] $ResourceGroup,
    [string] $ProfileName,
    [string] $ProfileValidationScript
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $RepositoryRoot 'validation/common/Validate-Kubernetes.ps1')

try {
    $requiredCommands = if ($Provider -eq 'eks') { @('aws', 'kubectl') } else { @('az', 'kubectl') }
    foreach ($commandName in $requiredCommands) {
        if (-not (Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue)) {
            Stop-ValidationFailure "'$commandName' was not found in PATH."
        }
    }

    switch ($Provider) {
        'eks' {
            if ([string]::IsNullOrWhiteSpace($ClusterName)) { $ClusterName = 'platform-breakfix' }
            if ([string]::IsNullOrWhiteSpace($CloudLocation)) { $CloudLocation = 'us-east-2' }
            if ($ExpectedNodeCount -le 0) { $ExpectedNodeCount = 2 }
            . (Join-Path $RepositoryRoot 'validation/providers/eks.ps1')
            $config = Get-EksValidationConfig `
                -ClusterName $ClusterName `
                -Region $CloudLocation `
                -ExpectedNodeCount $ExpectedNodeCount `
                -ExpectedContext $ExpectedContext

            $currentContext = Invoke-Kubectl -Arguments @('config', 'current-context') -Capture
            if ($currentContext.Trim() -ne $config.ExpectedContext) {
                Stop-ValidationFailure "Current context '$($currentContext.Trim())' does not match expected context '$($config.ExpectedContext)'."
            }
            Write-ValidationPass "Kubeconfig context is deterministic: $($config.ExpectedContext)."

            $storageManifest = Join-Path $RepositoryRoot 'validation/manifests/storage-smoke.yaml'
            $volumeHandle = Invoke-CommonKubernetesValidation `
                -ExpectedNodeCount $config.ExpectedNodeCount `
                -StorageManifest $storageManifest
            Invoke-EksValidation -Config $config -VolumeHandle $volumeHandle
        }
        'aks' {
            if ([string]::IsNullOrWhiteSpace($ClusterName)) { $ClusterName = 'platform-breakfix-aks' }
            if ([string]::IsNullOrWhiteSpace($CloudLocation)) { $CloudLocation = 'eastus2' }
            if ($ExpectedNodeCount -le 0) { $ExpectedNodeCount = 1 }
            if ([string]::IsNullOrWhiteSpace($ExpectedContext)) { $ExpectedContext = 'platform-breakfix-aks' }
            if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { $ResourceGroup = 'rg-platform-breakfix-aks' }

            . (Join-Path $RepositoryRoot 'validation/providers/aks.ps1')
            $config = Get-AksValidationConfig `
                -ClusterName $ClusterName `
                -Location $CloudLocation `
                -ExpectedNodeCount $ExpectedNodeCount `
                -ExpectedContext $ExpectedContext `
                -ResourceGroup $ResourceGroup

            $currentContext = Invoke-Kubectl -Arguments @('config', 'current-context') -Capture
            if ($currentContext.Trim() -ne $config.ExpectedContext) {
                Stop-ValidationFailure "Current context '$($currentContext.Trim())' does not match expected context '$($config.ExpectedContext)'."
            }
            Write-ValidationPass "Kubeconfig context is deterministic: $($config.ExpectedContext)."

            $storageManifest = Join-Path $RepositoryRoot 'validation/manifests/storage-smoke.yaml'
            $volumeHandle = Invoke-CommonKubernetesValidation `
                -ExpectedNodeCount $config.ExpectedNodeCount `
                -StorageManifest $storageManifest
            Invoke-AksValidation -Config $config -VolumeHandle $volumeHandle
            if (-not [string]::IsNullOrWhiteSpace($ProfileValidationScript)) {
                if (-not (Test-Path -LiteralPath $ProfileValidationScript -PathType Leaf)) {
                    Stop-ValidationFailure "AKS profile validation script '$ProfileValidationScript' does not exist."
                }
                & $ProfileValidationScript -Config $config
            }
            if (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
                Write-ValidationPass "AKS profile validation composition completed for '$ProfileName'."
            }
        }
    }

    Write-Host "PASS: $Provider satisfies the implemented v0 validation contract." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
