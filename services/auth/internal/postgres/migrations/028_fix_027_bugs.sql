-- ============================================================
-- services/auth/internal/postgres/migrations/028_fix_027_bugs.sql
-- Scope: auth service database only — independent migration sequence
--
-- Fixes bugs introduced in migration 027_fix_constraints_and_bugs.sql:
--
--   Bug 1 (F-SQL15): SKIPPED — system_config table doesn't exist yet
--
--   Bug 2 (F-SQL14): 027 sync_tenant_plan() added RAISE EXCEPTION
--          on unknown plan_id which breaks Stripe webhooks. Replace
--          with RAISE WARNING to log issue without failing transaction.
--
--   Bug 3: idx_agents_tenant redundant — IF NOT EXISTS in 027 already
--          prevented error. No SQL action needed, documented only.
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- Bug 1: F-SQL15 — SKIPPED
--
-- Original fix: UPDATE system_config SET value = '"live"'::jsonb
--               WHERE key = 'billing.stripe_mode'
--                 AND value::text NOT IN ('"live"', '"test"');
--
-- Table not created in migrations 004-027. Deferred until table exists.
-- ════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════
-- Bug 2: F-SQL14 — 027 sync_tenant_plan() added RAISE EXCEPTION
-- on unknown plan_id. This breaks Stripe webhook processing.
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION sync_tenant_plan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_new_tier TEXT;
BEGIN
    IF NEW.status IN ('active', 'trialing') THEN
        v_new_tier := CASE NEW.plan_id
            WHEN 'plan_basic'      THEN 'basic'
            WHEN 'plan_pro'        THEN 'pro'
            WHEN 'plan_business'   THEN 'pro'
            WHEN 'plan_enterprise' THEN 'enterprise'
            ELSE NULL
        END;

        IF v_new_tier IS NULL THEN
            RAISE WARNING
                'sync_tenant_plan: unknown plan_id=% for tenant=% subscription=% — tier unchanged',
                NEW.plan_id, NEW.tenant_id, NEW.id;
        ELSE
            UPDATE tenants
               SET tier       = v_new_tier,
                   updated_at = NOW()
             WHERE id = NEW.tenant_id;
        END IF;

    ELSIF NEW.status IN ('cancelled', 'unpaid', 'past_due') THEN
        UPDATE tenants
           SET tier       = 'basic',
               updated_at = NOW()
         WHERE id = NEW.tenant_id;

    END IF;
    RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- Bug 3: idx_agents_tenant redundant — documented only, no action.
-- ════════════════════════════════════════════════════════════════════

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- ── Reverse Bug 2: restore 027 version ──────────────────────────────
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

        IF NOT FOUND OR
           (SELECT tier FROM tenants WHERE id = NEW.tenant_id) IS NULL
        THEN
            RAISE EXCEPTION
                'Unknown plan_id: % for tenant: %',
                NEW.plan_id, NEW.tenant_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- +goose StatementEnd
