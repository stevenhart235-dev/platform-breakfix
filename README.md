# Platform Break/Fix Lab

This repository provisions the disposable `platform-breakfix` EKS lab with
OpenTofu on Windows. UDS deployments run from Ubuntu WSL.

## Prerequisites

Windows PowerShell requires OpenTofu and the AWS CLI. Ubuntu WSL requires the
AWS CLI, `kubectl`, and the UDS CLI. AWS credentials or profiles used in
Windows and WSL are configured separately.

## Normal workflow

1. Provision or recreate the cluster from Windows PowerShell:

   ```powershell
   cd infrastructure\eks
   tofu init
   tofu apply
   ```

2. Connect to the cluster from the operator environment you will use. On
   Windows PowerShell:

   ```powershell
   ..\..\scripts\Connect-Cluster.ps1
   ```

   Or, from the repository root in Ubuntu WSL:

   ```bash
   bash scripts/connect-cluster.sh [AWS_PROFILE]
   ```

   Omit `AWS_PROFILE` to use the default AWS credential chain.

3. Deploy the bundle from Ubuntu WSL:

   ```bash
   uds deploy uds-bundle-*.tar.zst --confirm
   ```

In short, the repeatable operator flow is:

1. `tofu apply`
2. `Connect-Cluster.ps1` (Windows) or `connect-cluster.sh` (WSL)
3. `uds deploy uds-bundle-*.tar.zst --confirm`

Both connection scripts are expected to authenticate to AWS, update
kubeconfig for `platform-breakfix` in `us-east-2`, and confirm access with
`kubectl get nodes`.

## Post-provisioning review

See [POST-PROVISIONING-REVIEW.md](POST-PROVISIONING-REVIEW.md) for the manual
steps that remain after `tofu apply` and the recommended follow-up automation.
The default EBS StorageClass options and recommendation are detailed in
[EBS-STORAGECLASS-DESIGN.md](EBS-STORAGECLASS-DESIGN.md).
