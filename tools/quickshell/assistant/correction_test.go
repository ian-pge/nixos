package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestSpellingEditsPreserveUnchangedContentAndUnicodeOffsets(t *testing.T) {
	source := "😂 Les fille sont aller au cinema.\n  42 € https://example.test/cinema"
	result := validateSpellingEdits(source, []spellingEdit{{"fille", "filles"}, {"aller", "allées"}, {"au cinema", "au cinéma"}})
	if result.Text != "😂 Les filles sont allées au cinéma.\n  42 € https://example.test/cinema" || len(result.Edits) != 3 {
		t.Fatalf("unexpected correction: %+v", result)
	}
	if result.Edits[0].Start != 6 {
		t.Fatalf("offset counted bytes instead of characters: %+v", result.Edits)
	}
}

func TestSpellingCandidateKeepsOriginalFormattingAndIgnoresInsertions(t *testing.T) {
	source := "salut les fille 😂\n  42 € https://example.test"
	candidate := "Salut les filles 🙂 43 € https://example.test!"
	result := validateSpellingCandidate(source, candidate)
	if result.Text != "salut les filles 😂\n  42 € https://example.test" {
		t.Fatalf("model changed unrelated content: %+v", result)
	}
	source = "je sais pas"
	if result := validateSpellingCandidate(source, "je ne sais pas"); result.Text != source || len(result.Edits) != 0 {
		t.Fatal("added words changed informal style")
	}
}
func TestSpellingRejectsRephrasingAndProtectedContent(t *testing.T) {
	cases := []struct{ source, from, to string }{
		{"salut tkt", "salut tkt", "Bonjour, ne t'inquiète pas"},
		{"I like it", "like", "love"},
		{"42 euros", "42", "43"},
		{"salut 😂", "😂", "🙂"},
		{"bonjour\nami", "bonjour\nami", "bonjour ami"},
		{"bonjour  ami", "bonjour  ami", "bonjour ami"},
		{"salut", "salut", "salut !"},
		{"https://example.test/fille", "fille", "filles"},
		{"test@exemple.fr", "exemple", "example"},
		{"@marie #fille", "marie", "Marie"},
		{"`fille`", "fille", "filles"},
		{"```\nfille\n```", "fille", "filles"},
		{"fille et fille", "fille", "filles"},
		{"feuille", "euille", "euillettes"},
	}
	for _, test := range cases {
		t.Run(test.source, func(t *testing.T) {
			r := validateSpellingEdits(test.source, []spellingEdit{{test.from, test.to}})
			if r.Text != test.source || len(r.Edits) != 0 {
				t.Fatalf("changed protected text: %+v", r)
			}
		})
	}
}
func TestSpellingRequestIsIsolatedAndDoesNotFollowRedirects(t *testing.T) {
	b, _ := testBackend(t)
	b.state.Conversations["qwen"].Messages = []chatMessage{{Role: "user", Content: "private chat history"}}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var payload object
		json.NewDecoder(r.Body).Decode(&payload)
		raw, _ := json.Marshal(payload)
		if strings.Contains(string(raw), "private chat history") || len(payload["messages"].([]any)) != 2 || payload["think"] != true || payload["stream"] != false {
			t.Error("incorrect correction request")
		}
		jsonResponse(w, object{"done": true, "message": object{"content": `{"text":"Les filles"}`}})
	}))
	defer server.Close()
	b.chatURL = server.URL
	result, err := b.handle(b.ctx, "correctText", parameters{Text: "Les fille", Review: true})
	if err != nil || result.(correctionResult).Text != "Les filles" {
		t.Fatalf("correction failed: %v %v", result, err)
	}
	if len(b.state.Conversations["qwen"].Messages) != 1 {
		t.Fatal("correction entered chat history")
	}
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { t.Error("followed redirect") }))
	defer target.Close()
	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL, http.StatusTemporaryRedirect)
	}))
	defer redirect.Close()
	if _, err := correctSpelling(b.ctx, redirect.URL, "Les fille"); err == nil {
		t.Fatal("accepted a redirect")
	}
}
