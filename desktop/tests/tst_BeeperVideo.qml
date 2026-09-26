import QtQuick
import QtTest
import QtMultimedia
import Quickshell

// Local silent video and fake downloads only: never opens real conversations.
// fullscreen-video.mp4 is a generated 20 s H.264 clip: 320x180, 5 fps,
// solid #4080c0, no audio (FFmpeg lavfi color, libx264 ultrafast, GOP 5).
ShellRoot {
  id: fixture
  property var beeperData: null
  property var viewer: null
  readonly property string videoSource: "file://" + Quickshell.shellDir + "/fixtures/fullscreen-video.mp4"
  Window { id: window; width: 900; height: 600; visible: true }
  SignalSpy { id: closed; target: fixture.viewer; signalName: "closeRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperVideo"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props); verify(item !== null); return item;
    }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      viewer = create("../features/messenger/BeeperPhotoViewer.qml", window.contentItem,
        {width: 900, height: 600, beeperData: beeperData, visible: false, active: false});
      viewer.closeRequested.connect(() => { viewer.active = false; viewer.visible = false; });
      closed.clear();
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      viewer.active = false; viewer.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperVideo: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function show(source) {
      viewer.attachment = {type: "video", srcURL: source, duration: 20, size: {width: 320, height: 180}};
      viewer.visible = true; viewer.active = true; viewer.forceActiveFocus();
    }
    function media() { return findChild(viewer, "beeperFullscreenPhoto"); }
    function player() { return findChild(viewer, "beeperMediaPlayer"); }
    function downloads() { return beeperData.requests.filter(request => request.method === "download"); }
    function waitPlaying() {
      tryVerify(() => player() !== null);
      tryCompare(player(), "playbackState", MediaPlayer.PlayingState, 3000);
      verify(!media().playWhenReady);
    }
    function test_video_autoplays_space_pauses_and_escape_stops() {
      show(fixture.videoSource); waitPlaying();
      tryVerify(() => player().duration > 19000 && player().seekable);
      const output = findChild(viewer, "beeperMediaVideo");
      compare(output.width, viewer.width); compare(output.height, viewer.height);
      compare(output.fillMode, VideoOutput.PreserveAspectFit);
      keyClick(Qt.Key_Space); tryCompare(player(), "playbackState", MediaPlayer.PausedState);
      compare(closed.count, 0); verify(viewer.visible);
      keyClick(Qt.Key_Space); waitPlaying();
      keyClick(Qt.Key_Escape); tryCompare(viewer, "visible", false); compare(closed.count, 1);
      wait(30); verify(!player() || player().playbackState !== MediaPlayer.PlayingState);
      verify(!media().playWhenReady);
    }
    function test_video_shortcuts_work_from_controls_and_seek_by_five_seconds_with_bounds() {
      show(fixture.videoSource); waitPlaying();
      keyClick(Qt.Key_Space); tryCompare(player(), "playbackState", MediaPlayer.PausedState);
      findChild(viewer, "beeperMediaRate").forceActiveFocus();
      keyClick(Qt.Key_Space); waitPlaying(); compare(player().playbackRate, 1, "Space must not activate the focused speed button");
      keyClick(Qt.Key_Space); tryCompare(player(), "playbackState", MediaPlayer.PausedState);
      tryVerify(() => player().seekable);
      player().setPosition(250); keyClick(Qt.Key_H); tryCompare(player(), "position", 0);
      keyClick(Qt.Key_L); tryVerify(() => Math.abs(player().position - 5000) < 250);
      compare(player().playbackState, MediaPlayer.PausedState);
      keyClick(Qt.Key_H); tryCompare(player(), "position", 0);
      player().setPosition(player().duration - 100); keyClick(Qt.Key_L);
      tryVerify(() => Math.abs(player().position - player().duration) < 250);
      verify(player().position <= player().duration);
    }
    function test_pause_during_download_and_closing_prevent_late_autoplay() {
      show("mxc://fixture/video-a");
      tryVerify(() => downloads().length === 1 && media().playWhenReady);
      keyClick(Qt.Key_Space); verify(!media().playWhenReady); verify(viewer.visible);
      beeperData.respond("download", {srcURL: fixture.videoSource});
      tryVerify(() => player() && player().duration > 19000); wait(100);
      verify(player().playbackState !== MediaPlayer.PlayingState);
      keyClick(Qt.Key_Space); waitPlaying();
      keyClick(Qt.Key_Escape); wait(20);
      show("mxc://fixture/video-b"); tryCompare(media(), "downloading", true);
      keyClick(Qt.Key_Escape); verify(!viewer.visible);
      beeperData.respond("download", {srcURL: fixture.videoSource}); wait(100);
      verify(!media().playWhenReady);
      verify(!player() || player().playbackState !== MediaPlayer.PlayingState);
    }
    function test_old_download_cannot_replace_a_new_video() {
      show("mxc://fixture/old"); tryCompare(media(), "downloading", true);
      show("mxc://fixture/new"); tryVerify(() => downloads().length === 2);
      beeperData.respond("download", {srcURL: "file:///not-the-selected-video.mp4"});
      compare(media().sourceUrl, "mxc://fixture/new"); verify(media().downloading);
      beeperData.respond("download", {srcURL: fixture.videoSource});
      waitPlaying(); compare(media().sourceUrl, fixture.videoSource); compare(media().errorText, "");
    }
  }
}
