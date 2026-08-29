[CmdletBinding()]
param([Parameter(Mandatory)][hashtable] $Config)

$namespace = 'platform-breakfix-cilium'
$allowPolicy = Join-Path $PSScriptRoot 'allow-source.yaml'

try {
    $clusterResult = & az aks show --resource-group $Config.ResourceGroup --name $Config.ClusterName --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Stop-ValidationFailure "Could not inspect the AKS network data plane: $($clusterResult -join [Environment]::NewLine)"
    }
    $cluster = ($clusterResult -join [Environment]::NewLine) | ConvertFrom-Json
    $dataPlane = ([string]$cluster.networkProfile.networkDataplane).ToLowerInvariant()
    if ($dataPlane -cne 'cilium') {
        Stop-ValidationFailure "AKS reports network data plane '$dataPlane', not 'cilium'."
    }
    Write-ValidationPass 'Azure reports the AKS-managed Cilium network data plane.'

    $daemonSet = (Invoke-Kubectl -Arguments @('get', 'daemonset/cilium', '-n', 'kube-system', '-o', 'json') -Capture) | ConvertFrom-Json
    if ($daemonSet.status.desiredNumberScheduled -ne $Config.ExpectedNodeCount -or
        $daemonSet.status.numberReady -ne $Config.ExpectedNodeCount -or
        $daemonSet.status.numberAvailable -ne $Config.ExpectedNodeCount) {
        Stop-ValidationFailure "Cilium DaemonSet health mismatch: expected $($Config.ExpectedNodeCount), desired $($daemonSet.status.desiredNumberScheduled), ready $($daemonSet.status.numberReady), available $($daemonSet.status.numberAvailable)."
    }
    $agents = (Invoke-Kubectl -Arguments @('get', 'pods', '-n', 'kube-system', '-l', 'k8s-app=cilium', '-o', 'json') -Capture) | ConvertFrom-Json
    $agentNodes = @($agents.items | ForEach-Object { $_.spec.nodeName } | Sort-Object -Unique)
    if ($agents.items.Count -ne $Config.ExpectedNodeCount -or $agentNodes.Count -ne $Config.ExpectedNodeCount) {
        Stop-ValidationFailure "Expected one healthy Cilium agent per node; found $($agents.items.Count) agents across $($agentNodes.Count) nodes."
    }
    foreach ($agent in $agents.items) {
        $notReady = @($agent.status.containerStatuses | Where-Object { -not $_.ready })
        if ($agent.status.phase -ne 'Running' -or $notReady.Count -gt 0) {
            Stop-ValidationFailure "Cilium agent '$($agent.metadata.name)' on '$($agent.spec.nodeName)' is not healthy."
        }
    }
    Write-ValidationPass "$($agents.items.Count) healthy Cilium agent represents each expected node."

    foreach ($deployment in @('policy-source', 'policy-destination')) {
        Invoke-Kubectl -Arguments @('rollout', 'status', "deployment/$deployment", '-n', $namespace, '--timeout=120s')
    }
    $endpointReady = Invoke-Kubectl -Arguments @(
        'get', 'endpointslice', '-n', $namespace,
        '-l', 'kubernetes.io/service-name=policy-destination',
        '-o', 'jsonpath={.items[0].endpoints[0].conditions.ready}'
    ) -Capture
    if ($endpointReady.Trim() -cne 'true') {
        Stop-ValidationFailure 'The Cilium policy destination Service has no ready endpoint.'
    }
    Write-ValidationPass 'The Cilium policy destination EndpointSlice reports a Ready endpoint.'
    $serviceIp = Invoke-Kubectl -Arguments @(
        'get', 'service/policy-destination', '-n', $namespace,
        '-o', 'jsonpath={.spec.clusterIP}'
    ) -Capture
    if ($serviceIp -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$') {
        Stop-ValidationFailure "The Cilium policy destination has invalid ClusterIP '$serviceIp'."
    }

    $probeArguments = @(
        'exec', '-n', $namespace, 'deployment/policy-source', '--',
        'curl', '--fail', '--silent', '--show-error',
        '--connect-timeout', '2', '--max-time', '5',
        '--output', '/dev/null', '--write-out', 'HTTP %{http_code}',
        "http://$serviceIp"
    )
    $deniedOutput = & kubectl @probeArguments 2>&1
    $deniedExitCode = $LASTEXITCODE
    if ($deniedExitCode -eq 0) {
        Stop-ValidationFailure 'Default-deny NetworkPolicy unexpectedly allowed source-to-destination HTTP traffic.'
    }
    $deniedText = ($deniedOutput -join [Environment]::NewLine).Trim()
    Write-ValidationPass "Default-deny blocked the direct-ClusterIP HTTP probe (kubectl exit $deniedExitCode; output: $deniedText)."

    Invoke-Kubectl -Arguments @('apply', '-f', $allowPolicy)
    Invoke-Kubectl -Arguments $probeArguments
    Write-ValidationPass 'Explicit allow NetworkPolicy restored the intended source-to-destination HTTP traffic.'
}
finally {
    & kubectl delete namespace $namespace --ignore-not-found=true --wait=true --timeout=180s | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Stop-ValidationFailure "Could not clean up Cilium validation namespace '$namespace'."
    }
}
