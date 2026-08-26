# ADR 0001: Platform lifecycle and acceptance contract

- Status: Accepted
- Date: 2026-08-24

## Context

The EKS lab has working infrastructure and Kubernetes layers but its lifecycle
is distributed across manual commands. AKS needs behavioral parity rather than
a resource-for-resource translation.

## Decision

Adopt the lifecycle and v0 criteria in `standards/lab-contract.md` and
`standards/acceptance-v0.md`. Operations define outcomes before a shared CLI is
introduced. External ingress is excluded from v0; internal DNS, HTTP, and
dynamic block storage are required.

The current approximately ten-minute EKS create/destroy time is a benchmark,
not an SLA. Lifecycle phase timings will eventually be measured independently.

## Consequences

Provider implementations can differ internally but must pass the same common
validation. An infrastructure apply alone no longer establishes conformance.
