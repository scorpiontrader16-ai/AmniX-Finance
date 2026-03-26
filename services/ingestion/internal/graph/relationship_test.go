// ╔══════════════════════════════════════════════════════════════════╗
// ║  services/ingestion/internal/graph/relationship_test.go         ║
// ║  Status: 🆕 New  |  M10 – Graph Intelligence Data Model         ║
// ╚══════════════════════════════════════════════════════════════════╝

package graph

import (
	"testing"
	"time"
)

// ─── validateRelationship ─────────────────────────────────────────────────────

func TestValidateRelationship_Valid(t *testing.T) {
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		ToEntity:   "NASDAQ",
		Type:       "LISTED_ON",
		Weight:     1.0,
	}
	if err := validateRelationship(rel); err != nil {
		t.Errorf("expected valid, got error: %v", err)
	}
}

func TestValidateRelationship_MissingTenantID(t *testing.T) {
	rel := Relationship{
		FromEntity: "AAPL",
		ToEntity:   "NASDAQ",
		Type:       "LISTED_ON",
		Weight:     1.0,
	}
	if err := validateRelationship(rel); err == nil {
		t.Fatal("expected error for missing tenant_id")
	}
}

func TestValidateRelationship_MissingFromEntity(t *testing.T) {
	rel := Relationship{
		TenantID: "tenant-1",
		ToEntity: "NASDAQ",
		Type:     "LISTED_ON",
		Weight:   1.0,
	}
	if err := validateRelationship(rel); err == nil {
		t.Fatal("expected error for missing from_entity")
	}
}

func TestValidateRelationship_MissingToEntity(t *testing.T) {
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		Type:       "LISTED_ON",
		Weight:     1.0,
	}
	if err := validateRelationship(rel); err == nil {
		t.Fatal("expected error for missing to_entity")
	}
}

func TestValidateRelationship_MissingType(t *testing.T) {
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		ToEntity:   "NASDAQ",
		Weight:     1.0,
	}
	if err := validateRelationship(rel); err == nil {
		t.Fatal("expected error for missing relationship type")
	}
}

func TestValidateRelationship_ZeroWeight(t *testing.T) {
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		ToEntity:   "NASDAQ",
		Type:       "LISTED_ON",
		Weight:     0,
	}
	if err := validateRelationship(rel); err == nil {
		t.Fatal("expected error for zero weight")
	}
}

func TestValidateRelationship_NegativeWeight(t *testing.T) {
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		ToEntity:   "NASDAQ",
		Type:       "LISTED_ON",
		Weight:     -1.5,
	}
	if err := validateRelationship(rel); err == nil {
		t.Fatal("expected error for negative weight")
	}
}

func TestValidateRelationship_ValidToBeforeValidFrom(t *testing.T) {
	now := time.Now()
	past := now.Add(-24 * time.Hour)
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		ToEntity:   "NASDAQ",
		Type:       "LISTED_ON",
		Weight:     1.0,
		ValidFrom:  &now,
		ValidTo:    &past,
	}
	if err := validateRelationship(rel); err == nil {
		t.Fatal("expected error when valid_to is before valid_from")
	}
}

func TestValidateRelationship_ValidToEqualValidFrom(t *testing.T) {
	now := time.Now()
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		ToEntity:   "NASDAQ",
		Type:       "LISTED_ON",
		Weight:     1.0,
		ValidFrom:  &now,
		ValidTo:    &now,
	}
	if err := validateRelationship(rel); err == nil {
		t.Fatal("expected error when valid_to equals valid_from")
	}
}

func TestValidateRelationship_ValidFromOnlyIsAllowed(t *testing.T) {
	now := time.Now()
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		ToEntity:   "NASDAQ",
		Type:       "LISTED_ON",
		Weight:     1.0,
		ValidFrom:  &now,
		ValidTo:    nil,
	}
	if err := validateRelationship(rel); err != nil {
		t.Errorf("expected valid for open-ended range, got: %v", err)
	}
}

func TestValidateRelationship_ValidToOnlyIsAllowed(t *testing.T) {
	future := time.Now().Add(24 * time.Hour)
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		ToEntity:   "NASDAQ",
		Type:       "LISTED_ON",
		Weight:     1.0,
		ValidFrom:  nil,
		ValidTo:    &future,
	}
	if err := validateRelationship(rel); err != nil {
		t.Errorf("expected valid for valid_to-only range, got: %v", err)
	}
}

func TestValidateRelationship_ValidTemporalRange(t *testing.T) {
	from := time.Now()
	to := from.Add(365 * 24 * time.Hour)
	rel := Relationship{
		TenantID:   "tenant-1",
		FromEntity: "AAPL",
		ToEntity:   "SP500",
		Type:       "MEMBER_OF",
		Weight:     1.0,
		ValidFrom:  &from,
		ValidTo:    &to,
	}
	if err := validateRelationship(rel); err != nil {
		t.Errorf("expected valid temporal range, got: %v", err)
	}
}

// ─── marshalMetadata ──────────────────────────────────────────────────────────

func TestMarshalMetadata_Nil(t *testing.T) {
	b, err := marshalMetadata(nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if b != nil {
		t.Errorf("expected nil bytes for nil metadata, got: %s", b)
	}
}

func TestMarshalMetadata_Empty(t *testing.T) {
	b, err := marshalMetadata(map[string]interface{}{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if b != nil {
		t.Errorf("expected nil bytes for empty metadata, got: %s", b)
	}
}

func TestMarshalMetadata_WithData(t *testing.T) {
	m := map[string]interface{}{
		"sector":      "technology",
		"asset_class": "equity",
	}
	b, err := marshalMetadata(m)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(b) == 0 {
		t.Error("expected non-empty JSON bytes")
	}
}

func TestMarshalMetadata_NonSerializable(t *testing.T) {
	m := map[string]interface{}{
		"channel": make(chan int),
	}
	_, err := marshalMetadata(m)
	if err == nil {
		t.Fatal("expected error for non-serializable value")
	}
}

// ─── nullableString ───────────────────────────────────────────────────────────

func TestNullableString_Empty(t *testing.T) {
	ns := nullableString("")
	if ns.Valid {
		t.Error("expected Valid=false for empty string")
	}
}

func TestNullableString_NonEmpty(t *testing.T) {
	ns := nullableString("bloomberg-feed")
	if !ns.Valid {
		t.Error("expected Valid=true for non-empty string")
	}
	if ns.String != "bloomberg-feed" {
		t.Errorf("expected String=bloomberg-feed, got %s", ns.String)
	}
}

// ─── NewStore ─────────────────────────────────────────────────────────────────

// TestNewStore_NilLoggerDefaults verifies that a nil logger falls back to
// slog.Default(). This test intentionally passes nil for *postgres.Client
// because it only exercises the logger initialisation path — no DB call
// is made, so no nil-pointer dereference can occur.
func TestNewStore_NilLoggerDefaults(t *testing.T) {
	s := NewStore(nil, nil)
	if s == nil {
		t.Fatal("expected non-nil Store")
	}
	if s.logger == nil {
		t.Error("expected logger to default to slog.Default()")
	}
}
