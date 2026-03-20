version: "3.8"

# ── Integration Test Environment ─────────────────────────────────────────
# الاستخدام:
#   docker compose -f docker-compose.integration.yml up -d
#   go test -tags=integration ./...
#   docker compose -f docker-compose.integration.yml down -v

networks:
  integration:
    driver: bridge

volumes:
  redpanda-data:
  clickhouse-data:

services:

  # ── Redpanda (Kafka-compatible) ─────────────────────────────────────────
  redpanda:
    image: redpandadata/redpanda:v24.1.1
    container_name: youtuop-redpanda
    networks: [integration]
    ports:
      - "9092:9092"   # Kafka API
      - "8081:8081"   # Schema Registry
      - "8082:8082"   # HTTP Proxy
      - "9644:9644"   # Admin API
    command:
      - redpanda
      - start
      - --mode=dev-container
      - --overprovisioned
      - --smp=1
      - --memory=512M
      - --reserve-memory=0M
      - --node-id=0
      - --kafka-addr=PLAINTEXT://0.0.0.0:9092
      - --advertise-kafka-addr=PLAINTEXT://localhost:9092
      - --schema-registry-addr=http://0.0.0.0:8081
      - --pandaproxy-addr=http://0.0.0.0:8082
      - --set=redpanda.auto_create_topics_enabled=true
    healthcheck:
      test: ["CMD", "rpk", "cluster", "info", "--brokers=localhost:9092"]
      interval: 5s
      timeout: 10s
      retries: 12
      start_period: 15s

  # ── ClickHouse ──────────────────────────────────────────────────────────
  clickhouse:
    image: clickhouse/clickhouse-server:24.3-alpine
    container_name: youtuop-clickhouse
    networks: [integration]
    ports:
      - "9000:9000"   # Native protocol
      - "8123:8123"   # HTTP interface
    environment:
      CLICKHOUSE_DB:       youtuop
      CLICKHOUSE_USER:     default
      CLICKHOUSE_PASSWORD: ""
      CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: "1"
    volumes:
      - clickhouse-data:/var/lib/clickhouse
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8123/ping"]
      interval: 5s
      timeout: 5s
      retries: 12
      start_period: 10s

  # ── Init: Create Redpanda topics ────────────────────────────────────────
  redpanda-init:
    image: redpandadata/redpanda:v24.1.1
    container_name: youtuop-redpanda-init
    networks: [integration]
    depends_on:
      redpanda:
        condition: service_healthy
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        rpk topic create market-events \
          --brokers=redpanda:9092 \
          --partitions=3 \
          --replicas=1 || true
        rpk topic create market-events-dlq \
          --brokers=redpanda:9092 \
          --partitions=1 \
          --replicas=1 || true
        echo "topics created ✅"
    restart: "no"
