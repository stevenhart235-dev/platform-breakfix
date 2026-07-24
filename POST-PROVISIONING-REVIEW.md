# Post-provisioning review

The review covered the tracked OpenTofu configuration, lifecycle scripts, and
deployment directories. No additional automation was implemented.

| Manual step currently required | Automate? | Why | Recommended approach | Complexity |
| --- | --- | --- | --- | --- |
| Configure kubeconfig and verify cluster access in each operator environment | Yes | A recreated EKS endpoint must be written to each environment's separate kubeconfig before Kubernetes or UDS commands can run. | Use `Connect-Cluster.ps1` on Windows and `connect-cluster.sh` in WSL immediately after `tofu apply`. | Low |
| Create and mark an EBS CSI-backed StorageClass as the default, if the UDS bundle expects dynamic default storage | Yes, after confirming the bundle's storage requirements | The EBS CSI add-on and IAM permissions are provisioned, but the repository defines no Kubernetes StorageClass. Workloads using a PVC without `storageClassName` may remain pending on a fresh cluster. | Manage a `gp3` StorageClass declaratively as part of cluster bootstrap (for example, with the Kubernetes provider or a versioned bootstrap manifest applied by an explicit script), and verify it after recreation. | Low |
| Supply the UDS bundle and run `uds deploy uds-bundle-*.tar.zst --confirm` from WSL | No for the operator-triggered deployment; automate bundle production/distribution separately if needed | Deployment is the intentional lab operation, but no bundle definition or archive is tracked in this repository, so the archive must currently be obtained or built out of band. | Document the authoritative bundle source and version. If repeatable builds are desired, add a versioned UDS bundle definition and CI-produced artifact in a separately approved change. | Medium |
| Prepare namespaces or other Kubernetes bootstrap resources | Not currently demonstrated | The repository contains no manifests or documentation requiring pre-created namespaces. UDS commonly owns resources in its bundle, so adding speculative bootstrap steps would create two sources of truth. | Declare any required namespaces and prerequisites in the UDS bundle. Add cluster-level bootstrap only when a concrete dependency cannot be owned by UDS. | Low once requirements are known |

## Findings that do not require a manual step

- The EKS managed node group, public API endpoint, cluster-creator admin access,
  core EKS add-ons, EBS CSI driver, and its pod-identity IAM policy are already
  created by OpenTofu.
- OpenTofu waits for its managed EKS resources and add-ons during `tofu apply`;
  no separate cluster bootstrap command is present in the repository.

## Repository gap

`scripts/Connect-Cluster.ps1` now provides the same authentication,
kubeconfig-update, connectivity, dependency-checking, and actionable-error
flow as `connect-cluster.sh`.

The EBS StorageClass follow-up is analyzed in
[EBS-STORAGECLASS-DESIGN.md](EBS-STORAGECLASS-DESIGN.md). No StorageClass
automation has been implemented.
