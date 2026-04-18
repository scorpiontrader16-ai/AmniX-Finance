# Variables extracted from main.tf
variable "cluster_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "kms_key_id" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "namespace" {
  type    = string
  default = "platform"
}

# H-05: ec2-based vault IAM role removed — all policies migrated to vault_irsa (OIDC)
# This eliminates the ec2 principal which allowed any EC2 instance to assume the role

resource "aws_iam_role_policy" "vault_kms" {
  name = "vault-kms-unseal"
  # H-05: migrated from ec2 vault role to OIDC vault_irsa role
