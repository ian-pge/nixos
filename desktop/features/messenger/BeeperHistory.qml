import QtQuick

// The height of a chat is the sum of its actual message layouts, not the
// ListView average-height estimate. Heavy media is enabled by the viewport.
Flickable {
  id: root
  property var model
  property Component delegate
  property Component header
  property real spacing: 8
  readonly property int count: rows.count
  property var movingAnchor: null
  contentWidth: width
  contentHeight: column.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  acceptedButtons: Qt.NoButton

  function forceLayout() {
    for (let i = 0; i < count; ++i) {
      const item = rows.itemAt(i);
      if (item && item.forceMessageLayout) item.forceMessageLayout();
    }
    column.forceLayout();
  }
  function finishLayout() {
    forceLayout();
    for (let i = 0; i < count; ++i) {
      const item = rows.itemAt(i);
      if (item && item.viewportReady !== undefined) item.viewportReady = true;
    }
  }
  function itemAtIndex(index) { return rows.itemAt(index); }
  function indexAt(x, y) {
    let low = 0, high = count - 1;
    while (low <= high) {
      const middle = Math.floor((low + high) / 2), item = rows.itemAt(middle);
      if (!item) return -1;
      if (y < item.y) high = middle - 1;
      else if (y >= item.y + item.height) low = middle + 1;
      else return middle;
    }
    return -1;
  }
  function positionViewAtEnd() { forceLayout(); contentY = Math.max(0, contentHeight - height); }
  function positionViewAtIndex(index, mode) {
    forceLayout();
    const item = rows.itemAt(index);
    if (!item) return;
    let position = contentY;
    if (mode === ListView.Beginning) position = item.y;
    else if (mode === ListView.Center) position = item.y + (item.height - height) / 2;
    else if (mode === ListView.End) position = item.y + item.height - height;
    else if (item.y < contentY) position = item.y;
    else if (item.y + item.height > contentY + height) position = item.y + item.height - height;
    contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), position));
  }
  function captureMovingAnchor() {
    forceLayout();
    const index = Math.max(0, indexAt(1, contentY + 2));
    const item = rows.itemAt(index);
    movingAnchor = item ? {item: item, y: item.y} : null;
  }
  function takeAnchorShift() {
    forceLayout();
    const anchor = movingAnchor;
    movingAnchor = null;
    return anchor?.item && anchor.item.parent === column ? anchor.item.y - anchor.y : 0;
  }
  Column {
    id: column
    width: root.width; spacing: root.spacing
    Loader { width: parent.width; sourceComponent: root.header }
    Repeater {
      id: rows; model: root.model; delegate: root.delegate
      onItemAdded: Qt.callLater(root.finishLayout)
    }
  }
}
