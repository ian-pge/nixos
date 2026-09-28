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
  property string photoStage: ""
  readonly property string videoSource: "file://" + Quickshell.shellDir + "/fixtures/fullscreen-video.mp4"
  readonly property var photoAttachment: ({type: "image", size: {width: 400, height: 200},
    srcURL: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200"><rect width="400" height="200" fill="#4080c0"/></svg>')})
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
      fixture.photoStage = "";
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      viewer = create("../features/messenger/BeeperPhotoViewer.qml", window.contentItem,
        {width: 900, height: 600, beeperData: beeperData, visible: false, active: false});
      viewer.closeRequested.connect(() => { viewer.active = false; viewer.visible = false; });
      closed.clear();
      inlineMedia = null;
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName, fixture.photoStage,
        "origin", viewer.originRect, "scale", viewer.originScale, "progress", viewer.progress, "closed", closed.count);
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
    function showPhoto(waitForImage = true) {
      inlineMedia = create("../features/messenger/BeeperMedia.qml", window.contentItem,
        {x: 80, y: 100, width: 200, height: 180, attachment: fixture.photoAttachment, beeperData: beeperData});
      tryCompare(findChild(inlineMedia, "beeperMediaImage"), "status", Image.Ready);
      viewer.animationDuration = 300;
      viewer.previewOrigin = inlineMedia;
      viewer.attachment = fixture.photoAttachment;
      viewer.visible = true; viewer.active = true; viewer.forceActiveFocus();
      tryCompare(viewer, "presented", true);
      if (waitForImage) { tryCompare(media(), "previewReady", true); tryCompare(viewer, "waitingForPreview", false); }
    }
    function test_photo_waits_for_fullscreen_decode_before_starting_shared_motion() {
      media().renderEnabled = false;
      showPhoto(false);
      verify(viewer.waitingForPreview); verify(viewer.sharedOrigin);
      wait(350);
      compare(viewer.progress, 0); verify(!viewer.transitionRunning);
      media().renderEnabled = true;
      tryCompare(media(), "previewReady", true);
      tryCompare(viewer, "waitingForPreview", false);
      tryVerify(() => viewer.progress > 0 && viewer.progress < 1);
      tryCompare(viewer, "transitionRunning", false); compare(viewer.progress, 1);
    }
    function test_photo_escape_during_decode_cancels_without_late_open_or_close() {
      media().renderEnabled = false;
      showPhoto(false); verify(viewer.waitingForPreview);
      keyClick(Qt.Key_Escape);
      verify(!viewer.visible); verify(!viewer.waitingForPreview); compare(closed.count, 1);
      media().renderEnabled = true;
      wait(350);
      verify(!viewer.visible); verify(!viewer.transitionRunning); compare(closed.count, 1);
    }
    function test_photo_decode_failure_reveals_error_and_can_still_close() {
      media().renderEnabled = false;
      showPhoto(false); verify(viewer.waitingForPreview);
      media().errorText = "Fixture decoder failure";
      tryCompare(viewer, "waitingForPreview", false); verify(!viewer.sharedOrigin);
      tryCompare(viewer, "progress", 1);
      keyClick(Qt.Key_Escape); tryCompare(viewer, "visible", false); compare(closed.count, 1);
    }
    function test_resolved_thumbnail_opens_without_a_second_download() {
      const attachment = {id: "resolved-photo", type: "image", srcURL: "mxc://fixture/photo", size: {width: 400, height: 200}};
      inlineMedia = create("../features/messenger/BeeperMedia.qml", window.contentItem,
        {x: 80, y: 100, width: 200, height: 180, attachment: attachment, beeperData: beeperData});
      tryCompare(inlineMedia, "downloading", true);
      compare(downloads().length, 1);
      beeperData.respond("download", {srcURL: fixture.photoAttachment.srcURL});
      tryCompare(inlineMedia, "previewReady", true);
      inlineMedia.previewRequested.connect((resolved, origin) => {
        viewer.previewOrigin = origin; viewer.attachment = resolved;
        viewer.active = true; viewer.visible = true;
      });
      inlineMedia.requestPreview();
      tryCompare(viewer, "presented", true); verify(viewer.sharedOrigin);
      compare(viewer.attachment.id, attachment.id);
      compare(viewer.attachment.srcURL, fixture.photoAttachment.srcURL);
      tryCompare(media(), "previewReady", true);
      tryCompare(viewer, "waitingForPreview", false);
      compare(downloads().length, 0, "Reuse the completed thumbnail download without another request");
      viewer.requestClose(); tryCompare(viewer, "visible", false);
    }
    function test_photo_grows_from_painted_thumbnail_without_resizing_or_recreating_image() {
      fixture.photoStage = "show";
      showPhoto(); verify(viewer.sharedOrigin);
      fixture.photoStage = "origin";
      compare(viewer.originRect, Qt.rect(80, 140, 200, 100), "Use painted bounds, including thumbnail letterboxing");
      fuzzyCompare(viewer.originScale, 200 / 900, 0.001);
      const image = findChild(viewer, "beeperMediaImage"), originalSource = image.source.toString();
      fixture.photoStage = "image";
      tryCompare(image, "status", Image.Ready);
      compare(image.width, 900); compare(image.height, 600);
      tryCompare(viewer, "progress", 1);
      tryCompare(viewer, "transitionRunning", false);
      viewer.progress = 0;
      const fitted = media().previewRect;
      const painted = media().mapToItem(viewer, fitted.x, fitted.y);
      fuzzyCompare(painted.x, viewer.originRect.x, 0.5, "The scene graph transform starts at the thumbnail pixels");
      fuzzyCompare(painted.y, viewer.originRect.y, 0.5);
      viewer.progress = 1;
      fixture.photoStage = "close";
      inlineMedia.x += 25;
      viewer.requestClose();
      verify(viewer.closing); verify(viewer.visible); compare(closed.count, 0);
      compare(viewer.originRect.x, 105, "A visible moved thumbnail remains the correct destination");
      wait(35);
      fixture.photoStage = "midclose";
      compare(findChild(viewer, "beeperMediaImage"), image);
      compare(image.source.toString(), originalSource);
      compare(image.width, 900); compare(image.height, 600);
      verify(viewer.progress > 0 && viewer.progress < 1);
      viewer.requestClose();
      fixture.photoStage = "closed";
      tryCompare(viewer, "visible", false); compare(closed.count, 1, "Repeated Escape emits one completed close");
    }
    function test_photo_close_reverses_opening_and_cancelled_close_cannot_close_reopened_photo() {
      showPhoto();
      tryVerify(() => viewer.progress > 0 && viewer.progress < 1);
      const progress = viewer.progress, scale = viewer.imageScale, offset = viewer.imageOffsetX;
      viewer.requestClose();
      compare(viewer.progress, progress); compare(viewer.imageScale, scale); compare(viewer.imageOffsetX, offset);
      verify(viewer.closing);
      viewer.active = false; viewer.visible = false;
      wait(0);
      viewer.attachment = Object.assign({}, fixture.photoAttachment, {id: "another-photo"});
      viewer.active = true; viewer.visible = true; viewer.forceActiveFocus();
      tryCompare(viewer, "progress", 1); wait(40);
      verify(viewer.visible); verify(!viewer.closing); compare(closed.count, 0);
      keyClick(Qt.Key_Escape); tryCompare(viewer, "visible", false); compare(closed.count, 1);
    }
    function test_photo_missing_offscreen_or_recycled_origin_fades_out_safely() {
      fixture.photoStage = "offscreen";
      showPhoto(); tryCompare(viewer, "transitionRunning", false);
      inlineMedia.y = -500;
      viewer.requestClose(); verify(!viewer.sharedOrigin); compare(viewer.imageScale, 1);
      tryCompare(viewer, "visible", false); compare(closed.count, 1);
      fixture.photoStage = "recycled";
      viewer.visible = true; viewer.active = true; viewer.forceActiveFocus();
      tryCompare(viewer, "presented", true); verify(!viewer.sharedOrigin);
      tryCompare(viewer, "transitionRunning", false);
      inlineMedia.y = 100;
      inlineMedia.attachment = {type: "image", srcURL: fixture.photoAttachment.srcURL + "#different"};
      viewer.requestClose(); verify(!viewer.sharedOrigin);
      tryCompare(viewer, "visible", false); compare(closed.count, 2);
      fixture.photoStage = "missing";
      viewer.previewOrigin = null; viewer.visible = true; viewer.active = true; viewer.forceActiveFocus();
      tryCompare(viewer, "presented", true); verify(!viewer.sharedOrigin);
      keyClick(Qt.Key_Space); tryCompare(viewer, "visible", false); compare(closed.count, 3);
    }
    function test_photo_lost_thumbnail_during_opening_keeps_current_transform_and_fades() {
      showPhoto(); tryVerify(() => viewer.progress > 0 && viewer.progress < 1);
      viewer.previewOrigin = null;
      const scale = viewer.imageScale, offset = viewer.imageOffsetX;
      viewer.requestClose();
      compare(viewer.imageScale, scale); compare(viewer.imageOffsetX, offset);
      compare(media().opacity, 1, "Losing the thumbnail must not jump the current image or opacity");
      verify(viewer.closeFadeStart > 0);
      tryCompare(viewer, "visible", false); compare(closed.count, 1);
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
