# ╔══════════════════════════════════════════════════════════════════╗
# ║  Full path: infra/terraform/environments/staging/main.tf         ║
# ║  Fix F-TF01: all hardcoded values replaced with var.*            ║
# ║  Fix F-TF01-C: multi_az hardcoded literal → var.multi_az         ║
# ║  Fix BUG-STAGING-PROVIDERS: helm + tls providers added           ║
# ║  Fix VAULT-REGION-BUG: aws_region passed to vault module         ║
# ║  Fix SG-BUG: vpc_cidr passed to redpanda module                  ║
# ║  Fix F-TF01-B: github_org/repo passed to cluster module          ║
# ╚══════════════════════════════════════════════════════════════════╝

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = "staging"
      Project     = "platform"
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source          = "../../modules/networking"
  name            = "platform-staging"
  cidr            = var.vpc_cidr
  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  cluster_name    = var.cluster_name
}

module "cluster" {
  source                  = "../../modules/cluster"
  cluster_name            = var.cluster_name
  environment             = "staging"
  vpc_id                  = module.vpc.vpc_id
  subnet_ids              = module.vpc.private_subnet_ids
  eks_public_access_cidrs = var.eks_public_access_cidrs
  github_org              = var.github_org
  github_repo             = var.github_repo
}

module "databases" {
  source        = "../../modules/databases"
  cluster_name  = var.cluster_name
  environment   = "staging"
  vpc_id        = module.vpc.vpc_id
  vpc_cidr      = var.vpc_cidr
  subnet_ids    = module.vpc.private_subnet_ids
  multi_az      = var.multi_az
  eks_node_cidr = var.eks_node_cidr
}

module "redpanda" {
  source             = "../../modules/redpanda"
  cluster_name       = var.cluster_name
  environment        = "staging"
  broker_count       = var.redpanda_broker_count
  instance_type      = var.redpanda_instance_type
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids
}

module "vault" {
  source            = "../../modules/vault"
  cluster_name      = var.cluster_name
  environment       = "staging"
  kms_key_id        = module.cluster.kms_key_id
  oidc_provider_arn = module.cluster.oidc_provider_arn
  oidc_provider_url = module.cluster.oidc_provider_url
  aws_region        = var.aws_region
}

output "eso_role_arn" {
  value = module.vault.eso_role_arn
}
