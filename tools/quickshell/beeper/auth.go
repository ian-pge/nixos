package main

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/godbus/dbus/v5"
)

var errCredentialMissing = errors.New("no saved credential")
var errCredentialLocked = errors.New("credential is locked")

type credentialStore interface {
	Load(context.Context) (string, error)
	Store(context.Context, string) error
}

type secretCredentialStore struct{}

// SearchItems separates absence from a locked/unavailable keyring without
// parsing localized command errors or asking the user to unlock repeatedly.
func inspectCredential(ctx context.Context, conn *dbus.Conn) error {
	service := conn.Object("org.freedesktop.secrets", "/org/freedesktop/secrets")
	var unlocked, locked []dbus.ObjectPath
	if err := service.CallWithContext(ctx, "org.freedesktop.Secret.Service.SearchItems", 0,
		map[string]string{"application": "quickshell-beeper", "service": "beeper-api"}).Store(&unlocked, &locked); err != nil {
		return err
	}
	if len(unlocked) > 0 {
		return nil
	}
	if len(locked) > 0 {
		return errCredentialLocked
	}
	// Some providers cannot search a locked collection's attributes.
	var collection dbus.ObjectPath
	if err := service.CallWithContext(ctx, "org.freedesktop.Secret.Service.ReadAlias", 0, "default").Store(&collection); err != nil {
		return err
	}
	if collection != "/" {
		var value dbus.Variant
		if err := conn.Object("org.freedesktop.secrets", collection).CallWithContext(ctx,
			"org.freedesktop.DBus.Properties.Get", 0, "org.freedesktop.Secret.Collection", "Locked").Store(&value); err != nil {
			return err
		}
		isLocked, ok := value.Value().(bool)
		if !ok {
			return errors.New("invalid collection lock state")
		}
		if isLocked {
			return errCredentialLocked
		}
	}
	return errCredentialMissing
}

func (secretCredentialStore) Load(ctx context.Context) (string, error) {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return "", err
	}
	defer conn.Close()
	if err = inspectCredential(ctx, conn); err != nil {
		return "", err
	}
	raw, err := exec.CommandContext(ctx, "secret-tool", "lookup", "application", "quickshell-beeper", "service", "beeper-api").Output()
	if err != nil {
		return "", err
	}
	token := strings.TrimSpace(string(raw))
	if token == "" {
		return "", errCredentialMissing
	}
	return token, nil
}

func (secretCredentialStore) Store(ctx context.Context, token string) error {
	cmd := exec.CommandContext(ctx, "secret-tool", "store", "--label=Quickshell · Beeper API", "application", "quickshell-beeper", "service", "beeper-api")
	cmd.Stdin = strings.NewReader(token)
	return cmd.Run()
}

func (b *backend) snapshotLocked() object {
	return object{"state": b.stateName, "message": b.stateMessage, "revision": b.stateRevision, "demo": b.demo}
}
func (b *backend) statusSnapshot() object {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.snapshotLocked()
}
func (b *backend) setStatusLocked(state, message string) object {
	b.stateName, b.stateMessage = state, message
	b.stateRevision++
	return b.snapshotLocked()
}
func (b *backend) status(state, message string) { b.statusForContext(b.ctx, state, message) }
func (b *backend) statusForContext(ctx context.Context, state, message string) {
	b.mu.Lock()
	if ctx.Err() != nil {
		b.mu.Unlock()
		return
	}
	snapshot := b.setStatusLocked(state, message)
	b.mu.Unlock()
	b.emit("status", snapshot)
}
func (b *backend) credentialStatus(state, message string) {
	b.mu.Lock()
	if b.ctx.Err() != nil || b.client != nil {
		b.mu.Unlock()
		return
	}
	snapshot := b.setStatusLocked(state, message)
	b.mu.Unlock()
	b.emit("status", snapshot)
}
func (b *backend) wakeCredentials() {
	select {
	case b.credentialWake <- struct{}{}:
	default:
	}
}

func (b *backend) initialize() {
	b.mu.Lock()
	if b.restoringCredentials || b.client != nil || b.demo || b.ctx.Err() != nil {
		b.mu.Unlock()
		return
	}
	b.restoringCredentials = true
	b.mu.Unlock()
	defer func() { b.mu.Lock(); b.restoringCredentials = false; b.mu.Unlock() }()
	b.credentialStatus("loading-token", "Restoring your saved access token…")
	for b.ctx.Err() == nil {
		b.mu.Lock()
		configured := b.client != nil
		b.mu.Unlock()
		if configured {
			return
		}
		token := strings.TrimSpace(os.Getenv("BEEPER_ACCESS_TOKEN"))
		var err error
		if token == "" {
			ctx, cancel := context.WithTimeout(b.ctx, 10*time.Second)
			token, err = b.credentials.Load(ctx)
			cancel()
		}
		if b.ctx.Err() != nil {
			return
		}
		if err == nil && token != "" {
			b.installClient(token, false)
			return
		}
		delay := b.credentialRetryDelay
		if err == nil || errors.Is(err, errCredentialMissing) {
			b.credentialStatus("needs-token", "No Beeper token is saved in the keyring.")
			delay = 30 * time.Second
		} else if errors.Is(err, errCredentialLocked) {
			b.credentialStatus("keyring-unavailable", "Unlock the GNOME keyring. The connection will resume automatically.")
		} else {
			b.credentialStatus("keyring-unavailable", "The keyring is temporarily unavailable. Retrying automatically…")
		}
		timer := time.NewTimer(delay)
		select {
		case <-b.ctx.Done():
			timer.Stop()
			return
		case <-b.credentialWake:
			timer.Stop()
		case <-timer.C:
		}
	}
}

func (b *backend) reconnect() {
	b.mu.Lock()
	token := b.token
	b.mu.Unlock()
	if token != "" {
		b.installClient(token, true)
		return
	}
	b.credentialStatus("loading-token", "Restoring your saved access token…")
	b.wakeCredentials()
	go b.initialize()
}
