-- ============================================================
-- services/notifications/internal/postgres/migrations/008_add_email_validation.sql
-- Scope: notifications service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL41 HIGH: email_log.to_email TEXT without format validation
--                - invalid email formats can cause delivery failures
--                - add basic email format validation pattern
--   F-SQL44 MEDIUM: notification templates hardcode "youtuop" brand name
--                  - breaks in white-label deployments
--                  - replace with configurable brand name
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL41: email_log.to_email TEXT without format validation.
--          Invalid email formats can cause delivery failures and 
--          bounce processing errors. Add basic pattern validation.
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE email_log
    ADD CONSTRAINT chk_email_format
    CHECK (to_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');

-- ════════════════════════════════════════════════════════════════════
-- F-SQL44: notification templates hardcode "youtuop" brand name.
--          This breaks in white-label deployments where the product
--          is rebranded. Replace with configurable brand name from
--          app.brand_name setting (defaults to "Platform" if unset).
-- ════════════════════════════════════════════════════════════════════

-- Update existing templates to use configurable brand name
UPDATE notification_templates
SET 
    subject = REPLACE(subject, 'Youtuop', 
        COALESCE(current_setting('app.brand_name', true), 'Platform')),
    body_text = REPLACE(body_text, 'Youtuop', 
        COALESCE(current_setting('app.brand_name', true), 'Platform')),
    body_html = REPLACE(body_html, 'Youtuop', 
        COALESCE(current_setting('app.brand_name', true), 'Platform'))
WHERE 
    subject LIKE '%Youtuop%' OR 
    body_text LIKE '%Youtuop%' OR 
    body_html LIKE '%Youtuop%';

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- ── Reverse F-SQL44 ──────────────────────────────────────────────────
-- Note: This will not perfectly restore original templates,
-- as we don't know which instances were originally "Youtuop".
-- In practice, Down migrations for seed data are rarely used.
UPDATE notification_templates
SET 
    subject = REPLACE(subject, 
        COALESCE(current_setting('app.brand_name', true), 'Platform'), 'Youtuop'),
    body_text = REPLACE(body_text, 
        COALESCE(current_setting('app.brand_name', true), 'Platform'), 'Youtuop'),
    body_html = REPLACE(body_html, 
        COALESCE(current_setting('app.brand_name', true), 'Platform'), 'Youtuop');

-- ── Reverse F-SQL41 ──────────────────────────────────────────────────
ALTER TABLE email_log
    DROP CONSTRAINT IF EXISTS chk_email_format;

-- +goose StatementEnd
