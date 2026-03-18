// services/ingestion/internal/tiering/job.go
package tiering

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/aminpola2001-ctrl/youtuop/services/ingestion/internal/coldstore"
	"github.com/aminpola2001-ctrl/youtuop/services/ingestion/internal/postgres"
)

const (
	// defaultBatchSize — عدد الـ records لكل Parquet file
	defaultBatchSize = 10_000
	// defaultColdThreshold — عمر البيانات قبل ما تنتقل لـ Cold
	defaultColdThreshold = 30 * 24 * time.Hour // 30 يوم
	// defaultTickInterval — كم مرة بيشتغل الـ job
	defaultTickInterval = 1 * time.Hour
)

// Config إعدادات الـ tiering job
type Config struct {
	BatchSize     int
	ColdThreshold time.Duration
	TickInterval  time.Duration
}

// DefaultConfig إعدادات enterprise افتراضية
func DefaultConfig() Config {
	return Config{
		BatchSize:     defaultBatchSize,
		ColdThreshold: defaultColdThreshold,
		TickInterval:  defaultTickInterval,
	}
}

// Job هو الـ background goroutine اللي بينقل البيانات من Warm لـ Cold
type Job struct {
	pg     *postgres.Client
	cold   *coldstore.Writer
	cfg    Config
	logger *slog.Logger
}

// New ينشئ tiering job جديد
func New(
	pg     *postgres.Client,
	cold   *coldstore.Writer,
	cfg    Config,
	logger *slog.Logger,
) *Job {
	if logger == nil {
		logger = slog.Default()
	}
	return &Job{
		pg:     pg,
		cold:   cold,
		cfg:    cfg,
		logger: logger,
	}
}

// Run يشغّل الـ job في loop حتى الـ context يتلغى
func (j *Job) Run(ctx context.Context) {
	j.logger.Info("tiering job started",
		"batch_size",     j.cfg.BatchSize,
		"cold_threshold", j.cfg.ColdThreshold,
		"tick_interval",  j.cfg.TickInterval,
	)

	// شغّل مرة فور الـ startup
	if err := j.runOnce(ctx); err != nil {
		j.logger.Error("tiering run failed", "error", err)
	}

	ticker := time.NewTicker(j.cfg.TickInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			j.logger.Info("tiering job stopped")
			return
		case <-ticker.C:
			if err := j.runOnce(ctx); err != nil {
				j.logger.Error("tiering run failed", "error", err)
			}
		}
	}
}

// runOnce ينفذ دورة كاملة من الـ Warm → Cold archival
func (j *Job) runOnce(ctx context.Context) error {
	olderThan := time.Now().UTC().Add(-j.cfg.ColdThreshold)

	j.logger.Info("tiering run started", "older_than", olderThan)

	totalMoved := 0

	for {
		// 1. جيب batch من الـ warm events اللي لسه ماتأرشفتش
		events, err := j.pg.GetUnarchived(ctx, olderThan, j.cfg.BatchSize)
		if err != nil {
			return fmt.Errorf("get unarchived events: %w", err)
		}
		if len(events) == 0 {
			break // خلصنا
		}

		// 2. حوّل لـ Parquet records
		records := toParquetRecords(events)

		// 3. اكتب Parquet file في S3
		key, err := j.cold.WriteParquet(ctx, records)
		if err != nil {
			return fmt.Errorf("write parquet: %w", err)
		}

		// 4. حدّث الـ archived_at في Postgres
		eventIDs := make([]string, len(events))
		for i, e := range events {
			eventIDs[i] = e.EventID
		}

		if err := j.pg.MarkArchived(ctx, eventIDs); err != nil {
			// نـ log بس ما نوقفش — الـ Parquet file اتكتب بالفعل
			j.logger.Error("mark archived failed — parquet written but postgres not updated",
				"key",      key,
				"count",    len(eventIDs),
				"error",    err,
			)
		}

		totalMoved += len(events)
		j.logger.Info("batch archived",
			"key",        key,
			"batch_size", len(events),
			"total",      totalMoved,
		)

		// لو جبنا أقل من الـ batch size يعني خلصنا
		if len(events) < j.cfg.BatchSize {
			break
		}
	}

	j.logger.Info("tiering run complete", "total_moved", totalMoved)
	return nil
}

// toParquetRecords يحوّل []postgres.WarmEvent لـ []coldstore.EventRecord
func toParquetRecords(events []postgres.WarmEvent) []coldstore.EventRecord {
	now := time.Now().UnixMilli()
	records := make([]coldstore.EventRecord, len(events))
	for i, e := range events {
		records[i] = coldstore.EventRecord{
			EventID:       e.EventID,
			EventType:     e.EventType,
			Source:        e.Source,
			SchemaVersion: e.SchemaVersion,
			TenantID:      e.TenantID,
			PartitionKey:  e.PartitionKey,
			ContentType:   e.ContentType,
			Payload:       e.Payload,
			PayloadBytes:  int32(e.PayloadBytes),
			TraceID:       e.TraceID,
			SpanID:        e.SpanID,
			OccurredAt:    e.OccurredAt.UnixMilli(),
			IngestedAt:    e.IngestedAt.UnixMilli(),
			ArchivedAt:    now,
		}
	}
	return records
}
