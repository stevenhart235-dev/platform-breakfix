$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repositoryRoot 'scripts/BreakfixOperations.ps1')
. (Join-Path $repositoryRoot 'scripts/BreakfixCli.ps1')
. (Join-Path $repositoryRoot 'scripts/LabHealth.ps1')
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Assert-Error($Result, [string]$Code, [int]$Version = 2) {
    Assert-True (-not $Result.Success) "Expected $Code failure."
    Assert-True ($Result.ContractVersion -eq $Version) "Expected envelope v$Version."
    Assert-True ($Result.Error.Code -ceq $Code) "Expected $Code, got $($Result.Error.Code)."
    Assert-True ($null -eq $Result.Data) 'Failure Data must be null.'
}
function Read-Fixture([string]$Name) { Read-LabHealthContract (Join-Path $repositoryRoot "dashboard/fixtures/$Name.json") }
function Set-ActiveHealthFixture($Health, [string]$Profile = 'minimal') {
    $script:healthFixture = $Health
    $script:healthProfile = $Profile
    $script:capturedHealthProfile = $null
    $script:BreakfixStatusReaders.aks = { param($Root) [pscustomobject]@{ State='ACTIVE'; Profile=$script:healthProfile; CreatedAt='2026-01-01T00:00:00Z'; ExpiresAt='2026-01-01T04:00:00Z' } }
    $script:BreakfixHealthReaders.aks = { param($Root, $Profile) $script:capturedHealthProfile=$Profile; $script:healthFixture }
}

$v1 = @('diagnose_evidence','get_lab_status','list_profiles','list_scenarios','read_evidence')
$v2 = @('diagnose_evidence','get_lab_health','get_lab_status','list_profiles','list_scenarios','read_evidence')
Assert-True (@(Compare-Object ($script:BreakfixOperationSets[1]|Sort-Object) $v1).Count -eq 0) 'Operations v1 set changed.'
Assert-True (@(Compare-Object ($script:BreakfixOperationSets[2]|Sort-Object) $v2).Count -eq 0) 'Operations v2 set is not exactly six.'
Assert-Error (Invoke-BreakfixOperation get_lab_health @{Provider='aks'}) INVALID_ARGUMENT 1
foreach ($operation in $v1) {
    $arguments = switch ($operation) { 'get_lab_status' {@{Provider='eks'}} 'read_evidence' {@{}} 'diagnose_evidence' {@{}} default {@{}} }
    $result = Invoke-BreakfixOperation $operation $arguments -ContractVersion 2
    Assert-True ($result.ContractVersion -eq 2 -and $result.Operation -ceq $operation) "v2 did not invoke $operation."
}

$originalStatus = $script:BreakfixStatusReaders.aks
$originalHealth = $script:BreakfixHealthReaders.aks
try {
    foreach ($case in @(
        @{Name='healthy';Overall='HEALTHY'},
        @{Name='readiness-degraded';Overall='DEGRADED'},
        @{Name='selector-degraded';Overall='DEGRADED'},
        @{Name='unknown';Overall='UNKNOWN'}
    )) {
        $fixture = Read-Fixture $case.Name
        Set-ActiveHealthFixture $fixture $fixture.Profile
        $result = Invoke-BreakfixOperation get_lab_health @{Provider='aks'} -ContractVersion 2
        Assert-True ($result.Success -and $result.ContractVersion -eq 2 -and $result.Operation -ceq 'get_lab_health') "$($case.Name) envelope failed."
        Assert-LabHealthContract $result.Data | Out-Null
        Assert-True ($result.Data.Overall -ceq $case.Overall) "$($case.Name) semantics changed."
        Assert-True ($script:capturedHealthProfile -ceq $fixture.Profile) 'Authoritative active-lab profile was not passed to health collector.'
    }

    foreach ($state in @('NO LAB','STALE','EXISTING INVALID')) {
        $script:stateFixture=$state
        $script:BreakfixStatusReaders.aks={param($Root) if($script:stateFixture -eq 'NO LAB'){[pscustomobject]@{State=$script:stateFixture}}else{[pscustomobject]@{State=$script:stateFixture;Profile='minimal';CreatedAt='2026-01-01T00:00:00Z';ExpiresAt='2026-01-01T04:00:00Z'}}}
        Assert-Error (Invoke-BreakfixOperation get_lab_health @{Provider='aks'} -ContractVersion 2) LAB_NOT_ACTIVE
    }
    Assert-Error (Invoke-BreakfixOperation get_lab_health @{Provider='eks'} -ContractVersion 2) PROVIDER_UNSUPPORTED

    Set-ActiveHealthFixture ([pscustomobject]@{ ContractVersion=1; Overall='HEALTHY' })
    $malformed = Invoke-BreakfixOperation get_lab_health @{Provider='aks'} -ContractVersion 2
    Assert-Error $malformed LAB_STATE_UNAVAILABLE
    Assert-True ($malformed.Error.Message -notmatch 'ContractVersion|Components|[A-Za-z]:\\|ScriptStackTrace') 'Malformed collector details escaped.'

    $script:BreakfixHealthReaders.aks={param($Root,$Profile)throw 'C:\secret\kubeconfig token=abc'}
    $sanitized=Invoke-BreakfixOperation get_lab_health @{Provider='aks'} -ContractVersion 2
    Assert-Error $sanitized LAB_STATE_UNAVAILABLE
    Assert-True ($sanitized.Error.Message -notmatch 'secret|kubeconfig|token|C:\\') 'Collector failure leaked details.'
} finally {
    $script:BreakfixStatusReaders.aks = $originalStatus
    $script:BreakfixHealthReaders.aks = $originalHealth
}

$healthy = Read-Fixture healthy
$degraded = Read-Fixture readiness-degraded
$script:cliResult = [pscustomobject][ordered]@{ContractVersion=2;Operation='get_lab_health';Success=$true;Data=$healthy;Error=$null}
$script:lastCliCall=$null
$invoker={param($Operation,$Arguments,$Version)$script:lastCliCall=[pscustomobject]@{Operation=$Operation;Provider=$Arguments.Provider;Version=$Version};$script:cliResult}
$human=Invoke-BreakfixCliAdapter lab health '' aks $false $invoker
Assert-True ($human.ExitCode -eq 0 -and $human.StandardOutput[0] -ceq 'Lab Health: HEALTHY') 'Healthy human rendering failed.'
foreach($name in @('Nodes','Pods','PVCs','Services','Endpoints','Cilium','Istio')){Assert-True (($human.StandardOutput -join "`n") -match "(?m)^$name\s+$($healthy.Components.$name.Status)$") "Human rendering omitted $name."}
Assert-True ($script:lastCliCall.Operation -ceq 'get_lab_health' -and $script:lastCliCall.Provider -ceq 'aks' -and $script:lastCliCall.Version -eq 2) 'CLI mapping/version failed.'
$script:cliResult=[pscustomobject][ordered]@{ContractVersion=2;Operation='get_lab_health';Success=$true;Data=$degraded;Error=$null}
$human=Invoke-BreakfixCliAdapter lab health '' aks $false $invoker
Assert-True (($human.StandardOutput -join "`n") -match 'Lab Health: DEGRADED' -and ($human.StandardOutput -join "`n") -match 'Pods\s+DEGRADED') 'Degraded human rendering failed.'
$json=Invoke-BreakfixCliAdapter lab health '' aks $true $invoker
$jsonResult=$json.StandardOutput|ConvertFrom-Json -DateKind String
Assert-True ($json.ExitCode -eq 0 -and $jsonResult.ContractVersion -eq 2 -and $jsonResult.Data.ContractVersion -eq 1) 'CLI JSON v2/v1 envelope failed.'
$script:cliResult=[pscustomobject][ordered]@{ContractVersion=2;Operation='get_lab_health';Success=$false;Data=$null;Error=[pscustomobject]@{Code='LAB_NOT_ACTIVE';Message='Lab health requires an observable active lab.'}}
$failure=Invoke-BreakfixCliAdapter lab health '' aks $false $invoker
Assert-True ($failure.ExitCode -eq 1 -and ($failure.StandardError -join '') -match 'LAB_NOT_ACTIVE') 'CLI operation failure exit failed.'
$invalid=Invoke-BreakfixCliAdapter lab health '' '' $true $invoker
Assert-True ($invalid.ExitCode -eq 2 -and (($invalid.StandardOutput|ConvertFrom-Json).ContractVersion -eq 2)) 'CLI syntax exit failed.'

$operationsSource=Get-Content -Raw (Join-Path $repositoryRoot 'scripts/BreakfixOperations.ps1')
$cliSource=(Get-Content -Raw (Join-Path $repositoryRoot 'scripts/BreakfixCli.ps1'))+(Get-Content -Raw (Join-Path $repositoryRoot 'breakfix.ps1'))
Assert-True ($operationsSource -match 'Get-AksLabHealth' -and $operationsSource -match 'Assert-LabHealthContract') 'Operation does not delegate to LabHealth.'
foreach($term in @('Get-LabHealthOverall','ConvertTo-LabHealthComponents','Test-ReadinessProbeFailureObservations','Test-ServiceSelectorMismatchObservations')){Assert-True ($operationsSource -notmatch [regex]::Escape($term)) "Operation duplicates classification: $term"}
foreach($term in @('kubectl exec','kubectl apply','kubectl patch','kubectl delete','kubectl create','get-credentials','update-kubeconfig','tofu apply','tofu destroy','docker push','docker login')){Assert-True (($operationsSource+$cliSource) -notmatch [regex]::Escape($term)) "Forbidden mutation introduced: $term"}
Write-Host 'PASS: Breakfix Operations v2 and lab health CLI deterministic tests.' -ForegroundColor Green
