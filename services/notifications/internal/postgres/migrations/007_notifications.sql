-- ============================================================
-- 007_notifications.sql
-- M13 Notifications — in-app + email preferences + audit
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ── 1. Notification Templates ────────────────────────────────
CREATE TABLE IF NOT EXISTS notification_templates (
    id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    name        TEXT        NOT NULL UNIQUE,
    type        TEXT        NOT NULL,
    subject     TEXT,
    body_html   TEXT        NOT NULL,
    body_text   TEXT        NOT NULL,
    variables   TEXT[]      NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_template_type CHECK (
        type IN ('email', 'in_app', 'sms')
    )
);

CREATE TRIGGER trg_notification_templates_updated_at
    BEFORE UPDATE ON notification_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 2. Notification Preferences (per user) ───────────────────
CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id            TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id          TEXT        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email_enabled      BOOLEAN     NOT NULL DEFAULT TRUE,
    in_app_enabled     BOOLEAN     NOT NULL DEFAULT TRUE,
    alert_email        BOOLEAN     NOT NULL DEFAULT TRUE,
    alert_in_app       BOOLEAN     NOT NULL DEFAULT TRUE,
    invoice_email      BOOLEAN     NOT NULL DEFAULT TRUE,
    digest_email       BOOLEAN     NOT NULL DEFAULT TRUE,
    digest_frequency   TEXT        NOT NULL DEFAULT 'weekly',
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, tenant_id),
    CONSTRAINT chk_digest_frequency CHECK (
        digest_frequency IN ('daily', 'weekly', 'never')
    )
);

CREATE INDEX IF NOT EXISTS idx_notif_prefs_tenant
    ON notification_preferences (tenant_id);

CREATE TRIGGER trg_notif_prefs_updated_at
    BEFORE UPDATE ON notification_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 3. In-App Notifications ──────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
    id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    tenant_id   TEXT        NOT NULL CHECK (tenant_id <> ''),
    user_id     TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type        TEXT        NOT NULL,
    title       TEXT        NOT NULL,
    body        TEXT        NOT NULL,
    data        JSONB       NOT NULL DEFAULT '{}',
    read        BOOLEAN     NOT NULL DEFAULT FALSE,
    read_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_notification_type CHECK (
        type IN (
            'alert', 'invoice', 'subscription',
            'system', 'welcome', 'digest'
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON notifications (user_id, created_at DESC)
    WHERE NOT read;

CREATE INDEX IF NOT EXISTS idx_notifications_tenant
    ON notifications (tenant_id, created_at DESC);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_notifications
    ON notifications
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

-- ── 4. Email Log (audit trail) ───────────────────────────────
CREATE TABLE IF NOT EXISTS email_log (
    id              BIGSERIAL   PRIMARY KEY,
    tenant_id       TEXT,
    user_id         TEXT        REFERENCES users(id),
    resend_id       TEXT        UNIQUE,
    template_name   TEXT        NOT NULL,
    to_email        TEXT        NOT NULL,
    subject         TEXT        NOT NULL,
    status          TEXT        NOT NULL DEFAULT 'sent',
    error           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_email_status CHECK (
        status IN ('sent', 'delivered', 'bounced', 'failed')
    )
);

CREATE INDEX IF NOT EXISTS idx_email_log_tenant
    ON email_log (tenant_id, created_at DESC)
    WHERE tenant_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_email_log_user
    ON email_log (user_id, created_at DESC)
    WHERE user_id IS NOT NULL;

-- ── 5. Seed: Default Templates ────────────────────────────────
INSERT INTO notification_templates (name, type, subject, body_html, body_text, variables) VALUES
(
    'welcome',
    'email',
    'Welcome to youtuop — Your financial intelligence platform',
    '<h1>Welcome {{.FirstName}}!</h1><p>Your account on <strong>{{.TenantName}}</strong> is ready.</p><p>You are on the <strong>{{.Plan}}</strong> plan with a 14-day free trial.</p>',
    'Welcome {{.FirstName}}! Your account on {{.TenantName}} is ready. You are on the {{.Plan}} plan with a 14-day free trial.',
    ARRAY['FirstName', 'TenantName', 'Plan']
),
(
    'invoice_paid',
    'email',
    'Invoice {{.InvoiceID}} — Payment confirmed',
    '<h2>Payment Confirmed</h2><p>Amount: <strong>{{.Amount}} {{.Currency}}</strong></p><p><a href="{{.InvoiceURL}}">View Invoice</a></p>',
    'Payment confirmed. Amount: {{.Amount}} {{.Currency}}. View invoice: {{.InvoiceURL}}',
    ARRAY['InvoiceID', 'Amount', 'Currency', 'InvoiceURL']
),
(
    'invoice_failed',
    'email',
    'Action required — Payment failed for {{.TenantName}}',
    '<h2>Payment Failed</h2><p>We could not process your payment of <strong>{{.Amount}} {{.Currency}}</strong>.</p><p><a href="{{.PortalURL}}">Update Payment Method</a></p>',
    'Payment failed. Amount: {{.Amount}} {{.Currency}}. Update payment: {{.PortalURL}}',
    ARRAY['TenantName', 'Amount', 'Currency', 'PortalURL']
),
(
    'subscription_cancelled',
    'email',
    'Your youtuop subscription has been cancelled',
    '<h2>Subscription Cancelled</h2><p>Your subscription will end on <strong>{{.EndDate}}</strong>. You can reactivate anytime.</p>',
    'Your subscription will end on {{.EndDate}}. You can reactivate anytime.',
    ARRAY['EndDate']
),
(
    'alert_triggered',
    'in_app',
    NULL,
    '',
    'Alert triggered: {{.AlertName}} — {{.Message}}',
    ARRAY['AlertName', 'Message', 'Severity']
),
(
    'weekly_digest',
    'email',
    'Your weekly summary — {{.TenantName}}',
    '<h2>Weekly Summary</h2><p>Events processed: <strong>{{.EventCount}}</strong></p><p>API calls: <strong>{{.APICalls}}</strong></p>',
    'Weekly Summary. Events: {{.EventCount}}. API calls: {{.APICalls}}.',
    ARRAY['TenantName', 'EventCount', 'APICalls', 'PeriodStart', 'PeriodEnd']
)
ON CONFLICT (name) DO NOTHING;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TRIGGER IF EXISTS trg_notif_prefs_updated_at        ON notification_preferences;
DROP TRIGGER IF EXISTS trg_notification_templates_updated_at ON notification_templates;

DROP POLICY IF EXISTS tenant_isolation_notifications ON notifications;
ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;

DROP TABLE IF EXISTS email_log                  CASCADE;
DROP TABLE IF EXISTS notifications              CASCADE;
DROP TABLE IF EXISTS notification_preferences   CASCADE;
DROP TABLE IF EXISTS notification_templates     CASCADE;

-- +goose StatementEnd
