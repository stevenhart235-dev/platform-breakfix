Set-StrictMode -Version Latest

$script:ScenarioNamespace = 'platform-breakfix-scenario'
$script:ScenarioService = 'scenario-destination'
$script:ScenarioDestination = 'scenario-destination'
$script:ScenarioHealthyProbePath = '/'
$script:ScenarioBrokenProbePath = '/platform-breakfix-readiness-failure'
$script:ScenarioUrl = "http://$($script:ScenarioService).$($script:ScenarioNamespace).svc.cluster.local/"

function Stop-ScenarioValidation { param([string]$Message) throw $Message }

function Test-ScenarioObjectProperty {
    param([Parameter(Mandatory)] $InputObject, [Parameter(Mandatory)][string] $Name)
    $null -ne $InputObject.psobject.Properties[$Name]
}

function Invoke-ScenarioKubectlJson {
    param([Parameter(Mandatory)][string[]] $Arguments)
    $result = & kubectl @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { Stop-ScenarioValidation "kubectl $($Arguments -join ' ') failed: $($result -join [Environment]::NewLine)" }
    ($result -join [Environment]::NewLine) | ConvertFrom-Json
}

function Assert-ScenarioDeploymentReady {
    param([Parameter(Mandatory)][string] $Name)
    $deployment = Invoke-ScenarioKubectlJson -Arguments @('get', 'deployment', $Name, '-n', $script:ScenarioNamespace, '-o', 'json')
    if ([int]$deployment.status.readyReplicas -ne 1) { Stop-ScenarioValidation "Deployment '$Name' is not Ready." }
}

function Get-ReadyEndpointCountFromEndpointSliceList {
    param([Parameter(Mandatory)] $EndpointSliceList)
    if (-not (Test-ScenarioObjectProperty -InputObject $EndpointSliceList -Name 'items') -or $null -eq $EndpointSliceList.items) {
        Stop-ScenarioValidation 'EndpointSlice list has no items collection.'
    }
    $count = 0
    foreach ($slice in @($EndpointSliceList.items)) {
        if ($null -eq $slice) { Stop-ScenarioValidation 'EndpointSlice list contains a null item.' }
        if (-not (Test-ScenarioObjectProperty -InputObject $slice -Name 'endpoints') -or $null -eq $slice.endpoints) { continue }
        foreach ($endpoint in @($slice.endpoints)) {
            if ($null -eq $endpoint) { continue }
            if (-not (Test-ScenarioObjectProperty -InputObject $endpoint -Name 'conditions') -or $null -eq $endpoint.conditions) { continue }
            if (-not (Test-ScenarioObjectProperty -InputObject $endpoint.conditions -Name 'ready') -or $null -eq $endpoint.conditions.ready) { continue }
            if ($endpoint.conditions.ready -eq $true) { $count++ }
        }
    }
    $count
}

function Get-ScenarioReadyEndpointCount {
    $slices = Invoke-ScenarioKubectlJson -Arguments @('get', 'endpointslice', '-n', $script:ScenarioNamespace, '-l', "kubernetes.io/service-name=$($script:ScenarioService)", '-o', 'json')
    Get-ReadyEndpointCountFromEndpointSliceList -EndpointSliceList $slices
}

function Wait-ScenarioReadyEndpointCount {
    param([Parameter(Mandatory)][int] $ExpectedCount, [int] $TimeoutSeconds = 120)
    $deadline = [datetimeoffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $count = Get-ScenarioReadyEndpointCount
        if ($count -eq $ExpectedCount) { return $count }
        Start-Sleep -Seconds 2
    } while ([datetimeoffset]::UtcNow -lt $deadline)
    Stop-ScenarioValidation "Timed out waiting for $ExpectedCount Ready EndpointSlice backends; last count was $count."
}

function Get-ScenarioServiceSelector {
    $service = Invoke-ScenarioKubectlJson -Arguments @('get', 'service', $script:ScenarioService, '-n', $script:ScenarioNamespace, '-o', 'json')
    [string]$service.spec.selector.app
}

function ConvertTo-ScenarioPodEvidence {
    param([Parameter(Mandatory)] $Pod)
    foreach ($section in @('metadata', 'spec', 'status')) {
        if (-not (Test-ScenarioObjectProperty $Pod $section) -or $null -eq $Pod.$section) { Stop-ScenarioValidation "Destination Pod is missing required '$section' state." }
    }
    $container = @($Pod.spec.containers | Where-Object { $_.name -ceq 'destination' })
    $containerStatus = @($Pod.status.containerStatuses | Where-Object { $_.name -ceq 'destination' })
    $readyCondition = @($Pod.status.conditions | Where-Object { $_.type -ceq 'Ready' })
    if ($container.Count -ne 1 -or $containerStatus.Count -ne 1 -or $readyCondition.Count -ne 1) { Stop-ScenarioValidation 'Destination Pod is missing required container or Ready condition state.' }
    if (-not (Test-ScenarioObjectProperty $container[0] 'readinessProbe') -or $null -eq $container[0].readinessProbe.httpGet.path) { Stop-ScenarioValidation 'Destination Pod has no HTTP readiness probe path.' }
    [pscustomobject]@{
        Name = [string]$Pod.metadata.name
        Created = [datetimeoffset]$Pod.metadata.creationTimestamp
        Phase = [string]$Pod.status.phase
        ContainerRunning = $null -ne $containerStatus[0].state.running
        Ready = [string]$readyCondition[0].status
        ProbePath = [string]$container[0].readinessProbe.httpGet.path
        Labels = $Pod.metadata.labels
    }
}

function Select-ScenarioCurrentDestinationEvidence {
    param([Parameter(Mandatory)] $PodList, [Parameter(Mandatory)][string] $ExpectedProbePath)
    if (-not (Test-ScenarioObjectProperty $PodList 'items') -or $null -eq $PodList.items) { Stop-ScenarioValidation 'Pod list has no items collection.' }
    $evidence = foreach ($pod in @($PodList.items)) {
        if ($null -eq $pod) { Stop-ScenarioValidation 'Pod list contains a null item.' }
        if ($pod.metadata.labels.app -cne $script:ScenarioDestination) { continue }
        if ((Test-ScenarioObjectProperty $pod.metadata 'deletionTimestamp') -and $null -ne $pod.metadata.deletionTimestamp) { continue }
        $item = ConvertTo-ScenarioPodEvidence $pod
        if ($item.ProbePath -ceq $ExpectedProbePath) { $item }
    }
    $matches = @($evidence | Sort-Object Created -Descending)
    if ($matches.Count -eq 0) { Stop-ScenarioValidation "No current destination Pod has readiness path '$ExpectedProbePath'." }
    $current = $matches[0]
    $current
}

function Get-ScenarioCurrentDestinationEvidence {
    param([Parameter(Mandatory)][string] $ExpectedProbePath)
    $pods = Invoke-ScenarioKubectlJson -Arguments @('get', 'pods', '-n', $script:ScenarioNamespace, '-l', "app=$($script:ScenarioDestination)", '-o', 'json')
    Select-ScenarioCurrentDestinationEvidence -PodList $pods -ExpectedProbePath $ExpectedProbePath
}

function Wait-ScenarioDestinationState {
    param([Parameter(Mandatory)][string] $ProbePath, [Parameter(Mandatory)][string] $Ready, [int] $TimeoutSeconds = 120)
    $deadline = [datetimeoffset]::UtcNow.AddSeconds($TimeoutSeconds)
    $evidence = $null
    $lastReason = 'no matching current Pod observed'
    do {
        try {
            $evidence = Get-ScenarioCurrentDestinationEvidence -ExpectedProbePath $ProbePath
            if ($evidence.Phase -ceq 'Running' -and $evidence.ContainerRunning -and $evidence.Ready -ceq $Ready) { return $evidence }
        } catch { $lastReason = $_.Exception.Message }
        Start-Sleep -Seconds 2
    } while ([datetimeoffset]::UtcNow -lt $deadline)
    if ($null -ne $evidence) { $lastReason = "pod=$($evidence.Name), phase=$($evidence.Phase), running=$($evidence.ContainerRunning), Ready=$($evidence.Ready), probe=$($evidence.ProbePath)" }
    Stop-ScenarioValidation "Timed out waiting for destination Running/Ready=$Ready with probe '$ProbePath': $lastReason"
}

function Invoke-ScenarioSourceCommand {
    param([Parameter(Mandatory)][string] $Command)
    $output = & kubectl exec -n $script:ScenarioNamespace deployment/scenario-source -- sh -c $Command 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join [Environment]::NewLine).Trim() }
}

function Get-ScenarioDnsResult { Invoke-ScenarioSourceCommand "nslookup $($script:ScenarioService).$($script:ScenarioNamespace).svc.cluster.local" }

function Get-ScenarioHttpResult {
    Invoke-ScenarioSourceCommand "curl --silent --show-error --output /dev/null --write-out '%{http_code}' --connect-timeout 3 --max-time 5 $script:ScenarioUrl"
}

function Get-ScenarioReadinessEvents {
    param([Parameter(Mandatory)][string] $PodName)
    $events = Invoke-ScenarioKubectlJson -Arguments @('get', 'events', '-n', $script:ScenarioNamespace, '--field-selector', "involvedObject.name=$PodName", '-o', 'json')
    @($events.items | Where-Object { $_.reason -ceq 'Unhealthy' } | Select-Object -Last 3 | ForEach-Object { [string]$_.message })
}
