[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $RepositoryRoot 'scenarios/readiness-probe-failure/Scenario-Kubernetes.ps1')

function New-TestPod {
    param([string]$Name, [string]$Created, [string]$Ready, [string]$Path, [bool]$Running = $true, [bool]$Deleting = $false)
    $metadata = [ordered]@{ name=$Name; creationTimestamp=$Created; labels=@{ app='scenario-destination' } }
    if ($Deleting) { $metadata.deletionTimestamp = '2026-08-29T12:01:00Z' }
    [pscustomobject]@{
        metadata=[pscustomobject]$metadata
        spec=[pscustomobject]@{ containers=@([pscustomobject]@{ name='destination'; readinessProbe=[pscustomobject]@{ httpGet=[pscustomobject]@{ path=$Path } } }) }
        status=[pscustomobject]@{
            phase='Running'
            conditions=@([pscustomobject]@{ type='Ready'; status=$Ready })
            containerStatuses=@([pscustomobject]@{ name='destination'; state=if ($Running) { [pscustomobject]@{ running=[pscustomobject]@{ startedAt=$Created } } } else { [pscustomobject]@{ waiting=[pscustomobject]@{ reason='test' } } } })
        }
    }
}

function Assert-Evidence {
    param([string]$Name, $Pod, [bool]$Running, [string]$Ready, [string]$Path)
    $actual = ConvertTo-ScenarioPodEvidence $Pod
    if ($actual.ContainerRunning -ne $Running -or $actual.Ready -cne $Ready -or $actual.ProbePath -cne $Path) { throw "$Name produced unexpected evidence." }
    Write-Host "PASS: $Name" -ForegroundColor Green
}

function Assert-Throws {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action } catch { Write-Host "PASS: $Name fails visibly." -ForegroundColor Green; return }
    throw "$Name unexpectedly succeeded."
}

$healthy = New-TestPod healthy '2026-08-29T12:00:00Z' True '/'
$broken = New-TestPod broken '2026-08-29T12:02:00Z' False '/platform-breakfix-readiness-failure'
Assert-Evidence 'Pod Running + Ready=True + healthy path' $healthy $true True '/'
Assert-Evidence 'Pod Running + Ready=False + injected path' $broken $true False '/platform-breakfix-readiness-failure'

$missingStatus = New-TestPod missing '2026-08-29T12:00:00Z' True '/'
$missingStatus.psobject.Properties.Remove('status')
Assert-Throws 'Missing required Pod state' { ConvertTo-ScenarioPodEvidence $missingStatus }

$stale = New-TestPod stale '2026-08-29T11:59:00Z' True '/' $true $true
$selected = Select-ScenarioCurrentDestinationEvidence -PodList ([pscustomobject]@{ items=@($stale, $broken) }) -ExpectedProbePath '/platform-breakfix-readiness-failure'
if ($selected.Name -cne 'broken') { throw "Fresh selection bound to stale Pod '$($selected.Name)'." }
Write-Host 'PASS: Fresh snapshots ignore a deleting stale Pod identity.' -ForegroundColor Green

Assert-Throws 'No current Pod with expected probe path' {
    Select-ScenarioCurrentDestinationEvidence -PodList ([pscustomobject]@{ items=@($healthy) }) -ExpectedProbePath '/platform-breakfix-readiness-failure'
}

$composition = Join-Path $RepositoryRoot 'scenarios/readiness-probe-failure/kubernetes'
$rendered = (& kubectl kustomize $composition 2>&1) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0) { throw "Could not render readiness scenario: $rendered" }
$documents = @($rendered -split '(?m)^---\s*$')
$destinationDocument = @($documents | Where-Object { $_ -match '(?m)^kind: Deployment\s*$' -and $_ -match '(?m)^  name: scenario-destination\s*$' })
$sourceDocument = @($documents | Where-Object { $_ -match '(?m)^kind: Deployment\s*$' -and $_ -match '(?m)^  name: scenario-source\s*$' })
if ($destinationDocument.Count -ne 1 -or $destinationDocument[0] -notmatch '(?m)^  strategy:\s*\r?\n    type: Recreate\s*$') { throw 'Rendered destination Deployment strategy is not Recreate.' }
if ($sourceDocument.Count -ne 1 -or $sourceDocument[0] -match '(?m)^  strategy:\s*$') { throw 'Source Deployment unexpectedly received a rollout strategy.' }
Write-Host 'PASS: Rendered destination alone uses strategy.type=Recreate.' -ForegroundColor Green
$scenarioRoot = Join-Path $RepositoryRoot 'scenarios/readiness-probe-failure'
$inspect = Get-Content -Raw -LiteralPath (Join-Path $scenarioRoot 'Inspect.ps1')
if ($inspect -notmatch 'New-ScenarioObservations' -or $inspect -notmatch 'Resolve-ScenarioDiagnosis' -or $inspect -notmatch 'Write-ScenarioEvidence' -or $inspect -notmatch 'PASS: Diagnosis:') { throw 'Readiness Inspect is not integrated with observation-derived diagnosis and evidence output.' }
if ($inspect -match 'readiness_probe_failure|service_selector_mismatch|DiagnosisIdentifier|DiagnosisSummary') { throw 'Readiness Inspect still selects a diagnosis identifier or summary.' }
$inject = Get-Content -Raw -LiteralPath (Join-Path $scenarioRoot 'Inject.ps1')
$repair = Get-Content -Raw -LiteralPath (Join-Path $scenarioRoot 'Repair.ps1')
if ($inject -notmatch 'patch deployment' -or $inject -notmatch '/platform-breakfix-readiness-failure' -or $inject -match 'patch service') { throw 'Readiness injection is no longer limited to the readiness path.' }
if ($repair -notmatch 'patch deployment' -or $repair -notmatch '"path":"/"' -or $repair -match 'patch service') { throw 'Readiness repair is no longer limited to the healthy readiness path.' }
Write-Host 'PASS: Readiness Inspect delegates diagnosis and injection/repair semantics remain unchanged.' -ForegroundColor Green
Write-Host 'PASS: Readiness scenario deterministic tests completed without Kubernetes or Azure access.' -ForegroundColor Green
