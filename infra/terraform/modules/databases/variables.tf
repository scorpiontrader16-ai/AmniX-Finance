# Variables extracted from main.tf
variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}
variable "eks_node_cidr" {
  type        = string
  description = "CIDR of the EKS node subnet — only this subnet can reach PostgreSQL on port 5432."
  # Set this to your EKS node subnet CIDR, e.g. "10.0.2.0/24"
}

variable "subnet_ids" {
  type = list(string)
}

variable "environment" {
  type = string
}

variable "postgres_instance" {
  type    = string
  default = "db.r8g.large"
}

variable "multi_az" {
  type    = bool
  default = false
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_name}-db"
  subnet_ids = var.subnet_ids
  tags       = { Environment = var.environment }
}

