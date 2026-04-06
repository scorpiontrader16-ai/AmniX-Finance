-- ============================================================
-- services/feature-flags/internal/postgres/migrations/012_fix_flag_overrides_seed.sql
-- Scope: feature-flags service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes:
--   F-SQL30: flag_overrides seed in 010 uses subquery in VALUES clause.
--            If the subquery returns NULL (flag not seeded yet or rolled back),
--            the INSERT fails with NOT NULL violation on flag_id.
--            Fix: replace VALUES+subquery with INSERT...SELECT pattern
--            which silently skips rows when the flag does not exist.
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL30: flag_overrides seed safety fix.
--
-- Root cause in 010_feature_flags.sql:
--   INSERT INTO flag_overrides (flag_id, ...) VALUES
--       ((SELECT id FROM feature_flags WHERE key = '...'), ...)
--
-- PostgreSQL evaluates the subquery at INSERT time. If the feature_flag
-- row is absent (e.g. seed failed, rolled back, or re-run on partial
-- state), the subquery returns NULL. flag_id is NOT NULL (FK), so the
-- INSERT raises:
--   ERROR: null value in column "flag_id" of relation "flag_overrides"
--          violates not-null constraint
--
-- Fix: use INSERT ... SELECT FROM feature_flags WHERE key = '...'
-- This skips the INSERT entirely when the flag does not exist,
-- rather than failing the migration.
--
-- ON CONFLICT DO NOTHING: idempotent re-runs safe.
-- ════════════════════════════════════════════════════════════════════

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'enterprise', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'ai_agents_enabled'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'business', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'ai_agents_enabled'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'enterprise', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'realtime_streaming'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'business', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'realtime_streaming'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'pro', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'realtime_streaming'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'enterprise', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'advanced_analytics'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'business', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'advanced_analytics'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'enterprise', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'developer_portal'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'business', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'developer_portal'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

INSERT INTO flag_overrides (flag_id, target_type, target_id, value)
SELECT f.id, 'plan', 'pro', 'true'::jsonb
FROM feature_flags f WHERE f.key = 'developer_portal'
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- F-SQL30 fix is additive — inserts already present in 010 via the
-- original subquery pattern are not duplicated (ON CONFLICT).
-- DOWN is intentionally a no-op: removing these overrides would break
-- runtime behavior for enterprise/business/pro tenants.
-- The correct rollback is to roll back 010_feature_flags.sql itself.
SELECT 'no-op: flag_override rows managed by 010_feature_flags seed';

-- +goose StatementEnd
