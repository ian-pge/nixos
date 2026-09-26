import Quickshell
import Quickshell.Io
import QtQuick
import QtTest

ShellRoot {
  id: root
  property var notifications: null

  QtObject {
    id: workspace
    property bool hasFullscreen: false
  }
  QtObject {
    id: monitor
    property string name: "TEST"
    property var activeWorkspace: workspace
  }
  Component.onCompleted: {
    if (Quickshell.env("QUICKSHELL_NOTIFICATION_TEST") !== "1") {
      console.error("Run notifications_test.sh to isolate D-Bus, audio and Hyprland first.");
      Qt.exit(1);
      return;
    }
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/notifications/NotificationData.qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString());
      Qt.exit(1);
      return;
    }
    notifications = component.createObject(root, {
      monitors: [monitor],
      focusedMonitor: monitor,
      soundPlayer: Quickshell.shellDir + "/fixtures/notification-sound.sh"
    });
  }

  Process {
    id: sender
    property int exitCode: -1
    onExited: (exitCode, exitStatus) => sender.exitCode = exitCode
    stdout: StdioCollector { id: senderOutput }
  }

  Window {
    id: testWindow
    visible: true
    width: 200
    height: 70
    Loader {
      id: pillLoader
      x: 10
      y: 10
      Component.onCompleted: setSource("file://" + Quickshell.shellDir + "/../ui/Pill.qml", {
        iconOnly: true,
        text: Qt.binding(() => root.notifications?.doNotDisturb ? "󰂛" : "󰂚"),
        accent: "#a6da95",
        forceHovered: Qt.binding(() => (root.notifications?.dndFeedbackActive ?? false)
          && root.notifications?.dndFeedbackTargetMonitor === "TEST"),
        interactive: true
      })
      onStatusChanged: if (status === Loader.Error) Qt.exit(1)
    }
    Connections {
      target: pillLoader.item
      function onLeftClicked() { root.notifications.toggleDoNotDisturb("TEST"); }
    }
  }

  TestResult { id: results }
  TestCase {
    name: "NotificationData"
    when: root.notifications !== null && testWindow.visible && pillLoader.status === Loader.Ready
    readonly property var notifications: root.notifications
    readonly property var pill: pillLoader.item

    function cleanupTestCase() {
      notifications.doNotDisturb = true;
      console.log("NotificationData: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount > 0 ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      notifications.doNotDisturb = true;
      tryVerify(() => notifications.soundProcesses.length === 0);
    }
    function init() {
      notifications.doNotDisturb = false;
      notifications.suppressNativeBeeper = false;
      notifications.suppressChatBanners = false;
      notifications.monitors = [monitor];
      notifications.focusedMonitor = monitor;
      workspace.hasFullscreen = false;
      notifications.soundPlayer = Quickshell.shellDir + "/fixtures/notification-sound.sh";
      mouseMove(testWindow.contentItem, 150, 50);
    }
    function send(title, extra = []) {
      sender.exitCode = -1;
      sender.command = ["notify-send", "--print-id", "--app-name", "Isolated notification test"]
        .concat(extra).concat([title, "Test message"]);
      sender.running = true;
      tryCompare(sender, "running", false, 3000);
      compare(sender.exitCode, 0);
      verify(Number(senderOutput.text.trim()) > 0);
    }
    function test_arrival_and_burst_have_independent_sounds() {
      send("First");
      verify(notifications.visible);
      compare(notifications.current.summary, "First");
      compare(notifications.soundProcesses.length, 1);
      const first = notifications.soundProcesses[0];
      compare(first.command.slice(1, 5), ["--media-role", "Notification", "--volume", "2.0"]);
      send("Second");
      send("Third");
      compare(notifications.current.summary, "Third");
      compare(notifications.soundProcesses.length, 3);
      verify(first.running, "New arrivals must not interrupt previous sounds");
    }
    function test_do_not_disturb_closes_card_stops_sound_and_drops_arrivals() {
      send("Before DND");
      notifications.toggleDoNotDisturb();
      verify(notifications.doNotDisturb);
      verify(!notifications.visible);
      tryVerify(() => notifications.soundProcesses.length === 0);
      tryCompare(notifications, "presented", null);
      send("Quiet", ["--urgency", "low"]);
      send("Normal", ["--urgency", "normal"]);
      send("Critical", ["--urgency", "critical"]);
      verify(!notifications.visible);
      compare(notifications.presented, null);
      compare(notifications.soundProcesses.length, 0);
      notifications.toggleDoNotDisturb();
      verify(!notifications.doNotDisturb);
      wait(100);
      verify(!notifications.visible, "No backlog may replay when leaving DND");
      compare(notifications.soundProcesses.length, 0);
      send("After DND");
      compare(notifications.current.summary, "After DND");
      compare(notifications.soundProcesses.length, 1);
    }
    function test_fullscreen_keeps_existing_and_new_notifications() {
      send("Silent card", ["--hint", "boolean:suppress-sound:true"]);
      verify(notifications.visible);
      compare(notifications.soundProcesses.length, 0);
      workspace.hasFullscreen = true;
      verify(notifications.visible);
      compare(notifications.current.summary, "Silent card");
      send("Fullscreen");
      verify(notifications.visible);
      compare(notifications.current.summary, "Fullscreen");
      compare(notifications.soundProcesses.length, 1);
      notifications.doNotDisturb = true;
      send("Fullscreen DND");
      verify(!notifications.visible);
      compare(notifications.soundProcesses.length, 0);
    }
    function test_notification_lifetime_ends_only_on_dismissal() {
      send("Incoming in messenger", ["--hint", "boolean:suppress-sound:true"]);
      verify(notifications.visible);
      const current = notifications.current;
      wait(50);
      compare(notifications.current, current);
      notifications.close();
      verify(!notifications.visible);
    }
    function test_native_beeper_suppression_does_not_drop_our_notifications() {
      notifications.suppressNativeBeeper = true;
      send("Native Desktop duplicate", ["--app-name", "Beeper"]);
      verify(!notifications.visible);
      compare(notifications.soundProcesses.length, 0);
      send("Our message", ["--app-name", "Messages", "--hint", "string:desktop-entry:quickshell-beeper"]);
      verify(notifications.visible);
      compare(notifications.current.summary, "Our message");
      notifications.close();
      notifications.suppressNativeBeeper = false;
      send("Desktop fallback", ["--app-name", "Beeper"]);
      verify(notifications.visible);
    }
    function test_open_chat_keeps_sounds_without_cards_or_a_later_backlog() {
      tryCompare(notifications, "presented", null);
      notifications.suppressChatBanners = true;
      send("Our chat", ["--app-name", "Messages", "--hint", "string:desktop-entry:quickshell-beeper"]);
      send("Another chat app", ["--hint", "string:category:im.received"]);
      send("Native fallback", ["--app-name", "Beeper"]);
      verify(!notifications.visible); compare(notifications.current, null);
      compare(notifications.presented, null);
      compare(notifications.soundProcesses.length, 3);
      verify(notifications.soundProcesses.every(player => player.running));
      notifications.suppressChatBanners = false; wait(100);
      verify(!notifications.visible); compare(notifications.presented, null);
      compare(notifications.soundProcesses.length, 3, "Closing the chat must not replay arrivals");
      send("After chat closes", ["--hint", "string:desktop-entry:quickshell-beeper"]);
      verify(notifications.visible); compare(notifications.current.summary, "After chat closes");
      compare(notifications.soundProcesses.length, 4);
    }
    function test_opening_chat_hides_an_existing_chat_card_without_stopping_sound() {
      send("Already shown", ["--hint", "string:desktop-entry:quickshell-beeper"]);
      verify(notifications.visible);
      const player = notifications.soundProcesses[0];
      notifications.suppressChatBanners = true;
      verify(!notifications.visible); compare(notifications.presented, null);
      verify(player.running); compare(notifications.soundProcesses.length, 1);
      send("While open", ["--hint", "string:desktop-entry:quickshell-beeper"]);
      verify(!notifications.visible); compare(notifications.soundProcesses.length, 2);
    }
    function test_chat_sounds_do_not_replace_an_unrelated_visible_notification() {
      send("System notification");
      const current = notifications.current;
      notifications.suppressChatBanners = true;
      compare(notifications.current, current);
      send("Incoming chat", ["--hint", "string:category:im.received"]);
      compare(notifications.current, current); compare(notifications.presented, current);
      compare(notifications.soundProcesses.length, 2);
    }
    function test_hidden_chat_banners_keep_dnd_silent_hints_and_duplicate_rules() {
      notifications.suppressChatBanners = true;
      notifications.suppressNativeBeeper = true;
      send("Duplicate", ["--app-name", "Beeper"]);
      send("Silent arrival", ["--hint", "string:desktop-entry:quickshell-beeper", "--hint", "boolean:suppress-sound:true"]);
      compare(notifications.soundProcesses.length, 0); verify(!notifications.visible);
      notifications.doNotDisturb = true;
      send("DND", ["--hint", "string:desktop-entry:quickshell-beeper"]);
      compare(notifications.soundProcesses.length, 0); verify(!notifications.visible);
    }
    function test_missing_monitor_still_closes_and_rejects_notifications() {
      send("Before unplugging", ["--hint", "boolean:suppress-sound:true"]);
      verify(notifications.visible);
      notifications.monitors = [];
      notifications.focusedMonitor = null;
      verify(!notifications.visible);
      send("Without an output");
      verify(!notifications.visible);
      compare(notifications.soundProcesses.length, 0);
    }
    function test_failed_player_is_released() {
      notifications.soundPlayer = "/nonexistent-quickshell-notification-test-player";
      send("Unavailable audio player");
      verify(notifications.visible);
      tryVerify(() => notifications.soundProcesses.length === 0);
    }
    function test_completed_player_is_released() {
      notifications.soundPlayer = "true";
      send("Completed sound");
      verify(notifications.visible);
      tryVerify(() => notifications.soundProcesses.length === 0);
    }
    function test_toggle_feedback_stops_but_muted_icon_remains() {
      compare(pill.width, 36);
      compare(pill.height, 36);
      compare(pill.accent, "#a6da95");
      pill.leftClicked();
      verify(notifications.doNotDisturb);
      verify(pill.hovered);
      const visual = pill.children[0];
      const mutedIcon = pill.text;
      compare(mutedIcon, "󰂛");
      // Pill's opaque hover uses the existing 16% accent tint.
      tryCompare(visual, "color", Qt.tint("#181926", Qt.alpha("#a6da95", 0.16)));
      tryCompare(notifications, "dndFeedbackActive", false, 2500);
      verify(notifications.doNotDisturb, "Ending feedback must not disable DND");
      verify(!pill.hovered, "Active DND must not keep its highlight or bounce");
      tryCompare(visual.transform[0], "y", 0);
      tryCompare(visual, "color", "#181926");
      compare(pill.text, mutedIcon);
      pill.leftClicked();
      verify(!notifications.doNotDisturb);
      verify(pill.hovered, "Unmuting must briefly bounce too");
      compare(pill.text, "󰂚");
      tryCompare(visual, "color", Qt.tint("#181926", Qt.alpha("#a6da95", 0.16)));
      tryCompare(notifications, "dndFeedbackActive", false, 2500);
      tryCompare(visual.transform[0], "y", 0);
      tryCompare(visual, "color", "#181926");
    }
    function test_toggle_feedback_only_highlights_its_target_monitor() {
      notifications.toggleDoNotDisturb("OTHER");
      verify(notifications.dndFeedbackActive);
      compare(notifications.dndFeedbackTargetMonitor, "OTHER");
      verify(!pill.hovered);
      notifications.toggleDoNotDisturb("TEST");
      compare(notifications.dndFeedbackTargetMonitor, "TEST");
      verify(pill.hovered);
    }
  }
}
