// ╔══════════════════════════════════════════════════════════════════╗
// ║  Full path: services/ingestion/internal/kafka/feature_event.go  ║
// ║  Status: 🆕 New                                                  ║
// ╚══════════════════════════════════════════════════════════════════╝

package kafka

// FeatureEvent — البنية التي تُرسَل إلى Redpanda topic "feature-events"
//
// Encoding: JSON (مقروء، بدون codegen dependency)
// Schema contract: services/ingestion/internal/schema/feature_event.proto
// Key (Redpanda): tenant_id — يضمن ordered delivery per tenant
//
// الحقول مطابقة 1-to-1 لـ proto message FeatureEvent:
//   event_id      → field 1
//   tenant_id     → field 2
//   source_type   → field 3
//   feature_vector → field 4
//   metadata      → field 5
//   occurred_at   → field 6 (Unix milliseconds)
type FeatureEvent struct {
	// معرّف فريد — "evt-{UnixNano}" من main.go
	EventID string `json:"event_id"`

	// معرّف الـ tenant — مطلوب دائماً (RLS)
	TenantID string `json:"tenant_id"`

	// نوع مصدر الحدث — من X-Event-Type header
	SourceType string `json:"source_type,omitempty"`

	// Feature vector — يُملَأ لاحقاً من ML pipeline
	FeatureVector []float64 `json:"feature_vector,omitempty"`

	// metadata إضافية
	Metadata map[string]string `json:"metadata,omitempty"`

	// وقت وقوع الحدث — Unix milliseconds (UTC)
	OccurredAt int64 `json:"occurred_at"`
}
