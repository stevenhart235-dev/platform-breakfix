# EKS Milestone 24A: advisory lifetime policy

## Decision and scope

M24 stopped correctly because EKS had no approved advisory lifetime from which to calculate immutable `ExpiresAt`. M24A resolves only that policy prerequisite. It changes documentation, not EKS infrastructure or lifecycle behavior.

EKS independently adopts this ephemeral-lab advisory lifetime policy:

| Policy element | Decision |
| --- | --- |
| Default lifetime | 4 hours |
| Minimum override | 1 hour |
| Maximum override | 24 hours |
| Override unit | Whole hours |
| Override boundary | Creation of a new EKS lifecycle only |
| Expiration action | Advisory status only; no automatic destruction |

Zero, negative, fractional, greater-than-24, unlimited, and operator-supplied absolute expiration timestamps are prohibited.

## Operator surface

The recommended future lifecycle-creation input is:

```powershell
-LifetimeHours <1..24>
```

`-LifetimeHours` belongs to the future bounded EKS lifecycle creation entry point. It is not profile configuration and must not be added to an EKS profile schema. The future provider implementation may pass the validated duration into its private OpenTofu input, but the policy is selected by the lifecycle operation, not inferred from a profile, workspace, region, or current configuration.

Omission selects 4 hours for a new lifecycle. An explicit override selects a whole number from 1 through 24. Once lifecycle identity exists, a changed or newly supplied value cannot reset the clock. Matching existing metadata is reused where later M24 semantics permit; a conflicting attempt fails closed rather than extending or adopting the lifecycle.

The 1–24 range matches the repository's existing bounded ephemeral-lab convention, but this is an explicit EKS policy decision. It is not inherited from AKS and does not create a cross-provider lifetime contract.

## Temporal semantics

At the accepted new-lifecycle creation boundary:

```text
CreatedAt = authoritative current UTC lifecycle-creation instant
ExpiresAt = CreatedAt + selected LifetimeHours
```

The future M24 implementation must generate `CreatedAt` once, calculate absolute `ExpiresAt` once, and persist both as immutable cloud metadata. Timestamps use an unambiguous UTC RFC 3339 representation. The selected duration is captured for that lifecycle, but future status consumes the persisted absolute timestamps rather than recalculating expiry.

Neither timestamp may be derived or recomputed later from current time, current/default configuration, a profile, plan time, state-file time, filesystem time, or a status request. Repeated plan, provision, connect, bootstrap, validate, and inspect operations must not advance `CreatedAt` or `ExpiresAt`. Changing the default or supplying another override against an existing lifecycle does not alter its expiration.

## ACTIVE, STALE, and advisory behavior

Subject to successful future ownership and status observation:

- Before `ExpiresAt`, the lab normalizes to `ACTIVE`.
- At or after `ExpiresAt`, the lab normalizes to `STALE`.
- `STALE` means the lab exceeded its intended ephemeral lifetime and should be reviewed or destroyed.

`STALE` does not mean unhealthy, inaccessible, invalid, or automatically deleted. Expiration triggers no deletion, shutdown, AWS mutation, or Kubernetes mutation. Explicit operator destruction remains required.

## Ownership

| Responsibility | Owner |
| --- | --- |
| Default 4-hour EKS duration, creation-only override, and 1–24-hour bounds | `BREAKFIX_POLICY` |
| Generate/persist immutable EKS lifecycle timestamps and ownership metadata | `EKS_PROVIDER` |
| Normalize valid temporal observations to `ACTIVE`, `STALE`, or `UNKNOWN` | `FOUNDATION` |
| Present normalized status through versioned operation results | `OPERATIONS` |

The policy does not belong to `cluster-foundation`. Foundation continues to accept only neutral `State`, `CreatedAt`, and `ExpiresAt`. Breakfix Operations contracts remain unchanged.

## AKS relationship

AKS currently has its own four-hour advisory default and 1–24-hour input bound. EKS now independently chooses the same values. Equality is useful operational consistency, not shared ownership or a provider-neutral contract. Any future policy unification requires a separate architectural decision. M24A changes no AKS behavior.

## M24 authorization boundary

With this policy established, M24 may resume and implement only its previously specified prerequisites: validate the default/creation override, create lifecycle identity once, persist immutable `CreatedAt` and absolute `ExpiresAt`, bind account/region/ownership metadata, prove immutability, and run its bounded acceptance.

M24A does not authorize EKS status, verify-clean, saved-plan parity, connection changes, lifecycle refactoring, automatic destruction, foundation changes, or Operations changes. All other original M24 stop conditions remain active.