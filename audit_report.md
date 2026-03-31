# Institutional Efficiency Audit Report

> Generated: 2026-03-31 21:51:14
> Repo: /workspaces/youtuop-1

---

## 1. Security

### [CRITICAL] Possible hardcoded credentials

**Where:** ./k8s/base/vault/vault-auth-config.yaml,

**Fix:** Move to environment variables or a secrets manager (Vault, AWS SSM, K8s Secrets). Rotate any real credentials immediately.

---

### [MEDIUM] govulncheck not available in PATH

**Where:** Go services

**Fix:** Install: go install golang.org/x/vuln/cmd/govulncheck@latest  Then run: govulncheck ./... in each service.

---

## 2. Code Quality

### [HIGH] Go errors silently discarded (_, _ := pattern)

**Where:** 24 occurrences across Go files

**Fix:** Replace with proper error handling. Use 'golangci-lint run --enable errcheck' to find all instances.

---

### [MEDIUM] Go functions with DB/client params possibly missing context.Context

**Where:** ~228 candidates — verify manually

**Fix:** First param should be ctx context.Context for all I/O-bound functions to support cancellation and tracing.

---

### [HIGH] go.sum missing

**Where:** ./tests/integration

**Fix:** Run: cd ./tests/integration && go mod tidy

---

### [MEDIUM] Bare except: clauses in Python (catches BaseException)

**Where:** 1 occurrences

**Fix:** Replace with 'except SpecificException as e:' to avoid silently catching SystemExit, KeyboardInterrupt.

---

## 3. Infrastructure

### [HIGH] K8s workloads missing resource limits (cpu/memory)

**Where:** ./k8s/base/data-quality/scaledobject.yaml

**Fix:** Add resources.limits.cpu and resources.limits.memory to every container spec. Prevents noisy-neighbour resource exhaustion.

---

### [HIGH] K8s Deployments missing liveness/readiness probes

**Where:** ./k8s/base/data-quality/scaledobject.yaml

**Fix:** Add livenessProbe (restart on deadlock) and readinessProbe (remove from LB until healthy) to each container.

---

### [MEDIUM] Hardcoded AWS region or account ID in Terraform

**Where:** ./infra/terraform/environments/eu-west-1

**Fix:** Move to variables.tf or tfvars. Use data.aws_caller_identity.current.account_id for account IDs.

---

### [MEDIUM] Hardcoded AWS region or account ID in Terraform

**Where:** ./infra/terraform/environments/production

**Fix:** Move to variables.tf or tfvars. Use data.aws_caller_identity.current.account_id for account IDs.

---

### [HIGH] Terraform directory missing backend.tf (local state risk)

**Where:** ./infra/terraform/modules/cluster

**Fix:** Add backend.tf with S3/GCS/Terraform Cloud backend. Local state gets lost and can't be shared.

---

### [MEDIUM] Terraform variables defined in main.tf (not variables.tf)

**Where:** ./infra/terraform/modules/cluster/main.tf

**Fix:** Move all variable blocks to variables.tf. Keep main.tf for resources only.

---

### [HIGH] Terraform directory missing backend.tf (local state risk)

**Where:** ./infra/terraform/modules/databases

**Fix:** Add backend.tf with S3/GCS/Terraform Cloud backend. Local state gets lost and can't be shared.

---

### [MEDIUM] Terraform variables defined in main.tf (not variables.tf)

**Where:** ./infra/terraform/modules/databases/main.tf

**Fix:** Move all variable blocks to variables.tf. Keep main.tf for resources only.

---

### [HIGH] Terraform directory missing backend.tf (local state risk)

**Where:** ./infra/terraform/modules/networking

**Fix:** Add backend.tf with S3/GCS/Terraform Cloud backend. Local state gets lost and can't be shared.

---

### [MEDIUM] Terraform variables defined in main.tf (not variables.tf)

**Where:** ./infra/terraform/modules/networking/main.tf

**Fix:** Move all variable blocks to variables.tf. Keep main.tf for resources only.

---

### [HIGH] Terraform directory missing backend.tf (local state risk)

**Where:** ./infra/terraform/modules/redpanda

**Fix:** Add backend.tf with S3/GCS/Terraform Cloud backend. Local state gets lost and can't be shared.

---

### [MEDIUM] Terraform variables defined in main.tf (not variables.tf)

**Where:** ./infra/terraform/modules/redpanda/main.tf

**Fix:** Move all variable blocks to variables.tf. Keep main.tf for resources only.

---

### [HIGH] Terraform directory missing backend.tf (local state risk)

**Where:** ./infra/terraform/modules/vault

**Fix:** Add backend.tf with S3/GCS/Terraform Cloud backend. Local state gets lost and can't be shared.

---

### [MEDIUM] Terraform variables defined in main.tf (not variables.tf)

**Where:** ./infra/terraform/modules/vault/main.tf

**Fix:** Move all variable blocks to variables.tf. Keep main.tf for resources only.

---

### [MEDIUM] Hardcoded AWS region or account ID in Terraform

**Where:** ./infra/terraform/modules/vault

**Fix:** Move to variables.tf or tfvars. Use data.aws_caller_identity.current.account_id for account IDs.

---

## 4. CI/CD Pipeline

### [MEDIUM] Workflows with no timeout-minutes (runaway jobs waste credits)

**Where:** .github/workflows/buf-lock-generate.yml
.github/workflows/generate-gosum.yml
.github/workflows/gitops-validate.yml
.github/workflows/image-sign.yml
.github/workflows/promote-staging-to-prod.yml
.github/workflows/proto-breaking-change.yml
.github/workflows/release.yml

**Fix:** Add 'timeout-minutes: 30' (or appropriate value) at job level to prevent hung jobs burning CI budget.

---

## 5. Observability

## 6. Dependency Hygiene

---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 1 |
| HIGH     | 9 |
| MEDIUM   | 12 |
| LOW      | 0 |
| **Total**| **22** |

### Recommended fix order

1. **CRITICAL** — fix before next deploy (secrets exposure, state files leaked)
2. **HIGH (Security)** — fix within current sprint (root containers, missing limits)
3. **HIGH (CI/CD)** — fix before next release (unsigned images, missing service entries)
4. **MEDIUM** — schedule in next sprint
5. **LOW** — track as tech debt, address in next refactor cycle
