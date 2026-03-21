-- ============================================================
-- 006_billing.sql
-- M12 Billing & Subscriptions
-- يبني فوق tenants table الموجودة في 004
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ── 1. Stripe Customer ID على الـ tenants ───────────────────
ALTER TABLE tenants
    ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT UNIQUE,
    ADD COLUMN IF NOT EXISTS billing_email      TEXT;

-- ── 2. Subscriptions ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS subscriptions (
    id                     TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    tenant_id              TEXT        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    stripe_subscription_id TEXT        UNIQUE,
    stripe_price_id        TEXT,
    plan                   TEXT        NOT NULL,
    status                 TEXT        NOT NULL DEFAULT 'trialing',
    current_period_start   TIMESTAMPTZ,
    current_period_end     TIMESTAMPTZ,
    cancel_at_period_end   BOOLEAN     NOT NULL DEFAULT FALSE,
    cancelled_at           TIMESTAMPTZ,
    trial_start            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    trial_end              TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '14 days',
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_subscription_status CHECK (
        status IN ('trialing', 'active', 'past_due', 'cancelled', 'unpaid', 'incomplete')
    ),
    CONSTRAINT chk_subscription_plan CHECK (
        plan IN ('basic', 'pro', 'business', 'enterprise')
    )
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_tenant
    ON subscriptions (tenant_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe
    ON subscriptions (stripe_subscription_id)
    WHERE stripe_subscription_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_subscriptions_status
    ON subscriptions (status, current_period_end);

-- ── 3. Invoices ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invoices (
    id                  TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    tenant_id           TEXT        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    subscription_id     TEXT        REFERENCES subscriptions(id),
    stripe_invoice_id   TEXT        UNIQUE,
    amount_due          INTEGER     NOT NULL DEFAULT 0,  -- بالـ cents
    amount_paid         INTEGER     NOT NULL DEFAULT 0,
    currency            TEXT        NOT NULL DEFAULT 'usd',
    status              TEXT        NOT NULL DEFAULT 'draft',
    invoice_pdf         TEXT,
    hosted_invoice_url  TEXT,
    period_start        TIMESTAMPTZ,
    period_end          TIMESTAMPTZ,
    due_date            TIMESTAMPTZ,
    paid_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_invoice_status CHECK (
        status IN ('draft', 'open', 'paid', 'void', 'uncollectible')
    ),
    CONSTRAINT chk_invoice_amounts CHECK (
        amount_due >= 0 AND amount_paid >= 0
    )
);

CREATE INDEX IF NOT EXISTS idx_invoices_tenant
    ON invoices (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_stripe
    ON invoices (stripe_invoice_id)
    WHERE stripe_invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_invoices_status
    ON invoices (status, tenant_id);

-- ── 4. Usage Records (usage-based billing) ──────────────────
CREATE TABLE IF NOT EXISTS usage_records (
    id              BIGSERIAL   PRIMARY KEY,
    tenant_id       TEXT        NOT NULL CHECK (tenant_id <> ''),
    subscription_id TEXT        REFERENCES subscriptions(id),
    metric          TEXT        NOT NULL,  -- api_calls, agents_executed, data_gb
    quantity        BIGINT      NOT NULL DEFAULT 0,
    period_start    TIMESTAMPTZ NOT NULL,
    period_end      TIMESTAMPTZ NOT NULL,
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_usage_metric CHECK (
        metric IN ('api_calls', 'agents_executed', 'data_gb', 'market_streams')
    ),
    CONSTRAINT chk_usage_quantity CHECK (quantity >= 0),
    CONSTRAINT chk_usage_period   CHECK (period_start < period_end)
);

CREATE INDEX IF NOT EXISTS idx_usage_tenant_period
    ON usage_records (tenant_id, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_usage_metric
    ON usage_records (tenant_id, metric, period_start DESC);

-- ── 5. Payment Methods ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_methods (
    id                      TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    tenant_id               TEXT        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    stripe_payment_method_id TEXT       NOT NULL UNIQUE,
    type                    TEXT        NOT NULL DEFAULT 'card',
    card_brand              TEXT,
    card_last4              TEXT,
    card_exp_month          INTEGER,
    card_exp_year           INTEGER,
    is_default              BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_payment_type CHECK (type IN ('card', 'bank_transfer', 'sepa_debit'))
);

CREATE INDEX IF NOT EXISTS idx_payment_methods_tenant
    ON payment_methods (tenant_id);

-- ── 6. Billing Events (audit trail للـ webhook events) ───────
CREATE TABLE IF NOT EXISTS billing_events (
    id               BIGSERIAL   PRIMARY KEY,
    tenant_id        TEXT,
    stripe_event_id  TEXT        NOT NULL UNIQUE,
    event_type       TEXT        NOT NULL,
    payload          JSONB       NOT NULL DEFAULT '{}',
    processed        BOOLEAN     NOT NULL DEFAULT FALSE,
    processed_at     TIMESTAMPTZ,
    error            TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_billing_events_tenant
    ON billing_events (tenant_id, created_at DESC)
    WHERE tenant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_billing_events_unprocessed
    ON billing_events (processed, created_at)
    WHERE NOT processed;

-- ── 7. RLS ──────────────────────────────────────────────────
ALTER TABLE subscriptions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices        ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_records   ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_subscriptions
    ON subscriptions
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

CREATE POLICY tenant_isolation_invoices
    ON invoices
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

CREATE POLICY tenant_isolation_usage_records
    ON usage_records
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

CREATE POLICY tenant_isolation_payment_methods
    ON payment_methods
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

-- ── 8. Triggers ─────────────────────────────────────────────
CREATE TRIGGER trg_subscriptions_updated_at
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 9. تحديث الـ tenants plan تلقائياً من الـ subscription ──
CREATE OR REPLACE FUNCTION sync_tenant_plan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status IN ('active', 'trialing') THEN
        UPDATE tenants
        SET plan       = NEW.plan,
            updated_at = NOW()
        WHERE id = NEW.tenant_id;
    ELSIF NEW.status IN ('cancelled', 'unpaid') THEN
        UPDATE tenants
        SET plan       = 'basic',
            updated_at = NOW()
        WHERE id = NEW.tenant_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_tenant_plan
    AFTER INSERT OR UPDATE OF status, plan ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION sync_tenant_plan();

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TRIGGER IF EXISTS trg_sync_tenant_plan        ON subscriptions;
DROP TRIGGER IF EXISTS trg_subscriptions_updated_at ON subscriptions;
DROP FUNCTION IF EXISTS sync_tenant_plan();

DROP POLICY IF EXISTS tenant_isolation_payment_methods ON payment_methods;
DROP POLICY IF EXISTS tenant_isolation_usage_records   ON usage_records;
DROP POLICY IF EXISTS tenant_isolation_invoices        ON invoices;
DROP POLICY IF EXISTS tenant_isolation_subscriptions   ON subscriptions;

ALTER TABLE payment_methods DISABLE ROW LEVEL SECURITY;
ALTER TABLE usage_records   DISABLE ROW LEVEL SECURITY;
ALTER TABLE invoices        DISABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions   DISABLE ROW LEVEL SECURITY;

DROP TABLE IF EXISTS billing_events   CASCADE;
DROP TABLE IF EXISTS payment_methods  CASCADE;
DROP TABLE IF EXISTS usage_records    CASCADE;
DROP TABLE IF EXISTS invoices         CASCADE;
DROP TABLE IF EXISTS subscriptions    CASCADE;

ALTER TABLE tenants
    DROP COLUMN IF EXISTS stripe_customer_id,
    DROP COLUMN IF EXISTS billing_email;

-- +goose StatementEnd
