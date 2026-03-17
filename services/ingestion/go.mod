module github.com/your-org/platform/services/ingestion

go 1.22

require (
	github.com/prometheus/client_golang v1.19.0
	github.com/sony/gobreaker v0.5.0
	github.com/twmb/franz-go v1.16.1
	go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc v0.49.0
	go.opentelemetry.io/otel v1.24.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.24.0
	go.opentelemetry.io/otel/sdk v1.24.0
	go.uber.org/zap v1.27.0
	golang.org/x/time v0.5.0
	google.golang.org/grpc v1.62.1
	google.golang.org/protobuf v1.33.0
)
