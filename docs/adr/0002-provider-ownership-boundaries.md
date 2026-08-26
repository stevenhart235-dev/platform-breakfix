# ADR 0002: Provider ownership boundaries

- Status: Accepted
- Date: 2026-08-24

## Context

AWS infrastructure, portable Kubernetes workloads, and an AWS EBS
StorageClass currently sit close together. A generic cloud abstraction would
hide meaningful EKS and AKS differences.

## Decision

Keep independently understandable provider infrastructure roots. Do not build
a generic cross-cloud Terraform Kubernetes module. Shared Kubernetes resources
live under `kubernetes/`; provider additions and canonical provider composition
live under `providers/<cloud>/<service>/kubernetes/`.

Keep the existing EKS OpenTofu root in place during the incremental transition.
Container registries are outside the core cluster lifecycle. Existing preserved
ECR resources remain unchanged but are documented as a lifecycle mismatch.

## Consequences

Some small composition files are duplicated intentionally. Cloud networking,
identity, registry, storage, and cleanup semantics remain provider-owned and
reviewable.
