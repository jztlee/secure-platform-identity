package opa

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type Decision struct {
	Allow bool `json:"allow"`
}

type Client interface {
	Evaluate(ctx context.Context, input map[string]any) (Decision, error)
}

type HTTPClient struct {
	BaseURL    string
	HTTPClient *http.Client
}

func NewHTTPClient(baseURL string) *HTTPClient {
	return &HTTPClient{
		BaseURL:    baseURL,
		HTTPClient: &http.Client{Timeout: 2 * time.Second},
	}
}

func (c *HTTPClient) Evaluate(ctx context.Context, input map[string]any) (Decision, error) {
	body, err := json.Marshal(map[string]any{"input": input})
	if err != nil {
		return Decision{}, fmt.Errorf("marshal input: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+"/v1/data/platform/authz/allow", bytes.NewReader(body))
	if err != nil {
		return Decision{}, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return Decision{}, fmt.Errorf("call opa: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return Decision{}, fmt.Errorf("opa returned status %d", resp.StatusCode)
	}

	var result struct {
		Result bool `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return Decision{}, fmt.Errorf("decode opa response: %w", err)
	}

	return Decision{Allow: result.Result}, nil
}
