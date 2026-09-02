[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$helperPath = Join-Path $repositoryRoot 'scripts/EksLifecycleMetadata.ps1'
$planPath = Join-Path $repositoryRoot 'scripts/New-EksLabPlan.ps1'
$infraRoot = Join-Path $repositoryRoot 'infrastructure/eks'
. $helperPath

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Fails([string]$Name, [scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -cnotmatch $Pattern) { throw "$Name failed unexpectedly: $($_.Exception.Message)" }; Write-Host "PASS: $Name fails closed." -ForegroundColor Green; return }
    throw "$Name unexpectedly succeeded."
}
function New-Metadata([int]$Hours = 4) {
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        LabId = '8ac61d2c-e353-4f69-8ea2-e72bc0339787'
        AccountId = '123456789012'
        Region = 'us-east-2'
        CreatedAt = '2026-09-02T12:00:00Z'
        ExpiresAt = ([datetimeoffset]'2026-09-02T12:00:00Z').AddHours($Hours).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}

$valid = New-Metadata
Assert-EksLifecycleMetadata $valid | Out-Null
Assert-EksLifecycleBinding $valid '123456789012' 'us-east-2' '8ac61d2c-e353-4f69-8ea2-e72bc0339787' | Out-Null
Write-Host 'PASS: exact version-1 metadata, account, region, LabId, and four-hour timestamps validate.' -ForegroundColor Green
Assert-Fails 'missing required metadata' { $value=New-Metadata;$value.PSObject.Properties.Remove('ExpiresAt');Assert-EksLifecycleMetadata $value } 'invalid field set'
Assert-Fails 'extra metadata' { $value=New-Metadata;$value|Add-Member Extra nope;Assert-EksLifecycleMetadata $value } 'invalid field set'
Assert-Fails 'malformed LabId' { $value=New-Metadata;$value.LabId='not-a-uuid';Assert-EksLifecycleMetadata $value } 'canonical lowercase UUID'
Assert-Fails 'uppercase LabId' { $value=New-Metadata;$value.LabId=$value.LabId.ToUpperInvariant();Assert-EksLifecycleMetadata $value } 'canonical lowercase UUID'
Assert-Fails 'malformed timestamp' { $value=New-Metadata;$value.CreatedAt='2026-09-02 12:00:00';Assert-EksLifecycleMetadata $value } 'second-precision UTC RFC3339'
Assert-Fails 'non-positive lifetime' { $value=New-Metadata;$value.ExpiresAt=$value.CreatedAt;Assert-EksLifecycleMetadata $value } '1 through 24 whole hours'
Assert-Fails 'fractional lifetime' { $value=New-Metadata;$value.ExpiresAt='2026-09-02T13:30:00Z';Assert-EksLifecycleMetadata $value } '1 through 24 whole hours'
Assert-Fails 'account mismatch' { Assert-EksLifecycleBinding $valid '999999999999' 'us-east-2' } 'Authenticated AWS account conflicts'
Assert-Fails 'region mismatch' { Assert-EksLifecycleBinding $valid '123456789012' 'us-west-2' } 'Configured AWS region conflicts'
Assert-Fails 'LabId mismatch' { Assert-EksLifecycleBinding $valid '123456789012' 'us-east-2' '00000000-0000-0000-0000-000000000001' } 'LabId conflicts'

$lifecycle = Get-Content -Raw (Join-Path $infraRoot 'lifecycle.tf')
$lifecycleModule = Get-Content -Raw (Join-Path $infraRoot 'modules/lifecycle/main.tf')
$main = Get-Content -Raw (Join-Path $infraRoot 'main.tf')
$variables = Get-Content -Raw (Join-Path $infraRoot 'variables.tf')
Assert-True ($lifecycle -match 'module "eks_lifecycle"' -and $lifecycleModule -match 'resource "random_uuid" "lab"' -and $lifecycleModule -match 'resource "time_static" "lab"') 'LabId/CreatedAt are not state-backed one-time resources.'
Assert-True ($lifecycleModule -match 'ignore_changes = \[input\]') 'Existing lifecycle metadata is not immutable against configuration changes.'
Assert-True ($lifecycleModule -match 'ExpiresAt\s+= timeadd\(time_static\.lab\.rfc3339, "\$\{var\.lifetime_hours\}h"\)') 'ExpiresAt is not calculated once from CreatedAt and selected lifetime.'
Assert-True ($variables -match 'default\s+= 4' -and $variables -match '>= 1.*<= 24.*floor') 'Lifetime default/bounds/whole-hour guard changed.'
$tagKeys=@('metadata-schema','lab-id','account-id','region','created-at','expires-at','provider','lifecycle')
foreach($key in $tagKeys){Assert-True($lifecycleModule -match [regex]::Escape("platform-breakfix:$key")) "Missing lifecycle tag key $key."}
Assert-True ($main -match '(?s)module "vpc".*?tags\s+= local\.eks_lifecycle_tags.*?vpc_tags\s+= local\.eks_lifecycle_tags') 'The VPC partial-provision anchor lacks full metadata.'
Assert-True ($main -match '(?s)module "eks".*?tags\s+= local\.eks_lifecycle_tags.*?cluster_tags\s+= local\.eks_lifecycle_tags') 'The EKS ownership anchor lacks full metadata.'
Assert-True ($main -match '(?s)module "ebs_csi_pod_identity".*?tags\s+= local\.eks_lifecycle_tags') 'The durable IAM ownership resource lacks lifecycle metadata.'
Assert-True (($valid.PSObject.Properties.Name -join ',') -notmatch '(?i)credential|secret|token|accesskey|kubeconfig|state') 'Metadata contains a prohibited sensitive field.'
Assert-True ((Get-Content -Raw $planPath) -match '\$repositoryRoot = Split-Path -Parent \$PSScriptRoot') 'Plan behavior depends on the current working directory.'

foreach($bad in @('0','-1','25','1.5','four')) {
    Assert-Fails "LifetimeHours $bad" { & $planPath -LifetimeHours $bad -TofuPath 'not-invoked' } 'parameter|validation|pattern'
}
Write-Host 'PASS: invalid creation-time LifetimeHours values fail before OpenTofu execution.' -ForegroundColor Green
Write-Host 'PASS: immutable EKS lifecycle metadata tests.' -ForegroundColor Green