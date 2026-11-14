package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHomePage(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()

	handler().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", response.Code)
	}

	if !strings.Contains(response.Body.String(), "Hello from my Go application!") {
		t.Fatal("home page greeting is missing")
	}
}
