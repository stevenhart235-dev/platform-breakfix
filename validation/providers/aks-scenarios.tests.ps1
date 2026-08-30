[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $RepositoryRoot 'scripts/Scenario.ps1')
. (Join-Path $RepositoryRoot 'providers/azure/aks/scripts/Profile-Aks.ps1')

function Assert-ThrowsLike {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    try { & $Action } catch { if ($_.Exception.Message -notmatch $Pattern) { throw "$Message Unexpected: $($_.Exception.Message)" }; Write-Host "PASS: $Message" -ForegroundColor Green; return }
    throw "$Message Expected an error matching '$Pattern'."
}

function Write-TestScenario {
    param([string]$Root, [string]$Name, [string]$Manifest)
    $scenarioRoot = Join-Path $Root $Name
    New-Item -ItemType Directory -Path (Join-Path $scenarioRoot 'kubernetes') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $scenarioRoot 'scenario.psd1') -Value $Manifest -Encoding utf8
    Set-Content -LiteralPath (Join-Path $scenarioRoot 'kubernetes/kustomization.yaml') -Value "apiVersion: kustomize.config.k8s.io/v1beta1`nkind: Kustomization`nresources: []" -Encoding utf8
    foreach ($hook in @('Inject','Validate-Broken','Inspect','Repair','Validate-Recovered','Cleanup')) { Set-Content -LiteralPath (Join-Path $scenarioRoot "$hook.ps1") -Value '[CmdletBinding()] param()' -Encoding utf8 }
}

$productionRoot = Join-Path $RepositoryRoot 'scenarios'
$readiness = Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName readiness-probe-failure -ScenariosRoot $productionRoot
if ($readiness.Name -cne 'readiness-probe-failure' -or $readiness.Provider -cne 'aks' -or $readiness.Profile -cne 'minimal' -or $readiness.Hooks.Count -ne 6) { throw 'Readiness scenario did not normalize correctly.' }
Write-Host 'PASS: Readiness scenario resolves with the unchanged six-hook schema.' -ForegroundColor Green
$selectorMismatch = Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName service-selector-mismatch -ScenariosRoot $productionRoot
if ($selectorMismatch.Name -cne 'service-selector-mismatch' -or $selectorMismatch.Provider -cne 'aks' -or $selectorMismatch.Profile -cne 'minimal' -or $selectorMismatch.Hooks.Count -ne 6) { throw 'Service selector mismatch scenario did not normalize correctly.' }
Write-Host 'PASS: Service selector mismatch resolves with the unchanged six-hook schema.' -ForegroundColor Green
Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName bad-service-selector -ScenariosRoot $productionRoot } 'Unknown scenario' 'Removed bad-service-selector fails closed as unknown.'
$none = Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName '' -ScenariosRoot $productionRoot
if (-not $none.IsNone -or $none.Name -cne 'none') { throw 'Omitted scenario did not resolve as none.' }
Write-Host 'PASS: Omitted scenario resolves as none.' -ForegroundColor Green
Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName cilium -ScenarioName readiness-probe-failure -ScenariosRoot $productionRoot } 'does not support profile' 'Readiness scenario rejects Cilium.'
Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName istio -ScenarioName readiness-probe-failure -ScenariosRoot $productionRoot } 'does not support profile' 'Readiness scenario rejects Istio.'
Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName cilium -ScenarioName service-selector-mismatch -ScenariosRoot $productionRoot } 'does not support profile' 'Service selector mismatch rejects Cilium.'
Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName istio -ScenarioName service-selector-mismatch -ScenariosRoot $productionRoot } 'does not support profile' 'Service selector mismatch rejects Istio.'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "platform-breakfix-scenario-tests-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot | Out-Null
$base = "@{ SchemaVersion=1; Name='NAME'; SupportedProviders=@('aks'); SupportedProfiles=@('minimal'); Description='test'; KubernetesComposition='kubernetes'; Hooks=@{ Inject='Inject.ps1'; ValidateBroken='Validate-Broken.ps1'; Inspect='Inspect.ps1'; Repair='Repair.ps1'; ValidateRecovered='Validate-Recovered.ps1'; Cleanup='Cleanup.ps1' } }"
try {
    Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName absent -ScenariosRoot $testRoot } 'Unknown scenario' 'Unknown scenario fails closed.'
    Write-TestScenario $testRoot unknown ($base.Replace('NAME','unknown').Replace("Description='test'","Description='test'; Surprise='blocked'"))
    Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName unknown -ScenariosRoot $testRoot } 'unknown manifest keys' 'Unknown manifest key fails closed.'
    Write-TestScenario $testRoot schema ($base.Replace('NAME','schema').Replace('SchemaVersion=1','SchemaVersion=2'))
    Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName schema -ScenariosRoot $testRoot } 'unsupported SchemaVersion' 'Malformed schema fails closed.'
    Write-TestScenario $testRoot provider ($base.Replace('NAME','provider').Replace("@('aks')","@('eks')"))
    Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName provider -ScenariosRoot $testRoot } 'does not support provider' 'Unsupported provider fails closed.'
    Write-TestScenario $testRoot profile ($base.Replace('NAME','profile').Replace("SupportedProfiles=@('minimal')","SupportedProfiles=@('cilium')"))
    Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName profile -ScenariosRoot $testRoot } 'does not support profile' 'Unsupported profile fails closed.'
    Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName '../escape' -ScenariosRoot $testRoot } 'Invalid scenario name' 'Scenario path traversal fails closed.'
    Write-TestScenario $testRoot outside ($base.Replace('NAME','outside').Replace("Inject='Inject.ps1'","Inject='../outside.ps1'")); Set-Content (Join-Path $testRoot 'outside.ps1') '[CmdletBinding()] param()'
    Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName outside -ScenariosRoot $testRoot } "hook 'Inject'.*beneath" 'Hook outside scenario root fails closed.'
    Write-TestScenario $testRoot missing ($base.Replace('NAME','missing').Replace("; Cleanup='Cleanup.ps1'",''));
    Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName missing -ScenariosRoot $testRoot } "missing required hook 'Cleanup'" 'Missing required hook fails closed.'
    $metadata = Join-Path $testRoot 'aks.tfplan.profile'
    Set-Content $metadata '{"Profile":"minimal","Scenario":"service-selector-mismatch","PlanSha256":"test"}'
    Assert-ThrowsLike { Assert-AksSavedPlanScenario -MetadataPath $metadata -RequestedScenario none } 'Saved plan scenario mismatch' 'Canonical selector plan cannot provision as none.'
    Assert-ThrowsLike { Assert-AksSavedPlanScenario -MetadataPath $metadata -RequestedScenario readiness-probe-failure } 'Saved plan scenario mismatch' 'Canonical selector plan cannot provision as readiness.'
    Set-Content $metadata '{"Profile":"minimal","Scenario":"none","PlanSha256":"test"}'
    Assert-ThrowsLike { Assert-AksSavedPlanScenario -MetadataPath $metadata -RequestedScenario service-selector-mismatch } 'Saved plan scenario mismatch' 'Scenario-none plan cannot provision as canonical selector scenario.'
    Set-Content $metadata '{"Profile":"minimal","Scenario":"readiness-probe-failure","PlanSha256":"test"}'
    Assert-ThrowsLike { Assert-AksSavedPlanScenario -MetadataPath $metadata -RequestedScenario service-selector-mismatch } 'Saved plan scenario mismatch' 'Readiness plan cannot provision as canonical selector scenario.'
    Set-Content $metadata '{"Profile":"minimal","Scenario":"bad-service-selector","PlanSha256":"test"}'
    Assert-ThrowsLike { Assert-AksSavedPlanScenario -MetadataPath $metadata -RequestedScenario service-selector-mismatch } 'Saved plan scenario mismatch' 'Stale bad-service-selector metadata cannot provision as canonical selector scenario.'
    Set-Content $metadata '{"Profile":"minimal","Scenario":"first","PlanSha256":"test"}'
    Assert-ThrowsLike { Assert-AksSavedPlanScenario -MetadataPath $metadata -RequestedScenario second } 'Saved plan scenario mismatch' 'One named scenario cannot silently become another.'
    $liveStatus = [pscustomobject]@{ State='ACTIVE'; Profile='cilium'; ResourceGroup='rg-test' }
    Assert-ThrowsLike { Assert-AksLiveLabProfile -Status $liveStatus -RequestedProfile minimal } 'Live AKS lab profile mismatch' 'Existing profile mismatch protection remains intact.'
} finally { if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force } }
Write-Host 'PASS: Scenario contract tests completed without Azure access.' -ForegroundColor Green