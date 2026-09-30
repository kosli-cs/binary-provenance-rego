package main

import (
	"fmt"
	"log"
	"net/http"
)

// version is set at build time: -ldflags "-X main.version=<git sha>".
var version = "dev"

const greeting = "Hello, world!"

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintf(w, "%s (version %s)\n", greeting, version)
	})
	log.Printf("hello-world %s listening on :8080", version)
	log.Fatal(http.ListenAndServe(":8080", nil))
}
