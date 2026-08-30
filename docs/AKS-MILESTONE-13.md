# AKS Milestone 13: deterministic passive Lab Health Contract

## Objective and accepted baseline

Milestone 13 starts from accepted M12 commit `1f79500ab411963d339ce475a0f67abb82d260f9` and introduces a strict, deterministic Lab Health Contract v1. It reports what can be determined about current cluster state through passive Kubernetes reads. It does not report whether every cluster capability has been functionally validated.

The repository boundary remains:

```text
platform-breakfix -> cluster-foundation <- future-platform
```

M12 Breakfix Operations Contract v1 and its five-operation allowlist remain unchanged. `get_lab_health` is deliberately not public yet.

## Scope correction and architectural boundary

The first M13 review correctly stopped on DNS and Storage. That finding produced an explicit architecture decision:

- **Passive health** asks, “What can be determined about current cluster state using read-only observations?” Lab Health Contract v1 owns this question.
- **Active validation** asks, “What capabilities have been functionally proven through bounded validation?” Existing breakfix validation owns this question.

DNS is excluded. The accepted deterministic proof resolves a Service name from a workload. CoreDNS Deployment, Pod, Service, or EndpointSlice readiness is not equivalent to successful DNS resolution. The health collector must not use `pods/exec`, create a diagnostic Pod, or publish a weaker DNS proxy as healthy.

Storage is excluded. The accepted deterministic proof creates a transient PVC and Pod, waits for binding and mounting, writes and reads data, cleans up, and verifies backing-disk deletion. CSI and StorageClass readiness is not equivalent to functional storage health. The passive collector creates no PVC and publishes no Storage component.

These exclusions are part of the contract boundary, not temporary missing implementation. A future dashboard may show separate sections:

- **LIVE HEALTH**, sourced from Lab Health Contract v1;
- **LAST VALIDATED**, sourced from a future persisted representation of active validation.

M13 implements neither the dashboard nor validation-result persistence.

## Lab Health Contract v1

Contract version `1` is independent of Breakfix Operations v1, Evidence Contract v1, and scenario manifest schema v1. The exact top-level fields are:

- `ContractVersion`
- `Overall`
- `ObservedAt`
- `Provider`
- `Profile`
- `Components`

Unknown or missing fields, malformed JSON, unsupported provider/profile values, invalid UTC timestamps, invalid states, inconsistent aggregation, and invalid fact types fail closed.

Overall states are exactly `HEALTHY`, `DEGRADED`, and `UNKNOWN`. Component states are exactly `HEALTHY`, `DEGRADED`, `UNKNOWN`, and `NOT_APPLICABLE`.

Aggregation precedence is deterministic:

1. Any `DEGRADED` component makes Overall `DEGRADED`.
2. Otherwise, any `UNKNOWN` component makes Overall `UNKNOWN`.
3. Otherwise, Overall is `HEALTHY`.

`NOT_APPLICABLE` does not degrade Overall. Overall `HEALTHY` means only: all applicable components represented by Lab Health Contract v1 are observationally healthy. It does not mean every cluster capability has passed active functional validation.

## Observation and classification separation

The implementation keeps three stages separate:

```text
read-only AKS Kubernetes observations
              |
              v
strict structured health observations
              |
              v
deterministic profile-aware classifier
              |
              v
Lab Health Contract v1
```

`Get-AksLabHealthObservations` is the provider collector. `New-LabHealthContract` and its component classifiers consume synthetic observations without Kubernetes access. Collection failures become structured unavailable observations and therefore `UNKNOWN`; malformed classifier input is rejected.

Classification receives Provider, Profile, and component observations. It has no Scenario field, scenario-name rule, expected-failure state, diagnosis identifier, or milestone identity. Profile is used only to determine whether Cilium or Istio is expected.

## Seven passive-health components

### Nodes

Nodes use current Node objects and the Ready condition. At least one node must exist and all current nodes must report Ready=True for `HEALTHY`. A successfully observed zero-node cluster or any non-Ready node is `DEGRADED`. Retrieval or structural failure is `UNKNOWN`. Deleted Nodes are absent from the current list.

### Pods

Pods use a fresh all-namespace snapshot. Successfully completed Pods and Pods already marked for deletion are excluded. Every remaining current Pod must be Running, have container status, and have all current containers Ready. Pending, Failed, Unknown, Running-but-not-Ready, and missing readiness status degrade health. Collection failure is `UNKNOWN`.

This makes readiness-probe failure observable as Pod degradation without naming that scenario or diagnosing its cause.

### PVCs

PVC health describes only current PersistentVolumeClaim state. If current claims exist, all must be Bound for `HEALTHY`; any unbound claim is `DEGRADED`; failed collection is `UNKNOWN`. With no current claim and no separate profile expectation, PVCs are `NOT_APPLICABLE`.

PVC `HEALTHY` must never be interpreted as functional Storage `HEALTHY`. It does not prove dynamic provisioning, volume mounting, read/write behavior, cleanup, or backing-volume deletion. The component summary repeats this boundary.

### Services

Services evaluate the repository's bounded expected workload Services for the selected profile and currently present scenario namespace. A Service must exist and its selector must match at least one current Pod label set. Pod readiness does not affect selector alignment, so a readiness failure leaves Services healthy while a selector mismatch degrades Services. Missing Service or selector mismatch is `DEGRADED`; unavailable Service or Pod observations are `UNKNOWN`.

### Endpoints

Endpoints evaluate Ready EndpointSlice backends independently from selector alignment. Every expected Service must have at least one endpoint whose `conditions.ready` is exactly true. Null/missing endpoints and ready=false do not count. A null slice item or invalid list makes observation unavailable and therefore `UNKNOWN`. A valid zero-ready result is `DEGRADED`.

These rules preserve the hardened EndpointSlice behavior already accepted by scenario regressions.

### Cilium

Cilium is applicable only to the `cilium` profile. Passive health combines the expected current node count, the managed `cilium` DaemonSet readiness, and healthy current `k8s-app=cilium` agents. Missing or unhealthy expected agents are `DEGRADED`; collection failure is `UNKNOWN`; other profiles are `NOT_APPLICABLE`.

This reports managed component readiness only. It does not claim complete networking or policy-path functional correctness. Version is optional and its absence alone does not degrade health.

### Istio

Istio is applicable only to the `istio` profile. Passive health requires expected managed istiod control-plane instances and managed Istio CNI agents to be Ready. Missing or unhealthy expected components are `DEGRADED`; collection failure is `UNKNOWN`; other profiles are `NOT_APPLICABLE`. The selected profile revision, currently `asm-1-30`, is reported when available.

This reports managed component readiness only. It does not claim end-to-end mesh traffic, policy, or routing correctness.

## Scenario-independent fixture outcomes

Synthetic observations produce these results without passing scenario identity to classification:

| Fixture | Overall | Pods | Services | Endpoints |
|---|---|---|---|---|
| Healthy baseline | `HEALTHY` | `HEALTHY` | `HEALTHY` | `HEALTHY` |
| Readiness failure facts | `DEGRADED` | `DEGRADED` | `HEALTHY` | `DEGRADED` |
| Selector mismatch facts | `DEGRADED` | `HEALTHY` | `DEGRADED` | `DEGRADED` |

Identical observations wrapped with different or absent external scenario metadata serialize to identical health documents when `ObservedAt` is fixed. Adding Scenario to classifier observations is rejected as an unknown field.

## Provider boundary and security

AKS collection requires an already configured, authorized Kubernetes context. It performs only list/get operations for Nodes, Pods, PVCs, Services, EndpointSlices, DaemonSets, and Deployments. It does not obtain AKS credentials or change kubeconfig. EKS passive Lab Health collection is explicitly unsupported in v1; no parity is manufactured.

A future in-cluster collector needs list/get/watch only where watch is operationally useful for:

- core `nodes`, `pods`, `persistentvolumeclaims`, and `services`;
- discovery.k8s.io `endpointslices`;
- apps `deployments` and `daemonsets`.

It does not need Secrets, ConfigMaps, `pods/exec`, Pod or PVC creation, patch, update, delete, rollout, impersonation, credential mutation, or cluster-admin.

## Relationship to other contracts

Scenario Evidence answers which bounded facts were captured for a specific investigation. Lab Health answers which represented components are unhealthy now. Evidence Contract remains v1 and does not depend on health.

Deterministic diagnosis explains why a known observation pattern occurred. Health reports what component is degraded. Lab Health contains no diagnosis identifier and does not call `Resolve-ScenarioDiagnosis`.

Breakfix Operations Contract v1 remains exactly five operations: `list_profiles`, `list_scenarios`, `read_evidence`, `diagnose_evidence`, and `get_lab_status`. A future operation such as `get_lab_health` requires an explicit versioning decision after the primitive is accepted; M13 does not add it or change the CLI.

## Explicit non-goals

M13 adds no web UI, HTML, CSS, JavaScript, container, Deployment, Service, Ingress, Prometheus, Grafana, Loki, OpenTelemetry, Azure Monitor, CloudWatch, metrics-server change, history store, active validation persistence, Kubernetes mutation, cloud lifecycle logic, or application-platform capability.

## Static validation and acceptance

Deterministic tests cover strict contract validation, state allowlists, aggregation precedence, Nodes, current Pods, PVC state, selector alignment, hardened EndpointSlice semantics, Cilium/Istio applicability, scenario independence, the three fixture patterns, read-only collector commands, DNS/Storage exclusion, EKS unsupported behavior, and the unchanged M12 allowlist.

The complete repository regression suite, OpenTofu 1.11.13 validation, all PowerShell parses, six Kustomize renders, architecture comparisons, and whitespace checks are required before acceptance.

No live acceptance is necessary for deterministic classification. A later targeted live read-only comparison could characterize real AKS object shapes, but it must be separately authorized and is not needed to accept the v1 contract.

The recommended next action is review and acceptance of the standalone primitive. Only afterward should a separately versioned read adapter or dashboard consumption design be considered.
