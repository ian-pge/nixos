import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

FocusScope {
  id: root
  objectName: "beeperImageEditor"
  required property var beeperData
  required property var attachment
  property bool active: true
  property color accent: Theme.sideApplications
  property color brushColor: "#ed8796"
  property real brushSize: 6
  property var strokes: []
  property var redoStrokes: []
  property var currentStroke: null
  property bool saving: false
  property string errorText: ""
  property var operation: ({alive: true, output: null})
  readonly property string sourceUrl: Format.attachmentSource(attachment || {})
  readonly property bool imageReady: photo.status === Image.Ready && photo.implicitWidth > 0 && photo.implicitHeight > 0
  readonly property bool dirty: strokes.length > 0 || currentStroke !== null
  signal cancelRequested()
  signal saved(var attachment)

  function point(x, y) { return {x: Math.max(0, Math.min(1, x / photoFrame.width)), y: Math.max(0, Math.min(1, y / photoFrame.height))}; }
  function beginStroke(x, y) {
    if (!active || saving || !imageReady) return;
    for (const stroke of redoStrokes) stroke.visual.destroy();
    redoStrokes = [];
    const first = point(x, y), width = brushSize / photoFrame.width;
    currentStroke = {color: brushColor.toString(), width: width, points: [first],
      visual: strokeComponent.createObject(ink, {color: brushColor, relativeWidth: width})};
    currentStroke.visual.append(first);
  }
  function extendStroke(x, y) {
    if (!currentStroke) return;
    const next = point(x, y), last = currentStroke.points[currentStroke.points.length - 1];
    if (Math.hypot((next.x - last.x) * photoFrame.width, (next.y - last.y) * photoFrame.height) < 1) return;
    currentStroke.points.push(next);
    currentStroke.visual.append(next);
  }
  function endStroke() {
    if (!currentStroke) return;
    strokes = strokes.concat([currentStroke]); currentStroke = null;
  }
  function undo() {
    if (saving) return;
    endStroke();
    if (!strokes.length) return;
    strokes[strokes.length - 1].visual.visible = false;
    redoStrokes = redoStrokes.concat([strokes[strokes.length - 1]]);
    strokes = strokes.slice(0, -1);
  }
  function redo() {
    if (saving || !redoStrokes.length) return;
    redoStrokes[redoStrokes.length - 1].visual.visible = true;
    strokes = strokes.concat([redoStrokes[redoStrokes.length - 1]]);
    redoStrokes = redoStrokes.slice(0, -1);
  }
  function clearDrawing() {
    if (saving) return;
    for (const stroke of strokes.concat(redoStrokes, currentStroke ? [currentStroke] : [])) stroke.visual.destroy();
    strokes = []; redoStrokes = []; currentStroke = null;
  }
  Component { id: strokeComponent; BeeperInkStroke {} }
  function paintStrokes(ctx, width, height) {
    for (const stroke of currentStroke ? strokes.concat([currentStroke]) : strokes) {
      if (!stroke.points.length) continue;
      const first = stroke.points[0], size = stroke.width * width;
      ctx.strokeStyle = stroke.color; ctx.fillStyle = stroke.color;
      ctx.lineWidth = size; ctx.lineCap = "round"; ctx.lineJoin = "round";
      ctx.beginPath();
      if (stroke.points.length === 1) {
        ctx.arc(first.x * width, first.y * height, size / 2, 0, Math.PI * 2); ctx.fill();
      } else {
        ctx.moveTo(first.x * width, first.y * height);
        for (let i = 1; i < stroke.points.length; ++i) ctx.lineTo(stroke.points[i].x * width, stroke.points[i].y * height);
        ctx.stroke();
      }
    }
  }
  function abandonSave() {
    operation.alive = false;
    if (operation.output?.path) beeperData.request("discardAttachment", {path: operation.output.path}, null, true);
    operation.output = null;
  }
  function cancel() { abandonSave(); cancelRequested(); }
  function saveDrawing() {
    if (saving || !imageReady || !active) return;
    endStroke();
    if (!dirty) { cancelRequested(); return; }
    if (photo.implicitWidth * photo.implicitHeight > 64 * 1024 * 1024) { errorText = "This image is too large to edit."; return; }
    saving = true; errorText = "";
    const pending = {alive: true, output: null}, data = beeperData;
    operation = pending;
    data.request("prepareImageEdit", {fileName: attachment.fileName || "Image"}, (result, error) => {
      if (!pending.alive) { if (result?.path) data.request("discardAttachment", {path: result.path}, null, true); return; }
      if (error || !result?.path) { saving = false; errorText = error?.message || "Could not prepare the edited image."; return; }
      pending.output = result;
      exportCanvas.loadImage(sourceUrl);
      Qt.callLater(writeImage);
    }, true);
  }
  function writeImage() {
    if (!saving || !operation.alive || !operation.output) return;
    if (exportCanvas.isImageError(sourceUrl)) { abandonSave(); saving = false; errorText = "Could not load the image for saving."; return; }
    if (!exportCanvas.available || !exportCanvas.isImageLoaded(sourceUrl)) return;
    if (!operation.painted) { exportCanvas.requestPaint(); return; }
    // save() repaints the whole canvas at native resolution, independent of
    // the preview size and monitor scale. Only the newly allocated PNG is written.
    if (!exportCanvas.save(operation.output.path, Qt.size(photo.implicitWidth, photo.implicitHeight))) {
      abandonSave(); saving = false; errorText = "Could not save the drawing. Your original image is unchanged."; return;
    }
    const result = operation.output;
    operation.output = null; saving = false;
    saved(result);
  }
  onActiveChanged: if (!active) abandonSave()
  Component.onDestruction: abandonSave()
  Keys.onPressed: event => {
    if (event.key === Qt.Key_Escape) { root.cancel(); event.accepted = true; }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) event.accepted = true;
  }
  Shortcut { sequence: "Ctrl+Z"; enabled: root.active && !root.saving; onActivated: root.undo() }
  Shortcut { sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]; enabled: root.active && !root.saving; onActivated: root.redo() }

  Rectangle { anchors.fill: parent; color: Theme.background }
  MouseArea { anchors.fill: parent }
  RowLayout {
    id: header
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
    spacing: 8
    Text {
      Layout.fillWidth: true; text: "Draw on image"; color: Theme.foreground
      font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.label; weight: Font.Medium }
    }
    BeeperButton { objectName: "beeperDrawingUndo"; iconName: "undo-2"; Accessible.name: "Undo stroke"; enabled: root.strokes.length > 0 && !root.saving; onClicked: root.undo() }
    BeeperButton { objectName: "beeperDrawingRedo"; iconName: "redo-2"; Accessible.name: "Redo stroke"; enabled: root.redoStrokes.length > 0 && !root.saving; onClicked: root.redo() }
    BeeperButton { objectName: "beeperDrawingClear"; iconName: "eraser"; Accessible.name: "Clear drawing"; enabled: root.dirty && !root.saving; onClicked: root.clearDrawing() }
    BeeperButton { objectName: "beeperDrawingCancel"; text: "Cancel"; onClicked: root.cancel() }
    BeeperButton { objectName: "beeperDrawingDone"; text: root.saving ? "Saving…" : "Done"; prominent: true; accent: root.accent; enabled: root.imageReady && !root.saving; onClicked: root.saveDrawing() }
  }
  Item {
    id: viewport
    anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: palette.top; margins: 16 }
    Item {
      id: photoFrame
      objectName: "beeperDrawingImage"
      anchors.centerIn: parent
      width: Math.min(parent.width, parent.height * (photo.implicitWidth / Math.max(1, photo.implicitHeight)))
      height: width * photo.implicitHeight / Math.max(1, photo.implicitWidth)
      clip: true
      Rectangle { anchors.fill: parent; color: Theme.surface }
      Image {
        id: photo
        anchors.fill: parent; source: root.sourceUrl; asynchronous: true; cache: true
        fillMode: Image.PreserveAspectFit
        onStatusChanged: if (status === Image.Error) root.errorText = "Could not open this image.";
      }
      Item {
        id: ink
        objectName: "beeperDrawingInk"
        anchors.fill: parent
      }
      MouseArea {
        id: drawingMouse
        objectName: "beeperDrawingMouse"
        anchors.fill: parent; hoverEnabled: true; preventStealing: true
        enabled: root.active && root.imageReady && !root.saving
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.CrossCursor
        onPressed: mouse => root.beginStroke(mouse.x, mouse.y)
        onPositionChanged: mouse => { if (pressed) root.extendStroke(mouse.x, mouse.y); }
        onReleased: mouse => { root.extendStroke(mouse.x, mouse.y); root.endStroke(); }
        onCanceled: root.endStroke()
      }
      Rectangle {
        visible: drawingMouse.containsMouse && !root.saving
        x: drawingMouse.mouseX - width / 2; y: drawingMouse.mouseY - height / 2
        width: root.brushSize; height: width; radius: width / 2
        color: "transparent"; border { width: 1; color: "white" }
      }
    }
    Text {
      anchors.centerIn: parent; visible: !!root.errorText || !root.imageReady
      text: root.errorText || "Loading image…"; color: root.errorText ? Theme.error : Theme.secondary
      font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control }
    }
  }
  Rectangle {
    id: palette
    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
    width: Math.min(parent.width - 32, 670); height: 64; radius: 16; color: Theme.surface
    RowLayout {
      anchors { fill: parent; margins: 12 }
      spacing: 10
      Row {
        spacing: 6
        Repeater {
          model: ["#ffffff", "#181926", "#ed8796", "#f5a97f", "#eed49f", "#a6da95", "#8aadf4", "#c6a0f6"]
          Button {
            required property string modelData
            required property int index
            objectName: "beeperDrawingColor" + index
            width: 28; height: 28; enabled: !root.saving
            Accessible.name: "Brush color " + modelData
            onClicked: root.brushColor = modelData
            background: Rectangle {
              radius: width / 2; color: parent.modelData
              border { width: Qt.colorEqual(root.brushColor, parent.modelData) ? 3 : 1; color: Qt.colorEqual(root.brushColor, parent.modelData) ? Theme.foreground : Theme.secondary }
            }
          }
        }
      }
      Text { text: "Size"; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
      Slider {
        objectName: "beeperDrawingSize"
        Layout.fillWidth: true; Layout.minimumWidth: 60
        from: 2; to: 32; stepSize: 1; value: root.brushSize; enabled: !root.saving
        Accessible.name: "Brush size"
        onMoved: root.brushSize = value
      }
      Text { text: root.brushSize + " px"; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
    }
  }
  // Kept out of the visible scene; a full-resolution repaint happens only on
  // Done. Pointer movement only updates the bounded vector path above.
  Canvas {
    id: exportCanvas
    contextType: "2d"
    opacity: 0
    visible: root.saving
    width: Math.max(1, photo.implicitWidth); height: Math.max(1, photo.implicitHeight)
    property bool renderedImage: false
    onImageLoaded: root.writeImage()
    onAvailableChanged: if (available) Qt.callLater(root.writeImage)
    onPaint: {
      renderedImage = false;
      const ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0, 0, width, height);
      if (!root.saving || !isImageLoaded(root.sourceUrl)) return;
      ctx.drawImage(root.sourceUrl, 0, 0, width, height);
      root.paintStrokes(ctx, width, height);
      renderedImage = true;
    }
    onPainted: if (renderedImage && root.saving && root.operation.alive && root.operation.output) {
      root.operation.painted = true;
      Qt.callLater(root.writeImage);
    }
  }
}
