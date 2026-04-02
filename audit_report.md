# Institutional Efficiency Audit Report

> Generated: 2026-04-01 23:47:51
> Repo: /workspaces/youtuop-1

---

## 1. Security

## 2. Code Quality

### [MEDIUM] Go functions with DB/client params possibly missing context.Context

**Where:** ~243 candidates — verify manually

**Fix:** First param should be ctx context.Context for all I/O-bound functions to support cancellation and tracing.

---

### [MEDIUM] Bare except: clauses in Python (catches BaseException)

**Where:** 1 occurrences

**Fix:** Replace with 'except SpecificException as e:' to avoid silently catching SystemExit, KeyboardInterrupt.

---

## 3. Infrastructure

### [MEDIUM] Hardcoded AWS region or account ID in Terraform

**Where:** ./infra/terraform/environments/eu-west-1

**Fix:** Move to variables.tf or tfvars. Use data.aws_caller_identity.current.account_id for account IDs.

---

### [MEDIUM] Hardcoded AWS region or account ID in Terraform

**Where:** ./infra/terraform/environments/production

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
| CRITICAL | 0 |
| HIGH     | 0 |
| MEDIUM   | 5 |
| LOW      | 0 |
| **Total**| **5** |

### Recommended fix order

1. **CRITICAL** — fix before next deploy (secrets exposure, state files leaked)
2. **HIGH (Security)** — fix within current sprint (root containers, missing limits)
3. **HIGH (CI/CD)** — fix before next release (unsigned images, missing service entries)
4. **MEDIUM** — schedule in next sprint
5. **LOW** — track as tech debt, address in next refactor cycle
