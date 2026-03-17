package schemaregistry

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client هو Schema Registry HTTP client
type Client struct {
	baseURL    string
	httpClient *http.Client
}

type schemaRequest struct {
	Schema     string `json:"schema"`
	SchemaType string `json:"schemaType"` // "PROTOBUF"
}

type schemaResponse struct {
	ID int `json:"id"`
}

type latestSchemaResponse struct {
	ID      int    `json:"id"`
	Version int    `json:"version"`
	Schema  string `json:"schema"`
}

type compatibilityResponse struct {
	IsCompatible bool `json:"is_compatible"`
}

// CompatibilityLevel هي الـ options المتاحة للـ schema compatibility
type CompatibilityLevel string

const (
	CompatBackward      CompatibilityLevel = "BACKWARD"
	CompatForward       CompatibilityLevel = "FORWARD"
	CompatFull          CompatibilityLevel = "FULL"
	CompatBackwardTrans CompatibilityLevel = "BACKWARD_TRANSITIVE"
	CompatNone          CompatibilityLevel = "NONE"
)

// New ينشئ client جديد
func New(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// RegisterSchema يسجل schema ويرجع الـ ID
func (c *Client) RegisterSchema(ctx context.Context, subject, schema string) (int, error) {
	body, err := json.Marshal(schemaRequest{
		Schema:     schema,
		SchemaType: "PROTOBUF",
	})
	if err != nil {
		return 0, fmt.Errorf("marshal schema: %w", err)
	}

	url := fmt.Sprintf("%s/subjects/%s/versions", c.baseURL, subject)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return 0, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/vnd.schemaregistry.v1+json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return 0, fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return 0, fmt.Errorf("registry returned %d: %s", resp.StatusCode, string(b))
	}

	var result schemaResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return 0, fmt.Errorf("decode response: %w", err)
	}
	return result.ID, nil
}

// GetLatestSchema يجيب آخر version من schema
func (c *Client) GetLatestSchema(ctx context.Context, subject string) (string, error) {
	url := fmt.Sprintf("%s/subjects/%s/versions/latest", c.baseURL, subject)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return "", fmt.Errorf("subject %q not found", subject)
	}
	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("registry returned %d: %s", resp.StatusCode, string(b))
	}

	var result latestSchemaResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}
	return result.Schema, nil
}

// SetCompatibility يحدد compatibility level للـ subject
func (c *Client) SetCompatibility(ctx context.Context, subject string, level CompatibilityLevel) error {
	body, _ := json.Marshal(map[string]string{"compatibility": string(level)})
	url := fmt.Sprintf("%s/config/%s", c.baseURL, subject)

	req, err := http.NewRequestWithContext(ctx, http.MethodPut, url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/vnd.schemaregistry.v1+json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("set compatibility failed %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

// CheckCompatibility يتحقق إن schema جديد compatible مع الموجود
func (c *Client) CheckCompatibility(ctx context.Context, subject, schema string) (bool, error) {
	body, _ := json.Marshal(schemaRequest{Schema: schema, SchemaType: "PROTOBUF"})
	url := fmt.Sprintf("%s/compatibility/subjects/%s/versions/latest", c.baseURL, subject)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return false, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/vnd.schemaregistry.v1+json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return false, fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return false, fmt.Errorf("compatibility check failed %d: %s", resp.StatusCode, string(b))
	}

	var result compatibilityResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return false, fmt.Errorf("decode response: %w", err)
	}
	return result.IsCompatible, nil
}

// ListSubjects يجيب كل الـ subjects المسجلة
func (c *Client) ListSubjects(ctx context.Context) ([]string, error) {
	url := fmt.Sprintf("%s/subjects", c.baseURL)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("list subjects failed %d: %s", resp.StatusCode, string(b))
	}

	var subjects []string
	if err := json.NewDecoder(resp.Body).Decode(&subjects); err != nil {
		return nil, fmt.Errorf("decode subjects: %w", err)
	}
	return subjects, nil
}
