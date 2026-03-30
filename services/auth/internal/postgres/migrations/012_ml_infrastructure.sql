-- ============================================================
-- services/auth/internal/postgres/migrations/012_ml_infrastructure.sql
-- Scope: auth service database only — independent migration sequence
-- ============================================================
-- ============================================================
-- 012_ml_infrastructure.sql
-- M19 AI/ML Infrastructure
-- Model Registry + Feature Store + Experiment Tracking
-- ============================================================

-- +goose Up
-- +goose StatementBegin

-- ── 1. ML Model Registry ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS ml_models (
    id              TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    name            TEXT        NOT NULL,
    version         TEXT        NOT NULL,
    type            TEXT        NOT NULL,
    framework       TEXT        NOT NULL DEFAULT 'sklearn',
    description     TEXT,
    artifact_path   TEXT        NOT NULL,
    artifact_size   BIGINT      NOT NULL DEFAULT 0,
    input_schema    JSONB       NOT NULL DEFAULT '{}',
    output_schema   JSONB       NOT NULL DEFAULT '{}',
    metrics         JSONB       NOT NULL DEFAULT '{}',
    hyperparameters JSONB       NOT NULL DEFAULT '{}',
    status          TEXT        NOT NULL DEFAULT 'staging',
    is_default      BOOLEAN     NOT NULL DEFAULT FALSE,
    created_by      TEXT        REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (name, version),
    CONSTRAINT chk_model_type CHECK (
        type IN (
            'price_prediction',
            'sentiment_analysis',
            'anomaly_detection',
            'trend_classification',
            'volatility_forecast',
            'portfolio_optimization'
        )
    ),
    CONSTRAINT chk_model_framework CHECK (
        framework IN ('sklearn', 'pytorch', 'tensorflow', 'xgboost', 'lightgbm', 'onnx')
    ),
    CONSTRAINT chk_model_status CHECK (
        status IN ('training', 'staging', 'production', 'deprecated', 'failed')
    )
);

CREATE INDEX IF NOT EXISTS idx_ml_models_type_status
    ON ml_models (type, status);

CREATE INDEX IF NOT EXISTS idx_ml_models_default
    ON ml_models (type, is_default)
    WHERE is_default = TRUE AND status = 'production';

CREATE TRIGGER trg_ml_models_updated_at
    BEFORE UPDATE ON ml_models
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 2. Model Deployments ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS model_deployments (
    id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    model_id    TEXT        NOT NULL REFERENCES ml_models(id) ON DELETE CASCADE,
    environment TEXT        NOT NULL DEFAULT 'production',
    replicas    INTEGER     NOT NULL DEFAULT 1,
    status      TEXT        NOT NULL DEFAULT 'deploying',
    endpoint    TEXT,
    deployed_by TEXT        REFERENCES users(id),
    deployed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    retired_at  TIMESTAMPTZ,
    CONSTRAINT chk_deployment_env    CHECK (environment IN ('staging', 'production', 'canary')),
    CONSTRAINT chk_deployment_status CHECK (status IN ('deploying', 'active', 'failed', 'retired'))
);

CREATE INDEX IF NOT EXISTS idx_model_deployments_active
    ON model_deployments (model_id, environment, status)
    WHERE status = 'active';

-- ── 3. ML Experiments ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ml_experiments (
    id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    name        TEXT        NOT NULL UNIQUE,
    description TEXT,
    model_type  TEXT        NOT NULL,
    status      TEXT        NOT NULL DEFAULT 'running',
    config      JSONB       NOT NULL DEFAULT '{}',
    results     JSONB       NOT NULL DEFAULT '{}',
    best_model_id TEXT      REFERENCES ml_models(id),
    created_by  TEXT        REFERENCES users(id),
    started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    CONSTRAINT chk_experiment_status CHECK (
        status IN ('running', 'completed', 'failed', 'cancelled')
    )
);

CREATE INDEX IF NOT EXISTS idx_ml_experiments_type
    ON ml_experiments (model_type, status);

-- ── 4. Feature Store ─────────────────────────────────────────
-- Feature definitions — الـ metadata للـ features
CREATE TABLE IF NOT EXISTS feature_definitions (
    id          TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    name        TEXT        NOT NULL UNIQUE,
    description TEXT,
    data_type   TEXT        NOT NULL,
    source      TEXT        NOT NULL,
    transform   TEXT,
    tags        TEXT[]      NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_feature_type CHECK (
        data_type IN ('float', 'integer', 'boolean', 'string', 'embedding')
    )
);

-- Feature Groups — مجموعات من الـ features للـ model training
CREATE TABLE IF NOT EXISTS feature_groups (
    id           TEXT        PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    name         TEXT        NOT NULL UNIQUE,
    description  TEXT,
    feature_ids  TEXT[]      NOT NULL DEFAULT '{}',
    ttl_seconds  INTEGER     NOT NULL DEFAULT 3600,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Materialized Features (online store — للـ inference في real-time) ────────
CREATE TABLE IF NOT EXISTS feature_values (
    entity_id   TEXT        NOT NULL,
    feature_id  TEXT        NOT NULL REFERENCES feature_definitions(id) ON DELETE CASCADE,
    value       JSONB       NOT NULL,
    computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ,
    PRIMARY KEY (entity_id, feature_id)
);

CREATE INDEX IF NOT EXISTS idx_feature_values_entity
    ON feature_values (entity_id, computed_at DESC);

CREATE INDEX IF NOT EXISTS idx_feature_values_expired
    ON feature_values (expires_at)
    WHERE expires_at IS NOT NULL;

-- ── 5. Prediction Log (للـ monitoring و feedback loop) ────────
CREATE TABLE IF NOT EXISTS prediction_log (
    id              BIGSERIAL   NOT NULL,
    model_id        TEXT        NOT NULL REFERENCES ml_models(id),
    tenant_id       TEXT,
    request_id      TEXT        NOT NULL DEFAULT gen_random_uuid()::TEXT,
    input_features  JSONB       NOT NULL DEFAULT '{}',
    prediction      JSONB       NOT NULL DEFAULT '{}',
    confidence      FLOAT,
    latency_ms      INTEGER,
    actual_outcome  JSONB,
    feedback_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

CREATE TABLE IF NOT EXISTS prediction_log_2026_q1
    PARTITION OF prediction_log
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');

CREATE TABLE IF NOT EXISTS prediction_log_2026_q2
    PARTITION OF prediction_log
    FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');

CREATE TABLE IF NOT EXISTS prediction_log_default
    PARTITION OF prediction_log DEFAULT;

CREATE INDEX IF NOT EXISTS idx_prediction_log_model
    ON prediction_log (model_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_prediction_log_tenant
    ON prediction_log (tenant_id, created_at DESC)
    WHERE tenant_id IS NOT NULL;

-- ── 6. Seed: Default Models ───────────────────────────────────
INSERT INTO ml_models (
    name, version, type, framework, description,
    artifact_path, status, is_default,
    input_schema, output_schema, metrics
) VALUES
(
    'price-momentum-v1', '1.0.0', 'price_prediction', 'xgboost',
    'XGBoost price momentum model trained on 2 years of market data',
    's3://platform-ml-artifacts/models/price-momentum/v1.0.0/model.json',
    'production', TRUE,
    '{"features": ["price", "volume", "rsi_14", "macd", "bb_upper", "bb_lower"]}',
    '{"prediction": "float", "direction": "string", "confidence": "float"}',
    '{"mse": 0.0023, "mae": 0.031, "r2": 0.847, "sharpe": 1.42}'
),
(
    'sentiment-bert-v1', '1.0.0', 'sentiment_analysis', 'pytorch',
    'FinBERT-based model fine-tuned on financial news sentiment',
    's3://platform-ml-artifacts/models/sentiment-bert/v1.0.0/model.pt',
    'production', TRUE,
    '{"text": "string", "max_length": 512}',
    '{"sentiment": "string", "score": "float", "confidence": "float"}',
    '{"accuracy": 0.923, "f1": 0.918, "auc": 0.971}'
),
(
    'anomaly-isolation-v1', '1.0.0', 'anomaly_detection', 'sklearn',
    'Isolation Forest for real-time market anomaly detection',
    's3://platform-ml-artifacts/models/anomaly-isolation/v1.0.0/model.pkl',
    'production', TRUE,
    '{"features": ["price_change_pct", "volume_ratio", "spread", "tick_count"]}',
    '{"is_anomaly": "boolean", "anomaly_score": "float", "severity": "string"}',
    '{"precision": 0.891, "recall": 0.876, "f1": 0.883}'
)
ON CONFLICT (name, version) DO NOTHING;

-- Seed: Feature Definitions
INSERT INTO feature_definitions (name, description, data_type, source, transform) VALUES
    ('price_close',       'Closing price',                     'float',   'market_events', NULL),
    ('price_open',        'Opening price',                     'float',   'market_events', NULL),
    ('volume_24h',        '24h trading volume',                'float',   'market_events', 'log1p'),
    ('rsi_14',            'RSI(14) indicator',                 'float',   'processing',    NULL),
    ('macd',              'MACD signal',                       'float',   'processing',    NULL),
    ('bb_upper',          'Bollinger Band upper',              'float',   'processing',    NULL),
    ('bb_lower',          'Bollinger Band lower',              'float',   'processing',    NULL),
    ('sentiment_score',   'News sentiment score',              'float',   'ml-engine',     NULL),
    ('volume_ratio',      'Volume vs 20d average',             'float',   'processing',    NULL),
    ('price_change_pct',  'Price change percentage',           'float',   'processing',    NULL)
ON CONFLICT (name) DO NOTHING;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

DROP TRIGGER IF EXISTS trg_ml_models_updated_at ON ml_models;

DROP TABLE IF EXISTS prediction_log       CASCADE;
DROP TABLE IF EXISTS feature_values       CASCADE;
DROP TABLE IF EXISTS feature_groups       CASCADE;
DROP TABLE IF EXISTS feature_definitions  CASCADE;
DROP TABLE IF EXISTS ml_experiments       CASCADE;
DROP TABLE IF EXISTS model_deployments    CASCADE;
DROP TABLE IF EXISTS ml_models            CASCADE;

-- +goose StatementEnd
