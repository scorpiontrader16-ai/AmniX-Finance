# YOUTUOP — Enterprise Security Audit Framework
## Financial Data Platform | Multi-Tenant SaaS | AWS EKS ARM64

---

## Quick Start

```bash
# 1. Clone and make executable
chmod +x security-audit-enterprise.sh

# 2. Full audit (all 35 sections)
./security-audit-enterprise.sh --json

# 3. Audit with auto-fix for safe findings
./security-audit-enterprise.sh --fix --json

# 4. Critical findings only
./security-audit-enterprise.sh --critical

# 5. Single section (e.g., only §7 Auth)
./security-audit-enterprise.sh --section 7

# 6. Custom report directory
./security-audit-enterprise.sh --report-dir /var/reports/$(date +%Y%m%d)
```

---

## Audit Sections

| §  | Domain                        | Standard              |
|----|-------------------------------|-----------------------|
| 1  | Environment & Toolchain       | —                     |
| 2  | Secret Leakage (Static)       | PCI-DSS 3.5, SOC2 CC6 |
| 3  | Kubernetes RBAC               | CIS K8s §5.1          |
| 4  | Network Policies              | PCI-DSS Req 1         |
| 5  | Pod Security Standards        | CIS K8s §5.2          |
| 6  | Supply Chain (Cosign/SBOM)    | SLSA Level 2+         |
| 7  | Auth & Authorization          | OWASP API01, PCI-DSS 8 |
| 8  | OWASP API Top 10              | OWASP API 2023        |
| 9  | Encryption (Transit/Rest)     | PCI-DSS Req 4         |
| 10 | External Secrets Operator     | PCI-DSS 3,8           |
| 11 | Falco Runtime Security        | SOC2 CC7.2            |
| 12 | Kyverno Admission Control     | CIS K8s §5.2          |
| 13 | Multi-Tenant Isolation        | SOC2 CC6.1            |
| 14 | SAST (gosec/bandit/semgrep)   | PCI-DSS 6.2           |
| 15 | Dependency CVE Scanning       | NIST SP 800-161       |
| 16 | Terraform / AWS IAM           | CIS AWS Foundations   |
| 17 | CI/CD Pipeline Security       | SLSA, NIST SP 800-218 |
| 18 | ArgoCD / Argo Rollouts        | NIST CSF PR.IP-1      |
| 19 | Audit Logging                 | PCI-DSS Req 10        |
| 20 | Database Security             | CIS PostgreSQL        |
| 21 | Kafka Security                | PCI-DSS Req 4         |
| 22 | Velero Backup Security        | PCI-DSS 12.3.3        |
| 23 | Cert-Manager & PKI            | PCI-DSS Req 4         |
| 24 | Envoy Gateway & Headers       | OWASP Headers         |
| 25 | KEDA Autoscaler               | NIST CSF PR.PT-4      |
| 26 | Chaos Engineering Boundaries  | SOC2 A1.1             |
| 27 | Data Sovereignty / GDPR       | GDPR Art 25           |
| 28 | PCI-DSS Specific Controls     | PCI-DSS v4.0 Full     |
| 29 | Container Image Hardening     | CIS Docker Benchmark  |
| 30 | Incident Response Readiness   | PCI-DSS 12.10         |
| 31 | Live Cluster Checks           | CIS K8s Benchmark v1.9 |
| 32 | Proto/gRPC Security           | NIST SP 800-204       |
| 33 | Schema Registry Security      | Data Governance       |
| 34 | CORS & Security Headers       | OWASP A05             |
| 35 | Compliance Scorecard          | Multi-framework       |

---

## Required Tools Installation

```bash
# Go security tools
go install github.com/securego/gosec/v2/cmd/gosec@latest
go install golang.org/x/vuln/cmd/govulncheck@latest

# Secret scanning
brew install gitleaks
pip install detect-secrets trufflehog

# Container security
brew install cosign syft grype trivy

# SAST
pip install semgrep bandit safety
pip install pip-audit

# Kubernetes
brew install kube-bench kube-linter kubeconform
# kubeaudit: https://github.com/Shopify/kubeaudit/releases

# Infrastructure
brew install tfsec checkov

# JSON processing
brew install jq yq
```

---

## Remediation Priority Matrix

| Priority | Finding Type                        | Action                    | Timeframe |
|----------|-------------------------------------|---------------------------|-----------|
| P0       | CRITICAL: Hardcoded secrets in git  | Rotate all secrets NOW    | < 1 hour  |
| P0       | CRITICAL: Privileged containers     | Remove privileged flag    | < 4 hours |
| P0       | CRITICAL: No RBAC policies          | Apply least-privilege     | < 24 hrs  |
| P0       | CRITICAL: SQL injection             | Parameterize all queries  | < 24 hrs  |
| P1       | FAIL: No NetworkPolicies            | Apply default-deny        | < 1 week  |
| P1       | FAIL: No image signing              | Enable cosign + Kyverno   | < 1 week  |
| P1       | FAIL: No audit logging              | Deploy audit pipeline     | < 1 week  |
| P1       | FAIL: Wildcard CORS                 | Restrict origins          | < 1 week  |
| P2       | WARN: Symmetric JWT (HS256)         | Migrate to RS256          | < 1 month |
| P2       | WARN: Missing MFA                   | Implement TOTP            | < 1 month |
| P2       | WARN: No refresh token rotation     | Implement rotation        | < 1 month |
| P3       | INFO: Actions not SHA-pinned        | Pin to commit SHA         | Next sprint |

---

## Report Files Generated

```
security-reports/TIMESTAMP/
├── findings.log          # Full human-readable audit trail
├── summary.json          # Machine-readable JSON summary
├── gitleaks.json         # Secret leakage in git history
├── trufflehog.json       # High-entropy secret findings
├── gosec-report.json     # Go SAST findings
├── bandit-report.json    # Python SAST findings
├── semgrep-report.json   # Multi-language SAST
├── tfsec-report.json     # Terraform security findings
├── checkov-tf.json       # Terraform checkov results
├── checkov-k8s.json      # K8s manifest checkov results
├── kube-bench.json       # CIS K8s benchmark results
├── safety-report.json    # Python CVE scan
└── pip-audit.json        # Python dependency audit
```

---

## Compliance Mapping

### PCI-DSS v4.0
- **Met by §2**: Req 3.3, 3.5 (secret protection)
- **Met by §4,24**: Req 1 (network controls)
- **Met by §9**: Req 4 (encryption in transit)
- **Met by §7**: Req 8 (authentication)
- **Met by §19**: Req 10 (audit logging)
- **Met by §14**: Req 6 (SAST/SDLC)

### SOC 2 Type II
- **CC6.1**: §7, §10 (access control, secrets)
- **CC6.3**: §3 (RBAC)
- **CC6.6**: §5 (pod security)
- **CC6.7**: §9 (encryption)
- **CC7.2**: §11, §19 (monitoring)
- **CC8.1**: §17, §18 (change management)

### ISO 27001:2022
- **A.5**: §27, §30 (information security policies)
- **A.8**: §3, §5, §13 (access control)
- **A.12**: §19, §22 (logging, backup)
- **A.14**: §14, §15 (security in SDLC)

---

## Integration with CI/CD

Add to `.github/workflows/security-audit.yml`:

```yaml
name: Enterprise Security Audit
on:
  schedule:
    - cron: '0 2 * * 1'   # Weekly Monday 2AM
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  security-events: write

jobs:
  security-audit:
    runs-on: ubuntu-latest-arm64
    steps:
      - uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11
        with:
          fetch-depth: 0   # Full history for gitleaks

      - name: Install audit tools
        run: |
          go install github.com/securego/gosec/v2/cmd/gosec@latest
          go install golang.org/x/vuln/cmd/govulncheck@latest
          pip install bandit safety detect-secrets --break-system-packages

      - name: Run Enterprise Security Audit
        run: |
          chmod +x security-audit-enterprise.sh
          ./security-audit-enterprise.sh --json --critical \
            --report-dir ./security-reports

      - name: Upload Security Reports
        if: always()
        uses: actions/upload-artifact@5d5d22a31266ced268874388b861e4b58bb5c2f3
        with:
          name: security-audit-${{ github.sha }}
          path: security-reports/
          retention-days: 90

      - name: Fail on Critical Findings
        run: |
          CRITICAL=$(jq '.summary.critical' security-reports/*/summary.json)
          [[ "$CRITICAL" -gt 0 ]] && exit 2 || exit 0
```

---

*YOUTUOP Platform Security — Enterprise Grade | Zero Tolerance for Critical Findings*
