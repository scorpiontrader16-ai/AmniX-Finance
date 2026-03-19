module github.com/aminpola2001-ctrl/youtuop/services/ingestion

go 1.22

require (
	github.com/ClickHouse/clickhouse-go/v2      v2.23.2
	github.com/jackc/pgx/v5                     v5.5.5
	github.com/minio/minio-go/v7                v7.0.70
	github.com/parquet-go/parquet-go            v0.23.0
	github.com/pressly/goose/v3                 v3.20.0
	github.com/prometheus/client_golang          v1.19.0
	github.com/sony/gobreaker                   v0.5.0
	github.com/twmb/franz-go                    v1.16.1
	go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc v0.49.0
	go.opentelemetry.io/otel                    v1.40.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.40.0
	go.opentelemetry.io/otel/sdk                v1.40.0
	go.uber.org/zap                             v1.27.0
	golang.org/x/crypto                         v0.35.0
	golang.org/x/time                           v0.5.0
	google.golang.org/grpc                      v1.79.3
	google.golang.org/protobuf                  v1.33.0
)
