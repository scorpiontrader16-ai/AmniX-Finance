# ============================================================
# Platform Infrastructure — Makefile
# ============================================================

.DEFAULT_GOAL := help

# ─── Variables ───────────────────────────────────────────
SCHEMA_REGISTRY_URL ?= http://localhost:8081
PROTO_DIR           ?= ./proto
POSTGRES_DSN        ?= postgres://platform:platform@localhost:5432/platform?sslmode=disable

# ─── Help ─────────────────────────────────────────────────
.PHONY: help
help: ## Show all available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ─── M1: Dev / Build / Test ───────────────────────────────
.PHONY: dev build test proto

dev: ## Start all services locally
	docker compose up -d

build: ## Build all services
	docker compose build

test: ## Run unit tests
	cd services/ingestion  && go test ./...
	cd services/processing && cargo test

proto: ## Generate code from proto files (requires buf)
	buf generate

# ─── Schema Registry ──────────────────────────────────────
.PHONY: schema-register schema-list

schema-register: ## Register all proto schemas
	SCHEMA_REGISTRY_URL=$(SCHEMA_REGISTRY_URL) \
	PROTO_DIR=$(PROTO_DIR) \
	bash ./scripts/register-schemas.sh

schema-list: ## List all registered subjects
	@curl -s $(SCHEMA_REGISTRY_URL)/subjects | jq .

# ─── Services ─────────────────────────────────────────────
.PHONY: up down logs status

up: ## Start all services with migrations and schema registration
	docker compose up -d
	@sleep 10
	@$(MAKE) db-migrate
	@$(MAKE) schema-register
	@echo ""
	@echo "Services ready:"
	@echo "  ClickHouse : http://localhost:8123/play"
	@echo "  MinIO      : http://localhost:9001"
	@echo "  Redpanda   : http://localhost:8080"
	@echo "  Grafana    : http://localhost:3000"

down: ## Stop all services
	docker compose down

logs: ## Show logs for data services
	docker compose logs -f clickhouse minio

status: ## Show health status of all services
	@echo "=== Redpanda ==="
	@curl -sf http://localhost:9644/v1/cluster/health || echo " DOWN"
	@echo "=== ClickHouse ==="
	@curl -sf http://localhost:8123/ping && echo " UP" || echo " DOWN"
	@echo "=== MinIO ==="
	@curl -sf http://localhost:9000/minio/health/live && echo " UP" || echo " DOWN"
	@echo "=== Schema Registry ==="
	@curl -sf http://localhost:8081/subjects > /dev/null && echo " UP" || echo " DOWN"
	@echo "=== Postgres ==="
	@pg_isready -h localhost -p 5432 -U platform && echo " UP" || echo " DOWN"
	@echo "=== Grafana ==="
	@curl -sf http://localhost:3000/api/health > /dev/null && echo " UP" || echo " DOWN"

# ─── Database Migrations ──────────────────────────────────
.PHONY: db-migrate db-migrate-down db-migrate-status

db-migrate: ## Run Postgres migrations
	GOOSE_MIGRATION_DIR=./services/ingestion/internal/postgres/migrations \
	GOOSE_DBSTRING=$(POSTGRES_DSN) \
	bash ./scripts/migrate.sh up

db-migrate-down: ## Rollback last migration
	GOOSE_MIGRATION_DIR=./services/ingestion/internal/postgres/migrations \
	GOOSE_DBSTRING=$(POSTGRES_DSN) \
	bash ./scripts/migrate.sh down

db-migrate-status: ## Show migrations status
	GOOSE_MIGRATION_DIR=./services/ingestion/internal/postgres/migrations \
	GOOSE_DBSTRING=$(POSTGRES_DSN) \
	bash ./scripts/migrate.sh status

# ─── Integration Tests ────────────────────────────────────
.PHONY: test-schema test-clickhouse test-postgres test-integration

test-schema: ## Integration tests for schema registry
	SCHEMA_REGISTRY_URL=$(SCHEMA_REGISTRY_URL) \
	go test -tags=integration -v -timeout=60s \
		./services/ingestion/internal/schemaregistry/...

test-clickhouse: ## Integration tests for ClickHouse
	go test -tags=integration -v -timeout=60s \
		./services/ingestion/internal/clickhouse/...

test-postgres: ## Integration tests for Postgres
	POSTGRES_DSN=$(POSTGRES_DSN) \
	go test -tags=integration -v -timeout=60s \
		./services/ingestion/internal/postgres/...

test-integration: test-schema test-clickhouse test-postgres ## Run all integration tests
	@echo "All integration tests passed"

# ─── Tiering ─────────────────────────────────────────────
.PHONY: tiering-run

tiering-run: ## Run tiering job manually
	cd services/ingestion && \
	POSTGRES_HOST=localhost \
	MINIO_ENDPOINT=localhost:9000 \
	go run ./cmd/tiering/...
