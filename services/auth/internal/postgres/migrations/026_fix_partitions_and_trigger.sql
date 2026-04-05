-- ============================================================
-- services/auth/internal/postgres/migrations/026_fix_partitions_and_trigger.sql
-- Scope: auth service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL35 CRITICAL: sync_tenant_plan() writes to tenants.plan after
--                     023 renamed plan→tier — billing sync broken
--   F-SQL07 HIGH:     audit_log partitions end 2027 — crash after that
--   F-SQL13 MEDIUM:   audit_log indexes on parent only — not on partitions
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL35: sync_tenant_plan() references tenants.plan which was
--          renamed to tenants.tier in migration 023. Every subscription
--          status change silently fails the UPDATE, leaving tenants
--          on wrong tier. Fix: replace function to write tier column.
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION sync_tenant_plan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    -- tenants.plan was renamed to tenants.tier in migration 023.
    -- This function is intentionally named sync_tenant_plan to preserve
    -- the trigger name — renaming the trigger requires DROP + recreate
    -- which causes a brief window with no trigger. Function body updated.
    IF NEW.status = 'active' THEN
        UPDATE tenants
        SET tier = CASE NEW.plan_id
            WHEN 'plan_basic'      THEN 'basic'
            WHEN 'plan_pro'        THEN 'pro'
            WHEN 'plan_enterprise' THEN 'enterprise'
            ELSE 'basic'
        END
        WHERE id = NEW.tenant_id;
    END IF;
    RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- F-SQL07: audit_log partitions currently end at 2027-01-01.
--          Any audit record written after that date causes a
--          "no partition found" error and the entire transaction
--          fails — this means ALL operations that write audit logs
--          will crash in production after 2026-12-31.
--          Adding partitions through 2031 gives 5 years of runway.
-- ════════════════════════════════════════════════════════════════════

-- 2027
CREATE TABLE IF NOT EXISTS audit_log_2027_q1
    PARTITION OF audit_log
    FOR VALUES FROM ('2027-01-01') TO ('2027-04-01');

CREATE TABLE IF NOT EXISTS audit_log_2027_q2
    PARTITION OF audit_log
    FOR VALUES FROM ('2027-04-01') TO ('2027-07-01');

CREATE TABLE IF NOT EXISTS audit_log_2027_q3
    PARTITION OF audit_log
    FOR VALUES FROM ('2027-07-01') TO ('2027-10-01');

CREATE TABLE IF NOT EXISTS audit_log_2027_q4
    PARTITION OF audit_log
    FOR VALUES FROM ('2027-10-01') TO ('2028-01-01');

-- 2028
CREATE TABLE IF NOT EXISTS audit_log_2028_q1
    PARTITION OF audit_log
    FOR VALUES FROM ('2028-01-01') TO ('2028-04-01');

CREATE TABLE IF NOT EXISTS audit_log_2028_q2
    PARTITION OF audit_log
    FOR VALUES FROM ('2028-04-01') TO ('2028-07-01');

CREATE TABLE IF NOT EXISTS audit_log_2028_q3
    PARTITION OF audit_log
    FOR VALUES FROM ('2028-07-01') TO ('2028-10-01');

CREATE TABLE IF NOT EXISTS audit_log_2028_q4
    PARTITION OF audit_log
    FOR VALUES FROM ('2028-10-01') TO ('2029-01-01');

-- 2029
CREATE TABLE IF NOT EXISTS audit_log_2029_q1
    PARTITION OF audit_log
    FOR VALUES FROM ('2029-01-01') TO ('2029-04-01');

CREATE TABLE IF NOT EXISTS audit_log_2029_q2
    PARTITION OF audit_log
    FOR VALUES FROM ('2029-04-01') TO ('2029-07-01');

CREATE TABLE IF NOT EXISTS audit_log_2029_q3
    PARTITION OF audit_log
    FOR VALUES FROM ('2029-07-01') TO ('2029-10-01');

CREATE TABLE IF NOT EXISTS audit_log_2029_q4
    PARTITION OF audit_log
    FOR VALUES FROM ('2029-10-01') TO ('2030-01-01');

-- 2030
CREATE TABLE IF NOT EXISTS audit_log_2030_q1
    PARTITION OF audit_log
    FOR VALUES FROM ('2030-01-01') TO ('2030-04-01');

CREATE TABLE IF NOT EXISTS audit_log_2030_q2
    PARTITION OF audit_log
    FOR VALUES FROM ('2030-04-01') TO ('2030-07-01');

CREATE TABLE IF NOT EXISTS audit_log_2030_q3
    PARTITION OF audit_log
    FOR VALUES FROM ('2030-07-01') TO ('2030-10-01');

CREATE TABLE IF NOT EXISTS audit_log_2030_q4
    PARTITION OF audit_log
    FOR VALUES FROM ('2030-10-01') TO ('2031-01-01');

-- 2031
CREATE TABLE IF NOT EXISTS audit_log_2031_q1
    PARTITION OF audit_log
    FOR VALUES FROM ('2031-01-01') TO ('2031-04-01');

CREATE TABLE IF NOT EXISTS audit_log_2031_q2
    PARTITION OF audit_log
    FOR VALUES FROM ('2031-04-01') TO ('2031-07-01');

CREATE TABLE IF NOT EXISTS audit_log_2031_q3
    PARTITION OF audit_log
    FOR VALUES FROM ('2031-07-01') TO ('2031-10-01');

CREATE TABLE IF NOT EXISTS audit_log_2031_q4
    PARTITION OF audit_log
    FOR VALUES FROM ('2031-10-01') TO ('2032-01-01');

-- ════════════════════════════════════════════════════════════════════
-- F-SQL13: Indexes on partitioned tables in PostgreSQL are NOT
--          automatically inherited by partitions created after the
--          index was defined. Each partition needs its own index.
--          Without per-partition indexes, queries on individual
--          partitions do full sequential scans — critical for
--          audit_log which can contain millions of rows per quarter.
--          Apply indexes to all partitions (2025–2031).
-- ════════════════════════════════════════════════════════════════════

-- 2025 partitions (indexes on existing partitions)
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2025_q1
    ON audit_log_2025_q1 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2025_q2
    ON audit_log_2025_q2 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2025_q3
    ON audit_log_2025_q3 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2025_q4
    ON audit_log_2025_q4 (tenant_id, created_at DESC);

-- 2026 partitions
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2026_q1
    ON audit_log_2026_q1 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2026_q2
    ON audit_log_2026_q2 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2026_q3
    ON audit_log_2026_q3 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2026_q4
    ON audit_log_2026_q4 (tenant_id, created_at DESC);

-- 2027 partitions (just created above)
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2027_q1
    ON audit_log_2027_q1 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2027_q2
    ON audit_log_2027_q2 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2027_q3
    ON audit_log_2027_q3 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2027_q4
    ON audit_log_2027_q4 (tenant_id, created_at DESC);

-- 2028 partitions
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2028_q1
    ON audit_log_2028_q1 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2028_q2
    ON audit_log_2028_q2 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2028_q3
    ON audit_log_2028_q3 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2028_q4
    ON audit_log_2028_q4 (tenant_id, created_at DESC);

-- 2029 partitions
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2029_q1
    ON audit_log_2029_q1 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2029_q2
    ON audit_log_2029_q2 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2029_q3
    ON audit_log_2029_q3 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2029_q4
    ON audit_log_2029_q4 (tenant_id, created_at DESC);

-- 2030 partitions
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2030_q1
    ON audit_log_2030_q1 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2030_q2
    ON audit_log_2030_q2 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2030_q3
    ON audit_log_2030_q3 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2030_q4
    ON audit_log_2030_q4 (tenant_id, created_at DESC);

-- 2031 partitions
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2031_q1
    ON audit_log_2031_q1 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2031_q2
    ON audit_log_2031_q2 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2031_q3
    ON audit_log_2031_q3 (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created_2031_q4
    ON audit_log_2031_q4 (tenant_id, created_at DESC);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- ── Reverse F-SQL13 — drop partition indexes (2027-2031 only, 2025-2026 existed before) ──
DROP INDEX IF EXISTS idx_audit_tenant_created_2031_q4;
DROP INDEX IF EXISTS idx_audit_tenant_created_2031_q3;
DROP INDEX IF EXISTS idx_audit_tenant_created_2031_q2;
DROP INDEX IF EXISTS idx_audit_tenant_created_2031_q1;
DROP INDEX IF EXISTS idx_audit_tenant_created_2030_q4;
DROP INDEX IF EXISTS idx_audit_tenant_created_2030_q3;
DROP INDEX IF EXISTS idx_audit_tenant_created_2030_q2;
DROP INDEX IF EXISTS idx_audit_tenant_created_2030_q1;
DROP INDEX IF EXISTS idx_audit_tenant_created_2029_q4;
DROP INDEX IF EXISTS idx_audit_tenant_created_2029_q3;
DROP INDEX IF EXISTS idx_audit_tenant_created_2029_q2;
DROP INDEX IF EXISTS idx_audit_tenant_created_2029_q1;
DROP INDEX IF EXISTS idx_audit_tenant_created_2028_q4;
DROP INDEX IF EXISTS idx_audit_tenant_created_2028_q3;
DROP INDEX IF EXISTS idx_audit_tenant_created_2028_q2;
DROP INDEX IF EXISTS idx_audit_tenant_created_2028_q1;
DROP INDEX IF EXISTS idx_audit_tenant_created_2027_q4;
DROP INDEX IF EXISTS idx_audit_tenant_created_2027_q3;
DROP INDEX IF EXISTS idx_audit_tenant_created_2027_q2;
DROP INDEX IF EXISTS idx_audit_tenant_created_2027_q1;
DROP INDEX IF EXISTS idx_audit_tenant_created_2026_q4;
DROP INDEX IF EXISTS idx_audit_tenant_created_2026_q3;
DROP INDEX IF EXISTS idx_audit_tenant_created_2026_q2;
DROP INDEX IF EXISTS idx_audit_tenant_created_2026_q1;
DROP INDEX IF EXISTS idx_audit_tenant_created_2025_q4;
DROP INDEX IF EXISTS idx_audit_tenant_created_2025_q3;
DROP INDEX IF EXISTS idx_audit_tenant_created_2025_q2;
DROP INDEX IF EXISTS idx_audit_tenant_created_2025_q1;

-- ── Reverse F-SQL07 — drop 2027-2031 partitions ──────────────────────
DROP TABLE IF EXISTS audit_log_2031_q4;
DROP TABLE IF EXISTS audit_log_2031_q3;
DROP TABLE IF EXISTS audit_log_2031_q2;
DROP TABLE IF EXISTS audit_log_2031_q1;
DROP TABLE IF EXISTS audit_log_2030_q4;
DROP TABLE IF EXISTS audit_log_2030_q3;
DROP TABLE IF EXISTS audit_log_2030_q2;
DROP TABLE IF EXISTS audit_log_2030_q1;
DROP TABLE IF EXISTS audit_log_2029_q4;
DROP TABLE IF EXISTS audit_log_2029_q3;
DROP TABLE IF EXISTS audit_log_2029_q2;
DROP TABLE IF EXISTS audit_log_2029_q1;
DROP TABLE IF EXISTS audit_log_2028_q4;
DROP TABLE IF EXISTS audit_log_2028_q3;
DROP TABLE IF EXISTS audit_log_2028_q2;
DROP TABLE IF EXISTS audit_log_2028_q1;
DROP TABLE IF EXISTS audit_log_2027_q4;
DROP TABLE IF EXISTS audit_log_2027_q3;
DROP TABLE IF EXISTS audit_log_2027_q2;
DROP TABLE IF EXISTS audit_log_2027_q1;

-- ── Reverse F-SQL35 — restore broken function (plan column) ──────────
CREATE OR REPLACE FUNCTION sync_tenant_plan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'active' THEN
        UPDATE tenants
        SET plan = CASE NEW.plan_id
            WHEN 'plan_basic'      THEN 'basic'
            WHEN 'plan_pro'        THEN 'pro'
            WHEN 'plan_enterprise' THEN 'enterprise'
            ELSE 'basic'
        END
        WHERE id = NEW.tenant_id;
    END IF;
    RETURN NEW;
END;
$$;

-- +goose StatementEnd
