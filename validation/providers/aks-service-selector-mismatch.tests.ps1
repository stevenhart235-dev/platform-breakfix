[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ScenarioRoot = Join-Path $RepositoryRoot 'scenarios/service-selector-mismatch'
. (Join-Path $ScenarioRoot 'Scenario-Kubernetes.ps1')

function New-TestDestinationPod {
    param([string]$Name, [string]$Created, [string]$Ready = 'True', [bool]$Running = $true, [bool]$Deleting = $false)
    $metadata = [ordered]@{ name=$Name; creationTimestamp=$Created; labels=@{ app='scenario-destination' } }
    if ($Deleting) { $metadata.deletionTimestamp = '2026-08-30T12:01:00Z' }
    [pscustomobject]@{
        metadata=[pscustomobject]$metadata
        spec=[pscustomobject]@{ containers=@([pscustomobject]@{ name='destination'; readinessProbe=[pscustomobject]@{ httpGet=[pscustomobject]@{ path='/' } } }) }
        status=[pscustomobject]@{
            phase='Running'
            conditions=@([pscustomobject]@{ type='Ready'; status=$Ready })
            containerStatuses=@([pscustomobject]@{ name='destination'; state=if($Running){[pscustomobject]@{running=[pscustomobject]@{startedAt=$Created}}}else{[pscustomobject]@{waiting=[pscustomobject]@{reason='test'}}} })
        }
    }
}

function Assert-Throws([string]$Name, [scriptblock]$Action) {
    try { & $Action } catch { Write-Host "PASS: $Name fails visibly." -ForegroundColor Green; return }
    throw "$Name unexpectedly succeeded."
}

$healthy = New-TestDestinationPod healthy '2026-08-30T12:02:00Z'
$evidence = Select-ScenarioCurrentDestinationEvidence ([pscustomobject]@{ items=@($healthy) })
if ($evidence.Phase -cne 'Running' -or -not $evidence.ContainerRunning -or $evidence.Ready -cne 'True' -or $evidence.AppLabel -cne 'scenario-destination' -or $evidence.ProbePath -cne '/') { throw 'Healthy destination evidence was interpreted incorrectly.' }
Write-Host 'PASS: Destination remains Running and Ready=True with its original label.' -ForegroundColor Green

if (-not (Test-ScenarioSelectorMatchesDestination 'scenario-destination' $evidence.AppLabel)) { throw 'Healthy selector did not match the destination label.' }
if (Test-ScenarioSelectorMatchesDestination 'scenario-destination-missing' $evidence.AppLabel) { throw 'Injected selector unexpectedly matched the destination label.' }
if (-not (Test-ScenarioSelectorMatchesDestination 'scenario-destination' $evidence.AppLabel)) { throw 'Repaired selector did not restore alignment.' }
Write-Host 'PASS: Healthy, injected, and repaired selector semantics are deterministic.' -ForegroundColor Green

$stale = New-TestDestinationPod stale '2026-08-30T12:00:00Z' 'True' $true $true
$selected = Select-ScenarioCurrentDestinationEvidence ([pscustomobject]@{ items=@($stale,$healthy) })
if ($selected.Name -cne 'healthy') { throw "Selection retained stale Pod '$($selected.Name)'." }
Write-Host 'PASS: Current-state selection ignores a deleting stale Pod identity.' -ForegroundColor Green
Assert-Throws 'Missing current destination Pod' { Select-ScenarioCurrentDestinationEvidence ([pscustomobject]@{items=@()}) }

$rendered = (& kubectl kustomize (Join-Path $ScenarioRoot 'kubernetes') 2>&1) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0) { throw "Scenario render failed: $rendered" }
$documents = @($rendered -split '(?m)^---\s*$')
$destination = @($documents | Where-Object { $_ -match '(?m)^kind: Deployment\s*$' -and $_ -match '(?m)^  name: scenario-destination\s*$' })
$source = @($documents | Where-Object { $_ -match '(?m)^kind: Deployment\s*$' -and $_ -match '(?m)^  name: scenario-source\s*$' })
$service = @($documents | Where-Object { $_ -match '(?m)^kind: Service\s*$' -and $_ -match '(?m)^  name: scenario-destination\s*$' })
if ($destination.Count -ne 1 -or $source.Count -ne 1 -or $service.Count -ne 1) { throw 'Rendered topology is incomplete.' }
if ($destination[0] -notmatch '(?m)^        app: scenario-destination\s*$' -or $service[0] -notmatch '(?m)^    app: scenario-destination\s*$') { throw 'Rendered healthy selector/label alignment is missing.' }
if ($destination[0] -notmatch '(?m)^        readinessProbe:\s*$' -or $destination[0] -notmatch '(?m)^            path: /\s*$') { throw 'Destination healthy readiness probe changed.' }

$inject = Get-Content -Raw -LiteralPath (Join-Path $ScenarioRoot 'Inject.ps1')
$repair = Get-Content -Raw -LiteralPath (Join-Path $ScenarioRoot 'Repair.ps1')
if ($inject -notmatch 'patch service' -or $inject -notmatch 'scenario-destination-missing' -or $inject -match 'patch deployment|readinessProbe') { throw 'Injection is not limited to the Service selector.' }
if ($repair -notmatch 'patch service' -or $repair -notmatch 'scenario-destination' -or $repair -match 'patch deployment|readinessProbe') { throw 'Repair is not limited to the Service selector.' }
Write-Host 'PASS: Render and hooks preserve probes/workloads and change only the Service selector.' -ForegroundColor Green
Write-Host 'PASS: Service selector mismatch deterministic tests completed without Kubernetes or Azure access.' -ForegroundColor Green
