[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $RepositoryRoot 'scenarios/bad-service-selector/Scenario-Kubernetes.ps1')

function Assert-Count {
    param([string]$Name, [string]$Json, [int]$Expected)
    $actual = Get-ReadyEndpointCountFromEndpointSliceList -EndpointSliceList ($Json | ConvertFrom-Json)
    if ($actual -ne $Expected) { throw "$Name expected $Expected, found $actual." }
    Write-Host "PASS: $Name => $actual" -ForegroundColor Green
}
function Assert-Throws {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action } catch { Write-Host "PASS: $Name remains a visible failure." -ForegroundColor Green; return }
    throw "$Name unexpectedly returned a count."
}
Assert-Count 'one Ready endpoint' '{"items":[{"endpoints":[{"conditions":{"ready":true}}]}]}' 1
Assert-Count 'multiple Ready endpoints' '{"items":[{"endpoints":[{"conditions":{"ready":true}},{"conditions":{"ready":true}}]}]}' 2
Assert-Count 'ready false' '{"items":[{"endpoints":[{"conditions":{"ready":false}}]}]}' 0
Assert-Count 'empty endpoints array' '{"items":[{"endpoints":[]}]}' 0
Assert-Count 'null endpoints' '{"items":[{"endpoints":null}]}' 0
Assert-Count 'missing endpoints' '{"items":[{}]}' 0
Assert-Count 'missing conditions' '{"items":[{"endpoints":[{}]}]}' 0
Assert-Count 'null conditions' '{"items":[{"endpoints":[{"conditions":null}]}]}' 0
Assert-Count 'missing ready' '{"items":[{"endpoints":[{"conditions":{}}]}]}' 0
Assert-Count 'null ready' '{"items":[{"endpoints":[{"conditions":{"ready":null}}]}]}' 0
Assert-Count 'mixed readiness' '{"items":[{"endpoints":[{"conditions":{"ready":true}},{"conditions":{"ready":false}},{"conditions":{}},null]}]}' 1
Assert-Throws 'missing list items' { Get-ReadyEndpointCountFromEndpointSliceList -EndpointSliceList ([pscustomobject]@{}) }
Assert-Throws 'null list items' { Get-ReadyEndpointCountFromEndpointSliceList -EndpointSliceList ([pscustomobject]@{ items = $null }) }
Assert-Throws 'null slice item' { Get-ReadyEndpointCountFromEndpointSliceList -EndpointSliceList ([pscustomobject]@{ items = @($null) }) }
Assert-Throws 'invalid JSON' { '{' | ConvertFrom-Json }
Write-Host 'PASS: EndpointSlice counting regression tests completed without Kubernetes or Azure access.' -ForegroundColor Green