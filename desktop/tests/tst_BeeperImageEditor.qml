import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var editor: null
  property var panel: null
  property var beeperData: null
  property var exportedImage: null
  property int exportSequence: 0
  readonly property string exportDirectory: Quickshell.env("BEEPER_DRAWING_TEST_DIR")
  readonly property var attachment: ({type: "image", fileName: "original.png", path: "/fixture/original.png",
    srcURL: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><rect width="200" height="100" fill="white"/></svg>')})
  QtObject {
    id: transport
    property var pending: []
    property var discarded: []
    function request(method, params, callback, quiet) {
      if (method === "prepareImageEdit") pending = pending.concat([{params: params, callback: callback}]);
      else if (method === "discardAttachment") discarded = discarded.concat([params.path]);
    }
    function prepared() {
      const request = pending[0]; pending = pending.slice(1);
      const path = fixture.exportDirectory + "/drawing-" + (++fixture.exportSequence) + ".png";
      const result = {path: path, srcURL: "file://" + path, type: "image", mimeType: "image/png", fileName: "original-edited.png"};
      request.callback(result, null); return result;
    }
  }
  Window { id: window; visible: true; width: 900; height: 650 }
  SignalSpy { id: saved; target: fixture.editor; signalName: "saved" }
  SignalSpy { id: cancelled; target: fixture.editor; signalName: "cancelRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperImageEditor"
    when: window.visible
    function create(file, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(window.contentItem, props); verify(item !== null); return item;
    }
    function init() {
      transport.pending = []; transport.discarded = [];
      editor = create("../features/messenger/BeeperImageEditor.qml", {width: 900, height: 650, attachment: fixture.attachment, beeperData: transport});
      tryCompare(editor, "imageReady", true);
      editor.forceActiveFocus(); saved.clear(); cancelled.clear();
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName, editor?.errorText);
      if (exportedImage) { exportedImage.destroy(); exportedImage = null; }
      if (panel) { panel.active = false; panel.destroy(); panel = null; }
      if (beeperData) { beeperData.destroy(); beeperData = null; }
      editor.destroy(); editor = null; wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperImageEditor: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function draw() {
      const area = findChild(editor, "beeperDrawingMouse");
      mousePress(area, area.width * 0.25, area.height * 0.5);
      mouseMove(area, area.width * 0.5, area.height * 0.5);
      mouseRelease(area, area.width * 0.75, area.height * 0.5);
    }
    function test_mouse_palette_brush_size_undo_redo_and_clear() {
      const area = findChild(editor, "beeperDrawingMouse");
      verify(area.width > 700); verify(area.height > 300);
      mouseClick(findChild(editor, "beeperDrawingColor6"));
      compare(editor.brushColor.toString(), "#8aadf4");
      const size = findChild(editor, "beeperDrawingSize");
      mouseClick(size, size.width * 0.8, size.height / 2); verify(editor.brushSize > 16);
      draw(); compare(editor.strokes.length, 1); compare(editor.strokes[0].color, "#8aadf4");
      verify(editor.strokes[0].points.length >= 2);
      mouseClick(findChild(editor, "beeperDrawingUndo")); compare(editor.strokes.length, 0);
      mouseClick(findChild(editor, "beeperDrawingRedo")); compare(editor.strokes.length, 1);
      mouseClick(findChild(editor, "beeperDrawingClear")); verify(!editor.dirty);
      compare(saved.count, 0); compare(transport.pending.length, 0);
    }
    function test_tip_is_visible_while_mouse_is_still_pressed() {
      editor.brushColor = "#0000ff"; editor.brushSize = 18;
      const area = findChild(editor, "beeperDrawingMouse"), frame = findChild(editor, "beeperDrawingImage");
      mousePress(area, area.width * 0.25, area.height * 0.5);
      mouseMove(area, area.width * 0.6, area.height * 0.5);
      verify(editor.currentStroke !== null); compare(editor.strokes.length, 0);
      verify(waitForRendering(frame));
      const pixels = grabImage(window.contentItem);
      const tip = area.mapToItem(window.contentItem, area.width * 0.6, area.height * 0.5);
      const x = Math.floor(tip.x * pixels.width / window.width), y = Math.floor(tip.y * pixels.height / window.height);
      compare(pixels.blue(x, y), 255); compare(pixels.red(x, y), 0);
      mouseRelease(area, area.width * 0.6, area.height * 0.5);
    }
    function test_long_strokes_freeze_finished_geometry_and_undo_without_repainting() {
      const area = findChild(editor, "beeperDrawingMouse");
      editor.beginStroke(10, area.height / 2);
      for (let i = 1; i <= 60; ++i) editor.extendStroke(10 + i * 2, area.height / 2);
      const visual = editor.currentStroke.visual, frozen = visual.chunks[0], points = JSON.stringify(frozen.points);
      for (let i = 61; i <= 4000; ++i)
        editor.extendStroke(10 + (i * 2) % (area.width - 20), area.height / 2 + Math.sin(i * 0.04) * 60);
      compare(visual.chunks[0], frozen); compare(JSON.stringify(frozen.points), points);
      verify(visual.chunks.length > 4);
      for (const chunk of visual.chunks) verify(chunk.points.length <= visual.chunkLimit);
      editor.endStroke(); editor.undo(); verify(!visual.visible);
      editor.redo(); verify(visual.visible); compare(editor.strokes[0].visual, visual);
      editor.undo(); editor.beginStroke(20, 20); editor.endStroke();
      compare(editor.redoStrokes.length, 0); compare(editor.strokes.length, 1);
      editor.clearDrawing(); wait(0);
      compare(findChild(editor, "beeperDrawingInk").children.length, 0);
    }
    function test_cancel_does_not_change_or_save_original() {
      draw(); keyClick(Qt.Key_Escape);
      compare(cancelled.count, 1); compare(saved.count, 0); compare(transport.pending.length, 0);
      compare(editor.attachment.path, "/fixture/original.png");
    }
    function test_cancel_during_preparation_discards_late_output() {
      draw(); mouseClick(findChild(editor, "beeperDrawingDone")); compare(transport.pending.length, 1);
      mouseClick(findChild(editor, "beeperDrawingCancel")); compare(cancelled.count, 1);
      const output = transport.prepared();
      compare(transport.discarded, [output.path]); compare(saved.count, 0);
    }
    function test_export_keeps_native_resolution_and_contains_the_drawing() {
      if (!fixture.exportDirectory) { skip("Set BEEPER_DRAWING_TEST_DIR to a private temporary directory"); return; }
      editor.brushColor = "#0000ff"; editor.brushSize = 24;
      draw(); mouseClick(findChild(editor, "beeperDrawingDone"));
      const output = transport.prepared();
      tryCompare(saved, "count", 1, 5000);
      compare(saved.signalArguments[0][0].path, output.path);
      editor.visible = false;
      exportedImage = Qt.createQmlObject('import QtQuick; Image { width: 200; height: 100; cache: false }', window.contentItem);
      exportedImage.source = output.srcURL;
      tryCompare(exportedImage, "status", Image.Ready);
      compare(exportedImage.implicitWidth, 200); compare(exportedImage.implicitHeight, 100);
      verify(waitForRendering(exportedImage));
      const pixels = grabImage(exportedImage);
      compare(pixels.blue(pixels.width / 2, pixels.height / 2), 255);
      compare(pixels.red(pixels.width / 2, pixels.height / 2), 0);
      compare(pixels.pixel(2, 2), "#ffffff");
      compare(editor.attachment.path, "/fixture/original.png"); compare(transport.discarded.length, 0);
    }
    function test_draft_button_opens_large_editor_and_replaces_only_selected_image() {
      editor.visible = false;
      beeperData = create("fixtures/PagedBeeperData.qml", {deferImageEdits: true});
      beeperData.chats = [{id: "chat", title: "Chat"}]; beeperData.currentChatID = "chat";
      beeperData.draftText = "My caption"; beeperData.replyToMessageID = "reply";
      beeperData.draftAttachments = [fixture.attachment, {type: "file", path: "/fixture/keep.txt", fileName: "keep.txt"}];
      panel = create("../features/messenger/BeeperPanel.qml", {width: 900, height: 650, active: true, windowFocused: true, beeperData: beeperData});
      const button = findChild(panel, "beeperDrawAttachment0"); tryCompare(button, "enabled", true);
      mouseClick(button); tryCompare(panel, "imageEditorOpen", true);
      const large = findChild(panel, "beeperImageEditor"); verify(large !== null);
      compare(large.width, panel.width); compare(large.height, panel.height);
      const replacement = {type: "image", path: "/fixture/edited.png", srcURL: fixture.attachment.srcURL};
      panel.completeImageEdit(replacement);
      compare(panel.imageEditorOpen, false); compare(beeperData.draftAttachments[0].path, replacement.path);
      compare(beeperData.draftAttachments[1].path, "/fixture/keep.txt");
      compare(beeperData.draftText, "My caption"); compare(beeperData.replyToMessageID, "reply");
      compare(beeperData.requests.filter(request => request.method === "send").length, 0);
    }
    function test_stale_edit_cannot_replace_a_different_draft_image() {
      beeperData = create("fixtures/PagedBeeperData.qml", {deferImageEdits: true});
      beeperData.currentChatID = "chat"; beeperData.draftText = "Caption";
      beeperData.draftAttachments = [{type: "image", path: "/fixture/new.png"}];
      const result = {type: "image", path: "/fixture/edited.png"};
      verify(!beeperData.replaceDraftImage("chat", 0, fixture.attachment, result));
      compare(beeperData.draftAttachments[0].path, "/fixture/new.png"); compare(beeperData.draftText, "Caption");
      compare(beeperData.requests.filter(request => request.method === "discardAttachment")[0].params.path, result.path);
    }
  }
}
