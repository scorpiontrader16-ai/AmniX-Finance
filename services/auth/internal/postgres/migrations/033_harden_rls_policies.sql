-- ============================================================
-- services/auth/internal/postgres/migrations/033_harden_rls_policies.sql
-- Scope: auth service database only — independent migration sequence
--
-- Fixes:
--   Hardening pass for existing RLS policies applied in 032.
--
-- Goals:
--   1. Replace overly broad ALL policies with command-specific policies
--      where appropriate.
--   2. Add explicit WITH CHECK clauses for INSERT/UPDATE safety.
--   3. Guard all operations by table existence to avoid dependency
--      failure on environments where cross-service tables are absent.
--
-- Tables affected:
--   announcements
--   impersonation_log
--   notification_preferences
--   notifications
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- announcements
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'announcements'
    ) THEN
        DROP POLICY IF EXISTS read_active_announcements ON announcements;
        DROP POLICY IF EXISTS super_admin_announcements ON announcements;

        CREATE POLICY read_active_announcements ON announcements
            FOR SELECT
            USING (active = TRUE);

        CREATE POLICY super_admin_announcements ON announcements
            FOR ALL
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END
$$;

-- impersonation_log
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'impersonation_log'
    ) THEN
        DROP POLICY IF EXISTS super_admin_impersonation ON impersonation_log;
        DROP POLICY IF EXISTS self_impersonation_view ON impersonation_log;
        DROP POLICY IF EXISTS admin_start_impersonation ON impersonation_log;
        DROP POLICY IF EXISTS admin_end_impersonation ON impersonation_log;

        CREATE POLICY super_admin_impersonation ON impersonation_log
            FOR SELECT
            USING (current_setting('app.user_role', true) = 'super_admin');

        CREATE POLICY self_impersonation_view ON impersonation_log
            FOR SELECT
            USING (target_user_id = current_setting('app.user_id', true)::text);

        CREATE POLICY admin_start_impersonation ON impersonation_log
            FOR INSERT
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');

        CREATE POLICY admin_end_impersonation ON impersonation_log
            FOR UPDATE
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END
$$;

-- notification_preferences
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'notification_preferences'
    ) THEN
        DROP POLICY IF EXISTS tenant_isolation_notif_prefs ON notification_preferences;
        DROP POLICY IF EXISTS super_admin_all ON notification_preferences;

        CREATE POLICY tenant_isolation_notif_prefs ON notification_preferences
            FOR ALL
            USING (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) <> ''
            )
            WITH CHECK (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) <> ''
            );

        CREATE POLICY super_admin_all ON notification_preferences
            FOR ALL
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END
$$;

-- notifications
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'notifications'
    ) THEN
        DROP POLICY IF EXISTS tenant_isolation_notifications ON notifications;
        DROP POLICY IF EXISTS super_admin_all ON notifications;

        CREATE POLICY tenant_isolation_notifications ON notifications
            FOR ALL
            USING (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) <> ''
            )
            WITH CHECK (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) <> ''
            );

        CREATE POLICY super_admin_all ON notifications
            FOR ALL
            USING (current_setting('app.user_role', true) = 'super_admin')
            WITH CHECK (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END
$$;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

-- announcements
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'announcements'
    ) THEN
        DROP POLICY IF EXISTS super_admin_announcements ON announcements;
        DROP POLICY IF EXISTS read_active_announcements ON announcements;

        CREATE POLICY read_active_announcements ON announcements
            USING (
                active = TRUE
                OR current_setting('app.user_role', true) = 'super_admin'
            );
    END IF;
END
$$;

-- impersonation_log
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'impersonation_log'
    ) THEN
        DROP POLICY IF EXISTS admin_end_impersonation ON impersonation_log;
        DROP POLICY IF EXISTS admin_start_impersonation ON impersonation_log;
        DROP POLICY IF EXISTS self_impersonation_view ON impersonation_log;
        DROP POLICY IF EXISTS super_admin_impersonation ON impersonation_log;

        CREATE POLICY super_admin_impersonation ON impersonation_log
            USING (current_setting('app.user_role', true) = 'super_admin');

        CREATE POLICY self_impersonation_view ON impersonation_log
            USING (target_user_id = current_setting('app.user_id', true)::text);
    END IF;
END
$$;

-- notification_preferences
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'notification_preferences'
    ) THEN
        DROP POLICY IF EXISTS super_admin_all ON notification_preferences;
        DROP POLICY IF EXISTS tenant_isolation_notif_prefs ON notification_preferences;

        CREATE POLICY tenant_isolation_notif_prefs ON notification_preferences
            USING (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) <> ''
            );

        CREATE POLICY super_admin_all ON notification_preferences
            USING (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END
$$;

-- notifications
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'notifications'
    ) THEN
        DROP POLICY IF EXISTS super_admin_all ON notifications;
        DROP POLICY IF EXISTS tenant_isolation_notifications ON notifications;

        CREATE POLICY tenant_isolation_notifications ON notifications
            USING (
                tenant_id = current_setting('app.tenant_id', true)::text
                AND current_setting('app.tenant_id', true) <> ''
            );

        CREATE POLICY super_admin_all ON notifications
            USING (current_setting('app.user_role', true) = 'super_admin');
    END IF;
END
$$;

-- +goose StatementEnd
