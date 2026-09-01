# AKS Milestone 15: First-Class Lab Health Operation and CLI

Milestone 15 promotes the accepted passive Lab Health capability to the external operator surface. The accepted baseline is `dbf241c7afe63661ee91874c4995fb0e8070b11a` (`feat: add lightweight AKS health dashboard`). No live cloud or Kubernetes lifecycle is required.

## Problem and architecture

Milestone 13 established deterministic Lab Health Contract v1 and Milestone 14 consumed it directly inside Kubernetes. Operators still lacked a first-class command outside the cluster. M15 adds an explicitly versioned operation and CLI adapter:

```text
CLI -> Breakfix Operations Contract v2 -> LabHealth.ps1 -> AKS collector
```

`LabHealth.ps1` remains the sole owner of observation validation, component classification, overall aggregation, and the exact seven-component contract. The operation layer checks lifecycle eligibility, supplies the authoritative active-lab profile, delegates collection, validates the returned contract, and wraps it. The CLI only maps syntax and renders returned fields. The in-cluster dashboard continues to call `LabHealth.ps1` directly.

## Operations Contract v2

Contract v1 remains the default and contains exactly `list_profiles`, `list_scenarios`, `read_evidence`, `diagnose_evidence`, and `get_lab_status`. Contract v2 contains those five operations plus `get_lab_health`. Existing callers that omit contract selection remain on v1; therefore v1 does not silently acquire a sixth operation. Existing operations produce an envelope matching the selected version.

The envelope remains `ContractVersion`, `Operation`, `Success`, `Data`, and `Error`. A successful `get_lab_health` has Operations Contract version `2` and contains an unchanged Lab Health Contract version `1` document in `Data`. Failures have null `Data` and a bounded error without raw provider output, paths, credentials, or stack traces.

## Health semantics

`get_lab_status` answers whether the ephemeral lab exists and reports `NO_LAB`, `ACTIVE`, `STALE`, or `UNKNOWN`. `get_lab_health` answers what is passively unhealthy in an observable active cluster and reports Lab Health overall `HEALTHY`, `DEGRADED`, or `UNKNOWN`. These state spaces are deliberately separate.

The operation requires only `Provider`. For AKS it calls the existing status primitive first and accepts only `ACTIVE` with an authoritative profile. It passes that profile to `Get-AksLabHealth` and uses the already-configured Kubernetes context. It does not obtain credentials or infer profile identity from Kubernetes.

`NO_LAB`, `STALE`, unknown lifecycle state, or a missing authoritative profile fail with the single narrow `LAB_NOT_ACTIVE` code. The operation never fabricates a healthy or empty contract. Collector failure or malformed output is translated to bounded `LAB_STATE_UNAVAILABLE`. EKS returns `PROVIDER_UNSUPPORTED`; passive EKS parity is not fabricated.

## CLI

Human rendering:

```powershell
.\breakfix.ps1 lab health -Provider aks
```

```text
Lab Health: HEALTHY

Nodes       HEALTHY
Pods        HEALTHY
PVCs        NOT_APPLICABLE
Services    HEALTHY
Endpoints   HEALTHY
Cilium      NOT_APPLICABLE
Istio       NOT_APPLICABLE
```

The CLI reads these values directly from the returned contract. JSON mode emits the complete v2 operation envelope:

```powershell
.\breakfix.ps1 lab health -Provider aks -Json
```

Exit code `0` means success, `1` means bounded operation failure, and `2` means invalid CLI syntax. Existing M12 commands retain their mappings, v1 envelopes, and exit behavior.

## Read-only boundary

AKS health performs passive list/get observations for Nodes, Pods, PVCs, Services, EndpointSlices, Deployments, and DaemonSets. It never runs `kubectl exec`, active DNS/HTTP/storage validation, scenarios, repairs, Kubernetes writes, cloud mutations, credential retrieval, kubeconfig mutation, or registry operations. Passive health remains exactly Nodes, Pods, PVCs, Services, Endpoints, Cilium, and Istio; DNS and Storage are not passive components.

## Test evidence

Deterministic tests prove exact v1/v2 allowlists, selected envelope versions, all existing-operation compatibility, four accepted health fixtures, authoritative profile propagation, fail-closed lifecycle states, unsupported EKS, malformed and sensitive provider failure sanitization, human healthy/degraded rendering, JSON v2 plus nested Health v1, exit codes, and mutation-command absence. The full repository suite also covers OpenTofu 1.11.13, AKS/EKS validation, PowerShell parsing, M12 through M14 regressions, scenarios/evidence/diagnosis, seven Kustomize renders, architecture invariants, and diff hygiene.

## Deferred

M15 does not add EKS passive health parity, HTTP API, MCP, mutation operations, active-validation history, Prometheus/Grafana, foundation extraction, or registry/artifact architecture. Those require separate milestones and explicit contract decisions.
