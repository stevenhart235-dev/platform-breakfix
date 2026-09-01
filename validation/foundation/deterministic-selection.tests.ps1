[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$primitivePath = Join-Path $RepositoryRoot 'foundation/DeterministicSelection.ps1'
. $primitivePath

function New-Candidate([string]$Name,[bool]$Matches,$Value) { [pscustomobject][ordered]@{ Name=$Name; Matches=$Matches; Value=$Value } }
function Assert-Fails([string]$Name,[scriptblock]$Action) { try { & $Action | Out-Null } catch { Write-Host "PASS: $Name fails closed." -ForegroundColor Green; return }; throw "$Name unexpectedly succeeded." }
function Assert-Equal([string]$Name,$Actual,$Expected) { if ($Actual -cne $Expected) { throw "$Name expected '$Expected', got '$Actual'." }; Write-Host "PASS: $Name" -ForegroundColor Green }

Assert-Fails 'zero candidates' { Resolve-DeterministicSelection -Candidates @() }
Assert-Fails 'zero matches' { Resolve-DeterministicSelection -Candidates @((New-Candidate alpha $false A),(New-Candidate beta $false B)) }
Assert-Equal 'exactly one match succeeds' (Resolve-DeterministicSelection -Candidates @((New-Candidate alpha $true A),(New-Candidate beta $false B))) A
Assert-Fails 'multiple matches' { Resolve-DeterministicSelection -Candidates @((New-Candidate alpha $true A),(New-Candidate beta $true B)) }
$forward = Resolve-DeterministicSelection -Candidates @((New-Candidate alpha $false A),(New-Candidate beta $true B))
$reverse = Resolve-DeterministicSelection -Candidates @((New-Candidate beta $true B),(New-Candidate alpha $false A))
Assert-Equal 'candidate order does not alter the result' $forward $reverse
Assert-Fails 'duplicate matching name cannot select first' { Resolve-DeterministicSelection -Candidates @((New-Candidate alpha $true A),(New-Candidate alpha $false B)) }
Assert-Fails 'missing candidate field' { Resolve-DeterministicSelection -Candidates @([pscustomobject]@{Name='alpha';Matches=$true}) }
Assert-Fails 'unknown candidate field' { Resolve-DeterministicSelection -Candidates @([pscustomobject]@{Name='alpha';Matches=$true;Value='A';Extra='x'}) }
Assert-Fails 'invalid match type' { Resolve-DeterministicSelection -Candidates @([pscustomobject]@{Name='alpha';Matches='true';Value='A'}) }
Assert-Fails 'null candidate input' { Resolve-DeterministicSelection -Candidates @($null) }
Assert-Fails 'null value' { Resolve-DeterministicSelection -Candidates @([pscustomobject]@{Name='alpha';Matches=$true;Value=$null}) }

$source = Get-Content -Raw -LiteralPath $primitivePath
foreach ($term in @('readiness_probe_failure','service_selector_mismatch','readiness-probe-failure','service-selector-mismatch','Scenario','kubectl','az','aws','Azure','AKS','EKS','Kubernetes','Pod','Service','EndpointSlice','HTTP','DNS','Invoke-Expression','Start-Process','& ','Set-Content','Add-Content','Remove-Item','Move-Item','Copy-Item')) {
    if ($source -cmatch [regex]::Escape($term)) { throw "Foundation primitive contains prohibited dependency or capability '$term'." }
}
if ($source -match '(?i)ScenarioDiagnosis|ScenarioEvidence|BreakfixOperations|BreakfixCli|LabHealth|dashboard|providers[/\\]|profiles[/\\]|\.\s+\(') { throw 'Foundation primitive imports or references an upstream consumer.' }
if ($source -notmatch 'matches\.Count -ne 1') { throw 'Foundation primitive does not canonically enforce exactly one match.' }
Write-Host 'PASS: foundation primitive is neutral, deterministic, read-only, and dependency-free.' -ForegroundColor Green
Write-Host 'PASS: deterministic selection foundation tests.' -ForegroundColor Green
