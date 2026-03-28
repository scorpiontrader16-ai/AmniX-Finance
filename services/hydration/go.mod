module github.com/scorpiontrader16-ai/youtuop-1/services/hydration

go 1.23

require (
    github.com/aminpola2001-ctrl/youtuop v0.0.0-00010101000000-000000000000
    google.golang.org/grpc v1.79.3
    google.golang.org/protobuf v1.36.11
)

replace github.com/aminpola2001-ctrl/youtuop => ../../gen
