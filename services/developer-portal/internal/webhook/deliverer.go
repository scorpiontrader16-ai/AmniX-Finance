package webhook

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
    "log/slog"
	"net/http"
	"time"
)

const (
	signatureHeader = "X-Youtuop-Signature-256"
	timestampHeader = "X-Youtuop-Timestamp"
	maxRetries      = 3
	baseDelay       = 1 * time.Second
)

// sharedHTTPClient هو عميل HTTP مشترك يُعاد استخدامه لكل طلبات الـ webhook.
// إعادة استخدام الاتصالات يحسن الأداء ويقلل استهلاك المقابس.
var sharedHTTPClient = &http.Client{
    Timeout: 30 * time.Second,
    Transport: &http.Transport{
        MaxIdleConns:        100,
        MaxIdleConnsPerHost: 10,
        IdleConnTimeout:     90 * time.Second,
    },
}


// Event حدث بيتبعت للـ webhook
type Event struct {
	ID        string         `json:"id"`
	Type      string         `json:"type"`
	TenantID  string         `json:"tenant_id"`
	CreatedAt time.Time      `json:"created_at"`
	Data      map[string]any `json:"data"`
}

// DeliveryResult نتيجة الإرسال
type DeliveryResult struct {
	StatusCode int
	Body       string
	DurationMS int64
	Success    bool
	Error      string
	Attempt    int
}

// Deliver يرسل event لـ webhook URL مع HMAC signature و retry
var packageLogger = slog.Default()

// SetLogger يضبط الـ logger المركزي للحزمة. يجب استدعاؤه من main().
func SetLogger(l *slog.Logger) {
    if l != nil {
        packageLogger = l
    }
}

func Deliver(ctx context.Context, url, secretHash string, event *Event) *DeliveryResult {
	payload, err := json.Marshal(event)
	if err != nil {
		return &DeliveryResult{Error: fmt.Sprintf("marshal event: %v", err)}
	}

	var lastResult *DeliveryResult
	for attempt := 1; attempt <= maxRetries; attempt++ {
		result := deliverOnce(ctx, url, secretHash, payload, attempt)
		lastResult = result
		if result.Success {
			return result
		}
		// Exponential backoff
		if attempt < maxRetries {
			select {
			case <-ctx.Done():
				lastResult.Error = "context cancelled"
				return lastResult
			case <-time.After(baseDelay * time.Duration(attempt*attempt)):
			}
		}
	}
	return lastResult
}

func deliverOnce(ctx context.Context, url, secretHash string, payload []byte, attempt int) *DeliveryResult {
	start := time.Now()
	ts := fmt.Sprintf("%d", start.Unix())

	// HMAC-SHA256 signature
	sig := computeSignature(secretHash, ts, payload)

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(payload))
	if err != nil {
		return &DeliveryResult{
			Attempt: attempt,
			Error:   fmt.Sprintf("create request: %v", err),
		}
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set(signatureHeader, "sha256="+sig)
	req.Header.Set(timestampHeader, ts)
	req.Header.Set("User-Agent", "AmniX-Finance-webhook/1.0")
	req.Header.Set("X-Youtuop-Event-Attempt", fmt.Sprintf("%d", attempt))

	client := sharedHTTPClient
	resp, err := client.Do(req)
	durationMS := time.Since(start).Milliseconds()

	if err != nil {
		return &DeliveryResult{
			Attempt:    attempt,
			DurationMS: durationMS,
			Error:      fmt.Sprintf("http request: %v", err),
		}
	}
	defer resp.Body.Close()

	var bodyBuf bytes.Buffer
		if _, err := bodyBuf.ReadFrom(resp.Body); err != nil {
			packageLogger.ErrorContext(ctx, "webhook read error", "error", err)
		}

	success := resp.StatusCode >= 200 && resp.StatusCode < 300
	return &DeliveryResult{
		StatusCode: resp.StatusCode,
		Body:       bodyBuf.String()[:min(len(bodyBuf.String()), 1000)],
		DurationMS: durationMS,
		Success:    success,
		Attempt:    attempt,
	}
}

// computeSignature ينشئ HMAC-SHA256 للـ payload
// Format: sha256(timestamp + "." + payload)
func computeSignature(secretHash, timestamp string, payload []byte) string {
	mac := hmac.New(sha256.New, []byte(secretHash))
	mac.Write([]byte(timestamp + "."))
	mac.Write(payload)
	return hex.EncodeToString(mac.Sum(nil))
}

// Verify يتحقق من الـ signature للـ incoming webhooks
func Verify(secretHash, timestamp, signature string, payload []byte) bool {
	expected := computeSignature(secretHash, timestamp, payload)
	return hmac.Equal([]byte(signature), []byte(expected))
}

