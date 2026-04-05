-- ============================================================
-- services/auth/internal/postgres/migrations/027_fix_constraints_and_bugs.sql
-- Scope: auth service database only — independent migration sequence
--
-- Fixes:
--   F-SQL09: failed_login_attempts missing index on attempted_at
--   F-SQL11: write_audit() without explicit schema prefix
--   F-SQL14: sync_tenant_plan() fails on unknown plan_id from Stripe
--   F-SQL15: SKIPPED — system_config table doesn't exist yet
--   F-SQL22: cron_jobs.schedule TEXT without cron format validation
--   F-SQL24: agents table missing tenant_id index for RLS queries
--   F-SQL28: S3 bucket hardcoded in ml_models seed data
--   F-SQL31: background_job_logs missing index on (job_id, attempt)
--   F-SQL37: search_queries.query_text without size limit (DoS vector)
--   F-SQL39: analytics_events.properties JSONB without size limit
--   F-SQL42: search_indices.index_type without CHECK constraint
--   F-SQL43: analytics_funnel_results missing UNIQUE constraint
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL09: failed_login_attempts missing index on attempted_at.
-- ════════════════════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_failed_attempts_time
    ON failed_login_attempts (attempted_at DESC);

-- ════════════════════════════════════════════════════════════════════
-- F-SQL11: write_audit() function inserts to audit_log without
--          explicit schema prefix.
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION write_audit(
    p_tenant_id   TEXT,
    p_user_id     TEXT,
    p_action      TEXT,
    p_resource    TEXT,
    p_resource_id TEXT DEFAULT NULL,
    p_old_data    JSONB DEFAULT NULL,
    p_new_data    JSONB DEFAULT NULL,
    p_ip_address  TEXT DEFAULT NULL,
    p_trace_id    TEXT DEFAULT NULL,
    p_status      TEXT DEFAULT 'success',
    p_error       TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.audit_log (
        tenant_id, user_id, action, resource, resource_id,
        old_data, new_data, ip_address, trace_id, status, error
    ) VALUES (
        p_tenant_id, p_user_id, p_action, p_resource, p_resource_id,
        p_old_data, p_new_data, p_ip_address, p_trace_id, p_status, p_error
    );
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'write_audit failed: %', SQLERRM;
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- F-SQL14: sync_tenant_plan() with ELSE NULL to catch unknown plan_ids
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION sync_tenant_plan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'active' THEN
        UPDATE tenants
        SET tier = CASE NEW.plan_id
            WHEN 'plan_basic'      THEN 'basic'
            WHEN 'plan_pro'        THEN 'pro'
            WHEN 'plan_enterprise' THEN 'enterprise'
            ELSE NULL
        END
        WHERE id = NEW.tenant_id;
        
        IF NOT FOUND OR (SELECT tier FROM tenants WHERE id = NEW.tenant_id) IS NULL THEN
            RAISE EXCEPTION 'Unknown plan_id: % for tenant: %', NEW.plan_id, NEW.tenant_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- F-SQL15: SKIPPED — system_config table doesn't exist yet
--
-- Original fix: UPDATE system_config SET value = '"live"'::jsonb
--               WHERE key = 'billing.stripe_mode' 
--                 AND value = '"""live"""'::jsonb;
--
-- Table not created in migrations 004-026. Deferred until table exists.
-- ════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════
-- F-SQL22: cron_jobs.schedule validation
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE cron_jobs
    ADD CONSTRAINT chk_cron_schedule
    CHECK (schedule ~ '^(\*|\d+|\d+-\d+|\*/\d+)(\s+(\*|\d+|\d+-\d+|\*/\d+)){4}(\s+(\*|\d+|\d+-\d+|\*/\d+))?$');

-- ════════════════════════════════════════════════════════════════════
-- F-SQL24: agents table missing tenant_id index
-- ════════════════════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_agents_tenant
    ON agents (tenant_id);

-- ════════════════════════════════════════════════════════════════════
-- F-SQL28: S3 bucket hardcoded in ml_models seed data
-- ════════════════════════════════════════════════════════════════════
UPDATE ml_models
SET artifact_path = REPLACE(
    artifact_path,
    's3://platform-ml-artifacts',
    COALESCE(current_setting('app.s3_bucket', true), 's3://platform-ml-artifacts')
)
WHERE artifact_path LIKE 's3://platform-ml-artifacts%';

-- ════════════════════════════════════════════════════════════════════
-- F-SQL31: background_job_logs missing index on (job_id, attempt)
-- ════════════════════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_background_job_logs_job_attempt
    ON background_job_logs (job_id, attempt DESC);

-- ════════════════════════════════════════════════════════════════════
-- F-SQL37: search_queries.query_text without size limit (DoS vector)
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE search_queries
    ADD CONSTRAINT chk_query_text_size
    CHECK (length(query_text) <= 10240);

-- ════════════════════════════════════════════════════════════════════
-- F-SQL39: analytics_events.properties JSONB without size limit
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE analytics_events
    ADD CONSTRAINT chk_properties_size
    CHECK (length(properties::text) <= 102400);

-- ════════════════════════════════════════════════════════════════════
-- F-SQL42: search_indices.index_type without CHECK constraint
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE search_indices
    ADD CONSTRAINT chk_index_type
    CHECK (index_type IN ('semantic', 'keyword', 'hybrid'));

-- ════════════════════════════════════════════════════════════════════
-- F-SQL43: analytics_funnel_results missing UNIQUE constraint
-- ════════════════════════════════════════════════════════════════════
ALTER TABLE analytics_funnel_results
    ADD CONSTRAINT uq_funnel_results_unique
    UNIQUE (funnel_id, cohort_date, step_index);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

ALTER TABLE analytics_funnel_results DROP CONSTRAINT IF EXISTS uq_funnel_results_unique;
ALTER TABLE search_indices DROP CONSTRAINT IF EXISTS chk_index_type;
ALTER TABLE analytics_events DROP CONSTRAINT IF EXISTS chk_properties_size;
ALTER TABLE search_queries DROP CONSTRAINT IF EXISTS chk_query_text_size;
DROP INDEX IF EXISTS idx_background_job_logs_job_attempt;
DROP INDEX IF EXISTS idx_agents_tenant;
ALTER TABLE cron_jobs DROP CONSTRAINT IF EXISTS chk_cron_schedule;
DROP INDEX IF EXISTS idx_failed_attempts_time;

-- Reverse F-SQL28: restore original hardcoded path
UPDATE ml_models
SET artifact_path = REPLACE(
    artifact_path,
    COALESCE(current_setting('app.s3_bucket', true), 's3://platform-ml-artifacts'),
    's3://platform-ml-artifacts'
)
WHERE artifact_path NOT LIKE 's3://platform-ml-artifacts%';

-- Reverse F-SQL14 & F-SQL11: restore original functions
CREATE OR REPLACE FUNCTION sync_tenant_plan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'active' THEN
        UPDATE tenants
        SET tier = CASE NEW.plan_id
            WHEN 'plan_basic'      THEN 'basic'
            WHEN 'plan_pro'        THEN 'pro'
            WHEN 'plan_enterprise' THEN 'enterprise'
        END
        WHERE id = NEW.tenant_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION write_audit(
    p_tenant_id   TEXT,
    p_user_id     TEXT,
    p_action      TEXT,
    p_resource    TEXT,
    p_resource_id TEXT DEFAULT NULL,
    p_old_data    JSONB DEFAULT NULL,
    p_new_data    JSONB DEFAULT NULL,
    p_ip_address  TEXT DEFAULT NULL,
    p_trace_id    TEXT DEFAULT NULL,
    p_status      TEXT DEFAULT 'success',
    p_error       TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO audit_log (
        tenant_id, user_id, action, resource, resource_id,
        old_data, new_data, ip_address, trace_id, status, error
    ) VALUES (
        p_tenant_id, p_user_id, p_action, p_resource, p_resource_id,
        p_old_data, p_new_data, p_ip_address, p_trace_id, p_status, p_error
    );
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'write_audit failed: %', SQLERRM;
END;
$$;

-- +goose StatementEnd
