[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Scenario-Kubernetes.ps1')
$patch = '{"spec":{"template":{"spec":{"containers":[{"name":"destination","readinessProbe":{"httpGet":{"path":"/","port":"http"},"initialDelaySeconds":1,"periodSeconds":2}}]}}}}'
& kubectl patch deployment $script:ScenarioDestination -n $script:ScenarioNamespace --type strategic --patch $patch | Out-Host
if ($LASTEXITCODE -ne 0) { Stop-ScenarioValidation 'Could not restore the readiness probe path.' }
Write-Host "PASS: Restored only readiness probe path to $script:ScenarioHealthyProbePath." -ForegroundColor Green
