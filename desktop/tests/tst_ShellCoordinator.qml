import QtQuick
import QtTest
import Quickshell

// The real presentation policy, with only local QtObject service doubles.
// No shell process, compositor command, device access or update is launched.
ShellRoot {
  id: fixture
  property var controller: null
  property var events: []
  property var lifecycle: []

  Component.onCompleted: {
    if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"
        || !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
      Qt.callLater(() => Qt.exit(1));
      return;
    }
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../shell/ShellCoordinator.qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString()); Qt.callLater(() => Qt.exit(1)); return;
    }
    controller = component.createObject(fixture, {
      services: services, messenger: messenger, focusedMonitor: "A", monitors: ["A", "B"]
    });
  }
  QtObject {
    id: services
    readonly property var notifications: notifications
    readonly property var auth: auth
    readonly property var updates: updates
    readonly property var calendar: calendar
    readonly property var appLauncher: apps
    readonly property var chromeTabs: tabs
    readonly property var brightness: brightness
    readonly property var media: media
    readonly property var dictation: dictation
  }
  QtObject {
    id: notifications
    property bool visible: false
    property string targetMonitor: ""
    function close() { fixture.events.push("notification-close"); visible = false; }
  }
  QtObject {
    id: auth
    property bool active: false
    property string input: ""
    function clearInput() { input = ""; fixture.events.push("auth-clear"); }
  }
  QtObject { id: updates; property bool awaitingPolkit: false }
  QtObject {
    id: calendar
    property string selectedDate: "today"
    readonly property var weather: weather
    function goToday() { selectedDate = "today"; fixture.events.push("calendar-today"); }
  }
  QtObject {
    id: weather
    property bool locationSearchOpen: false
    function closeLocationSearch() { locationSearchOpen = false; }
    function beginCalendarSession() { fixture.events.push("calendar-session"); }
    function refreshIfNeeded() { fixture.events.push("calendar-refresh"); }
  }
  QtObject {
    id: apps
    property string query: ""
    function setQuery(value) { query = value; fixture.events.push("apps-query:" + value); }
    function refreshResults() { fixture.events.push("apps-refresh"); }
  }
  QtObject {
    id: tabs
    property string query: ""
    property int selectedIndex: 0
    function setQuery(value) { query = value; fixture.events.push("tabs-query:" + value); }
    function requestTabs() { fixture.events.push("tabs-request"); }
  }
  QtObject {
    id: brightness
    function queueChange(monitor, delta) { fixture.events.push("brightness:" + monitor + ":" + delta); }
    function reset() { fixture.events.push("brightness-reset"); }
  }
  QtObject { id: media; property var player: ({name: "Fake player"}) }
  QtObject { id: dictation; property bool active: false }
  QtObject {
    id: messenger
    property bool visible: false
    property string targetMonitor: "A"
    property int focusSerial: 0
    readonly property var beeperData: beeperData
    function hide() { visible = false; fixture.events.push("messenger-hide"); }
  }
  QtObject { id: beeperData; property bool viewFocused: false }
  QtObject {
    id: network
    property bool active: fixture.controller !== null && fixture.controller.mode === "wifi"
    property string password: ""
    onActiveChanged: {
      fixture.lifecycle.push("wifi:" + active + ":" + fixture.controller.targetMonitor);
      if (!active) password = "";
    }
  }
  QtObject {
    id: bluetooth
    property bool active: fixture.controller !== null && fixture.controller.mode === "bluetooth"
    onActiveChanged: fixture.lifecycle.push("bluetooth:" + active + ":" + fixture.controller.targetMonitor)
  }

  TestResult { id: results }
  TestCase {
    name: "ShellCoordinator"
    when: fixture.controller !== null
    function cleanupTestCase() {
      console.log("ShellCoordinator: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      controller.close(controller.mode);
    }
    function init() {
      controller.close(controller.mode);
      controller.focusedMonitor = "A";
      controller.monitors = ["A", "B"];
      controller.dictationTargetMonitor = "";
      controller.authPreviousPanel = null;
      controller.authRequestForUpdate = false;
      notifications.visible = false;
      notifications.targetMonitor = "";
      auth.active = false; auth.input = "";
      updates.awaitingPolkit = false;
      media.player = {name: "Fake player"};
      dictation.active = false;
      messenger.visible = false; beeperData.viewFocused = false;
      apps.query = ""; tabs.query = ""; tabs.selectedIndex = 0;
      calendar.selectedDate = "today";
      fixture.events = []; fixture.lifecycle = [];
    }
    function events() { return fixture.events.join(","); }
    function beginAuth(forUpdate = false) {
      updates.awaitingPolkit = forUpdate;
      auth.active = true; auth.input = "temporary-secret";
      controller.beginAuthentication();
    }
    function finishAuth() {
      auth.active = false;
      controller.finishAuthentication();
    }
    function test_one_exclusive_mode_and_explicit_monitor() {
      controller.open("wifi", "A");
      verify(controller.isOpen("wifi", "A"));
      verify(!controller.isOpen("wifi", "B"));
      controller.open("audio", "B");
      compare(controller.mode, "audio"); compare(controller.targetMonitor, "B");
      verify(!network.active);
      controller.close("wifi"); compare(controller.mode, "audio");
      controller.open("unknown", "A"); compare(controller.mode, "audio");
      controller.close("audio");
      compare(controller.mode, "workspaces"); compare(controller.targetMonitor, "");
    }
    function test_monitor_resolution_and_toggle() {
      compare(controller.resolveMonitor(), "A");
      compare(controller.resolveMonitor("B"), "B");
      controller.focusedMonitor = "";
      compare(controller.resolveMonitor(), "A");
      controller.toggle("system"); verify(controller.isOpen("system", "A"));
      controller.toggle("system", "B"); verify(controller.isOpen("system", "B"));
      controller.toggle("system", "B"); compare(controller.mode, "workspaces");
    }
    function test_only_volume_and_brightness_can_share_with_messenger() {
      messenger.visible = true; beeperData.viewFocused = true;
      for (const kind of ["volume", "brightness"]) {
        controller.open(kind, "B");
        verify(messenger.visible);
        compare(messenger.targetMonitor, "A");
        verify(beeperData.viewFocused);
        controller.close(kind);
        verify(messenger.visible);
      }
      verify(events().indexOf("messenger-hide") < 0);
    }
    function test_other_widgets_replace_chat_and_chat_replaces_them() {
      for (const kind of ["audio", "wifi", "bluetooth", "calendar", "system", "launcher", "tabs", "updates", "media"]) {
        messenger.visible = true;
        controller.open(kind, "A");
        verify(!messenger.visible, kind + " replaces the chat");
        compare(controller.mode, kind);
        messenger.visible = true; ++messenger.focusSerial;
        compare(controller.mode, "workspaces", "Opening chat closes " + kind);
      }
    }
    function test_passive_track_feedback_does_not_close_chat() {
      messenger.visible = true;
      controller.showMedia("A");
      verify(messenger.visible); compare(controller.mode, "workspaces");
    }
    function test_notification_cover_reveals_underlying_panel_instead_of_toggling_closed() {
      controller.open("wifi", "A");
      notifications.visible = true; notifications.targetMonitor = "A";
      controller.toggle("wifi", "A");
      verify(controller.isOpen("wifi", "A")); verify(!notifications.visible);
      compare(events(), "notification-close");
      // Re-showing the same presentation does not wipe its credentials.
      compare(fixture.lifecycle.join(","), "wifi:true:A");
      controller.toggle("wifi", "A"); compare(controller.mode, "workspaces");
    }
    function test_other_monitor_notification_does_not_cover_panel() {
      notifications.visible = true; notifications.targetMonitor = "B";
      controller.open("system", "A"); controller.toggle("system", "A");
      compare(controller.mode, "workspaces"); verify(notifications.visible);
      compare(events(), "");
    }
    function test_network_move_ends_old_lifecycle_before_new_monitor() {
      controller.open("wifi", "A"); network.password = "temporary-secret";
      controller.open("wifi", "A"); compare(network.password, "temporary-secret");
      controller.open("wifi", "B");
      compare(network.password, "");
      compare(fixture.lifecycle.join(","), "wifi:true:A,wifi:false:A,wifi:true:B");
      controller.open("bluetooth", "A"); controller.open("bluetooth", "B");
      compare(fixture.lifecycle.filter(event => event.startsWith("bluetooth:")).join(","),
        "bluetooth:true:A,bluetooth:false:A,bluetooth:true:B");
    }
    function test_calendar_fresh_session_move_and_auth_restore() {
      controller.open("calendar", "B");
      compare(events(), "calendar-today,calendar-session,calendar-refresh");
      calendar.selectedDate = "2030-06-15"; fixture.events = [];
      controller.open("calendar", "A");
      compare(calendar.selectedDate, "2030-06-15"); compare(events(), "calendar-refresh");
      controller.focusedMonitor = "B";
      beginAuth(); verify(controller.isOpen("updates", "B"));
      fixture.events = [];
      finishAuth();
      verify(controller.isOpen("calendar", "A"));
      compare(calendar.selectedDate, "2030-06-15");
      compare(events(), "auth-clear,calendar-refresh");
      controller.close("calendar"); fixture.events = [];
      controller.open("calendar", "A"); compare(calendar.selectedDate, "today");
      compare(events(), "calendar-today,calendar-session,calendar-refresh");
    }
    function test_calendar_search_closes_with_its_presentation() {
      controller.open("calendar", "A"); weather.locationSearchOpen = true;
      controller.open("calendar", "B"); verify(weather.locationSearchOpen);
      controller.open("audio", "B"); verify(!weather.locationSearchOpen);
      controller.open("calendar", "A"); weather.locationSearchOpen = true;
      controller.close("calendar"); verify(!weather.locationSearchOpen);
    }
    function test_display_reconfiguration_closes_brightness_feedback() {
      controller.showBrightness("A", false);
      controller.monitors = ["A", "C"];
      compare(controller.mode, "workspaces");
    }
    function test_launcher_preserves_query_on_move_but_resets_on_fresh_open() {
      controller.open("launcher", "A");
      compare(events(), "apps-query:,apps-refresh");
      apps.query = "browser"; fixture.events = [];
      controller.open("launcher", "B");
      compare(apps.query, "browser"); compare(events(), "apps-refresh");
      controller.close("launcher"); fixture.events = [];
      controller.open("launcher", "A");
      compare(apps.query, ""); compare(events(), "apps-query:,apps-refresh");
    }
    function test_tabs_fresh_and_moved_presentations_refresh_catalog_and_selection() {
      controller.open("tabs", "A");
      compare(events(), "tabs-query:,tabs-request");
      tabs.query = "documentation"; tabs.selectedIndex = 5; fixture.events = [];
      controller.open("tabs", "B");
      compare(tabs.query, ""); compare(tabs.selectedIndex, 0);
      compare(events(), "tabs-query:,tabs-request");
    }
    function test_media_suppression_under_interactive_panels() {
      for (const kind of ["audio", "calendar", "system", "wifi", "bluetooth", "updates", "launcher", "tabs"]) {
        controller.open(kind, "A"); controller.showMedia("B");
        verify(controller.isOpen(kind, "A"));
      }
      controller.close(controller.mode);
      media.player = null; controller.showMedia("B");
      compare(controller.mode, "workspaces");
      media.player = {name: "Fake player"};
      controller.showBrightness("A", false); controller.showMedia("B");
      verify(controller.isOpen("media", "B"));
    }
    function test_volume_timeout_restart_and_audio_selector_priority() {
      controller.showVolume("A");
      wait(1100); controller.showVolume("B"); wait(1100);
      verify(controller.isOpen("volume", "B"));
      tryCompare(controller, "mode", "workspaces", 1500);
      controller.open("audio", "A"); controller.showVolume("B");
      verify(controller.isOpen("audio", "A"));
    }
    function test_brightness_refresh_timeout_and_monitor_scoped_callbacks() {
      controller.showBrightness("A"); compare(events(), "brightness:A:0");
      wait(1100); controller.brightnessUpdated("A"); wait(1100);
      verify(controller.isOpen("brightness", "A"));
      tryCompare(controller, "mode", "workspaces", 1500);
      fixture.events = [];
      controller.showBrightness("A", false); compare(events(), "");
      controller.brightnessFailed("B"); verify(controller.isOpen("brightness", "A"));
      controller.brightnessFailed("A"); compare(controller.mode, "workspaces");
      controller.open("system", "B"); controller.brightnessFailed("B");
      verify(controller.isOpen("system", "B"));
    }
    function test_expired_old_osd_cannot_close_new_panel() {
      controller.showVolume("A"); controller.open("wifi", "B");
      wait(2100);
      verify(controller.isOpen("wifi", "B"));
    }
    function test_auth_update_owned_keeps_update_panel_and_clears_waiting_flag() {
      controller.open("updates", "B");
      beginAuth(true);
      verify(controller.authRequestForUpdate); compare(controller.authPreviousPanel, null);
      finishAuth();
      verify(controller.isOpen("updates", "A"));
      verify(!updates.awaitingPolkit); compare(auth.input, "");
      verify(!controller.authRequestForUpdate); compare(controller.authPreviousPanel, null);
    }
    function test_auth_unrelated_restores_original_monitor_not_new_focus() {
      controller.open("system", "B");
      beginAuth();
      verify(controller.isOpen("updates", "A"));
      compare(controller.authPreviousPanel.mode, "system");
      compare(controller.authPreviousPanel.monitor, "B");
      controller.focusedMonitor = "A";
      finishAuth();
      verify(controller.isOpen("system", "B"));
      compare(auth.input, ""); compare(controller.authPreviousPanel, null);
    }
    function test_auth_without_old_panel_or_with_unplugged_target_stays_closed() {
      beginAuth(); finishAuth(); compare(controller.mode, "workspaces");
      controller.open("system", "B"); beginAuth();
      controller.monitors = ["A"];
      finishAuth(); compare(controller.mode, "workspaces");
    }
    function test_auth_does_not_restore_expired_volume_or_brightness_osd() {
      for (const kind of ["volume", "brightness"]) {
        controller.open(kind, "B"); beginAuth(); finishAuth();
        compare(controller.mode, "workspaces");
      }
    }
    function test_auth_media_restore_has_a_fresh_timeout() {
      controller.showMedia("B"); beginAuth(); finishAuth();
      verify(controller.isOpen("media", "B"));
      tryCompare(controller, "mode", "workspaces", 4500);
    }
    function test_system_collectors_follow_visible_target_and_auth() {
      controller.open("system", "A"); verify(controller.systemProcessListsWanted);
      notifications.visible = true; notifications.targetMonitor = "B";
      verify(controller.systemProcessListsWanted);
      notifications.targetMonitor = "A"; verify(!controller.systemProcessListsWanted);
      notifications.visible = false; verify(controller.systemProcessListsWanted);
      dictation.active = true; controller.dictationTargetMonitor = "B";
      verify(controller.systemProcessListsWanted);
      controller.dictationTargetMonitor = "A"; verify(!controller.systemProcessListsWanted);
      dictation.active = false; auth.active = true; verify(!controller.systemProcessListsWanted);
      auth.active = false; verify(controller.systemProcessListsWanted);
      controller.open("audio", "A"); verify(!controller.systemProcessListsWanted);
    }
    function test_unplug_closes_only_target_and_resets_brightness_queue() {
      messenger.visible = true;
      controller.open("wifi", "B"); controller.dictationTargetMonitor = "B";
      verify(!messenger.visible); fixture.events = [];
      controller.monitors = ["A"];
      compare(controller.mode, "workspaces"); compare(controller.dictationTargetMonitor, "");
      verify(!network.active); verify(!messenger.visible);
      compare(events(), "brightness-reset");
      controller.open("system", "A"); controller.monitors = ["A", "C"];
      verify(controller.isOpen("system", "A"));
    }
    function test_dictation_and_microphone_feedback_capture_focused_monitor() {
      controller.focusedMonitor = "B"; dictation.active = true;
      controller.dictationChanged(); compare(controller.dictationTargetMonitor, "B");
      dictation.active = false; controller.dictationChanged();
      compare(controller.dictationTargetMonitor, "");
      controller.showMicrophoneFeedback();
      compare(controller.microphoneFeedbackTargetMonitor, "B");
      verify(controller.microphoneFeedbackActive);
      tryCompare(controller, "microphoneFeedbackActive", false, 2500);
    }
    function test_focus_border_depends_on_panel_or_focused_chat() {
      verify(!controller.highlightFocusedWindow);
      messenger.visible = true; verify(!controller.highlightFocusedWindow);
      beeperData.viewFocused = true; verify(controller.highlightFocusedWindow);
      beeperData.viewFocused = false; verify(!controller.highlightFocusedWindow);
      controller.open("audio", "A"); verify(controller.highlightFocusedWindow);
      controller.close("audio"); verify(!controller.highlightFocusedWindow);
    }
  }
}
