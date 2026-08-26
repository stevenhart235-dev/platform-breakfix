# ADR 0003: State isolation strategy

- Status: Accepted
- Date: 2026-08-24

## Context

The current EKS root uses ignored local OpenTofu state. Introducing AKS creates
a risk that unrelated provider lifecycles become coupled.

## Decision

Local state remains acceptable for v0. Every provider uses an independent
OpenTofu root and independent state. State files stay uncommitted. No provider
may read or mutate another provider's state as part of its normal lifecycle.

Remote state, collaboration, recovery, and state bootstrap will be reconsidered
when a multi-operator or automated workflow requires them.

## Consequences

The operator remains responsible for protecting local state and backups. An
AKS root must not be added inside the current EKS state boundary.
