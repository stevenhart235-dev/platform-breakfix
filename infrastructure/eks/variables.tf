variable "aws_region" {
  description = "AWS region in which to query and eventually create lab infrastructure."
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "Name to use for the future EKS cluster and related resources."
  type        = string
  default     = "platform-breakfix"
}

variable "kubernetes_version" {
  description = "Kubernetes minor version for the EKS control plane and managed addons."
  type        = string
  default     = "1.36"
}
