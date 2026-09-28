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
  property var inlineMedia: null
  property var messageView: null
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
      inlineMedia = null;
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      viewer.active = false; viewer.destroy();
      if (inlineMedia) { inlineMedia.destroy(); inlineMedia = null; wait(0); }
      if (messageView) { messageView.destroy(); messageView = null; wait(0); }
      beeperData.destroy(); wait(0);
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
    function test_hidden_inline_video_never_loads_a_decoder() {
      inlineMedia = create("../features/messenger/BeeperMedia.qml", window.contentItem,
        {width: 400, height: 250, attachment: {type: "video", srcURL: fixture.videoSource, isGif: true},
          beeperData: beeperData, playbackEnabled: false});
      const decoder = findChild(inlineMedia, "beeperMediaPlayer"); verify(decoder !== null);
      compare(decoder.source.toString(), "");
      inlineMedia.playbackEnabled = true;
      tryCompare(decoder, "playbackState", MediaPlayer.PlayingState, 3000);
      inlineMedia.playbackEnabled = false;
      tryCompare(decoder, "playbackState", MediaPlayer.StoppedState);
      compare(decoder.source.toString(), "");
      inlineMedia.visible = false; inlineMedia.playbackEnabled = true;
      compare(decoder.source.toString(), "");
    }
    function test_video_frames_render_with_the_real_wayland_scene_graph() {
      if (Quickshell.env("QT_QUICK_BACKEND") === "software") skip("Run with --video for the normal Wayland scene graph");
      show(fixture.videoSource); waitPlaying();
      verify(waitForRendering(media()));
      tryVerify(() => {
        const frame = grabImage(media()), x = Math.floor(frame.width / 2), y = Math.floor(frame.height / 2);
        return Math.abs(frame.red(x, y) - 64) < 8 && Math.abs(frame.green(x, y) - 128) < 8
          && Math.abs(frame.blue(x, y) - 192) < 8;
      }, 3000, "PlayingState is not enough: the decoded blue frame must actually reach the screen");
    }
    function test_inline_gif_refresh_and_viewport_unloads_keep_event_loop_responsive() {
      inlineMedia = create("../features/messenger/BeeperMedia.qml", window.contentItem,
        {width: 400, height: 250, attachment: {type: "video", srcURL: fixture.videoSource, isGif: true}, beeperData: beeperData});
      for (let i = 0; i < 8; ++i) {
        inlineMedia.renderEnabled = true; inlineMedia.playbackEnabled = true; inlineMedia.visible = true;
        tryVerify(() => findChild(inlineMedia, "beeperMediaPlayer") !== null);
        tryCompare(findChild(inlineMedia, "beeperMediaPlayer"), "playbackState", MediaPlayer.PlayingState, 3000);
        inlineMedia.attachment = Object.assign({}, inlineMedia.attachment);
        wait(20);
        if (i % 2) inlineMedia.renderEnabled = false;
        else inlineMedia.playbackEnabled = false;
        wait(20);
      }
    }
    function test_message_metadata_refresh_preserves_the_inline_decoder() {
      const original = {id: "video-message", chatID: "chat", text: "A clip", attachments: [
        {id: "clip", type: "video", srcURL: fixture.videoSource, isGif: true, size: {width: 320, height: 180}}
      ]};
      messageView = create("../features/messenger/BeeperMessage.qml", window.contentItem,
        {width: 700, message: original, beeperData: beeperData});
      const media = findChild(messageView, "beeperMedia");
      verify(media !== null);
      const decoder = findChild(media, "beeperMediaPlayer");
      verify(decoder !== null);
      tryCompare(decoder, "playbackState", MediaPlayer.PlayingState, 3000);
      for (let index = 0; index < 5; ++index) {
        messageView.message = JSON.parse(JSON.stringify(Object.assign({}, original, {
          isUnread: false, reactions: [{participantID: "friend", reactionKey: index % 2 ? "💙" : "👍", emoji: true}]
        })));
        wait(20);
        compare(findChild(messageView, "beeperMedia"), media);
        compare(findChild(media, "beeperMediaPlayer"), decoder);
        compare(decoder.playbackState, MediaPlayer.PlayingState, "Metadata must not interrupt the GIF");
      }
      messageView.message = Object.assign({}, original, {attachments: []});
      compare(findChild(messageView, "beeperMedia"), null, "Removed attachments must still release their players");
    }
  }
}
