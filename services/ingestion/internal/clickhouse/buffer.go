// services/ingestion/internal/clickhouse/buffer.go
package clickhouse

import (
	"context"
	"log/slog"
	"sync"
	"time"
)

// BufferConfig إعدادات الـ buffered writer
type BufferConfig struct {
	// MaxSize — عدد الـ events قبل ما يعمل flush تلقائي
	MaxSize int
	// FlushInterval — وقت الانتظار الأقصى قبل الـ flush حتى لو الـ buffer مش ممتلي
	FlushInterval time.Duration
	// Workers — عدد الـ goroutines اللي بتكتب في ClickHouse
	Workers int
}

// DefaultBufferConfig إعدادات افتراضية enterprise-ready
func DefaultBufferConfig() BufferConfig {
	return BufferConfig{
		MaxSize:       500,
		FlushInterval: 2 * time.Second,
		Workers:       4,
	}
}

// BufferedWriter يجمع الـ events في batches قبل ما يكتبهم في ClickHouse
type BufferedWriter struct {
	writer    *Writer
	cfg       BufferConfig
	logger    *slog.Logger
	ch        chan EventRow
	wg        sync.WaitGroup
	closeOnce sync.Once
	done      chan struct{}
}

// NewBufferedWriter ينشئ buffered writer جديد ويبدأ الـ workers
func NewBufferedWriter(writer *Writer, cfg BufferConfig, logger *slog.Logger) *BufferedWriter {
	if logger == nil {
		logger = slog.Default()
	}
	if cfg.MaxSize <= 0 {
		cfg.MaxSize = DefaultBufferConfig().MaxSize
	}
	if cfg.FlushInterval <= 0 {
		cfg.FlushInterval = DefaultBufferConfig().FlushInterval
	}
	if cfg.Workers <= 0 {
		cfg.Workers = DefaultBufferConfig().Workers
	}

	bw := &BufferedWriter{
		writer: writer,
		cfg:    cfg,
		logger: logger,
		ch:     make(chan EventRow, cfg.MaxSize*cfg.Workers),
		done:   make(chan struct{}),
	}

	for i := range cfg.Workers {
		bw.wg.Add(1)
		go bw.runWorker(i)
	}

	logger.Info("buffered clickhouse writer started",
		"max_batch_size", cfg.MaxSize,
		"flush_interval", cfg.FlushInterval,
		"workers", cfg.Workers,
	)

	return bw
}

// Enqueue يضيف event للـ buffer — non-blocking
// بيرجع false لو الـ buffer ممتلي أو الـ writer اتقفل
func (bw *BufferedWriter) Enqueue(row EventRow) bool {
	select {
	case <-bw.done:
		// الـ writer اتقفل — ارفض بهدوء
		return false
	default:
	}

	select {
	case bw.ch <- row:
		return true
	case <-bw.done:
		return false
	default:
		bw.logger.Warn("clickhouse buffer full — dropping event",
			"event_id", row.EventID,
			"buffer_size", len(bw.ch),
		)
		return false
	}
}

// Close يوقف الـ workers بعد ما يخلصوا الـ buffer كله
// لا نغلق bw.ch هنا عشان نتجنب PANIC لو Enqueue شغال بالتوازي
// الـ workers بيخرجوا عن طريق <-bw.done ويعملوا drain للمتبقي
func (bw *BufferedWriter) Close() {
	bw.closeOnce.Do(func() {
		close(bw.done)
		bw.wg.Wait()
		bw.logger.Info("buffered clickhouse writer stopped")
	})
}

// runWorker يجمع الـ events ويكتبهم في batches
func (bw *BufferedWriter) runWorker(id int) {
	defer bw.wg.Done()

	batch := make([]EventRow, 0, bw.cfg.MaxSize)
	ticker := time.NewTicker(bw.cfg.FlushInterval)
	defer ticker.Stop()

	flush := func(reason string) {
		if len(batch) == 0 {
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := bw.writer.WriteBatch(ctx, batch); err != nil {
			bw.logger.Error("clickhouse batch write failed",
				"worker", id,
				"reason", reason,
				"batch_size", len(batch),
				"error", err,
			)
		} else {
			bw.logger.Debug("clickhouse batch written",
				"worker", id,
				"reason", reason,
				"batch_size", len(batch),
			)
		}
		batch = batch[:0]
	}

	for {
		select {
		case row := <-bw.ch:
			batch = append(batch, row)
			if len(batch) >= bw.cfg.MaxSize {
				flush("max_size")
			}

		case <-ticker.C:
			flush("interval")

		case <-bw.done:
			// drain ما تبقى في الـ channel قبل الخروج
			for {
				select {
				case row := <-bw.ch:
					batch = append(batch, row)
				default:
					flush("shutdown")
					return
				}
			}
		}
	}
}
