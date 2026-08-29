Set-StrictMode -Version Latest

$script:AksDefaults = @{
    SubscriptionId        = '0071dee8-974f-4f93-ad2a-0960557e1888'
    SubscriptionName      = 'Ordicor Platform Lab'
    Location              = 'eastus2'
    KubernetesVersion     = '1.35.7'
    VmSize                = 'Standard_D2as_v7'
    NodeCount             = 1
    ResourceGroup         = 'rg-platform-breakfix-aks'
    NodeResourceGroup     = 'rg-platform-breakfix-aks-nodes'
    ClusterName           = 'platform-breakfix-aks'
    Context               = 'platform-breakfix-aks'
    VnetCidr              = '10.20.0.0/16'
    SubnetCidr            = '10.20.0.0/22'
    PodCidr               = '10.244.0.0/16'
    ServiceCidr           = '10.2.0.0/16'
    DnsServiceIp          = '10.2.0.10'
    TtlHours              = 4
    EstimatedNodeHourlyUsd = [decimal]0.10
    RequiredProviders     = @(
        'Microsoft.ContainerService',
        'Microsoft.Network',
        'Microsoft.Compute',
        'Microsoft.ManagedIdentity',
        'Microsoft.Storage'
    )
}

function Get-AksLabTemporalState {
    param(
        [Parameter(Mandatory)][string] $CreatedAt,
        [Parameter(Mandatory)][string] $ExpiresAt,
        [datetimeoffset] $Now = [datetimeoffset]::UtcNow
    )

    $created = [datetimeoffset]::Parse(
        $CreatedAt, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal
    ).ToUniversalTime()
    $expires = [datetimeoffset]::Parse(
        $ExpiresAt, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal
    ).ToUniversalTime()
    $nowUtc = $Now.ToUniversalTime()
    $isStale = $nowUtc -ge $expires

    [pscustomobject]@{
        State     = if ($isStale) { 'STALE' } else { 'ACTIVE' }
        CreatedAt = $created
        ExpiresAt = $expires
        Age       = $nowUtc - $created
        Remaining = if ($isStale) { [timespan]::Zero } else { $expires - $nowUtc }
        Overdue   = if ($isStale) { $nowUtc - $expires } else { [timespan]::Zero }
    }
}

function Get-AksTagValue {
    param(
        [Parameter(Mandatory)] $Tags,
        [Parameter(Mandatory)][string] $Name
    )
    $property = $Tags.psobject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($null -eq $property) { return $null }
    return [string]$property.Value
}

function Get-AksLabStatus {
    $exists = & az group exists --name $script:AksDefaults.ResourceGroup --output tsv
    if ($LASTEXITCODE -ne 0) {
        Stop-AksLifecycle "Could not determine whether resource group '$($script:AksDefaults.ResourceGroup)' exists."
    }
    if ($exists.Trim() -eq 'false') {
        return [pscustomobject]@{ State = 'NO LAB'; ResourceGroup = $script:AksDefaults.ResourceGroup }
    }

    $tagsResult = & az group show --name $script:AksDefaults.ResourceGroup --query tags --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Stop-AksLifecycle "Could not inspect resource group '$($script:AksDefaults.ResourceGroup)': $($tagsResult -join [Environment]::NewLine)"
    }
    $tags = ($tagsResult -join [Environment]::NewLine) | ConvertFrom-Json
    $owner = Get-AksTagValue -Tags $tags -Name 'PlatformBreakfix'
    $provider = Get-AksTagValue -Tags $tags -Name 'Provider'
    $profile = Get-AksTagValue -Tags $tags -Name 'Profile'
    $createdAt = Get-AksTagValue -Tags $tags -Name 'CreatedAt'
    $expiresAt = Get-AksTagValue -Tags $tags -Name 'ExpiresAt'
    if ($owner -ne 'true' -or $provider -ne 'aks' -or
        [string]::IsNullOrWhiteSpace($createdAt) -or [string]::IsNullOrWhiteSpace($expiresAt)) {
        return [pscustomobject]@{
            State = 'EXISTING UNCLASSIFIED'; ResourceGroup = $script:AksDefaults.ResourceGroup
            CreatedAt = $createdAt; ExpiresAt = $expiresAt; Profile = $profile
        }
    }

    try {
        $temporal = Get-AksLabTemporalState -CreatedAt $createdAt -ExpiresAt $expiresAt
    }
    catch {
        return [pscustomobject]@{
            State = 'EXISTING INVALID'; ResourceGroup = $script:AksDefaults.ResourceGroup
            CreatedAt = $createdAt; ExpiresAt = $expiresAt; Profile = $profile
        }
    }
    $temporal | Add-Member -NotePropertyName ResourceGroup -NotePropertyValue $script:AksDefaults.ResourceGroup
    $temporal | Add-Member -NotePropertyName Profile -NotePropertyValue $profile
    return $temporal
}

function Format-AksDuration {
    param([Parameter(Mandatory)][timespan] $Duration)
    return '{0}d {1:00}h {2:00}m' -f [math]::Floor($Duration.TotalDays), $Duration.Hours, $Duration.Minutes
}

function Show-AksLabStatus {
    param([Parameter(Mandatory)] $Profile)
    $status = Get-AksLabStatus
    $color = if ($status.State -eq 'STALE') { 'Red' } elseif ($status.State -eq 'ACTIVE') { 'Green' } else { 'Yellow' }
    Write-Host "`nAKS PAYG lab status: $($status.State)" -ForegroundColor $color
    Write-Host "Resource group: $($status.ResourceGroup)"
    Write-Host "Requested profile: $($Profile.Name)"
    $detectedProfile = if ($status.psobject.Properties.Name -contains 'Profile' -and $status.Profile) { $status.Profile } else { '(none)' }
    Write-Host "Detected profile:  $detectedProfile"
    if ($status.psobject.Properties.Name -contains 'CreatedAt' -and $status.CreatedAt) {
        $createdText = if ($status.CreatedAt -is [datetimeoffset]) { $status.CreatedAt.ToString('u') } else { $status.CreatedAt }
        Write-Host "Created:        $createdText"
    }
    if ($status.psobject.Properties.Name -contains 'ExpiresAt' -and $status.ExpiresAt) {
        $expiresText = if ($status.ExpiresAt -is [datetimeoffset]) { $status.ExpiresAt.ToString('u') } else { $status.ExpiresAt }
        Write-Host "Expires:        $expiresText"
    }
    if ($status.State -in @('ACTIVE', 'STALE')) {
        Write-Host "Age:            $(Format-AksDuration -Duration $status.Age)"
        if ($status.State -eq 'ACTIVE') {
            Write-Host "Remaining TTL:  $(Format-AksDuration -Duration $status.Remaining)"
        }
        else {
            Write-Host "Overdue by:     $(Format-AksDuration -Duration $status.Overdue)" -ForegroundColor Red
            Write-Host 'WARNING: TTL is advisory; explicitly run destroy.' -ForegroundColor Red
        }
    }
    return $status
}

function Write-AksPaygWarning {
    param([Parameter(Mandatory)] $Profile)
    $ttlCost = $script:AksDefaults.EstimatedNodeHourlyUsd * $script:AksDefaults.NodeCount * $script:AksDefaults.TtlHours
    Write-Host @"

AKS PAYG LAB

Subscription:     $($script:AksDefaults.SubscriptionName)
Region:           $($script:AksDefaults.Location)
Profile:          $($Profile.Name)
Node:             $($script:AksDefaults.NodeCount) x $($script:AksDefaults.VmSize)
TTL:              $($script:AksDefaults.TtlHours) hours (advisory; no automatic deletion)

Estimated compute: ~`$$($script:AksDefaults.EstimatedNodeHourlyUsd.ToString('0.00'))/hour
Estimated lab:     ~`$$($ttlCost.ToString('0.00')) for $($script:AksDefaults.TtlHours) hours of node compute

AKS Free tier has no cluster-management charge. Managed disks, Standard Load
Balancer/public IP usage, network egress, taxes, and other usage-based Azure
charges may apply. This estimate is informational, not billing-authoritative.
"@ -ForegroundColor Yellow
}

function Assert-AksProvisionAllowed {
    param([Parameter(Mandatory)] $Status, [Parameter(Mandatory)] $Profile)
    if ($Status.State -ne 'NO LAB') {
        Assert-AksLiveLabProfile -Status $Status -RequestedProfile $Profile.Name
        Stop-AksLifecycle "Existing AKS lab detected in '$($Status.ResourceGroup)' with state '$($Status.State)'. Explicitly inspect or destroy it before provision."
    }
}

function Test-AksDuplicateProvisionProtection {
    param([Parameter(Mandatory)] $Status, [Parameter(Mandatory)] $Profile)
    try {
        Assert-AksProvisionAllowed -Status $Status -Profile $Profile
    }
    catch {
        if ($_.Exception.Message -notmatch '^Existing AKS lab detected') { throw }
        Write-Host 'PASS: The normal provision gate blocks this existing PAYG lab.' -ForegroundColor Green
        return
    }
    Stop-AksLifecycle 'Duplicate-provision protection did not block the existing AKS lab.'
}

function Stop-AksLifecycle {
    param([Parameter(Mandatory)][string] $Message)
    throw $Message
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string] $Command,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    & $Command @Arguments | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Stop-AksLifecycle "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')"
    }
}

function Get-AzureManagementValue {
    param([Parameter(Mandatory)][string] $Uri)

    $token = & az account get-access-token `
        --resource 'https://management.azure.com/' `
        --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        Stop-AksLifecycle 'Could not obtain an Azure Resource Manager access token.'
    }
    Invoke-RestMethod -Uri $Uri -Headers @{ Authorization = "Bearer $token" }
}

function Invoke-AksDoctor {
    param([Parameter(Mandatory)][string] $TofuPath, [Parameter(Mandatory)] $Profile)

    foreach ($command in @('az', 'kubectl')) {
        if (-not (Get-Command $command -CommandType Application -ErrorAction SilentlyContinue)) {
            Stop-AksLifecycle "'$command' was not found in PATH."
        }
    }
    if (-not (Test-Path -LiteralPath $TofuPath -PathType Leaf)) {
        Stop-AksLifecycle "OpenTofu executable '$TofuPath' does not exist."
    }

    $tofu = & $TofuPath version -json | ConvertFrom-Json
    $tofuVersion = [version]$tofu.terraform_version
    if ($tofuVersion -lt [version]'1.11.5' -or $tofuVersion -ge [version]'1.12.0') {
        Stop-AksLifecycle "OpenTofu $tofuVersion is unsupported; use >=1.11.5 and <1.12.0."
    }
    Write-Host "PASS: OpenTofu $tofuVersion is supported." -ForegroundColor Green

    $accountResult = & az account show --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Stop-AksLifecycle "Azure authentication failed: $($accountResult -join [Environment]::NewLine)"
    }
    $account = ($accountResult -join [Environment]::NewLine) | ConvertFrom-Json
    if ($account.id -ne $script:AksDefaults.SubscriptionId -or
        $account.name -ne $script:AksDefaults.SubscriptionName -or
        $account.state -ne 'Enabled') {
        Stop-AksLifecycle "Expected enabled subscription '$($script:AksDefaults.SubscriptionName)' ($($script:AksDefaults.SubscriptionId)); active subscription is '$($account.name)' ($($account.id)), state '$($account.state)'."
    }
    Write-Host 'PASS: Expected enabled Azure subscription is active.' -ForegroundColor Green

    foreach ($namespace in $script:AksDefaults.RequiredProviders) {
        $state = & az provider show --namespace $namespace --query registrationState --output tsv
        if ($LASTEXITCODE -ne 0 -or $state.Trim() -ne 'Registered') {
            Stop-AksLifecycle "Required provider '$namespace' is not Registered (state: '$state')."
        }
    }
    Write-Host 'PASS: Required Azure resource providers are Registered.' -ForegroundColor Green

    $versionsResult = & az aks get-versions --location $script:AksDefaults.Location --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Stop-AksLifecycle "Could not query AKS versions: $($versionsResult -join [Environment]::NewLine)"
    }
    $versions = ($versionsResult -join [Environment]::NewLine) | ConvertFrom-Json
    $versionCount = @($versions.values | Where-Object {
        $_.patchVersions.psobject.Properties.Name -contains $script:AksDefaults.KubernetesVersion
    }).Count
    if ($versionCount -lt 1) {
        Stop-AksLifecycle "AKS Kubernetes $($script:AksDefaults.KubernetesVersion) is not offered in $($script:AksDefaults.Location)."
    }
    Write-Host "PASS: AKS Kubernetes $($script:AksDefaults.KubernetesVersion) is offered in $($script:AksDefaults.Location)." -ForegroundColor Green

    $subscriptionId = $script:AksDefaults.SubscriptionId
    $skuUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/skus?api-version=2021-07-01&`$filter=location%20eq%20'$($script:AksDefaults.Location)'"
    $skuItems = @()
    do {
        $response = Get-AzureManagementValue -Uri $skuUri
        $skuItems += $response.value
        $skuUri = if ($response.psobject.Properties.Name -contains 'nextLink') {
            $response.nextLink
        }
        else {
            $null
        }
    } while ($skuUri)
    $sku = $skuItems | Where-Object {
        $_.resourceType -eq 'virtualMachines' -and $_.name -eq $script:AksDefaults.VmSize
    }
    if (-not $sku -or @($sku.restrictions).Count -gt 0) {
        Stop-AksLifecycle "VM SKU '$($script:AksDefaults.VmSize)' is absent or restricted in $($script:AksDefaults.Location)."
    }
    Write-Host "PASS: VM SKU $($script:AksDefaults.VmSize) is available without restrictions." -ForegroundColor Green

    $usageUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/locations/$($script:AksDefaults.Location)/usages?api-version=2024-03-01"
    $usage = (Get-AzureManagementValue -Uri $usageUri).value
    $regional = $usage | Where-Object { $_.name.localizedValue -eq 'Total Regional vCPUs' }
    $family = $usage | Where-Object { $_.name.localizedValue -eq 'Standard Dasv7 Family vCPUs' }
    foreach ($quota in @($regional, $family)) {
        if (-not $quota -or ($quota.limit - $quota.currentValue) -lt 2) {
            Stop-AksLifecycle "Insufficient quota for '$($quota.name.localizedValue)': usage $($quota.currentValue), limit $($quota.limit), required 2."
        }
    }
    Write-Host 'PASS: Regional and Dasv7 family quota each have at least 2 free vCPUs.' -ForegroundColor Green
    $status = Show-AksLabStatus -Profile $Profile
    if ($status.State -ne 'NO LAB') { Assert-AksLiveLabProfile -Status $status -RequestedProfile $Profile.Name }
}

function Write-AksConfigurationSummary {
    param([Parameter(Mandatory)] $Profile)
    Write-Host @"
AKS Milestone 3 PAYG plan
  profile:         $($Profile.Name)
  subscription:    $($script:AksDefaults.SubscriptionName) ($($script:AksDefaults.SubscriptionId))
  location:        $($script:AksDefaults.Location)
  resource group:  $($script:AksDefaults.ResourceGroup)
  Kubernetes:      $($script:AksDefaults.KubernetesVersion)
  node pool:       $($script:AksDefaults.NodeCount) x $($script:AksDefaults.VmSize), fixed System pool
  networking:      Azure CNI Overlay
  VNet/subnet:     $($script:AksDefaults.VnetCidr) / $($script:AksDefaults.SubnetCidr)
  pod/service:     $($script:AksDefaults.PodCidr) / $($script:AksDefaults.ServiceCidr)
  DNS service IP:  $($script:AksDefaults.DnsServiceIp)
  API:             public, no authorized-IP restriction
  outbound:        Standard Load Balancer
  ownership:       dedicated resource group plus deterministic AKS node resource group
  advisory TTL:    $($script:AksDefaults.TtlHours) hours; explicit destroy required
"@
}

function Invoke-AksPlan {
    param(
        [Parameter(Mandatory)][string] $TofuPath,
        [Parameter(Mandatory)][string] $InfrastructureRoot,
        [Parameter(Mandatory)] $Profile
    )

    Write-AksConfigurationSummary -Profile $Profile
    Push-Location $InfrastructureRoot
    try {
        Remove-Item -LiteralPath 'aks.tfplan', 'aks.tfplan.profile' -Force -ErrorAction SilentlyContinue
        Invoke-CheckedCommand -Command $TofuPath -Arguments @('init', '-input=false')
        Invoke-CheckedCommand -Command $TofuPath -Arguments @('fmt', '-check')
        Invoke-CheckedCommand -Command $TofuPath -Arguments @('validate')
        Invoke-CheckedCommand -Command $TofuPath -Arguments @(
            'plan', '-input=false',
            "-var=lab_ttl_hours=$($script:AksDefaults.TtlHours)",
            "-var=profile_name=$($Profile.Name)",
            "-var=network_data_plane=$($Profile.InfrastructureInputs.NetworkDataPlane)",
            "-var=node_vm_size=$($Profile.InfrastructureInputs.NodeVmSize)",
            "-var=node_count=$($Profile.InfrastructureInputs.NodeCount)",
            '-out=aks.tfplan'
        )
        $plan = & $TofuPath show -json aks.tfplan | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { Stop-AksLifecycle 'Could not inspect the saved AKS plan.' }
        $allowedTypes = @(
            'time_static',
            'azurerm_resource_group',
            'azurerm_virtual_network',
            'azurerm_subnet',
            'azurerm_user_assigned_identity',
            'azurerm_role_assignment',
            'azurerm_kubernetes_cluster'
        )
        $changes = @($plan.resource_changes | Where-Object { $_.change.actions -notcontains 'no-op' })
        $unexpected = @($changes | Where-Object { $_.type -notin $allowedTypes })
        if ($unexpected.Count -gt 0) {
            Stop-AksLifecycle "Plan contains resources outside Milestone 2 scope: $($unexpected.type -join ', ')"
        }
        if (@($changes | Where-Object { $_.change.actions -contains 'delete' }).Count -gt 0) {
            Stop-AksLifecycle 'Initial AKS plan unexpectedly contains delete actions.'
        }
        $azureChanges = @($changes | Where-Object { $_.provider_name -match 'azurerm' })
        @{
            Profile    = $Profile.Name
            PlanSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath 'aks.tfplan').Hash
        } | ConvertTo-Json -Compress | Set-Content -LiteralPath 'aks.tfplan.profile' -Encoding utf8
        Write-Host "PASS: Plan contains $($azureChanges.Count) scoped Azure changes and $($changes.Count - $azureChanges.Count) stable timestamp state change; no unexpected types." -ForegroundColor Green
        $changes | ForEach-Object { Write-Host "  $($_.change.actions -join '/') $($_.type).$($_.name)" }
    }
    finally {
        Pop-Location
    }
}

function Invoke-AksProvision {
    param(
        [Parameter(Mandatory)][string] $TofuPath,
        [Parameter(Mandatory)][string] $InfrastructureRoot,
        [Parameter(Mandatory)] $Profile
    )
    $status = Show-AksLabStatus -Profile $Profile
    Assert-AksProvisionAllowed -Status $status -Profile $Profile

    Push-Location $InfrastructureRoot
    try {
        if (-not (Test-Path -LiteralPath 'aks.tfplan')) {
            Stop-AksLifecycle 'Saved plan aks.tfplan is missing; run plan before provision.'
        }
        Assert-AksSavedPlanProfile -MetadataPath 'aks.tfplan.profile' -PlanPath 'aks.tfplan' -RequestedProfile $Profile.Name
        Write-AksPaygWarning -Profile $Profile
        Invoke-CheckedCommand -Command $TofuPath -Arguments @('apply', '-input=false', '-auto-approve', 'aks.tfplan')
    }
    finally { Pop-Location }
}

function Set-AksKubeconfigContext {
    $currentContext = (& kubectl config current-context).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentContext)) {
        Stop-AksLifecycle 'Azure credentials were merged, but kubectl has no current context.'
    }
    if ($currentContext -ne $script:AksDefaults.Context) {
        & kubectl config delete-context $script:AksDefaults.Context 2>$null | Out-Null
        Invoke-CheckedCommand -Command 'kubectl' -Arguments @(
            'config', 'rename-context', $currentContext, $script:AksDefaults.Context
        )
    }
    Invoke-CheckedCommand -Command 'kubectl' -Arguments @('config', 'use-context', $script:AksDefaults.Context)
}

function Invoke-AksConnect {
    param([Parameter(Mandatory)] $Profile)
    Invoke-CheckedCommand -Command 'az' -Arguments @(
        'aks', 'get-credentials', '--admin', '--overwrite-existing',
        '--resource-group', $script:AksDefaults.ResourceGroup,
        '--name', $script:AksDefaults.ClusterName,
        '--context', $script:AksDefaults.Context
    )
    Set-AksKubeconfigContext
    $context = & kubectl config current-context
    if ($LASTEXITCODE -ne 0 -or $context.Trim() -ne $script:AksDefaults.Context) {
        Stop-AksLifecycle "Expected kubeconfig context '$($script:AksDefaults.Context)', got '$context'."
    }
    Invoke-CheckedCommand -Command 'kubectl' -Arguments @('cluster-info')
    Invoke-CheckedCommand -Command 'kubectl' -Arguments @('get', 'nodes')
}

function Invoke-AksBootstrap {
    param([Parameter(Mandatory)] $Profile)
    Invoke-CheckedCommand -Command 'kubectl' -Arguments @('apply', '-k', $Profile.BootstrapComposition)
    foreach ($item in @('platform/nginx', 'platform/podinfo', 'platform/whoami', 'diagnostics/curl')) {
        $parts = $item.Split('/')
        Invoke-CheckedCommand -Command 'kubectl' -Arguments @(
            'rollout', 'status', "deployment/$($parts[1])", '-n', $parts[0], '--timeout=180s'
        )
    }
}

function Invoke-AksInspect {
    param([Parameter(Mandatory)] $Profile)
    $status = Show-AksLabStatus -Profile $Profile
    if ($status.State -eq 'NO LAB') { return }
    if ($status.State -ne 'ACTIVE') {
        Stop-AksLifecycle "Expected the live repeatability lab to be ACTIVE; detected '$($status.State)'."
    }
    Assert-AksLiveLabProfile -Status $status -RequestedProfile $Profile.Name
    Write-Host "Requested profile: $($Profile.Name)"
    Write-Host "Detected profile:  $($status.Profile)"
    $detectedDataPlane = & az aks show --resource-group $script:AksDefaults.ResourceGroup --name $script:AksDefaults.ClusterName --query networkProfile.networkDataplane --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($detectedDataPlane)) {
        Stop-AksLifecycle 'Could not detect the live AKS network data plane.'
    }
    $detectedDataPlane = $detectedDataPlane.Trim().ToLowerInvariant()
    $expectedDataPlane = ([string]$Profile.InfrastructureInputs.NetworkDataPlane).ToLowerInvariant()
    Write-Host "Expected network data plane: $expectedDataPlane"
    Write-Host "Detected network data plane: $detectedDataPlane"
    if ($detectedDataPlane -cne $expectedDataPlane) {
        Stop-AksLifecycle "AKS network data plane mismatch: profile '$($Profile.Name)' expects '$expectedDataPlane', Azure reports '$detectedDataPlane'."
    }
    $tagTtlHours = ($status.ExpiresAt - $status.CreatedAt).TotalHours
    if ([math]::Abs($tagTtlHours - $script:AksDefaults.TtlHours) -gt (1.0 / 60.0)) {
        Stop-AksLifecycle "Expected an approximately $($script:AksDefaults.TtlHours)-hour tag TTL; found $tagTtlHours hours."
    }
    Write-Host "PASS: Ownership, CreatedAt, ExpiresAt, and approximately $($script:AksDefaults.TtlHours)-hour TTL tags are valid." -ForegroundColor Green
    Write-Host "PASS: Azure reports the '$detectedDataPlane' network data plane required by profile '$($Profile.Name)'." -ForegroundColor Green
    Test-AksDuplicateProvisionProtection -Status $status -Profile $Profile
    Invoke-CheckedCommand -Command 'az' -Arguments @(
        'aks', 'show', '--resource-group', $script:AksDefaults.ResourceGroup,
        '--name', $script:AksDefaults.ClusterName,
        '--query', '{name:name,location:location,kubernetesVersion:kubernetesVersion,provisioningState:provisioningState,nodeResourceGroup:nodeResourceGroup,networkProfile:networkProfile,identity:identity.type}',
        '--output', 'json'
    )
    Invoke-CheckedCommand -Command 'kubectl' -Arguments @('get', 'nodes', '-o', 'wide')
    Invoke-CheckedCommand -Command 'kubectl' -Arguments @('get', 'pods', '-A')
    Invoke-CheckedCommand -Command 'kubectl' -Arguments @('get', 'storageclass')
}

function Invoke-AksDestroy {
    param(
        [Parameter(Mandatory)][string] $TofuPath,
        [Parameter(Mandatory)][string] $InfrastructureRoot,
        [Parameter(Mandatory)] $Profile
    )

    $exists = & az group exists --name $script:AksDefaults.ResourceGroup --output tsv
    if ($LASTEXITCODE -eq 0 -and $exists.Trim() -eq 'true') {
        & az aks get-credentials --admin --overwrite-existing `
            --resource-group $script:AksDefaults.ResourceGroup `
            --name $script:AksDefaults.ClusterName `
            --context $script:AksDefaults.Context 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Set-AksKubeconfigContext
            & kubectl delete namespace platform-breakfix-validation --ignore-not-found=true --wait=true --timeout=180s
            & kubectl delete -k $Profile.BootstrapComposition --ignore-not-found=true --wait=true --timeout=180s
        }
    }

    Push-Location $InfrastructureRoot
    try {
        Invoke-CheckedCommand -Command $TofuPath -Arguments @(
            'destroy', '-input=false', '-auto-approve',
            "-var=lab_ttl_hours=$($script:AksDefaults.TtlHours)",
            "-var=profile_name=$($Profile.Name)",
            "-var=network_data_plane=$($Profile.InfrastructureInputs.NetworkDataPlane)",
            "-var=node_vm_size=$($Profile.InfrastructureInputs.NodeVmSize)",
            "-var=node_count=$($Profile.InfrastructureInputs.NodeCount)"
        )
    }
    finally { Pop-Location }
}

function Invoke-AksVerifyClean {
    param([Parameter(Mandatory)] $Profile)
    foreach ($group in @($script:AksDefaults.ResourceGroup, $script:AksDefaults.NodeResourceGroup)) {
        $exists = & az group exists --name $group --output tsv
        if ($LASTEXITCODE -ne 0) { Stop-AksLifecycle "Could not verify resource group '$group'." }
        if ($exists.Trim() -ne 'false') { Stop-AksLifecycle "Resource group '$group' still exists." }
        Write-Host "PASS: Resource group '$group' is absent." -ForegroundColor Green
    }

    $leftovers = & az resource list --tag Project=platform-breakfix --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { Stop-AksLifecycle 'Could not list tagged Azure resources.' }
    $aksLeftovers = @($leftovers | Where-Object { $_.tags.Provider -eq 'aks' })
    if ($aksLeftovers.Count -gt 0) {
        Stop-AksLifecycle "Found $($aksLeftovers.Count) tagged AKS lab resources after destroy: $($aksLeftovers.id -join ', ')"
    }
    Write-Host 'PASS: No tagged AKS lab resources remain.' -ForegroundColor Green
    $status = Show-AksLabStatus -Profile $Profile
    if ($status.State -ne 'NO LAB') {
        Stop-AksLifecycle "Expected NO LAB after cleanup; detected '$($status.State)'."
    }
}

function Invoke-AksScenario {
    param([Parameter(Mandatory)] $Profile)
    Write-Host "No scenario is implemented for AKS profile '$($Profile.Name)'; the validated baseline is the scenario starting point."
}
