package hub

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

// Message هو الـ message اللي بيتبعت للـ clients
type Message struct {
	Type      string          `json:"type"`
	TenantID  string          `json:"tenant_id"`
	Channel   string          `json:"channel"`
	Payload   json.RawMessage `json:"payload"`
	Timestamp time.Time       `json:"timestamp"`
}

// Client يمثل WebSocket connection واحدة
type Client struct {
	ID       string
	UserID   string
	TenantID string
	Channels map[string]bool // الـ channels المشترك فيها
	conn     *websocket.Conn
	send     chan []byte
	mu       sync.Mutex
}

func newClient(userID, tenantID string, conn *websocket.Conn) *Client {
	return &Client{
		ID:       uuid.NewString(),
		UserID:   userID,
		TenantID: tenantID,
		Channels: make(map[string]bool),
		conn:     conn,
		send:     make(chan []byte, 256),
	}
}

func (c *Client) Subscribe(channel string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.Channels[channel] = true
}

func (c *Client) Unsubscribe(channel string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.Channels, channel)
}

func (c *Client) IsSubscribed(channel string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	// wildcard subscription
	if c.Channels["*"] {
		return true
	}
	return c.Channels[channel]
}

// writePump يبعت الـ messages للـ WebSocket
func (c *Client) writePump(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case msg, ok := <-c.send:
			if !ok {
				c.conn.Close(websocket.StatusNormalClosure, "")
				return
			}
			if err := c.conn.Write(ctx, websocket.MessageText, msg); err != nil {
				return
			}
		case <-ticker.C:
			// Ping للـ keep-alive
			if err := c.conn.Write(ctx, websocket.MessageText, []byte(`{"type":"ping"}`)); err != nil {
				return
			}
		case <-ctx.Done():
			return
		}
	}
}

// ── Hub ───────────────────────────────────────────────────────────────────

// Hub يدير كل الـ WebSocket connections مع per-tenant isolation
type Hub struct {
	// tenants: tenantID → clientID → *Client
	tenants map[string]map[string]*Client
	mu      sync.RWMutex
	log     *zap.Logger

	register   chan *Client
	unregister chan *Client
	broadcast  chan *Message
}

func New(log *zap.Logger) *Hub {
	return &Hub{
		tenants:    make(map[string]map[string]*Client),
		log:        log,
		register:   make(chan *Client, 64),
		unregister: make(chan *Client, 64),
		broadcast:  make(chan *Message, 1024),
	}
}

// Run يشغّل الـ hub event loop
func (h *Hub) Run(ctx context.Context) {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			if h.tenants[client.TenantID] == nil {
				h.tenants[client.TenantID] = make(map[string]*Client)
			}
			h.tenants[client.TenantID][client.ID] = client
			h.mu.Unlock()
			h.log.Info("client registered",
				zap.String("client_id", client.ID),
				zap.String("tenant_id", client.TenantID),
			)

		case client := <-h.unregister:
			h.mu.Lock()
			if clients, ok := h.tenants[client.TenantID]; ok {
				delete(clients, client.ID)
				if len(clients) == 0 {
					delete(h.tenants, client.TenantID)
				}
			}
			close(client.send)
			h.mu.Unlock()
			h.log.Debug("client unregistered",
				zap.String("client_id", client.ID),
				zap.String("tenant_id", client.TenantID),
			)

		case msg := <-h.broadcast:
			h.deliverMessage(msg)

		case <-ctx.Done():
			return
		}
	}
}

// Broadcast يبعت message لكل الـ clients في tenant معين
func (h *Hub) Broadcast(msg *Message) {
	select {
	case h.broadcast <- msg:
	default:
		h.log.Warn("broadcast channel full — message dropped",
			zap.String("tenant_id", msg.TenantID),
			zap.String("channel", msg.Channel),
		)
	}
}

func (h *Hub) deliverMessage(msg *Message) {
	data, err := json.Marshal(msg)
	if err != nil {
		h.log.Error("marshal message failed", zap.Error(err))
		return
	}

	h.mu.RLock()
	clients := h.tenants[msg.TenantID]
	h.mu.RUnlock()

	delivered := 0
	for _, client := range clients {
		if !client.IsSubscribed(msg.Channel) {
			continue
		}
		select {
		case client.send <- data:
			delivered++
		default:
			// الـ client slow — skip
			h.log.Warn("client send buffer full",
				zap.String("client_id", client.ID),
			)
		}
	}
	h.log.Debug("message delivered",
		zap.String("channel", msg.Channel),
		zap.String("tenant_id", msg.TenantID),
		zap.Int("delivered", delivered),
	)
}

// ConnectedClients يرجع عدد الـ connections النشطة
func (h *Hub) ConnectedClients() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	total := 0
	for _, clients := range h.tenants {
		total += len(clients)
	}
	return total
}

// ConnectedTenants يرجع عدد الـ tenants المتصلين
func (h *Hub) ConnectedTenants() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.tenants)
}

// RegisterClient يضيف client وبيبدأ الـ write pump بتاعه
func (h *Hub) RegisterClient(ctx context.Context, userID, tenantID string, conn *websocket.Conn) *Client {
	client := newClient(userID, tenantID, conn)
	h.register <- client
	go client.writePump(ctx)
	return client
}

// UnregisterClient يشيل الـ client من الـ hub
func (h *Hub) UnregisterClient(client *Client) {
	h.unregister <- client
}

// SendToClient يبعت message لـ client معين مباشرة
func (h *Hub) SendToClient(client *Client, msg any) error {
	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("marshal: %w", err)
	}
	select {
	case client.send <- data:
		return nil
	default:
		return fmt.Errorf("client buffer full")
	}
}
