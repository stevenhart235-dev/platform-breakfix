[CmdletBinding()]
param(
    [Parameter()]
    [string] $Profile
)

$ClusterName = 'platform-breakfix'
$AwsRegion = 'us-east-2'

function Stop-WithError {
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

foreach ($CommandName in @('aws', 'kubectl')) {
    if (-not (Get-Command $CommandName -CommandType Application -ErrorAction SilentlyContinue)) {
        Stop-WithError "'$CommandName' was not found in PATH. Install it in Windows and try again."
    }
}

$AwsArguments = @()
$ProfileDescription = 'the default AWS credential chain'
if (-not [string]::IsNullOrWhiteSpace($Profile)) {
    $AwsArguments = @('--profile', $Profile)
    $ProfileDescription = "AWS profile '$Profile'"
}

Write-Host "Verifying authentication with $ProfileDescription..."
& aws @AwsArguments sts get-caller-identity *> $null
if ($LASTEXITCODE -ne 0) {
    Stop-WithError "AWS authentication failed using $ProfileDescription. Refresh your credentials or select a valid profile, then try again."
}

Write-Host "Updating kubeconfig for EKS cluster $ClusterName in $AwsRegion..."
& aws @AwsArguments eks update-kubeconfig --name $ClusterName --region $AwsRegion
if ($LASTEXITCODE -ne 0) {
    Stop-WithError "Could not update kubeconfig. Confirm the cluster exists in $AwsRegion and your AWS identity can call eks:DescribeCluster."
}

Write-Host 'Verifying Kubernetes connectivity...'
& kubectl get nodes
if ($LASTEXITCODE -ne 0) {
    Stop-WithError 'kubectl could not reach the cluster. Check the EKS endpoint, network access, and access-entry permissions.'
}

Write-Host "Connected to $ClusterName successfully." -ForegroundColor Green
