package handlers

import (
	"encoding/json"
	"net/http"

	"go.uber.org/zap"

	"github.com/scorpiontrader16-ai/AmniX-Finance/services/auth/internal/middleware"
	"github.com/scorpiontrader16-ai/AmniX-Finance/services/auth/internal/postgres"
)

type SessionHandler struct {
	db     *postgres.Client
	logger *zap.Logger
}

func NewSessionHandler(db *postgres.Client, logger *zap.Logger) *SessionHandler {
	return &SessionHandler{db: db, logger: logger}
}

func (h *SessionHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok || userID == "" {
		http.Error(w, "missing user context", http.StatusUnauthorized)
		return
	}
	tenantID, ok := r.Context().Value(middleware.TenantIDKey).(string)
	if !ok || tenantID == "" {
		http.Error(w, "missing tenant context", http.StatusUnauthorized)
		return
	}

	sessions, err := h.db.ListSessions(r.Context(), userID, tenantID)
	if err != nil {
		h.logger.Error("list sessions", zap.Error(err))
		http.Error(w, "database error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sessions)
}

func (h *SessionHandler) Revoke(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok || userID == "" {
		http.Error(w, "missing user context", http.StatusUnauthorized)
		return
	}
	tenantID, ok := r.Context().Value(middleware.TenantIDKey).(string)
	if !ok || tenantID == "" {
		http.Error(w, "missing tenant context", http.StatusUnauthorized)
		return
	}
	sessionID := r.PathValue("session_id")

	if err := h.db.RevokeSession(r.Context(), sessionID, userID, tenantID); err != nil {
		http.Error(w, "failed to revoke", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *SessionHandler) RevokeAll(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.UserIDKey).(string)
	if !ok || userID == "" {
		http.Error(w, "missing user context", http.StatusUnauthorized)
		return
	}
	tenantID, ok := r.Context().Value(middleware.TenantIDKey).(string)
	if !ok || tenantID == "" {
		http.Error(w, "missing tenant context", http.StatusUnauthorized)
		return
	}
	currentSessionID, ok := r.Context().Value(middleware.SessionIDKey).(string)
	if !ok || currentSessionID == "" {
		http.Error(w, "missing session context", http.StatusUnauthorized)
		return
	}

	if err := h.db.RevokeAllSessions(r.Context(), userID, tenantID, currentSessionID); err != nil {
		http.Error(w, "failed to revoke all", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
