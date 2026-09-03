package main

import (
	"log"
	"log/slog"
	"net/http"
	"os"

	"github.com/jztlee/secure-platform-identity/platform-api/internal/api"
	"github.com/jztlee/secure-platform-identity/platform-api/internal/authz"
	"github.com/jztlee/secure-platform-identity/platform-api/internal/opa"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	opaClient := opa.NewHTTPClient("http://opa.platform-api.svc.cluster.local:8181")
	authorizer := &authz.Authorizer{OPA: opaClient, Logger: logger}

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	http.HandleFunc("/v1/namespaces", api.NamespacesHandler)
	http.HandleFunc("/v1/authorize", api.AuthorizeHandler(authorizer))

	log.Println("listening on :8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}
