# AKS Milestone 4: Managed Cilium Profile

The provider-scoped cilium profile selects AKS-managed Azure CNI Powered by
Cilium. It keeps Azure CNI Overlay, the accepted network ranges, one
Standard_D2as_v7 System node, the user-assigned identity, AKS Free tier,
Standard Load Balancer outbound, public API, and Azure Disk CSI behavior.

Cilium is a creation-time AKS network data-plane selection. The repository does
not install Cilium through Helm and does not manage a separate Cilium release.
This profile is an AKS-specific tested configuration, not a portable Cilium
installation abstraction. A future EKS profile may require different provider
and bootstrap details.

## Bootstrap and validation

The profile composition adds one disposable namespace containing a curl source,
an nginx destination Service, and a default-deny ingress NetworkPolicy. Common
validation and AKS provider validation remain mandatory before the profile
validator.

The profile validator checks that Azure reports the Cilium data plane, the
managed cilium DaemonSet has one healthy agent for every expected node, and the
destination has a ready EndpointSlice. It then performs two bounded HTTP
probes:

1. default-deny must block source-to-destination traffic
2. an explicit allow policy must restore that traffic

The validation namespace is deleted in a finally block. Baseline DNS, HTTP, and
Azure Disk tests remain owned by common and AKS validation and cannot be
suppressed by the profile.

## PAYG and switching

The profile inherits the four-hour advisory TTL, stable ownership timestamps,
cost warning, duplicate-provision block, profile-aware plan/live-lab checks,
mandatory cleanup, and verify-clean behavior. Switching profiles requires
destroy followed by verify-clean before planning another profile.

## First live acceptance attempt

The single Milestone 4 PAYG run on 2026-08-29 established:

- Azure reported networkDataPlane=cilium and networkPolicy=cilium.
- One healthy managed Cilium agent represented the one Ready node.
- Common DNS and cross-namespace HTTP validation passed.
- Azure Disk provisioning, read/write, and backing-disk deletion passed.
- Profile=cilium, stable timestamps, and the existing infrastructure footprint
  were present.

The run failed before the deny/allow probes because warning text from a
Kubernetes watch was merged into an endpoint JSON capture. Cleanup still
deleted the validation namespace and all Azure lab resources. The validator now
uses the nondeprecated EndpointSlice API with a scalar JSONPath readiness check,
avoiding warning-sensitive JSON parsing. This correction has static coverage
but has not received a second PAYG lifecycle run.

Observed timings:

| Phase | Duration |
| --- | ---: |
| doctor | 00:00:15 |
| plan | 00:00:14 |
| provision | 00:04:37 |
| connect | 00:00:02 |
| bootstrap | 00:00:13 |
| validate | 00:04:37 |
| destroy | 00:42:35 |
| verify-clean | 00:00:04 |
| **Total** | **00:52:40** |

Azure AKS deletion took 40 minutes 35 seconds. Verify-clean subsequently
reported both Resource Groups absent, no tagged AKS resources, and NO LAB.
