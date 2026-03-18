//go:build integration

// الاستخدام: go test -tags=integration -v ./internal/clickhouse/...
// متطلبات: ClickHouse شغال على localhost:9000
package clickhouse

import (
	"context"
	"log/slog"
	"testing"
	"time"
)

func testWriter(t *testing.T) *Writer {
	t.Helper()
	cfg := ConfigFromEnv()
	// override للـ test environment
	cfg.Host = "localhost"
	cfg.Port = 9000

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	w, err := New(ctx, cfg, slog.Default())
	if err != nil {
		t.Fatalf("connect to clickhouse: %v", err)
	}
	t.Cleanup(func() { w.Close() })
	return w
}

func TestClickHouse_Ping(t *testing.T) {
	testWriter(t)
	t.Log("clickhouse ping OK ✅")
}

func TestClickHouse_WriteEvent(t *testing.T) {
	w := testWriter(t)
	ctx := context.Background()

	row := EventRow{
		EventID:       "test-evt-001",
		EventType:     "test.created",
		Source:        "integration-test",
		SchemaVersion: "1.0.0",
		OccurredAt:    time.Now().UTC(),
		IngestedAt:    time.Now().UTC(),
		TenantID:      "tenant-test",
		PartitionKey:  "test-key",
		ContentType:   "application/json",
		Payload:       `{"test":true}`,
		PayloadBytes:  13,
		TraceID:       "trace-abc123",
		SpanID:        "span-def456",
		MetaKeys:      []string{"env", "region"},
		MetaValues:    []string{"test", "us-east-1"},
	}

	if err := w.WriteEvent(ctx, row); err != nil {
		t.Fatalf("write event: %v", err)
	}
	t.Log("single event written ✅")
}

func TestClickHouse_WriteBatch(t *testing.T) {
	w := testWriter(t)
	ctx := context.Background()

	rows := make([]EventRow, 100)
	now := time.Now().UTC()
	for i := range rows {
		rows[i] = EventRow{
			EventID:       generateTestID(i),
			EventType:     "test.batch",
			Source:        "integration-test",
			SchemaVersion: "1.0.0",
			OccurredAt:    now.Add(time.Duration(i) * time.Millisecond),
			IngestedAt:    now,
			TenantID:      "tenant-test",
			PartitionKey:  "batch-key",
			ContentType:   "application/json",
			Payload:       `{"batch":true}`,
			PayloadBytes:  14,
			TraceID:       "trace-batch",
			SpanID:        "span-batch",
			MetaKeys:      []string{"batch_index"},
			MetaValues:    []string{generateTestID(i)},
		}
	}

	start := time.Now()
	if err := w.WriteBatch(ctx, rows); err != nil {
		t.Fatalf("write batch: %v", err)
	}
	elapsed := time.Since(start)

	t.Logf("batch of 100 events written in %s ✅", elapsed)

	// تحقق إن الـ throughput معقول
	if elapsed > 5*time.Second {
		t.Errorf("batch write too slow: %s (expected < 5s)", elapsed)
	}
}

func TestClickHouse_BufferedWriter(t *testing.T) {
	w := testWriter(t)

	cfg := BufferConfig{
		MaxSize:       50,
		FlushInterval: 500 * time.Millisecond,
		Workers:       2,
	}

	bw := NewBufferedWriter(w, cfg, slog.Default())
	defer bw.Close()

	now := time.Now().UTC()
	enqueued := 0
	for i := range 200 {
		row := EventRow{
			EventID:       generateTestID(i + 10000),
			EventType:     "test.buffered",
			Source:        "integration-test",
			SchemaVersion: "1.0.0",
			OccurredAt:    now,
			IngestedAt:    now,
			TenantID:      "tenant-test",
			PartitionKey:  "buffered-key",
			ContentType:   "application/json",
			Payload:       `{"buffered":true}`,
			PayloadBytes:  17,
			TraceID:       "trace-buffered",
			SpanID:        "span-buffered",
			MetaKeys:      []string{},
			MetaValues:    []string{},
		}
		if bw.Enqueue(row) {
			enqueued++
		}
	}

	t.Logf("enqueued %d/200 events", enqueued)

	// انتظر الـ flush
	time.Sleep(1 * time.Second)
	t.Log("buffered writer test complete ✅")
}

func TestMetaFromStruct_NilSafe(t *testing.T) {
	keys, values := MetaFromStruct(nil)
	if len(keys) != 0 || len(values) != 0 {
		t.Errorf("expected empty slices for nil struct, got keys=%v values=%v", keys, values)
	}
	t.Log("nil struct handled safely ✅")
}

// ── Helpers ───────────────────────────────────────────────────────────────

func generateTestID(i int) string {
	return "test-" + padInt(i, 6)
}

func padInt(i, width int) string {
	s := ""
	n := i
	if n == 0 {
		s = "0"
	}
	for n > 0 {
		s = string(rune('0'+n%10)) + s
		n /= 10
	}
	for len(s) < width {
		s = "0" + s
	}
	return s
}
