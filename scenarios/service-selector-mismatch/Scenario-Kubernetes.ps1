Set-StrictMode -Version Latest

$script:ScenarioNamespace = 'platform-breakfix-scenario'
$script:ScenarioService = 'scenario-destination'
$script:ScenarioUrl = 'http://scenario-destination.platform-breakfix-scenario.svc.cluster.local/'

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
    param([Parameter(Mandatory)][int] $ExpectedCount, [int] $TimeoutSeconds = 60)
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

function ConvertTo-ScenarioDestinationEvidence {
    param([Parameter(Mandatory)] $Pod)
    foreach ($section in @('metadata', 'spec', 'status')) {
        if (-not (Test-ScenarioObjectProperty $Pod $section) -or $null -eq $Pod.$section) { Stop-ScenarioValidation "Destination Pod is missing required '$section' state." }
    }
    $containerSpec = @($Pod.spec.containers | Where-Object { $_.name -ceq 'destination' })
    $container = @($Pod.status.containerStatuses | Where-Object { $_.name -ceq 'destination' })
    $ready = @($Pod.status.conditions | Where-Object { $_.type -ceq 'Ready' })
    if ($containerSpec.Count -ne 1 -or $container.Count -ne 1 -or $ready.Count -ne 1) { Stop-ScenarioValidation 'Destination Pod is missing its container or Ready condition state.' }
    if (-not (Test-ScenarioObjectProperty $containerSpec[0] 'readinessProbe') -or $null -eq $containerSpec[0].readinessProbe.httpGet.path) { Stop-ScenarioValidation 'Destination Pod has no HTTP readiness probe path.' }
    [pscustomobject]@{
        Name = [string]$Pod.metadata.name
        Created = [datetimeoffset]$Pod.metadata.creationTimestamp
        Phase = [string]$Pod.status.phase
        ContainerRunning = $null -ne $container[0].state.running
        Ready = [string]$ready[0].status
        AppLabel = [string]$Pod.metadata.labels.app
        ProbePath = [string]$containerSpec[0].readinessProbe.httpGet.path
    }
}

function Select-ScenarioCurrentDestinationEvidence {
    param([Parameter(Mandatory)] $PodList)
    if (-not (Test-ScenarioObjectProperty $PodList 'items') -or $null -eq $PodList.items) { Stop-ScenarioValidation 'Pod list has no items collection.' }
    $evidence = foreach ($pod in @($PodList.items)) {
        if ($null -eq $pod) { Stop-ScenarioValidation 'Pod list contains a null item.' }
        if ($pod.metadata.labels.app -cne 'scenario-destination') { continue }
        if ((Test-ScenarioObjectProperty $pod.metadata 'deletionTimestamp') -and $null -ne $pod.metadata.deletionTimestamp) { continue }
        ConvertTo-ScenarioDestinationEvidence $pod
    }
    $current = @($evidence | Sort-Object Created -Descending)
    if ($current.Count -ne 1) { Stop-ScenarioValidation "Expected exactly one current destination Pod; found $($current.Count)." }
    $current[0]
}

function Get-ScenarioCurrentDestinationEvidence {
    $pods = Invoke-ScenarioKubectlJson -Arguments @('get', 'pods', '-n', $script:ScenarioNamespace, '-l', 'app=scenario-destination', '-o', 'json')
    Select-ScenarioCurrentDestinationEvidence $pods
}

function Assert-ScenarioDestinationHealthy {
    $destination = Get-ScenarioCurrentDestinationEvidence
    if ($destination.Phase -cne 'Running' -or -not $destination.ContainerRunning -or $destination.Ready -cne 'True' -or $destination.AppLabel -cne 'scenario-destination') {
        Stop-ScenarioValidation "Destination is not healthy: pod=$($destination.Name), phase=$($destination.Phase), running=$($destination.ContainerRunning), Ready=$($destination.Ready), app=$($destination.AppLabel)."
    }
    $destination
}

function Test-ScenarioSelectorMatchesDestination {
    param([Parameter(Mandatory)][string] $Selector, [Parameter(Mandatory)][string] $DestinationLabel)
    $Selector -ceq $DestinationLabel
}
function Invoke-ScenarioSourceCommand {
    param([Parameter(Mandatory)][string] $Command)
    $output = & kubectl exec -n $script:ScenarioNamespace deployment/scenario-source -- sh -c $Command 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join [Environment]::NewLine).Trim() }
}

function Get-ScenarioDnsResult {
    Invoke-ScenarioSourceCommand "nslookup $($script:ScenarioService).$($script:ScenarioNamespace).svc.cluster.local"
}

function Get-ScenarioHttpResult {
    Invoke-ScenarioSourceCommand "curl --silent --show-error --output /dev/null --write-out '%{http_code}' --connect-timeout 3 --max-time 5 $script:ScenarioUrl"
}
