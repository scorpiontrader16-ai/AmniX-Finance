-- ============================================================
-- services/auth/internal/postgres/migrations/022_graph_relationships.sql
-- Scope: auth service database only — independent migration sequence
-- ============================================================
-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  services/auth/internal/postgres/migrations/022_graph_relationships.sql ║
-- ║  Status: 🆕 New  |  M10 – Graph Intelligence Data Model         ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- +goose Up
-- +goose StatementBegin

-- ── 1. entity_relationships ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS entity_relationships (
    id              TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    tenant_id       TEXT        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    from_entity     TEXT        NOT NULL,
    to_entity       TEXT        NOT NULL,
    relationship    TEXT        NOT NULL,
    weight          FLOAT8      NOT NULL DEFAULT 1.0,
    metadata        JSONB,
    source          TEXT,
    valid_from      TIMESTAMPTZ,
    valid_to        TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_entity_rel_from        CHECK (from_entity  <> ''),
    CONSTRAINT chk_entity_rel_to          CHECK (to_entity    <> ''),
    CONSTRAINT chk_entity_rel_type        CHECK (relationship <> ''),
    CONSTRAINT chk_entity_rel_weight      CHECK (weight > 0),
    CONSTRAINT chk_entity_rel_valid_range CHECK (
        valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from
    )
);

-- ── 2. Indexes ────────────────────────────────────────────────────────────

-- Tenant isolation — required for RLS scan efficiency
CREATE INDEX IF NOT EXISTS idx_entity_rel_tenant
    ON entity_relationships (tenant_id);

-- Graph traversal: outbound edges
CREATE INDEX IF NOT EXISTS idx_entity_rel_from
    ON entity_relationships (tenant_id, from_entity);

-- Graph traversal: inbound edges
CREATE INDEX IF NOT EXISTS idx_entity_rel_to
    ON entity_relationships (tenant_id, to_entity);

-- Relationship type queries (e.g. "all OWNS edges for tenant X")
CREATE INDEX IF NOT EXISTS idx_entity_rel_type
    ON entity_relationships (tenant_id, relationship);

-- Temporal validity queries — partial index avoids scanning NULL valid_to rows
CREATE INDEX IF NOT EXISTS idx_entity_rel_valid_range
    ON entity_relationships (tenant_id, valid_from, valid_to)
    WHERE valid_to IS NOT NULL;

-- JSONB path queries on metadata (e.g. sector, asset class)
CREATE INDEX IF NOT EXISTS idx_entity_rel_metadata
    ON entity_relationships USING GIN (metadata)
    WHERE metadata IS NOT NULL;

-- ── 3. RLS ────────────────────────────────────────────────────────────────
ALTER TABLE entity_relationships ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_entity_relationships
    ON entity_relationships
    USING (
        current_setting('app.tenant_id', true) = ''
        OR tenant_id = current_setting('app.tenant_id', true)
    );

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP POLICY  IF EXISTS tenant_isolation_entity_relationships ON entity_relationships;
ALTER TABLE  entity_relationships DISABLE ROW LEVEL SECURITY;
DROP TABLE   IF EXISTS entity_relationships CASCADE;

-- +goose StatementEnd
