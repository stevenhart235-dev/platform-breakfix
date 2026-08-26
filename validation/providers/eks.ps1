Set-StrictMode -Version Latest

function Get-EksValidationConfig {
    param(
        [string] $ClusterName = 'platform-breakfix',
        [string] $Region = 'us-east-2',
        [int] $ExpectedNodeCount = 2,
        [string] $ExpectedContext
    )

    $accountId = (& aws sts get-caller-identity --query Account --output text 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Stop-ValidationFailure "AWS authentication failed: $($accountId -join [Environment]::NewLine)"
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedContext)) {
        $ExpectedContext = "arn:aws:eks:${Region}:$accountId`:cluster/$ClusterName"
    }

    return @{
        ClusterName       = $ClusterName
        Region            = $Region
        ExpectedContext   = $ExpectedContext
        ExpectedNodeCount = $ExpectedNodeCount
        Composition       = 'providers/aws/eks/kubernetes'
    }
}

function Invoke-EksValidation {
    param(
        [Parameter(Mandatory)][hashtable] $Config,
        [string] $VolumeHandle
    )

    $clusterStatus = (& aws eks describe-cluster --name $Config.ClusterName --region $Config.Region --query 'cluster.status' --output text 2>&1)
    if ($LASTEXITCODE -ne 0 -or $clusterStatus.Trim() -ne 'ACTIVE') {
        Stop-ValidationFailure "EKS cluster '$($Config.ClusterName)' is not ACTIVE: $($clusterStatus -join [Environment]::NewLine)"
    }
    Write-ValidationPass 'EKS control plane is ACTIVE.'

    $defaultClasses = (Invoke-Kubectl -Arguments @('get', 'storageclass', '-o', 'json') -Capture) | ConvertFrom-Json
    $defaults = @($defaultClasses.items | Where-Object {
        $_.metadata.annotations.'storageclass.kubernetes.io/is-default-class' -eq 'true'
    })
    if ($defaults.Count -ne 1 -or $defaults[0].provisioner -ne 'ebs.csi.aws.com') {
        Stop-ValidationFailure 'EKS must have exactly one default StorageClass using ebs.csi.aws.com.'
    }
    Write-ValidationPass "EKS default StorageClass '$($defaults[0].metadata.name)' uses the EBS CSI driver."

    if (-not [string]::IsNullOrWhiteSpace($VolumeHandle)) {
        $deleted = $false
        for ($attempt = 1; $attempt -le 24; $attempt++) {
            $result = & aws ec2 describe-volumes --region $Config.Region --volume-ids $VolumeHandle 2>&1
            if ($LASTEXITCODE -ne 0) {
                $errorText = $result -join [Environment]::NewLine
                if ($errorText -match 'InvalidVolume\.NotFound') {
                    $deleted = $true
                    break
                }
                Stop-ValidationFailure "Could not verify deletion of EBS volume '$VolumeHandle': $errorText"
            }
            Start-Sleep -Seconds 5
        }
        if (-not $deleted) {
            Stop-ValidationFailure "Backing EBS volume '$VolumeHandle' still exists after storage cleanup."
        }
        Write-ValidationPass "Backing EBS volume '$VolumeHandle' was deleted."
    }
}
