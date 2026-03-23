package handlers

import (
    "crypto/rand"
    "encoding/hex"
    "encoding/json"
    "net/http"
    "strconv"
    "time"

    "github.com/gorilla/mux"
    "go.uber.org/zap"

    "github.com/aminpola2001-ctrl/youtuop/services/auth/internal/postgres"
)

type APIKeyHandler struct {
    db     *postgres.Client
    logger *zap.Logger
}

func NewAPIKeyHandler(db *postgres.Client, logger *zap.Logger) *APIKeyHandler {
    return &APIKeyHandler{db: db, logger: logger}
}

func (h *APIKeyHandler) Create(w http.ResponseWriter, r *http.Request) {
    userID := r.Context().Value("user_id").(string)
    tenantID := r.Context().Value("tenant_id").(string)

    var req struct {
        Name        string   `json:"name"`
        Permissions []string `json:"permissions"`
        ExpiresIn   int      `json:"expires_in_days"`
    }
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "invalid request", http.StatusBadRequest)
        return
    }

    keyBytes := make([]byte, 32)
    if _, err := rand.Read(keyBytes); err != nil {
        http.Error(w, "failed to generate key", http.StatusInternalServerError)
        return
    }
    key := "pk_" + hex.EncodeToString(keyBytes)

    var expiresAt *time.Time
    if req.ExpiresIn > 0 {
        t := time.Now().Add(time.Duration(req.ExpiresIn) * 24 * time.Hour)
        expiresAt = &t
    }

    if err := h.db.CreateAPIKey(r.Context(), tenantID, userID, req.Name, key, req.Permissions, expiresAt); err != nil {
        h.logger.Error("create api key", zap.Error(err))
        http.Error(w, "failed to create key", http.StatusInternalServerError)
        return
    }

    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(map[string]string{"api_key": key})
}

func (h *APIKeyHandler) List(w http.ResponseWriter, r *http.Request) {
    userID := r.Context().Value("user_id").(string)
    tenantID := r.Context().Value("tenant_id").(string)

    keys, err := h.db.ListAPIKeys(r.Context(), userID, tenantID)
    if err != nil {
        h.logger.Error("list api keys", zap.Error(err))
        http.Error(w, "database error", http.StatusInternalServerError)
        return
    }
    json.NewEncoder(w).Encode(keys)
}

func (h *APIKeyHandler) Revoke(w http.ResponseWriter, r *http.Request) {
    userID := r.Context().Value("user_id").(string)
    tenantID := r.Context().Value("tenant_id").(string)
    keyIDStr := mux.Vars(r)["key_id"]
    keyID, err := strconv.ParseInt(keyIDStr, 10, 64)
    if err != nil {
        http.Error(w, "invalid key id", http.StatusBadRequest)
        return
    }

    if err := h.db.RevokeAPIKey(r.Context(), keyID, userID, tenantID); err != nil {
        http.Error(w, "failed to revoke", http.StatusInternalServerError)
        return
    }
    w.WriteHeader(http.StatusNoContent)
}
