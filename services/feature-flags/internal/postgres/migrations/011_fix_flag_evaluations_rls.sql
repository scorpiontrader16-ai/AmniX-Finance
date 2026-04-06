-- ============================================================
-- services/feature-flags/internal/postgres/migrations/011_fix_flag_evaluations_rls.sql
-- Scope: feature-flags service database only — independent migration sequence
--
-- Fix:
--   F-SQL25: flag_evaluations.tenant_id is nullable with no RLS —
--   any session can read evaluation logs for any tenant.
--
--   Root cause: 010_feature_flags.sql created flag_evaluations with
--   tenant_id TEXT (nullable) and no RLS policy. Without RLS, every
--   tenant session sees all flag evaluation rows across all tenants.
--
--   Fix:
--     1. Backfill existing NULL tenant_id rows to 'system' sentinel
--        (platform-level evaluations with no tenant context).
--     2. Enforce NOT NULL to prevent future null insertions.
--     3. Enable RLS with tenant isolation and super_admin bypass.
--     4. Add WITH CHECK so INSERT/UPDATE cannot write cross-tenant rows.
--
--   Note: flag_evaluations is a sampling log — rows with NULL tenant_id
--   were inserted by the platform evaluation path (no tenant session).
--   Backfilling to 'system' is the correct sentinel per platform convention
--   (established in 004_tenants.sql seed).
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- Step 1: Backfill NULL tenant_id rows to 'system' sentinel.
-- These are platform-level evaluations (no tenant context).
-- Must run before NOT NULL constraint is applied.
-- ════════════════════════════════════════════════════════════════════
UPDATE flag_evaluations
    SET tenant_id = 'system'
    WHERE tenant_id IS NULL;

-- ════════════════════════════════════════════════════════════════════
-- Step 2: Enforce NOT NULL — future inserts must provide tenant_id.
-- Set DEFAULT 'system' so platform paths without tenant context
-- continue to work without data loss (mirrors prediction_log pattern).
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE flag_evaluations
    ALTER COLUMN tenant_id SET NOT NULL,
    ALTER COLUMN tenant_id SET DEFAULT 'system';

-- ════════════════════════════════════════════════════════════════════
-- Step 3: Drop partial index (assumed nullable tenant_id) and replace
-- with full index now that column is NOT NULL.
-- ════════════════════════════════════════════════════════════════════
DROP INDEX IF EXISTS idx_flag_evaluations_tenant;

CREATE INDEX IF NOT EXISTS idx_flag_evaluations_tenant
    ON flag_evaluations (tenant_id, evaluated_at DESC);

-- ════════════════════════════════════════════════════════════════════
-- Step 4: Enable RLS and create tenant isolation policy.
-- System-level evaluations (tenant_id = 'system') are readable by
-- super_admin only — not by individual tenants.
-- WITH CHECK prevents cross-tenant writes on INSERT/UPDATE.
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE flag_evaluations ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_flag_evaluations ON flag_evaluations
    USING (
        tenant_id = current_setting('app.tenant_id', true)::text
        AND current_setting('app.tenant_id', true) != ''
    )
    WITH CHECK (
        tenant_id = current_setting('app.tenant_id', true)::text
        AND current_setting('app.tenant_id', true) != ''
    );

CREATE POLICY super_admin_all ON flag_evaluations
    USING (current_setting('app.user_role', true) = 'super_admin')
    WITH CHECK (current_setting('app.user_role', true) = 'super_admin');

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- ── Reverse Step 4: remove RLS ───────────────────────────────────────
DROP POLICY IF EXISTS super_admin_all                       ON flag_evaluations;
DROP POLICY IF EXISTS tenant_isolation_flag_evaluations     ON flag_evaluations;
ALTER TABLE flag_evaluations DISABLE ROW LEVEL SECURITY;

-- ── Reverse Step 3: restore partial index ────────────────────────────
DROP INDEX IF EXISTS idx_flag_evaluations_tenant;
CREATE INDEX IF NOT EXISTS idx_flag_evaluations_tenant
    ON flag_evaluations (tenant_id, evaluated_at DESC)
    WHERE tenant_id IS NOT NULL;

-- ── Reverse Step 2: remove NOT NULL and DEFAULT ──────────────────────
ALTER TABLE flag_evaluations
    ALTER COLUMN tenant_id DROP NOT NULL,
    ALTER COLUMN tenant_id DROP DEFAULT;

-- ── Reverse Step 1: restore NULL for backfilled system rows ──────────
UPDATE flag_evaluations
    SET tenant_id = NULL
    WHERE tenant_id = 'system';

-- +goose StatementEnd
