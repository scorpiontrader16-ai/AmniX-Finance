-- ============================================================
-- infra/clickhouse/init.sql
-- ClickHouse Hot Store — Events Database
-- ============================================================

-- تمت إزالة أوامر CREATE USER و GRANT لأن المستخدم platform موجود مسبقاً
CREATE DATABASE IF NOT EXISTS events;

-- ── جدول base_events (Hot Store — 7 أيام) ─────────────────
CREATE TABLE IF NOT EXISTS events.base_events
(
    event_id       String,
    event_type     LowCardinality(String),
    source         LowCardinality(String),
    schema_version LowCardinality(String),
    occurred_at    DateTime64(3, 'UTC'),
    ingested_at    DateTime64(3, 'UTC'),
    tenant_id      LowCardinality(String),
    partition_key  String,
    content_type   LowCardinality(String),
    payload        String,
    payload_bytes  UInt32 DEFAULT 0,
    trace_id       String,
    span_id        String,
    meta_keys      Array(String),
    meta_values    Array(String),
    inserted_at    DateTime64(3, 'UTC') DEFAULT now64(3)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (tenant_id, event_type, occurred_at, event_id)
TTL toDateTime(occurred_at) + INTERVAL 7 DAY
SETTINGS
    index_granularity = 8192,
    ttl_only_drop_parts = 1;

-- ── جدول events_by_type ────────────────────────────────────
CREATE TABLE IF NOT EXISTS events.events_by_type
(
    event_type  LowCardinality(String),
    tenant_id   LowCardinality(String),
    occurred_at DateTime64(3, 'UTC'),
    event_id    String,
    source      LowCardinality(String),
    trace_id    String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(occurred_at)
ORDER BY (event_type, tenant_id, occurred_at)
TTL toDateTime(occurred_at) + INTERVAL 7 DAY;

-- ── Materialized View: base_events → events_by_type ────────
CREATE MATERIALIZED VIEW IF NOT EXISTS events.mv_events_by_type
TO events.events_by_type
AS SELECT
    event_type,
    tenant_id,
    occurred_at,
    event_id,
    source,
    trace_id
FROM events.base_events;

-- ── جدول hourly_stats ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS events.hourly_stats
(
    hour                DateTime,
    tenant_id           LowCardinality(String),
    event_type          LowCardinality(String),
    source              LowCardinality(String),
    event_count         UInt64,
    total_payload_bytes UInt64
)
ENGINE = SummingMergeTree((event_count, total_payload_bytes))
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, tenant_id, event_type, source)
TTL hour + INTERVAL 30 DAY;

-- ── Materialized View: base_events → hourly_stats ──────────
CREATE MATERIALIZED VIEW IF NOT EXISTS events.mv_hourly_stats
TO events.hourly_stats
AS SELECT
    toStartOfHour(occurred_at) AS hour,
    tenant_id,
    event_type,
    source,
    count()              AS event_count,
    sum(payload_bytes)   AS total_payload_bytes
FROM events.base_events
GROUP BY hour, tenant_id, event_type, source;

-- ── جدول cold_storage_index — تتبع Parquet files في MinIO ──
-- يُستخدم للـ query routing: هل البيانات في hot أو cold؟
CREATE TABLE IF NOT EXISTS events.cold_storage_index
(
    file_id         String,
    tenant_id       LowCardinality(String),
    bucket          LowCardinality(String),
    object_key      String,
    schema_version  LowCardinality(String),
    row_count       UInt64  DEFAULT 0,
    file_size_bytes UInt64  DEFAULT 0,
    from_date       DateTime,
    to_date         DateTime,
    event_types     Array(String),
    status          LowCardinality(String) DEFAULT 'active',
    created_at      DateTime64(3, 'UTC')  DEFAULT now64(3)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(from_date)
ORDER BY (tenant_id, from_date, file_id)
SETTINGS index_granularity = 8192;
