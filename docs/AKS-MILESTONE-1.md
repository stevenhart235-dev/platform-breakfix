# AKS Milestone 1

AKS Milestone 1 is a tested, disposable Azure implementation of the v0
platform contract. It owns its Azure infrastructure independently under
`providers/azure/aks` and reuses the provider-independent Kubernetes baseline
from `kubernetes/shared`.

## Tested architecture

The tested configuration is:

- subscription: Ordicor Platform Lab (`0071dee8-974f-4f93-ad2a-0960557e1888`)
- region: `eastus2`
- AKS: Kubernetes `1.35.7`, Free tier, KubernetesOfficial support plan
- node pool: one fixed System node, `Standard_D2as_v7`, Ubuntu, 64 GiB managed
  OS disk, no availability zones or autoscaling
- networking: Azure CNI Overlay with the Azure data plane, Standard Load
  Balancer, and `loadBalancer` outbound
- addressing: VNet `10.20.0.0/16`, subnet `10.20.0.0/22`, pods
  `10.244.0.0/16`, services `10.2.0.0/16`, DNS `10.2.0.10`
- API: public with no authorized-IP restriction for this disposable baseline
- identity: user-assigned control-plane identity, AKS-managed kubelet identity,
  and subnet-scoped Network Contributor for the control-plane identity
- storage: AKS-managed Azure Disk CSI with the built-in `default` StorageClass
- state: local, AKS-specific OpenTofu state

The resource ownership boundary is `rg-platform-breakfix-aks`; AKS creates the
deterministically named node resource group `rg-platform-breakfix-aks-nodes`.
Resource tags identify the project, AKS provider, OpenTofu ownership, and
ephemeral lab purpose.

## Prerequisites

- OpenTofu `>= 1.11.5, < 1.12.0`
- Azure CLI authenticated to the expected enabled subscription
- `kubectl`
- permissions to create the six planned resources and the subnet-scoped role
  assignment
- registered ContainerService, Network, Compute, ManagedIdentity, and Storage
  resource providers
- Kubernetes `1.35.7`, `Standard_D2as_v7`, and at least two free regional and
  Dasv7-family vCPUs in `eastus2`

The `doctor` operation checks these deterministic cloud prerequisites before a
plan or apply.

## Lifecycle

Run lifecycle operations from Windows PowerShell at the repository root:

```powershell
.\scripts\Invoke-Lab.ps1 -Provider aks -Operation doctor
.\scripts\Invoke-Lab.ps1 -Provider aks -Operation plan
.\scripts\Invoke-Lab.ps1 -Provider aks -Operation provision
.\scripts\Invoke-Lab.ps1 -Provider aks -Operation connect
.\scripts\Invoke-Lab.ps1 -Provider aks -Operation bootstrap
.\scripts\Invoke-Lab.ps1 -Provider aks -Operation validate
.\scripts\Invoke-Lab.ps1 -Provider aks -Operation inspect
.\scripts\Invoke-Lab.ps1 -Provider aks -Operation destroy
.\scripts\Invoke-Lab.ps1 -Provider aks -Operation verify-clean
```

Use `-Operation full` to execute the complete guarded lifecycle. It always
attempts destroy and verify-clean after provisioning is attempted, including
when an intermediate operation fails. `scenario` intentionally reports that
Milestone 1 has no separate break/fix scenario.

The plan guard accepts only the Resource Group, VNet, subnet, managed identity,
subnet role assignment, and AKS cluster. It rejects deletes and unexpected
resource types before provision.

## Validation and Azure audit

Validation checks the deterministic kubeconfig context, API, one Ready node,
kube-system readiness, all four shared deployments, internal DNS, and
cross-namespace HTTP. The storage smoke test dynamically provisions an Azure
Disk, mounts it, writes and reads a probe, deletes its namespace and PV, and
uses Azure Resource Manager to prove the backing managed disk returns
`NotFound`.

Expected live inspection findings include:

- AKS provisioning state `Succeeded` and identity type `UserAssigned`
- Kubernetes `1.35.7` on one Ready Ubuntu node
- Azure CNI with overlay mode and the configured pod/service/DNS CIDRs
- Standard Load Balancer with one AKS-managed outbound public IP
- exactly one default StorageClass, `default`, using `disk.csi.azure.com`

`verify-clean` proves both dedicated resource groups are absent and queries for
remaining resources tagged `Project=platform-breakfix` and `Provider=aks`.
Milestone 1 intentionally creates no external persistent resources.

## Measured successful lifecycle

The successful live run on 2026-08-26 measured:

```text
doctor        00:00:14
plan          00:00:13
provision     00:05:23
connect       00:00:02
bootstrap     00:00:14
validate      00:02:06
destroy       00:07:32
verify-clean  00:00:03
Total         00:15:52
```

Azure control-plane creation and deletion vary between runs, so these are
observed timings rather than service-level targets.

## Known limitations and future work

- The public API and enabled local admin account suit an ephemeral learning lab,
  not a production security posture.
- The AzureRM AKS node-pool schema sets a 64 GiB managed OS disk but does not
  expose a separate OS-disk storage-account SKU control in this configuration.
- The built-in AKS StorageClasses are retained; no custom class is needed for
  the v0 contract.
- Monitoring, Log Analytics, Defender, Azure Policy, OIDC, Workload Identity,
  ingress, registry integration, and optional platform profiles are disabled or
  absent.
- Future Cilium, Istio, observability, and full profiles remain design work and
  may require creation-time cluster settings; Milestone 1 does not add feature
  flags for them.

The original v5 node proposals were not used because live quota was zero for
those VM families. `Standard_D2as_v7` is the tested and required baseline SKU.

Milestone 2 adds PAYG lifecycle guardrails without redesigning this baseline;
see [AKS-MILESTONE-2.md](AKS-MILESTONE-2.md).
