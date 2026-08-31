# AKS Milestone 14: Lightweight Lab Health Dashboard

Milestone 14 adds a presentation-only web dashboard over the accepted Milestone 13 Lab Health Contract v1. The accepted baseline is `108a876a5750494e3dc8fe433e231046271fbb8e` (`feat: add deterministic lab health contract`). This milestone does not run a cloud lifecycle and does not change Lab Health semantics.

## Architecture and boundaries

The dashboard is a small PowerShell HTTP process packaged with the canonical `scripts/LabHealth.ps1` collector and `kubectl`. In a cluster, `kubectl` uses the projected Kubernetes service-account credentials and API server discovery automatically. No kubeconfig, Azure CLI, AWS CLI, cloud credential, OpenTofu, Helm, scenario hook, or diagnosis engine is included.

The server calls `Get-AksLabHealth` and serializes the resulting bounded object with `ConvertTo-LabHealthJson`. Fixture mode calls `Read-LabHealthContract` against one of four fixed bundled documents. It cannot accept an arbitrary fixture path. The dashboard does not calculate health, infer a root cause, classify a scenario, or mutate Kubernetes.

Milestone 13 remains Contract version `1`, with exactly `Nodes`, `Pods`, `PVCs`, `Services`, `Endpoints`, `Cilium`, and `Istio`. DNS and storage are intentionally not invented as dashboard components: they remain active lifecycle validation. The Milestone 12 five-operation contract and CLI are unchanged. AKS is supported; EKS health support is not fabricated.

## HTTP behavior

- `GET /` returns an accessible status page with text and color indicators, direct component summaries, observation time, and add-on revision when supplied.
- `GET /api/health` returns a valid Lab Health Contract v1 with HTTP 200 for `HEALTHY`, `DEGRADED`, or `UNKNOWN`. If current collection is unavailable it returns HTTP 503 with bounded `HEALTH_UNAVAILABLE` JSON.
- `GET /healthz` reports only whether the web process is alive and returns HTTP 200 while it can serve requests. It does not claim cluster health.

The browser refreshes every five seconds. A failed refresh changes the current view to `UNKNOWN`, marks any retained observation as stale, and shows an unavailable warning. Stale data is never presented as current.

## Fixtures

The deterministic fixtures are `healthy`, `readiness-degraded`, `selector-degraded`, and `unknown`. Each passes the canonical Contract v1 validator. The two degraded fixtures deliberately remain distinct: readiness degradation affects Pods and Endpoints, while selector degradation leaves Pods healthy and affects Services and Endpoints. They demonstrate presentation, not scenario diagnosis.

Run locally without a cluster:

```powershell
pwsh -NoProfile -File dashboard/server.ps1 -Fixture healthy
```

Then browse `http://localhost:8080`. The same fixed fixture can be selected with `LAB_HEALTH_FIXTURE`. Omit fixture mode only when an already authorized Kubernetes context exists.

## Container and Kubernetes packaging

Build from the repository root:

```powershell
docker build -f dashboard/Dockerfile -t platform-breakfix-dashboard:0.1.0 .
docker run --rm -p 8080:8080 -e LAB_HEALTH_FIXTURE=healthy platform-breakfix-dashboard:0.1.0
```

The image runs as UID/GID 10001, pins `kubectl` v1.35.7 and verifies its published SHA-256 digest during build. The Kubernetes deployment additionally requires a non-root process, read-only root filesystem, no privilege escalation, all Linux capabilities dropped, RuntimeDefault seccomp, and bounded requests/limits.

`dashboard/kubernetes` creates a dedicated namespace, ServiceAccount, ClusterIP Service, Deployment, ClusterRole, and ClusterRoleBinding. The reader can only `get` and `list` Nodes, Pods, PVCs, Services, EndpointSlices, Deployments, and DaemonSets. It cannot read Secrets, execute in Pods, or mutate resources. Cluster scope is necessary because Nodes are cluster-scoped and health observations cover the lab cluster.

Render without applying:

```powershell
kubectl kustomize dashboard/kubernetes
```

The packaged Deployment defaults to the `minimal` AKS profile. Select `cilium` or `istio` through `LAB_HEALTH_PROFILE` only when the lab was provisioned with that saved profile identity. This milestone does not add the dashboard to any breakfix profile or lifecycle operation.

For M14 live acceptance, the image remains local and is imported temporarily into every schedulable AKS node's containerd image store through a short-lived, separate node-debug workload. The Deployment uses `platform-breakfix-dashboard:m14` with `imagePullPolicy: Never`; it has no registry or credential dependency. The privileged debug workload is acceptance scaffolding only, is removed before dashboard health assertions, and is not part of the dashboard manifests or runtime privileges. The imported image disappears when the ephemeral node is destroyed. Permanent artifact distribution remains an explicit future decision.

## Acceptance

Static acceptance requires all four fixtures to validate, local endpoint tests (including bounded failure behavior), direct UI rendering of every Contract v1 component, exact RBAC review, hardened workload rendering, PowerShell parsing, repository regression suites, Kustomize renders, and `git diff --check`. When Docker is locally available, the image must build and the same endpoint matrix must pass in the container. No Azure, AWS, or live Kubernetes lifecycle is required.
