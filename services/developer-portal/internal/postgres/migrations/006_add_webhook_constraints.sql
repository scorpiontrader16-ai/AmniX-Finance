-- ============================================================
-- services/developer-portal/internal/postgres/migrations/006_add_webhook_constraints.sql
-- Scope: developer-portal service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL20 HIGH: webhook_endpoints.secret_hash without constraint
--                 - SHA256 hash should be exactly 64 characters
--                 - Without validation, security bypass is possible
--   F-SQL29 MEDIUM: webhook_deliveries.response_body without size limit
--                  - can exhaust storage with large responses
--                  - limit to 1MB per response body
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL20: webhook_endpoints.secret_hash without length constraint.
--          This column stores SHA256 hash of webhook secret - must be
--          exactly 64 characters. Without validation, invalid hashes
--          could be stored, breaking webhook signature verification.
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE webhook_endpoints
    ADD CONSTRAINT chk_secret_hash_length
    CHECK (length(secret_hash) = 64);

-- ════════════════════════════════════════════════════════════════════
-- F-SQL29: webhook_deliveries.response_body TEXT without size limit.
--          Large responses can consume excessive storage and impact
--          query performance. Limit to 1MB per response body.
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE webhook_deliveries
    ADD CONSTRAINT chk_response_body_size
    CHECK (response_body IS NULL OR length(response_body) <= 1048576);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

ALTER TABLE webhook_deliveries
    DROP CONSTRAINT IF EXISTS chk_response_body_size;

ALTER TABLE webhook_endpoints
    DROP CONSTRAINT IF EXISTS chk_secret_hash_length;

-- +goose StatementEnd
