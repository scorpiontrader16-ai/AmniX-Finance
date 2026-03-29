#!/usr/bin/env bash
set -euo pipefail

REPORT="audit-report.md"
PASS=0; FAIL=0; WARN=0

section() { echo ""; echo "## $1" | tee -a "$REPORT"; echo ""; }
pass()    { echo "- [x] $1" | tee -a "$REPORT"; PASS=$((PASS+1)); }
fail()    { echo "- [ ] FAIL $1" | tee -a "$REPORT"; FAIL=$((FAIL+1)); }
warn()    { echo "- [~] WARN $1" | tee -a "$REPORT"; WARN=$((WARN+1)); }

rm -f "$REPORT"
echo "# Youtuop Audit Report" >> "$REPORT"
echo "Generated: $(date -u)" >> "$REPORT"
echo "Commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)" >> "$REPORT"
echo "---" >> "$REPORT"

section "1. Repository Structure"
find . -mindepth 1 -maxdepth 3 \
  -not -path "./.git/*" \
  -not -path "./vendor/*" \
  -not -path "./target/*" \
  -not -path "./.terraform/*" \
  | sort >> "$REPORT"

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
else warn "Same filename exists in multiple paths"; echo "$SAME" >> "$REPORT"; fi

section "3. Go Services"
# Only check services/* directories — skip root go.mod and tests/
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

section "5. Proto Generated Files"
# Only check root proto/ directory — not internal service protos
find proto -name "*.proto" 2>/dev/null | sort | while read -r proto; do
  BASE=$(basename "$proto" .proto)
  PB=$(find gen -name "${BASE}.pb.go" 2>/dev/null)
  if [ -z "$PB" ]; then fail "Missing gen/${BASE}.pb.go"; else pass "${BASE}.pb.go exists"; fi
  if grep -q "^service " "$proto" 2>/dev/null; then
    GRPC=$(find gen -name "${BASE}_grpc.pb.go" 2>/dev/null)
    if [ -z "$GRPC" ]; then fail "Missing gen/${BASE}_grpc.pb.go"; else pass "${BASE}_grpc.pb.go exists"; fi
  fi
done

section "6. Kubernetes Manifests"
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
      -skip BackendLBPolicy,BackendTLSPolicy \
      -skip Kustomization,HelmRepository,GitRepository \
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
        fail "App '$NAME' path '$PVAL' NOT FOUND"
      fi
    fi
  done
else
  warn "yq not installed — skipping ArgoCD path check"
fi

section "9. Empty Directories"
EMPTY=$(find . -not -path "./.git/*" -not -path "./vendor/*" -type d -empty 2>/dev/null | sort)
if [ -z "$EMPTY" ]; then pass "No empty directories"
else warn "Empty directories:"; echo "$EMPTY" >> "$REPORT"
fi

section "10. Large Files over 1MB (untracked or tracked)"
# Only flag files that are actually tracked by git
LARGE=$(git ls-files | xargs -I{} find {} -size +1M 2>/dev/null | sort)
if [ -z "$LARGE" ]; then pass "No large files tracked in git"
else fail "Large files tracked in git:"; echo "$LARGE" >> "$REPORT"; fi


set +e  # الـ sections 11-19 تستخدم || true — نوقف exit-on-error
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

section "12. Overlays Completeness"
for svc in services/*/; do
  name=$(basename "$svc")
  staging="k8s/overlays/staging/$name/kustomization.yaml"
  production="k8s/overlays/production/$name/kustomization.yaml"
  [ -f "$staging" ]    || fail "Missing overlay staging: $name"
  [ -f "$production" ] || fail "Missing overlay production: $name"
  [ -f "$staging" ] && [ -f "$production" ] && pass "Overlays OK: $name"
done

section "13. Service Completeness — ESO / PDB / HPA"
for svc in services/*/; do
  name=$(basename "$svc")
  base="k8s/base/$name"
  [ -d "$base" ] || continue
  eso=$(find "$base" -maxdepth 1 -name "externalsecret*.yaml" 2>/dev/null | wc -l)
  pdb=$(find "$base" -maxdepth 1 -name "pdb*.yaml" -o -name "poddisruptionbudget*.yaml" 2>/dev/null | wc -l)
  hpa=$(find "$base" -maxdepth 1 -name "hpa*.yaml" -o -name "scaledobject*.yaml" 2>/dev/null | wc -l)
  [ "$eso" -eq 0 ] && fail "Missing ExternalSecret: $name"
  [ "$pdb" -eq 0 ] && fail "Missing PodDisruptionBudget: $name"
  [ "$hpa" -eq 0 ] && fail "Missing HPA/ScaledObject: $name"
  [ "$eso" -gt 0 ] && [ "$pdb" -gt 0 ] && [ "$hpa" -gt 0 ] && pass "ESO+PDB+HPA OK: $name"
done

section "14. ArgoCD Applications"
ARGOCD_APPS=$(find k8s/ infra/ -name "*.yaml" 2>/dev/null \
  | xargs grep -l "kind: Application" 2>/dev/null | wc -l)
ARGOCD_APPSETS=$(find k8s/ infra/ -name "*.yaml" 2>/dev/null \
  | xargs grep -l "kind: ApplicationSet" 2>/dev/null | wc -l)
if [ "$ARGOCD_APPS" -gt 0 ] || [ "$ARGOCD_APPSETS" -gt 0 ]; then
  pass "ArgoCD Applications found: apps=$ARGOCD_APPS appsets=$ARGOCD_APPSETS"
else
  fail "No ArgoCD Application or ApplicationSet found — cluster will not sync"
fi

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

set -e
section "Summary"
TOTAL=$((PASS+FAIL+WARN))
echo "| Status | Count |" >> "$REPORT"
echo "|--------|-------|" >> "$REPORT"
echo "| PASS   | $PASS |" >> "$REPORT"
echo "| FAIL   | $FAIL |" >> "$REPORT"
echo "| WARN   | $WARN |" >> "$REPORT"
echo "| TOTAL  | $TOTAL |" >> "$REPORT"

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then echo "RESULT: CLEAN" >> "$REPORT"
elif [ "$FAIL" -eq 0 ]; then echo "RESULT: ACCEPTABLE" >> "$REPORT"
else echo "RESULT: ACTION REQUIRED" >> "$REPORT"
fi

echo ""
echo "============================="
echo "PASS=$PASS | FAIL=$FAIL | WARN=$WARN"
echo "Report saved: $REPORT"
echo "============================="
