# ADR 0004: Portable Kubernetes baseline

- Status: Accepted
- Date: 2026-08-24

## Context

Namespaces and learning workloads are portable, while the default `gp3`
StorageClass uses the AWS EBS CSI provisioner. Mixing them makes the apparent
baseline cloud-specific.

## Decision

The shared baseline is composed by `kubernetes/shared/kustomization.yaml` and
contains the namespaces and existing nginx, podinfo, whoami, and curl
resources. Provider Kustomizations compose that baseline with provider-owned
storage and any other provider additions.

The root `kubernetes/kustomization.yaml` remains an EKS-compatible transition
entry point so the established bootstrap command continues to work.

Do not introduce Helm or redesign the workloads.

## Consequences

The shared baseline can render without AWS APIs or CSI names. AKS can later add
its own composition without copying or conditionally templating the workloads.
