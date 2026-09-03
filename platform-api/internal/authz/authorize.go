package authz

import (
	"context"
	"log/slog"

	"github.com/jztlee/secure-platform-identity/platform-api/internal/opa"
)

type Authorizer struct {
	OPA    opa.Client
	Logger *slog.Logger
}

type Request struct {
	SubjectID     string
	Action        string
	Resource      string
	CorrelationID string
}

type Result struct {
	Allow  bool
	Reason string
}

func (a *Authorizer) Authorize(ctx context.Context, req Request) Result {
	input := map[string]any{
		"subject_id": req.SubjectID,
		"action":     req.Action,
		"resource":   req.Resource,
	}

	decision, err := a.OPA.Evaluate(ctx, input)

	result := Result{}
	if err != nil {
		result.Allow = false
		result.Reason = "opa_unreachable"
	} else {
		result.Allow = decision.Allow
		if decision.Allow {
			result.Reason = "policy_allow"
		} else {
			result.Reason = "policy_deny"
		}
	}

	a.Logger.Info("authorization_decision",
		"subject_id", req.SubjectID,
		"action", req.Action,
		"resource", req.Resource,
		"result", result.Allow,
		"reason", result.Reason,
		"correlation_id", req.CorrelationID,
	)

	return result
}
