[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $RepositoryRoot 'providers/azure/aks/scripts/Profile-Aks.ps1')

function Assert-ThrowsLike {
    param([Parameter(Mandatory)][scriptblock] $Action, [Parameter(Mandatory)][string] $Pattern, [Parameter(Mandatory)][string] $Message)
    try { & $Action }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw "$Message Unexpected error: $($_.Exception.Message)" }
        Write-Host "PASS: $Message" -ForegroundColor Green
        return
    }
    throw "$Message Expected an error matching '$Pattern'."
}

function Write-TestProfile {
    param([Parameter(Mandatory)][string] $Root, [Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][string] $Manifest)
    $profileRoot = Join-Path $Root $Name
    $kubernetesRoot = Join-Path $profileRoot 'kubernetes'
    New-Item -ItemType Directory -Path $kubernetesRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $profileRoot 'profile.psd1') -Value $Manifest -Encoding utf8
    Set-Content -LiteralPath (Join-Path $kubernetesRoot 'kustomization.yaml') -Value @(
        'apiVersion: kustomize.config.k8s.io/v1beta1', 'kind: Kustomization', 'resources: []'
    ) -Encoding utf8
}

$productionProfiles = Join-Path $RepositoryRoot 'providers/azure/aks/profiles'
$implicit = Resolve-AksProfile -Provider aks -ProfileName minimal -ProfilesRoot $productionProfiles
$explicit = Resolve-AksProfile -Provider aks -ProfileName minimal -ProfilesRoot $productionProfiles
if ($implicit.Name -ne $explicit.Name -or
    $implicit.InfrastructureInputs.NetworkDataPlane -ne $explicit.InfrastructureInputs.NetworkDataPlane -or
    $implicit.InfrastructureInputs.NodeVmSize -ne $explicit.InfrastructureInputs.NodeVmSize -or
    $implicit.InfrastructureInputs.NodeCount -ne $explicit.InfrastructureInputs.NodeCount) {
    throw 'Default and explicit minimal resolution differ.'
}
Write-Host 'PASS: Omitted/default and explicit minimal resolve to the same normalized profile.' -ForegroundColor Green

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "platform-breakfix-aks-profile-tests-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    Assert-ThrowsLike -Action { Resolve-AksProfile -Provider aks -ProfileName absent -ProfilesRoot $testRoot } -Pattern 'Unknown AKS profile' -Message 'Unknown profile fails closed.'
    Write-TestProfile -Root $testRoot -Name mismatch -Manifest "@{ SchemaVersion = 1; Name = 'mismatch'; Provider = 'eks'; InfrastructureInputs = @{ NetworkDataPlane = 'azure'; NodeVmSize = 'Standard_D2as_v7'; NodeCount = 1 }; BootstrapComposition = 'kubernetes' }"
    Assert-ThrowsLike -Action { Resolve-AksProfile -Provider aks -ProfileName mismatch -ProfilesRoot $testRoot } -Pattern "belongs to provider 'eks'" -Message 'Provider/profile mismatch fails closed.'
    Write-TestProfile -Root $testRoot -Name unknown-key -Manifest "@{ SchemaVersion = 1; Name = 'unknown-key'; Provider = 'aks'; InfrastructureInputs = @{ NetworkDataPlane = 'azure'; NodeVmSize = 'Standard_D2as_v7'; NodeCount = 1 }; BootstrapComposition = 'kubernetes'; Surprise = 'blocked' }"
    Assert-ThrowsLike -Action { Resolve-AksProfile -Provider aks -ProfileName unknown-key -ProfilesRoot $testRoot } -Pattern 'unknown manifest keys' -Message 'Unknown manifest key fails closed.'
    Write-TestProfile -Root $testRoot -Name unknown-input -Manifest "@{ SchemaVersion = 1; Name = 'unknown-input'; Provider = 'aks'; InfrastructureInputs = @{ NetworkDataPlane = 'azure'; NodeVmSize = 'Standard_D2as_v7'; NodeCount = 1; ArbitraryTerraformVariable = 'blocked' }; BootstrapComposition = 'kubernetes' }"
    Assert-ThrowsLike -Action { Resolve-AksProfile -Provider aks -ProfileName unknown-input -ProfilesRoot $testRoot } -Pattern 'unknown InfrastructureInputs' -Message 'Unknown infrastructure input fails closed.'
    Write-TestProfile -Root $testRoot -Name invalid-path -Manifest "@{ SchemaVersion = 1; Name = 'invalid-path'; Provider = 'aks'; InfrastructureInputs = @{ NetworkDataPlane = 'azure'; NodeVmSize = 'Standard_D2as_v7'; NodeCount = 1 }; BootstrapComposition = '..' }"
    Assert-ThrowsLike -Action { Resolve-AksProfile -Provider aks -ProfileName invalid-path -ProfilesRoot $testRoot } -Pattern 'beneath its profile directory' -Message 'Profile path traversal fails closed.'

    $metadataPath = Join-Path $testRoot 'aks.tfplan.profile'
    $planPath = Join-Path $testRoot 'aks.tfplan'
    Set-Content -LiteralPath $planPath -Value 'deterministic-test-plan' -Encoding utf8
    Set-Content -LiteralPath $metadataPath -Value '{"Profile":"different","PlanSha256":"unused"}' -Encoding utf8
    Assert-ThrowsLike -Action { Assert-AksSavedPlanProfile -MetadataPath $metadataPath -PlanPath $planPath -RequestedProfile minimal } -Pattern 'Saved plan profile mismatch' -Message 'Saved-plan/profile mismatch is detected.'
    $liveStatus = [pscustomobject]@{ State = 'ACTIVE'; Profile = 'different'; ResourceGroup = 'rg-test' }
    Assert-ThrowsLike -Action { Assert-AksLiveLabProfile -Status $liveStatus -RequestedProfile minimal } -Pattern 'Live AKS lab profile mismatch' -Message 'Live-lab/profile mismatch is detected.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host 'PASS: AKS profile contract negative tests completed without Azure access.' -ForegroundColor Green
