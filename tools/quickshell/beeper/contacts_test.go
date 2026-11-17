package main

import (
	"encoding/json"
	"net/http"
	"testing"
)

func TestStartChatUsesTypedIdentifiersWithoutSendingOrRetrying(t *testing.T) {
	for _, tc := range []struct {
		name   string
		params parameters
		want   chatContact
	}{
		{"legacy", parameters{UserID: "contact/#"}, chatContact{ID: "contact/#"}},
		{"phone", parameters{User: &chatContact{PhoneNumber: "+33612345678"}}, chatContact{PhoneNumber: "+33612345678"}},
		{"username", parameters{User: &chatContact{Username: "@alex"}}, chatContact{Username: "@alex"}},
		{"email", parameters{User: &chatContact{Email: "alex@example.org"}}, chatContact{Email: "alex@example.org"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
				calls++
				if r.Method != "POST" || r.URL.Path != "/v1/chats/start" {
					t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
				}
				var body struct {
					AccountID   string      `json:"accountID"`
					User        chatContact `json:"user"`
					MessageText *string     `json:"messageText"`
				}
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Fatal(err)
				}
				if body.AccountID != "account/#" || body.User != tc.want || body.MessageText != nil {
					t.Errorf("wrong payload: %+v", body)
				}
				jsonResponse(w, object{"id": "new-chat", "accountID": body.AccountID})
			})
			tc.params.AccountID = "account/#"
			result, err := b.handle(b.ctx, "startChat", tc.params)
			if err != nil || calls != 1 {
				t.Fatalf("start: %v (%d requests)", err, calls)
			}
			var chat object
			if err := json.Unmarshal(result.(json.RawMessage), &chat); err != nil || chat["id"] != "new-chat" {
				t.Fatalf("wrong result: %s", result)
			}
		})
	}
}

func TestStartChatRejectsMissingIdentifierAndDoesNotRetryFailure(t *testing.T) {
	calls := 0
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.WriteHeader(http.StatusInternalServerError)
		jsonResponse(w, object{"message": "network unavailable"})
	})
	for _, p := range []parameters{{}, {AccountID: "account"}, {AccountID: "account", User: &chatContact{FullName: "Alex"}}, {AccountID: "account", User: &chatContact{Username: " "}}} {
		if _, err := b.handle(b.ctx, "startChat", p); errorCode(err) != "invalid_params" {
			t.Fatalf("accepted invalid contact: %+v, %v", p, err)
		}
	}
	if calls != 0 {
		t.Fatal("invalid contacts reached the API")
	}
	if _, err := b.handle(b.ctx, "startChat", parameters{AccountID: "account", UserID: "alex"}); err == nil || calls != 1 {
		t.Fatalf("failure retried or hidden: %v, calls %d", err, calls)
	}
}

func TestContactSearchEscapesAccountAndExactIdentifier(t *testing.T) {
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" || r.URL.EscapedPath() != "/v1/accounts/account%2F%23/contacts" || r.URL.Query().Get("query") != "+33 6 12 34 56 78" {
			t.Errorf("wrong contact search: %s", r.URL)
		}
		jsonResponse(w, object{"items": []object{{"id": "contact", "cannotMessage": true}}})
	})
	if _, err := b.handle(b.ctx, "contacts", parameters{AccountID: "account/#", Query: "+33 6 12 34 56 78"}); err != nil {
		t.Fatal(err)
	}
}
