[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
$patch = '{"spec":{"selector":{"app":"scenario-destination"}}}'
& kubectl patch service $script:ScenarioService -n $script:ScenarioNamespace --type merge --patch $patch | Out-Host
if ($LASTEXITCODE -ne 0) { Stop-ScenarioValidation 'Could not restore the Service selector.' }
Write-Host 'PASS: Restored only the Service selector to app=scenario-destination.' -ForegroundColor Green
