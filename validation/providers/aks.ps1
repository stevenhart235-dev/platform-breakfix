Set-StrictMode -Version Latest

function Get-AksValidationConfig {
    param(
        [string] $ClusterName = 'platform-breakfix-aks',
        [string] $Location = 'eastus2',
        [int] $ExpectedNodeCount = 1,
        [string] $ExpectedContext = 'platform-breakfix-aks',
        [string] $ResourceGroup = 'rg-platform-breakfix-aks'
    )

    return @{
        ClusterName       = $ClusterName
        Location          = $Location
        ExpectedContext   = $ExpectedContext
        ExpectedNodeCount = $ExpectedNodeCount
        ResourceGroup     = $ResourceGroup
        Composition       = 'providers/azure/aks/kubernetes'
    }
}

function Invoke-AksValidation {
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [string] $VolumeHandle
    )

    $clusterResult = & az aks show `
        --resource-group $Config.ResourceGroup `
        --name $Config.ClusterName `
        --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Stop-ValidationFailure "Could not inspect AKS: $($clusterResult -join [Environment]::NewLine)"
    }
    $cluster = ($clusterResult -join [Environment]::NewLine) | ConvertFrom-Json
    if ($cluster.provisioningState -ne 'Succeeded') {
        Stop-ValidationFailure "AKS provisioning state is '$($cluster.provisioningState)', not Succeeded."
    }
    Write-ValidationPass 'AKS provisioning state is Succeeded.'

    $classes = (Invoke-Kubectl -Arguments @('get', 'storageclass', '-o', 'json') -Capture) | ConvertFrom-Json
    $defaults = @($classes.items | Where-Object {
        $annotations = $_.metadata.psobject.Properties['annotations']
        if ($null -eq $annotations) { return $false }
        $defaultAnnotation = $annotations.Value.psobject.Properties['storageclass.kubernetes.io/is-default-class']
        return $null -ne $defaultAnnotation -and $defaultAnnotation.Value -eq 'true'
    })
    if ($defaults.Count -ne 1 -or $defaults[0].provisioner -ne 'disk.csi.azure.com') {
        Stop-ValidationFailure 'AKS must have exactly one default StorageClass using disk.csi.azure.com.'
    }
    Write-ValidationPass "AKS default StorageClass '$($defaults[0].metadata.name)' uses Azure Disk CSI."

    if (-not [string]::IsNullOrWhiteSpace($VolumeHandle)) {
        if ($VolumeHandle -notmatch '^/subscriptions/.+/providers/Microsoft\.Compute/disks/.+$') {
            Stop-ValidationFailure "CSI volume handle '$VolumeHandle' is not an Azure managed disk resource ID."
        }

        $deleted = $false
        for ($attempt = 1; $attempt -le 24; $attempt++) {
            $result = & az resource show --ids $VolumeHandle --output none 2>&1
            if ($LASTEXITCODE -ne 0) {
                $errorText = $result -join [Environment]::NewLine
                if ($errorText -match '\bNotFound\b|could not be found|(?:is|was) not found') {
                    $deleted = $true
                    break
                }
                Stop-ValidationFailure "Could not verify Azure Disk deletion: $errorText"
            }
            Start-Sleep -Seconds 5
        }
        if (-not $deleted) {
            Stop-ValidationFailure "Backing Azure Disk '$VolumeHandle' still exists after cleanup."
        }
        Write-ValidationPass "Backing Azure Disk '$VolumeHandle' was deleted."
    }
}
