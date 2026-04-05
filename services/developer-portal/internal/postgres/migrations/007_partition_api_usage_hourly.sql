-- ============================================================
-- services/developer-portal/internal/postgres/migrations/007_partition_api_usage_hourly.sql
-- Scope: developer-portal service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL26 MEDIUM: api_usage_hourly without partitioning
--                   Hourly aggregated metrics table grows continuously.
--                   Without partitioning, old data cleanup and queries
--                   on recent data both require full table scans.
--                   Partition by RANGE (hour) with monthly partitions
--                   for efficient archival and query performance.
--
-- Strategy: RENAME → CREATE partitioned → INSERT → DROP
--           Safe on empty table (Codespace). In production with data,
--           requires maintenance window (tested here for future deploy).
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL26: Convert api_usage_hourly to partitioned table.
--          PostgreSQL cannot ALTER TABLE ... PARTITION BY on existing
--          table. Must use RENAME → CREATE → INSERT → DROP pattern.
-- ════════════════════════════════════════════════════════════════════

-- Step 1: Rename existing table (preserves data)
ALTER TABLE api_usage_hourly RENAME TO api_usage_hourly_old;

-- Step 2: Create new partitioned table with exact same structure
CREATE TABLE api_usage_hourly (
    id              BIGSERIAL    NOT NULL,
    api_key_id      TEXT         NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
    tenant_id       TEXT         NOT NULL,
    hour            TIMESTAMPTZ  NOT NULL,
    endpoint        TEXT         NOT NULL,
    total_calls     BIGINT       NOT NULL DEFAULT 0,
    success_calls   BIGINT       NOT NULL DEFAULT 0,
    error_calls     BIGINT       NOT NULL DEFAULT 0,
    avg_duration_ms INTEGER      NOT NULL DEFAULT 0,
    p99_duration_ms INTEGER      NOT NULL DEFAULT 0,
    total_bytes_in  BIGINT       NOT NULL DEFAULT 0,
    total_bytes_out BIGINT       NOT NULL DEFAULT 0,
    UNIQUE (api_key_id, hour, endpoint)
) PARTITION BY RANGE (hour);

-- Step 3: Create partitions (monthly for 2025-2027)
CREATE TABLE api_usage_hourly_2025_01 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE api_usage_hourly_2025_02 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE api_usage_hourly_2025_03 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE api_usage_hourly_2025_04 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
CREATE TABLE api_usage_hourly_2025_05 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
CREATE TABLE api_usage_hourly_2025_06 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE api_usage_hourly_2025_07 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE api_usage_hourly_2025_08 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE api_usage_hourly_2025_09 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE api_usage_hourly_2025_10 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE api_usage_hourly_2025_11 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE api_usage_hourly_2025_12 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

CREATE TABLE api_usage_hourly_2026_01 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE api_usage_hourly_2026_02 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE api_usage_hourly_2026_03 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE api_usage_hourly_2026_04 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE api_usage_hourly_2026_05 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE api_usage_hourly_2026_06 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE api_usage_hourly_2026_07 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE api_usage_hourly_2026_08 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE api_usage_hourly_2026_09 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE api_usage_hourly_2026_10 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE api_usage_hourly_2026_11 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE api_usage_hourly_2026_12 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

CREATE TABLE api_usage_hourly_2027_01 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
CREATE TABLE api_usage_hourly_2027_02 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-02-01') TO ('2027-03-01');
CREATE TABLE api_usage_hourly_2027_03 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-03-01') TO ('2027-04-01');
CREATE TABLE api_usage_hourly_2027_04 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-04-01') TO ('2027-05-01');
CREATE TABLE api_usage_hourly_2027_05 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-05-01') TO ('2027-06-01');
CREATE TABLE api_usage_hourly_2027_06 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-06-01') TO ('2027-07-01');
CREATE TABLE api_usage_hourly_2027_07 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-07-01') TO ('2027-08-01');
CREATE TABLE api_usage_hourly_2027_08 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-08-01') TO ('2027-09-01');
CREATE TABLE api_usage_hourly_2027_09 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-09-01') TO ('2027-10-01');
CREATE TABLE api_usage_hourly_2027_10 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-10-01') TO ('2027-11-01');
CREATE TABLE api_usage_hourly_2027_11 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-11-01') TO ('2027-12-01');
CREATE TABLE api_usage_hourly_2027_12 PARTITION OF api_usage_hourly
    FOR VALUES FROM ('2027-12-01') TO ('2028-01-01');

-- Default partition for future dates
CREATE TABLE api_usage_hourly_default PARTITION OF api_usage_hourly DEFAULT;

-- Step 4: Recreate indexes (automatically applied to all partitions)
CREATE INDEX idx_api_usage_hourly_key
    ON api_usage_hourly (api_key_id, hour DESC);
CREATE INDEX idx_api_usage_hourly_tenant
    ON api_usage_hourly (tenant_id, hour DESC);

-- Step 5: Migrate data from old table (if any exists)
INSERT INTO api_usage_hourly
    SELECT * FROM api_usage_hourly_old;

-- Step 6: Drop old table
DROP TABLE api_usage_hourly_old;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- Reverse: RENAME partitioned → CREATE non-partitioned → INSERT → DROP
ALTER TABLE api_usage_hourly RENAME TO api_usage_hourly_partitioned;

CREATE TABLE api_usage_hourly (
    id              BIGSERIAL   PRIMARY KEY,
    api_key_id      TEXT        NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
    tenant_id       TEXT        NOT NULL,
    hour            TIMESTAMPTZ NOT NULL,
    endpoint        TEXT        NOT NULL,
    total_calls     BIGINT      NOT NULL DEFAULT 0,
    success_calls   BIGINT      NOT NULL DEFAULT 0,
    error_calls     BIGINT      NOT NULL DEFAULT 0,
    avg_duration_ms INTEGER     NOT NULL DEFAULT 0,
    p99_duration_ms INTEGER     NOT NULL DEFAULT 0,
    total_bytes_in  BIGINT      NOT NULL DEFAULT 0,
    total_bytes_out BIGINT      NOT NULL DEFAULT 0,
    UNIQUE (api_key_id, hour, endpoint)
);

CREATE INDEX idx_api_usage_hourly_key ON api_usage_hourly (api_key_id, hour DESC);
CREATE INDEX idx_api_usage_hourly_tenant ON api_usage_hourly (tenant_id, hour DESC);

INSERT INTO api_usage_hourly SELECT * FROM api_usage_hourly_partitioned;
DROP TABLE api_usage_hourly_partitioned;

-- +goose StatementEnd
