# AKS Milestone 3: Profile Framework and Minimal Profile

An AKS profile is a provider-owned, reproducible selection of the small set of
infrastructure inputs, bootstrap composition, and optional validation needed
for one tested AKS lab shape. Exactly one profile is selected per lifecycle
run. Profiles are not generic feature flags and cannot inject arbitrary
OpenTofu variables.

The minimal profile is the only implemented profile and is the default. These
commands resolve to the same profile:

    .\scripts\Invoke-Lab.ps1 -Provider aks -Operation plan
    .\scripts\Invoke-Lab.ps1 -Provider aks -Profile minimal -Operation plan

The provider-local manifest is
providers/azure/aks/profiles/minimal/profile.psd1. Resolution occurs once,
before doctor, and the normalized profile is passed through the existing
lifecycle.

## Ownership and composition

Creation-time settings such as the AKS network data plane, node VM SKU, and
node count remain provider-owned OpenTofu inputs. The profile resolver exposes
only the explicit NetworkDataPlane, NodeVmSize, and NodeCount allowlist.

Bootstrap-time Kubernetes resources compose in this order:

1. shared baseline
2. AKS provider baseline
3. selected profile additions

The minimal composition delegates to the existing AKS provider composition and
adds no Kubernetes resources. Validation always runs common validation, then
AKS provider validation, then an optional profile validator. A profile cannot
suppress either existing validation stage; minimal needs no additional
validator.

## Lifecycle and PAYG guarantees

Saved plans are bound to their selected profile by ignored local metadata.
Azure ownership tags include Profile=minimal, and live-lab inspection rejects
a requested/detected profile mismatch. Switching profiles requires explicit
destroy followed by verify-clean before planning and provisioning the new
profile.

Profiles inherit the accepted PAYG contract unchanged: stable CreatedAt and
ExpiresAt, four-hour default advisory TTL, visible cost warning, duplicate
provision blocking, cleanup in finally, explicit destroy, and verify-clean.
TTL remains advisory and never triggers automatic deletion.

Profile selection is noninteractive and suitable for reproducible automation.
Cilium and Istio remain planned future profiles; neither is implemented by
Milestone 3.
