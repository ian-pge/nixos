package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestCorrectionProvidersReportsAndToolIsolation(t *testing.T) {
	b, log := testBackend(t)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, object{"done": true, "message": object{"content": `{"text":"Les filles","explanations":[{"from":"fille","to":"filles","reason":"Avec les, le nom est au pluriel."},{"from":"other","to":"word","reason":"must not appear"}]}`}})
	}))
	defer server.Close()
	b.chatURL = server.URL
	for _, provider := range []string{"qwen", "openai"} {
		r, err := b.runCorrection(context.Background(), parameters{Conversation: provider, Text: "Les fille", Review: true})
		if err != nil {
			t.Fatal(err)
		}
		if r.Text != "Les filles" || r.ReportID == "" || len(r.Explanations) != 1 || !strings.Contains(r.Explanations[0].Reason, "pluriel") {
			t.Fatalf("bad report: %+v", r)
		}
		if !strings.Contains(b.correction["html"].(string), `color:#ed8796`) {
			t.Fatal("correction not highlighted")
		}
		b.decideCorrection(parameters{ReportID: r.ReportID, Status: "accept"})
		b.finishCorrection(parameters{ReportID: r.ReportID, Status: "applied"})
		if b.correction["state"] != "applied" {
			t.Fatal("missing applied status")
		}
	}
	args, _ := piLog(t, log)
	if len(args) != 1 {
		t.Fatalf("wrong pi invocation count: %d", len(args))
	}
	for _, flag := range []string{"--no-tools", "--no-session", "--no-context-files", "--no-mcp", "--no-extensions"} {
		if !strings.Contains(strings.Join(args[0], " "), flag) {
			t.Fatal("missing isolation flag", flag)
		}
	}
	if len(b.state.Conversations["openai"].Messages) != 0 || len(b.state.Conversations["qwen"].Messages) != 0 {
		t.Fatal("correction polluted chat history")
	}
}
func TestCorrectionSocketUsesPanelAndRejectsUnknownProviders(t *testing.T) {
	b, _ := testBackend(t)
	runtime, err := os.MkdirTemp("/tmp", "qc-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(runtime)
	t.Setenv("XDG_RUNTIME_DIR", runtime)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, object{"done": true, "message": object{"content": `{"text":"Les filles","explanations":[]}`}})
	}))
	defer server.Close()
	b.chatURL = server.URL
	stop, err := b.serveCorrectionSocket()
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	response, err := requestCorrectionPanel(context.Background(), parameters{Action: "correct", Conversation: "qwen", Text: "Les fille", Review: true})
	if err != nil || response["ok"] != true {
		t.Fatalf("%v %v", response, err)
	}
	if b.correction == nil || b.correction["source"] != "Les fille" {
		t.Fatal("Chrome correction did not reach the panel")
	}
	response, err = requestCorrectionPanel(context.Background(), parameters{Action: "correct", Conversation: "unknown", Text: "private"})
	if err != nil || response["ok"] != false {
		t.Fatal("unsupported provider accepted")
	}
}
