# ╔══════════════════════════════════════════════════════════════════╗
# ║  Full path: infra/terraform/environments/staging/variables.tf    ║
# ║  Fix F-TF01: all hardcoded values from main.tf declared here     ║
# ║  Fix F-TF18: all variables for this environment declared here    ║
# ║  Fix F-TF01-B: added github_org + github_repo for cluster module ║
# ╚══════════════════════════════════════════════════════════════════╝

variable "aws_region" {
  description = "AWS region for staging environment"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "List of availability zones for the region"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "cluster_name" {
  description = "EKS cluster name for staging"
  type        = string
  default     = "platform-staging"
}

variable "vpc_cidr" {
  description = "VPC CIDR block for staging"
  type        = string
  default     = "10.1.0.0/16"
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks for staging (one per AZ)"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks for staging (one per AZ)"
  type        = list(string)
  default     = ["10.1.101.0/24", "10.1.102.0/24"]
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to access EKS API server."
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "eks_node_cidr" {
  description = "CIDR permitted to reach PostgreSQL on port 5432."
  type        = string
  default     = "10.1.0.0/16"
}

variable "redpanda_broker_count" {
  description = "Number of Redpanda broker EC2 instances. 1 for staging."
  type        = number
  default     = 1
}

variable "redpanda_instance_type" {
  description = "EC2 instance type for Redpanda brokers."
  type        = string
  default     = "im4gn.xlarge"
}

variable "github_org" {
  description = "GitHub organization name for OIDC trust policy in cluster module."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for OIDC trust policy in cluster module."
  type        = string
}
