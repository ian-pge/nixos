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
  property int dirtyFrom: 0
  property bool measureAll: false
  property var pendingMeasurements: []
  property var pendingReveal: []
  property real textScale: 1
  property int scaleCursor: 0
  property bool rescaling: false
  property var resizeAnchor: null
  property var shiftViewport: delta => { root.contentY += delta; }
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

  function invalidateLayout(start = 0, measure = true) {
    if (layingOut) return;
    dirtyFrom = Math.min(dirtyFrom, Math.max(0, start));
    measureAll = measureAll || (measure && createdCount > 0);
    layoutDirty = true;
    finishPending = true;
    Qt.callLater(finishLayout);
  }
  function invalidateItemLayout(item) { invalidateLayout(item?.index ?? 0, false); }
  function measureItem(item) {
    if (!item || item.parent !== root.contentItem) return;
    if (!pendingMeasurements.includes(item)) pendingMeasurements.push(item);
    invalidateItemLayout(item);
  }
  function forceLayout() {
    if (loading || layingOut || !layoutDirty) return;
    layingOut = true;
    if (measureAll) {
      for (let i = 0; i < count; ++i) rows.objectAt(i)?.forceMessageLayout?.();
    } else for (const item of pendingMeasurements) {
      if (item?.parent === root.contentItem) item.forceMessageLayout?.();
    }
    const start = Math.min(dirtyFrom, count);
    const previous = start > 0 ? rows.objectAt(start - 1) : null;
    let y = previous ? previous.y + previous.height : heading.height;
    for (let i = start; i < count; ++i) {
      const item = rows.objectAt(i);
      if (!item) continue;
      if (i > 0 || heading.height > 0) y += spacing;
      if (item.y !== y) item.y = y;
      y += item.height;
    }
    contentHeight = y;
    dirtyFrom = count; measureAll = false; pendingMeasurements = [];
    layoutDirty = false;
    layingOut = false;
  }
  function finishLayout() {
    if (loading || !finishPending) return;
    forceLayout();
    finishPending = false;
    const anchor = resizeAnchor;
    resizeAnchor = null;
    if (anchor) {
      const position = anchor.atEnd ? Math.max(0, contentHeight - height)
        : anchor.item?.parent === root.contentItem ? anchor.item.y + anchor.offset : contentY;
      shiftViewport(Math.max(0, Math.min(Math.max(0, contentHeight - height), position)) - contentY);
    }
    // Restore the viewport before enabling media, so initial loading does not
    // briefly start decoders at the top of a conversation opened at its end.
    layoutReady();
    const reveal = pendingReveal; pendingReveal = [];
    for (const item of reveal) {
      if (!item || item.parent !== root.contentItem) continue;
      if (item && item.viewportReady !== undefined) item.viewportReady = true;
      if (item) item.visible = true;
    }
    updateViewport();
    playArrivals();
  }
  function preserveResizeAnchor() {
    if (resizeAnchor || loading || !count) return;
    forceLayout();
    const item = rows.objectAt(Math.max(0, indexAt(1, contentY + 12)));
    resizeAnchor = item ? {item: item, offset: contentY - item.y, atEnd: atYEnd} : null;
  }
  function scaleItem(item) {
    if (!item || item.textScale === undefined || item.textScale === textScale) return;
    preserveResizeAnchor();
    item.textScale = textScale;
    measureItem(item);
  }
  function scheduleTextScale() {
    scaleCursor = 0; rescaling = count > 0;
    for (const item of activeViewportItems) if (item?.inVisibleViewport) scaleItem(item);
  }
  function rescaleFrame() {
    if (loading) return;
    if (finishPending) finishLayout();
    const started = Date.now();
    let changed = 0;
    while (scaleCursor < count && changed < 12 && Date.now() - started < 3) {
      const item = rows.objectAt(scaleCursor++);
      if (item && item.textScale !== textScale) { scaleItem(item); ++changed; }
    }
    if (scaleCursor >= count) rescaling = false;
    if (finishPending) finishLayout();
  }
  onTextScaleChanged: scheduleTextScale()
  FrameAnimation { running: root.rescaling && root.visible; onTriggered: root.rescaleFrame() }
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
        if (rescaling) scaleItem(item);
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
  onSpacingChanged: invalidateLayout(0, false)
  onMovementStarted: resizeAnchor = null
  Connections {
    target: root.model
    function onUpdating() { root.resizeAnchor = null; }
    function onUpdated(structural, changedIndexes, firstChanged) {
      if (structural) {
        root.invalidateLayout(firstChanged, false);
        if (root.rescaling) root.scaleCursor = 0;
      }
      for (const index of changedIndexes || []) root.measureItem(rows.objectAt(index));
    }
  }
  Loader {
    id: heading
    width: root.width; sourceComponent: root.header
    onHeightChanged: root.invalidateLayout(0, false)
  }
  Instantiator {
    id: rows
    model: root.model; delegate: root.delegate
    asynchronous: true
    onObjectAdded: (index, item) => {
      item.visible = false;
      item.parent = root.contentItem;
      if (item.textScale !== undefined) item.textScale = root.textScale;
      // Incubation already spreads creation across frames; measure each new
      // bubble there instead of forcing every bubble at the end of the batch.
      item.forceMessageLayout?.();
      if (item.heightInvalidated) item.heightInvalidated.connect(root.invalidateItemLayout);
      else item.heightChanged.connect(root.invalidateLayout);
      root.pendingReveal.push(item);
      ++root.createdCount;
      root.invalidateLayout(index, false);
    }
    onObjectRemoved: (index, item) => {
      if (item) {
        if (item.inViewport !== undefined) item.inViewport = false;
        if (item.inVisibleViewport !== undefined) item.inVisibleViewport = false;
        if (root.activeViewportItems.includes(item))
          root.activeViewportItems = root.activeViewportItems.filter(active => active !== item);
        item.visible = false;
        if (item.heightInvalidated) item.heightInvalidated.disconnect(root.invalidateItemLayout);
        else item.heightChanged.disconnect(root.invalidateLayout);
        --root.createdCount;
      }
      root.invalidateLayout(index, false);
    }
  }
}
