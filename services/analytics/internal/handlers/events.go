package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
)

type Event struct {
	UserID     string                 `json:"user_id"`
	SessionID  string                 `json:"session_id,omitempty"`
	EventType  string                 `json:"event_type"`
	EventName  string                 `json:"event_name"`
	Properties map[string]interface{} `json:"properties,omitempty"`
	Timestamp  time.Time              `json:"timestamp,omitempty"`
}

type EventHandler struct {
	db *pgx.Conn
}

func NewEventHandler(db *pgx.Conn) *EventHandler {
	return &EventHandler{db: db}
}

func (h *EventHandler) Track(w http.ResponseWriter, r *http.Request) {
	tenantID := r.Header.Get("X-Tenant-ID")
	if tenantID == "" {
		http.Error(w, "missing tenant id", http.StatusBadRequest)
		return
	}

	var ev Event
	if err := json.NewDecoder(r.Body).Decode(&ev); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	if ev.Timestamp.IsZero() {
		ev.Timestamp = time.Now().UTC()
	}

	ip := r.Header.Get("X-Forwarded-For")
	if ip == "" {
		ip = r.RemoteAddr
	}
	ua := r.UserAgent()

	_, err := h.db.Exec(r.Context(),
		`INSERT INTO analytics_events (tenant_id, user_id, session_id, event_type, event_name, properties, timestamp, ip_address, user_agent)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		tenantID, ev.UserID, ev.SessionID, ev.EventType, ev.EventName, ev.Properties, ev.Timestamp, ip, ua,
	)
	if err != nil {
		http.Error(w, "failed to record event", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "tracked"})
}
