# AKS Milestone 5: Managed Istio Profile

The provider-scoped `istio` profile selects the AKS-managed Istio service
mesh add-on. It is an AKS-specific tested configuration, not a portable Istio
installation. It remains independent from the `cilium` profile and uses the
normal Azure CNI Overlay data plane:

- network plugin: `azure`
- network plugin mode: `overlay`
- network data plane: `azure`
- managed service mesh mode: `Istio`
- Istio revision: `asm-1-30`

The profile does not install Istio with Helm or `istioctl`. It enables no
ingress or egress gateway, exposes no workload publicly, and adds no monitoring,
registry, Application Gateway, or other unrelated service.

## Live discovery

Live discovery in `eastus2` on 2026-08-29 found AKS Kubernetes `1.35.7`
still offered. Azure reported revisions `asm-1-28`, `asm-1-29`, and
`asm-1-30` compatible with Kubernetes 1.35. The response did not identify a
default. The profile explicitly selects the latest offered compatible revision,
`asm-1-30`.

For a new AKS 1.35 installation, `asm-1-30` uses native sidecars and
`CNIChaining`. Live Azure output confirmed `CNIChaining`. The validator
therefore expects a running native `istio-proxy` init container, the
`istio-validation` init container, no legacy `istio-init`, and a healthy
managed Istio CNI DaemonSet.

Azure CLI 2.89.0 supports the required mesh commands. Pinned AzureRM 4.81.0
supports creation-time `service_mesh_profile` configuration with explicit
revisions and disabled internal/external gateways.

## Bootstrap and validation

The profile adds one disposable namespace labeled exactly
`istio.io/rev=asm-1-30`, one curl source Deployment, one nginx destination
Deployment, and one ClusterIP Service. It does not use the generic
`istio-injection=enabled` label.

Validation remains ordered common, AKS provider, then profile. The profile
validator discovers rather than hard-codes the managed `istiod` Deployment
name. It checks Azure mesh mode/revision and redirection mechanism, managed
control-plane readiness, CNI DaemonSet health, exact namespace revision,
native-sidecar pod composition, EndpointSlice readiness, and bounded direct
ClusterIP HTTP behavior.

The intended deterministic policy sequence is:

1. meshed request returns `HTTP 200`
2. a destination-scoped Istio DENY AuthorizationPolicy returns `HTTP 403`
3. removing the policy restores `HTTP 200`

Disposable policy and test resources are removed in `finally`.

## Node sizing and PAYG

The initial single live run used one `Standard_D2as_v7` node. Azure's managed
`istiod` Deployment requires a minimum of two replicas. Only one of two became
available within the bounded 180-second rollout, so the run established that
D2as_v7 is not a safe deterministic size for this profile.

The profile was corrected to one `Standard_D4as_v7` node. A post-cleanup
read-only doctor confirmed the SKU is available without restrictions in
`eastus2` and both regional and Dasv7 quotas have at least four free vCPUs.
This correction has static and plan coverage but has not been applied in a
second PAYG run.

The PAYG estimate for the corrected profile is approximately USD 0.20 per hour,
or USD 0.80 for the four-hour advisory TTL. It models node compute only and
does not invent an Istio surcharge. Existing managed disk, Standard Load
Balancer/public IP, egress, tax, and billing-authoritative disclaimers remain.

## Single live acceptance attempt

The authorized run proved:

- AKS 1.35.7 provisioned successfully with `Profile=istio`.
- Azure CNI Overlay remained enabled with the Azure network data plane.
- Azure reported managed Istio mode and revision `asm-1-30`.
- Azure reported proxy redirection mechanism `CNIChaining`.
- common DNS and cross-namespace HTTP validation passed.
- AKS provider validation passed.
- Azure Disk provisioning, read/write, Kubernetes cleanup, and backing-disk
  deletion passed.
- the four-hour TTL and Istio PAYG banner were correct.
- destroy used profile `istio`, removed all seven state objects, and
  verify-clean returned `NO LAB`.

The run stopped before namespace/proxy and deny/allow proof because the second
managed `istiod` replica did not become available on the D2 node. Inspect and
duplicate-provision validation were consequently not reached. No second Azure
lifecycle was performed.

Observed timings:

| Phase | Duration |
| --- | ---: |
| doctor | 00:00:16 |
| plan | 00:00:13 |
| provision | 00:05:42 |
| connect | 00:00:02 |
| bootstrap | 00:00:15 |
| validate | 00:05:22 |
| destroy | 00:06:36 |
| verify-clean | 00:00:04 |
| **Total** | **00:18:34** |

## Limitations and cleanup

The profile is not accepted until one D4-backed lifecycle proves two healthy
managed control-plane replicas, native sidecar injection, meshed HTTP,
deterministic Istio denial/restoration, inspect consistency, duplicate
provision blocking, and final cleanup.

Switching profiles still requires explicit destroy followed by verify-clean.
The accepted PAYG ownership, saved-plan/profile binding, live-profile mismatch,
TTL, duplicate-provision, and cleanup contracts are unchanged. A combined
Cilium/Istio profile is deliberately not implemented.
