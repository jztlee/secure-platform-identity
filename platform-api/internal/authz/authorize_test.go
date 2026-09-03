package authz

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"

	"github.com/jztlee/secure-platform-identity/platform-api/internal/opa"
)

type fakeOPAClient struct {
	decision opa.Decision
	err      error
}

func (f fakeOPAClient) Evaluate(ctx context.Context, input map[string]any) (opa.Decision, error) {
	return f.decision, f.err
}

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestAuthorize_AllowsWhenOPAAllows(t *testing.T) {
	a := &Authorizer{OPA: fakeOPAClient{decision: opa.Decision{Allow: true}}, Logger: testLogger()}
	result := a.Authorize(context.Background(), Request{SubjectID: "user:lee", Action: "read", Resource: "namespace:dev"})
	if !result.Allow {
		t.Errorf("expected allowed, got denied (reason: %s)", result.Reason)
	}
}

func TestAuthorize_DeniesWhenOPADenies(t *testing.T) {
	a := &Authorizer{OPA: fakeOPAClient{decision: opa.Decision{Allow: false}}, Logger: testLogger()}
	result := a.Authorize(context.Background(), Request{SubjectID: "user:lee", Action: "delete", Resource: "namespace:prod"})
	if result.Allow {
		t.Error("expected denied, got allowed")
	}
}

func TestAuthorize_FailsClosedWhenOPAUnreachable(t *testing.T) {
	a := &Authorizer{OPA: fakeOPAClient{err: errors.New("connection refused")}, Logger: testLogger()}
	result := a.Authorize(context.Background(), Request{SubjectID: "user:lee", Action: "read", Resource: "namespace:dev"})
	if result.Allow {
		t.Error("expected fail-closed deny when OPA is unreachable, got allowed")
	}
	if result.Reason != "opa_unreachable" {
		t.Errorf("expected reason 'opa_unreachable', got %q", result.Reason)
	}
}
