-- ============================================================
-- 011_developer_portal.sql
-- M18 Developer Portal
-- يبني فوق api_keys الموجودة في 005
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ── 1. إضافة columns على api_keys الموجودة ──────────────────
ALTER TABLE api_keys
    ADD COLUMN IF NOT EXISTS description  TEXT,
    ADD COLUMN IF NOT EXISTS environment  TEXT NOT NULL DEFAULT 'production',
    ADD COLUMN IF NOT EXISTS request_count BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS rate_limit   INTEGER NOT NULL DEFAULT 1000,
    ADD COLUMN IF NOT EXISTS allowed_ips  TEXT[],
    ADD COLUMN IF NOT EXISTS metadata     JSONB NOT NULL DEFAULT '{}';

ALTER TABLE api_keys
    ADD CONSTRAINT chk_api_keys_env CHECK (
        environment IN ('production', 'sandbox')
    );

-- ── 2. Webhook Endpoints ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS webhook_endpoints (
    id           TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    tenant_id    TEXT        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id      TEXT        NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    name         TEXT        NOT NULL,
    url          TEXT        NOT NULL,
    secret_hash  TEXT        NOT NULL,
    events       TEXT[]      NOT NULL DEFAULT '{}',
    enabled      BOOLEAN     NOT NULL DEFAULT TRUE,
    retry_count  INTEGER     NOT NULL DEFAULT 3,
    timeout_ms   INTEGER     NOT NULL DEFAULT 5000,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_webhook_url     CHECK (url     <> ''),
    CONSTRAINT chk_webhook_name    CHECK (name    <> ''),
    CONSTRAINT chk_webhook_timeout CHECK (timeout_ms BETWEEN 1000 AND 30000),
    CONSTRAINT chk_webhook_retry   CHECK (retry_count BETWEEN 0 AND 10)
);

CREATE INDEX IF NOT EXISTS idx_webhooks_tenant
    ON webhook_endpoints (tenant_id, enabled)
    WHERE enabled = TRUE;

ALTER TABLE webhook_endpoints ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_webhooks
    ON webhook_endpoints
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

CREATE TRIGGER trg_webhooks_updated_at
    BEFORE UPDATE ON webhook_endpoints
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 3. Webhook Deliveries (delivery log) ─────────────────────
CREATE TABLE IF NOT EXISTS webhook_deliveries (
    id              BIGSERIAL   PRIMARY KEY,
    webhook_id      TEXT        NOT NULL REFERENCES webhook_endpoints(id) ON DELETE CASCADE,
    event_type      TEXT        NOT NULL,
    payload         JSONB       NOT NULL DEFAULT '{}',
    response_status INTEGER,
    response_body   TEXT,
    duration_ms     INTEGER,
    attempt         INTEGER     NOT NULL DEFAULT 1,
    success         BOOLEAN     NOT NULL DEFAULT FALSE,
    error           TEXT,
    delivered_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook
    ON webhook_deliveries (webhook_id, delivered_at DESC);

CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_failed
    ON webhook_deliveries (webhook_id, success, delivered_at DESC)
    WHERE NOT success;

-- ── 4. API Usage Statistics ───────────────────────────────────
-- مقسمة بالساعة للـ performance
CREATE TABLE IF NOT EXISTS api_usage (
    id          BIGSERIAL   NOT NULL,
    api_key_id  TEXT        NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
    tenant_id   TEXT        NOT NULL,
    endpoint    TEXT        NOT NULL,
    method      TEXT        NOT NULL,
    status_code INTEGER     NOT NULL,
    duration_ms INTEGER     NOT NULL,
    bytes_in    INTEGER     NOT NULL DEFAULT 0,
    bytes_out   INTEGER     NOT NULL DEFAULT 0,
    ip_address  TEXT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (recorded_at);

-- Partitions بالأسبوع — usage data ضخمة
CREATE TABLE IF NOT EXISTS api_usage_2026_w01
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-01-01') TO ('2026-01-08');

CREATE TABLE IF NOT EXISTS api_usage_2026_w02
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-01-08') TO ('2026-01-15');

CREATE TABLE IF NOT EXISTS api_usage_2026_w13
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-03-23') TO ('2026-03-30');

CREATE TABLE IF NOT EXISTS api_usage_2026_w14
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-03-30') TO ('2026-04-06');

CREATE TABLE IF NOT EXISTS api_usage_2026_w15
    PARTITION OF api_usage
    FOR VALUES FROM ('2026-04-06') TO ('2026-04-13');

CREATE TABLE IF NOT EXISTS api_usage_default
    PARTITION OF api_usage DEFAULT;

CREATE INDEX IF NOT EXISTS idx_api_usage_key_time
    ON api_usage (api_key_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_usage_tenant_time
    ON api_usage (tenant_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_usage_endpoint
    ON api_usage (tenant_id, endpoint, recorded_at DESC);

-- ── 5. API Usage Aggregates (hourly rollup للـ dashboards) ───
CREATE TABLE IF NOT EXISTS api_usage_hourly (
    id          BIGSERIAL   PRIMARY KEY,
    api_key_id  TEXT        NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
    tenant_id   TEXT        NOT NULL,
    hour        TIMESTAMPTZ NOT NULL,
    endpoint    TEXT        NOT NULL,
    total_calls BIGINT      NOT NULL DEFAULT 0,
    success_calls BIGINT    NOT NULL DEFAULT 0,
    error_calls BIGINT      NOT NULL DEFAULT 0,
    avg_duration_ms INTEGER NOT NULL DEFAULT 0,
    p99_duration_ms INTEGER NOT NULL DEFAULT 0,
    total_bytes_in  BIGINT  NOT NULL DEFAULT 0,
    total_bytes_out BIGINT  NOT NULL DEFAULT 0,
    UNIQUE (api_key_id, hour, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_api_usage_hourly_key
    ON api_usage_hourly (api_key_id, hour DESC);

CREATE INDEX IF NOT EXISTS idx_api_usage_hourly_tenant
    ON api_usage_hourly (tenant_id, hour DESC);

-- ── 6. Sandbox Events (بيانات test للـ developers) ───────────
CREATE TABLE IF NOT EXISTS sandbox_events (
    id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    tenant_id   TEXT        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    event_type  TEXT        NOT NULL,
    payload     JSONB       NOT NULL DEFAULT '{}',
    processed   BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sandbox_events_tenant
    ON sandbox_events (tenant_id, created_at DESC);

ALTER TABLE sandbox_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_sandbox
    ON sandbox_events
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

-- ── 7. Webhook Allowed Events ────────────────────────────────
-- Reference table للـ events المتاحة
CREATE TABLE IF NOT EXISTS webhook_event_types (
    name        TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    category    TEXT NOT NULL,
    schema      JSONB NOT NULL DEFAULT '{}'
);

INSERT INTO webhook_event_types (name, description, category) VALUES
    ('market.event.ingested',      'New market event ingested',                'markets'),
    ('market.event.processed',     'Market event processed by AI engine',      'markets'),
    ('agent.execution.started',    'AI agent execution started',               'agents'),
    ('agent.execution.completed',  'AI agent execution completed',             'agents'),
    ('agent.execution.failed',     'AI agent execution failed',                'agents'),
    ('billing.subscription.created',  'New subscription created',              'billing'),
    ('billing.subscription.updated',  'Subscription plan changed',             'billing'),
    ('billing.subscription.cancelled','Subscription cancelled',                'billing'),
    ('billing.invoice.paid',          'Invoice payment successful',            'billing'),
    ('billing.invoice.failed',        'Invoice payment failed',                'billing'),
    ('user.created',               'New user added to tenant',                 'users'),
    ('user.role.changed',          'User role changed',                        'users'),
    ('alert.triggered',            'Custom alert triggered',                   'alerts')
ON CONFLICT (name) DO NOTHING;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP POLICY IF EXISTS tenant_isolation_sandbox   ON sandbox_events;
DROP POLICY IF EXISTS tenant_isolation_webhooks  ON webhook_endpoints;

DROP TRIGGER IF EXISTS trg_webhooks_updated_at ON webhook_endpoints;

ALTER TABLE sandbox_events   DISABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_endpoints DISABLE ROW LEVEL SECURITY;

DROP TABLE IF EXISTS webhook_event_types  CASCADE;
DROP TABLE IF EXISTS sandbox_events       CASCADE;
DROP TABLE IF EXISTS api_usage_hourly     CASCADE;
DROP TABLE IF EXISTS api_usage            CASCADE;
DROP TABLE IF EXISTS webhook_deliveries   CASCADE;
DROP TABLE IF EXISTS webhook_endpoints    CASCADE;

ALTER TABLE api_keys
    DROP COLUMN IF EXISTS description,
    DROP COLUMN IF EXISTS environment,
    DROP COLUMN IF EXISTS request_count,
    DROP COLUMN IF EXISTS rate_limit,
    DROP COLUMN IF EXISTS allowed_ips,
    DROP COLUMN IF EXISTS metadata;

-- +goose StatementEnd
