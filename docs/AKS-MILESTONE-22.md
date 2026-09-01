# Milestone 22: lifecycle-status foundation extraction

## Scope and release

M21 identified pure lifecycle-status normalization as the only ready lifecycle extraction slice. M22 publishes that additive contract in signed `cluster-foundation` v0.2.0 and atomically migrates the existing platform consumer. It does not add EKS status, move discovery, or change any Operations, health, evidence, scenario, profile, diagnosis, provider, infrastructure, connection, plan, destroy, or clean-verification behavior.

The foundation release is:

- repository: `https://github.com/stevenhart235-dev/cluster-foundation.git`
- version/tag: `0.2.0` / `v0.2.0`
- commit: `d042fa4e9a3b8ef975554fa56b7c9a4b61547e54`
- lifecycle source: `src/LifecycleStatus.ps1`
- lifecycle Git-blob SHA-256: `F324164D951F16D0EEC6ED871DB4BFA787D12D8C392D1A88E22F0047ED43D85B`
- deterministic-selection Git-blob SHA-256: `F03C4401552FB6F9F9BE65DB813127B8ECF020A1089A8889064F95C4A0B4D866`

The release commit and annotated tag are SSH-signed. The platform gitlink and bounded dependency lock pin the exact release commit; no branch is configured.

## Ownership layers

```text
AKS Azure observation discovery
              |
              v
platform native-to-neutral adapter
              |
              v
cluster-foundation Resolve-LifecycleStatus
              |
              v
NO_LAB / ACTIVE / STALE / UNKNOWN
              |
              v
Breakfix Operations result/envelope and CLI presentation
```

AKS continues to own Azure CLI calls, resource-group existence, ownership/timestamp tags, temporal classification, authentication, and provider errors. The thin platform adapter translates native `NO LAB`/`NO_LAB`, `ACTIVE`, `STALE`, and all other provider-native states into the bounded neutral observation vocabulary.

Foundation owns validation and deterministic normalization of exactly `State`, `CreatedAt`, and `ExpiresAt`. It returns only normalized state and UTC/null timestamps. Valid `INDETERMINATE` becomes `UNKNOWN`; `ACTIVE`/`STALE` with absent or unparseable timestamps also becomes `UNKNOWN`. Invalid neutral shape/type/state fails closed. Provider collection failure remains distinct and never becomes successful `UNKNOWN`.

Breakfix Operations continues to own supported-provider checks, profile passthrough, result field names, `ConnectionState`, operation envelope, error translation/sanitization, and presentation. Contracts v1 and v2 and CLI syntax/output are unchanged. Foundation exceptions are translated to the existing bounded `LAB_STATE_UNAVAILABLE` operation error.

EKS remains unsupported for `get_lab_status` and continues to return `PROVIDER_UNSUPPORTED`. EKS control-plane `ACTIVE` is not treated as complete lab `ACTIVE`; no AWS observation adapter is introduced.

## Canonical implementation and dependency integrity

`external/cluster-foundation/src/LifecycleStatus.ps1` is the sole reachable implementation of `Resolve-LifecycleStatus`. The former platform timestamp helper and inline generic state normalization are removed. Provider-native translation is not generic normalization and remains in the adapter.

The v0.2.0 lock verifies URL, gitlink/commit, detached HEAD, version, signed tag/target, contract major, both source paths, and both raw Git-blob hashes. Raw blobs avoid checkout line-ending differences. Dependency validation also proves both public primitives parse, each has one canonical implementation, consumers delegate, and foundation executable source has no platform/provider leakage.

Fresh clones use `git clone --recurse-submodules`; existing clones run `git submodule update --init --recursive`. Initialization must restore exact commit `d042fa4e9a3b8ef975554fa56b7c9a4b61547e54` detached at `v0.2.0`.

## Compatibility and non-goals

Existing `get_lab_status` outputs remain `Provider`, `State`, `Profile`, `CreatedAt`, `ExpiresAt`, and `ConnectionState` within the unchanged Operations envelope. Accepted states remain exactly `NO_LAB`, `ACTIVE`, `STALE`, and `UNKNOWN`. Existing malformed/missing provider observation and collection failures retain bounded failure behavior.

M22 does not extract lifecycle errors/results, connection context, plan/provision, destroy/verify-clean, orchestration, TTL, profiles, scenarios, or provider discovery. It does not change deterministic selection.

## Rollback

Rollback is atomic: revert the M22 platform migration, restoring the v0.1.0 gitlink and lock plus the previous local consumer normalization. Do not copy the v0.2.0 lifecycle source into platform-breakfix. The published signed foundation release remains immutable.