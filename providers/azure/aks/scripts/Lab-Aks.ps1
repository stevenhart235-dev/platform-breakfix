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
    RequiredProviders     = @(
        'Microsoft.ContainerService',
        'Microsoft.Network',
        'Microsoft.Compute',
        'Microsoft.ManagedIdentity',
        'Microsoft.Storage'
    )
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
    param([Parameter(Mandatory)][string] $TofuPath)

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
}

function Write-AksConfigurationSummary {
    Write-Host @"
AKS Milestone 1 plan
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
"@
}

function Invoke-AksPlan {
    param(
        [Parameter(Mandatory)][string] $TofuPath,
        [Parameter(Mandatory)][string] $InfrastructureRoot
    )

    Write-AksConfigurationSummary
    Push-Location $InfrastructureRoot
    try {
        Invoke-CheckedCommand -Command $TofuPath -Arguments @('init', '-input=false')
        Invoke-CheckedCommand -Command $TofuPath -Arguments @('fmt', '-check')
        Invoke-CheckedCommand -Command $TofuPath -Arguments @('validate')
        Invoke-CheckedCommand -Command $TofuPath -Arguments @('plan', '-input=false', '-out=aks.tfplan')

        $plan = & $TofuPath show -json aks.tfplan | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { Stop-AksLifecycle 'Could not inspect the saved AKS plan.' }
        $allowedTypes = @(
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
            Stop-AksLifecycle "Plan contains resources outside Milestone 1 scope: $($unexpected.type -join ', ')"
        }
        if (@($changes | Where-Object { $_.change.actions -contains 'delete' }).Count -gt 0) {
            Stop-AksLifecycle 'Initial AKS plan unexpectedly contains delete actions.'
        }
        Write-Host "PASS: Plan contains $($changes.Count) scoped resource changes and no unexpected types." -ForegroundColor Green
        $changes | ForEach-Object { Write-Host "  $($_.change.actions -join '/') $($_.type).$($_.name)" }
    }
    finally {
        Pop-Location
    }
}

function Invoke-AksProvision {
    param(
        [Parameter(Mandatory)][string] $TofuPath,
        [Parameter(Mandatory)][string] $InfrastructureRoot
    )
    Push-Location $InfrastructureRoot
    try {
        if (-not (Test-Path -LiteralPath 'aks.tfplan')) {
            Stop-AksLifecycle 'Saved plan aks.tfplan is missing; run plan before provision.'
        }
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
    param([Parameter(Mandatory)][string] $RepositoryRoot)
    $composition = Join-Path $RepositoryRoot 'providers/azure/aks/kubernetes'
    Invoke-CheckedCommand -Command 'kubectl' -Arguments @('apply', '-k', $composition)
    foreach ($item in @('platform/nginx', 'platform/podinfo', 'platform/whoami', 'diagnostics/curl')) {
        $parts = $item.Split('/')
        Invoke-CheckedCommand -Command 'kubectl' -Arguments @(
            'rollout', 'status', "deployment/$($parts[1])", '-n', $parts[0], '--timeout=180s'
        )
    }
}

function Invoke-AksInspect {
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
        [Parameter(Mandatory)][string] $RepositoryRoot
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
            & kubectl delete -k (Join-Path $RepositoryRoot 'providers/azure/aks/kubernetes') --ignore-not-found=true --wait=true --timeout=180s
        }
    }

    Push-Location $InfrastructureRoot
    try {
        Invoke-CheckedCommand -Command $TofuPath -Arguments @('destroy', '-input=false', '-auto-approve')
    }
    finally { Pop-Location }
}

function Invoke-AksVerifyClean {
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
}
