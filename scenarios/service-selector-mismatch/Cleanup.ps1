[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$namespace = 'platform-breakfix-scenario'
& kubectl delete namespace $namespace --ignore-not-found=true --wait=true --timeout=180s | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Could not clean up scenario namespace '$namespace'." }
Write-Host "PASS: Scenario-owned namespace '$namespace' is absent." -ForegroundColor Green
