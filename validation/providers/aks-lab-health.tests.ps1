$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repositoryRoot 'scripts/LabHealth.ps1')

function Assert-True([bool] $Value, [string] $Message) { if (-not $Value) { throw $Message } }
function Assert-Fails([string] $Name, [scriptblock] $Action) {
    try { & $Action | Out-Null } catch { Write-Host "PASS: $Name fails closed." -ForegroundColor Green; return }
    throw "$Name unexpectedly succeeded."
}
function Copy-Value($Value) { ($Value | ConvertTo-Json -Depth 12) | ConvertFrom-Json }
function New-HealthObservations([string] $Profile = 'minimal') {
    [pscustomobject][ordered]@{
        Provider='aks'; Profile=$Profile
        Nodes=[pscustomobject]@{ Available=$true; Total=1; Ready=1 }
        Pods=[pscustomobject]@{ Available=$true; Total=6; Ready=6 }
        PVCs=[pscustomobject]@{ Available=$true; Applicable=$false; Total=0; Bound=0 }
        Services=[pscustomobject]@{ Available=$true; Expected=3; Observed=3; SelectorAligned=3 }
        Endpoints=[pscustomobject]@{ Available=$true; Expected=3; ReadyServices=3; ReadyEndpoints=3 }
        Cilium=[pscustomobject]@{ Available=$true; Expected=$(if($Profile -ceq 'cilium'){1}else{0}); Ready=$(if($Profile -ceq 'cilium'){1}else{0}); Version=$null }
        Istio=[pscustomobject]@{ Available=$true; ControlPlaneExpected=$(if($Profile -ceq 'istio'){1}else{0}); ControlPlaneReady=$(if($Profile -ceq 'istio'){1}else{0}); CniExpected=$(if($Profile -ceq 'istio'){1}else{0}); CniReady=$(if($Profile -ceq 'istio'){1}else{0}); Version=$(if($Profile -ceq 'istio'){'asm-1-30'}else{$null}) }
    }
}

Assert-True ($script:LabHealthContractVersion -eq 1) 'Lab Health Contract version changed.'
Assert-True ((@($script:LabHealthOverallStates) -join ',') -ceq 'HEALTHY,DEGRADED,UNKNOWN') 'Overall state allowlist changed.'
Assert-True ((@($script:LabHealthComponentStates) -join ',') -ceq 'HEALTHY,DEGRADED,UNKNOWN,NOT_APPLICABLE') 'Component state allowlist changed.'
Assert-True ((@($script:LabHealthComponentNames) -join ',') -ceq 'Nodes,Pods,PVCs,Services,Endpoints,Cilium,Istio') 'Component allowlist changed.'
Assert-True ('DNS' -cnotin $script:LabHealthComponentNames -and 'Storage' -cnotin $script:LabHealthComponentNames) 'DNS or Storage entered passive health.'

$healthy = New-LabHealthContract (New-HealthObservations) ([datetimeoffset]'2026-01-01T00:00:00Z')
Assert-True ($healthy.ContractVersion -eq 1 -and $healthy.Overall -ceq 'HEALTHY') 'Healthy document failed.'
Assert-True ($healthy.Components.PVCs.Status -ceq 'NOT_APPLICABLE' -and $healthy.Components.Cilium.Status -ceq 'NOT_APPLICABLE' -and $healthy.Components.Istio.Status -ceq 'NOT_APPLICABLE') 'Optional applicability failed.'
Assert-True ($healthy.Components.PVCs.Summary -match 'does not validate storage capability') 'PVC terminology could be mistaken for storage validation.'

$runtime = Join-Path $repositoryRoot '.runtime/lab-health-tests'
try {
    [IO.Directory]::CreateDirectory($runtime) | Out-Null
    $validPath = Join-Path $runtime 'valid.json'; [IO.File]::WriteAllText($validPath, (ConvertTo-LabHealthJson $healthy), [Text.UTF8Encoding]::new($false))
    $roundTrip = Read-LabHealthContract $validPath
    Assert-True ($roundTrip.Overall -ceq 'HEALTHY') 'Valid health JSON round-trip failed.'
    $badPath = Join-Path $runtime 'bad.json'; [IO.File]::WriteAllText($badPath, '{', [Text.UTF8Encoding]::new($false))
    Assert-Fails 'Malformed health JSON' { Read-LabHealthContract $badPath }
}
finally { if (Test-Path $runtime) { Remove-Item $runtime -Recurse -Force } }

$invalid = Copy-Value $healthy; $invalid | Add-Member Extra nope
Assert-Fails 'Unknown contract field' { Assert-LabHealthContract $invalid }
$invalid = Copy-Value $healthy; $invalid.Components | Add-Member DNS ([pscustomobject]@{Status='HEALTHY';Summary='nope'})
Assert-Fails 'Unknown DNS component' { Assert-LabHealthContract $invalid }
$invalid = Copy-Value $healthy; $invalid.Components | Add-Member Storage ([pscustomobject]@{Status='HEALTHY';Summary='nope'})
Assert-Fails 'Unknown Storage component' { Assert-LabHealthContract $invalid }
$invalid = Copy-Value $healthy; $invalid.Components.psobject.Properties.Remove('Nodes')
Assert-Fails 'Missing component' { Assert-LabHealthContract $invalid }
$invalid = Copy-Value $healthy; $invalid.Components.Nodes.Status='WARNING'
Assert-Fails 'Invalid component status' { Assert-LabHealthContract $invalid }
$invalid = Copy-Value $healthy; $invalid.ObservedAt='yesterday'
Assert-Fails 'Invalid observed timestamp' { Assert-LabHealthContract $invalid }
$invalid = Copy-Value $healthy; $invalid.Provider='eks'
Assert-Fails 'Unsupported health provider' { Assert-LabHealthContract $invalid }
$invalid = Copy-Value $healthy; $invalid.Profile='unknown'
Assert-Fails 'Unsupported health profile' { Assert-LabHealthContract $invalid }
$invalid = Copy-Value $healthy; $invalid.Components.Nodes.Ready='1'
Assert-Fails 'Invalid numeric fact type' { Assert-LabHealthContract $invalid }

$unknownObs = New-HealthObservations; $unknownObs.Nodes.Available=$false; $unknownObs.Nodes.Total=0; $unknownObs.Nodes.Ready=0
$unknown = New-LabHealthContract $unknownObs
Assert-True ($unknown.Overall -ceq 'UNKNOWN') 'Required UNKNOWN did not aggregate to UNKNOWN.'
$degradedObs = New-HealthObservations; $degradedObs.Nodes.Ready=0
$degraded = New-LabHealthContract $degradedObs
Assert-True ($degraded.Overall -ceq 'DEGRADED') 'One DEGRADED did not aggregate to DEGRADED.'
$degradedObs.Pods.Ready=5
Assert-True ((New-LabHealthContract $degradedObs).Overall -ceq 'DEGRADED') 'Multiple DEGRADED aggregation failed.'
$degradedObs.Services.Available=$false
Assert-True ((New-LabHealthContract $degradedObs).Overall -ceq 'DEGRADED') 'DEGRADED did not take precedence over UNKNOWN.'
Assert-True ((New-LabHealthContract (New-HealthObservations)).Overall -ceq 'HEALTHY') 'NOT_APPLICABLE degraded overall health.'

$obs=New-HealthObservations;$obs.Nodes.Total=3;$obs.Nodes.Ready=3;Assert-True ((New-LabHealthContract $obs).Components.Nodes.Status -ceq 'HEALTHY') 'All Ready nodes failed.'
$obs.Nodes.Ready=2;Assert-True ((New-LabHealthContract $obs).Components.Nodes.Status -ceq 'DEGRADED') 'NotReady node failed.'
$obs.Nodes.Total=0;$obs.Nodes.Ready=0;Assert-True ((New-LabHealthContract $obs).Components.Nodes.Status -ceq 'DEGRADED') 'Zero observed nodes did not degrade.'
$obs.Nodes.Available=$false;Assert-True ((New-LabHealthContract $obs).Components.Nodes.Status -ceq 'UNKNOWN') 'Node observation failure did not become UNKNOWN.'

$obs=New-HealthObservations;$obs.Pods.Ready=5;Assert-True ((New-LabHealthContract $obs).Components.Pods.Status -ceq 'DEGRADED') 'Running not-Ready Pod did not degrade.'
$obs.Pods.Ready=4;Assert-True ((New-LabHealthContract $obs).Components.Pods.Status -ceq 'DEGRADED') 'Pending/Failed Pod count did not degrade.'
$obs.Pods.Available=$false;$obs.Pods.Total=0;$obs.Pods.Ready=0;Assert-True ((New-LabHealthContract $obs).Components.Pods.Status -ceq 'UNKNOWN') 'Pod observation failure did not become UNKNOWN.'
$malformed=New-HealthObservations;$malformed.Pods.Ready=7;Assert-Fails 'Malformed Pod counts' { New-LabHealthContract $malformed }

$obs=New-HealthObservations;$obs.PVCs.Applicable=$true;$obs.PVCs.Total=2;$obs.PVCs.Bound=2;$pvcHealth=(New-LabHealthContract $obs).Components.PVCs;Assert-True ($pvcHealth.Status -ceq 'HEALTHY') 'Bound PVC state failed.';Assert-True ($pvcHealth.Summary -match 'not functional storage validation') 'Healthy PVC state implied functional storage health.'
$obs.PVCs.Bound=1;Assert-True ((New-LabHealthContract $obs).Components.PVCs.Status -ceq 'DEGRADED') 'Unbound PVC did not degrade.'
$obs.PVCs.Available=$false;Assert-True ((New-LabHealthContract $obs).Components.PVCs.Status -ceq 'UNKNOWN') 'PVC observation failure did not become UNKNOWN.'

$obs=New-HealthObservations;$obs.Services.SelectorAligned=2;Assert-True ((New-LabHealthContract $obs).Components.Services.Status -ceq 'DEGRADED') 'Selector mismatch did not degrade Services.'
$obs=New-HealthObservations;$obs.Services.Observed=2;$obs.Services.SelectorAligned=2;Assert-True ((New-LabHealthContract $obs).Components.Services.Status -ceq 'DEGRADED') 'Missing Service did not degrade.'
$obs.Services.Available=$false;Assert-True ((New-LabHealthContract $obs).Components.Services.Status -ceq 'UNKNOWN') 'Service observation failure did not become UNKNOWN.'
$obs=New-HealthObservations;$obs.Endpoints.ReadyServices=2;$obs.Endpoints.ReadyEndpoints=2;Assert-True ((New-LabHealthContract $obs).Components.Endpoints.Status -ceq 'DEGRADED') 'Zero-ready Service endpoints did not degrade.'
$obs.Endpoints.Available=$false;Assert-True ((New-LabHealthContract $obs).Components.Endpoints.Status -ceq 'UNKNOWN') 'Endpoint observation failure did not become UNKNOWN.'
Assert-True ((Get-LabHealthReadyEndpointCount ([pscustomobject]@{items=@([pscustomobject]@{endpoints=@([pscustomobject]@{conditions=[pscustomobject]@{ready=$true}},[pscustomobject]@{conditions=[pscustomobject]@{ready=$false}})})})) -eq 1) 'EndpointSlice ready semantics changed.'
Assert-Fails 'Malformed EndpointSlice' { Get-LabHealthReadyEndpointCount ([pscustomobject]@{}) }

$cilium=New-HealthObservations cilium;Assert-True ((New-LabHealthContract $cilium).Components.Cilium.Status -ceq 'HEALTHY') 'Healthy Cilium failed.'
$cilium.Cilium.Ready=0;Assert-True ((New-LabHealthContract $cilium).Components.Cilium.Status -ceq 'DEGRADED') 'Unhealthy/missing Cilium did not degrade.'
$cilium.Cilium.Available=$false;Assert-True ((New-LabHealthContract $cilium).Components.Cilium.Status -ceq 'UNKNOWN') 'Unavailable Cilium did not become UNKNOWN.'
$istio=New-HealthObservations istio;Assert-True ((New-LabHealthContract $istio).Components.Istio.Status -ceq 'HEALTHY') 'Healthy Istio failed.'
$istio.Istio.CniReady=0;Assert-True ((New-LabHealthContract $istio).Components.Istio.Status -ceq 'DEGRADED') 'Unhealthy/missing Istio did not degrade.'
$istio.Istio.Available=$false;Assert-True ((New-LabHealthContract $istio).Components.Istio.Status -ceq 'UNKNOWN') 'Unavailable Istio did not become UNKNOWN.'

$baselineObs=New-HealthObservations;$baseline=New-LabHealthContract $baselineObs
$readinessObs=Copy-Value $baselineObs;$readinessObs.Pods.Ready=5;$readinessObs.Endpoints.ReadyServices=2;$readinessObs.Endpoints.ReadyEndpoints=2;$readiness=New-LabHealthContract $readinessObs
Assert-True ($readiness.Overall -ceq 'DEGRADED' -and $readiness.Components.Pods.Status -ceq 'DEGRADED' -and $readiness.Components.Services.Status -ceq 'HEALTHY' -and $readiness.Components.Endpoints.Status -ceq 'DEGRADED') 'Readiness fixture pattern failed.'
$selectorObs=Copy-Value $baselineObs;$selectorObs.Services.SelectorAligned=2;$selectorObs.Endpoints.ReadyServices=2;$selectorObs.Endpoints.ReadyEndpoints=2;$selector=New-LabHealthContract $selectorObs
Assert-True ($selector.Overall -ceq 'DEGRADED' -and $selector.Components.Pods.Status -ceq 'HEALTHY' -and $selector.Components.Services.Status -ceq 'DEGRADED' -and $selector.Components.Endpoints.Status -ceq 'DEGRADED') 'Selector fixture pattern failed.'
$withMetadata=[pscustomobject]@{Scenario='any-valid-name';Observations=$readinessObs};$withoutMetadata=[pscustomobject]@{Observations=(Copy-Value $readinessObs)}
Assert-True ((ConvertTo-LabHealthJson (New-LabHealthContract $withMetadata.Observations ([datetimeoffset]'2026-01-01T00:00:00Z'))) -ceq (ConvertTo-LabHealthJson (New-LabHealthContract $withoutMetadata.Observations ([datetimeoffset]'2026-01-01T00:00:00Z')))) 'Scenario metadata influenced health.'
$scenarioField=Copy-Value $baselineObs;$scenarioField|Add-Member Scenario 'readiness-probe-failure';Assert-Fails 'Scenario field in classifier input' { New-LabHealthContract $scenarioField }

function New-Pod($Namespace,$Name,$Phase,$Ready,$App,$DeletionTimestamp=$null) {
    $metadata=[pscustomobject]@{namespace=$Namespace;name=$Name;labels=[pscustomobject]@{app=$App}}
    if($null-ne $DeletionTimestamp){$metadata|Add-Member deletionTimestamp $DeletionTimestamp}
    [pscustomobject]@{metadata=$metadata;status=[pscustomobject]@{phase=$Phase;containerStatuses=@([pscustomobject]@{ready=$Ready})}}
}
function New-Service($Name,$App) { [pscustomobject]@{metadata=[pscustomobject]@{namespace='platform';name=$Name};spec=[pscustomobject]@{selector=[pscustomobject]@{app=$App}}} }
function New-Slice($Name,$Ready) { [pscustomobject]@{metadata=[pscustomobject]@{namespace='platform';labels=[pscustomobject]@{'kubernetes.io/service-name'=$Name}};endpoints=@([pscustomobject]@{conditions=[pscustomobject]@{ready=$Ready}})} }
$script:healthLists=@{
    nodes=@([pscustomobject]@{metadata=[pscustomobject]@{name='node-1'};status=[pscustomobject]@{conditions=@([pscustomobject]@{type='Ready';status='True'})}})
    pods=@(New-Pod platform nginx Running $true nginx;New-Pod platform podinfo Running $true podinfo;New-Pod platform whoami Running $true whoami;New-Pod diagnostics curl Running $true curl;New-Pod platform completed Succeeded $false completed;New-Pod platform deleting Running $false stale '2026-01-01T00:00:00Z')
    persistentvolumeclaims=@()
    services=@(New-Service nginx nginx;New-Service podinfo podinfo;New-Service whoami whoami)
    'endpointslices.discovery.k8s.io'=@(New-Slice nginx $true;New-Slice podinfo $true;New-Slice whoami $true)
    'daemonsets.apps'=@();'deployments.apps'=@()
}
$invoker={param([string[]]$Arguments)[pscustomobject]@{items=@($script:healthLists[$Arguments[1]])}}
$collected=Get-AksLabHealthObservations -Profile minimal -KubectlInvoker $invoker -RepositoryRoot $repositoryRoot
Assert-True ($collected.Pods.Total -eq 4 -and $collected.Pods.Ready -eq 4) 'Collector counted completed or deleting historical Pods.'
Assert-True ((New-LabHealthContract $collected).Overall -ceq 'HEALTHY') 'Mocked AKS passive collection was not healthy.'
$healthyPods=@($script:healthLists.pods)
foreach($phaseCase in @(@{Phase='Running';Ready=$false;Name='not-ready'},@{Phase='Pending';Ready=$false;Name='pending'},@{Phase='Failed';Ready=$false;Name='failed'})) {
    $script:healthLists.pods=@($healthyPods)+(New-Pod platform $phaseCase.Name $phaseCase.Phase $phaseCase.Ready $phaseCase.Name)
    $podHealth=New-LabHealthContract (Get-AksLabHealthObservations -Profile minimal -KubectlInvoker $invoker -RepositoryRoot $repositoryRoot)
    Assert-True ($podHealth.Components.Pods.Status -ceq 'DEGRADED') "Current $($phaseCase.Phase)/Ready=$($phaseCase.Ready) Pod did not degrade passive Pod health."
}
$script:healthLists.pods=$healthyPods
$script:healthLists['endpointslices.discovery.k8s.io']=@($null)
$collected=Get-AksLabHealthObservations -Profile minimal -KubectlInvoker $invoker -RepositoryRoot $repositoryRoot
Assert-True (-not $collected.Endpoints.Available -and (New-LabHealthContract $collected).Components.Endpoints.Status -ceq 'UNKNOWN') 'Malformed EndpointSlice did not fail closed.'

$healthSource=Get-Content -Raw (Join-Path $repositoryRoot 'scripts/LabHealth.ps1')
foreach($term in @("'exec'",'pods/exec',"'apply'", "'patch'", "'delete'", "'rollout'",'get-credentials','update-kubeconfig','Resolve-ScenarioDiagnosis','readiness_probe_failure','service_selector_mismatch')) { Assert-True ($healthSource -notmatch [regex]::Escape($term)) "Health source contains forbidden dependency or mutation '$term'." }
$operationsSource=Get-Content -Raw (Join-Path $repositoryRoot 'scripts/BreakfixOperations.ps1')
Assert-True ($operationsSource -match 'get_lab_health') 'M15 get_lab_health operation is missing.'
. (Join-Path $repositoryRoot 'scripts/BreakfixOperations.ps1')
Assert-True ((@($script:BreakfixPublicOperations|Sort-Object) -join ',') -ceq 'diagnose_evidence,get_lab_status,list_profiles,list_scenarios,read_evidence') 'M12 five-operation allowlist changed.'
Assert-Fails 'EKS health unsupported' { Get-EksLabHealth }

Write-Host 'PASS: Lab Health Contract v1 deterministic tests.' -ForegroundColor Green
