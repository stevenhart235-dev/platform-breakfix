Set-StrictMode -Version Latest

function Assert-SingleScenarioDiagnosisMatch {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Matches)
    if ($Matches.Count -ne 1) { throw "Scenario diagnosis requires exactly one matching rule; found $($Matches.Count)." }
    $Matches[0]
}

function Test-ReadinessProbeFailureObservations {
    param([Parameter(Mandatory)] $Observations)
    $workload = $Observations.Workload; $service = $Observations.Service; $connectivity = $Observations.Connectivity
    $workload.DestinationPodExists -eq $true -and $workload.Phase -ceq 'Running' -and
        $workload.ContainerRunning -eq $true -and $workload.Ready -eq $false -and
        $workload.ReadinessProbePath -ceq '/platform-breakfix-readiness-failure' -and
        $workload.DestinationLabels.app -ceq 'scenario-destination' -and
        $service.Exists -eq $true -and $service.Selector.app -ceq 'scenario-destination' -and
        $service.SelectorMatchesDestinationLabel -eq $true -and $service.ReadyEndpointCount -eq 0 -and
        $connectivity.DnsSuccess -eq $true -and $connectivity.HttpSuccess -eq $false
}

function Test-ServiceSelectorMismatchObservations {
    param([Parameter(Mandatory)] $Observations)
    $workload = $Observations.Workload; $service = $Observations.Service; $connectivity = $Observations.Connectivity
    $workload.DestinationPodExists -eq $true -and $workload.Phase -ceq 'Running' -and
        $workload.ContainerRunning -eq $true -and $workload.Ready -eq $true -and
        $workload.ReadinessProbePath -ceq '/' -and
        $workload.DestinationLabels.app -ceq 'scenario-destination' -and
        $service.Exists -eq $true -and $service.Selector.app -ceq 'scenario-destination-missing' -and
        $service.SelectorMatchesDestinationLabel -eq $false -and $service.ReadyEndpointCount -eq 0 -and
        $connectivity.DnsSuccess -eq $true -and $connectivity.HttpSuccess -eq $false
}

function Resolve-ScenarioDiagnosis {
    param([Parameter(Mandatory)] $Observations)
    if (-not (Get-Command Assert-ScenarioObservations -ErrorAction SilentlyContinue)) { throw 'Scenario evidence validation must be loaded before diagnosis.' }
    Assert-ScenarioObservations $Observations | Out-Null
    $matches = @()
    if (Test-ReadinessProbeFailureObservations $Observations) {
        $matches += [pscustomobject][ordered]@{ Identifier='readiness_probe_failure'; Summary='Destination workload is running but not Ready because the injected readiness probe fails while the Service selector still matches.' }
    }
    if (Test-ServiceSelectorMismatchObservations $Observations) {
        $matches += [pscustomobject][ordered]@{ Identifier='service_selector_mismatch'; Summary='Destination workload is running and Ready, but the Service selector does not match the destination workload label.' }
    }
    Assert-SingleScenarioDiagnosisMatch -Matches $matches
}
