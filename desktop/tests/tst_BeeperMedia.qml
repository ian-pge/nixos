import QtQuick
import QtTest
import QtMultimedia
import Quickshell

ShellRoot {
  id: fixture
  property var controls: null
  property var message: null
  property var format: null
  Component.onCompleted: format = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../features/messenger/BeeperFormat.js" as F; QtObject { property var library: F }', fixture).library
  QtObject {
    id: groupData
    property var currentChat: ({id: "group", type: "group"})
    property var senderColors: ({someone: "#c6a0f6"})
    property var accounts: []
    function quote(id) { return {state: "missing", message: null}; }
  }
  QtObject {
    id: player
    property real duration: 34000
    property real position: 0
    property real playbackRate: 1
    property int playbackState: MediaPlayer.StoppedState
    property bool seekable: true
    function play() { playbackState = MediaPlayer.PlayingState; }
    function pause() { playbackState = MediaPlayer.PausedState; }
    function setPosition(value) { position = value; }
  }
  Window { id: window; width: 900; height: 600; visible: true }
  TestResult { id: results }
  TestCase {
    name: "BeeperMedia"
    when: window.visible && fixture.format !== null
    function create(name, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/" + name + ".qml");
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(window.contentItem, props); verify(item !== null); return item;
    }
    function init() {
      player.duration = 34000; player.position = 0; player.playbackRate = 1;
      player.playbackState = MediaPlayer.StoppedState; player.seekable = true;
      controls = create("BeeperPlaybackControls", {width: 392, height: 48, player: player});
      message = null;
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      controls.destroy(); if (message) message.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperMedia: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_compact_audio_has_only_the_message_background() {
      controls.visible = false;
      message = create("BeeperMessage", {width: 800, message: {id: "audio", senderName: "Someone", attachments: [{type: "audio", isVoiceNote: true, duration: 34}]}});
      wait(30);
      const bubble = findChild(message, "beeperMessageBubble"), media = findChild(message, "beeperMedia");
      compare(bubble.width, 420); compare(media.implicitHeight, 48);
      compare(bubble.height, 48 + findChild(message, "beeperSenderName").implicitHeight + 3 + 12);
      verify(media.color === undefined, "Media is an unpainted Item, not a second bubble");
      compare(findChild(media, "beeperMediaTime").text, "0:34");
      message.playbackEnabled = false;
      verify(!findChild(media, "beeperMediaPlay").enabled);
    }
    function test_message_fills_stay_opaque_for_all_selection_and_sender_states() {
      controls.visible = false;
      message = create("BeeperMessage", {width: 680, message: {id: "opaque", text: "Hello"}});
      for (const group of [false, true]) {
        message.beeperData = group ? groupData : null;
        for (const outgoing of [false, true]) {
          message.message = {id: "opaque", text: "Hello", senderID: "someone", isSender: outgoing};
          for (const selected of [false, true]) {
            message.selected = selected;
            compare(message.bubbleColor.a, 1, "Bubble fill must be opaque in every state");
            compare(message.bubbleColor.toString(), outgoing ? message.networkAccent.toString() : "#24273a", "Sent bubbles use the network accent; received bubbles keep Macchiato Base");
            compare(findChild(message, "beeperMessageSelection").visible, selected);
          }
        }
      }
    }
    function test_search_marks_every_literal_occurrence_and_preserves_unicode_offsets() {
      const sample = "Café CAFE\u0301 🐈 café";
      const ranges = fixture.format.searchTextRanges(sample, "cafe 🐈");
      compare(ranges.map(range => sample.slice(range.start, range.end)), ["Café", "CAFE\u0301", "🐈", "café"]);
      compare(fixture.format.searchTextRanges("Chat CHAT chat", "chat").length, 3);
      compare(fixture.format.searchTextRanges("a+b [x] aaaa", "a+b [x]").length, 2, "Search terms are literal, not regular expressions");
      compare(fixture.format.searchTextRanges("banana", "ana nan"), [{start: 1, end: 6}], "Overlaps are highlighted once without nested spans");
      compare(fixture.format.highlightText("Hello", "absent", "#eed49f", "#181926"), "");
      compare(fixture.format.highlightText("Hello", "   ", "#eed49f", "#181926"), "");
    }
    function test_search_markup_cannot_interpret_message_html_or_load_resources() {
      controls.visible = false;
      const text = '<img src="https://not-loaded.invalid/pixel"> & Café\n  <b>café</b>';
      message = create("BeeperMessage", {width: 800, searchQuery: "cafe", message: {id: "safe", text: text}});
      const body = findChild(message, "messageBody"), highlight = findChild(message, "beeperMessageHighlights");
      compare(message.plainBody, text); compare(body.textFormat, Text.PlainText); compare(highlight.textFormat, Text.RichText);
      verify(highlight.text.includes("&lt;img src=&quot;")); verify(highlight.text.includes("&lt;b&gt;")); verify(highlight.text.includes("&amp;"));
      verify(!highlight.text.includes("<img")); verify(!highlight.text.includes("<b>"));
      compare(highlight.text.match(/background-color:/g).length, 2);
      message.searchQuery = "";
      compare(body.textFormat, Text.PlainText); compare(body.text, text); compare(highlight.text, ""); verify(!highlight.visible);
    }
    function test_search_highlights_preserve_bubble_geometry_and_line_breaks_data() {
      return [
        {tag: "single", text: "Chat chat", width: 800},
        {tag: "whitespace", text: "Chat\n  chat\tchat\n\nChat ", width: 800},
        {tag: "wrapped", text: "Chat and other words. ".repeat(20), width: 320},
        {tag: "literal markup", text: "<b>chat</b> & CHAT\n🙂 café", width: 520}
      ];
    }
    function test_search_highlights_preserve_bubble_geometry_and_line_breaks(test) {
      controls.visible = false;
      message = create("BeeperMessage", {width: test.width, message: {id: "geometry", text: test.text}});
      const bubble = findChild(message, "beeperMessageBubble"), body = findChild(message, "messageBody");
      const highlight = findChild(message, "beeperMessageHighlights");
      for (const scale of [1, 1.8]) {
        message.searchQuery = ""; message.textScale = scale; message.forceMessageLayout(); wait(20);
        const size = {width: bubble.width, height: bubble.height, textHeight: body.implicitHeight};
        message.searchQuery = "chat"; message.forceMessageLayout(); wait(20);
        fuzzyCompare(bubble.width, size.width, 0.5, "Highlight does not change bubble width");
        fuzzyCompare(body.implicitHeight, size.textHeight, 0.5, "Highlight preserves text line layout");
        fuzzyCompare(bubble.height, size.height, 0.5, "Highlight does not change bubble height");
        if (Math.abs(highlight.implicitHeight - size.textHeight) > 1)
          console.error("Text layer height", test.tag, scale, highlight.implicitHeight, size.textHeight);
        fuzzyCompare(highlight.implicitHeight, size.textHeight, 1, "Highlighted glyphs use the same line spacing");
      }
    }
    function test_highlight_background_is_really_painted_for_both_message_directions() {
      controls.visible = false;
      message = create("BeeperMessage", {width: 800, searchQuery: "chat", message: {id: "paint", text: "Chat chat"}});
      const body = findChild(message, "messageBody");
      for (const outgoing of [false, true]) {
        message.message = {id: "paint", text: "Chat chat", isSender: outgoing};
        message.forceMessageLayout(); wait(30);
        // Capture the stable window origin, then sample the body's mapped
        // bounds. Cropping a nested, right-anchored item is not reliable here.
        const rendered = grabImage(window.contentItem), point = body.mapToItem(window.contentItem, 0, 0);
        const scaleX = rendered.width / window.width, scaleY = rendered.height / window.height;
        let yellow = 0;
        for (let y = Math.floor(point.y * scaleY); y < (point.y + body.height) * scaleY; ++y)
          for (let x = Math.floor(point.x * scaleX); x < (point.x + body.width) * scaleX; ++x)
            if (rendered.pixel(x, y).toString() === "#eed49f") ++yellow;
        verify(yellow > 50, "The matched words must have a real yellow background, not just colored text");
      }
    }
    function test_selection_dot_is_outside_on_the_opposite_side_with_the_conversation_color() {
      controls.visible = false;
      message = create("BeeperMessage", {width: 800, beeperData: groupData, renderMedia: false,
        networkAccent: "#a6da95", message: {id: "selection", senderID: "someone", text: "Hello"}});
      const bubble = findChild(message, "beeperMessageBubble"), dot = findChild(message, "beeperMessageSelection");
      for (const outgoing of [false, true]) {
        for (const width of [800, 320]) {
          for (const text of ["Hello", "A long message that wraps. ".repeat(10)]) {
            message.width = width;
            message.message = {id: "selection", senderID: "someone", text: text, isSender: outgoing, seen: true};
            message.selected = false; message.forceMessageLayout(); wait(20);
            const bubbleWidth = bubble.width, bubbleHeight = bubble.height, rowHeight = message.height;
            verify(!dot.visible);
            message.selected = true; wait(0);
            verify(dot.visible); compare(dot.color.toString(), "#a6da95");
            compare(dot.width, dot.height); compare(dot.radius, dot.width / 2);
            compare(dot.width, 12);
            if (outgoing) fuzzyCompare(dot.x + dot.width, -6, 0.1);
            else fuzzyCompare(dot.x, bubble.width + 6, 0.1);
            // Qt's centered anchors snap to whole pixels by default.
            fuzzyCompare(dot.y + dot.height / 2, bubble.height / 2, 0.5);
            const point = dot.mapToItem(message, 0, 0);
            verify(point.x >= 0 && point.x + dot.width <= message.width, "The dot must not be clipped at maximum bubble width");
            compare(bubble.width, bubbleWidth, "Selection keeps bubble width");
            compare(bubble.height, bubbleHeight, "Selection keeps bubble height");
            compare(message.height, rowHeight, "Selection keeps row height");
          }
        }
      }
      message.networkAccent = "#7dc4e4";
      compare(dot.color.toString(), "#7dc4e4", "Changing the conversation accent also changes the selection dot");
    }
    function test_play_pause_and_speed_are_native_buttons() {
      const play = findChild(controls, "beeperMediaPlay"), rate = findChild(controls, "beeperMediaRate");
      mouseClick(play); compare(player.playbackState, MediaPlayer.PlayingState);
      mouseClick(play); compare(player.playbackState, MediaPlayer.PausedState);
      compare(play.background.radius, play.width / 2);
      mouseClick(rate); compare(player.playbackRate, 1.5);
      mouseClick(rate); compare(player.playbackRate, 2);
      mouseClick(rate); compare(player.playbackRate, 1);
    }
    function test_thin_seek_track_supports_mouse_vim_and_no_wheel_seeking() {
      const seek = findChild(controls, "beeperMediaSeek");
      compare(seek.background.height, 4); verify(!seek.wheelEnabled);
      mouseClick(seek, seek.width / 2, seek.height / 2);
      verify(player.position > 14000 && player.position < 20000);
      seek.forceActiveFocus(); const position = player.position;
      keyClick(Qt.Key_L); compare(player.position, position + 5000);
      keyClick(Qt.Key_H); compare(player.position, position);
      mouseWheel(seek, seek.width / 2, seek.height / 2, 0, 120, Qt.NoButton);
      compare(player.position, position);
      player.seekable = false; verify(!seek.enabled);
    }
    function test_time_uses_metadata_before_loading_then_player_position() {
      controls.fallbackDuration = 45000; player.duration = 0;
      compare(findChild(controls, "beeperMediaTime").text, "0:45");
      player.duration = 34000; compare(findChild(controls, "beeperMediaTime").text, "0:34");
      player.position = 12000; compare(findChild(controls, "beeperMediaTime").text, "0:12");
    }
    function test_image_has_no_second_card_and_keeps_preview_action() {
      controls.visible = false;
      message = create("BeeperMessage", {width: 700, message: {id: "image", attachments: [{type: "img"}]}});
      wait(20);
      const media = findChild(message, "beeperMedia");
      verify(media.color === undefined); verify(media.implicitHeight > 150);
      verify(findChild(message, "beeperMessageBubble").height >= media.implicitHeight + 12);
    }
    function test_portrait_with_short_caption_fits_content_instead_of_the_whole_row() {
      controls.visible = false;
      message = create("BeeperMessage", {width: 1000, renderMedia: false, message: {
        id: "portrait", isSender: true, text: "Je suis sur la trott", timestamp: "2026-09-25T18:13:00Z",
        attachments: [{type: "img", size: {width: 1080, height: 1920}}]
      }});
      wait(20);
      const bubble = findChild(message, "beeperMessageBubble"), media = findChild(message, "beeperMedia");
      verify(bubble.width < 350, "A short caption and portrait must not create a full-width bubble: " + bubble.width);
      fuzzyCompare(media.implicitWidth, 250 * 1080 / 1920, 0.1);
      compare(media.height, 250, "Keep the photo's height when shrinking the bubble");
      const expected = Math.max(110, media.implicitWidth + 28,
        findChild(message, "messageBody").implicitWidth + 28,
        findChild(message, "beeperSenderName").implicitWidth + 28,
        findChild(message, "beeperMessageMeta").implicitWidth + 28);
      fuzzyCompare(bubble.width, expected, 0.1);
      fuzzyCompare(bubble.mapToItem(message, bubble.width, 0).x, message.width - 14, 0.1);
    }
    function test_visual_dimensions_preserve_ratio_and_stay_within_the_row_data() {
      return [
        {tag: "portrait", type: "img", width: 1080, height: 1920},
        {tag: "landscape", type: "img", width: 1600, height: 900},
        {tag: "square GIF", type: "gif", width: 512, height: 512},
        {tag: "panorama", type: "img", width: 3000, height: 300},
        {tag: "small image", type: "img", width: 120, height: 80},
        {tag: "portrait video", type: "video", width: 1080, height: 1920}
      ];
    }
    function test_visual_dimensions_preserve_ratio_and_stay_within_the_row(data) {
      controls.visible = false;
      message = create("BeeperMessage", {width: 1000, renderMedia: false, message: {
        id: "sized", senderName: "A", attachments: [{type: data.type, size: {width: data.width, height: data.height}}]
      }});
      wait(20);
      const bubble = findChild(message, "beeperMessageBubble"), media = findChild(message, "beeperMedia");
      const preferred = Math.max(data.type === "video" ? 240 : 0, Math.min(data.width, 250 * data.width / data.height));
      fuzzyCompare(media.implicitWidth, preferred, 0.1);
      fuzzyCompare(bubble.width, Math.min(680, Math.max(110, preferred + 28)), 0.1);
      for (const rowWidth of [1000, 400, 260]) {
        message.width = rowWidth; wait(0);
        verify(bubble.width <= rowWidth - 76);
        fuzzyCompare(media.height, Math.min(250, data.height, media.width * data.height / data.width), 0.1);
        const point = bubble.mapToItem(message, 0, 0);
        verify(point.x >= 0 && point.x + bubble.width <= rowWidth);
      }
    }
    function test_loaded_image_dimensions_survive_offscreen_unloading_and_do_not_leak_to_another_source() {
      controls.visible = false;
      const source = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="400"><rect width="200" height="400" fill="#a6da95"/></svg>');
      message = create("BeeperMessage", {width: 1000, message: {
        id: "decoded", senderName: "A", attachments: [{type: "img", srcURL: source}]
      }});
      const bubble = findChild(message, "beeperMessageBubble"), media = findChild(message, "beeperMedia");
      tryCompare(media, "decodedSource", source);
      fuzzyCompare(media.implicitWidth, 125, 0.1);
      fuzzyCompare(bubble.width, 153, 0.1);
      const height = message.height;
      message.renderMedia = false; wait(20);
      verify(findChild(media, "beeperMediaImage") === null);
      compare(bubble.width, 153); compare(message.height, height);
      message.renderMedia = true;
      tryVerify(() => findChild(media, "beeperMediaImage")?.status === Image.Ready);
      compare(bubble.width, 153); compare(message.height, height);
      const image = findChild(media, "beeperMediaImage");
      fuzzyCompare(image.paintedWidth, 125, 0.1); compare(image.paintedHeight, 250);
      message.renderMedia = false;
      media.attachment = {type: "img", srcURL: "data:pending", size: {width: 800, height: 400}};
      compare(media.implicitWidth, 500, "Decoded dimensions belong only to their own source");
      compare(bubble.width, 528);
    }
    function test_long_caption_and_multiple_attachments_take_only_the_largest_required_width() {
      controls.visible = false;
      message = create("BeeperMessage", {width: 1000, renderMedia: false, message: {
        id: "album", senderName: "A", text: "A caption longer than the portrait",
        attachments: [{type: "img", size: {width: 100, height: 200}}, {type: "img", size: {width: 400, height: 300}}]
      }});
      wait(20);
      const bubble = findChild(message, "beeperMessageBubble"), body = findChild(message, "messageBody");
      fuzzyCompare(bubble.width, Math.max(body.implicitWidth, 250 * 400 / 300) + 28, 0.1);
      message.message = {id: "album", senderName: "A", text: "Long caption. ".repeat(30),
        attachments: [{type: "img", size: {width: 100, height: 200}}]};
      wait(20); compare(bubble.width, 680); verify(body.implicitHeight > body.font.pixelSize);
      message.message = {id: "album", senderName: "A", text: "Short"};
      wait(20); verify(bubble.width < 150, "Removing media must release its requested width");
    }
    function test_short_file_and_invalid_dimensions_do_not_force_full_width() {
      controls.visible = false;
      message = create("BeeperMessage", {width: 1000, renderMedia: false, message: {
        id: "file", attachments: [{type: "file", fileName: "Note.txt", fileSize: 1024}]
      }});
      wait(20);
      const bubble = findChild(message, "beeperMessageBubble");
      verify(bubble.width < 350);
      message.message = {id: "unknown", attachments: [{type: "img", size: {width: 0, height: -1}}]};
      wait(20); compare(bubble.width, 428);
      verify(isFinite(bubble.height) && bubble.height > 250);
    }
    function test_waveform_bars_follow_real_samples_and_remain_seekable() {
      controls.peaks = [0, 0.2, 0.5, 1, 0.3, 0.8];
      const track = findChild(controls, "beeperWaveform");
      compare(track.barCount, 6); compare(track.height, 32);
      const bars = track.children.filter(item => item.objectName === "beeperWaveformBar");
      compare(bars.length, 6); verify(bars[0].height < bars[3].height);
      compare(bars[3].height, 32);
      const seek = findChild(controls, "beeperMediaSeek");
      mouseClick(seek, seek.width * 0.75, seek.height / 2);
      verify(player.position > 20000); verify(!seek.wheelEnabled);
    }
    function test_name_is_inside_tailed_bubble_and_avatar_is_beside_it() {
      controls.visible = false;
      message = create("BeeperMessage", {width: 800, message: {id: "text", senderName: "Camille", text: "Hello"}});
      wait(20);
      const bubble = findChild(message, "beeperMessageBubble"), name = findChild(message, "beeperSenderName");
      const avatar = findChild(message, "beeperSenderAvatar");
      verify(findChild(message, "beeperMessageShape") !== null);
      const labelPoint = name.mapToItem(bubble, 0, 0);
      verify(labelPoint.x > 0 && labelPoint.y > 0); compare(name.text, "Camille");
      const bubblePoint = bubble.mapToItem(message, 0, 0);
      verify(avatar.x + avatar.width < bubblePoint.x);
    }
  }
}
