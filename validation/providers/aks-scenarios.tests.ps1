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
$known = Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName bad-service-selector -ScenariosRoot $productionRoot
if ($known.Name -cne 'bad-service-selector' -or $known.Provider -cne 'aks' -or $known.Profile -cne 'minimal' -or $known.Hooks.Count -ne 6) { throw 'Known scenario did not normalize correctly.' }
Write-Host 'PASS: Known scenario resolves with all explicit hooks.' -ForegroundColor Green
$none = Resolve-LabScenario -Provider aks -ProfileName minimal -ScenarioName '' -ScenariosRoot $productionRoot
if (-not $none.IsNone -or $none.Name -cne 'none') { throw 'Omitted scenario did not resolve as none.' }
Write-Host 'PASS: Omitted scenario resolves as none.' -ForegroundColor Green
Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName cilium -ScenarioName bad-service-selector -ScenariosRoot $productionRoot } 'does not support profile' 'Cilium compatibility fails closed.'
Assert-ThrowsLike { Resolve-LabScenario -Provider aks -ProfileName istio -ScenarioName bad-service-selector -ScenariosRoot $productionRoot } 'does not support profile' 'Istio compatibility fails closed.'

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
    Set-Content $metadata '{"Profile":"minimal","Scenario":"bad-service-selector","PlanSha256":"test"}'
    Assert-ThrowsLike { Assert-AksSavedPlanScenario -MetadataPath $metadata -RequestedScenario none } 'Saved plan scenario mismatch' 'Named plan cannot provision as scenario none.'
    Set-Content $metadata '{"Profile":"minimal","Scenario":"none","PlanSha256":"test"}'
    Assert-ThrowsLike { Assert-AksSavedPlanScenario -MetadataPath $metadata -RequestedScenario bad-service-selector } 'Saved plan scenario mismatch' 'Scenario-none plan cannot provision as named scenario.'
    Set-Content $metadata '{"Profile":"minimal","Scenario":"first","PlanSha256":"test"}'
    Assert-ThrowsLike { Assert-AksSavedPlanScenario -MetadataPath $metadata -RequestedScenario second } 'Saved plan scenario mismatch' 'One named scenario cannot silently become another.'
    $liveStatus = [pscustomobject]@{ State='ACTIVE'; Profile='cilium'; ResourceGroup='rg-test' }
    Assert-ThrowsLike { Assert-AksLiveLabProfile -Status $liveStatus -RequestedProfile minimal } 'Live AKS lab profile mismatch' 'Existing profile mismatch protection remains intact.'
} finally { if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force } }
Write-Host 'PASS: Scenario contract tests completed without Azure access.' -ForegroundColor Green
