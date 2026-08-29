[CmdletBinding()]
param([Parameter(Mandatory)][hashtable] $Config)

$namespace = 'platform-breakfix-istio'
$denyPolicy = Join-Path $PSScriptRoot 'deny-destination.yaml'
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'profile.psd1')
$expectedRevision = [string]$manifest.InfrastructureInputs.IstioRevision

function Invoke-IstioHttpProbe {
    param([Parameter(Mandatory)][string] $ServiceIp, [Parameter(Mandatory)][string] $ExpectedCode)
    $lastResult = ''
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $lastResult = Invoke-Kubectl -Arguments @(
            'exec', '-n', $namespace, 'deployment/mesh-source', '-c', 'curl', '--',
            'curl', '--silent', '--show-error', '--connect-timeout', '2', '--max-time', '5',
            '--output', '/dev/null', '--write-out', 'HTTP %{http_code}', "http://$ServiceIp"
        ) -Capture
        $lastResult = $lastResult.Trim()
        if ($lastResult -ceq "HTTP $ExpectedCode") { return $lastResult }
        if ($attempt -lt 12) { Start-Sleep -Seconds 2 }
    }
    Stop-ValidationFailure "Expected Istio HTTP result 'HTTP $ExpectedCode'; received '$lastResult'."
}

try {
    $clusterResult = & az aks show --resource-group $Config.ResourceGroup --name $Config.ClusterName --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Stop-ValidationFailure "Could not inspect the AKS service mesh profile: $($clusterResult -join [Environment]::NewLine)"
    }
    $cluster = ($clusterResult -join [Environment]::NewLine) | ConvertFrom-Json
    $meshMode = [string]$cluster.serviceMeshProfile.mode
    $installedRevisions = @($cluster.serviceMeshProfile.istio.revisions)
    if ($meshMode -cne 'Istio' -or $installedRevisions.Count -ne 1 -or $installedRevisions[0] -cne $expectedRevision) {
        Stop-ValidationFailure "Expected managed Istio revision '$expectedRevision'; Azure reports mode '$meshMode' and revisions '$($installedRevisions -join ', ')'."
    }
    Write-ValidationPass "Azure reports managed Istio mode with revision '$expectedRevision'."

    $redirection = [string]$cluster.serviceMeshProfile.istio.components.proxyRedirectionMechanism
    if ($redirection -cne 'CNIChaining') {
        Stop-ValidationFailure "Expected Istio proxy redirection mechanism 'CNIChaining'; Azure reports '$redirection'."
    }
    Write-ValidationPass "Azure reports Istio proxy redirection mechanism '$redirection'."

    $controlPlane = (Invoke-Kubectl -Arguments @('get', 'deployment', '-n', 'aks-istio-system', '-l', 'app=istiod', '-o', 'json') -Capture) | ConvertFrom-Json
    if (@($controlPlane.items).Count -lt 1) {
        Stop-ValidationFailure 'No managed istiod deployment was discovered in aks-istio-system.'
    }
    foreach ($deployment in $controlPlane.items) {
        Invoke-Kubectl -Arguments @('rollout', 'status', "deployment/$($deployment.metadata.name)", '-n', 'aks-istio-system', '--timeout=180s')
        $nativeSetting = @($deployment.spec.template.spec.containers | ForEach-Object { $_.env } | Where-Object { $_.name -eq 'ENABLE_NATIVE_SIDECARS' })
        if ($nativeSetting.Count -lt 1 -or $nativeSetting[0].value -cne 'true') {
            Stop-ValidationFailure "Managed istiod deployment '$($deployment.metadata.name)' does not report native sidecars enabled."
        }
    }
    $istiodPods = (Invoke-Kubectl -Arguments @('get', 'pods', '-n', 'aks-istio-system', '-l', 'app=istiod', '-o', 'json') -Capture) | ConvertFrom-Json
    if (@($istiodPods.items).Count -lt 1) { Stop-ValidationFailure 'No managed istiod pods were discovered.' }
    foreach ($pod in $istiodPods.items) {
        if ($pod.status.phase -ne 'Running' -or @($pod.status.containerStatuses | Where-Object { -not $_.ready }).Count -gt 0) {
            Stop-ValidationFailure "Managed Istio control-plane pod '$($pod.metadata.name)' is not Ready."
        }
    }
    Write-ValidationPass "$(@($istiodPods.items).Count) managed Istio control-plane pod(s) are healthy with native sidecars enabled."

    $cniSets = (Invoke-Kubectl -Arguments @('get', 'daemonset', '-n', 'aks-istio-system', '-o', 'json') -Capture) | ConvertFrom-Json
    $cniSet = @($cniSets.items | Where-Object { $_.metadata.name -match 'istio-cni' })
    if ($cniSet.Count -ne 1 -or
        $cniSet[0].status.desiredNumberScheduled -ne $Config.ExpectedNodeCount -or
        $cniSet[0].status.numberReady -ne $Config.ExpectedNodeCount -or
        $cniSet[0].status.numberAvailable -ne $Config.ExpectedNodeCount) {
        Stop-ValidationFailure 'The managed Istio CNI DaemonSet is not healthy on every expected node.'
    }
    Write-ValidationPass "Managed Istio CNI is healthy on $($Config.ExpectedNodeCount) expected node(s)."

    $revisionLabel = Invoke-Kubectl -Arguments @('get', 'namespace', $namespace, '-o', 'jsonpath={.metadata.labels.istio\.io/rev}') -Capture
    if ($revisionLabel.Trim() -cne $expectedRevision) {
        Stop-ValidationFailure "Namespace revision label '$($revisionLabel.Trim())' does not match '$expectedRevision'."
    }
    Write-ValidationPass "Test namespace uses exact revision label istio.io/rev=$expectedRevision."

    foreach ($deployment in @('mesh-source', 'mesh-destination')) {
        Invoke-Kubectl -Arguments @('rollout', 'status', "deployment/$deployment", '-n', $namespace, '--timeout=180s')
    }
    foreach ($app in @('mesh-source', 'mesh-destination')) {
        $pods = (Invoke-Kubectl -Arguments @('get', 'pods', '-n', $namespace, '-l', "app=$app", '-o', 'json') -Capture) | ConvertFrom-Json
        if (@($pods.items).Count -ne 1) { Stop-ValidationFailure "Expected one '$app' pod." }
        $pod = $pods.items[0]
        $proxySpec = @($pod.spec.initContainers | Where-Object { $_.name -eq 'istio-proxy' -and $_.restartPolicy -eq 'Always' })
        $validationSpec = @($pod.spec.initContainers | Where-Object { $_.name -eq 'istio-validation' })
        $legacyInit = @($pod.spec.initContainers | Where-Object { $_.name -eq 'istio-init' })
        $proxyStatus = @($pod.status.initContainerStatuses | Where-Object { $_.name -eq 'istio-proxy' })
        if ($proxySpec.Count -ne 1 -or $validationSpec.Count -ne 1 -or $legacyInit.Count -ne 0 -or
            $proxyStatus.Count -ne 1 -or -not $proxyStatus[0].ready -or -not $proxyStatus[0].state.running) {
            Stop-ValidationFailure "Pod '$($pod.metadata.name)' does not have the expected healthy native Istio sidecar and CNI validation composition."
        }
        if (@($pod.status.containerStatuses | Where-Object { -not $_.ready }).Count -gt 0) {
            Stop-ValidationFailure "Application container in '$($pod.metadata.name)' is not Ready."
        }
    }
    Write-ValidationPass 'Both test workloads contain healthy native managed Istio proxies with CNI validation and no legacy istio-init container.'

    $endpointReady = Invoke-Kubectl -Arguments @(
        'get', 'endpointslice', '-n', $namespace, '-l', 'kubernetes.io/service-name=mesh-destination',
        '-o', 'jsonpath={.items[0].endpoints[0].conditions.ready}'
    ) -Capture
    if ($endpointReady.Trim() -cne 'true') { Stop-ValidationFailure 'The meshed destination has no Ready EndpointSlice endpoint.' }
    $serviceIp = Invoke-Kubectl -Arguments @('get', 'service/mesh-destination', '-n', $namespace, '-o', 'jsonpath={.spec.clusterIP}') -Capture
    if ($serviceIp -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$') { Stop-ValidationFailure "Invalid mesh destination ClusterIP '$serviceIp'." }

    $initialResult = Invoke-IstioHttpProbe -ServiceIp $serviceIp -ExpectedCode '200'
    Write-ValidationPass "Initial meshed HTTP request succeeded ($initialResult)."

    Invoke-Kubectl -Arguments @('apply', '-f', $denyPolicy)
    $denyResult = Invoke-IstioHttpProbe -ServiceIp $serviceIp -ExpectedCode '403'
    Write-ValidationPass "Istio DENY AuthorizationPolicy produced a deterministic response ($denyResult)."

    Invoke-Kubectl -Arguments @('delete', '-f', $denyPolicy, '--ignore-not-found=true', '--wait=true')
    $restoredResult = Invoke-IstioHttpProbe -ServiceIp $serviceIp -ExpectedCode '200'
    Write-ValidationPass "Removing the DENY policy restored meshed HTTP communication ($restoredResult)."
}
finally {
    & kubectl delete -f $denyPolicy --ignore-not-found=true --wait=true 2>$null | Out-Host
    & kubectl delete namespace $namespace --ignore-not-found=true --wait=true --timeout=180s | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Stop-ValidationFailure "Could not clean up Istio validation namespace '$namespace'."
    }
}
