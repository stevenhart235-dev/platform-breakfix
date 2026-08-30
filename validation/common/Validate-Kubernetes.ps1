Set-StrictMode -Version Latest

function Write-ValidationPass {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Stop-ValidationFailure {
    param([Parameter(Mandatory)][string] $Message)
    throw "FAIL: $Message"
}

function Invoke-Kubectl {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture
    )

    if ($Capture) {
        $result = & kubectl @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            Stop-ValidationFailure "kubectl $($Arguments -join ' ') failed: $($result -join [Environment]::NewLine)"
        }
        return ($result -join [Environment]::NewLine)
    }

    & kubectl @Arguments | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Stop-ValidationFailure "kubectl $($Arguments -join ' ') failed."
    }
}

function Invoke-CommonKubernetesValidation {
    param(
        [Parameter(Mandatory)][int] $ExpectedNodeCount,
        [Parameter(Mandatory)][string] $StorageManifest
    )

    $storageNamespace = 'platform-breakfix-validation'
    $persistentVolumeName = $null
    $volumeHandle = $null

    Invoke-Kubectl -Arguments @('version', '--request-timeout=10s')
    Write-ValidationPass 'Kubernetes API is reachable.'

    $nodes = (Invoke-Kubectl -Arguments @('get', 'nodes', '-o', 'json') -Capture) | ConvertFrom-Json
    if ($nodes.items.Count -ne $ExpectedNodeCount) {
        Stop-ValidationFailure "Expected $ExpectedNodeCount nodes but found $($nodes.items.Count)."
    }
    foreach ($node in $nodes.items) {
        $ready = $node.status.conditions | Where-Object { $_.type -eq 'Ready' }
        if (-not $ready -or $ready.status -ne 'True') {
            Stop-ValidationFailure "Node '$($node.metadata.name)' is not Ready."
        }
    }
    Write-ValidationPass "$ExpectedNodeCount expected nodes are Ready."

    $systemPodsDeadline = [datetimeoffset]::UtcNow.AddSeconds(180)
    do {
        $systemPods = (Invoke-Kubectl -Arguments @('get', 'pods', '-n', 'kube-system', '-o', 'json') -Capture) | ConvertFrom-Json
        if ($systemPods.items.Count -eq 0) { Stop-ValidationFailure 'No kube-system pods were found.' }
        $unhealthySystemPods = @($systemPods.items | Where-Object {
            $systemPod = $_
            if ($systemPod.status.phase -eq 'Succeeded') { return $false }
            $containersReady = @($systemPod.status.containerStatuses).Count -gt 0 -and
                (@($systemPod.status.containerStatuses | Where-Object { -not $_.ready }).Count -eq 0)
            return $systemPod.status.phase -ne 'Running' -or -not $containersReady
        })
        if ($unhealthySystemPods.Count -eq 0) { break }
        Start-Sleep -Seconds 2
    } while ([datetimeoffset]::UtcNow -lt $systemPodsDeadline)
    if ($unhealthySystemPods.Count -gt 0) {
        $details = $unhealthySystemPods | ForEach-Object { "$($_.metadata.name) (phase=$($_.status.phase))" }
        Stop-ValidationFailure "System pods did not become healthy within 180 seconds: $($details -join ', ')."
    }
    Write-ValidationPass 'System pods are healthy.'

    foreach ($deployment in @(
        @{ Namespace = 'platform'; Name = 'nginx' },
        @{ Namespace = 'platform'; Name = 'podinfo' },
        @{ Namespace = 'platform'; Name = 'whoami' },
        @{ Namespace = 'diagnostics'; Name = 'curl' }
    )) {
        Invoke-Kubectl -Arguments @(
            'rollout', 'status', "deployment/$($deployment.Name)",
            '-n', $deployment.Namespace, '--timeout=120s'
        )
    }
    Write-ValidationPass 'Baseline workloads rolled out successfully.'

    Invoke-Kubectl -Arguments @(
        'exec', '-n', 'diagnostics', 'deployment/curl', '--',
        'curl', '--fail', '--silent', '--show-error', '--output', '/dev/null',
        'http://nginx.platform.svc.cluster.local'
    )
    Write-ValidationPass 'Internal Kubernetes DNS resolves a fully qualified cross-namespace Service name.'

    foreach ($url in @(
        'http://nginx.platform',
        'http://podinfo.platform:9898',
        'http://whoami.platform'
    )) {
        Invoke-Kubectl -Arguments @(
            'exec', '-n', 'diagnostics', 'deployment/curl', '--',
            'curl', '--fail', '--silent', '--show-error', $url
        )
    }
    Write-ValidationPass 'Cross-namespace HTTP connectivity works for all baseline Services.'

    try {
        Invoke-Kubectl -Arguments @('apply', '-f', $StorageManifest)
        Invoke-Kubectl -Arguments @(
            'wait', '--for=condition=Ready', 'pod/block-storage-smoke',
            '-n', $storageNamespace, '--timeout=180s'
        )

        $persistentVolumeName = Invoke-Kubectl -Arguments @(
            'get', 'pvc/block-storage-smoke', '-n', $storageNamespace,
            '-o', 'jsonpath={.spec.volumeName}'
        ) -Capture
        if ([string]::IsNullOrWhiteSpace($persistentVolumeName)) {
            Stop-ValidationFailure 'The storage smoke PVC did not bind to a PersistentVolume.'
        }
        $volumeHandle = Invoke-Kubectl -Arguments @(
            'get', "persistentvolume/$persistentVolumeName",
            '-o', 'jsonpath={.spec.csi.volumeHandle}'
        ) -Capture
        if ([string]::IsNullOrWhiteSpace($volumeHandle)) {
            Stop-ValidationFailure "PersistentVolume '$persistentVolumeName' has no CSI volume handle."
        }

        Invoke-Kubectl -Arguments @(
            'exec', '-n', $storageNamespace, 'pod/block-storage-smoke', '--',
            'grep', '-qx', 'platform-breakfix-storage-ok', '/data/probe'
        )
        Write-ValidationPass "Dynamic block storage '$persistentVolumeName' was provisioned, mounted, written, and read."
    }
    finally {
        & kubectl delete namespace $storageNamespace --ignore-not-found=true --wait=true --timeout=180s | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Stop-ValidationFailure "Could not delete validation namespace '$storageNamespace'."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($persistentVolumeName)) {
        & kubectl wait --for=delete "persistentvolume/$persistentVolumeName" --timeout=180s 2>$null | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Stop-ValidationFailure "PersistentVolume '$persistentVolumeName' was not deleted."
        }
        Write-ValidationPass 'Test pod, claim, and PersistentVolume were deleted.'
    }

    return $volumeHandle
}
