[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$providerPath = Join-Path $RepositoryRoot 'providers/azure/aks/scripts/Lab-Aks.ps1'
$foundationPath = Join-Path $RepositoryRoot 'foundation/DeterministicSelection.ps1'
. $providerPath

function New-Revision([string]$Revision,[string[]]$Versions,[string]$Marker) {
    [pscustomobject][ordered]@{ revision=$Revision; marker=$Marker; compatibleWith=@([pscustomobject][ordered]@{name='KubernetesOfficial';versions=@($Versions)}) }
}
function Assert-FailsExact([string]$Name,[scriptblock]$Action,[string]$Expected) {
    try { & $Action | Out-Null } catch { if($_.Exception.Message -cne $Expected){throw "$Name returned unexpected error: $($_.Exception.Message)"};Write-Host "PASS: $Name fails with the bounded provider error." -ForegroundColor Green;return };throw "$Name unexpectedly succeeded."
}
function Assert-True([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}

$requested='asm-1-30';$minor='1.35';$failure="Managed Istio revision '$requested' is not offered for Kubernetes $minor in eastus2."
Assert-FailsExact 'zero requested-revision matches' { Resolve-AksManagedIstioRevision -Revisions @((New-Revision 'asm-1-29' @('1.35') old)) -RequestedRevision $requested -KubernetesMinorVersion $minor } $failure
$selectedObject=New-Revision $requested @($minor) selected
$selected=Resolve-AksManagedIstioRevision -Revisions @($selectedObject) -RequestedRevision $requested -KubernetesMinorVersion $minor
Assert-True ([object]::ReferenceEquals($selected,$selectedObject)) 'Exactly-one selection did not preserve the original revision object.'
Write-Host 'PASS: exactly one match succeeds and preserves the original object.' -ForegroundColor Green
$duplicate=New-Revision $requested @($minor) duplicate
Assert-FailsExact 'multiple requested-revision matches' { Resolve-AksManagedIstioRevision -Revisions @($selectedObject,$duplicate) -RequestedRevision $requested -KubernetesMinorVersion $minor } $failure
$unrelatedA=New-Revision 'asm-1-28' @($minor) a;$unrelatedB=New-Revision 'asm-1-31' @($minor) b
$forward=Resolve-AksManagedIstioRevision -Revisions @($unrelatedA,$selectedObject,$unrelatedB) -RequestedRevision $requested -KubernetesMinorVersion $minor
$reverse=Resolve-AksManagedIstioRevision -Revisions @($unrelatedB,$selectedObject,$unrelatedA) -RequestedRevision $requested -KubernetesMinorVersion $minor
Assert-True ([object]::ReferenceEquals($forward,$selectedObject) -and [object]::ReferenceEquals($reverse,$selectedObject)) 'Unrelated entries or candidate order changed selection.'
Write-Host 'PASS: unrelated entries and catalog ordering do not change the semantic result.' -ForegroundColor Green
$incompatible=New-Revision $requested @('1.34') incompatible
Assert-FailsExact 'incompatible Kubernetes version after successful selection' { Resolve-AksManagedIstioRevision -Revisions @($incompatible) -RequestedRevision $requested -KubernetesMinorVersion $minor } $failure
Write-Host 'PASS: compatibility validation executes after exact-one selection.' -ForegroundColor Green

$providerSource=Get-Content -Raw -LiteralPath $providerPath;$foundationSource=Get-Content -Raw -LiteralPath $foundationPath;$diagnosisSource=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'scripts/ScenarioDiagnosis.ps1')
Assert-True ($providerSource -match '(?s)if \(\$Profile\.InfrastructureInputs\.ServiceMeshMode -eq ''Istio''\).*Resolve-AksManagedIstioRevision') 'Doctor does not confine revision resolution to the existing Istio branch.'
Assert-True ($providerSource -match 'Resolve-DeterministicSelection -Candidates' -and $diagnosisSource -match 'Resolve-DeterministicSelection -Candidates') 'Foundation does not have both active consumers.'
Assert-True ($providerSource -notmatch 'ScenarioDiagnosis|Resolve-ScenarioDiagnosis' -and $diagnosisSource -notmatch 'Lab-Aks|Resolve-AksManagedIstioRevision') 'The two consumers depend on one another.'
Assert-True ($foundationSource -notmatch 'ScenarioDiagnosis|Lab-Aks|Resolve-AksManagedIstioRevision') 'Foundation depends on a consumer.'
$selectionGuards=@(rg -l --glob '*.ps1' '\$matches\.Count -ne 1' (Join-Path $RepositoryRoot 'foundation') (Join-Path $RepositoryRoot 'scripts') (Join-Path $RepositoryRoot 'providers'))
Assert-True ($selectionGuards.Count -eq 1 -and $selectionGuards[0] -match 'foundation[\\/]DeterministicSelection\.ps1$') 'Generic exactly-one mechanics are duplicated outside foundation.'
$helperText=[regex]::Match($providerSource,'(?s)function Resolve-AksManagedIstioRevision \{.*?\n\}').Value
Assert-True ($helperText -match '\.revision -ceq \$RequestedRevision' -and $helperText -notmatch '\$selected\.Count -ne 1|Select-Object -First') 'Provider matching predicate or exact-one delegation changed.'
Assert-True ($providerSource -match '(?s)Resolve-AksManagedIstioRevision.*?Write-Host "PASS: Managed Istio revision') 'Doctor no longer continues accepted Istio behavior after selection.'
Write-Host 'PASS: AKS doctor has two-consumer architecture with provider-owned matching and no duplicate selection guard.' -ForegroundColor Green
Write-Host 'PASS: AKS managed Istio revision deterministic-selection tests.' -ForegroundColor Green
