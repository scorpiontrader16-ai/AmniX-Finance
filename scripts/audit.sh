#!/usr/bin/env bash
set -euo pipefail

REPORT="audit-report.md"
PASS=0; FAIL=0; WARN=0

section() { echo ""; echo "## $1" | tee -a "$REPORT"; echo ""; }
pass()    { echo "- [x] $1" | tee -a "$REPORT"; PASS=$((PASS+1)); }
fail()    { echo "- [ ] FAIL $1" | tee -a "$REPORT"; FAIL=$((FAIL+1)); }
warn()    { echo "- [~] WARN $1" | tee -a "$REPORT"; WARN=$((WARN+1)); }

rm -f "$REPORT"
echo "# Youtuop Platform — Full Audit Report" >> "$REPORT"
echo "Generated: $(date -u)" >> "$REPORT"
echo "Commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)" >> "$REPORT"
echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)" >> "$REPORT"
echo "---" >> "$REPORT"

# ══════════════════════════════════════════════════════════════════
# 1. Repository Structure
# ══════════════════════════════════════════════════════════════════
section "1. Repository Structure"
find . -mindepth 1 -maxdepth 3 \
  -not -path "./.git/*" \
  -not -path "./vendor/*" \
  -not -path "./target/*" \
  -not -path "./.terraform/*" \
  | sort >> "$REPORT"

# ══════════════════════════════════════════════════════════════════
# 2. Duplicate Files
# ══════════════════════════════════════════════════════════════════
section "2. Duplicate Files"
if command -v fdupes >/dev/null 2>&1; then
  DUP=$(fdupes -rq . --exclude=".git" --exclude="vendor" 2>/dev/null || true)
  if [ -z "$DUP" ]; then pass "No exact duplicate files"
  else fail "Duplicate files found"; echo "$DUP" >> "$REPORT"; fi
else
  warn "fdupes not installed — skipping exact duplicate check"
fi

SAME=$(find . -not -path "./.git/*" -not -path "./vendor/*" -type f \
  | awk -F/ '{print $NF}' | sort | uniq -d)
if [ -z "$SAME" ]; then pass "No filename collisions"
else warn "Same filename exists in multiple paths (expected in monorepo)"; echo "$SAME" >> "$REPORT"; fi

# ══════════════════════════════════════════════════════════════════
# 3. Go Services
# ══════════════════════════════════════════════════════════════════
section "3. Go Services"
find services -maxdepth 2 -name "go.mod" | sort | while read -r modfile; do
  DIR=$(dirname "$modfile")
  OUT=$(cd "$DIR" && go build ./... 2>&1 || true)
  if [ -z "$OUT" ]; then pass "go build OK: $DIR"; else fail "go build FAILED: $DIR"; echo "$OUT" >> "$REPORT"; fi
  OUT=$(cd "$DIR" && go vet ./... 2>&1 || true)
  if [ -z "$OUT" ]; then pass "go vet OK: $DIR"; else fail "go vet issues: $DIR"; echo "$OUT" >> "$REPORT"; fi
  if [ -f "$DIR/Dockerfile" ] || [ -f "$DIR/Dockerfile.arm64" ]; then
    pass "Dockerfile present: $DIR"
  else
    fail "Dockerfile MISSING: $DIR"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 4. Rust Services
# ══════════════════════════════════════════════════════════════════
section "4. Rust Services"
find . -not -path "./.git/*" -not -path "./target/*" -name "Cargo.toml" | sort | while read -r f; do
  DIR=$(dirname "$f")
  if grep -q "^\[package\]" "$f" 2>/dev/null; then
    OUT=$(cd "$DIR" && cargo check 2>&1 || true)
    if echo "$OUT" | grep -q "^error"; then
      fail "cargo check FAILED: $DIR"
      echo "$OUT" | grep "^error" | head -10 >> "$REPORT"
    else
      pass "cargo check OK: $DIR"
    fi
  fi
done

# ══════════════════════════════════════════════════════════════════
# 5. Proto Generated Files
# ══════════════════════════════════════════════════════════════════
section "5. Proto Generated Files"
find proto -name "*.proto" 2>/dev/null | sort | while read -r proto; do
  BASE=$(basename "$proto" .proto)
  PB=$(find gen -name "${BASE}.pb.go" 2>/dev/null)
  if [ -z "$PB" ]; then fail "Missing gen/${BASE}.pb.go"; else pass "${BASE}.pb.go exists"; fi
  if grep -q "^service " "$proto" 2>/dev/null; then
    GRPC=$(find gen -name "${BASE}_grpc.pb.go" 2>/dev/null)
    if [ -z "$GRPC" ]; then fail "Missing gen/${BASE}_grpc.pb.go"; else pass "${BASE}_grpc.pb.go exists"; fi
  fi
done

# ══════════════════════════════════════════════════════════════════
# 6. Kubernetes Manifests — kubeconform
# ══════════════════════════════════════════════════════════════════
section "6. Kubernetes Manifests — kubeconform"
if command -v kubeconform >/dev/null 2>&1; then
  FILES=$(find k8s -\( -name "*.yaml" -o -name "*.yml" \) \
    | xargs grep -l "^kind:" 2>/dev/null | head -200)
  if [ -n "$FILES" ]; then
    OUT=$(echo "$FILES" | xargs kubeconform -summary -ignore-missing-schemas \
      -skip HelmRelease,Application,AppProject,ApplicationSet \
      -skip CiliumNetworkPolicy,ClusterSecretStore,ExternalSecret,SecretStore \
      -skip Certificate,ClusterIssuer,Issuer \
      -skip Rollout,AnalysisTemplate \
      -skip ScaledObject,ScaledJob,TriggerAuthentication \
      -skip GatewayClass,Gateway,HTTPRoute,GRPCRoute,BackendTrafficPolicy \
      -skip BackendLBPolicy,BackendTLSPolicy,SecurityPolicy \
      -skip Kustomization,HelmRepository,GitRepository \
      -skip ClusterPolicy,Policy \
      2>&1 || true)
    ERR=$(echo "$OUT" | grep -ic "^.*error" || true)
    if [ "$ERR" -eq 0 ]; then
      pass "kubeconform OK (CRDs skipped)"
      echo "$OUT" | tail -3 >> "$REPORT"
    else
      fail "kubeconform $ERR error(s)"
      echo "$OUT" | grep -i "error" | head -20 >> "$REPORT"
    fi
  else
    warn "No K8s manifests found"
  fi
else
  warn "kubeconform not installed"
fi

# ══════════════════════════════════════════════════════════════════
# 7. Helm Charts
# ══════════════════════════════════════════════════════════════════
section "7. Helm Charts"
if command -v helm >/dev/null 2>&1; then
  find . -not -path "./.git/*" -name "Chart.yaml" | sort | while read -r f; do
    DIR=$(dirname "$f")
    NAME=$(basename "$DIR")
    OUT=$(helm lint "$DIR" 2>&1 || true)
    ERRS=$(echo "$OUT" | grep -c "^\[ERROR\]" || true)
    WARNS=$(echo "$OUT" | grep -c "^\[WARNING\]" || true)
    if [ "$ERRS" -eq 0 ] && [ "$WARNS" -eq 0 ]; then pass "helm lint $NAME OK"
    elif [ "$ERRS" -eq 0 ]; then warn "helm lint $NAME: $WARNS warning(s)"
    else fail "helm lint $NAME: $ERRS error(s)"; echo "$OUT" | grep "ERROR" >> "$REPORT"
    fi
  done
else
  warn "helm not installed"
fi

# ══════════════════════════════════════════════════════════════════
# 8. ArgoCD App Paths
# ══════════════════════════════════════════════════════════════════
section "8. ArgoCD App Paths"
if command -v yq >/dev/null 2>&1; then
  find infra/argocd -\( -name "*.yaml" -o -name "*.yml" \) \
    | xargs grep -l "kind: Application$" 2>/dev/null | sort | while read -r app; do
    NAME=$(yq '.metadata.name' "$app" 2>/dev/null || echo "unknown")
    PVAL=$(yq '.spec.source.path' "$app" 2>/dev/null || echo "")
    if [ -n "$PVAL" ] && [ "$PVAL" != "null" ]; then
      CLEAN="${PVAL#/}"
      if [ -d "$CLEAN" ] || [ -f "$CLEAN" ]; then
        pass "App '$NAME' path '$PVAL' OK"
      else
        fail "App '$NAME' path '$PVAL' NOT FOUND on disk"
      fi
    fi
  done
else
  warn "yq not installed — skipping ArgoCD path check"
fi

# ══════════════════════════════════════════════════════════════════
# 9. Empty Directories
# ══════════════════════════════════════════════════════════════════
section "9. Empty Directories"
EMPTY=$(find . -not -path "./.git/*" -not -path "./vendor/*" -type d -empty 2>/dev/null | sort)
if [ -z "$EMPTY" ]; then pass "No empty directories"
else warn "Empty directories found:"; echo "$EMPTY" >> "$REPORT"
fi

# ══════════════════════════════════════════════════════════════════
# 10. Large Files (tracked by git, >1MB)
# ══════════════════════════════════════════════════════════════════
section "10. Large Files over 1MB (git-tracked)"
LARGE=$(git ls-files | xargs -I{} find {} -size +1M 2>/dev/null | sort)
if [ -z "$LARGE" ]; then pass "No large files tracked in git"
else fail "Large files tracked in git:"; echo "$LARGE" >> "$REPORT"; fi

set +e

# ══════════════════════════════════════════════════════════════════
# 11. Kustomization Orphan Files
# ══════════════════════════════════════════════════════════════════
section "11. Kustomization Orphan Files"
ORPHAN_COUNT=0
for dir in k8s/base/*/; do
  kust="$dir/kustomization.yaml"
  [ -f "$kust" ] || continue
  for yaml_file in "$dir"*.yaml; do
    fname=$(basename "$yaml_file")
    [ "$fname" = "kustomization.yaml" ] && continue
    if ! grep -q "$fname" "$kust"; then
      fail "ORPHAN (not in kustomization): $yaml_file"
      ORPHAN_COUNT=$((ORPHAN_COUNT+1))
    fi
  done
done
[ "$ORPHAN_COUNT" -eq 0 ] && pass "No orphan yaml files in k8s/base"

# ══════════════════════════════════════════════════════════════════
# 12. Overlays Completeness (app services only)
# ══════════════════════════════════════════════════════════════════
section "12. Overlays Completeness (app services)"
for svc in services/*/; do
  name=$(basename "$svc")
  staging="k8s/overlays/staging/$name/kustomization.yaml"
  production="k8s/overlays/production/$name/kustomization.yaml"
  [ -f "$staging" ]    || fail "Missing overlay staging: $name"
  [ -f "$production" ] || fail "Missing overlay production: $name"
  [ -f "$staging" ] && [ -f "$production" ] && pass "Overlays OK: $name"
done

# ══════════════════════════════════════════════════════════════════
# 13. Service Completeness — ESO / PDB / ScaledObject
# ══════════════════════════════════════════════════════════════════
section "13. Service Completeness — ESO / PDB / ScaledObject"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  eso=$(find "$base" -maxdepth 1 -name "externalsecret*.yaml" 2>/dev/null | wc -l)
  pdb=$(find "$base" -maxdepth 1 -name "pdb*.yaml" -o -name "poddisruptionbudget*.yaml" 2>/dev/null | wc -l)
  hpa=$(find "$base" -maxdepth 1 -name "hpa*.yaml" -o -name "scaledobject*.yaml" 2>/dev/null | wc -l)
  [ "$eso" -eq 0 ] && fail "Missing ExternalSecret: $name"
  [ "$pdb" -eq 0 ] && fail "Missing PodDisruptionBudget: $name"
  [ "$hpa" -eq 0 ] && fail "Missing ScaledObject/HPA: $name"
  [ "$eso" -gt 0 ] && [ "$pdb" -gt 0 ] && [ "$hpa" -gt 0 ] && pass "ESO+PDB+ScaledObject OK: $name"
done

# ══════════════════════════════════════════════════════════════════
# 14. ArgoCD Applications exist
# ══════════════════════════════════════════════════════════════════
section "14. ArgoCD Applications"
ARGOCD_APPS=$(find k8s/ infra/ -name "*.yaml" 2>/dev/null \
  | xargs grep -l "kind: Application" 2>/dev/null | wc -l)
ARGOCD_APPSETS=$(find k8s/ infra/ -name "*.yaml" 2>/dev/null \
  | xargs grep -l "kind: ApplicationSet" 2>/dev/null | wc -l)
if [ "$ARGOCD_APPS" -gt 0 ] || [ "$ARGOCD_APPSETS" -gt 0 ]; then
  pass "ArgoCD Applications found: apps=$ARGOCD_APPS appsets=$ARGOCD_APPSETS"
else
  fail "No ArgoCD Application or ApplicationSet — cluster will not sync"
fi

# ══════════════════════════════════════════════════════════════════
# 15. CI/CD Build + Trivy Coverage
# ══════════════════════════════════════════════════════════════════
section "15. CI/CD Coverage — Build + Trivy"
CI_FILE=".github/workflows/ci.yml"
for svc in services/*/; do
  name=$(basename "$svc")
  [ -f "$svc/go.mod" ] || continue
  if grep -q "build-$name\|working-directory: services/$name" "$CI_FILE" 2>/dev/null; then
    pass "CI build job exists: $name"
  else
    fail "Missing CI build job: $name"
  fi
done
for svc in services/*/; do
  name=$(basename "$svc")
  if grep -q "trivy-$name" "$CI_FILE" 2>/dev/null; then
    pass "Trivy scan exists: $name"
  else
    fail "Missing Trivy scan in CI: $name"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 16. IRSA Annotations — AWS Readiness
# ══════════════════════════════════════════════════════════════════
section "16. IRSA Annotations — AWS Readiness"
IRSA_MISSING=0
for svc in services/*/; do
  name=$(basename "$svc")
  sa="k8s/base/$name/serviceaccount.yaml"
  [ -f "$sa" ] || continue
  if grep -q "eks.amazonaws.com/role-arn\|eks.amazonaws" "$sa" 2>/dev/null; then
    pass "IRSA annotation present: $name"
  else
    warn "IRSA annotation missing (required for AWS): $name"
    IRSA_MISSING=$((IRSA_MISSING+1))
  fi
done
[ "$IRSA_MISSING" -gt 0 ] && warn "Total services missing IRSA: $IRSA_MISSING"

# ══════════════════════════════════════════════════════════════════
# 17. Terraform
# ══════════════════════════════════════════════════════════════════
section "17. Terraform"
if [ -d "terraform/" ]; then
  TF_FILES=$(find terraform/ -name "*.tf" | wc -l)
  [ "$TF_FILES" -gt 0 ] && pass "Terraform files found: $TF_FILES" \
    || fail "terraform/ exists but contains no .tf files"
  for env in terraform/environments/*/; do
    [ -d "$env" ] || continue
    ename=$(basename "$env")
    [ -f "$env/main.tf" ]          || fail "Missing $ename/main.tf"
    [ -f "$env/variables.tf" ]     || fail "Missing $ename/variables.tf"
    [ -f "$env/terraform.tfvars" ] || fail "Missing $ename/terraform.tfvars"
    [ -f "$env/backend.tf" ]       || fail "Missing $ename/backend.tf"
    [ -f "$env/main.tf" ] && [ -f "$env/variables.tf" ] && \
    [ -f "$env/terraform.tfvars" ] && [ -f "$env/backend.tf" ] && \
      pass "Terraform environment complete: $ename"
  done
else
  fail "terraform/ not found — AWS deployment impossible"
fi

# ══════════════════════════════════════════════════════════════════
# 18. Cargo.lock
# ══════════════════════════════════════════════════════════════════
section "18. Cargo.lock"
find services/ -name "Cargo.toml" | while read -r f; do
  dir=$(dirname "$f")
  name=$(basename "$dir")
  if grep -q "^\[package\]" "$f" 2>/dev/null; then
    [ -f "$dir/Cargo.lock" ] \
      && pass "Cargo.lock present: $name" \
      || fail "Cargo.lock missing: $name"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 19. Kustomization Header Accuracy
# ══════════════════════════════════════════════════════════════════
section "19. Kustomization Header Accuracy"
for kust in k8s/base/*/kustomization.yaml; do
  dir=$(dirname "$kust")
  name=$(basename "$dir")
  if grep -q "المسار الكامل" "$kust"; then
    declared=$(grep "المسار الكامل" "$kust" \
      | grep -o "k8s/base/[^/]*/kustomization.yaml" | head -1)
    if [ -n "$declared" ] && [ "$declared" != "k8s/base/$name/kustomization.yaml" ]; then
      fail "Wrong header in $name/kustomization.yaml — declares $declared"
    else
      pass "Header accurate: $name"
    fi
  fi
done

# ══════════════════════════════════════════════════════════════════
# 20. Security — Hardcoded Secrets Scan
# لماذا: secret مكتوب في الكود يُسرَّب في git history للأبد
# ══════════════════════════════════════════════════════════════════
section "20. Security — Hardcoded Secrets Scan"
SECRET_PATTERNS=(
  'password\s*=\s*"[^"]+'
  'secret\s*=\s*"[^"]+'
  'api_key\s*=\s*"[^"]+'
  'apikey\s*=\s*"[^"]+'
  'token\s*=\s*"[^"]+'
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'
  'Authorization:\s*Bearer\s+[A-Za-z0-9\-_.]+'
)
SECRET_FOUND=0
for pattern in "${SECRET_PATTERNS[@]}"; do
  HITS=$(grep -rniE "$pattern" \
    --include="*.go" --include="*.rs" --include="*.py" \
    --include="*.ts" --include="*.js" --include="*.env" \
    --exclude-dir=".git" --exclude-dir="vendor" --exclude-dir="target" \
    . 2>/dev/null \
    | grep -v "_test.go" \
    | grep -v "example\|sample\|placeholder\|YOUR_\|CHANGE_ME\|TODO\|fake\|mock" \
    | grep -v "^Binary" || true)
  if [ -n "$HITS" ]; then
    fail "Potential hardcoded secret (pattern: $pattern)"
    echo "$HITS" | head -5 >> "$REPORT"
    SECRET_FOUND=$((SECRET_FOUND+1))
  fi
done
[ "$SECRET_FOUND" -eq 0 ] && pass "No hardcoded secrets detected in source code"

# ══════════════════════════════════════════════════════════════════
# 21. Security — Pod Security Context
# لماذا: container يشتغل كـ root أو بصلاحيات escalation = ثغرة أمنية
# ══════════════════════════════════════════════════════════════════
section "21. Security — Pod Security Context"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  # ابحث في deployment.yaml أو rollout.yaml
  manifest=$(find "$base" -maxdepth 1 \( -name "deployment.yaml" -o -name "rollout.yaml" \) 2>/dev/null | head -1)
  [ -z "$manifest" ] && continue

  grep -q "runAsNonRoot: true" "$manifest" \
    && pass "runAsNonRoot=true: $name" \
    || fail "runAsNonRoot missing or false: $name"

  grep -q "readOnlyRootFilesystem: true" "$manifest" \
    && pass "readOnlyRootFilesystem=true: $name" \
    || fail "readOnlyRootFilesystem missing or false: $name"

  grep -q 'allowPrivilegeEscalation: false' "$manifest" \
    && pass "allowPrivilegeEscalation=false: $name" \
    || fail "allowPrivilegeEscalation missing: $name"

  grep -q 'drop:' "$manifest" \
    && pass "capabilities.drop present: $name" \
    || fail "capabilities.drop missing: $name"
done

# ══════════════════════════════════════════════════════════════════
# 22. Security — NetworkPolicy Coverage
# لماذا: بدون NetworkPolicy أي pod يقدر يكلّم أي pod في الـ cluster
# ══════════════════════════════════════════════════════════════════
section "22. Security — NetworkPolicy Coverage"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  if find "$base" -maxdepth 1 -name "networkpolicy*.yaml" 2>/dev/null | grep -q .; then
    pass "NetworkPolicy present: $name"
  else
    fail "NetworkPolicy MISSING: $name"
  fi
done

# تحقق من وجود default-deny في كل namespace
if find k8s/ -name "*.yaml" | xargs grep -l "default-deny\|deny-all" 2>/dev/null | grep -q .; then
  pass "Default-deny NetworkPolicy found"
else
  warn "No default-deny NetworkPolicy found — open mesh by default"
fi

# ══════════════════════════════════════════════════════════════════
# 23. Security — ServiceAccount Token Automount
# لماذا: token مرفوع تلقائياً يُعرِّض الـ API server لأي container مخترق
# ══════════════════════════════════════════════════════════════════
section "23. Security — ServiceAccount Token Automount Disabled"
for svc in services/*/; do
  name=$(basename "$svc")
  sa="k8s/base/$name/serviceaccount.yaml"
  [ -f "$sa" ] || continue
  if grep -q "automountServiceAccountToken: false" "$sa"; then
    pass "automountServiceAccountToken=false: $name"
  else
    fail "automountServiceAccountToken not disabled: $name"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 24. Security — No :latest Image Tags
# لماذا: :latest غير محدد الإصدار — يكسر reproducibility والـ rollback
# ══════════════════════════════════════════════════════════════════
section "24. Security — No :latest Image Tags"
LATEST_HITS=$(grep -rn "image:.*:latest" k8s/ \
  --include="*.yaml" 2>/dev/null | grep -v "^#" || true)
if [ -z "$LATEST_HITS" ]; then
  pass "No :latest image tags in k8s manifests"
else
  fail "Found :latest image tags — breaks reproducibility"
  echo "$LATEST_HITS" >> "$REPORT"
fi

# ══════════════════════════════════════════════════════════════════
# 25. Security — RBAC: No ClusterAdmin for App Services
# لماذا: cluster-admin = god mode — أي service يخترق يتحكم في كل الـ cluster
# ══════════════════════════════════════════════════════════════════
section "25. Security — RBAC ClusterAdmin Check"
CLUSTER_ADMIN=$(grep -rn "cluster-admin" k8s/ --include="*.yaml" 2>/dev/null \
  | grep -v "^#" \
  | grep -v "argocd\|kyverno\|cert-manager\|cilium\|velero" || true)
if [ -z "$CLUSTER_ADMIN" ]; then
  pass "No app service bound to cluster-admin"
else
  warn "cluster-admin binding found — verify it is infrastructure only:"
  echo "$CLUSTER_ADMIN" >> "$REPORT"
fi

# ══════════════════════════════════════════════════════════════════
# 26. Security — Kyverno Policies Present
# لماذا: Kyverno = admission controller — يمنع manifests غير الآمنة من الدخول
# ══════════════════════════════════════════════════════════════════
section "26. Security — Kyverno Policies"
KYVERNO_POLICIES=$(find k8s/ -name "*.yaml" 2>/dev/null \
  | xargs grep -l "kind: ClusterPolicy\|kind: Policy" 2>/dev/null | wc -l)
if [ "$KYVERNO_POLICIES" -gt 0 ]; then
  pass "Kyverno ClusterPolicy/Policy found: $KYVERNO_POLICIES file(s)"
else
  fail "No Kyverno policies found — no admission enforcement"
fi

# ══════════════════════════════════════════════════════════════════
# 27. Kubernetes — Resource Requests & Limits
# لماذا: بدون limits الـ container ياكل كل موارد الـ node وييجي OOMKilled
# ══════════════════════════════════════════════════════════════════
section "27. Kubernetes — Resource Requests & Limits"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  manifest=$(find "$base" -maxdepth 1 \( -name "deployment.yaml" -o -name "rollout.yaml" \) 2>/dev/null | head -1)
  [ -z "$manifest" ] && continue
  grep -q "requests:" "$manifest" \
    && pass "resources.requests present: $name" \
    || fail "resources.requests MISSING: $name"
  grep -q "limits:" "$manifest" \
    && pass "resources.limits present: $name" \
    || fail "resources.limits MISSING: $name"
done

# ══════════════════════════════════════════════════════════════════
# 28. Kubernetes — Liveness & Readiness Probes
# لماذا: بدون probes الـ pod بيظل في الـ LB حتى لو dead
# ══════════════════════════════════════════════════════════════════
section "28. Kubernetes — Health Probes"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  manifest=$(find "$base" -maxdepth 1 \( -name "deployment.yaml" -o -name "rollout.yaml" \) 2>/dev/null | head -1)
  [ -z "$manifest" ] && continue
  grep -q "livenessProbe:" "$manifest" \
    && pass "livenessProbe present: $name" \
    || fail "livenessProbe MISSING: $name"
  grep -q "readinessProbe:" "$manifest" \
    && pass "readinessProbe present: $name" \
    || fail "readinessProbe MISSING: $name"
done

# ══════════════════════════════════════════════════════════════════
# 29. Kubernetes — Certificate Coverage
# لماذا: كل service يحتاج TLS certificate من cert-manager للـ mTLS
# ══════════════════════════════════════════════════════════════════
section "29. Kubernetes — Certificate Coverage"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  if find "$base" -maxdepth 1 -name "certificate*.yaml" 2>/dev/null | grep -q .; then
    pass "Certificate present: $name"
  else
    warn "Certificate missing: $name (required for mTLS)"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 30. Kubernetes — Prometheus Annotations on Workloads
# لماذا: بدون annotations الـ Prometheus مش هيعرف يـ scrape الـ metrics
# ══════════════════════════════════════════════════════════════════
section "30. Kubernetes — Prometheus Scrape Annotations"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  manifest=$(find "$base" -maxdepth 1 \( -name "deployment.yaml" -o -name "rollout.yaml" \) 2>/dev/null | head -1)
  [ -z "$manifest" ] && continue
  if grep -q "prometheus.io/scrape" "$manifest"; then
    pass "Prometheus scrape annotation present: $name"
  else
    warn "Prometheus scrape annotation missing: $name"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 31. Kubernetes — Namespace Consistency
# لماذا: resource في namespace خطأ = ArgoCD يرفضه أو يعزله غلط
# ══════════════════════════════════════════════════════════════════
section "31. Kubernetes — Namespace Consistency"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  NAMESPACES=$(grep -rh "namespace:" "$base" --include="*.yaml" 2>/dev/null \
    | grep -v "^#" | sort -u | grep -v "kustomization" || true)
  NS_COUNT=$(echo "$NAMESPACES" | grep -v "^$" | wc -l)
  if [ "$NS_COUNT" -le 1 ]; then
    pass "Namespace consistent: $name"
  else
    warn "Multiple namespaces in $name manifests — verify intentional:"
    echo "$NAMESPACES" >> "$REPORT"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 32. CI/CD — Required Workflow Files Exist
# لماذا: ملف workflow ناقص = pipeline كامل بيوقف
# ══════════════════════════════════════════════════════════════════
section "32. CI/CD — Required Workflow Files"
REQUIRED_WORKFLOWS=(
  ".github/workflows/ci.yml"
  ".github/workflows/release.yml"
  ".github/workflows/image-sign.yml"
)
for wf in "${REQUIRED_WORKFLOWS[@]}"; do
  [ -f "$wf" ] && pass "Workflow exists: $wf" || fail "Workflow MISSING: $wf"
done

# ══════════════════════════════════════════════════════════════════
# 33. CI/CD — Workflow YAML Validity
# لماذا: YAML خطأ = GitHub Actions يرفض الـ workflow بالكامل
# ══════════════════════════════════════════════════════════════════
section "33. CI/CD — Workflow YAML Validity"
if command -v python3 >/dev/null 2>&1; then
  find .github/workflows -name "*.yml" -o -name "*.yaml" 2>/dev/null | sort | while read -r wf; do
    ERR=$(python3 -c "
import yaml, sys
try:
    list(yaml.safe_load_all(open('$wf')))
    print('ok')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)
    if echo "$ERR" | grep -q "^ok"; then
      pass "Valid YAML: $wf"
    else
      fail "Invalid YAML: $wf — $ERR"
    fi
  done
else
  warn "python3 not available — skipping workflow YAML validation"
fi

# ══════════════════════════════════════════════════════════════════
# 34. CI/CD — image-sign.yml + release.yml Coverage per Service
# لماذا: service بدون entry = image مش موقّع ومش بيتنزل على الـ cluster
# ══════════════════════════════════════════════════════════════════
section "34. CI/CD — image-sign.yml + release.yml Per-Service Coverage"
for svc in services/*/; do
  name=$(basename "$svc")
  grep -qi "$name" .github/workflows/image-sign.yml 2>/dev/null \
    && pass "image-sign.yml covers: $name" \
    || fail "image-sign.yml MISSING: $name"
  grep -qi "$name" .github/workflows/release.yml 2>/dev/null \
    && pass "release.yml covers: $name" \
    || fail "release.yml MISSING: $name"
done

# ══════════════════════════════════════════════════════════════════
# 35. Go — Module Hygiene
# لماذا: replace directive لـ local path = build يفشل خارج الـ dev machine
# ══════════════════════════════════════════════════════════════════
section "35. Go — Module Hygiene"
find services -maxdepth 2 -name "go.mod" | sort | while read -r modfile; do
  dir=$(dirname "$modfile")
  name=$(basename "$dir")

  # go.sum يجب أن يكون موجوداً
  [ -f "$dir/go.sum" ] \
    && pass "go.sum present: $name" \
    || fail "go.sum MISSING: $name — run 'go mod tidy'"

  # لا replace directives تشير لـ local paths
  LOCAL_REPLACE=$(grep "^replace" "$modfile" | grep "\.\." || true)
  if [ -n "$LOCAL_REPLACE" ]; then
    fail "Local replace directive in go.mod: $name"
    echo "$LOCAL_REPLACE" >> "$REPORT"
  else
    pass "No local replace directives: $name"
  fi

  # كل dependency محددة الإصدار (لا pseudo-versions للـ main packages)
  PSEUDO=$(grep "v0\.0\.0-[0-9]" "$modfile" | grep -v "//\s*indirect" | wc -l)
  if [ "$PSEUDO" -gt 3 ]; then
    warn "Many pseudo-version dependencies in $name ($PSEUDO) — consider pinning"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 36. Proto Tooling
# لماذا: buf.yaml ناقص = buf lint يفشل = proto generation ينكسر
# ══════════════════════════════════════════════════════════════════
section "36. Proto Tooling"
[ -f "buf.yaml" ]     && pass "buf.yaml present at root"     || fail "buf.yaml MISSING at root"
[ -f "buf.gen.yaml" ] && pass "buf.gen.yaml present at root" || fail "buf.gen.yaml MISSING at root"
[ -f "buf.lock" ]     && pass "buf.lock present at root"     || warn "buf.lock missing — run 'buf dep update'"

# buf lint
if command -v buf >/dev/null 2>&1; then
  BUFERR=$(buf lint 2>&1 || true)
  if [ -z "$BUFERR" ]; then
    pass "buf lint OK"
  else
    fail "buf lint errors:"
    echo "$BUFERR" >> "$REPORT"
  fi
else
  warn "buf not installed — skipping proto lint"
fi

# ══════════════════════════════════════════════════════════════════
# 37. Database Migrations — Sequencing & Scope Headers
# لماذا: فجوة في الترقيم = goose يوقف الـ migration chain
# ══════════════════════════════════════════════════════════════════
section "37. Database Migrations — Sequencing & Scope Headers"
find services -path "*/migrations/*.sql" 2>/dev/null | sort | while read -r f; do
  # تحقق من scope header
  if grep -q "^-- Scope:" "$f"; then
    pass "Scope header present: $(basename $f)"
  else
    fail "Scope header missing: $f"
  fi
done

# تحقق من عدم تكرار أرقام الـ migration
ALL_NUMS=$(find services -path "*/migrations/*.sql" 2>/dev/null \
  | awk -F/ '{print $NF}' | grep -oE '^[0-9]+' | sort)
DUP_NUMS=$(echo "$ALL_NUMS" | uniq -d)
if [ -z "$DUP_NUMS" ]; then
  pass "No duplicate migration numbers"
else
  fail "Duplicate migration numbers found:"
  echo "$DUP_NUMS" >> "$REPORT"
fi

# ══════════════════════════════════════════════════════════════════
# 38. Git Hygiene — No Secrets or Binaries Tracked
# لماذا: .env في git history = بيانات مسرَّبة للأبد حتى بعد الحذف
# ══════════════════════════════════════════════════════════════════
section "38. Git Hygiene — No Secrets or Binaries Tracked"

# ملفات .env محظورة
ENV_TRACKED=$(git ls-files | grep -E "^\.env$|/\.env$|\.env\." | grep -v ".env.example" || true)
if [ -z "$ENV_TRACKED" ]; then
  pass "No .env files tracked in git"
else
  fail "Secret .env files tracked in git:"
  echo "$ENV_TRACKED" >> "$REPORT"
fi

# مفاتيح خاصة
KEY_TRACKED=$(git ls-files | grep -E "\.(pem|key|p12|pfx|jks)$" || true)
if [ -z "$KEY_TRACKED" ]; then
  pass "No private key files tracked in git"
else
  fail "Private key files tracked in git:"
  echo "$KEY_TRACKED" >> "$REPORT"
fi

# Merge conflict markers
CONFLICT=$(grep -rn "^<<<<<<< \|^>>>>>>> \|^=======$" \
  --include="*.go" --include="*.rs" --include="*.py" \
  --include="*.yaml" --include="*.yml" --include="*.tf" \
  --exclude-dir=".git" . 2>/dev/null || true)
if [ -z "$CONFLICT" ]; then
  pass "No merge conflict markers in source files"
else
  fail "Merge conflict markers found:"
  echo "$CONFLICT" | head -10 >> "$REPORT"
fi

# Binary files tracked (عدا الـ images المتوقعة)
BIN_TRACKED=$(git ls-files | xargs -I{} file {} 2>/dev/null \
  | grep -v "text\|ASCII\|UTF-8\|JSON\|YAML\|empty\|symlink" \
  | grep -v "\.(png\|jpg\|jpeg\|gif\|svg\|ico\|woff\|ttf):" \
  | grep -v "^Binary" || true)
if [ -z "$BIN_TRACKED" ]; then
  pass "No unexpected binary files tracked"
else
  warn "Possible binary files tracked in git:"
  echo "$BIN_TRACKED" | head -10 >> "$REPORT"
fi

# ══════════════════════════════════════════════════════════════════
# 39. Python — Dependency Pinning
# لماذا: dependency غير مثبتة = build مختلف في كل مرة = CVEs مخفية
# ══════════════════════════════════════════════════════════════════
section "39. Python — Dependency Pinning"
find services -name "requirements.txt" 2>/dev/null | sort | while read -r req; do
  name=$(dirname "$req" | xargs basename)
  UNPINNED=$(grep -vE "^\s*#|^\s*$|==" "$req" | grep -vE "^-r |^-c |^--" || true)
  if [ -z "$UNPINNED" ]; then
    pass "All dependencies pinned with ==: $name"
  else
    fail "Unpinned dependencies in $name/requirements.txt:"
    echo "$UNPINNED" >> "$REPORT"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 40. Documentation — README per Service
# لماذا: service بدون README = الـ onboarding يأخذ أيام بدل ساعات
# ══════════════════════════════════════════════════════════════════
section "40. Documentation — README per Service"
[ -f "README.md" ] && pass "Root README.md present" || warn "Root README.md missing"
[ -f "CHANGELOG.md" ] && pass "CHANGELOG.md present" || warn "CHANGELOG.md missing"

for svc in services/*/; do
  name=$(basename "$svc")
  if [ -f "$svc/README.md" ]; then
    pass "README.md present: $name"
  else
    warn "README.md missing: $name"
  fi
done

# ══════════════════════════════════════════════════════════════════
# 41. .env.example Completeness
# لماذا: .env.example ناقصة = developer جديد مش عارف الـ vars المطلوبة
# ══════════════════════════════════════════════════════════════════
section "41. .env.example Completeness"
if [ -f ".env.example" ]; then
  pass ".env.example present at root"
  # تحقق إن مفيش قيم حقيقية مكتوبة فيه
  REAL_VALUES=$(grep -vE "^\s*#|^\s*$|=\s*$|=your_|=CHANGE_ME|=<|=example|=placeholder|=xxx" \
    .env.example 2>/dev/null | grep "=" | head -5 || true)
  if [ -n "$REAL_VALUES" ]; then
    warn ".env.example may contain real values — verify:"
    echo "$REAL_VALUES" >> "$REPORT"
  else
    pass ".env.example contains no apparent real secrets"
  fi
else
  fail ".env.example missing at root — developers cannot configure locally"
fi

# ══════════════════════════════════════════════════════════════════
# 42. Cosign / Supply Chain — SBOM & Signatures
# لماذا: image غير موقّع = Kyverno يرفضه = deployment يفشل على AWS
# ══════════════════════════════════════════════════════════════════
section "42. Supply Chain — Cosign & SBOM Workflow"
if grep -q "cosign" .github/workflows/image-sign.yml 2>/dev/null; then
  pass "cosign signing present in image-sign.yml"
else
  fail "cosign signing NOT found in image-sign.yml"
fi

if grep -q "sbom\|syft\|cyclonedx" .github/workflows/image-sign.yml 2>/dev/null; then
  pass "SBOM generation present in image-sign.yml"
else
  warn "SBOM generation not found in image-sign.yml"
fi

if grep -q "grype\|trivy" .github/workflows/image-sign.yml 2>/dev/null; then
  pass "Vulnerability scan present in image-sign.yml"
else
  warn "Vulnerability scan not found in image-sign.yml"
fi

# ══════════════════════════════════════════════════════════════════
# 43. ArgoCD ApplicationSet — All App Services Covered
# لماذا: service غير مدرج في ApplicationSet = ArgoCD مش هيـ deploy
# ══════════════════════════════════════════════════════════════════
section "43. ArgoCD ApplicationSet Coverage"
APPSET_FILE=$(find infra/ k8s/ -name "*.yaml" 2>/dev/null \
  | xargs grep -l "kind: ApplicationSet" 2>/dev/null | head -1)
if [ -z "$APPSET_FILE" ]; then
  fail "No ApplicationSet file found"
else
  pass "ApplicationSet found: $APPSET_FILE"
  for svc in services/*/; do
    name=$(basename "$svc")
    if grep -q "$name" "$APPSET_FILE" 2>/dev/null; then
      pass "ApplicationSet covers: $name"
    else
      warn "ApplicationSet may not cover: $name — verify manually"
    fi
  done
fi

# ══════════════════════════════════════════════════════════════════
# 44. Dockerfile Convention
# لماذا: ml-engine بـ Dockerfile.arm64 = wrong base image = build فاشل
# ══════════════════════════════════════════════════════════════════
section "44. Dockerfile Convention"
for svc in services/*/; do
  name=$(basename "$svc")
  # ml-engine يجب أن يستخدم Dockerfile فقط (Python)
  if [ "$name" = "ml-engine" ]; then
    [ -f "$svc/Dockerfile" ] \
      && pass "ml-engine uses Dockerfile (Python) ✓" \
      || fail "ml-engine/Dockerfile MISSING"
    [ -f "$svc/Dockerfile.arm64" ] \
      && fail "ml-engine has Dockerfile.arm64 — WRONG (Python service must use Dockerfile only)" \
      || true
  else
    # Go services → Dockerfile.arm64
    if [ -f "$svc/go.mod" ]; then
      [ -f "$svc/Dockerfile.arm64" ] \
        && pass "Go service uses Dockerfile.arm64: $name ✓" \
        || fail "Go service missing Dockerfile.arm64: $name"
    fi
  fi
done

# ══════════════════════════════════════════════════════════════════
# 45. Rollout vs Deployment Convention
# لماذا: data-quality هو Python Deployment وليس Rollout — KEDA scalesObject يستهدفه
# ══════════════════════════════════════════════════════════════════
section "45. Rollout vs Deployment Convention"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  HAS_ROLLOUT=$(find "$base" -maxdepth 1 -name "rollout.yaml" 2>/dev/null | wc -l)
  HAS_DEPLOY=$(find "$base" -maxdepth 1 -name "deployment.yaml" 2>/dev/null | wc -l)

  if [ "$HAS_ROLLOUT" -gt 0 ] && [ "$HAS_DEPLOY" -gt 0 ]; then
    fail "Both rollout.yaml AND deployment.yaml exist: $name — pick one"
  elif [ "$HAS_ROLLOUT" -gt 0 ]; then
    pass "Uses Argo Rollout: $name"
  elif [ "$HAS_DEPLOY" -gt 0 ]; then
    pass "Uses Deployment: $name"
  else
    warn "No rollout.yaml or deployment.yaml: $name"
  fi
done

# ══════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════
set -e
section "Summary"
TOTAL=$((PASS+FAIL+WARN))
echo "| Status | Count |" >> "$REPORT"
echo "|--------|-------|" >> "$REPORT"
echo "| ✅ PASS  | $PASS  |" >> "$REPORT"
echo "| ❌ FAIL  | $FAIL  |" >> "$REPORT"
echo "| ⚠️  WARN  | $WARN  |" >> "$REPORT"
echo "| TOTAL  | $TOTAL |" >> "$REPORT"

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo "**RESULT: CLEAN ✅**" >> "$REPORT"
elif [ "$FAIL" -eq 0 ]; then
  echo "**RESULT: ACCEPTABLE ⚠️**" >> "$REPORT"
else
  echo "**RESULT: ACTION REQUIRED ❌**" >> "$REPORT"
fi

echo ""
echo "════════════════════════════════════════"
echo "PASS=$PASS | FAIL=$FAIL | WARN=$WARN | TOTAL=$TOTAL"
echo "Report saved: $REPORT"
echo "════════════════════════════════════════"
