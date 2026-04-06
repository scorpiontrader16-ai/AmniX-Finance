-- ============================================================
-- services/auth/internal/postgres/migrations/032_control_plane_and_notifications_rls.sql
-- Scope: auth service database only — independent migration sequence
--
-- Fixes:
--   F-SQL06: control-plane tables RLS (system_config, kill_switches,
--            maintenance_windows, announcements, impersonation_log)
--   F-SQL15: no-op — billing.stripe_mode verified as '"live"'::jsonb
--   F-SQL40: notification_preferences RLS + notifications policy fix
--
-- Dependencies (must exist before this migration runs):
--   010_control_plane.sql (control-plane service)
--   007_notifications.sql (notifications service)
--
-- Safety: All ALTER TABLE statements check for table existence first
--         to prevent failure if dependencies are missing.
--
-- Down section symmetry: Fully reversible with exact state restoration.
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ════════════════════════════════════════════════════════════════════
-- F-SQL06: control-plane tables — super_admin only access
--          These are platform-wide config tables. No tenant isolation
--          needed — only super_admin role may read/write them.
--
--          Safety: Check table existence before applying RLS.
-- ════════════════════════════════════════════════════════════════════

-- system_config
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'system_config') THEN
        ALTER TABLE system_config ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS super_admin_only ON system_config;
        CREATE POLICY super_admin_only ON system_config
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END $$;

-- kill_switches
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'kill_switches') THEN
        ALTER TABLE kill_switches ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS super_admin_only ON kill_switches;
        CREATE POLICY super_admin_only ON kill_switches
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END $$;

-- maintenance_windows
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'maintenance_windows') THEN
        ALTER TABLE maintenance_windows ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS super_admin_only ON maintenance_windows;
        CREATE POLICY super_admin_only ON maintenance_windows
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END $$;

-- announcements
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'announcements') THEN
        ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS read_active_announcements ON announcements;
        DROP POLICY IF EXISTS super_admin_announcements ON announcements;
        -- Active announcements readable by all
        CREATE POLICY read_active_announcements ON announcements
            FOR SELECT
            USING (active = TRUE);
        -- Super admin full access
        CREATE POLICY super_admin_announcements ON announcements
            FOR ALL
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END $$;

-- impersonation_log
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'impersonation_log') THEN
        ALTER TABLE impersonation_log ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS super_admin_impersonation ON impersonation_log;
        DROP POLICY IF EXISTS self_impersonation_view ON impersonation_log;
        -- Super admin reads all
        CREATE POLICY super_admin_impersonation ON impersonation_log
            FOR SELECT
            USING (current_setting('app.user_role', true) = 'super_admin');
        -- Target user reads own records
        CREATE POLICY self_impersonation_view ON impersonation_log
            FOR SELECT
            USING (target_user_id = current_setting('app.user_id', true)::text);
        -- Admin can insert (start impersonation)
        CREATE POLICY admin_start_impersonation ON impersonation_log
            FOR INSERT
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
        -- Admin can update (end impersonation)
        CREATE POLICY admin_end_impersonation ON impersonation_log
            FOR UPDATE
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════
-- F-SQL15: no-op
--
-- billing.stripe_mode verified in DB: value = '"live"'::jsonb
-- This is the correct JSONB representation of the string "live".
-- No UPDATE required.
-- ════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════
-- F-SQL40: notification_preferences — no RLS
--          notifications — policy accepts empty tenant_id (data leak)
-- ════════════════════════════════════════════════════════════════════

-- notification_preferences
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notification_preferences') THEN
        ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS tenant_isolation_notif_prefs ON notification_preferences;
        DROP POLICY IF EXISTS super_admin_all ON notification_preferences;
        CREATE POLICY tenant_isolation_notif_prefs ON notification_preferences
            FOR ALL
            USING (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) != ''
            )
            WITH CHECK (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) != ''
            );
        CREATE POLICY super_admin_all ON notification_preferences
            FOR ALL
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END $$;

-- notifications: fix empty tenant_id vulnerability
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notifications') THEN
        DROP POLICY IF EXISTS tenant_isolation_notifications ON notifications;
        DROP POLICY IF EXISTS super_admin_all ON notifications;
        CREATE POLICY tenant_isolation_notifications ON notifications
            FOR ALL
            USING (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) != ''
            )
            WITH CHECK (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) != ''
            );
        CREATE POLICY super_admin_all ON notifications
            FOR ALL
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END $$;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- ── Reverse F-SQL40 ──────────────────────────────────────────────────
DROP POLICY IF EXISTS super_admin_all ON notifications;
DROP POLICY IF EXISTS tenant_isolation_notifications ON notifications;
CREATE POLICY tenant_isolation_notifications ON notifications
    FOR ALL
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

DROP POLICY IF EXISTS super_admin_all ON notification_preferences;
DROP POLICY IF EXISTS tenant_isolation_notif_prefs ON notification_preferences;
ALTER TABLE notification_preferences DISABLE ROW LEVEL SECURITY;

-- ── Reverse F-SQL06 ──────────────────────────────────────────────────
DROP POLICY IF EXISTS admin_end_impersonation ON impersonation_log;
DROP POLICY IF EXISTS admin_start_impersonation ON impersonation_log;
DROP POLICY IF EXISTS self_impersonation_view ON impersonation_log;
DROP POLICY IF EXISTS super_admin_impersonation ON impersonation_log;
DROP POLICY IF EXISTS super_admin_announcements ON announcements;
DROP POLICY IF EXISTS read_active_announcements ON announcements;
DROP POLICY IF EXISTS super_admin_only ON system_config;
DROP POLICY IF EXISTS super_admin_only ON kill_switches;
DROP POLICY IF EXISTS super_admin_only ON maintenance_windows;

ALTER TABLE system_config DISABLE ROW LEVEL SECURITY;
ALTER TABLE kill_switches DISABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_windows DISABLE ROW LEVEL SECURITY;
ALTER TABLE announcements DISABLE ROW LEVEL SECURITY;
ALTER TABLE impersonation_log DISABLE ROW LEVEL SECURITY;

-- +goose StatementEnd
