package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func handler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}

		hostname, _ := os.Hostname()
		w.Header().Set("Content-Type", "text/html; charset=utf-8")

		fmt.Fprintf(w, `<!DOCTYPE html>
<html>
<head><title>My Go Kubernetes App</title></head>
<body style="font-family: sans-serif; padding: 50px; background: #eef2ff">
  <h1>Hello from my Go application!</h1>
  <p>Deployed with Docker, Kubernetes and GitHub Actions.</p>
  <p>Version: v1</p>
  <p>Serving pod: %s</p>
</body>
</html>`, hostname)
	})

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	return mux
}

func main() {
	server := &http.Server{
		Addr:              ":8080",
		Handler:           handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Println("Listening on port 8080")
	log.Fatal(server.ListenAndServe())
}
