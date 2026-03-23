package middleware

import (
    "context"
    "database/sql"
    "net/http"
)

type TenantContextKey string

const TenantIDKey TenantContextKey = "tenant_id"

func TenantMiddleware(db *sql.DB) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            // Extract tenant ID from JWT claims or header
            // For now, assume it's set by previous middleware (JWT validation)
            tenantID := r.Context().Value(TenantIDKey)
            if tenantID != nil {
                // Set PostgreSQL session variable for RLS
                _, err := db.ExecContext(r.Context(), "SELECT set_config('app.tenant_id', $1, false)", tenantID)
                if err != nil {
                    // Log error but continue (RLS will block if missing)
                }
            }
            next.ServeHTTP(w, r)
        })
    }
}
