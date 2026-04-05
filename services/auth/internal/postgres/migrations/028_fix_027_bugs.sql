-- ============================================================
-- services/auth/internal/postgres/migrations/028_fix_027_bugs.sql
-- Scope: auth service database only — independent migration sequence
-- Global numbering reflects creation order across all services
--
-- Fixes bugs introduced in migration 027_fix_constraints_and_bugs.sql:
--
--   Bug 1 (F-SQL15): 027 UPDATE had impossible WHERE condition
--          '"""live"""'::jsonb never existed — seed in 010 already
--          stores '"live"'::jsonb which is correct JSONB string 'live'.
--          Fix: UPDATE with correct WHERE to fix any bad values,
--               then document that seed is already correct.
--
--   Bug 2 (F-SQL14): 027 sync_tenant_plan() correct API is NEW.plan_id
--          + SET tier — matching 026 which properly handles post-023
--          rename. But 027 added RAISE EXCEPTION on NULL which breaks
--          Stripe webhook processing when unknown plan_id arrives.
--          Fix: Keep NEW.plan_id + SET tier (correct post-023 API),
--               replace RAISE EXCEPTION with RAISE WARNING + LOG.
--
--   Bug 3: idx_agents_tenant redundant — IF NOT EXISTS in 027 already
--          prevented error. No SQL action needed, documented only.
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- Bug 1: F-SQL15 — 027 UPDATE stripe_mode had impossible condition.
-- The WHERE clause matched '"""live"""'::jsonb which can never exist.
-- Correct fix: if bad double-quoted value somehow exists, fix it.
-- The seed in 010_control_plane.sql stores '"live"' which PostgreSQL
-- parses as JSONB string "live" — this is already the correct value.
-- We add a defensive UPDATE targeting the actual wrong value pattern.
-- ════════════════════════════════════════════════════════════════════
UPDATE system_config
    SET value = '"live"'::jsonb
    WHERE key   = 'billing.stripe_mode'
      AND value::text NOT IN ('"live"', '"test"');

-- ════════════════════════════════════════════════════════════════════
-- Bug 2: F-SQL14 — 027 sync_tenant_plan() added RAISE EXCEPTION
-- on unknown plan_id. This breaks Stripe webhook processing when
-- Stripe sends a plan_id not yet in our mapping (e.g., new plans,
-- grandfathered plans, coupon plans). RAISE EXCEPTION inside a
-- trigger causes the entire transaction to roll back, meaning the
-- webhook event is lost with no retry possible.
--
-- Correct behaviour (per F-SQL14 spec):
--   - Unknown plan_id → RAISE WARNING (logged) + leave tier unchanged
--   - API: NEW.plan_id (correct post-023) + SET tier (post-023 rename)
--   - Handles all subscription statuses from chk_subscription_status
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
            -- Unknown plan_id from Stripe: log warning, do NOT fail.
            -- Tier remains unchanged — ops team investigates via logs.
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
        -- Degraded billing state → downgrade to basic tier
        UPDATE tenants
           SET tier       = 'basic',
               updated_at = NOW()
         WHERE id = NEW.tenant_id;

    END IF;
    -- 'incomplete' status: do nothing — subscription not yet confirmed
    RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════════════
-- Bug 3: idx_agents_tenant redundant in 027.
-- Created in 021_agent_identity.sql line 29 with IF NOT EXISTS.
-- 027 line 101 also used IF NOT EXISTS — no error, no duplicate index.
-- No SQL action needed. Documented here for audit trail.
-- ════════════════════════════════════════════════════════════════════

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- ── Reverse Bug 2: restore 027 version of sync_tenant_plan ──────────
-- Note: restores the RAISE EXCEPTION behaviour of 027 for rollback.
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

-- ── Reverse Bug 1: restore stripe_mode to pre-028 state ─────────────
-- 027 UPDATE was a no-op (impossible condition), so there is nothing
-- to undo. The value '"live"'::jsonb remains correct after rollback.

-- +goose StatementEnd
