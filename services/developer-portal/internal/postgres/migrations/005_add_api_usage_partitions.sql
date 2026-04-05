-- ============================================================
-- services/developer-portal/internal/postgres/migrations/005_add_api_usage_partitions.sql
-- Scope: developer-portal service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL19 HIGH: api_usage partitions missing w03→w12 (2026-01-15 to 2026-03-23)
--                 Data for those weeks falls to DEFAULT partition causing
--                 full sequential scans on every weekly query.
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL19: api_usage weekly partitions w03→w12 are missing.
--          Existing: w01, w02, w13, w14, w15, default
--          Missing:  w03(Jan15-22), w04(Jan22-29), w05(Jan29-Feb5),
--                    w06(Feb5-12),  w07(Feb12-19), w08(Feb19-26),
--                    w09(Feb26-Mar5), w10(Mar5-12), w11(Mar12-19),
--                    w12(Mar19-23→Mar23 because w13 starts Mar23)
--          Data currently in DEFAULT partition will NOT migrate
--          automatically — PostgreSQL does not move rows when a new
--          partition is added. Existing data stays in DEFAULT.
--          New data from these date ranges will route correctly.
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS api_usage_2026_w03
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-01-15') TO ('2026-01-22');

CREATE TABLE IF NOT EXISTS api_usage_2026_w04
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-01-22') TO ('2026-01-29');

CREATE TABLE IF NOT EXISTS api_usage_2026_w05
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-01-29') TO ('2026-02-05');

CREATE TABLE IF NOT EXISTS api_usage_2026_w06
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-02-05') TO ('2026-02-12');

CREATE TABLE IF NOT EXISTS api_usage_2026_w07
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-02-12') TO ('2026-02-19');

CREATE TABLE IF NOT EXISTS api_usage_2026_w08
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-02-19') TO ('2026-02-26');

CREATE TABLE IF NOT EXISTS api_usage_2026_w09
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-02-26') TO ('2026-03-05');

CREATE TABLE IF NOT EXISTS api_usage_2026_w10
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-03-05') TO ('2026-03-12');

CREATE TABLE IF NOT EXISTS api_usage_2026_w11
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-03-12') TO ('2026-03-19');

CREATE TABLE IF NOT EXISTS api_usage_2026_w12
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-03-19') TO ('2026-03-23');

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- NOTE: Dropping partitions does NOT delete data — rows move back to DEFAULT
DROP TABLE IF EXISTS api_usage_2026_w12;
DROP TABLE IF EXISTS api_usage_2026_w11;
DROP TABLE IF EXISTS api_usage_2026_w10;
DROP TABLE IF EXISTS api_usage_2026_w09;
DROP TABLE IF EXISTS api_usage_2026_w08;
DROP TABLE IF EXISTS api_usage_2026_w07;
DROP TABLE IF EXISTS api_usage_2026_w06;
DROP TABLE IF EXISTS api_usage_2026_w05;
DROP TABLE IF EXISTS api_usage_2026_w04;
DROP TABLE IF EXISTS api_usage_2026_w03;

-- +goose StatementEnd
