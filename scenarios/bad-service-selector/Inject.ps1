[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
$patch = '{"spec":{"selector":{"app":"scenario-destination-missing"}}}'
& kubectl patch service $script:ScenarioService -n $script:ScenarioNamespace --type merge --patch $patch | Out-Host
if ($LASTEXITCODE -ne 0) { Stop-ScenarioValidation 'Could not inject the Service selector mismatch.' }
Write-Host 'PASS: Injected selector app=scenario-destination-missing.' -ForegroundColor Green
