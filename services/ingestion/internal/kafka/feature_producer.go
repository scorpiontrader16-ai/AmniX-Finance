// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  المسار الكامل: services/ingestion/internal/kafka/feature_producer.go   ║
// ║  الحالة: ✏️ معدل — إزالة اعتماد proto schema، استخدام JSON encoding     ║
// ╚══════════════════════════════════════════════════════════════════════════╝

package kafka

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	kafka "github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

// FeatureProducer يُرسل FeatureEvent messages إلى Redpanda
// topic: "feature-events"
// encoding: JSON
// key: tenant_id (لضمان ordered delivery per tenant)
type FeatureProducer struct {
	writer *kafka.Writer
	log    *zap.Logger
}

// NewFeatureProducer ينشئ producer جاهزاً للاستخدام الفوري
//
// brokers: قائمة Redpanda brokers — مثال: []string{"redpanda:9092"}
// topic:   اسم الـ topic — "feature-events"
// log:     zap logger للـ error reporting
func NewFeatureProducer(brokers []string, topic string, log *zap.Logger) *FeatureProducer {
	writer := &kafka.Writer{
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
		writer: writer,
		log:    log,
	}
}

// SendFeatureEvent يُسلسل FeatureEvent كـ JSON ويُرسله إلى Redpanda
//
// يُستدعى من goroutine منفصلة في main.go (non-blocking على الـ hot path)
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

	value, err := json.Marshal(event)
	if err != nil {
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
		return fmt.Errorf("feature_producer: write failed: %w", err)
	}

	return nil
}

// Close يغلق الـ writer بشكل آمن — يُستدعى عند graceful shutdown
func (p *FeatureProducer) Close() {
	if err := p.writer.Close(); err != nil {
		p.log.Error("feature producer close error", zap.Error(err))
		return
	}
	p.log.Info("feature producer closed")
}
