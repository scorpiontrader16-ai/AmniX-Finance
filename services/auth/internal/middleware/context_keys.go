package middleware

// ╔══════════════════════════════════════════════════════════════════╗
// ║  services/auth/internal/middleware/context_keys.go              ║
// ║  F-AUTH62 — Delegates to shared platform contextkeys package    ║
// ║                                                                  ║
// ║  لماذا delegation بدلاً من تعريف محلي:                         ║
// ║  - يضمن أن كل service تستخدم نفس key type بالضبط               ║
// ║  - type collision مستحيل — struct type فريد في Go type system   ║
// ║  - الأسماء المحلية محفوظة — لا تغيير على الـ handlers           ║
// ╚══════════════════════════════════════════════════════════════════╝

import (
	"github.com/scorpiontrader16-ai/AmniX-Finance/internal/platform/contextkeys"
)

// الأسماء المحلية تفوِّض للـ shared package — handlers لا تحتاج تغيير
var (
	// UserIDKey هو مفتاح الـ context للمستخدم المُحقَّق منه.
	// يُضبط بواسطة TenantContextMiddleware بعد التحقق من الـ JWT.
	UserIDKey = contextkeys.UserIDKey

	// TenantIDKey هو مفتاح الـ context للـ tenant المُحقَّق منه.
	// يُضبط بواسطة TenantContextMiddleware بعد التحقق من الـ JWT.
	TenantIDKey = contextkeys.TenantIDKey

	// SessionIDKey هو مفتاح الـ context للـ session الحالية.
	// يُضبط بواسطة TenantContextMiddleware بعد التحقق من الـ JWT.
	SessionIDKey = contextkeys.SessionIDKey

	// DeviceFingerprintKey هو مفتاح الـ context لبصمة الجهاز.
	// يُضبط بواسطة DeviceFingerprintMiddleware.
	DeviceFingerprintKey = contextkeys.DeviceFingerprintKey
)
