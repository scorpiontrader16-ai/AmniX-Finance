package apikey

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"strings"
)

const (
	// يوتوب_prod_xxxxx أو يوتوب_sand_xxxxx
	ProductionPrefix = "ytp"
	SandboxPrefix    = "yts"
	keyLength        = 32
)

// Generated نتيجة إنشاء API key جديد
type Generated struct {
	RawKey    string // بيتبعت للـ user مرة واحدة فقط
	KeyPrefix string // أول 8 chars للـ display
	KeyHash   string // SHA-256 للـ DB storage
}

// Generate ينشئ API key آمن بـ prefix يدل على البيئة
func Generate(environment string) (*Generated, error) {
	raw := make([]byte, keyLength)
	if _, err := rand.Read(raw); err != nil {
		return nil, fmt.Errorf("generate key bytes: %w", err)
	}

	prefix := ProductionPrefix
	if environment == "sandbox" {
		prefix = SandboxPrefix
	}

	encoded := base64.RawURLEncoding.EncodeToString(raw)
	// Format: ytp_live_<random> أو yts_test_<random>
	env := "live"
	if environment == "sandbox" {
		env = "test"
	}
	rawKey := fmt.Sprintf("%s_%s_%s", prefix, env, encoded)
	keyPrefix := rawKey[:12] // أول 12 chars للـ display

	hash := sha256.Sum256([]byte(rawKey))
	keyHash := hex.EncodeToString(hash[:])

	return &Generated{
		RawKey:    rawKey,
		KeyPrefix: keyPrefix,
		KeyHash:   keyHash,
	}, nil
}

// Hash يحسب SHA-256 لـ raw key (للتحقق عند الـ authentication)
func Hash(rawKey string) string {
	h := sha256.Sum256([]byte(rawKey))
	return hex.EncodeToString(h[:])
}

// ExtractPrefix يستخرج الـ prefix من الـ raw key للـ lookup
func ExtractPrefix(rawKey string) string {
	if len(rawKey) < 12 {
		return rawKey
	}
	return rawKey[:12]
}

// IsValid يتحقق من الـ format الأساسي
func IsValid(rawKey string) bool {
	return strings.HasPrefix(rawKey, ProductionPrefix+"_") ||
		strings.HasPrefix(rawKey, SandboxPrefix+"_")
}
