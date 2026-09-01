# Milestone 21: provider-neutral lifecycle foundation discovery

## Scope and baseline

M21 is a read-only, design-only reassessment at accepted baseline `17201bea49feb5ad36759bf857b488d8edb2c7d2` (`refactor: consume cluster foundation v0.1.0`). It changes documentation only. It does not modify either provider, any public contract, or pinned `cluster-foundation` v0.1.0 commit `06509854104d8b0289790a6ec3b3bd9053761522`.

```text
                provider-neutral lifecycle contract
                         /               \
                  AKS adapter         EKS adapter
                      |                   |
                Azure-native         AWS-native
                implementation       implementation
```

This is not a universal Terraform/OpenTofu implementation. A shared contract may describe outcomes while each provider independently discovers, creates, connects to, and removes its resources.

## Active lifecycle inventory

### AKS

`scripts/Invoke-Lab.ps1` is an AKS-only orchestrator. It resolves a profile and scenario, sequences the lifecycle, records timings, and prioritizes destroy plus verify-clean after any attempted provision. `providers/azure/aks/scripts/Lab-Aks.ps1` implements doctor, status, plan, provision, connect, bootstrap, inspect, destroy, and verify-clean. `scripts/Validate-Lab.ps1`, common validation, the AKS validator, and an optional profile validator implement validate.

- **Doctor/preflight:** checks tools/OpenTofu, exact Azure subscription, provider registration, Kubernetes/addon availability, VM restrictions, quota, and existing-lab/profile state.
- **Plan:** initializes/validates OpenTofu, writes a plan, allowlists resource types, rejects deletes, and binds profile, scenario, and SHA-256 in metadata.
- **Provision:** requires `NO LAB`, validates saved-plan bindings, shows PAYG policy, and applies only that plan.
- **Status:** Azure resource-group existence plus ownership/temporal tags produce native `NO LAB`, `ACTIVE`, `STALE`, `EXISTING UNCLASSIFIED`, or `EXISTING INVALID`.
- **Connect:** gets Azure admin credentials, normalizes/selects the exact context, and checks cluster/node access.
- **Bootstrap:** applies the profile composition and waits for four named breakfix Deployments.
- **Validate:** checks context, common Kubernetes/storage behavior, AKS facts, and profile acceptance.
- **Inspect:** validates status/profile/TTL/data-plane/mesh, duplicate protection, and emits cloud/Kubernetes evidence.
- **Destroy:** attempts scenario/Kubernetes cleanup while the API exists, then uses provider-native OpenTofu destroy.
- **Verify-clean:** requires primary/node groups absent, zero tagged leftovers, and final `NO LAB`.

AKS state is local OpenTofu state plus live Azure ownership tags. Context includes subscription, location, groups, cluster/context names, networking, profile inputs, and plan metadata. Failures are exceptions and checked command exits; Breakfix Operations translates status failures separately.

### EKS

EKS has an independent AWS-native OpenTofu root but no top-level lifecycle adapter. The README sequence is manual: `tofu init/apply`, a PowerShell or Bash connection script, `kubectl apply -k kubernetes`, `Validate-Lab.ps1 -Provider eks`, and `tofu destroy`.

- **Doctor/preflight:** partial. Connection scripts check tools, AWS caller identity, and access; OpenTofu checks configuration. No consolidated quota/configuration/existing-lab gate exists.
- **Plan:** partial. OpenTofu can plan, but no adapter requires a saved plan or binds identity/profile/scenario.
- **Provision:** partial lifecycle support through direct `tofu apply`; no normalized guarded adapter exists.
- **Status:** unsupported. `get_lab_status` intentionally returns `PROVIDER_UNSUPPORTED` for EKS.
- **Connect:** implemented in PowerShell/Bash via `aws eks update-kubeconfig` and `kubectl get nodes`; it mutates kubeconfig.
- **Bootstrap:** partial/manual through canonical EKS Kustomize; no accepted-rollout coordinator.
- **Validate:** implemented through common Kubernetes plus EKS control-plane, storage-class, and EBS deletion checks.
- **Inspect:** partial/manual; no bounded result exists.
- **Destroy:** partial through direct `tofu destroy`, with known preserved-ECR exceptions and no cleanup coordinator.
- **Verify-clean:** unsupported; no ownership inventory, state-zero assertion, secondary-resource check, or retained-resource result exists.

EKS state is independent local OpenTofu state. Context is split between variables/outputs and hard-coded connection defaults; AWS profile is optional and Windows/WSL kubeconfigs differ. It has no breakfix profile identity, timestamps, plan metadata, or normalized errors. Preserved ECR is an external exception and known lifecycle mismatch.

## Capability matrix

| Capability | AKS | EKS | Difference and ownership |
| --- | --- | --- | --- |
| doctor/preflight | `IMPLEMENTED` | `PARTIAL` | EKS parity gap; cloud checks stay provider-native, eventual result shape may be foundation-owned. |
| plan | `IMPLEMENTED` | `PARTIAL` | AKS has breakfix saved-plan policy; production remains provider-native; EKS lacks integrity binding. |
| provision | `IMPLEMENTED` | `PARTIAL` | Both create natively, only AKS has guarded orchestration; no generic OpenTofu layer. |
| status | `IMPLEMENTED` | `UNSUPPORTED` | Discovery is provider-owned; pure normalization is reusable; EKS needs a producer. |
| connect | `IMPLEMENTED` | `IMPLEMENTED` | Equivalent intent, different native authentication; both mutate kubeconfig and lack structured results. |
| bootstrap | `IMPLEMENTED` | `PARTIAL` | AKS mixes breakfix rollout policy; EKS is manual. Needs decoupling. |
| validate | `IMPLEMENTED` | `IMPLEMENTED` | Common facts plus native provider checks; profile acceptance stays breakfix-owned. |
| inspect | `IMPLEMENTED` | `PARTIAL` | AKS mixes native facts/presentation; EKS lacks a bounded adapter. |
| destroy | `IMPLEMENTED` | `PARTIAL` | Both destroy natively; only AKS coordinates live cleanup. ECR/EKS cleanup are gaps. |
| verify-clean | `IMPLEMENTED` | `UNSUPPORTED` | Invariant is reusable, evidence stays native, and EKS has no producer. |

Provider implementations have `DIFFERENT_SEMANTICS` even where both are implemented: authentication, discovery, state, resource containers, and backing-storage cleanup must remain native. `PARTIAL` means the core action exists but normalized guardrails/outcomes do not.

## Status contract audit

AKS resource-group absence produces `NO LAB`. A correctly owned group with valid timestamps is `ACTIVE` before expiry and `STALE` at/after expiry. Missing/wrong ownership produces `EXISTING UNCLASSIFIED`; invalid timestamps produce `EXISTING INVALID`. Azure discovery failure throws rather than pretending state is known.

`Get-BreakfixLabStatus` performs a second pure normalization: native `NO LAB`/`NO_LAB` becomes `NO_LAB`; `ACTIVE`/`STALE` survive only with parseable timestamps; other native states become `UNKNOWN`; collection failure becomes `LAB_STATE_UNAVAILABLE`. Output is provider, normalized state, optional profile/timestamps, and `ConnectionState=UNKNOWN`. It is read-only and does not acquire kubeconfig credentials.

EKS has no lab status. EKS control-plane `ACTIVE` in validation is not breakfix lab `ACTIVE`: it proves neither ownership, expiry, nor the complete lab. Equating them would fabricate parity.

The reusable portion belongs beneath Breakfix Operations. A foundation primitive can validate and normalize provider-produced observations without Azure, AWS, operations, or transport knowledge. Neutral fields are provider identity, state, optional lab/profile identity, timestamps, and optional connection state. Resource groups, AWS account/region, native tags/states, and discovery evidence remain provider-specific. `UNKNOWN` means collected facts cannot be classified; collection failure remains an error, not successful `UNKNOWN`.

## Error contract audit

AKS uses lifecycle exceptions and checked exits. EKS scripts print/exit and OpenTofu/validators return native exits. Breakfix Operations owns its versioned success/error envelope and breakfix code allowlist.

A future foundation lifecycle result could represent success/failure, a bounded category, safe message, and adapter-selected diagnostic detail. Breakfix Operations must retain operation names, versions, codes, sanitization, and envelope. This is not ready: no second normalized provider exists and mapping shell, PowerShell, OpenTofu, cloud authorization, and ambiguity requires multiple policies. Classification: `NEEDS_PROVIDER_PARITY` and `NEEDS_DECOUPLING`.

## Connection-context audit

AKS uses Azure admin credential acquisition and exact context normalization. EKS uses the default AWS chain or named profile and `update-kubeconfig`. Both mutate a user kubeconfig.

Consumers need only non-secret provider/cluster/location identity, optional explicit kubeconfig path, exact context, selection state, and API-probe result. Credentials, tokens, certificates, and kubeconfig content remain provider-owned and must never cross the contract.

A neutral context is plausible but not ready: AKS has no structured result, EKS duplicates PowerShell/Bash with hard-coded identity, neither takes an explicit destination, and mutation/rollback semantics are undefined. Classification: `NEEDS_DECOUPLING`.

## Plan/provision audit

AKS produces a saved plan and profile/scenario/SHA binding, rejects unexpected types/deletes, and blocks duplicate provision. EKS takes Terraform inputs directly and uses ordinary local state/outputs; its documented apply requires no approved artifact or breakfix binding.

The eventual abstraction remains `Plan(request) -> result` and `Provision(approved plan) -> result`, identifying provider, independent root, immutable configuration identity, plan identity/hash, change summary, and exceptions. It must never share modules, state, provider arguments, or resource allowlists. This is not ready because AKS metadata mixes breakfix policy and EKS lacks an approved-plan contract. Classification: `NEEDS_PROVIDER_PARITY`.

## Destroy/verify-clean audit

AKS orders reconnection, scenario/validation/bootstrap cleanup, provider destroy, group/tag absence, and final `NO LAB`. These zero-leftover semantics cannot be weakened.

EKS has direct destroy but no live cleanup orchestration, AWS ownership discovery, state-zero check, generated-resource check, or retained-resource report. Preserved ECR is outside ephemeral ownership but shares the root, so successful destroy alone cannot prove no lab remains.

Reusable semantics are: destroy reports provider destruction; verify-clean succeeds only after a provider positively proves no owned lab remains and reports declared exceptions separately. Evidence remains provider-native. This needs EKS parity and machine-readable ECR ownership. Classification: `NEEDS_PROVIDER_PARITY`.

## Ownership boundaries

| Behavior | Owner |
| --- | --- |
| Normalized state vocabulary and pure observation validation | `FOUNDATION_CONTRACT` candidate |
| Azure/AWS discovery, authentication, quota checks, infrastructure/state, kubeconfig mutation, cloud cleanup | `PROVIDER_IMPLEMENTATION` |
| Profile/scenario, TTL/cost display, duplicate-provision operator policy, scenario ordering/cleanup, expected failure/recovery, acceptance timing | `BREAKFIX_POLICY` |
| Current error, connection, plan/provision, and destroy/verify-clean extraction | `NOT_READY_FOR_EXTRACTION` |

The lifecycle sequence and lab standard remain breakfix-owned outcome policy for now, evidence for contracts rather than authorization to move the orchestrator.

## Candidate extraction slices

### A. Pure lifecycle status normalization — `READY_FOR_EXTRACTION`

- **Contract:** validate a bounded provider observation and return exactly `NO_LAB`, `ACTIVE`, `STALE`, or `UNKNOWN`, with validated optional identity/timestamps; reject unavailable/malformed required facts. No cloud calls or mutation.
- **AKS:** `Get-AksLabStatus` produces native facts; `Get-BreakfixLabStatus` consumes and normalizes them.
- **EKS:** no producer today. Independent testing does not claim EKS parity; a future AWS adapter may adopt it.
- **Retained behavior:** discovery remains provider-owned; Operations retains envelope/error/presentation; TTL policy remains breakfix-owned.
- **Risk/prerequisite:** low if collection failure remains distinct from `UNKNOWN`; characterize current mappings before migration.
- **Owner:** `cluster-foundation`; the primitive is provider- and transport-neutral with a real current seam.

### B. Lifecycle error/result primitive — `NEEDS_PROVIDER_PARITY`

No shared provider result exists. Safe diagnostic fields and categories need characterization; M12 error codes stay breakfix-owned.

### C. Connection-context contract — `NEEDS_DECOUPLING`

The non-secret result is reusable, but implicit kubeconfig mutation and console-only results must first become explicit per provider.

### D. Plan/provision interface — `NEEDS_PROVIDER_PARITY`

AKS has strong identity; EKS does not. Provider plans/state remain independent; no universal OpenTofu abstraction.

### E. Destroy/verify-clean interface — `NEEDS_PROVIDER_PARITY`

The no-lab invariant is reusable, but EKS cannot prove it and retained ECR is not represented in a cleanup result.

### F. Whole lifecycle, TTL, scenarios, acceptance — `NOT_FOUNDATION`

These express breakfix policy. Moving them would produce a universal implementation or move behavior out of its owner.

## Recommended M22

Implement exactly one slice: a versioned pure lifecycle-status normalization contract in `cluster-foundation`, then atomically migrate the platform consumer and remove duplicate normalization. It must have no cloud CLI, OpenTofu, kubectl, kubeconfig, filesystem discovery, or Operations knowledge; preserve all four states; distinguish collection failure from `UNKNOWN`; keep Operations v1/v2 behavior compatible; adapt only the existing AKS consumer; and defer EKS status production.

Required provider changes: none. Required breakfix change: delegate only pure normalization while retaining operation mapping/presentation. Required foundation change: add/test the primitive in a signed release, then atomically update submodule/lock. No existing public contract changes.

This is genuinely reusable because it describes ephemeral-lab facts independently of cloud discovery and transport. It serves a real AKS provider-to-operation seam now and creates a truthful seam for future EKS without pretending EKS support exists.

No larger capability is recommended. Extracting connection, error, plan/provision, or destroy/verify-clean now would weaken AKS, leak native detail, move breakfix policy, require simultaneous capabilities, or fabricate EKS parity.