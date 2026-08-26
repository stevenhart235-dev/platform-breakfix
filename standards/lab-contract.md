# Platform break/fix lab contract v0

This contract defines the lifecycle semantics that every provider implementation
must satisfy. It describes outcomes, not a required CLI or a shared Terraform
abstraction. Provider implementations may use different cloud resources as long
as they meet the same acceptance criteria.

The canonical lifecycle is:

```text
doctor -> plan -> provision -> connect -> bootstrap -> validate
       -> scenario -> inspect -> destroy -> verify-clean
```

The current approximately ten-minute EKS provision and destroy behavior is a
benchmark target, not an SLA. Provision, bootstrap, validation, and destruction
durations should eventually be measured independently.

## Operations

| Operation | Purpose | Expected inputs | Expected outputs | Success criteria | Ownership | Failure means |
| --- | --- | --- | --- | --- | --- | --- |
| `doctor` | Prove the operator can safely start. | Provider, provider configuration, credentials, required toolchain. | Human-readable preflight results and a deterministic exit status. | Tools meet declared versions; credentials, account/subscription, location, configuration, and required quotas are usable. | Common checks plus a provider adapter. | Provisioning should not start because the workstation or cloud prerequisites are incomplete. |
| `plan` | Preview owned infrastructure and consequential choices. | Provider infrastructure root and environment inputs. | Reviewable OpenTofu plan, including creates, changes, destroys, and preservation exceptions. | Configuration validates and the plan represents the intended provider environment. | Provider-adapted. | The desired environment is invalid, ambiguous, or unsafe to apply. |
| `provision` | Create provider infrastructure and a managed Kubernetes cluster. | Approved plan, credentials, provider inputs, and independent provider state. | Cloud resources, cluster identity, and normalized lifecycle values. | The managed control plane exists, expected compute exists, and the API can become reachable. | Provider-adapted. | Infrastructure is incomplete or the cluster cannot progress to connection/bootstrap. |
| `connect` | Give the operator deterministic cluster access. | Provider, cluster name, location, credentials, and kubeconfig destination. | A deterministic kubeconfig context selected or reported to the operator. | `kubectl` can query the intended cluster and cannot silently target another lab. | Common semantics with provider authentication. | Identity, endpoint access, authorization, or context selection is wrong. |
| `bootstrap` | Install the lab's Kubernetes starting state. | Connected context, shared baseline, and provider-specific Kubernetes additions. | Applied shared resources and provider additions. | The shared baseline applies; required provider storage configuration applies separately; rollouts can begin. | Shared baseline plus provider composition. | The cluster exists but is not ready for validation or scenarios. |
| `validate` | Prove machine-detectable conformance to v0. | Connected context, expected capacity, shared validation, and provider adapter. | Clear `PASS`/`FAIL` results and deterministic exit code. | Every criterion in `acceptance-v0.md` passes, including disposable storage. | Common Kubernetes validation followed by provider validation. | The environment must not be treated as a conforming lab until the failed capability is fixed. |
| `scenario` | Apply, run, reset, or remove an intentional break/fix exercise. | Validated lab, scenario identifier, and scenario inputs. | Known scenario state with documented symptoms and recovery goal. | The requested scenario transition completes without changing unrelated ownership boundaries. | Usually provider-independent; provider-specific scenarios are allowed. | The lab state is no longer known or the scenario cannot be run/reset predictably. |
| `inspect` | Collect evidence for learning and troubleshooting. | Connected context and optional scenario/provider scope. | Readable cluster, workload, event, network, storage, and provider diagnostics. | Evidence identifies the target environment and is sufficient to begin diagnosis. | Common inspection plus optional provider diagnostics. | Evidence is incomplete, stale, or from the wrong environment. |
| `destroy` | Remove scenario, bootstrap, and ephemeral provider resources in safe order. | Provider state, credentials, connected context when required, and preservation declarations. | Removed scenario/bootstrap resources and destroyed provider infrastructure. | Kubernetes cleanup that requires a live API runs first; the provider destroy completes. | Common ordering with provider destruction. | Owned resources may remain billable or cleanup may need recovery. |
| `verify-clean` | Detect unintended leftovers after destruction. | Provider ownership markers, state, account/subscription, location, and allowed exceptions. | Inventory of leftovers and deterministic exit status. | No unintended billable resource owned by the ephemeral lab remains. | Provider-adapted with common exception semantics. | Destruction is incomplete even if OpenTofu reported success. |

## Normalized lifecycle values

Each provider must make these values available to lifecycle tooling. They may
initially be OpenTofu outputs or small provider-adapter values; a shared schema
is not required for v0.

| Value | Meaning |
| --- | --- |
| `provider` | Stable provider identifier such as `eks` or `aks`. |
| `cluster_name` | Cloud-managed cluster name. |
| `cloud_location` | AWS region, Azure location, or provider equivalent. |
| `kubeconfig_context` | Exact context lifecycle tooling expects and validates. |
| `infrastructure_root` | Repository-relative OpenTofu root owned by the provider. |
| `kubernetes_provider_composition` | Repository-relative Kustomize entry point that combines the shared baseline and provider additions. |
| `created_at` | Creation timestamp when the provider can supply one. |
| `expires_at` | Intended expiration timestamp when configured. |

The values must identify one environment unambiguously. Connection and
destruction tooling must not depend on defaults that can diverge from the
provider inputs.

## Lifecycle boundaries

- Each provider has independent infrastructure code and local state.
- Container registries are external to the core ephemeral cluster lifecycle.
- Intentionally preserved registries are allowed exceptions only when they are
  declared as externally owned; they are not evidence of successful cluster
  cleanup.
- External ingress is not required for v0.
- Provider-specific cloud behavior remains visible instead of being hidden by
  a generic cross-cloud Terraform module.
