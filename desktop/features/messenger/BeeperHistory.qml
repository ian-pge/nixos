import QtQuick
import QtQml.Models

// Incubate message components across frames, then position their real layouts.
// Keep exact history heights without blocking input while a page is created.
Flickable {
  id: root
  property var model
  property Component delegate
  property Component header
  property real spacing: 8
  readonly property int count: model?.count ?? 0
  property int createdCount: 0
  readonly property bool loading: createdCount < count
  property bool layoutDirty: true
  property bool finishPending: true
  property bool layingOut: false
  property var movingAnchor: null
  property var activeViewportItems: []
  property var arrivalIds: ({})
  signal layoutReady()
  contentWidth: width
  contentHeight: 0
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  acceptedButtons: Qt.NoButton

  function invalidateLayout() {
    layoutDirty = true;
    finishPending = true;
    Qt.callLater(finishLayout);
  }
  function forceLayout() {
    if (loading || layingOut || !layoutDirty) return;
    layingOut = true;
    let y = heading.height;
    for (let i = 0; i < count; ++i) {
      const item = rows.objectAt(i);
      if (!item) continue;
      if (item.forceMessageLayout) item.forceMessageLayout();
      if (i > 0 || heading.height > 0) y += spacing;
      item.y = y;
      y += item.height;
    }
    contentHeight = y;
    layoutDirty = false;
    layingOut = false;
  }
  function finishLayout() {
    if (loading || !finishPending) return;
    forceLayout();
    finishPending = false;
    // Restore the viewport before enabling media, so initial loading does not
    // briefly start decoders at the top of a conversation opened at its end.
    layoutReady();
    for (let i = 0; i < count; ++i) {
      const item = rows.objectAt(i);
      if (item && item.viewportReady !== undefined) item.viewportReady = true;
      if (item) item.visible = true;
    }
    updateViewport();
    playArrivals();
  }
  function queueArrivals(ids) {
    const queued = Object.assign({}, arrivalIds);
    for (const id of ids) queued[id] = true;
    arrivalIds = queued;
    if (!loading && !finishPending) Qt.callLater(playArrivals);
  }
  function clearArrivals() {
    arrivalIds = ({});
    for (const item of activeViewportItems) if (item?.finishArrival) item.finishArrival();
  }
  function playArrivals() {
    const queued = arrivalIds;
    arrivalIds = ({});
    if (!visible || !atYEnd) return;
    for (const item of activeViewportItems) {
      if (item?.inVisibleViewport && queued[item.message?.id] && item.playArrival) item.playArrival();
    }
  }
  function updateViewport() {
    if (loading || layingOut) return;
    const next = [];
    if (visible && height > 0) {
      const top = contentY - height / 2, bottom = contentY + height * 1.5;
      let low = 0, high = count;
      while (low < high) {
        const middle = Math.floor((low + high) / 2), item = rows.objectAt(middle);
        if (!item) return;
        if (item.y + item.height < top) low = middle + 1;
        else high = middle;
      }
      for (let index = low; index < count; ++index) {
        const item = rows.objectAt(index);
        if (!item || item.y > bottom) break;
        next.push(item);
        if (item.inViewport !== undefined) item.inViewport = true;
        if (item.inVisibleViewport !== undefined)
          item.inVisibleViewport = item.y + item.height >= contentY && item.y <= contentY + height;
      }
    }
    for (const item of activeViewportItems) {
      if (item && !next.includes(item)) {
        if (item.inViewport !== undefined) item.inViewport = false;
        if (item.inVisibleViewport !== undefined) item.inVisibleViewport = false;
      }
    }
    activeViewportItems = next;
  }
  function itemAtIndex(index) { return rows.objectAt(index); }
  function indexAt(x, y) {
    let low = 0, high = count - 1;
    while (low <= high) {
      const middle = Math.floor((low + high) / 2), item = rows.objectAt(middle);
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
    const item = rows.objectAt(index);
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
    const item = rows.objectAt(index);
    movingAnchor = item ? {item: item, y: item.y} : null;
  }
  function takeAnchorShift() {
    forceLayout();
    const anchor = movingAnchor;
    movingAnchor = null;
    return anchor?.item && anchor.item.parent === root.contentItem ? anchor.item.y - anchor.y : 0;
  }
  onWidthChanged: invalidateLayout()
  onContentYChanged: Qt.callLater(updateViewport)
  onHeightChanged: Qt.callLater(updateViewport)
  onVisibleChanged: { if (!visible) clearArrivals(); Qt.callLater(updateViewport); }
  onSpacingChanged: invalidateLayout()
  Connections {
    target: root.model
    function onUpdated() { root.invalidateLayout(); }
  }
  Loader {
    id: heading
    width: root.width; sourceComponent: root.header
    onHeightChanged: root.invalidateLayout()
  }
  Instantiator {
    id: rows
    model: root.model; delegate: root.delegate
    asynchronous: true
    onObjectAdded: (index, item) => {
      item.visible = false;
      item.parent = root.contentItem;
      item.heightChanged.connect(root.invalidateLayout);
      ++root.createdCount;
      root.invalidateLayout();
    }
    onObjectRemoved: (index, item) => {
      if (item) {
        if (item.inViewport !== undefined) item.inViewport = false;
        if (item.inVisibleViewport !== undefined) item.inVisibleViewport = false;
        if (root.activeViewportItems.includes(item))
          root.activeViewportItems = root.activeViewportItems.filter(active => active !== item);
        item.visible = false;
        item.heightChanged.disconnect(root.invalidateLayout);
        --root.createdCount;
      }
      root.invalidateLayout();
    }
  }
}
