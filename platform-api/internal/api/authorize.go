package api

import (
	"encoding/json"
	"net/http"

	"github.com/jztlee/secure-platform-identity/platform-api/internal/authz"
)

type authorizeRequestBody struct {
	Subject  string `json:"subject"`
	Action   string `json:"action"`
	Resource string `json:"resource"`
}

func AuthorizeHandler(a *authz.Authorizer) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body authorizeRequestBody
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid request body", http.StatusBadRequest)
			return
		}

		result := a.Authorize(r.Context(), authz.Request{
			SubjectID:     body.Subject,
			Action:        body.Action,
			Resource:      body.Resource,
			CorrelationID: r.Header.Get("X-Correlation-ID"),
		})

		w.Header().Set("Content-Type", "application/json")
		if !result.Allow {
			w.WriteHeader(http.StatusForbidden)
		}
		json.NewEncoder(w).Encode(result)
	}
}
