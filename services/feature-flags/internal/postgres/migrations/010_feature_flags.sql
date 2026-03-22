-- ============================================================
-- 010_feature_flags.sql
-- M16 Feature Flags
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ── 1. Feature Flags ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS feature_flags (
    id           TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    key          TEXT        NOT NULL UNIQUE,
    name         TEXT        NOT NULL,
    description  TEXT,
    type         TEXT        NOT NULL DEFAULT 'boolean',
    default_value JSONB      NOT NULL DEFAULT 'false',
    enabled      BOOLEAN     NOT NULL DEFAULT FALSE,
    rollout_pct  INTEGER     NOT NULL DEFAULT 0,
    created_by   TEXT        REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_ff_type CHECK (
        type IN ('boolean', 'string', 'number', 'json')
    ),
    CONSTRAINT chk_ff_rollout CHECK (
        rollout_pct BETWEEN 0 AND 100
    )
);

CREATE INDEX IF NOT EXISTS idx_feature_flags_enabled
    ON feature_flags (key, enabled)
    WHERE enabled = TRUE;

CREATE TRIGGER trg_feature_flags_updated_at
    BEFORE UPDATE ON feature_flags
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 2. Flag Overrides (per-tenant أو per-user) ───────────────
CREATE TABLE IF NOT EXISTS flag_overrides (
    id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    flag_id     TEXT        NOT NULL REFERENCES feature_flags(id) ON DELETE CASCADE,
    target_type TEXT        NOT NULL,
    target_id   TEXT        NOT NULL,
    value       JSONB       NOT NULL DEFAULT 'true',
    enabled     BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by  TEXT        REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (flag_id, target_type, target_id),
    CONSTRAINT chk_override_target CHECK (
        target_type IN ('tenant', 'user', 'plan')
    )
);

CREATE INDEX IF NOT EXISTS idx_flag_overrides_flag
    ON flag_overrides (flag_id, enabled)
    WHERE enabled = TRUE;

CREATE INDEX IF NOT EXISTS idx_flag_overrides_target
    ON flag_overrides (target_type, target_id)
    WHERE enabled = TRUE;

-- ── 3. Flag Evaluation Log (sampling فقط — مش كل request) ───
CREATE TABLE IF NOT EXISTS flag_evaluations (
    id          BIGSERIAL   PRIMARY KEY,
    flag_key    TEXT        NOT NULL,
    tenant_id   TEXT,
    user_id     TEXT,
    result      JSONB       NOT NULL,
    reason      TEXT        NOT NULL DEFAULT 'default',
    evaluated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_eval_reason CHECK (
        reason IN ('default', 'override', 'rollout', 'disabled')
    )
);

CREATE INDEX IF NOT EXISTS idx_flag_evaluations_key
    ON flag_evaluations (flag_key, evaluated_at DESC);

CREATE INDEX IF NOT EXISTS idx_flag_evaluations_tenant
    ON flag_evaluations (tenant_id, evaluated_at DESC)
    WHERE tenant_id IS NOT NULL;

-- ── 4. Seed: Platform Feature Flags ──────────────────────────
INSERT INTO feature_flags (key, name, description, type, default_value, enabled, rollout_pct) VALUES
    ('ai_agents_enabled',        'AI Agents',              'Enable AI agent execution',               'boolean', 'false', FALSE, 0),
    ('realtime_streaming',       'Real-time Streaming',    'WebSocket market data streaming',          'boolean', 'false', FALSE, 0),
    ('advanced_analytics',       'Advanced Analytics',     'Backtesting and ML-based indicators',      'boolean', 'false', FALSE, 0),
    ('bulk_export',              'Bulk Data Export',       'Export large datasets to CSV/Parquet',     'boolean', 'true',  TRUE,  100),
    ('api_v2',                   'API v2',                 'New API version with GraphQL support',     'boolean', 'false', FALSE, 0),
    ('dark_mode',                'Dark Mode',              'UI dark mode toggle',                      'boolean', 'true',  TRUE,  100),
    ('mfa_required',             'MFA Required',           'Force MFA for all users in tenant',        'boolean', 'false', FALSE, 0),
    ('custom_dashboards',        'Custom Dashboards',      'Allow custom dashboard creation',          'boolean', 'true',  TRUE,  100),
    ('developer_portal',         'Developer Portal',       'API keys and developer tools',             'boolean', 'false', FALSE, 0),
    ('rate_limit_override',      'Rate Limit Override',    'Custom rate limits per tenant',            'json',    'null',  FALSE, 0)
ON CONFLICT (key) DO NOTHING;

-- ── 5. Seed: Plan-based overrides ────────────────────────────
-- Enterprise gets everything enabled
INSERT INTO flag_overrides (flag_id, target_type, target_id, value) VALUES
    ((SELECT id FROM feature_flags WHERE key = 'ai_agents_enabled'),   'plan', 'enterprise', 'true'),
    ((SELECT id FROM feature_flags WHERE key = 'ai_agents_enabled'),   'plan', 'business',   'true'),
    ((SELECT id FROM feature_flags WHERE key = 'realtime_streaming'),  'plan', 'enterprise', 'true'),
    ((SELECT id FROM feature_flags WHERE key = 'realtime_streaming'),  'plan', 'business',   'true'),
    ((SELECT id FROM feature_flags WHERE key = 'realtime_streaming'),  'plan', 'pro',        'true'),
    ((SELECT id FROM feature_flags WHERE key = 'advanced_analytics'),  'plan', 'enterprise', 'true'),
    ((SELECT id FROM feature_flags WHERE key = 'advanced_analytics'),  'plan', 'business',   'true'),
    ((SELECT id FROM feature_flags WHERE key = 'developer_portal'),    'plan', 'enterprise', 'true'),
    ((SELECT id FROM feature_flags WHERE key = 'developer_portal'),    'plan', 'business',   'true'),
    ((SELECT id FROM feature_flags WHERE key = 'developer_portal'),    'plan', 'pro',        'true')
ON CONFLICT (flag_id, target_type, target_id) DO NOTHING;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TRIGGER IF EXISTS trg_feature_flags_updated_at ON feature_flags;

DROP TABLE IF EXISTS flag_evaluations CASCADE;
DROP TABLE IF EXISTS flag_overrides   CASCADE;
DROP TABLE IF EXISTS feature_flags    CASCADE;

-- +goose StatementEnd
