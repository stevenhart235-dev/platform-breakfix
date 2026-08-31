$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

. (Join-Path $repositoryRoot 'scripts/LabHealth.ps1')
$dashboardRoot = Join-Path $repositoryRoot 'dashboard'
$fixtures = @('healthy', 'readiness-degraded', 'selector-degraded', 'unknown')
$contracts = @{}
foreach ($name in $fixtures) {
    $contracts[$name] = Read-LabHealthContract (Join-Path $dashboardRoot "fixtures/$name.json")
    Assert-True ($contracts[$name].ContractVersion -eq 1) "Fixture $name is not Contract v1."
}
Assert-True ($contracts.healthy.Overall -ceq 'HEALTHY') 'Healthy fixture is not healthy.'
Assert-True ($contracts.'readiness-degraded'.Components.Pods.Status -ceq 'DEGRADED') 'Readiness fixture does not degrade Pods.'
Assert-True ($contracts.'readiness-degraded'.Components.Services.Status -ceq 'HEALTHY') 'Readiness fixture incorrectly degrades Services.'
Assert-True ($contracts.'selector-degraded'.Components.Pods.Status -ceq 'HEALTHY') 'Selector fixture incorrectly degrades Pods.'
Assert-True ($contracts.'selector-degraded'.Components.Services.Status -ceq 'DEGRADED') 'Selector fixture does not degrade Services.'
Assert-True ($contracts.unknown.Overall -ceq 'UNKNOWN') 'Unknown fixture is not unknown.'

$serverPath = Join-Path $dashboardRoot 'server.ps1'
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile($serverPath, [ref]$null, [ref]$parseErrors) | Out-Null
Assert-True ($parseErrors.Count -eq 0) 'Dashboard server does not parse.'
$server = Get-Content -Raw $serverPath
foreach ($term in @('Get-AksLabHealth', 'Read-LabHealthContract', 'ConvertTo-LabHealthJson')) { Assert-True ($server -match $term) "Dashboard does not delegate to $term." }
foreach ($term in @('New-LabHealthContract', 'ScenarioDiagnosis', 'readiness_probe_failure', 'service_selector_mismatch', 'az aks', 'aws eks', 'kubectl exec', 'kubectl patch', 'kubectl delete')) { Assert-True ($server -notmatch [regex]::Escape($term)) "Dashboard contains prohibited logic: $term" }

$js = Get-Content -Raw (Join-Path $dashboardRoot 'static/app.js')
foreach ($name in @('Nodes', 'Pods', 'PVCs', 'Services', 'Endpoints', 'Cilium', 'Istio')) { Assert-True ($js -match "'$name'") "UI omits $name." }
Assert-True ($js -match 'setInterval\(refresh, 5000\)') 'UI refresh interval is not five seconds.'
Assert-True ($js -match 'health\.Overall' -and $js -match 'component\.Status' -and $js -match 'component\.Summary') 'UI does not render direct contract fields.'
Assert-True ($js -match 'Last observed \(stale\)' -and $js -match 'showUnavailable') 'UI lacks visible stale/unavailable behavior.'

$render = & kubectl kustomize (Join-Path $dashboardRoot 'kubernetes') 2>&1
if ($LASTEXITCODE -ne 0) { throw "Dashboard Kustomize render failed: $render" }
$renderText = $render -join "`n"
foreach ($resource in @('nodes', 'pods', 'persistentvolumeclaims', 'services', 'endpointslices', 'deployments', 'daemonsets')) { Assert-True ($renderText -match "- $resource") "RBAC omits $resource." }
foreach ($verb in @('create', 'update', 'patch', 'delete', 'deletecollection', 'impersonate', 'bind', 'escalate')) { Assert-True ($renderText -notmatch "- $verb(?:\r?\n|$)") "RBAC grants prohibited verb $verb." }
Assert-True ($renderText -notmatch '(?m)^\s*- secrets$') 'RBAC grants Secret access.'
foreach ($term in @('runAsNonRoot: true', 'readOnlyRootFilesystem: true', 'allowPrivilegeEscalation: false', 'drop:', 'limits:', 'requests:')) { Assert-True ($renderText -match [regex]::Escape($term)) "Deployment omits $term." }
Assert-True ($renderText -match 'image: platform-breakfix-dashboard:m14' -and $renderText -match 'imagePullPolicy: Never') 'Dashboard is not bound to deterministic node-local image execution.'
Assert-True ($renderText -notmatch 'ghcr\.io|azurecr\.io|imagePullSecrets') 'Dashboard manifest retains an external registry dependency.'

$dockerfile = Get-Content -Raw (Join-Path $dashboardRoot 'Dockerfile')
Assert-True ($dockerfile -match 'KUBECTL_VERSION=v1\.35\.7' -and $dockerfile -match 'sha256sum -c') 'kubectl is not pinned and checksum verified.'
Assert-True ($dockerfile -match 'HOME=/tmp' -and $dockerfile -match 'XDG_CACHE_HOME=/tmp/.cache') 'Read-only runtime cache is not directed to the writable tmp mount.'
foreach ($term in @('azure-cli', 'aws-cli', 'opentofu', 'terraform', 'helm')) { Assert-True ($dockerfile -notmatch $term) "Container adds prohibited dependency $term." }

function Get-FreePort { $socket = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $socket.Start(); $port = ([Net.IPEndPoint]$socket.LocalEndpoint).Port; $socket.Stop(); $port }
function Invoke-DashboardTest([string]$Fixture, [switch]$Failure) {
    $port = Get-FreePort
    $stdout = Join-Path ([IO.Path]::GetTempPath()) "dashboard-$port.out"
    $stderr = Join-Path ([IO.Path]::GetTempPath()) "dashboard-$port.err"
    $arguments = @('-NoLogo', '-NoProfile', '-File', $serverPath, '-Port', $port, '-BindAddress', '127.0.0.1')
    if ($Fixture) { $arguments += @('-Fixture', $Fixture) }
    if ($Failure) { $arguments += '-SimulateCollectorFailure' }
    $process = Start-Process pwsh -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    try {
        $ready = $false
        foreach ($attempt in 1..40) { try { $probe = Invoke-WebRequest "http://127.0.0.1:$port/healthz" -TimeoutSec 1; if ($probe.StatusCode -eq 200) { $ready = $true; break } } catch {}; Start-Sleep -Milliseconds 100 }
        Assert-True $ready "Dashboard did not start: $(Get-Content -Raw $stderr -ErrorAction SilentlyContinue)"
        $healthz = Invoke-WebRequest "http://127.0.0.1:$port/healthz"
        Assert-True ($healthz.StatusCode -eq 200) '/healthz did not return 200.'
        $api = Invoke-WebRequest "http://127.0.0.1:$port/api/health" -SkipHttpErrorCheck
        $page = Invoke-WebRequest "http://127.0.0.1:$port/"
        if ($Failure) {
            Assert-True ($api.StatusCode -eq 503) 'Collector failure did not return 503.'
            Assert-True ($api.Content -match 'HEALTH_UNAVAILABLE' -and $api.Content -notmatch [regex]::Escape($repositoryRoot)) 'Collector error is unbounded or leaks a path.'
            Assert-True ($page.Content -match 'UNKNOWN' -and $page.Content -match 'unavailable') 'Failure UI is not visibly unavailable.'
        } else {
            Assert-True ($api.StatusCode -eq 200) "Valid $Fixture health did not return 200."
            $contract = $api.Content | ConvertFrom-Json -Depth 20 -DateKind String
            Assert-LabHealthContract $contract | Out-Null
            Assert-True ($page.Content -match [regex]::Escape($contract.Overall)) "Root page omits $Fixture overall state."
            if ($Fixture -ceq 'healthy') { Assert-True ($page.Content -match 'asm-1-30') 'Root page omits add-on revision.' }
        }
    }
    finally { if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }; Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue }
}
foreach ($fixture in $fixtures) { Invoke-DashboardTest $fixture }
Invoke-DashboardTest '' -Failure

$m13Hash = git rev-parse 'HEAD:scripts/LabHealth.ps1'
$currentM13Hash = git hash-object (Join-Path $repositoryRoot 'scripts/LabHealth.ps1')
Assert-True ($m13Hash -ceq $currentM13Hash) 'Canonical Lab Health implementation changed.'
$operations = Get-Content -Raw (Join-Path $repositoryRoot 'scripts/BreakfixOperations.ps1')
Assert-True ($operations -notmatch 'get_lab_health') 'M12 Operations v1 was expanded.'
Write-Host 'PASS: AKS Lab Health Dashboard tests.' -ForegroundColor Green
