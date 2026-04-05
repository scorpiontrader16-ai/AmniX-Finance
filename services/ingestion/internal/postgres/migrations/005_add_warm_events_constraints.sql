-- ============================================================
-- services/ingestion/internal/postgres/migrations/005_add_warm_events_constraints.sql
-- Scope: ingestion service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL27 MEDIUM: warm_events.payload TEXT without size limit
--                   - unbounded text fields can cause disk space issues
--                   - limit to 1MB (1048576 bytes) per event payload
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL27: warm_events.payload TEXT without size limit.
--          Unbounded text column can cause disk space exhaustion and
--          performance issues when loading large events. Limit to 1MB
--          which is more than sufficient for any valid event data.
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE warm_events
    ADD CONSTRAINT chk_payload_size
    CHECK (length(payload) <= 1048576);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

ALTER TABLE warm_events
    DROP CONSTRAINT IF EXISTS chk_payload_size;

-- +goose StatementEnd
