# Platform Infrastructure — High-Performance ARM64

> Kubernetes ARM64 + GitOps + Zero Trust + Go + Rust

---

## Quick Start

### 1. Configure GitHub Secrets

```
AWS_OIDC_ROLE_ARN              # IAM Role ARN (OIDC)
AWS_OIDC_ROLE_ARN_STAGING
AWS_OIDC_ROLE_ARN_PRODUCTION
TF_STATE_BUCKET                # S3 bucket for Terraform state
TF_LOCK_TABLE                  # DynamoDB table for state locking
GITOPS_TOKEN                   # GitHub token with repo write access
INFRACOST_API_KEY              # From infracost.io (free)
```

### 2. Configure GitHub Environments

In GitHub → Settings → Environments:
- `staging` — no approval required
- `production` — require 1+ reviewers

### 3. Replace Placeholder Values

Search for `your-org` and replace with your GitHub org name.

### 4. Push to GitHub

```bash
git init
git add .
git commit -m "feat: initial platform infrastructure"
git remote add origin https://github.com/YOUR-ORG/platform.git
git push -u origin main
```

---

## Architecture

```
External APIs / WebSockets
         │
  ┌──────▼──────┐
  │     Go      │  Ingestion Service
  │  Ingestion  │  gRPC :8080  HTTP :9090
  └──────┬──────┘
         │  gRPC / Protobuf
  ┌──────▼──────┐
  │    Rust     │  Processing Engine
  │ Processing  │  gRPC :50051  HTTP :9090
  └──────┬──────┘
         │
  ┌──────┴─────────────────┐
  │     Redpanda           │  Event streaming
  │     QuestDB            │  Time-series
  │     PostgreSQL         │  Relational + pgvector
  │     Dragonfly          │  Hot cache
  └────────────────────────┘
```

---

## Repository Structure

```
platform/
├── .github/workflows/       # CI/CD (7 workflows)
├── infra/
│   ├── argocd/apps/         # GitOps App of Apps
│   └── terraform/
│       ├── modules/         # cluster, networking, vault, redpanda, databases
│       └── environments/    # staging, production
├── k8s/
│   ├── base/                # Base K8s manifests
│   └── overlays/production/ # Kustomize production patches
├── proto/                   # Single source of truth for APIs
├── services/
│   ├── ingestion/           # Go service
│   └── processing/          # Rust service
└── scripts/
    ├── chaos/               # Chaos Mesh manifests
    └── load-tests/          # k6 load tests
```

---

## Adding a New Service

```bash
# 1. Define the API contract first
touch proto/my-service/v1/service.proto

# 2. Generate SDKs (CI does this automatically on push)
buf generate proto

# 3. Create the service
mkdir -p services/my-service

# 4. Add K8s manifests
mkdir -p k8s/base/my-service

# 5. Register with ArgoCD
# Add Application entry to infra/argocd/apps/applications.yaml
```

---

## Secrets Setup

All secrets are managed by HashiCorp Vault via External Secrets Operator.
No secrets are stored in Git. Ever.

```
Vault path: secret/platform/ingestion
Required keys: redpanda_api_key, data_source_api_key

Vault path: secret/platform/processing
Required keys: questdb_password, postgres_password
```
