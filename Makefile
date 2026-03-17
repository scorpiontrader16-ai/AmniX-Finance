# ============================================================
# أضف الـ targets دي في نهاية Makefile الموجود عندك
# ============================================================

SCHEMA_REGISTRY_URL ?= http://localhost:8081
PROTO_DIR           ?= ./proto

# ─── Schema ──────────────────────────────────────────────
.PHONY: schema-register schema-list proto-gen

schema-register: ## يسجل كل الـ proto schemas
	SCHEMA_REGISTRY_URL=$(SCHEMA_REGISTRY_URL) \
	PROTO_DIR=$(PROTO_DIR) \
	bash ./scripts/register-schemas.sh

schema-list: ## يعرض كل الـ registered subjects
	@curl -s $(SCHEMA_REGISTRY_URL)/subjects | jq .

proto-gen: ## يولد Go code من الـ proto files (يحتاج buf)
	buf generate

# ─── M4 Services ─────────────────────────────────────────
.PHONY: m4-up m4-down m4-logs

m4-up: ## يشغل M4 services (Schema Registry + MinIO)
	docker compose -f docker-compose.yml -f docker/docker-compose.m4.yml up -d
	@echo "⏳ Waiting for services to be healthy..."
	@sleep 8
	@$(MAKE) schema-register
	@echo ""
	@echo "✅ M4 ready"
	@echo "   Schema Registry : $(SCHEMA_REGISTRY_URL)/subjects"
	@echo "   MinIO Console   : http://localhost:9001  (admin/minioadmin123)"

m4-down: ## يوقف M4 services
	docker compose -f docker-compose.yml -f docker/docker-compose.m4.yml down

m4-logs: ## يعرض logs الـ M4 services
	docker compose -f docker-compose.yml -f docker/docker-compose.m4.yml logs -f schema-registry minio

# ─── Tests ───────────────────────────────────────────────
.PHONY: test-schema

test-schema: ## integration tests للـ schema registry
	SCHEMA_REGISTRY_URL=$(SCHEMA_REGISTRY_URL) \
	go test -tags=integration -v -timeout=60s ./internal/schemaregistry/...
