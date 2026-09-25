package main

import (
	"bufio"
	"bytes"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

type notificationCall struct {
	AppName string
	Body    string
	Actions []string
	Hints   map[string]dbus.Variant
}
type notificationService struct {
	calls  chan notificationCall
	markup atomic.Bool
}

func (s *notificationService) GetCapabilities() ([]string, *dbus.Error) {
	caps := []string{"actions", "body"}
	if s.markup.Load() {
		caps = append(caps, "body-markup")
	}
	return caps, nil
}

func (s *notificationService) Notify(app string, replaces uint32, icon, summary, body string, actions []string, hints map[string]dbus.Variant, timeout int32) (uint32, *dbus.Error) {
	s.calls <- notificationCall{app, body, actions, hints}
	return 42, nil
}

// No diagnostic test connects to the user's notifications or secret store.
func privateTestBus(t *testing.T) {
	t.Helper()
	bin, err := exec.LookPath("dbus-daemon")
	if err != nil {
		t.Skip("dbus-daemon not in PATH; run in the Go development shell")
	}
	// Unix socket paths must fit even for long test names/Nix TMPDIR paths.
	dir, err := os.MkdirTemp("/tmp", "qb-bus-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	configPath := filepath.Join(dir, "bus.conf")
	config := `<busconfig><type>session</type><listen>unix:tmpdir=` + dir + `</listen><auth>EXTERNAL</auth><policy context="default"><allow send_destination="*"/><allow receive_sender="*"/><allow own="*"/></policy></busconfig>`
	if err = os.WriteFile(configPath, []byte(config), 0600); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(bin, "--config-file="+configPath, "--nofork", "--nopidfile", "--print-address=1")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err = cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	scanner := bufio.NewScanner(stdout)
	if !scanner.Scan() {
		_ = cmd.Wait()
		t.Fatalf("private bus did not start: %s", stderr.String())
	}
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", scanner.Text())
}

func TestDBusNotificationIdentityMarkupAndClick(t *testing.T) {
	privateTestBus(t)
	server, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	service := &notificationService{calls: make(chan notificationCall, 2)}
	if err = server.Export(service, "/org/freedesktop/Notifications", "org.freedesktop.Notifications"); err != nil {
		t.Fatal(err)
	}
	if _, err = server.RequestName("org.freedesktop.Notifications", dbus.NameFlagDoNotQueue); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	events := make(chan object, 1)
	n, err := newNotifier(ctx, func(name string, data any) {
		if name == "openChat" {
			events <- data.(object)
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	defer n.close()
	n.send("Camille", "L'atelier & <b>texte</b>", "", object{"chatID": "chat", "messageID": "message"}, true)
	select {
	case call := <-service.calls:
		if call.AppName != "Messages" || call.Hints["desktop-entry"].Value() != "quickshell-beeper" {
			t.Fatal("wrong application identity")
		}
		if call.Body != "L'atelier & <b>texte</b>" || call.Hints["suppress-sound"].Value() != true {
			t.Fatal("plain-text content changed or silent hint missing")
		}
		if len(call.Actions) != 2 || call.Actions[0] != "default" {
			t.Fatal("default action missing")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no Notify call")
	}
	service.markup.Store(true)
	n.send("Camille", "L'atelier & <b>texte</b>", "", object{"chatID": "chat", "messageID": "message"}, true)
	select {
	case call := <-service.calls:
		if call.Body != "L&#39;atelier &amp; &lt;b&gt;texte&lt;/b&gt;" {
			t.Fatal("markup-enabled server must receive escaped text")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no markup-aware Notify call")
	}
	if err = server.Emit("/org/freedesktop/Notifications", "org.freedesktop.Notifications.ActionInvoked", uint32(42), "default"); err != nil {
		t.Fatal(err)
	}
	select {
	case target := <-events:
		if target["chatID"] != "chat" || target["messageID"] != "message" {
			t.Fatal("wrong click target")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("click not delivered")
	}
}
