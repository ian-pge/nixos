package main

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/gorilla/websocket"
)

type credentialResult struct {
	token string
	err   error
}
type fakeCredentials struct {
	mu            sync.Mutex
	results       []credentialResult
	token         string
	loads, stores int
	storeErr      error
}

func (s *fakeCredentials) Load(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.loads++
	if len(s.results) > 0 {
		r := s.results[0]
		s.results = s.results[1:]
		return r.token, r.err
	}
	if s.token == "" {
		return "", errCredentialMissing
	}
	return s.token, nil
}
func (s *fakeCredentials) Store(ctx context.Context, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stores++
	if s.storeErr != nil {
		return s.storeErr
	}
	s.token = token
	return nil
}

func authBackend(t *testing.T, store *fakeCredentials, httpStatus, wsStatus int) *backend {
	t.Helper()
	t.Setenv("BEEPER_ACCESS_TOKEN", "")
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/accounts":
			if httpStatus != 200 {
				w.WriteHeader(httpStatus)
				jsonResponse(w, object{"error": "unavailable"})
				return
			}
			jsonResponse(w, []object{})
		case "/v1/chats":
			jsonResponse(w, object{"items": []object{}, "hasMore": false})
		case "/v1/ws":
			if wsStatus != 101 {
				w.WriteHeader(wsStatus)
				return
			}
			conn, err := (&websocket.Upgrader{}).Upgrade(w, r, nil)
			if err != nil {
				return
			}
			defer conn.Close()
			for {
				if _, _, err = conn.ReadMessage(); err != nil {
					return
				}
			}
		default:
			t.Errorf("unexpected path %s", r.URL.Path)
		}
	})
	b.client = nil
	b.credentials = store
	b.credentialRetryDelay = 5 * time.Millisecond
	return b
}
func waitAuthState(t *testing.T, b *backend, state string) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if textField(b.statusSnapshot(), "state") == state {
			return
		}
		time.Sleep(2 * time.Millisecond)
	}
	t.Fatalf("expected %s, got %s", state, textField(b.statusSnapshot(), "state"))
}

func TestStartupRecoversStoredTokenAfterKeyringBecomesAvailable(t *testing.T) {
	store := &fakeCredentials{token: "saved-token", results: []credentialResult{
		{err: errors.New("secret diagnostic must stay private")}, {err: errCredentialLocked},
	}}
	b := authBackend(t, store, 200, 101)
	if textField(b.statusSnapshot(), "state") != "loading-token" {
		t.Fatal("startup falsely asks for token")
	}
	go b.initialize()
	waitAuthState(t, b, "connected")
	store.mu.Lock()
	defer store.mu.Unlock()
	if store.loads != 3 || store.stores != 0 {
		t.Fatal("restore must retry reads without rewriting credentials")
	}
}

func TestUnavailableAPIKeepsSavedCredential(t *testing.T) {
	store := &fakeCredentials{token: "saved-token"}
	b := authBackend(t, store, 503, 101)
	go b.initialize()
	waitAuthState(t, b, "offline")
	b.mu.Lock()
	token := b.token
	b.mu.Unlock()
	if token != "saved-token" {
		t.Fatal("offline must preserve saved credential")
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	if store.loads != 1 || store.stores != 0 {
		t.Fatal("network failure should not rewrite or reload secrets")
	}
}

func TestReconnectRetriesKeyringWithoutEnteringToken(t *testing.T) {
	store := &fakeCredentials{}
	b := authBackend(t, store, 200, 101)
	go b.initialize()
	waitAuthState(t, b, "needs-token")
	store.mu.Lock()
	store.token = "saved-token"
	store.mu.Unlock()
	if _, err := b.handle(b.ctx, "reconnect", parameters{}); err != nil {
		t.Fatal(err)
	}
	waitAuthState(t, b, "connected")
	store.mu.Lock()
	defer store.mu.Unlock()
	if store.loads < 2 || store.stores != 0 {
		t.Fatal("Retry must actually re-read the keyring")
	}
}

func TestSavedTokenSurvivesBackendRecreation(t *testing.T) {
	store := &fakeCredentials{}
	first := authBackend(t, store, 200, 101)
	if _, err := first.handle(first.ctx, "connect", parameters{Token: "saved-token"}); err != nil {
		t.Fatal(err)
	}
	waitAuthState(t, first, "connected")
	first.mu.Lock()
	first.streamCancel()
	first.mu.Unlock()
	second := authBackend(t, store, 200, 101)
	go second.initialize()
	waitAuthState(t, second, "connected")
	store.mu.Lock()
	defer store.mu.Unlock()
	if store.stores != 1 || store.token != "saved-token" {
		t.Fatal("restart must reuse the original stored token")
	}
}

func TestOnlyAuthenticationRejectionRequiresReplacement(t *testing.T) {
	for _, tc := range []struct {
		name                 string
		httpStatus, wsStatus int
	}{
		{"http_unauthorized", 401, 101}, {"http_forbidden", 403, 101}, {"websocket_forbidden", 200, 403},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := &fakeCredentials{token: "saved-token"}
			b := authBackend(t, store, tc.httpStatus, tc.wsStatus)
			go b.initialize()
			waitAuthState(t, b, "invalid-token")
			store.mu.Lock()
			defer store.mu.Unlock()
			if store.token != "saved-token" || store.stores != 0 {
				t.Fatal("a rejected token must not be erased")
			}
		})
	}
}

func TestCancelledStreamCannotOverwriteNewConnectionStatus(t *testing.T) {
	b := authBackend(t, &fakeCredentials{}, 200, 101)
	stale := b.statusSnapshot()
	b.status("connected", "Connecté")
	current := b.statusSnapshot()
	if stale["revision"].(uint64) >= current["revision"].(uint64) {
		t.Fatal("status revisions must increase")
	}
	ctx, cancel := context.WithCancel(b.ctx)
	cancel()
	b.statusForContext(ctx, "invalid-token", "ancienne connexion")
	if textField(b.statusSnapshot(), "state") != "connected" {
		t.Fatal("cancelled stream replaced current state")
	}
}

func TestKeyringStoreFailureDoesNotPretendConnectionWasSaved(t *testing.T) {
	store := &fakeCredentials{storeErr: errors.New("locked")}
	b := authBackend(t, store, 200, 101)
	_, err := b.handle(b.ctx, "connect", parameters{Token: "new-token"})
	if safeError(err).Code != "keyring" {
		t.Fatalf("unexpected error %v", err)
	}
	b.mu.Lock()
	configured := b.client != nil
	b.mu.Unlock()
	if configured {
		t.Fatal("unsaved token must not be treated as durable")
	}
}

type fakeSecretService struct {
	unlocked, locked []dbus.ObjectPath
	unavailable      bool
}

func (s *fakeSecretService) SearchItems(attrs map[string]string) ([]dbus.ObjectPath, []dbus.ObjectPath, *dbus.Error) {
	if s.unavailable || attrs["application"] != "quickshell-beeper" || attrs["service"] != "beeper-api" {
		return nil, nil, dbus.NewError("org.freedesktop.DBus.Error.Failed", []any{"unavailable"})
	}
	return s.unlocked, s.locked, nil
}
func (s *fakeSecretService) ReadAlias(name string) (dbus.ObjectPath, *dbus.Error) { return "/", nil }

func TestSecretServiceDistinguishesMissingLockedAndUnavailable(t *testing.T) {
	privateTestBus(t)
	server, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	if _, err = server.RequestName("org.freedesktop.secrets", dbus.NameFlagDoNotQueue); err != nil {
		t.Fatal(err)
	}
	client, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	for _, tc := range []struct {
		name    string
		service fakeSecretService
		want    error
	}{
		{"missing", fakeSecretService{}, errCredentialMissing},
		{"locked", fakeSecretService{locked: []dbus.ObjectPath{"/locked"}}, errCredentialLocked},
		{"readable", fakeSecretService{unlocked: []dbus.ObjectPath{"/readable"}}, nil},
		{"unavailable", fakeSecretService{unavailable: true}, errors.New("unavailable")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if err := server.Export(&tc.service, "/org/freedesktop/secrets", "org.freedesktop.Secret.Service"); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			err := inspectCredential(ctx, client)
			if tc.name == "unavailable" {
				if err == nil || errors.Is(err, errCredentialMissing) || strings.Contains(err.Error(), "saved-token") {
					t.Fatal("service errors must not become missing credentials")
				}
			} else if !errors.Is(err, tc.want) {
				t.Fatalf("got %v, want %v", err, tc.want)
			}
		})
	}
}
