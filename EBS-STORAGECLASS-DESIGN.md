# Default gp3 StorageClass design

## Decision summary

The current cluster has the EBS CSI driver and its AWS permissions, but it has
no declarative `StorageClass`. Those are separate concerns: the driver can
provision volumes only after a Kubernetes `StorageClass` tells it how to do so.

The recommended design is a small, versioned Kubernetes manifest owned by the
UDS bundle and applied as an early, ordered prerequisite of the bundle. It
should define one default `gp3` class using `ebs.csi.aws.com`,
`WaitForFirstConsumer`, volume expansion, encryption, and an explicitly chosen
reclaim policy. This keeps Kubernetes workload policy with the Kubernetes/UDS
deployment layer, avoids OpenTofu's new-cluster provider bootstrap problem, and
preserves the desired three-command workflow.

This document is design-only. No StorageClass or related automation has been
implemented.

## 1. Why gp3 is absent

`infrastructure/eks/main.tf` asks the EKS module to install the
`aws-ebs-csi-driver` managed add-on and associates the driver's service account
with an IAM role. That installs the CSI controller/node components and gives
them permission to manage EBS volumes. It does not declare a Kubernetes
`StorageClass`.

A `StorageClass` is a separate cluster policy object containing the
provisioner, parameters, reclaim policy, and binding behavior. The EBS CSI
driver supports dynamic provisioning through such an object, but the operator
must supply it. AWS likewise documents the add-on installation and application
storage configuration as separate steps:

- [AWS: Use Kubernetes volume storage with Amazon EBS](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
- [EBS CSI driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [Kubernetes StorageClasses](https://kubernetes.io/docs/concepts/storage/storage-classes/)

The older in-tree `gp2` default class must not be treated as the desired CSI
configuration. This cluster uses the CSI provisioner, for which the class
should use `ebs.csi.aws.com`.

## 2. Is this expected for the current EKS module?

Yes. The repository uses `terraform-aws-modules/eks/aws` `~> 21.0`. Its
`addons` input creates EKS managed add-on resources; it does not expose or
create Kubernetes `StorageClass` resources. The locally initialized v21 module
contains add-on resources but no StorageClass resource. This matches the
module's documented scope:

- [terraform-aws-eks module](https://github.com/terraform-aws-modules/terraform-aws-eks)
- [AWS: Amazon EKS add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)

Therefore, successfully installing `aws-ebs-csi-driver` without receiving a
default `gp3` class is expected behavior, not a failed add-on installation.

## 3. Implementation options

| Option | How it works | Advantages | Limitations |
| --- | --- | --- | --- |
| OpenTofu Kubernetes provider | Add `hashicorp/kubernetes` and a `kubernetes_storage_class_v1` resource. | Declarative state, drift detection, explicit dependency, and normal plan output. The provider has a purpose-built [StorageClass resource](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/storage_class_v1). | On a brand-new cluster, the Kubernetes provider needs an endpoint and credentials produced by the same apply. OpenTofu states that provider configuration values must be known before apply, making a clean single-root first apply unreliable. Destroy ordering and expired EKS tokens also need care. |
| Versioned Kubernetes manifest in UDS | Package a plain `StorageClass` manifest and apply it before packages that create PVCs. | Native, portable, reviewable, and aligned with the existing UDS deployment boundary. No extra operator command or OpenTofu provider is required. | The class appears during `uds deploy`, not during `tofu apply`. Bundle ordering becomes important, and the UDS bundle must remain the sole owner. |
| Standalone manifest applied by a script | Store YAML in the repository and apply it with `kubectl apply`. | Simple and easy to troubleshoot. | A manually run script violates the target workflow. Calling it from an OpenTofu `local-exec` provisioner hides Kubernetes drift from state and adds local AWS CLI/kubectl dependencies to infrastructure provisioning. |
| Helm release/chart | Render the StorageClass from a minimal chart or an existing bootstrap chart. | Useful if the platform already has a Helm-owned bootstrap layer and values conventions. | Excess machinery for one stable API object. A Helm provider in the same fresh-cluster root has the same provider bootstrap and destroy-order concerns as the Kubernetes provider. |
| EBS CSI add-on configuration | Try to create the class through managed add-on values. | Would keep the change near the driver if the managed schema supported it. | The EKS module only passes the add-on's supported configuration schema, and a StorageClass is not part of the current module contract. Depending on an undocumented chart value would be fragile. |

## 4. Recommended approach

Add a versioned `storage.k8s.io/v1` manifest to the UDS bundle and order it
before every package that may create a PVC. The proposed object should have:

- a stable name such as `gp3`;
- `storageclass.kubernetes.io/is-default-class: "true"`;
- `provisioner: ebs.csi.aws.com`;
- `parameters.type: gp3` and `parameters.encrypted: "true"`;
- `volumeBindingMode: WaitForFirstConsumer`;
- `allowVolumeExpansion: true`;
- an explicitly selected `reclaimPolicy` (`Delete` for a disposable lab is the
  likely choice, subject to confirmation).

Kubernetes recommends `WaitForFirstConsumer` for topology-constrained storage
so volume provisioning accounts for the consuming Pod's scheduling topology.
Kubernetes also warns that multiple default classes are ambiguous, so the
design should include a validation that exactly one default exists.

## 5. Why this approach

The StorageClass is Kubernetes workload policy rather than an AWS
infrastructure resource. UDS already supplies the authenticated Kubernetes
deployment phase in the required workflow and can enforce ordering. Keeping
the manifest there avoids an unsupported dependency from an OpenTofu provider
configuration to a cluster being created in that same apply.

It is also more transparent than `local-exec`: the desired object is plain
YAML, is reviewable with the rest of the platform bundle, and can be updated or
removed through the same deployment system.

## 6. Operational tradeoffs

- Storage is unavailable in the short interval between `tofu apply` and
  `uds deploy`. That is acceptable if UDS is the first Kubernetes workload
  deployment and the class package is ordered first.
- Any workload installed outside UDS before the bundle would need an explicit
  class or would wait for the default class to appear.
- Changing a default class affects PVCs that omit `storageClassName`; consumers
  that require a different policy should name their class explicitly.
- `WaitForFirstConsumer` improves availability-zone placement but means a PVC
  can remain pending until a consuming Pod is schedulable.
- `Delete` makes lab teardown simple but deletes backing volumes when their PVs
  are released. `Retain` protects data but leaves cleanup work and cost.
- EBS provides `ReadWriteOnce`/single-zone block storage semantics; workloads
  requiring multi-node `ReadWriteMany` need a different storage backend.
- Ownership must be exclusive. The same StorageClass should not be managed
  simultaneously by UDS, Helm, and OpenTofu.

## 7. Can tofu apply alone create it reproducibly?

Yes, but with an important distinction:

- A two-stage OpenTofu design can reliably create the EKS cluster first and
  then run a Kubernetes-provider bootstrap root against the now-known cluster.
- A single root and single first `tofu apply` is not the recommended design
  because the Kubernetes provider's endpoint is produced during that apply.
  [OpenTofu provider configuration](https://opentofu.org/docs/language/providers/configuration/)
  requires provider inputs to be known before apply.
- A single apply can be forced with `local-exec` plus `kubectl`, but that loses
  Kubernetes state/drift management and adds workstation dependencies. It is
  not recommended.

For the stated end-to-end goal, no manual cluster configuration is necessary:
the StorageClass can be reproducibly created as part of the already-required
`uds deploy`. The resulting workflow remains exactly:

1. `tofu apply`
2. `Connect-Cluster.ps1` or `connect-cluster.sh`
3. `uds deploy uds-bundle-*.tar.zst --confirm`

If a future requirement says the StorageClass must exist at the end of step 1,
use two OpenTofu roots behind a checked-in orchestration command, or accept and
document the `local-exec` tradeoff. That would be a separate implementation
decision.
