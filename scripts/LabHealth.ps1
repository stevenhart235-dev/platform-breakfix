Set-StrictMode -Version Latest

$script:LabHealthContractVersion = 1
$script:LabHealthOverallStates = @('HEALTHY', 'DEGRADED', 'UNKNOWN')
$script:LabHealthComponentStates = @('HEALTHY', 'DEGRADED', 'UNKNOWN', 'NOT_APPLICABLE')
$script:LabHealthComponentNames = @('Nodes', 'Pods', 'PVCs', 'Services', 'Endpoints', 'Cilium', 'Istio')

function Test-LabHealthInteger {
    param($Value)
    $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
}

function Assert-LabHealthObjectKeys {
    param($Value, [string[]] $Required, [string] $Context)
    if ($null -eq $Value) { throw "$Context must be an object." }
    $actual = @($Value.psobject.Properties.Name)
    $missing = @($Required | Where-Object { $_ -notin $actual })
    $unknown = @($actual | Where-Object { $_ -notin $Required })
    if ($missing.Count) { throw "$Context is missing required field(s): $($missing -join ', ')." }
    if ($unknown.Count) { throw "$Context contains unknown field(s): $($unknown -join ', ')." }
}

function Assert-LabHealthBoolean {
    param($Value, [string] $Field)
    if ($Value -isnot [bool]) { throw "$Field must be boolean." }
}

function Assert-LabHealthCount {
    param($Value, [string] $Field)
    if (-not (Test-LabHealthInteger $Value) -or $Value -lt 0) { throw "$Field must be a non-negative integer." }
}

function Assert-LabHealthString {
    param($Value, [string] $Field, [switch] $AllowNull)
    if ($AllowNull -and $null -eq $Value) { return }
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw "$Field must be a non-empty string." }
}

function Assert-LabHealthObservations {
    param([Parameter(Mandatory)] $Observations)
    $topKeys = @('Provider', 'Profile') + $script:LabHealthComponentNames
    Assert-LabHealthObjectKeys $Observations $topKeys 'Health observations'
    if ($Observations.Provider -cne 'aks') { throw "Health observations provider '$($Observations.Provider)' is unsupported." }
    if ($Observations.Profile -cnotin @('minimal', 'cilium', 'istio')) { throw "Health observations profile '$($Observations.Profile)' is unsupported." }

    foreach ($name in @('Nodes', 'Pods')) {
        $component = $Observations.$name
        Assert-LabHealthObjectKeys $component @('Available', 'Total', 'Ready') "Health observations.$name"
        Assert-LabHealthBoolean $component.Available "Health observations.$name.Available"
        Assert-LabHealthCount $component.Total "Health observations.$name.Total"
        Assert-LabHealthCount $component.Ready "Health observations.$name.Ready"
        if ($component.Ready -gt $component.Total) { throw "Health observations.$name.Ready cannot exceed Total." }
    }
    $pvc = $Observations.PVCs
    Assert-LabHealthObjectKeys $pvc @('Available', 'Applicable', 'Total', 'Bound') 'Health observations.PVCs'
    Assert-LabHealthBoolean $pvc.Available 'Health observations.PVCs.Available'
    Assert-LabHealthBoolean $pvc.Applicable 'Health observations.PVCs.Applicable'
    Assert-LabHealthCount $pvc.Total 'Health observations.PVCs.Total'
    Assert-LabHealthCount $pvc.Bound 'Health observations.PVCs.Bound'
    if ($pvc.Bound -gt $pvc.Total -or (-not $pvc.Applicable -and ($pvc.Total -ne 0 -or $pvc.Bound -ne 0))) { throw 'Health observations.PVCs counts are inconsistent with applicability.' }

    $services = $Observations.Services
    Assert-LabHealthObjectKeys $services @('Available', 'Expected', 'Observed', 'SelectorAligned') 'Health observations.Services'
    Assert-LabHealthBoolean $services.Available 'Health observations.Services.Available'
    foreach ($field in @('Expected', 'Observed', 'SelectorAligned')) { Assert-LabHealthCount $services.$field "Health observations.Services.$field" }
    if ($services.Observed -gt $services.Expected -or $services.SelectorAligned -gt $services.Observed) { throw 'Health observations.Services counts are inconsistent.' }

    $endpoints = $Observations.Endpoints
    Assert-LabHealthObjectKeys $endpoints @('Available', 'Expected', 'ReadyServices', 'ReadyEndpoints') 'Health observations.Endpoints'
    Assert-LabHealthBoolean $endpoints.Available 'Health observations.Endpoints.Available'
    foreach ($field in @('Expected', 'ReadyServices', 'ReadyEndpoints')) { Assert-LabHealthCount $endpoints.$field "Health observations.Endpoints.$field" }
    if ($endpoints.ReadyServices -gt $endpoints.Expected -or $endpoints.ReadyEndpoints -lt $endpoints.ReadyServices) { throw 'Health observations.Endpoints counts are inconsistent.' }

    $cilium = $Observations.Cilium
    Assert-LabHealthObjectKeys $cilium @('Available', 'Expected', 'Ready', 'Version') 'Health observations.Cilium'
    Assert-LabHealthBoolean $cilium.Available 'Health observations.Cilium.Available'
    Assert-LabHealthCount $cilium.Expected 'Health observations.Cilium.Expected'
    Assert-LabHealthCount $cilium.Ready 'Health observations.Cilium.Ready'
    if ($cilium.Ready -gt $cilium.Expected) { throw 'Health observations.Cilium.Ready cannot exceed Expected.' }
    Assert-LabHealthString $cilium.Version 'Health observations.Cilium.Version' -AllowNull

    $istio = $Observations.Istio
    Assert-LabHealthObjectKeys $istio @('Available', 'ControlPlaneExpected', 'ControlPlaneReady', 'CniExpected', 'CniReady', 'Version') 'Health observations.Istio'
    Assert-LabHealthBoolean $istio.Available 'Health observations.Istio.Available'
    foreach ($field in @('ControlPlaneExpected', 'ControlPlaneReady', 'CniExpected', 'CniReady')) { Assert-LabHealthCount $istio.$field "Health observations.Istio.$field" }
    if ($istio.ControlPlaneReady -gt $istio.ControlPlaneExpected -or $istio.CniReady -gt $istio.CniExpected) { throw 'Health observations.Istio counts are inconsistent.' }
    Assert-LabHealthString $istio.Version 'Health observations.Istio.Version' -AllowNull
    $Observations
}

function New-LabHealthComponent {
    param([string] $Status, [string] $Summary, [hashtable] $Facts)
    $ordered = [ordered]@{ Status = $Status; Summary = $Summary }
    foreach ($key in @($Facts.Keys | Sort-Object)) { $ordered[$key] = $Facts[$key] }
    [pscustomobject]$ordered
}

function Get-LabHealthCountComponent {
    param([string] $Name, $Observation)
    if (-not $Observation.Available) { return New-LabHealthComponent UNKNOWN "$Name could not be observed." @{ Total = 0; Ready = 0 } }
    $status = if ($Observation.Total -gt 0 -and $Observation.Ready -eq $Observation.Total) { 'HEALTHY' } else { 'DEGRADED' }
    New-LabHealthComponent $status "$($Observation.Ready)/$($Observation.Total) Ready" @{ Total = $Observation.Total; Ready = $Observation.Ready }
}

function ConvertTo-LabHealthComponents {
    param([Parameter(Mandatory)] $Observations)
    Assert-LabHealthObservations $Observations | Out-Null
    $components = [ordered]@{}
    $components.Nodes = Get-LabHealthCountComponent Nodes $Observations.Nodes
    $components.Pods = Get-LabHealthCountComponent Pods $Observations.Pods

    $pvc = $Observations.PVCs
    if (-not $pvc.Available) { $components.PVCs = New-LabHealthComponent UNKNOWN 'PVC state could not be observed.' @{ Total = 0; Bound = 0 } }
    elseif (-not $pvc.Applicable) { $components.PVCs = New-LabHealthComponent NOT_APPLICABLE 'No current PVCs are applicable; this does not validate storage capability.' @{ Total = 0; Bound = 0 } }
    else {
        $status = if ($pvc.Total -gt 0 -and $pvc.Bound -eq $pvc.Total) { 'HEALTHY' } else { 'DEGRADED' }
        $components.PVCs = New-LabHealthComponent $status "$($pvc.Bound)/$($pvc.Total) Bound; PVC state is not functional storage validation." @{ Total = $pvc.Total; Bound = $pvc.Bound }
    }

    $services = $Observations.Services
    if (-not $services.Available) { $components.Services = New-LabHealthComponent UNKNOWN 'Service state or selector alignment could not be observed.' @{ Expected = $services.Expected; Observed = 0; SelectorAligned = 0 } }
    else {
        $status = if ($services.Expected -gt 0 -and $services.Observed -eq $services.Expected -and $services.SelectorAligned -eq $services.Expected) { 'HEALTHY' } else { 'DEGRADED' }
        $components.Services = New-LabHealthComponent $status "$($services.Observed)/$($services.Expected) present; $($services.SelectorAligned)/$($services.Expected) selectors aligned" @{ Expected = $services.Expected; Observed = $services.Observed; SelectorAligned = $services.SelectorAligned }
    }

    $endpoints = $Observations.Endpoints
    if (-not $endpoints.Available) { $components.Endpoints = New-LabHealthComponent UNKNOWN 'EndpointSlice state could not be observed reliably.' @{ Expected = $endpoints.Expected; ReadyServices = 0; ReadyEndpoints = 0 } }
    else {
        $status = if ($endpoints.Expected -gt 0 -and $endpoints.ReadyServices -eq $endpoints.Expected) { 'HEALTHY' } else { 'DEGRADED' }
        $components.Endpoints = New-LabHealthComponent $status "$($endpoints.ReadyServices)/$($endpoints.Expected) Services have Ready endpoints ($($endpoints.ReadyEndpoints) total)" @{ Expected = $endpoints.Expected; ReadyServices = $endpoints.ReadyServices; ReadyEndpoints = $endpoints.ReadyEndpoints }
    }

    $cilium = $Observations.Cilium
    if ($Observations.Profile -cne 'cilium') { $components.Cilium = New-LabHealthComponent NOT_APPLICABLE 'Managed Cilium is not expected by the selected profile.' @{ Expected = 0; Ready = 0; Version = $null } }
    elseif (-not $cilium.Available) { $components.Cilium = New-LabHealthComponent UNKNOWN 'Managed Cilium component readiness could not be observed.' @{ Expected = $cilium.Expected; Ready = 0; Version = $cilium.Version } }
    else {
        $status = if ($cilium.Expected -gt 0 -and $cilium.Ready -eq $cilium.Expected) { 'HEALTHY' } else { 'DEGRADED' }
        $components.Cilium = New-LabHealthComponent $status "$($cilium.Ready)/$($cilium.Expected) expected managed Cilium agents Ready" @{ Expected = $cilium.Expected; Ready = $cilium.Ready; Version = $cilium.Version }
    }

    $istio = $Observations.Istio
    if ($Observations.Profile -cne 'istio') { $components.Istio = New-LabHealthComponent NOT_APPLICABLE 'Managed Istio is not expected by the selected profile.' @{ ControlPlaneExpected = 0; ControlPlaneReady = 0; CniExpected = 0; CniReady = 0; Version = $null } }
    elseif (-not $istio.Available) { $components.Istio = New-LabHealthComponent UNKNOWN 'Managed Istio component readiness could not be observed.' @{ ControlPlaneExpected = $istio.ControlPlaneExpected; ControlPlaneReady = 0; CniExpected = $istio.CniExpected; CniReady = 0; Version = $istio.Version } }
    else {
        $healthy = $istio.ControlPlaneExpected -gt 0 -and $istio.ControlPlaneReady -eq $istio.ControlPlaneExpected -and $istio.CniExpected -gt 0 -and $istio.CniReady -eq $istio.CniExpected
        $components.Istio = New-LabHealthComponent $(if ($healthy) { 'HEALTHY' } else { 'DEGRADED' }) "$($istio.ControlPlaneReady)/$($istio.ControlPlaneExpected) managed control-plane instances and $($istio.CniReady)/$($istio.CniExpected) managed CNI agents Ready" @{ ControlPlaneExpected = $istio.ControlPlaneExpected; ControlPlaneReady = $istio.ControlPlaneReady; CniExpected = $istio.CniExpected; CniReady = $istio.CniReady; Version = $istio.Version }
    }
    [pscustomobject]$components
}

function Get-LabHealthOverall {
    param([Parameter(Mandatory)] $Components)
    $states = @($script:LabHealthComponentNames | ForEach-Object { $Components.$_.Status })
    if ('DEGRADED' -cin $states) { return 'DEGRADED' }
    if ('UNKNOWN' -cin $states) { return 'UNKNOWN' }
    'HEALTHY'
}

function Assert-LabHealthContract {
    param([Parameter(Mandatory)] $Health)
    Assert-LabHealthObjectKeys $Health @('ContractVersion', 'Overall', 'ObservedAt', 'Provider', 'Profile', 'Components') 'Lab Health'
    if (-not (Test-LabHealthInteger $Health.ContractVersion) -or $Health.ContractVersion -ne 1) { throw 'Lab Health ContractVersion must be 1.' }
    if ($Health.Overall -cnotin $script:LabHealthOverallStates) { throw "Lab Health Overall '$($Health.Overall)' is invalid." }
    $timestamp = [datetimeoffset]::MinValue
    if ($Health.ObservedAt -isnot [string] -or -not [datetimeoffset]::TryParseExact($Health.ObservedAt, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$timestamp)) { throw 'Lab Health ObservedAt must be a round-trip UTC timestamp.' }
    if ($timestamp.Offset -ne [timespan]::Zero) { throw 'Lab Health ObservedAt must be UTC.' }
    if ($Health.Provider -cne 'aks' -or $Health.Profile -cnotin @('minimal', 'cilium', 'istio')) { throw 'Lab Health provider or profile is unsupported.' }
    Assert-LabHealthObjectKeys $Health.Components $script:LabHealthComponentNames 'Lab Health.Components'
    $shapes = @{
        Nodes=@('Status','Summary','Total','Ready'); Pods=@('Status','Summary','Total','Ready'); PVCs=@('Status','Summary','Total','Bound')
        Services=@('Status','Summary','Expected','Observed','SelectorAligned'); Endpoints=@('Status','Summary','Expected','ReadyServices','ReadyEndpoints')
        Cilium=@('Status','Summary','Expected','Ready','Version'); Istio=@('Status','Summary','ControlPlaneExpected','ControlPlaneReady','CniExpected','CniReady','Version')
    }
    foreach ($name in $script:LabHealthComponentNames) {
        $component = $Health.Components.$name
        Assert-LabHealthObjectKeys $component $shapes[$name] "Lab Health.Components.$name"
        if ($component.Status -cnotin $script:LabHealthComponentStates) { throw "Lab Health.Components.$name.Status is invalid." }
        Assert-LabHealthString $component.Summary "Lab Health.Components.$name.Summary"
        foreach ($field in @($shapes[$name] | Where-Object { $_ -notin @('Status', 'Summary', 'Version') })) {
            Assert-LabHealthCount $component.$field "Lab Health.Components.$name.$field"
        }
        if ('Version' -in $shapes[$name]) { Assert-LabHealthString $component.Version "Lab Health.Components.$name.Version" -AllowNull }
    }
    $expectedOverall = Get-LabHealthOverall $Health.Components
    if ($Health.Overall -cne $expectedOverall) { throw "Lab Health Overall '$($Health.Overall)' is inconsistent with component precedence '$expectedOverall'." }
    $Health
}

function New-LabHealthContract {
    param([Parameter(Mandatory)] $Observations, [datetimeoffset] $ObservedAt = [datetimeoffset]::UtcNow)
    Assert-LabHealthObservations $Observations | Out-Null
    $components = ConvertTo-LabHealthComponents $Observations
    $health = [pscustomobject][ordered]@{
        ContractVersion = 1
        Overall = Get-LabHealthOverall $components
        ObservedAt = $ObservedAt.ToUniversalTime().ToString('o')
        Provider = $Observations.Provider
        Profile = $Observations.Profile
        Components = $components
    }
    Assert-LabHealthContract $health
}

function ConvertTo-LabHealthJson {
    param([Parameter(Mandatory)] $Health)
    (Assert-LabHealthContract $Health) | ConvertTo-Json -Depth 8
}

function Read-LabHealthContract {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Lab Health document does not exist.' }
    try { $health = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -DateKind String }
    catch { throw 'Lab Health document contains malformed JSON.' }
    Assert-LabHealthContract $health
}

function Get-LabHealthReadyEndpointCount {
    param([Parameter(Mandatory)] $EndpointSliceList)
    if (-not ($EndpointSliceList.psobject.Properties.Name -contains 'items') -or $null -eq $EndpointSliceList.items) { throw 'EndpointSlice list has no items collection.' }
    $count = 0
    foreach ($slice in @($EndpointSliceList.items)) {
        if ($null -eq $slice) { throw 'EndpointSlice list contains a null item.' }
        if (-not ($slice.psobject.Properties.Name -contains 'endpoints') -or $null -eq $slice.endpoints) { continue }
        foreach ($endpoint in @($slice.endpoints)) {
            if ($null -eq $endpoint) { continue }
            $conditions = if ($endpoint.psobject.Properties.Name -contains 'conditions') { $endpoint.conditions } else { $null }
            if ($null -ne $conditions -and $conditions.psobject.Properties.Name -contains 'ready' -and $conditions.ready -eq $true) { $count++ }
        }
    }
    $count
}

function Invoke-LabHealthKubectlJson {
    param([string[]] $Arguments)
    $output = & kubectl @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Kubernetes observation failed.' }
    try { ($output -join [Environment]::NewLine) | ConvertFrom-Json }
    catch { throw 'Kubernetes observation returned malformed JSON.' }
}

function Get-LabHealthListObservation {
    param([string] $Resource, [scriptblock] $KubectlInvoker)
    try {
        $list = & $KubectlInvoker @('get', $Resource, '--all-namespaces', '-o', 'json')
        if ($null -eq $list -or -not ($list.psobject.Properties.Name -contains 'items') -or $null -eq $list.items) { throw 'Invalid list.' }
        [pscustomobject]@{ Available = $true; Items = @($list.items) }
    }
    catch { [pscustomobject]@{ Available = $false; Items = @() } }
}

function Test-LabHealthLabelsMatch {
    param($Selector, $Labels)
    if ($null -eq $Selector -or $null -eq $Labels) { return $false }
    $selectorFields = @($Selector.psobject.Properties)
    if ($selectorFields.Count -eq 0) { return $false }
    foreach ($field in $selectorFields) {
        $label = $Labels.psobject.Properties[$field.Name]
        if ($null -eq $label -or [string]$label.Value -cne [string]$field.Value) { return $false }
    }
    $true
}

function Get-LabHealthPropertyValue {
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.psobject.Properties[$Name]
    if ($null -eq $property) { return $null }
    $property.Value
}

function Get-AksLabHealthObservations {
    param(
        [Parameter(Mandatory)][string] $Profile,
        [scriptblock] $KubectlInvoker = ${function:Invoke-LabHealthKubectlJson},
        [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
    )
    $profileRoot = Join-Path $RepositoryRoot 'providers/azure/aks'
    . (Join-Path $profileRoot 'scripts/Profile-Aks.ps1')
    $resolvedProfile = Resolve-AksProfile -Provider aks -ProfileName $Profile -ProfilesRoot (Join-Path $profileRoot 'profiles')
    $nodes = Get-LabHealthListObservation nodes $KubectlInvoker
    $pods = Get-LabHealthListObservation pods $KubectlInvoker
    $pvcs = Get-LabHealthListObservation persistentvolumeclaims $KubectlInvoker
    $services = Get-LabHealthListObservation services $KubectlInvoker
    $slices = Get-LabHealthListObservation endpointslices.discovery.k8s.io $KubectlInvoker
    $daemonSets = Get-LabHealthListObservation daemonsets.apps $KubectlInvoker
    $deployments = Get-LabHealthListObservation deployments.apps $KubectlInvoker

    $nodeTotal = $nodes.Items.Count
    $nodeReady = @($nodes.Items | Where-Object { @($_.status.conditions | Where-Object { $_.type -ceq 'Ready' -and $_.status -ceq 'True' }).Count -eq 1 }).Count
    $currentPods = @($pods.Items | Where-Object { $null -eq (Get-LabHealthPropertyValue $_.metadata 'deletionTimestamp') -and (Get-LabHealthPropertyValue $_.status 'phase') -cne 'Succeeded' })
    $readyPods = @($currentPods | Where-Object {
        (Get-LabHealthPropertyValue $_.status 'phase') -ceq 'Running' -and @(Get-LabHealthPropertyValue $_.status 'containerStatuses').Count -gt 0 -and @(@(Get-LabHealthPropertyValue $_.status 'containerStatuses') | Where-Object { $_.ready -ne $true }).Count -eq 0
    }).Count
    $pvcTotal = $pvcs.Items.Count
    $pvcBound = @($pvcs.Items | Where-Object { (Get-LabHealthPropertyValue $_.status 'phase') -ceq 'Bound' }).Count

    $expectedServices = @(
        @{ Namespace='platform'; Name='nginx' }, @{ Namespace='platform'; Name='podinfo' }, @{ Namespace='platform'; Name='whoami' }
    )
    $scenarioPresent = @($pods.Items | Where-Object { $_.metadata.namespace -ceq 'platform-breakfix-scenario' }).Count -gt 0 -or @($services.Items | Where-Object { $_.metadata.namespace -ceq 'platform-breakfix-scenario' }).Count -gt 0
    if ($scenarioPresent) { $expectedServices += @{ Namespace='platform-breakfix-scenario'; Name='scenario-destination' } }
    if ($Profile -ceq 'cilium') { $expectedServices += @{ Namespace='platform-breakfix-cilium'; Name='policy-destination' } }
    if ($Profile -ceq 'istio') { $expectedServices += @{ Namespace='platform-breakfix-istio'; Name='mesh-destination' } }
    $observedServices = 0; $alignedServices = 0; $readyServices = 0; $readyEndpoints = 0; $endpointValid = $slices.Available
    if ($services.Available -and $pods.Available) {
        foreach ($expected in $expectedServices) {
            $service = @($services.Items | Where-Object { $_.metadata.namespace -ceq $expected.Namespace -and $_.metadata.name -ceq $expected.Name }) | Select-Object -First 1
            if ($service) {
                $observedServices++
                $candidatePods = @($currentPods | Where-Object { $_.metadata.namespace -ceq $expected.Namespace })
                if (@($candidatePods | Where-Object { Test-LabHealthLabelsMatch (Get-LabHealthPropertyValue $service.spec 'selector') (Get-LabHealthPropertyValue $_.metadata 'labels') }).Count -gt 0) { $alignedServices++ }
                if ($slices.Available) {
                    try {
                        $serviceSlices = @($slices.Items | Where-Object { $_.metadata.namespace -ceq $expected.Namespace -and (Get-LabHealthPropertyValue (Get-LabHealthPropertyValue $_.metadata 'labels') 'kubernetes.io/service-name') -ceq $expected.Name })
                        $count = Get-LabHealthReadyEndpointCount ([pscustomobject]@{ items = $serviceSlices })
                        $readyEndpoints += $count
                        if ($count -gt 0) { $readyServices++ }
                    }
                    catch { $endpointValid = $false }
                }
            }
        }
    }

    $ciliumExpected = if ($nodes.Available) { $nodeTotal } else { 0 }; $ciliumReady = 0
    if ($Profile -ceq 'cilium' -and $daemonSets.Available -and $pods.Available -and $nodes.Available) {
        $ciliumSet = @($daemonSets.Items | Where-Object { $_.metadata.namespace -ceq 'kube-system' -and $_.metadata.name -ceq 'cilium' }) | Select-Object -First 1
        $healthyAgents = @($currentPods | Where-Object {
            $_.metadata.namespace -ceq 'kube-system' -and (Get-LabHealthPropertyValue (Get-LabHealthPropertyValue $_.metadata 'labels') 'k8s-app') -ceq 'cilium' -and (Get-LabHealthPropertyValue $_.status 'phase') -ceq 'Running' -and
            @(Get-LabHealthPropertyValue $_.status 'containerStatuses').Count -gt 0 -and @((Get-LabHealthPropertyValue $_.status 'containerStatuses') | Where-Object { $_.ready -ne $true }).Count -eq 0
        }).Count
        if ($ciliumSet) { $ciliumReady = [math]::Min([int](Get-LabHealthPropertyValue $ciliumSet.status 'numberReady'), $healthyAgents) }
    }

    $istioControlExpected = 1; $istioControlReady = 0; $istioCniExpected = if ($nodes.Available) { $nodeTotal } else { 0 }; $istioCniReady = 0
    if ($Profile -ceq 'istio' -and $deployments.Available -and $daemonSets.Available -and $pods.Available -and $nodes.Available) {
        $controlDeployments = @($deployments.Items | Where-Object { $_.metadata.namespace -ceq 'aks-istio-system' -and (Get-LabHealthPropertyValue (Get-LabHealthPropertyValue $_.metadata 'labels') 'app') -ceq 'istiod' })
        if ($controlDeployments.Count -gt 0) { $istioControlExpected = @($controlDeployments | ForEach-Object { [int](Get-LabHealthPropertyValue $_.spec 'replicas') } | Measure-Object -Sum).Sum }
        $istioControlReady = @($currentPods | Where-Object {
            $_.metadata.namespace -ceq 'aks-istio-system' -and (Get-LabHealthPropertyValue (Get-LabHealthPropertyValue $_.metadata 'labels') 'app') -ceq 'istiod' -and (Get-LabHealthPropertyValue $_.status 'phase') -ceq 'Running' -and
            @(Get-LabHealthPropertyValue $_.status 'containerStatuses').Count -gt 0 -and @((Get-LabHealthPropertyValue $_.status 'containerStatuses') | Where-Object { $_.ready -ne $true }).Count -eq 0
        }).Count
        $cniSet = @($daemonSets.Items | Where-Object { $_.metadata.namespace -ceq 'aks-istio-system' -and $_.metadata.name -match 'istio-cni' }) | Select-Object -First 1
        if ($cniSet) { $istioCniReady = [int](Get-LabHealthPropertyValue $cniSet.status 'numberReady') }
    }

    [pscustomobject][ordered]@{
        Provider='aks'; Profile=$resolvedProfile.Name
        Nodes=[pscustomobject]@{ Available=$nodes.Available; Total=$nodeTotal; Ready=$nodeReady }
        Pods=[pscustomobject]@{ Available=$pods.Available; Total=$currentPods.Count; Ready=$readyPods }
        PVCs=[pscustomobject]@{ Available=$pvcs.Available; Applicable=($pvcTotal -gt 0); Total=$pvcTotal; Bound=$pvcBound }
        Services=[pscustomobject]@{ Available=($services.Available -and $pods.Available); Expected=$expectedServices.Count; Observed=$observedServices; SelectorAligned=$alignedServices }
        Endpoints=[pscustomobject]@{ Available=($services.Available -and $endpointValid); Expected=$expectedServices.Count; ReadyServices=$readyServices; ReadyEndpoints=$readyEndpoints }
        Cilium=[pscustomobject]@{ Available=($daemonSets.Available -and $pods.Available -and $nodes.Available); Expected=$ciliumExpected; Ready=$ciliumReady; Version=$null }
        Istio=[pscustomobject]@{ Available=($deployments.Available -and $daemonSets.Available -and $pods.Available -and $nodes.Available); ControlPlaneExpected=$istioControlExpected; ControlPlaneReady=$istioControlReady; CniExpected=$istioCniExpected; CniReady=$istioCniReady; Version=$(if ($Profile -ceq 'istio') { $resolvedProfile.InfrastructureInputs.IstioRevision } else { $null }) }
    }
}

function Get-AksLabHealth {
    param([Parameter(Mandatory)][string] $Profile, [scriptblock] $KubectlInvoker = ${function:Invoke-LabHealthKubectlJson})
    New-LabHealthContract -Observations (Get-AksLabHealthObservations -Profile $Profile -KubectlInvoker $KubectlInvoker)
}

function Get-EksLabHealth {
    throw 'EKS passive Lab Health collection is unsupported in Contract v1.'
}
