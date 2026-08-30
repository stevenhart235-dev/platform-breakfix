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
