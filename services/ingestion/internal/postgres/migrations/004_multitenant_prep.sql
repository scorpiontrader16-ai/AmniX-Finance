-- ============================================================
-- 004_multitenant_prep.sql
-- Multi-Tenant Foundation — tenants table + RLS + safe constraints
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ── 1. جدول الـ Tenants (أساس M9) ─────────────────────────
CREATE TABLE IF NOT EXISTS tenants (
    id            TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    name          TEXT        NOT NULL,
    slug          TEXT        NOT NULL UNIQUE,
    status        TEXT        NOT NULL DEFAULT 'active',
    plan          TEXT        NOT NULL DEFAULT 'basic',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_tenant_status CHECK (status IN ('active', 'suspended', 'deleted')),
    CONSTRAINT chk_tenant_plan   CHECK (plan   IN ('basic', 'pro', 'business', 'enterprise')),
    CONSTRAINT chk_tenant_slug   CHECK (slug ~ '^[a-z0-9-]+$')
);

CREATE INDEX IF NOT EXISTS idx_tenants_slug   ON tenants (slug);
CREATE INDEX IF NOT EXISTS idx_tenants_status ON tenants (status);

-- ── 2. إزالة DEFAULT '' من tenant_id بشكل آمن ──────────────
-- يجبر الـ application على إرسال tenant_id دائماً
ALTER TABLE warm_events  ALTER COLUMN tenant_id DROP DEFAULT;
ALTER TABLE tiering_jobs ALTER COLUMN tenant_id DROP DEFAULT;

-- ── 3. Check constraints لمنع empty string ─────────────────
ALTER TABLE warm_events
    ADD CONSTRAINT chk_warm_events_tenant_id
    CHECK (tenant_id <> '');

ALTER TABLE tiering_jobs
    ADD CONSTRAINT chk_tiering_jobs_tenant_id
    CHECK (tenant_id <> '');

-- ── 4. Row Level Security ───────────────────────────────────
ALTER TABLE warm_events  ENABLE ROW LEVEL SECURITY;
ALTER TABLE tiering_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_warm_events
    ON warm_events
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

CREATE POLICY tenant_isolation_tiering_jobs
    ON tiering_jobs
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

-- ── 5. Multi-Tenant performance indexes ────────────────────
CREATE INDEX IF NOT EXISTS idx_warm_events_tenant_type
    ON warm_events (tenant_id, event_type, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_warm_events_tenant_archived
    ON warm_events (tenant_id, archived_at)
    WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_tiering_jobs_tenant_status
    ON tiering_jobs (tenant_id, status, created_at DESC);

-- ── 6. Parquet Files Index ──────────────────────────────────
CREATE TABLE IF NOT EXISTS parquet_files (
    id              BIGSERIAL    PRIMARY KEY,
    file_id         TEXT         NOT NULL UNIQUE DEFAULT gen_random_uuid()::TEXT,
    tenant_id       TEXT         NOT NULL CHECK (tenant_id <> ''),
    bucket          TEXT         NOT NULL,
    object_key      TEXT         NOT NULL,
    schema_version  TEXT         NOT NULL DEFAULT '1.0.0',
    row_count       BIGINT       NOT NULL DEFAULT 0,
    file_size_bytes BIGINT       NOT NULL DEFAULT 0,
    from_date       TIMESTAMPTZ  NOT NULL,
    to_date         TIMESTAMPTZ  NOT NULL,
    event_types     TEXT[]       NOT NULL DEFAULT '{}',
    status          TEXT         NOT NULL DEFAULT 'active',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_parquet_status     CHECK (status   IN ('active', 'archived', 'deleted')),
    CONSTRAINT chk_parquet_date_range CHECK (from_date < to_date)
);

CREATE INDEX IF NOT EXISTS idx_parquet_files_tenant_date
    ON parquet_files (tenant_id, from_date DESC);

CREATE INDEX IF NOT EXISTS idx_parquet_files_object_key
    ON parquet_files (bucket, object_key);

CREATE INDEX IF NOT EXISTS idx_parquet_files_status
    ON parquet_files (status, tenant_id);

ALTER TABLE parquet_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_parquet_files
    ON parquet_files
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

-- ── 7. updated_at trigger ───────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tenants_updated_at
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TRIGGER IF EXISTS trg_tenants_updated_at ON tenants;
DROP FUNCTION IF EXISTS update_updated_at();

DROP POLICY IF EXISTS tenant_isolation_parquet_files ON parquet_files;
DROP POLICY IF EXISTS tenant_isolation_tiering_jobs  ON tiering_jobs;
DROP POLICY IF EXISTS tenant_isolation_warm_events   ON warm_events;

DROP TABLE IF EXISTS parquet_files CASCADE;

ALTER TABLE warm_events  DISABLE ROW LEVEL SECURITY;
ALTER TABLE tiering_jobs DISABLE ROW LEVEL SECURITY;

ALTER TABLE warm_events
    DROP CONSTRAINT IF EXISTS chk_warm_events_tenant_id;
ALTER TABLE tiering_jobs
    DROP CONSTRAINT IF EXISTS chk_tiering_jobs_tenant_id;

ALTER TABLE warm_events  ALTER COLUMN tenant_id SET DEFAULT '';
ALTER TABLE tiering_jobs ALTER COLUMN tenant_id SET DEFAULT '';

DROP INDEX IF EXISTS idx_tiering_jobs_tenant_status;
DROP INDEX IF EXISTS idx_warm_events_tenant_archived;
DROP INDEX IF EXISTS idx_warm_events_tenant_type;
DROP INDEX IF EXISTS idx_tenants_status;
DROP INDEX IF EXISTS idx_tenants_slug;

DROP TABLE IF EXISTS tenants CASCADE;

-- +goose StatementEnd
