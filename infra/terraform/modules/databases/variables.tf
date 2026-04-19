# ╔══════════════════════════════════════════════════════════════════╗
# ║  Full path: infra/terraform/modules/databases/variables.tf       ║
# ║  Fix F-TF01: removed leaked resource block                       ║
# ║  Fix F-TF01-B: extracted all hardcoded values to variables       ║
# ║  Fix F-TF05: postgres_instance default → db.t4g.medium           ║
# ║  Fix F-TF06: multi_az default → true (production-safe)           ║
# ║  Fix F-TF03-egress: added vpc_cidr for restricted egress rule    ║
# ╚══════════════════════════════════════════════════════════════════╝

variable "cluster_name" {
  type        = string
  description = "EKS cluster name — used as prefix for RDS identifier and subnet group"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID from networking module"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block — restricts RDS security group egress to within the VPC only."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }

  validation {
    condition     = !contains(["0.0.0.0/0", "::/0"], var.vpc_cidr)
    error_message = "vpc_cidr must NOT be 0.0.0.0/0 or ::/0."
  }
}

variable "eks_node_cidr" {
  type        = string
  description = "CIDR of the EKS node subnet — only this subnet can reach PostgreSQL on port 5432."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the RDS subnet group"
}

variable "environment" {
  type        = string
  description = "Deployment environment (staging | production)"
}

# F-TF05: default changed from db.r8g.large → db.t4g.medium
variable "postgres_instance" {
  type        = string
  default     = "db.t4g.medium"
  description = "RDS instance class. Default: db.t4g.medium (dev/staging). Production must explicitly set db.r8g.large or higher."

  validation {
    condition     = can(regex("^db\\.(t[0-9]|r[0-9]|m[0-9])", var.postgres_instance))
    error_message = "postgres_instance must be a valid RDS instance class (e.g. db.t4g.medium, db.r8g.large)."
  }
}

# F-TF06: default changed from false → true
variable "multi_az" {
  type        = bool
  default     = true
  description = "Enable Multi-AZ for RDS. Default: true (production-safe). Non-production must explicitly set to false."
}

# F-TF01-B: extracted hardcoded engine version
variable "engine_version" {
  type        = string
  default     = "16.2"
  description = "PostgreSQL engine version. Verify compatibility with EKS version before upgrading."
}

# F-TF01-B: extracted hardcoded storage values
variable "allocated_storage" {
  type        = number
  default     = 100
  description = "Initial allocated storage in GB for the RDS instance."

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be at least 20 GB."
  }
}

variable "max_allocated_storage" {
  type        = number
  default     = 1000
  description = "Maximum storage autoscaling limit in GB. Must be greater than allocated_storage."

  validation {
    condition     = var.max_allocated_storage > var.allocated_storage
    error_message = "max_allocated_storage must be greater than allocated_storage."
  }
}

# F-TF01-B: extracted hardcoded maintenance windows
variable "backup_window" {
  type        = string
  default     = "03:00-04:00"
  description = "Daily backup window (UTC). Format: hh24:mi-hh24:mi. Must not overlap maintenance_window."
}

variable "maintenance_window" {
  type        = string
  default     = "Mon:04:00-Mon:05:00"
  description = "Weekly maintenance window (UTC). Format: ddd:hh24:mi-ddd:hh24:mi."
}

variable "monitoring_interval" {
  type        = number
  default     = 60
  description = "Enhanced monitoring interval in seconds. 0 = disabled. Valid: 0,1,5,10,15,30,60."

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}
