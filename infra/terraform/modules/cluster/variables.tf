# Variables extracted from main.tf
variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  type    = string
  default = "1.29"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "environment" {
  type = string
}

# أضف متغير للـ CIDRs المسموح بها للوصول لـ EKS API
# غيّر القيمة دي لـ IP الخاص بـ VPN أو bastion host عندك
variable "eks_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to access EKS API server. Must be restricted to VPN/bastion IPs only. No default — must be set explicitly per environment."
  # No default — forces each environment to declare its VPN CIDR explicitly
  # Example: ["10.0.1.0/24"] for a specific VPN subnet
}

# ── EKS Cluster ──────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
