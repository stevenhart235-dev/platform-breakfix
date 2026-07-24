#!/usr/bin/env bash

set -Eeuo pipefail

CLUSTER_NAME="platform-breakfix"
AWS_REGION="us-east-2"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if (( $# > 1 )); then
  fail "Usage: $0 [AWS_PROFILE]"
fi

for command_name in aws kubectl; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    fail "'${command_name}' was not found in PATH. Install it in WSL and try again."
done

aws_args=()
profile_description="the default AWS credential chain"
if (( $# == 1 )) && [[ -n "${1}" ]]; then
  aws_args=(--profile "$1")
  profile_description="AWS profile '$1'"
fi

printf 'Verifying authentication with %s...\n' "${profile_description}"
if ! aws "${aws_args[@]}" sts get-caller-identity >/dev/null; then
  fail "AWS authentication failed using ${profile_description}. Refresh your credentials or select a valid profile, then try again."
fi

printf 'Updating kubeconfig for EKS cluster %s in %s...\n' "${CLUSTER_NAME}" "${AWS_REGION}"
if ! aws "${aws_args[@]}" eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}"; then
  fail "Could not update kubeconfig. Confirm the cluster exists in ${AWS_REGION} and your AWS identity can call eks:DescribeCluster."
fi

printf 'Verifying Kubernetes connectivity...\n'
if ! kubectl get nodes; then
  fail "kubectl could not reach the cluster. Check the EKS endpoint, network access, and access-entry permissions."
fi

printf 'Connected to %s successfully.\n' "${CLUSTER_NAME}"
