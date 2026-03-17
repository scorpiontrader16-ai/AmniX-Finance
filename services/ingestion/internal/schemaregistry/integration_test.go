//go:build integration

// الاستخدام: go test -tags=integration -v ./internal/schemaregistry/...
package schemaregistry

import (
	"context"
	"log/slog"
	"os"
	"testing"
	"time"
)

// testClient يبني client ويتحقق من الـ registry
func testClient(t *testing.T) *Client {
	t.Helper()
	url := os.Getenv("SCHEMA_REGISTRY_URL")
	if url == "" {
		url = "http://localhost:8081"
	}
	return New(url)
}

func TestSchemaRegistry_ListSubjects(t *testing.T) {
	c := testClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	subjects, err := c.ListSubjects(ctx)
	if err != nil {
		t.Fatalf("list subjects: %v", err)
	}
	t.Logf("existing subjects (%d): %v", len(subjects), subjects)
}

func TestSchemaRegistry_RegisterAndRetrieve(t *testing.T) {
	c := testClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	const subject = "integration-test-event"
	schema := `syntax = "proto3";
package integration.v1;
message TestEvent {
  string id   = 1;
  string type = 2;
}`

	// ─── Register ────────────────────────────────────────
	id, err := c.RegisterSchema(ctx, subject, schema)
	if err != nil {
		t.Fatalf("register schema: %v", err)
	}
	if id <= 0 {
		t.Errorf("expected positive schema ID, got %d", id)
	}
	t.Logf("registered schema id=%d", id)

	// ─── Retrieve ────────────────────────────────────────
	retrieved, err := c.GetLatestSchema(ctx, subject)
	if err != nil {
		t.Fatalf("get latest schema: %v", err)
	}
	if retrieved == "" {
		t.Error("expected non-empty schema content")
	}
	t.Logf("retrieved schema (%d bytes)", len(retrieved))
}

func TestSchemaRegistry_BackwardCompatible(t *testing.T) {
	c := testClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	const subject = "integration-test-event"

	// إضافة optional field — BACKWARD compatible
	evolved := `syntax = "proto3";
package integration.v1;
message TestEvent {
  string id     = 1;
  string type   = 2;
  string source = 3;
}`

	ok, err := c.CheckCompatibility(ctx, subject, evolved)
	if err != nil {
		t.Fatalf("check compatibility: %v", err)
	}
	if !ok {
		t.Error("adding optional field should be BACKWARD compatible")
	}
	t.Log("backward compatibility check passed ✅")
}

func TestSchemaRegistry_BreakingChangeRejected(t *testing.T) {
	c := testClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	const subject = "integration-test-event"

	// حذف field موجود — breaking change
	breaking := `syntax = "proto3";
package integration.v1;
message TestEvent {
  string id = 1;
}`

	ok, err := c.CheckCompatibility(ctx, subject, breaking)
	if err != nil {
		// بعض الـ registries بترجع error بدل is_compatible=false
		t.Logf("compatibility returned error (acceptable): %v", err)
		return
	}
	if ok {
		t.Error("removing existing field should NOT be backward compatible")
	}
	t.Log("breaking change correctly rejected ✅")
}

func TestRegistrar_RegisterAll(t *testing.T) {
	url := os.Getenv("SCHEMA_REGISTRY_URL")
	if url == "" {
		url = "http://localhost:8081"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	r := NewRegistrar(url, slog.Default())

	if err := r.WaitForRegistry(ctx); err != nil {
		t.Fatalf("wait for registry: %v", err)
	}

	// يستخدم proto directory نسبة للـ test
	if err := r.RegisterAll(ctx, "../../proto"); err != nil {
		t.Fatalf("register all: %v", err)
	}
}
