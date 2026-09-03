package api

import (
	"encoding/json"
	"net/http"
)

type Namespace struct {
	Name string `json:"name"`
}

func NamespacesHandler(w http.ResponseWriter, r *http.Request) {
	namespaces := []Namespace{
		{Name: "platform-api"},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(namespaces)
}
