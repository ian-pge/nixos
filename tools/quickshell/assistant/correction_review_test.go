package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestCorrectionReviewRequiresReadyExplicitAcceptance(t *testing.T) {
	b, _ := testBackend(t)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, object{"done": true, "message": object{"content": `{"text":"Les filles","explanations":[]}`}})
	}))
	defer server.Close()
	b.chatURL = server.URL
	if _, err := b.runCorrection(b.ctx, parameters{Text: "Les fille"}); err == nil {
		t.Fatal("old client bypassed review")
	}
	r, err := b.runCorrection(b.ctx, parameters{Text: "Les fille", ReportID: "preview", Review: true})
	if err != nil {
		t.Fatal(err)
	}
	if b.correction["state"] != "ready" {
		t.Fatal("proposal was applied automatically")
	}
	done := make(chan any, 1)
	go func() { v, _ := b.waitCorrectionDecision(b.ctx, r.ReportID); done <- v }()
	select {
	case <-done:
		t.Fatal("review resolved before a choice")
	case <-time.After(30 * time.Millisecond):
	}
	b.decideCorrection(parameters{ReportID: "stale", Status: "accept"})
	if b.correction["state"] != "ready" {
		t.Fatal("stale decision accepted")
	}
	if _, err := b.decideCorrection(parameters{ReportID: r.ReportID, Status: "accept"}); err != nil {
		t.Fatal(err)
	}
	select {
	case v := <-done:
		if v.(object)["decision"] != "accept" {
			t.Fatal(v)
		}
	case <-time.After(time.Second):
		t.Fatal("review did not wake")
	}
	b.decideCorrection(parameters{ReportID: r.ReportID, Status: "reject"})
	if b.correction["state"] != "accepted" {
		t.Fatal("second decision replaced the first")
	}
}

func TestCorrectionReviewEscapeCancelsRunningModelAndLateResult(t *testing.T) {
	b, _ := testBackend(t)
	started := make(chan struct{})
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(started)
		select {
		case <-r.Context().Done():
		case <-release:
		}
	}))
	defer server.Close()
	defer close(release)
	b.chatURL = server.URL
	done := make(chan correctionResult, 1)
	go func() {
		r, _ := b.runCorrection(context.Background(), parameters{Text: "Les fille", ReportID: "running", Review: true})
		done <- r
	}()
	<-started
	v, _ := b.decideCorrection(parameters{ReportID: "running", Status: "accept"})
	if v.(object)["decision"] != "" {
		t.Fatal("Enter accepted an unfinished proposal")
	}
	b.decideCorrection(parameters{ReportID: "running", Status: "reject"})
	select {
	case r := <-done:
		if !r.Cancelled || len(r.Edits) != 0 {
			t.Fatal(r)
		}
	case <-time.After(time.Second):
		t.Fatal("Escape did not stop the request")
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.correction["state"] != "dismissed" {
		t.Fatal("late result reopened the review")
	}
}
