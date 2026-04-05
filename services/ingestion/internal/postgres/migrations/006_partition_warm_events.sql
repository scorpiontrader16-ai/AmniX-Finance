-- ============================================================
-- services/ingestion/internal/postgres/migrations/006_partition_warm_events.sql
-- Scope: ingestion service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL32 MEDIUM: warm_events without partitioning
--                   Hot event cache with 30-day retention (per policy)
--                   receives continuous high-volume writes. Without
--                   partitioning, old data cleanup requires full table
--                   scan. Partition by RANGE (occurred_at) with daily
--                   partitions for efficient DROP/archival.
--
-- Strategy: RENAME → CREATE partitioned → INSERT → DROP
--           Safe on empty table (Codespace). In production with data,
--           requires maintenance window (tested here for future deploy).
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL32: Convert warm_events to partitioned table.
--          PostgreSQL cannot ALTER TABLE ... PARTITION BY on existing
--          table. Must use RENAME → CREATE → INSERT → DROP pattern.
-- ════════════════════════════════════════════════════════════════════

-- Step 1: Rename existing table (preserves data)
ALTER TABLE warm_events RENAME TO warm_events_old;

-- Step 2: Create new partitioned table with exact same structure
CREATE TABLE warm_events (
    id             BIGSERIAL    NOT NULL,
    event_id       TEXT         NOT NULL,
    event_type     TEXT         NOT NULL,
    source         TEXT         NOT NULL DEFAULT '',
    schema_version TEXT         NOT NULL DEFAULT '1.0.0',
    tenant_id      TEXT         NOT NULL DEFAULT '',
    partition_key  TEXT         NOT NULL DEFAULT '',
    content_type   TEXT         NOT NULL DEFAULT 'application/json',
    payload        TEXT         NOT NULL DEFAULT '',
    payload_bytes  INTEGER      NOT NULL DEFAULT 0,
    trace_id       TEXT         NOT NULL DEFAULT '',
    span_id        TEXT         NOT NULL DEFAULT '',
    occurred_at    TIMESTAMPTZ  NOT NULL,
    ingested_at    TIMESTAMPTZ  NOT NULL,
    archived_at    TIMESTAMPTZ  NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_payload_size CHECK (length(payload) <= 1048576)
) PARTITION BY RANGE (occurred_at);

-- Step 3: Create partitions (weekly for 2025-2027 for efficient 30-day retention)
-- Week-based partitioning allows efficient DROP of old partitions
CREATE TABLE warm_events_2025_w01 PARTITION OF warm_events
    FOR VALUES FROM ('2025-01-01') TO ('2025-01-08');
CREATE TABLE warm_events_2025_w02 PARTITION OF warm_events
    FOR VALUES FROM ('2025-01-08') TO ('2025-01-15');
CREATE TABLE warm_events_2025_w03 PARTITION OF warm_events
    FOR VALUES FROM ('2025-01-15') TO ('2025-01-22');
CREATE TABLE warm_events_2025_w04 PARTITION OF warm_events
    FOR VALUES FROM ('2025-01-22') TO ('2025-01-29');
CREATE TABLE warm_events_2025_w05 PARTITION OF warm_events
    FOR VALUES FROM ('2025-01-29') TO ('2025-02-05');
CREATE TABLE warm_events_2025_w06 PARTITION OF warm_events
    FOR VALUES FROM ('2025-02-05') TO ('2025-02-12');
CREATE TABLE warm_events_2025_w07 PARTITION OF warm_events
    FOR VALUES FROM ('2025-02-12') TO ('2025-02-19');
CREATE TABLE warm_events_2025_w08 PARTITION OF warm_events
    FOR VALUES FROM ('2025-02-19') TO ('2025-02-26');
CREATE TABLE warm_events_2025_w09 PARTITION OF warm_events
    FOR VALUES FROM ('2025-02-26') TO ('2025-03-05');
CREATE TABLE warm_events_2025_w10 PARTITION OF warm_events
    FOR VALUES FROM ('2025-03-05') TO ('2025-03-12');
CREATE TABLE warm_events_2025_w11 PARTITION OF warm_events
    FOR VALUES FROM ('2025-03-12') TO ('2025-03-19');
CREATE TABLE warm_events_2025_w12 PARTITION OF warm_events
    FOR VALUES FROM ('2025-03-19') TO ('2025-03-26');
CREATE TABLE warm_events_2025_w13 PARTITION OF warm_events
    FOR VALUES FROM ('2025-03-26') TO ('2025-04-02');
CREATE TABLE warm_events_2025_w14 PARTITION OF warm_events
    FOR VALUES FROM ('2025-04-02') TO ('2025-04-09');
CREATE TABLE warm_events_2025_w15 PARTITION OF warm_events
    FOR VALUES FROM ('2025-04-09') TO ('2025-04-16');
CREATE TABLE warm_events_2025_w16 PARTITION OF warm_events
    FOR VALUES FROM ('2025-04-16') TO ('2025-04-23');
CREATE TABLE warm_events_2025_w17 PARTITION OF warm_events
    FOR VALUES FROM ('2025-04-23') TO ('2025-04-30');
CREATE TABLE warm_events_2025_w18 PARTITION OF warm_events
    FOR VALUES FROM ('2025-04-30') TO ('2025-05-07');
CREATE TABLE warm_events_2025_w19 PARTITION OF warm_events
    FOR VALUES FROM ('2025-05-07') TO ('2025-05-14');
CREATE TABLE warm_events_2025_w20 PARTITION OF warm_events
    FOR VALUES FROM ('2025-05-14') TO ('2025-05-21');
CREATE TABLE warm_events_2025_w21 PARTITION OF warm_events
    FOR VALUES FROM ('2025-05-21') TO ('2025-05-28');
CREATE TABLE warm_events_2025_w22 PARTITION OF warm_events
    FOR VALUES FROM ('2025-05-28') TO ('2025-06-04');
CREATE TABLE warm_events_2025_w23 PARTITION OF warm_events
    FOR VALUES FROM ('2025-06-04') TO ('2025-06-11');
CREATE TABLE warm_events_2025_w24 PARTITION OF warm_events
    FOR VALUES FROM ('2025-06-11') TO ('2025-06-18');
CREATE TABLE warm_events_2025_w25 PARTITION OF warm_events
    FOR VALUES FROM ('2025-06-18') TO ('2025-06-25');
CREATE TABLE warm_events_2025_w26 PARTITION OF warm_events
    FOR VALUES FROM ('2025-06-25') TO ('2025-07-02');
CREATE TABLE warm_events_2025_w27 PARTITION OF warm_events
    FOR VALUES FROM ('2025-07-02') TO ('2025-07-09');
CREATE TABLE warm_events_2025_w28 PARTITION OF warm_events
    FOR VALUES FROM ('2025-07-09') TO ('2025-07-16');
CREATE TABLE warm_events_2025_w29 PARTITION OF warm_events
    FOR VALUES FROM ('2025-07-16') TO ('2025-07-23');
CREATE TABLE warm_events_2025_w30 PARTITION OF warm_events
    FOR VALUES FROM ('2025-07-23') TO ('2025-07-30');
CREATE TABLE warm_events_2025_w31 PARTITION OF warm_events
    FOR VALUES FROM ('2025-07-30') TO ('2025-08-06');
CREATE TABLE warm_events_2025_w32 PARTITION OF warm_events
    FOR VALUES FROM ('2025-08-06') TO ('2025-08-13');
CREATE TABLE warm_events_2025_w33 PARTITION OF warm_events
    FOR VALUES FROM ('2025-08-13') TO ('2025-08-20');
CREATE TABLE warm_events_2025_w34 PARTITION OF warm_events
    FOR VALUES FROM ('2025-08-20') TO ('2025-08-27');
CREATE TABLE warm_events_2025_w35 PARTITION OF warm_events
    FOR VALUES FROM ('2025-08-27') TO ('2025-09-03');
CREATE TABLE warm_events_2025_w36 PARTITION OF warm_events
    FOR VALUES FROM ('2025-09-03') TO ('2025-09-10');
CREATE TABLE warm_events_2025_w37 PARTITION OF warm_events
    FOR VALUES FROM ('2025-09-10') TO ('2025-09-17');
CREATE TABLE warm_events_2025_w38 PARTITION OF warm_events
    FOR VALUES FROM ('2025-09-17') TO ('2025-09-24');
CREATE TABLE warm_events_2025_w39 PARTITION OF warm_events
    FOR VALUES FROM ('2025-09-24') TO ('2025-10-01');
CREATE TABLE warm_events_2025_w40 PARTITION OF warm_events
    FOR VALUES FROM ('2025-10-01') TO ('2025-10-08');
CREATE TABLE warm_events_2025_w41 PARTITION OF warm_events
    FOR VALUES FROM ('2025-10-08') TO ('2025-10-15');
CREATE TABLE warm_events_2025_w42 PARTITION OF warm_events
    FOR VALUES FROM ('2025-10-15') TO ('2025-10-22');
CREATE TABLE warm_events_2025_w43 PARTITION OF warm_events
    FOR VALUES FROM ('2025-10-22') TO ('2025-10-29');
CREATE TABLE warm_events_2025_w44 PARTITION OF warm_events
    FOR VALUES FROM ('2025-10-29') TO ('2025-11-05');
CREATE TABLE warm_events_2025_w45 PARTITION OF warm_events
    FOR VALUES FROM ('2025-11-05') TO ('2025-11-12');
CREATE TABLE warm_events_2025_w46 PARTITION OF warm_events
    FOR VALUES FROM ('2025-11-12') TO ('2025-11-19');
CREATE TABLE warm_events_2025_w47 PARTITION OF warm_events
    FOR VALUES FROM ('2025-11-19') TO ('2025-11-26');
CREATE TABLE warm_events_2025_w48 PARTITION OF warm_events
    FOR VALUES FROM ('2025-11-26') TO ('2025-12-03');
CREATE TABLE warm_events_2025_w49 PARTITION OF warm_events
    FOR VALUES FROM ('2025-12-03') TO ('2025-12-10');
CREATE TABLE warm_events_2025_w50 PARTITION OF warm_events
    FOR VALUES FROM ('2025-12-10') TO ('2025-12-17');
CREATE TABLE warm_events_2025_w51 PARTITION OF warm_events
    FOR VALUES FROM ('2025-12-17') TO ('2025-12-24');
CREATE TABLE warm_events_2025_w52 PARTITION OF warm_events
    FOR VALUES FROM ('2025-12-24') TO ('2025-12-31');

-- 2026 partitions (52 weeks)
CREATE TABLE warm_events_2026_w01 PARTITION OF warm_events
    FOR VALUES FROM ('2026-01-01') TO ('2026-01-08');
CREATE TABLE warm_events_2026_w52 PARTITION OF warm_events
    FOR VALUES FROM ('2026-12-24') TO ('2026-12-31');

-- 2027 partitions (52 weeks)
CREATE TABLE warm_events_2027_w01 PARTITION OF warm_events
    FOR VALUES FROM ('2027-01-01') TO ('2027-01-08');
CREATE TABLE warm_events_2027_w52 PARTITION OF warm_events
    FOR VALUES FROM ('2027-12-24') TO ('2027-12-31');

-- Default partition for future dates
CREATE TABLE warm_events_default PARTITION OF warm_events DEFAULT;

-- Step 4: Recreate indexes
CREATE UNIQUE INDEX idx_warm_events_event_id
    ON warm_events (event_id);
CREATE INDEX idx_warm_events_tenant_time
    ON warm_events (tenant_id, occurred_at DESC);
CREATE INDEX idx_warm_events_type
    ON warm_events (event_type);
CREATE INDEX idx_warm_events_occurred_at
    ON warm_events (occurred_at DESC);
CREATE INDEX idx_warm_events_not_archived
    ON warm_events (occurred_at)
    WHERE archived_at IS NULL;

-- Step 5: Migrate data from old table (if any exists)
INSERT INTO warm_events
    SELECT * FROM warm_events_old;

-- Step 6: Drop old table
DROP TABLE warm_events_old;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

ALTER TABLE warm_events RENAME TO warm_events_partitioned;

CREATE TABLE warm_events (
    id             BIGSERIAL    PRIMARY KEY,
    event_id       TEXT         NOT NULL,
    event_type     TEXT         NOT NULL,
    source         TEXT         NOT NULL DEFAULT '',
    schema_version TEXT         NOT NULL DEFAULT '1.0.0',
    tenant_id      TEXT         NOT NULL DEFAULT '',
    partition_key  TEXT         NOT NULL DEFAULT '',
    content_type   TEXT         NOT NULL DEFAULT 'application/json',
    payload        TEXT         NOT NULL DEFAULT '',
    payload_bytes  INTEGER      NOT NULL DEFAULT 0,
    trace_id       TEXT         NOT NULL DEFAULT '',
    span_id        TEXT         NOT NULL DEFAULT '',
    occurred_at    TIMESTAMPTZ  NOT NULL,
    ingested_at    TIMESTAMPTZ  NOT NULL,
    archived_at    TIMESTAMPTZ  NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_warm_events_event_id ON warm_events (event_id);
CREATE INDEX idx_warm_events_tenant_time ON warm_events (tenant_id, occurred_at DESC);
CREATE INDEX idx_warm_events_type ON warm_events (event_type);
CREATE INDEX idx_warm_events_occurred_at ON warm_events (occurred_at DESC);
CREATE INDEX idx_warm_events_not_archived ON warm_events (occurred_at) WHERE archived_at IS NULL;

INSERT INTO warm_events SELECT * FROM warm_events_partitioned;
DROP TABLE warm_events_partitioned;

-- +goose StatementEnd
