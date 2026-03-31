package jwt

// ╔══════════════════════════════════════════════════════════════════╗
// ║  services/auth/internal/jwt/service.go                          ║
// ║  M5 – Crypto Agility: supports RS256 + ES256                    ║
// ╚══════════════════════════════════════════════════════════════════╝

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"time"

	gojwt "github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const (
	AccessTokenTTL  = 15 * time.Minute
	RefreshTokenTTL = 30 * 24 * time.Hour
)

// Claims هي الـ payload في كل access token.
// UserID محفوظ في RegisteredClaims.Subject (json:"sub") — مفيش تكرار.
type Claims struct {
	// M8: بيانات الـ session
	Email     string `json:"email"`
	SessionID string `json:"sid"`

	// M9: الـ tenant
	TenantID   string `json:"tid"`
	TenantSlug string `json:"tslug"`
	Tier       string `json:"tier"`

	// M10: الـ permissions
	Role        string   `json:"role"`
	Permissions []string `json:"perms"`

	// RegisteredClaims.Subject = UserID (json:"sub")
	gojwt.RegisteredClaims
}

// UserID يرجع الـ user ID من الـ Subject claim
func (c *Claims) UserID() string { return c.Subject }

// IssueInput — input لإصدار token جديد
type IssueInput struct {
	UserID      string
	Email       string
	SessionID   string
	TenantID    string
	TenantSlug  string
	Tier        string
	Role        string
	Permissions []string
}

// ── Service ───────────────────────────────────────────────────────────────

type Service struct {
	cfg    *CryptoConfig
	issuer string
}

// NewService ينشئ service من PEM bytes مباشرة (backward compatible)
// يستخدم RS256 افتراضياً
func NewService(privateKeyPEM []byte, issuer string) (*Service, error) {
	cfg, err := LoadCryptoConfigFromPEM(AlgorithmRS256, privateKeyPEM, "v1")
	if err != nil {
		return nil, fmt.Errorf("load crypto config: %w", err)
	}
	return &Service{cfg: cfg, issuer: issuer}, nil
}

// NewServiceFromConfig ينشئ service من CryptoConfig — M5 entry point
func NewServiceFromConfig(cfg *CryptoConfig, issuer string) (*Service, error) {
	if cfg == nil {
		return nil, errors.New("crypto config is required")
	}
	if issuer == "" {
		return nil, errors.New("issuer is required")
	}
	return &Service{cfg: cfg, issuer: issuer}, nil
}

// Algorithm يرجع الـ algorithm المستخدم حالياً
func (s *Service) Algorithm() Algorithm { return s.cfg.Algorithm }

// IssueAccessToken يصدر JWT موقّع بالـ algorithm المختار
func (s *Service) IssueAccessToken(in IssueInput) (string, error) {
	now := time.Now()
	c := Claims{
		Email:       in.Email,
		SessionID:   in.SessionID,
		TenantID:    in.TenantID,
		TenantSlug:  in.TenantSlug,
		Tier:        in.Tier,
		Role:        in.Role,
		Permissions: in.Permissions,
		RegisteredClaims: gojwt.RegisteredClaims{
			Issuer:    s.issuer,
			Subject:   in.UserID,
			IssuedAt:  gojwt.NewNumericDate(now),
			ExpiresAt: gojwt.NewNumericDate(now.Add(AccessTokenTTL)),
			ID:        uuid.NewString(),
		},
	}

	var token *gojwt.Token
	switch s.cfg.Algorithm {
	case AlgorithmRS256:
		token = gojwt.NewWithClaims(gojwt.SigningMethodRS256, c)
	case AlgorithmES256:
		token = gojwt.NewWithClaims(gojwt.SigningMethodES256, c)
	default:
		return "", fmt.Errorf("unsupported algorithm: %s", s.cfg.Algorithm)
	}

	token.Header["kid"] = s.cfg.KeyID
	return token.SignedString(s.cfg.PrivateKey)
}

// Validate يتحقق من الـ JWT ويرجع الـ Claims
func (s *Service) Validate(tokenStr string) (*Claims, error) {
	t, err := gojwt.ParseWithClaims(tokenStr, &Claims{}, func(t *gojwt.Token) (any, error) {
		switch s.cfg.Algorithm {
		case AlgorithmRS256:
			if _, ok := t.Method.(*gojwt.SigningMethodRSA); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			return s.cfg.PublicKey, nil
		case AlgorithmES256:
			if _, ok := t.Method.(*gojwt.SigningMethodECDSA); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			return s.cfg.PublicKey, nil
		default:
			return nil, fmt.Errorf("unsupported algorithm: %s", s.cfg.Algorithm)
		}
	})
	if err != nil {
		return nil, fmt.Errorf("invalid token: %w", err)
	}
	c, ok := t.Claims.(*Claims)
	if !ok || !t.Valid {
		return nil, errors.New("malformed claims")
	}
	return c, nil
}

// JWKS يرجع الـ public key بصيغة JWK Set لـ /.well-known/jwks.json
func (s *Service) JWKS() ([]byte, error) {
	switch s.cfg.Algorithm {
	case AlgorithmRS256:
		return s.jwksRSA()
	case AlgorithmES256:
		return s.jwksECDSA()
	default:
		return nil, fmt.Errorf("unsupported algorithm: %s", s.cfg.Algorithm)
	}
}

func (s *Service) jwksRSA() ([]byte, error) {
	pub, ok := s.cfg.PublicKey.(*rsa.PublicKey)
	if !ok {
		return nil, errors.New("public key is not RSA")
	}
	n := base64.RawURLEncoding.EncodeToString(pub.N.Bytes())
	e := base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes())
	return json.Marshal(map[string]any{
		"keys": []map[string]any{{
			"kty": "RSA",
			"use": "sig",
			"alg": "RS256",
			"kid": s.cfg.KeyID,
			"n":   n,
			"e":   e,
		}},
	})
}

func (s *Service) jwksECDSA() ([]byte, error) {
	pub, ok := s.cfg.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return nil, errors.New("public key is not ECDSA")
	}
	if pub.Curve != elliptic.P256() {
		return nil, errors.New("only P-256 curve is supported for ES256 JWKS")
	}
	byteLen := (pub.Curve.Params().BitSize + 7) / 8
	xBytes := make([]byte, byteLen)
	yBytes := make([]byte, byteLen)
	pub.X.FillBytes(xBytes)
	pub.Y.FillBytes(yBytes)
	return json.Marshal(map[string]any{
		"keys": []map[string]any{{
			"kty": "EC",
			"use": "sig",
			"alg": "ES256",
			"kid": s.cfg.KeyID,
			"crv": "P-256",
			"x":   base64.RawURLEncoding.EncodeToString(xBytes),
			"y":   base64.RawURLEncoding.EncodeToString(yBytes),
		}},
	})
}
