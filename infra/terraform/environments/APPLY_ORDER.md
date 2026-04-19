# Terraform Apply Order — Two-Phase Required

## Why Two Phases?

The `helm` provider in each environment references `module.cluster.cluster_endpoint`.
This endpoint does not exist until the EKS cluster is created.
Running `terraform apply` directly on a fresh environment will fail with:
`Error: Get "https://<endpoint>/api": dial tcp: no route to host`

## Phase 1 — Create the EKS Cluster First

```bash
terraform apply -target=module.vpc -target=module.cluster
```

Wait for Phase 1 to complete (EKS cluster will be in ACTIVE state).

## Phase 2 — Apply Everything Else

```bash
terraform apply
```

This applies: databases, redpanda, vault (helm releases), S3 resources.

## CI/CD

In automated pipelines, split into two steps with a readiness check between them:
```bash
# Step 1
terraform apply -target=module.vpc -target=module.cluster -auto-approve
aws eks wait cluster-active --name <cluster_name> --region <region>

# Step 2
terraform apply -auto-approve
```
