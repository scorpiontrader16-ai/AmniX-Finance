# ╔══════════════════════════════════════════════════════════════════╗
# ║  Full path: infra/terraform/modules/vault/variables.tf           ║
# ║  Fix F-TF01: removed leaked resource block                       ║
# ║  Fix VAULT-REGION-BUG: added aws_region — removes hardcoded      ║
# ║    "us-east-1" from helm storage config (critical bug for EU)    ║
# ║  Fix F-TF01-B: vault_version + vault_ha_replicas extracted       ║
# ╚══════════════════════════════════════════════════════════════════╝

variable "cluster_name" {
  type        = string
  description = "EKS cluster name — used as prefix for IAM roles and S3 bucket"
}

variable "environment" {
  type        = string
  description = "Deployment environment (staging | production)"
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN for Vault auto-unseal and S3 encryption"
}

variable "oidc_provider_arn" {
  type        = string
  description = "EKS OIDC provider ARN for IRSA trust policy"
}

variable "oidc_provider_url" {
  type        = string
  description = "EKS OIDC provider URL (without https://) for condition keys"
}

variable "namespace" {
  type        = string
  default     = "platform"
  description = "Kubernetes namespace for platform workloads"
}

# VAULT-REGION-BUG FIX: was hardcoded "us-east-1" in helm storage config.
# Vault S3 storage backend requires the correct region or it cannot write state.
# In eu-west-1 environment, the S3 bucket is in eu-west-1 — hardcoding us-east-1
# causes Vault to fail silently on startup. Must match the provider region.
variable "aws_region" {
  type        = string
  description = "AWS region where Vault S3 storage bucket resides. Must match the provider region. Critical: mismatch causes Vault startup failure."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. us-east-1, eu-west-1)."
  }
}

# F-TF01-B: extracted hardcoded Vault helm chart version
variable "vault_version" {
  type        = string
  default     = "0.27.0"
  description = "Helm chart version for HashiCorp Vault. Pin explicitly. See: https://github.com/hashicorp/vault-helm/releases"
}

# F-TF01-B: extracted hardcoded HA replicas count
variable "vault_ha_replicas" {
  type        = number
  default     = 3
  description = "Number of Vault HA replicas. Minimum 3 for production Raft consensus."

  validation {
    condition     = var.vault_ha_replicas >= 3 || var.vault_ha_replicas == 1
    error_message = "vault_ha_replicas must be 1 (dev/staging non-HA) or >= 3 (production HA Raft)."
  }
}
