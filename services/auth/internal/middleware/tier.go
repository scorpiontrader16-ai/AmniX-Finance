package middleware

// ╔══════════════════════════════════════════════════════════════════╗
// ║  services/auth/internal/middleware/tier.go                      ║
// ║  M8 — RequireTier: rejects requests below the minimum tier      ║
// ╚══════════════════════════════════════════════════════════════════╝

import (
	"net/http"
	"strings"

	appjwt "github.com/scorpiontrader16-ai/AmniX-Finance/services/auth/internal/jwt"
)

// tierLevel maps tier names to numeric levels for ordered comparison.
// Must stay in sync with the chk_tenant_tier DB constraint.
var tierLevel = map[string]int{
	"basic":      1,
	"pro":        2,
	"enterprise": 3,
}

// RequireTier returns middleware that validates the JWT and rejects the request
// when the caller's tier is below minTier.
//
// Hierarchy: basic(1) < pro(2) < enterprise(3).
//
// Usage:
//
//	mux.Handle("/v1/premium", RequireTier(jwtSvc, "pro")(myHandler))
func RequireTier(jwtSvc *appjwt.Service, minTier string) func(http.Handler) http.Handler {
	required, ok := tierLevel[minTier]
	if !ok {
		// programmer error — panic at startup, not at request time
		panic("middleware.RequireTier: unknown minTier value: " + minTier)
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if !strings.HasPrefix(authHeader, "Bearer ") {
				http.Error(w, `{"error":"missing authorization"}`, http.StatusUnauthorized)
				return
			}

			claims, err := jwtSvc.Validate(strings.TrimPrefix(authHeader, "Bearer "))
			if err != nil {
				http.Error(w, `{"error":"invalid token"}`, http.StatusUnauthorized)
				return
			}

			actual := tierLevel[claims.Tier]
			if actual < required {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusForbidden)
				_ = w.Write([]byte(`{"error":"insufficient_tier","required":"` + minTier + `","actual":"` + claims.Tier + `"}`)) //nolint:errcheck
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
