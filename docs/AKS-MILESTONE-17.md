# AKS Milestone 17: Reuse deterministic selection for Istio revisions

Milestone 17 proves the M16 foundation primitive with a second unrelated active consumer. The accepted baseline is `bceef0f935b2777b54f3c7678128833db0bfc6b0` (`refactor: extract deterministic selection foundation`). No live Azure, AWS, or Kubernetes access is required.

## Discovery history

The initial M17 proposal considered AKS profile resolution. Discovery correctly stopped because `Resolve-AksProfile` performs direct deterministic path lookup and has no bounded zero/one/many candidate seam. Enumerating profiles or wrapping one path would have manufactured a consumer and changed filesystem semantics.

M17R then audited active repository code. The managed-Istio preflight inside `Invoke-AksDoctor` was the sole strong natural fit: Azure already returns a bounded revision catalog, the provider already filters it by the profile-requested revision, zero and multiple matches already fail, exactly one object is selected, and its Kubernetes compatibility metadata is evaluated.

## Selected seam and neutral adaptation

`Resolve-AksManagedIstioRevision` remains provider-owned in `providers/azure/aks/scripts/Lab-Aks.ps1`. It adapts every existing catalog object to the unchanged foundation shape:

```text
Name    candidate-<zero-padded catalog index>
Matches revision equals requested profile revision
Value   original Azure revision object
```

Index-based names preserve the previous match-cardinality semantics even if duplicate revision strings appear. The resolver does not select first, sort semantically, infer another revision, or fall back. `Resolve-DeterministicSelection` returns the original object only when exactly one candidate matches.

## Ownership and dependency direction

```text
scripts/ScenarioDiagnosis.ps1
            |
            v
foundation/DeterministicSelection.ps1
            ^
            |
providers/azure/aks/scripts/Lab-Aks.ps1
```

Foundation owns bounded candidate validation, deterministic ordering, unique neutral identities, and exactly-one selection. It remains byte-unchanged and unaware of diagnosis, Azure, AKS, Istio, revisions, profiles, or Kubernetes.

The AKS provider continues to own Azure CLI catalog acquisition, catalog object shape, requested revision input, equality matching, neutral adaptation, Kubernetes minor-version compatibility, and translation to the existing bounded lifecycle error. ScenarioDiagnosis continues to own its observation predicates, identifiers, and summaries. Neither consumer depends on the other.

## Compatibility guarantees

Zero or multiple requested-revision matches produce the same provider message used before M17. One match preserves and returns the original catalog object, after which the existing exact Kubernetes compatibility predicate executes. An incompatible selected revision produces the same bounded message. The minimal and Cilium branches do not call revision resolution.

No profile manifest, profile resolver, lifecycle operation sequence, OpenTofu configuration, Kubernetes manifest, scenario behavior, dashboard, registry mechanism, CLI, or public operation changed. Breakfix Operations Contracts v1/v2, Lab Health Contract v1, Evidence Contract v1, and scenario schema v1 remain unchanged.

## Validation evidence

Synthetic provider tests prove zero, one, and multiple matches; unrelated entries; order independence; original-object identity; compatibility-after-selection; incompatible-version failure; Istio-branch confinement; two independent consumers; one-way dependencies; and one canonical generic selection guard. Existing diagnosis and profile regressions remain byte-compatible. The full repository suite covers checksum-verified OpenTofu 1.11.13, AKS/EKS validation, all PowerShell parsing and provider regressions, neutral foundation tests, seven Kustomize renders, architecture and contract invariants, whitespace, and artifact exclusion.

## Physical extraction assessment

The primitive now has provider-neutral source, independent neutral tests, two unrelated active consumers, one-way dependencies, one canonical implementation, and no consumer-specific knowledge. Physical extraction into a future `cluster-foundation` repository is architecturally justified, but M17 deliberately does not perform it. Repository/package topology should be handled as its own bounded milestone.
