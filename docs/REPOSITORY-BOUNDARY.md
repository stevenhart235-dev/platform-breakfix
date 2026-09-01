# Repository boundary

This document is the canonical architectural fence for `platform-breakfix`. It governs future extraction and any CLI, HTTP API, or MCP design.

## Purpose and dependency direction

`platform-breakfix` is an ephemeral infrastructure proving ground and a deterministic break/fix lab. It validates provider, profile, lifecycle, and scenario behavior. It may prove reusable cluster-foundation primitives, but it is not an application-platform control plane.

The required long-term dependency direction is:

```text
                    cluster-foundation
                      ^           ^
                      |           |
             platform-breakfix   future-platform
```

`cluster-foundation` is the single owner of reusable cluster and diagnostic primitives. `platform-breakfix` consumes them to run deterministic labs. A future platform consumes them to compose and reconcile application-platform capabilities. The future platform must never depend on `platform-breakfix`, and reusable implementation must not be copied between repositories.

## Ownership matrix

| Domain | Owns | May consume | Must not own |
| --- | --- | --- | --- |
| `platform-breakfix` | Ephemeral lab semantics; break/fix orchestration; scenario catalog and compatibility; expected-failure behavior; scenario injection, repair, and observation gathering; acceptance tests and milestone evidence; lab-oriented operator interface. | Provider provisioning, profiles/addons, guardrails, validation/preflight, generic scenario execution, evidence, and diagnosis primitives from foundation. | Application-platform reconciliation or application lifecycle. |
| Future `cluster-foundation` | Provider-native AKS/EKS create and teardown; reusable profile/addon mechanisms; lifecycle, TTL, plan-binding, and cleanup guardrails; reusable preflight/validation; generic scenario execution; evidence schema/serialization; generic diagnosis execution. | Cloud/provider SDKs and provider-native infrastructure implementations. | Scenario catalog, application-platform composition, or a universal cross-cloud Terraform implementation. |
| Future platform repository | Cloudflare, identity, platform networking/policy, Ceph, Kafka, databases, GitOps, observability, application contracts, onboarding, self-service, promotion, application lifecycle, placement, and platform reconciliation. | Proven foundation capabilities through stable contracts. | Foundation implementation copied from another consumer, or dependencies through `platform-breakfix`. |

Provider-specific behavior remains visible. Put a stable capability contract above independently understandable `providers/aks` and `providers/eks` implementations; do not replace them with one universal implementation. Do not introduce `UniversalCloudClusterFactory`, `GenericInfrastructureProvider`, `MultiCloudPlacementEngine`, `PlatformCapabilityReconciler`, or an equivalent giant abstraction without a concrete existing requirement.

## Hard exclusions from platform-breakfix

The following responsibilities and placeholders are forbidden:

- `ApplicationBlueprint` or application-blueprint abstractions
- application contracts, onboarding, or dependency resolution
- developer self-service or developer portals
- platform capability or application reconciliation
- multi-cloud workload placement or cross-provider workload scheduling
- application deployment lifecycle, rollout, or environment promotion
- application database or Kafka provisioning
- Ceph application-storage orchestration
- Cloudflare application-routing orchestration
- application identity lifecycle
- GitOps application management
- platform product catalogs
- application control-plane state
- tenant or application ownership models

## Similar names, different abstractions

A **breakfix profile** is a tested cluster configuration appropriate for a deterministic lab, such as `minimal`, `cilium`, or `istio`. It is not a future platform application contract describing capabilities that a control plane must reconcile. The lab taxonomy must not become a platform API accidentally.

A **breakfix scenario** injects, observes, diagnoses, and repairs a bounded condition in a lab. It is not an application deployment, rollout, promotion, reconciliation, or lifecycle operation.

## Extraction principles

1. Give each reusable implementation one canonical owner.
2. Make `platform-breakfix` consume that implementation without copying it.
3. Preserve existing breakfix regressions and provider behavior.
4. Keep AKS and EKS implementations independently understandable beneath stable outcome contracts.
5. Extract leaf contracts before lifecycle orchestrators that depend on them.
6. Keep the breakfix scenario catalog, expected-failure semantics, and milestone evidence in `platform-breakfix`.
7. Extraction is incomplete while copy-and-diverge implementations remain or while a future platform must reach through `platform-breakfix`.

Profile schema/parsing and addon installation mechanisms may move to foundation. Exact lab profiles remain breakfix-owned unless they are promoted deliberately as reusable tested cluster configurations. Reusable addon mechanisms may move; synthetic lab workloads and acceptance assertions do not.

Generic scenario resolution, hook execution, and cleanup/finally behavior may move to foundation after fixed lab workload names and provider entry points are removed from the generic primitive. Scenario definitions remain here.

Evidence shape, validation, serialization, and artifact I/O are shared-contract candidates. A generic exactly-one diagnosis executor may move to foundation; the current rules for the two breakfix scenarios remain with the breakfix catalog unless another consumer adopts the same diagnostic contract.

### First implemented foundation boundary

M11 designed the ownership boundary. M16 proves its first concrete in-repository extraction under `foundation/`: generic deterministic exactly-one selection is foundation-owned and has one canonical implementation. `scripts/ScenarioDiagnosis.ps1` consumes that primitive while retaining breakfix-owned observation predicates, diagnosis identifiers, summaries, and failure semantics.

This is intentionally a source boundary inside `platform-breakfix`, not a new repository or package. No future-platform dependency exists yet, and foundation code has no dependency back into breakfix, scenarios, providers, health, dashboard, or lifecycle code.

M17 proves a second genuine, independent consumer after rejecting profile resolution as a force-fit: `providers/azure/aks/scripts/Lab-Aks.ps1` delegates the existing bounded managed-Istio revision zero/one/many decision to the same primitive. Azure catalog acquisition, the requested revision predicate, Kubernetes compatibility, and lifecycle errors remain provider-owned. The two consumers—breakfix diagnosis and AKS managed-Istio revision resolution—do not depend on each other, and generic selection remains implemented once. Physical extraction to a future `cluster-foundation` repository is now architecturally justified but remains intentionally deferred to a separate milestone.

M18 designed that physical move. M19 published signed `cluster-foundation` v0.1.0 at commit `06509854104d8b0289790a6ec3b3bd9053761522`. M20 completes the atomic consumer migration: `platform-breakfix` consumes the allowlisted repository through the gitlink-pinned submodule at `external/cluster-foundation`, with `external/cluster-foundation.lock.json` binding URL, version, signed tag, commit, contract major, source path, and source SHA-256.

After M20, `cluster-foundation` is the sole canonical owner of deterministic selection. Both platform consumers load its pinned source directly; the former local implementation and neutral test are removed. Foundation owns neutral unit/contract tests, while the platform owns dependency-integrity and consumer compatibility tests. Floating branches, runtime downloads, vendored fallbacks, and manual source copying are forbidden. Fresh clones use `git clone --recurse-submodules`; existing clones use `git submodule update --init --recursive`. Rollback reverts the complete M20 migration commit, or atomically restores a prior gitlink and lock for a later dependency update.

### Lifecycle foundation boundary

M21 audits the active AKS and EKS lifecycles without changing implementation. The next boundary is not a shared orchestrator or generic cross-cloud OpenTofu layer. Providers own cloud discovery, credentials, infrastructure/state, connection mutation, and resource cleanup; breakfix owns profiles, scenarios, TTL/cost policy, operator ordering, expected-failure semantics, acceptance, and cleanup priority.

The smallest ready slice is pure lifecycle-status normalization beneath Breakfix Operations. Foundation may validate a bounded provider observation and normalize it to `NO_LAB`, `ACTIVE`, `STALE`, or `UNKNOWN`; it must not collect cloud facts, turn collection failures into successful `UNKNOWN`, or own the Operations envelope. AKS has a real producer/consumer seam. EKS remains unsupported until an AWS-native adapter proves ownership and temporal state; EKS control-plane `ACTIVE` alone is not lab `ACTIVE`.

Connection-context, lifecycle error/result, plan/provision, and destroy/verify-clean remain candidates, not approved extraction. They require decoupling or EKS parity first. AKS zero-leftover verification must not be weakened, preserved ECR ownership must stay explicit, credentials must never enter a shared context, and provider modules/state remain independent. See [AKS-MILESTONE-21.md](AKS-MILESTONE-21.md).
### Second implemented foundation capability

M22 publishes signed `cluster-foundation` v0.2.0 at commit `d042fa4e9a3b8ef975554fa56b7c9a4b61547e54` and atomically transfers pure lifecycle-status normalization. Foundation now owns strict neutral observation validation and deterministic `NO_LAB`/`ACTIVE`/`STALE`/`UNKNOWN` normalization. AKS retains Azure discovery and native observation interpretation; Breakfix Operations retains provider support, envelopes, errors, result fields, and presentation. EKS status remains unsupported.

The platform pins the v0.2.0 gitlink and lock, verifies both foundation source blobs and the signed tag, and contains no duplicate generic lifecycle-status implementation. This extraction does not authorize connection, plan/provision, lifecycle error, destroy/verify-clean, or orchestration work. Rollback restores the complete v0.1.0 dependency and consumer commit atomically; source copying is forbidden. See [AKS-MILESTONE-22.md](AKS-MILESTONE-22.md).
## Breakfix capability interface

The transport-neutral breakfix contract is limited to:

```text
create_lab            get_lab_status       inspect_lab
list_profiles         list_scenarios       run_scenario
collect_evidence      diagnose             validate_lab
destroy_lab           verify_clean
```

`create_lab`, `run_scenario`, and `destroy_lab` mutate durable lab state. `validate_lab` is logically validation but currently creates and removes temporary Kubernetes storage-test resources, so it must be treated as a bounded mutation. Status, inspection, listing, evidence collection, diagnosis, and cleanup verification are read-only with respect to cloud/Kubernetes state; evidence collection may overwrite its ignored local artifact.

CLI commands, HTTP resources, and MCP tools are transport adapters over this one capability contract. They must not become independent contracts or add application-platform operations. Mutation must remain explicit, fail closed, preserve saved-plan/profile/scenario binding, prioritize cleanup, and never be silently authorized by a read-only transport call.

Breakfix Operations v1 exposes the read-only subset `list_profiles`, `list_scenarios`, `read_evidence`, `diagnose_evidence`, and `get_lab_status`. The evidence operations read an existing bounded local artifact and diagnose it offline; they do not collect fresh cluster evidence. The CLI is the first adapter. Future HTTP and MCP adapters must preserve these operation semantics and delegate to the same operation layer.

## Future extension rules

- Add a capability only when it serves deterministic ephemeral lab behavior.
- Keep read-only operations separable from mutating operations and surface mutations only after authorization, idempotency, and cleanup semantics exist.
- Add provider adapters rather than cloud conditionals inside a universal infrastructure implementation.
- Promote reusable code only with a consuming `platform-breakfix` integration and regression parity; do not copy it speculatively.
- Reject application-platform vocabulary and placeholders at review time.
- Update this boundary document before approving a change that alters repository ownership or dependency direction.
