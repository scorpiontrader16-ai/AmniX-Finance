// ╔══════════════════════════════════════════════════════════════════╗
// ║  Full path: services/ingestion/internal/kafka/feature_producer.go ║
// ║  Status: 🆕 New                                                  ║
// ╚══════════════════════════════════════════════════════════════════╝

package kafka

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	kafka "github.com/segmentio/kafka-go"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"go.uber.org/zap"
)

// ── Prometheus Metrics ────────────────────────────────────────────────────

var (
	featureEventsPublishedTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "ingestion_feature_events_published_total",
		Help: "Total number of feature events successfully published to Redpanda",
	})

	featureEventsFailedTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "ingestion_feature_events_failed_total",
		Help: "Total number of feature events that failed to publish",
	})

	featurePublishDuration = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "ingestion_feature_publish_duration_seconds",
		Help:    "Duration of feature event publish operations",
		Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0},
	})
)

// ── FeatureProducer ───────────────────────────────────────────────────────

// FeatureProducer يُرسل FeatureEvent messages إلى Redpanda
//
// topic:    "feature-events"
// encoding: JSON
// key:      tenant_id — يضمن ordered delivery per tenant
// acks:     RequireOne — at-least-once delivery
// compress: Snappy — سريع مع ضغط جيد
type FeatureProducer struct {
	writer *kafka.Writer
	log    *zap.Logger
}

// NewFeatureProducer ينشئ producer جاهزاً للاستخدام الفوري
//
//   brokers: قائمة Redpanda brokers — []string{"redpanda:9092"}
//   topic:   "feature-events"
//   log:     zap structured logger
//
// الـ writer lazy — لا يتصل بـ Redpanda حتى أول write attempt.
// هذا صحيح لأن Redpanda قد لا يكون جاهزاً عند startup.
func NewFeatureProducer(brokers []string, topic string, log *zap.Logger) *FeatureProducer {
	w := &kafka.Writer{
		Addr:         kafka.TCP(brokers...),
		Topic:        topic,
		Balancer:     &kafka.LeastBytes{},
		Async:        false,
		MaxAttempts:  3,
		WriteTimeout: 2 * time.Second,
		ReadTimeout:  2 * time.Second,
		Compression:  kafka.Snappy,
		RequiredAcks: kafka.RequireOne,
	}

	log.Info("feature producer initialized",
		zap.Strings("brokers", brokers),
		zap.String("topic", topic),
	)

	return &FeatureProducer{
		writer: w,
		log:    log,
	}
}

// SendFeatureEvent يُسلسل FeatureEvent كـ JSON ويُرسله إلى Redpanda
//
// يُستدعى من goroutine منفصلة في main.go (non-blocking على الـ hot path).
// context يجب أن يحمل timeout (2s موصى به).
func (p *FeatureProducer) SendFeatureEvent(ctx context.Context, event *FeatureEvent) error {
	if event == nil {
		return fmt.Errorf("feature_producer: event must not be nil")
	}
	if event.TenantID == "" {
		return fmt.Errorf("feature_producer: tenant_id is required")
	}
	if event.EventID == "" {
		return fmt.Errorf("feature_producer: event_id is required")
	}

	start := time.Now()

	value, err := json.Marshal(event)
	if err != nil {
		featureEventsFailedTotal.Inc()
		return fmt.Errorf("feature_producer: json marshal failed: %w", err)
	}

	msg := kafka.Message{
		Key:   []byte(event.TenantID),
		Value: value,
		Headers: []kafka.Header{
			{Key: "event_id", Value: []byte(event.EventID)},
			{Key: "source_type", Value: []byte(event.SourceType)},
			{Key: "content_type", Value: []byte("application/json")},
		},
	}

	if err := p.writer.WriteMessages(ctx, msg); err != nil {
		featureEventsFailedTotal.Inc()
		return fmt.Errorf("feature_producer: write failed: %w", err)
	}

	featureEventsPublishedTotal.Inc()
	featurePublishDuration.Observe(time.Since(start).Seconds())

	return nil
}

// Close يغلق الـ writer بشكل آمن — يُستدعى عند graceful shutdown.
// ينتظر حتى تنتهي كل الـ pending writes.
func (p *FeatureProducer) Close() {
	if err := p.writer.Close(); err != nil {
		p.log.Error("feature producer close error", zap.Error(err))
		return
	}
	p.log.Info("feature producer closed")
}
