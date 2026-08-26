# Platform Break/Fix Lab

`platform-breakfix` is a disposable, hands-on platform engineering lab for
learning by building, intentionally breaking, troubleshooting, and recovering
Kubernetes environments. It favors small, readable examples over
production-platform complexity.

## What is implemented

The repository currently contains:

- a tested, disposable Azure AKS Milestone 1 provider using Azure CNI Overlay,
  one `Standard_D2as_v7` node, and AKS-managed Azure Disk CSI;
- an Amazon EKS cluster defined with OpenTofu-compatible Terraform
  configuration;
- optional, generic Amazon ECR repositories for external image producers;
- a VPC with two public subnets and a two-node EKS managed node group;
- Kubernetes 1.36 with CoreDNS, kube-proxy, VPC CNI, EKS Pod Identity, and the
  EBS CSI managed add-on;
- EBS CSI permissions through Pod Identity and a default, encrypted `gp3`
  StorageClass using `WaitForFirstConsumer`;
- Kustomize-managed namespaces and lightweight nginx, podinfo, whoami, and curl
  diagnostic workloads;
- Services, health probes, resource requests and limits, service accounts, an
  nginx ConfigMap, and an nginx Ingress;
- PowerShell and Bash scripts that authenticate to AWS, refresh kubeconfig for
  `platform-breakfix` in `us-east-2`, and verify cluster connectivity.

Helm is reserved for third-party software or application packaging, but no
chart or Helm release definition is currently checked in. UDS and Zarf are
operator tools used in the lab workflow; the repository does not currently
contain a UDS bundle definition, bundle archive, Zarf package, or registry
inspection automation.

## UDS and Zarf lab work

The operator-led UDS/Zarf exercises completed around this repository include:

- deploying an externally supplied UDS bundle to EKS;
- inspecting the private registry managed by Zarf;
- tracing how imported images are stored and how workload image references are
  rewritten to use that registry;
- inspecting the resulting Kubernetes Deployments, ReplicaSets, Pods,
  Services, Secrets, and PersistentVolumeClaims;
- retrieving registry credentials from the cluster and viewing the registry
  catalog.

These steps were performed interactively and are not yet represented by
checked-in scripts or UDS/Zarf configuration. Secret names, namespaces,
registry endpoints, and exact authentication commands depend on the external
bundle and therefore are intentionally not documented as fixed repository
commands.

Useful generic inspection commands are:

```bash
kubectl get deployments,replicasets,pods,services,secrets,pvc -A
kubectl describe deployment <deployment> -n <namespace>
kubectl get deployment <deployment> -n <namespace> \
  -o jsonpath='{.spec.template.spec.containers[*].image}'
```

## Prerequisites

Windows PowerShell is the infrastructure operator environment. Ubuntu WSL is
the Kubernetes and UDS operator environment.

- AWS account credentials with permission to create and delete the lab
  resources
- OpenTofu `>= 1.11.5, < 1.12.0`
- AWS CLI in each operator environment
- `kubectl` in Windows and/or WSL
- UDS CLI and the external `uds-bundle-*.tar.zst` archive for UDS deployment
- Helm and Zarf CLIs only for the related interactive exercises

AWS profiles and kubeconfig files are separate between Windows and WSL.

## Repository layout

```text
.
├── infrastructure/eks/        # OpenTofu AWS infrastructure, including optional ECR
├── kubernetes/
│   ├── namespaces/            # platform and diagnostics namespaces
│   ├── apps/                  # nginx, podinfo, whoami, and curl
│   ├── ingress/               # nginx Ingress
│   ├── shared/                # provider-independent namespace/workload baseline
│   ├── scheduling/            # empty extension point
│   ├── policies/              # empty extension point
│   └── failures/              # empty extension point
├── charts/                    # policy placeholder; no Helm chart yet
├── providers/aws/eks/         # canonical EKS Kubernetes additions/composition
├── providers/azure/aks/       # AKS infrastructure, composition, and lifecycle
├── standards/                 # lifecycle and v0 acceptance contract
├── validation/                # common and provider validation logic
├── scripts/                   # cluster connection scripts
└── docs/                      # Kubernetes lab instructions
```

Each Kubernetes object is kept in its own YAML file and related resources are
composed with Kustomize.

See [docs/ECR.md](docs/ECR.md) for the optional repository schema, defaults,
outputs, lifecycle policy, teardown behavior, and external workload boundary.
See [docs/AKS-MILESTONE-1.md](docs/AKS-MILESTONE-1.md) for the tested AKS
architecture, lifecycle, validation, timings, cleanup audit, and limitations.

## Provision and connect

From Windows PowerShell:

```powershell
cd infrastructure\eks
tofu init
tofu apply
cd ..\..
.\scripts\Connect-Cluster.ps1
```

Use a named AWS profile when required:

```powershell
.\scripts\Connect-Cluster.ps1 -Profile <profile>
```

From the repository root in Ubuntu WSL, connect using the default AWS
credential chain or an optional profile:

```bash
bash scripts/connect-cluster.sh
bash scripts/connect-cluster.sh <profile>
```

Both scripts verify `aws` and `kubectl`, call
`aws sts get-caller-identity`, update the EKS kubeconfig, and run
`kubectl get nodes`.

After bootstrapping, run the machine-detectable v0 checks from PowerShell:

```powershell
.\scripts\Validate-Lab.ps1 -Provider eks
```

Override `-ClusterName`, `-CloudLocation`, `-ExpectedNodeCount`, or
`-ExpectedContext` when the infrastructure inputs differ from their defaults.
The validator refuses to run against an unexpected kubeconfig context.

## Deploy and inspect the Kubernetes baseline

Render before applying:

```bash
kubectl kustomize kubernetes
```

Apply all implemented Kubernetes resources:

```bash
kubectl apply -k kubernetes
kubectl get all -n platform
kubectl get all -n diagnostics
kubectl get storageclass
```

`kubernetes` remains a compatibility entry point for EKS. New lifecycle tooling
uses `providers/aws/eks/kubernetes`; the portable workload-only baseline is
`kubernetes/shared`.

Test service discovery from the curl workload:

```bash
kubectl exec -n diagnostics deploy/curl -- curl -sS http://nginx.platform
kubectl exec -n diagnostics deploy/curl -- curl -sS http://podinfo.platform:9898
kubectl exec -n diagnostics deploy/curl -- curl -sS http://whoami.platform
```

The Ingress uses `lab.local` and requires an existing controller that provides
the `nginx` IngressClass. No ingress controller is installed by this
repository.

## Deploy an external UDS bundle

After connecting from WSL and obtaining the bundle out of band:

```bash
uds deploy uds-bundle-*.tar.zst --confirm
```

The repository does not build, download, or version this archive.

## Break/fix lessons represented

### Missing default gp3 StorageClass

Installing the EBS CSI add-on provides the storage driver, not a default
StorageClass. Without a suitable class, PVCs that rely on dynamic provisioning
can remain pending. The lab now includes
`providers/aws/eks/kubernetes/storage/gp3-storageclass.yaml`, which declares
encrypted `gp3` volumes, expansion support, and `WaitForFirstConsumer`.

See [EBS-STORAGECLASS-DESIGN.md](EBS-STORAGECLASS-DESIGN.md) for the design
tradeoffs.

### Helm release stuck in pending-install

An interactive lab deployment encountered a Helm release stuck in
`pending-install`. Recovery consisted of identifying the failed release,
removing it, confirming that the release state was gone, and reinstalling it.
The exact release and installation command are not stored in this repository.
A generic investigation pattern is:

```bash
helm list -A --pending
helm status <release> -n <namespace>
helm uninstall <release> -n <namespace>
helm list -n <namespace>
# Repeat the original installation command.
```

There are not yet any checked-in, intentionally broken manifests under
`kubernetes/failures/`.

## Teardown

Delete the Kustomize baseline while the cluster is reachable:

```bash
kubectl delete -k kubernetes
```

Then destroy the AWS infrastructure from Windows PowerShell:

```powershell
cd infrastructure\eks
tofu destroy
```

Do not use `scripts/Remove-Lab.ps1`; it is currently an empty placeholder.
External UDS/Zarf resources may require cleanup using the matching external
bundle workflow before cluster destruction.

## Safety and cost

This configuration creates billable AWS resources, including an EKS control
plane, two on-demand `m7i-flex.large` nodes, EBS volumes, and potentially
load balancers created by later exercises. Run `tofu destroy` when the lab is
not in use and verify the destroy plan before approving it.

The EKS API has public access enabled, the nodes run in public subnets, control
plane logging and envelope encryption are disabled, and the cluster creator
receives administrator access. These choices support a disposable learning
lab; they are not production recommendations. Never store real credentials or
sensitive data in the example manifests.

## Current limitations

- The UDS bundle and all Zarf registry details are external to this repository.
- No Helm charts or third-party controllers are installed from checked-in code.
- The nginx Ingress is inactive until an nginx ingress controller exists.
- The example applications do not currently create Secrets or PVCs.
- `scripts/Remove-Lab.ps1` is empty.
- The `scheduling`, `policies`, and `failures` Kustomizations are empty.
- Terraform state is local; no remote backend is configured.
- ECR image building, pushing, and workload deployment require separately
  authorized external tooling.

## Planned lab ideas

The following are planned learning areas, not implemented capabilities:

- deliberate Deployment, Service selector, probe, DNS, and image failures;
- taints, tolerations, affinity, and other scheduling exercises;
- PVC lifecycle and additional storage failures;
- Helm application packaging and third-party add-ons;
- CRDs, Istio, Cilium, Argo Rollouts, and GitOps-style workflows;
- checked-in UDS bundle metadata and repeatable Zarf registry inspection.

Additional Kubernetes commands and extension guidance are in
[docs/KUBERNETES-LAB.md](docs/KUBERNETES-LAB.md). The earlier repository review
is in [POST-PROVISIONING-REVIEW.md](POST-PROVISIONING-REVIEW.md).
