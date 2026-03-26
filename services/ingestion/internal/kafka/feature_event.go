// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  المسار الكامل: services/ingestion/internal/kafka/feature_event.go      ║
// ║  الحالة: 🆕 جديد                                                        ║
// ╚══════════════════════════════════════════════════════════════════════════╝

package kafka

// ─────────────────────────────────────────────────────────────────────────────
// FeatureEvent — البنية التي تُرسَل إلى Redpanda topic "feature-events"
//
// Encoding: JSON (مقروء، سريع، لا يحتاج protoc)
// المرحلة القادمة: استبدال بـ proto.Marshal بعد تشغيل buf generate
// التوثيق: services/ingestion/internal/schema/feature_event.proto
// ─────────────────────────────────────────────────────────────────────────────
type FeatureEvent struct {
	// معرّف فريد — يأتي من main.go كـ "evt-{UnixNano}"
	EventID string `json:"event_id"`

	// معرّف الـ tenant — مطلوب دائماً (RLS)
	TenantID string `json:"tenant_id"`

	// نوع مصدر الحدث — من X-Event-Type header
	SourceType string `json:"source_type,omitempty"`

	// Feature vector — يُملَأ لاحقاً من ML feature extraction pipeline
	FeatureVector []float64 `json:"feature_vector,omitempty"`

	// metadata إضافية
	Metadata map[string]string `json:"metadata,omitempty"`

	// وقت وقوع الحدث — Unix milliseconds (UTC)
	OccurredAt int64 `json:"occurred_at"`
}
