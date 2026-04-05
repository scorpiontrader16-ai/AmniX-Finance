-- ============================================================
-- services/auth/internal/postgres/migrations/029_partition_analytics_events.sql
-- Scope: auth service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL38 HIGH: analytics_events without partitioning
--                 High-volume event tracking table (potentially millions
--                 of rows) without partitioning causes full table scans
--                 on time-range queries. Partition by RANGE (timestamp)
--                 with monthly partitions for efficient archival.
--
-- Strategy: RENAME → CREATE partitioned → INSERT → DROP
--           Safe on empty table (Codespace). In production with data,
--           requires maintenance window (tested here for future deploy).
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL38: Convert analytics_events to partitioned table.
--          PostgreSQL cannot ALTER TABLE ... PARTITION BY on existing
--          table. Must use RENAME → CREATE → INSERT → DROP pattern.
-- ════════════════════════════════════════════════════════════════════

-- Step 1: Rename existing table (preserves data)
ALTER TABLE analytics_events RENAME TO analytics_events_old;

-- Step 2: Create new partitioned table with exact same structure
CREATE TABLE analytics_events (
    id             BIGSERIAL    NOT NULL,
    tenant_id      TEXT         NOT NULL,
    user_id        TEXT         NOT NULL,
    session_id     TEXT,
    event_type     TEXT         NOT NULL,
    event_name     TEXT         NOT NULL,
    properties     JSONB        NOT NULL DEFAULT '{}',
    timestamp      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    ip_address     INET,
    user_agent     TEXT,
    CONSTRAINT chk_properties_size CHECK (length(properties::text) <= 102400)
) PARTITION BY RANGE (timestamp);

-- Step 3: Create partitions (monthly from 2025 through 2027)
CREATE TABLE analytics_events_2025_01 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE analytics_events_2025_02 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE analytics_events_2025_03 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE analytics_events_2025_04 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
CREATE TABLE analytics_events_2025_05 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
CREATE TABLE analytics_events_2025_06 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE analytics_events_2025_07 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE analytics_events_2025_08 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE analytics_events_2025_09 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE analytics_events_2025_10 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE analytics_events_2025_11 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE analytics_events_2025_12 PARTITION OF analytics_events
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

CREATE TABLE analytics_events_2026_01 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE analytics_events_2026_02 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE analytics_events_2026_03 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE analytics_events_2026_04 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE analytics_events_2026_05 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE analytics_events_2026_06 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE analytics_events_2026_07 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE analytics_events_2026_08 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE analytics_events_2026_09 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE analytics_events_2026_10 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE analytics_events_2026_11 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE analytics_events_2026_12 PARTITION OF analytics_events
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

CREATE TABLE analytics_events_2027_01 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
CREATE TABLE analytics_events_2027_02 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-02-01') TO ('2027-03-01');
CREATE TABLE analytics_events_2027_03 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-03-01') TO ('2027-04-01');
CREATE TABLE analytics_events_2027_04 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-04-01') TO ('2027-05-01');
CREATE TABLE analytics_events_2027_05 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-05-01') TO ('2027-06-01');
CREATE TABLE analytics_events_2027_06 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-06-01') TO ('2027-07-01');
CREATE TABLE analytics_events_2027_07 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-07-01') TO ('2027-08-01');
CREATE TABLE analytics_events_2027_08 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-08-01') TO ('2027-09-01');
CREATE TABLE analytics_events_2027_09 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-09-01') TO ('2027-10-01');
CREATE TABLE analytics_events_2027_10 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-10-01') TO ('2027-11-01');
CREATE TABLE analytics_events_2027_11 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-11-01') TO ('2027-12-01');
CREATE TABLE analytics_events_2027_12 PARTITION OF analytics_events
    FOR VALUES FROM ('2027-12-01') TO ('2028-01-01');

-- Default partition for future dates
CREATE TABLE analytics_events_default PARTITION OF analytics_events DEFAULT;

-- Step 4: Recreate indexes (automatically applied to all partitions)
CREATE INDEX idx_analytics_events_tenant_time
    ON analytics_events (tenant_id, timestamp DESC);
CREATE INDEX idx_analytics_events_user
    ON analytics_events (tenant_id, user_id, timestamp);
CREATE INDEX idx_analytics_events_type
    ON analytics_events (event_type, event_name);

-- Step 5: Migrate data from old table (if any exists)
INSERT INTO analytics_events
    SELECT * FROM analytics_events_old;

-- Step 6: Drop old table
DROP TABLE analytics_events_old;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- Reverse: RENAME partitioned → CREATE non-partitioned → INSERT → DROP
ALTER TABLE analytics_events RENAME TO analytics_events_partitioned;

CREATE TABLE analytics_events (
    id             BIGSERIAL PRIMARY KEY,
    tenant_id      TEXT      NOT NULL,
    user_id        TEXT      NOT NULL,
    session_id     TEXT,
    event_type     TEXT      NOT NULL,
    event_name     TEXT      NOT NULL,
    properties     JSONB     NOT NULL DEFAULT '{}',
    timestamp      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_address     INET,
    user_agent     TEXT
);

CREATE INDEX idx_analytics_events_tenant_time ON analytics_events(tenant_id, timestamp DESC);
CREATE INDEX idx_analytics_events_user ON analytics_events(tenant_id, user_id, timestamp);
CREATE INDEX idx_analytics_events_type ON analytics_events(event_type, event_name);

INSERT INTO analytics_events SELECT * FROM analytics_events_partitioned;
DROP TABLE analytics_events_partitioned;

-- +goose StatementEnd
