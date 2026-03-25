#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  scripts/rollback-tenant-migration.sh                           ║
# ║  Multi-Tenant Rollback — Enterprise Grade                       ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail
IFS=$'\n\t'

# ── Configuration ────────────────────────────────────────────────────
DB_HOST="${DB_HOST:-postgres.platform.svc.cluster.local}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-platform_admin}"
DB_NAME="${DB_NAME:-platform}"
DB_SSLMODE="${DB_SSLMODE:-require}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-services/auth/internal/postgres/migrations}"
PERFORMED_BY="${PERFORMED_BY:-rollback-script}"
STEPS="${STEPS:-1}"

# ── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2; }

# ── Usage ────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 <tenant_slug> [--steps=N] [--performed-by=<actor>] [--confirm]"
  echo ""
  echo "  <tenant_slug>          Required — tenant to roll back"
  echo "  --steps=N              Number of migrations to roll back (default: 1)"
  echo "  --performed-by=<actor> Who is running the rollback (for audit log)"
  echo "  --confirm              Skip confirmation prompt"
  exit 1
}

# ── Argument Parsing ─────────────────────────────────────────────────
TENANT_SLUG=""
CONFIRM=false

for arg in "$@"; do
  case $arg in
    --steps=*)        STEPS="${arg#*=}" ;;
    --performed-by=*) PERFORMED_BY="${arg#*=}" ;;
    --confirm)        CONFIRM=true ;;
    --help|-h)        usage ;;
    -*)               log_warn "Unknown flag: $arg" ;;
    *)
      if [[ -z "$TENANT_SLUG" ]]; then
        TENANT_SLUG="$arg"
      else
        log_error "Unexpected argument: $arg"
        usage
      fi
      ;;
  esac
done

if [[ -z "$TENANT_SLUG" ]]; then
  log_error "tenant_slug is required"
  usage
fi

# ── psql Helper ──────────────────────────────────────────────────────
run_psql() {
  PGPASSWORD="${PGPASSWORD:-}" psql \
    -h "$DB_HOST" -p "$DB_PORT" \
    -U "$DB_USER" -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 \
    --no-password \
    "$@"
}

# ── Audit Log ────────────────────────────────────────────────────────
audit_log() {
  local tenant_id="$1"
  local action="$2"
  local details="${3:-{}}"

  run_psql -c "
    INSERT INTO tenant_audit_log (tenant_id, action, performed_by, details, performed_at)
    VALUES (
      '${tenant_id}',
      '${action}',
      '${PERFORMED_BY}',
      '${details}'::jsonb,
      NOW()
    );
  " &>/dev/null || log_warn "Could not write audit log for tenant ${tenant_id}"
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
  local schema="tenant_${TENANT_SLUG//-/_}"
  local dsn="host=${DB_HOST} port=${DB_PORT} user=${DB_USER} dbname=${DB_NAME} sslmode=${DB_SSLMODE} search_path=${schema}"

  log_info "═══════════════════════════════════════════"
  log_info "  Tenant Rollback"
  log_info "  Tenant: ${TENANT_SLUG}"
  log_info "  Schema: ${schema}"
  log_info "  Steps:  ${STEPS}"
  log_info "  Actor:  ${PERFORMED_BY}"
  log_info "═══════════════════════════════════════════"

  # Preflight
  if ! command -v goose &>/dev/null; then
    log_error "goose not found"
    exit 1
  fi

  if ! run_psql -c "SELECT 1" &>/dev/null; then
    log_error "Cannot connect to database"
    exit 1
  fi

  # Verify tenant exists
  local tenant_id
  tenant_id=$(run_psql -t -A -c \
    "SELECT id FROM tenants WHERE slug='${TENANT_SLUG}';" \
    | tr -d ' \n' || true)

  if [[ -z "$tenant_id" ]]; then
    log_error "Tenant '${TENANT_SLUG}' not found in database"
    exit 1
  fi

  # Verify schema exists
  local schema_exists
  schema_exists=$(run_psql -t -c \
    "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${schema}';" \
    | tr -d ' \n')

  if [[ "$schema_exists" == "0" ]]; then
    log_error "Schema '${schema}' does not exist"
    exit 1
  fi

  # Show current migration status
  log_info "Current migration status:"
  goose -dir="$MIGRATIONS_DIR" postgres "$dsn" status 2>/dev/null || true

  # Confirmation prompt
  if [[ "$CONFIRM" != "true" ]]; then
    log_warn "⚠️  This will roll back ${STEPS} migration(s) for tenant: ${TENANT_SLUG}"
    log_warn "⚠️  This operation may cause DATA LOSS"
    read -r -p "Type 'yes' to confirm: " confirmation
    if [[ "$confirmation" != "yes" ]]; then
      log_info "Rollback cancelled"
      exit 0
    fi
  fi

  # Execute rollback
  log_info "Rolling back ${STEPS} step(s) for schema: ${schema}"

  if goose -dir="$MIGRATIONS_DIR" postgres "$dsn" down-to 0 2>&1; then
    # goose down rolls back 1 step — use down for STEPS times
    :
  fi

  local i=0
  local rollback_success=true
  while [[ $i -lt $STEPS ]]; do
    i=$((i + 1))
    log_info "  Rollback step ${i}/${STEPS}..."
    if ! goose -dir="$MIGRATIONS_DIR" postgres "$dsn" down 2>&1; then
      log_error "  Rollback failed at step ${i}"
      rollback_success=false
      break
    fi
  done

  if [[ "$rollback_success" == "true" ]]; then
    log_success "Rollback completed: ${TENANT_SLUG} (${STEPS} step(s))"
    audit_log "$tenant_id" "migration_rollback_success" \
      "{\"schema\":\"${schema}\",\"steps\":${STEPS},\"performed_by\":\"${PERFORMED_BY}\"}"
  else
    log_error "Rollback FAILED: ${TENANT_SLUG}"
    audit_log "$tenant_id" "migration_rollback_failed" \
      "{\"schema\":\"${schema}\",\"steps_requested\":${STEPS}}"
    exit 1
  fi

  # Show status after rollback
  log_info "Migration status after rollback:"
  goose -dir="$MIGRATIONS_DIR" postgres "$dsn" status 2>/dev/null || true
}

main "$@"
