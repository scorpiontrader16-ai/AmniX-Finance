-- ============================================================
-- services/auth/internal/postgres/migrations/025_add_missing_columns.sql
-- Scope: auth service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL08: api_keys missing revoked_at column — cannot revoke keys safely
--   F-SQL10: usage_records missing UNIQUE constraint — duplicate billing records
--   F-SQL16: ml_models missing tenant_id — all tenants see all models
--   F-SQL17: feature_values missing tenant_id — cross-tenant ML feature leak
--   F-SQL18: prediction_log.tenant_id nullable — cross-tenant prediction data
--   F-SQL23: model_deployments missing tenant_id — cross-tenant deployment leak
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL08: api_keys.revoked_at missing — without this column there is
--          no way to revoke a key without deleting it, losing audit
--          trail. NULL means active; non-NULL means revoked at that time.
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE api_keys
    ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ DEFAULT NULL;

-- Index to efficiently query active (non-revoked) keys
CREATE INDEX IF NOT EXISTS idx_api_keys_active
    ON api_keys (tenant_id, user_id)
    WHERE revoked_at IS NULL;

-- ════════════════════════════════════════════════════════════════════
-- F-SQL10: usage_records missing UNIQUE constraint — without it,
--          idempotent billing upserts are impossible and the same
--          usage period can be inserted multiple times, causing
--          duplicate invoices. Stripe webhook retries make this
--          a near-certainty in production.
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE usage_records
    ADD CONSTRAINT uq_usage_records_billing
    UNIQUE (tenant_id, subscription_id, metric, period_start, period_end);

-- ════════════════════════════════════════════════════════════════════
-- F-SQL16: ml_models.tenant_id missing — platform-wide ML models are
--          shared (tenant_id = 'system') but tenant-specific fine-tuned
--          models are completely exposed across tenants without this.
--          tenants.id is TEXT (not UUID) — must match exactly.
--          Backfill existing rows as 'system' (platform-wide models).
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE ml_models
    ADD COLUMN IF NOT EXISTS tenant_id TEXT
        REFERENCES tenants(id) ON DELETE CASCADE;

-- Backfill: existing models are platform-wide (seeded in 012)
UPDATE ml_models SET tenant_id = 'system' WHERE tenant_id IS NULL;

-- Now enforce NOT NULL
ALTER TABLE ml_models
    ALTER COLUMN tenant_id SET NOT NULL;

-- Enable RLS on ml_models — tenant sees own + system models
ALTER TABLE ml_models ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_ml_models ON ml_models
    USING (
        tenant_id = 'system'
        OR (
            tenant_id = current_setting('app.tenant_id', true)::text
            AND current_setting('app.tenant_id', true) != ''
        )
    );

CREATE POLICY super_admin_all ON ml_models
    USING (current_setting('app.user_role', true) = 'super_admin');

-- Index: tenant-scoped model lookup
CREATE INDEX IF NOT EXISTS idx_ml_models_tenant
    ON ml_models (tenant_id, type, status);

-- ════════════════════════════════════════════════════════════════════
-- F-SQL17: feature_values.tenant_id missing — ML features are keyed
--          by (entity_id, feature_id). entity_id is typically a
--          user_id or symbol — without tenant_id, tenant A can read
--          tenant B's feature vectors.
--          PK must be rebuilt to include tenant_id.
--          Existing rows backfilled as 'system'.
-- ════════════════════════════════════════════════════════════════════

-- Drop existing PK before adding tenant_id (cannot alter PK in place)
ALTER TABLE feature_values DROP CONSTRAINT IF EXISTS feature_values_pkey;

ALTER TABLE feature_values
    ADD COLUMN IF NOT EXISTS tenant_id TEXT NOT NULL DEFAULT 'system';

-- Rebuild PK to include tenant_id — prevents cross-tenant key collision
ALTER TABLE feature_values
    ADD CONSTRAINT feature_values_pkey
    PRIMARY KEY (tenant_id, entity_id, feature_id);

-- Remove the DEFAULT after backfill — future inserts must set tenant_id
ALTER TABLE feature_values
    ALTER COLUMN tenant_id DROP DEFAULT;

ALTER TABLE feature_values ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_feature_values ON feature_values
    USING (
        tenant_id = 'system'
        OR (
            tenant_id = current_setting('app.tenant_id', true)::text
            AND current_setting('app.tenant_id', true) != ''
        )
    );

CREATE POLICY super_admin_all ON feature_values
    USING (current_setting('app.user_role', true) = 'super_admin');

CREATE INDEX IF NOT EXISTS idx_feature_values_tenant
    ON feature_values (tenant_id, entity_id, computed_at DESC);

-- ════════════════════════════════════════════════════════════════════
-- F-SQL18: prediction_log.tenant_id is nullable — any row with NULL
--          tenant_id is invisible to tenant queries but readable by
--          service accounts, creating a data consistency gap.
--          prediction_log is a partitioned table — ALTER COLUMN SET
--          NOT NULL applies to parent and propagates to all partitions.
--          Backfill NULLs to 'system' sentinel before enforcing.
-- ════════════════════════════════════════════════════════════════════

-- Backfill all existing NULL tenant_ids across all partitions
UPDATE prediction_log
    SET tenant_id = 'system'
    WHERE tenant_id IS NULL;

ALTER TABLE prediction_log
    ALTER COLUMN tenant_id SET NOT NULL,
    ALTER COLUMN tenant_id SET DEFAULT '';

-- Drop partial index that assumed nullable tenant_id
DROP INDEX IF EXISTS idx_prediction_log_tenant;

-- Full index now that column is NOT NULL
CREATE INDEX IF NOT EXISTS idx_prediction_log_tenant
    ON prediction_log (tenant_id, created_at DESC);

-- Enable RLS on partitioned table — applies to all partitions
ALTER TABLE prediction_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_prediction_log ON prediction_log
    USING (
        tenant_id = 'system'
        OR (
            tenant_id = current_setting('app.tenant_id', true)::text
            AND current_setting('app.tenant_id', true) != ''
        )
    );

CREATE POLICY super_admin_all ON prediction_log
    USING (current_setting('app.user_role', true) = 'super_admin');

-- ════════════════════════════════════════════════════════════════════
-- F-SQL23: model_deployments missing tenant_id — deployments are
--          children of ml_models but a tenant querying deployments
--          bypasses the ml_models RLS unless deployments also carry
--          tenant_id directly. Backfill from parent ml_models.
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE model_deployments
    ADD COLUMN IF NOT EXISTS tenant_id TEXT
        REFERENCES tenants(id) ON DELETE CASCADE;

-- Backfill from parent ml_models.tenant_id
UPDATE model_deployments md
    SET tenant_id = m.tenant_id
    FROM ml_models m
    WHERE md.model_id = m.id;

-- Enforce NOT NULL after backfill
ALTER TABLE model_deployments
    ALTER COLUMN tenant_id SET NOT NULL;

ALTER TABLE model_deployments ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_model_deployments ON model_deployments
    USING (
        tenant_id = 'system'
        OR (
            tenant_id = current_setting('app.tenant_id', true)::text
            AND current_setting('app.tenant_id', true) != ''
        )
    );

CREATE POLICY super_admin_all ON model_deployments
    USING (current_setting('app.user_role', true) = 'super_admin');

CREATE INDEX IF NOT EXISTS idx_model_deployments_tenant
    ON model_deployments (tenant_id, environment, status);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- ── Reverse F-SQL23 ──────────────────────────────────────────────────
DROP POLICY IF EXISTS super_admin_all ON model_deployments;
DROP POLICY IF EXISTS tenant_isolation_model_deployments ON model_deployments;
ALTER TABLE model_deployments DISABLE ROW LEVEL SECURITY;
DROP INDEX IF EXISTS idx_model_deployments_tenant;
ALTER TABLE model_deployments DROP COLUMN IF EXISTS tenant_id;

-- ── Reverse F-SQL18 ──────────────────────────────────────────────────
DROP POLICY IF EXISTS super_admin_all ON prediction_log;
DROP POLICY IF EXISTS tenant_isolation_prediction_log ON prediction_log;
ALTER TABLE prediction_log DISABLE ROW LEVEL SECURITY;
DROP INDEX IF EXISTS idx_prediction_log_tenant;
CREATE INDEX IF NOT EXISTS idx_prediction_log_tenant
    ON prediction_log (tenant_id, created_at DESC)
    WHERE tenant_id IS NOT NULL;
ALTER TABLE prediction_log ALTER COLUMN tenant_id DROP NOT NULL;
ALTER TABLE prediction_log ALTER COLUMN tenant_id DROP DEFAULT;
UPDATE prediction_log SET tenant_id = NULL WHERE tenant_id = 'system';

-- ── Reverse F-SQL17 ──────────────────────────────────────────────────
DROP POLICY IF EXISTS super_admin_all ON feature_values;
DROP POLICY IF EXISTS tenant_isolation_feature_values ON feature_values;
ALTER TABLE feature_values DISABLE ROW LEVEL SECURITY;
DROP INDEX IF EXISTS idx_feature_values_tenant;
ALTER TABLE feature_values DROP CONSTRAINT IF EXISTS feature_values_pkey;
ALTER TABLE feature_values DROP COLUMN IF EXISTS tenant_id;
ALTER TABLE feature_values
    ADD CONSTRAINT feature_values_pkey PRIMARY KEY (entity_id, feature_id);

-- ── Reverse F-SQL16 ──────────────────────────────────────────────────
DROP POLICY IF EXISTS super_admin_all ON ml_models;
DROP POLICY IF EXISTS tenant_isolation_ml_models ON ml_models;
ALTER TABLE ml_models DISABLE ROW LEVEL SECURITY;
DROP INDEX IF EXISTS idx_ml_models_tenant;
ALTER TABLE ml_models DROP COLUMN IF EXISTS tenant_id;

-- ── Reverse F-SQL10 ──────────────────────────────────────────────────
ALTER TABLE usage_records
    DROP CONSTRAINT IF EXISTS uq_usage_records_billing;

-- ── Reverse F-SQL08 ──────────────────────────────────────────────────
DROP INDEX IF EXISTS idx_api_keys_active;
ALTER TABLE api_keys DROP COLUMN IF EXISTS revoked_at;

-- +goose StatementEnd
