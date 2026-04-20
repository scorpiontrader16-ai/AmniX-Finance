package schemaregistry

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// ─── helpers ─────────────────────────────────────────────────────────────────

func newTestServer(t *testing.T, handler http.HandlerFunc) (*httptest.Server, *Client) {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	return srv, New(srv.URL)
}

// ─── New ─────────────────────────────────────────────────────────────────────

func TestNew_SetsBaseURL(t *testing.T) {
	c := New("http://localhost:8081")
	if c.baseURL != "http://localhost:8081" {
		t.Errorf("unexpected baseURL: %s", c.baseURL)
	}
	if c.httpClient == nil {
		t.Error("httpClient must not be nil")
	}
}

// ─── RegisterSchema ──────────────────────────────────────────────────────────

func TestRegisterSchema_Success(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("expected POST, got %s", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(schemaResponse{ID: 42})
	})

	id, err := client.RegisterSchema(context.Background(), "test-subject", `syntax="proto3";`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if id != 42 {
		t.Errorf("expected id=42, got %d", id)
	}
}

func TestRegisterSchema_ServerError(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "internal error", http.StatusInternalServerError)
	})

	_, err := client.RegisterSchema(context.Background(), "subject", "schema")
	if err == nil {
		t.Fatal("expected error, got nil")
	}
}

func TestRegisterSchema_InvalidJSON(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("not-json"))
	})

	_, err := client.RegisterSchema(context.Background(), "subject", "schema")
	if err == nil {
		t.Fatal("expected JSON decode error")
	}
}

// ─── GetLatestSchema ─────────────────────────────────────────────────────────

func TestGetLatestSchema_Success(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(latestSchemaResponse{
			ID:      1,
			Version: 1,
			Schema:  `syntax="proto3";`,
		})
	})

	schema, err := client.GetLatestSchema(context.Background(), "subject")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if schema == "" {
		t.Error("expected non-empty schema")
	}
}

func TestGetLatestSchema_NotFound(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "not found", http.StatusNotFound)
	})

	_, err := client.GetLatestSchema(context.Background(), "missing-subject")
	if err == nil {
		t.Fatal("expected error for 404")
	}
}

// ─── CheckCompatibility ──────────────────────────────────────────────────────

func TestCheckCompatibility_Compatible(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(compatibilityResponse{IsCompatible: true})
	})

	ok, err := client.CheckCompatibility(context.Background(), "subject", "schema")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ok {
		t.Error("expected compatible=true")
	}
}

func TestCheckCompatibility_Incompatible(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(compatibilityResponse{IsCompatible: false})
	})

	ok, err := client.CheckCompatibility(context.Background(), "subject", "breaking-schema")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Error("expected compatible=false for breaking change")
	}
}

// ─── ListSubjects ────────────────────────────────────────────────────────────

func TestListSubjects_Success(t *testing.T) {
	expected := []string{"events-v1", "processing-v1"}

	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(expected)
	})

	subjects, err := client.ListSubjects(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(subjects) != len(expected) {
		t.Errorf("expected %d subjects, got %d", len(expected), len(subjects))
	}
}

func TestListSubjects_Empty(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode([]string{})
	})

	subjects, err := client.ListSubjects(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(subjects) != 0 {
		t.Errorf("expected empty list, got %d", len(subjects))
	}
}

// ─── SetCompatibility ────────────────────────────────────────────────────────

func TestSetCompatibility_Success(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			t.Errorf("expected PUT, got %s", r.Method)
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"compatibility": "BACKWARD"})
	})

	err := client.SetCompatibility(context.Background(), "subject", CompatBackward)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestSetCompatibility_ServerError(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "forbidden", http.StatusForbidden)
	})

	err := client.SetCompatibility(context.Background(), "subject", CompatBackward)
	if err == nil {
		t.Fatal("expected error on server failure")
	}
}

// ─── ContextCancellation ─────────────────────────────────────────────────────

func TestRegisterSchema_ContextCancelled(t *testing.T) {
	_, client := newTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(schemaResponse{ID: 1})
	})

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	_, err := client.RegisterSchema(ctx, "subject", "schema")
	if err == nil {
		t.Fatal("expected error with cancelled context")
	}
}
