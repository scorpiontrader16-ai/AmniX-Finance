-- ============================================================
-- services/auth/internal/postgres/migrations/020_rls_warm_events.sql
-- Scope: auth service database only — independent migration sequence
-- ============================================================
-- +goose Up
-- +goose StatementBegin

ALTER TABLE warm_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE tiering_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE schema_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_warm_events ON warm_events
    USING (tenant_id = current_setting('app.tenant_id', true)::text);

CREATE POLICY tenant_isolation_tiering_jobs ON tiering_jobs
    USING (tenant_id = current_setting('app.tenant_id', true)::text);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP POLICY IF EXISTS tenant_isolation_warm_events ON warm_events;
DROP POLICY IF EXISTS tenant_isolation_tiering_jobs ON tiering_jobs;
ALTER TABLE warm_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE tiering_jobs DISABLE ROW LEVEL SECURITY;
ALTER TABLE schema_versions DISABLE ROW LEVEL SECURITY;
-- +goose StatementEnd
