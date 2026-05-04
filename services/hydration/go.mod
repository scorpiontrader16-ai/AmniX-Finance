module github.com/scorpiontrader16-ai/AmniX-Finance/services/hydration

go 1.25.0

require (
	google.golang.org/grpc v1.81.0
	google.golang.org/protobuf v1.36.11
)

require (
	github.com/grafana/pyroscope-go/godeltaprof v0.1.9 // indirect
	github.com/klauspost/compress v1.17.9 // indirect
	golang.org/x/net v0.51.0 // indirect
	golang.org/x/sys v0.42.0 // indirect
	golang.org/x/text v0.34.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260226221140-a57be14db171 // indirect
)

require (
	github.com/grafana/pyroscope-go v1.2.8 // indirect
	github.com/scorpiontrader16-ai/AmniX-Finance v0.0.0-00010101000000-000000000000
)

replace github.com/scorpiontrader16-ai/AmniX-Finance => ../..

require github.com/scorpiontrader16-ai/AmniX-Finance/internal/platform v0.0.0

replace github.com/scorpiontrader16-ai/AmniX-Finance/internal/platform => ../../internal/platform
