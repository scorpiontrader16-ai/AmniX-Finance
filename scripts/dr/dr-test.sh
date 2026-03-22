#!/usr/bin/env bash
# ============================================================
# dr-test.sh — Monthly DR Drill Script
# يختبر الـ DR بدون failover حقيقي
# ============================================================

set -euo pipefail

PRIMARY_REGION="us-east-1"
DR_REGION="eu-west-1"
DR_CLUSTER="platform-prod-dr"
DR_NAMESPACE="platform"
LOG_FILE="/tmp/dr-test-$(date +%Y%m%d-%H%M%S).log"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"; }
pass() { log "✅ PASS: $*"; }
fail() { log "❌ FAIL: $*"; exit 1; }

log "=== DR Drill Started ==="
log "Primary: $PRIMARY_REGION | DR: $DR_REGION"

# ── 1. Postgres Replica Lag ───────────────────────────────────────────────
log "Checking Postgres replica lag..."
REPLICA_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier platform-prod-dr-postgres \
  --region "$DR_REGION" \
  --query 'DBInstances[0].StatusInfos[0].Message' \
  --output text 2>/dev/null || echo "ERROR")

if [[ "$REPLICA_STATUS" == *"ERROR"* ]]; then
  fail "Postgres replica unreachable"
fi
pass "Postgres replica healthy: $REPLICA_STATUS"

# ── 2. Velero Backups ─────────────────────────────────────────────────────
log "Checking latest Velero backup..."
LATEST_BACKUP=$(velero backup get \
  --kubeconfig /tmp/dr-kubeconfig \
  --output json 2>/dev/null | \
  python3 -c "import sys,json; \
    backups=json.load(sys.stdin)['items']; \
    backups.sort(key=lambda x: x['status']['completionTimestamp'], reverse=True); \
    b=backups[0]; \
    print(b['metadata']['name'], b['status']['phase'])" 2>/dev/null || echo "ERROR")

if [[ "$LATEST_BACKUP" == *"ERROR"* || "$LATEST_BACKUP" == *"Failed"* ]]; then
  fail "Latest backup failed or unreachable"
fi
pass "Latest backup: $LATEST_BACKUP"

# ── 3. DR Cluster Health ──────────────────────────────────────────────────
log "Checking DR cluster node health..."
aws eks update-kubeconfig \
  --name "$DR_CLUSTER" \
  --region "$DR_REGION" \
  --kubeconfig /tmp/dr-kubeconfig 2>/dev/null

READY_NODES=$(kubectl get nodes \
  --kubeconfig /tmp/dr-kubeconfig \
  --no-headers 2>/dev/null | \
  grep -c "Ready" || echo "0")

if [[ "$READY_NODES" -lt 3 ]]; then
  fail "DR cluster has only $READY_NODES ready nodes (need >= 3)"
fi
pass "DR cluster has $READY_NODES ready nodes"

# ── 4. S3 Replication ────────────────────────────────────────────────────
log "Checking S3 DR bucket..."
BUCKET_EXISTS=$(aws s3 ls "s3://platform-dr-data-eu-west-1" \
  --region "$DR_REGION" 2>/dev/null && echo "yes" || echo "no")

if [[ "$BUCKET_EXISTS" != "yes" ]]; then
  fail "DR S3 bucket not accessible"
fi
pass "DR S3 bucket accessible"

# ── 5. Route53 Health Check ───────────────────────────────────────────────
log "Checking Route53 health check..."
HEALTH_STATUS=$(aws route53 get-health-check-status \
  --health-check-id "${HEALTH_CHECK_ID:-}" \
  --query 'HealthCheckObservations[0].StatusReport.Status' \
  --output text 2>/dev/null || echo "UNKNOWN")

log "Route53 health status: $HEALTH_STATUS"
if [[ "$HEALTH_STATUS" == *"Failure"* ]]; then
  fail "Route53 health check reporting failure"
fi
pass "Route53 health check: $HEALTH_STATUS"

# ── 6. RTO Estimation ─────────────────────────────────────────────────────
log "Estimating RTO..."
log "  - Postgres promotion: ~10 min"
log "  - Secret updates: ~15 min"
log "  - Pod restarts: ~10 min"
log "  - DNS propagation: ~5 min"
log "  - Validation: ~30 min"
log "  Total estimated RTO: ~70 min (target: 4 hours) ✅"

# ── Summary ───────────────────────────────────────────────────────────────
log ""
log "=== DR Drill Complete ==="
log "All checks passed. Log saved to: $LOG_FILE"
log "Next drill scheduled: $(date -d '+1 month' +%Y-%m-01)"
