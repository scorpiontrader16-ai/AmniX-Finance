package rbac

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

const cacheTTL = 2 * time.Minute

// tierPermissions — permissions تتفتح بالـ tier بغض النظر عن الـ role.
// القيم المعتمدة: basic | pro | enterprise (M8 spec).
var tierPermissions = map[string][]string{
	"basic": {
		"markets:read",
		"analytics:read",
	},
	"pro": {
		"markets:read", "markets:stream",
		"analytics:read", "analytics:export",
		"agents:read", "agents:execute",
	},
	"enterprise": nil, // كل الـ permissions عن طريق الـ roles
}

// DB interface — يتطابق مع postgres.Client.GetPermissions
type DB interface {
	GetPermissions(ctx context.Context, userID, tenantID string) ([]string, error)
}

// Engine يدير الـ RBAC checks مع Redis cache
type Engine struct {
	db    DB
	redis *redis.Client
}

func NewEngine(db DB, rdb *redis.Client) *Engine {
	return &Engine{db: db, redis: rdb}
}

// Check يتحقق إن الـ user عنده permission محددة في tenant معين
func (e *Engine) Check(ctx context.Context, userID, tenantID, tier, resource, action string) (bool, error) {
	perms, err := e.GetPermissions(ctx, userID, tenantID, tier)
	if err != nil {
		return false, err
	}
	required := resource + ":" + action
	for _, p := range perms {
		if p == required || p == resource+":*" || p == "*:*" {
			return true, nil
		}
	}
	return false, nil
}

// GetPermissions يجمع role permissions + tier permissions مع Redis cache
func (e *Engine) GetPermissions(ctx context.Context, userID, tenantID, tier string) ([]string, error) {
	cacheKey := fmt.Sprintf("perms:%s:%s", userID, tenantID)

	// 1. Redis cache
	if cached, err := e.getFromCache(ctx, cacheKey); err == nil {
		return cached, nil
	}

	// 2. Role permissions من DB
	rolePerms, err := e.db.GetPermissions(ctx, userID, tenantID)
	if err != nil {
		return nil, err
	}

	// 3. دمج role + tier permissions
	permSet := make(map[string]struct{})
	for _, p := range rolePerms {
		permSet[p] = struct{}{}
	}
	for _, p := range tierPermissions[tier] {
		permSet[p] = struct{}{}
	}

	perms := make([]string, 0, len(permSet))
	for p := range permSet {
		perms = append(perms, p)
	}

	e.setInCache(ctx, cacheKey, perms)
	return perms, nil
}

// Invalidate يمسح الـ cache لما الـ role أو الـ tier يتغير
func (e *Engine) Invalidate(ctx context.Context, userID, tenantID string) {
	e.redis.Del(ctx, fmt.Sprintf("perms:%s:%s", userID, tenantID))
}

func (e *Engine) getFromCache(ctx context.Context, key string) ([]string, error) {
	data, err := e.redis.Get(ctx, key).Bytes()
	if err != nil {
		return nil, err
	}
	var perms []string
	return perms, json.Unmarshal(data, &perms)
}

func (e *Engine) setInCache(ctx context.Context, key string, perms []string) {
	data, _ := json.Marshal(perms)
	e.redis.Set(ctx, key, data, cacheTTL)
}
