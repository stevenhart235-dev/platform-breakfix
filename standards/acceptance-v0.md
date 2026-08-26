# Provider acceptance criteria v0

A provider implementation conforms to v0 only when every required criterion is
machine-detectable and passes against a newly provisioned environment. A
documentation claim or successful OpenTofu apply is not sufficient.

## Provision

- A managed Kubernetes control plane exists.
- The provider's declared compute capacity exists.
- The Kubernetes API progresses to a reachable state.

## Connect

- The operator receives an exact, deterministic kubeconfig context.
- Lifecycle tooling verifies the current context represents the intended lab.
- `kubectl` can successfully query the cluster.

## Bootstrap

- The shared Kubernetes baseline renders and applies successfully.
- Provider-specific Kubernetes configuration is composed separately.
- A provider-specific default block-storage class is available where the
  managed service does not already provide the selected policy.

External ingress is explicitly outside v0 acceptance.

## Validate

Validation returns exit code `0` only when all checks pass and nonzero when any
check fails. It must prove:

- the Kubernetes API is reachable;
- the expected number of nodes report `Ready`;
- all scheduled system pods are healthy;
- the nginx, podinfo, whoami, and curl baseline Deployments roll out;
- cluster DNS resolves Kubernetes Services;
- the diagnostics workload can make HTTP requests across namespaces;
- a dynamic block volume can be provisioned;
- a test pod can mount, write, and read that volume; and
- the test pod, claim, volume, and backing provider storage can be deleted.

Provider validation may add checks, but it may not weaken the common checks.

## Destroy

- Scenario resources are removed where applicable.
- Bootstrap resources that require a live Kubernetes API are removed before the
  control plane is destroyed.
- Provider infrastructure destruction completes using that provider's state.

## Verify-clean

- No unintended billable resource carrying the environment's ownership markers
  remains.
- Expected retained resources are reported separately and do not make cluster
  cleanup appear successful by omission.

## Allowed v0 exceptions

- The existing preserved ECR repositories are externally owned exceptions to
  the cluster lifecycle. Their current co-location in the EKS OpenTofu root is
  a known lifecycle mismatch and is not redesigned in v0.
- Local state is acceptable, but state is isolated by provider and must not be
  committed.
- Creation and expiration timestamps may be unavailable until lifecycle tooling
  begins recording them.
- Workload Identity is not required until a baseline or scenario workload needs
  Azure API access.
