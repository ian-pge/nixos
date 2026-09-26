import QtQuick

// Short retargetable wheel motion, not a touch flick with long coasting.
// Pixel-delta gestures keep the platform's touchpad motion and momentum.
Item {
  id: root
  required property var flickable
  parent: flickable
  anchors.fill: parent
  z: 20
  property bool inputEnabled: true
  // Matches Qt's ordinary wheel path: wheelScrollLines * 24 logical pixels.
  property real step: (Qt.styleHints.wheelScrollLines || 3) * 24
  readonly property int duration: 150
  property real startedAt: 0
  property real lastTime: 0
  property int lastDirection: 0
  property real destination: 0
  readonly property bool driving: glide.running
  signal scrolled()
  // ScrollView disables mouse dragging via interactive=false, but wheel
  // scrolling must remain available. Owners control it with inputEnabled.
  enabled: inputEnabled && flickable !== null

  function reset() { glide.stop(); lastTime = 0; lastDirection = 0; }
  function animateTo(target, milliseconds) {
    glide.stop(); destination = target; startedAt = Date.now();
    glide.from = flickable.contentY; glide.to = destination;
    glide.duration = milliseconds; glide.start();
  }
  function scroll(notches, now) {
    if (!notches || !flickable) return;
    const direction = Math.sign(notches), elapsed = now - lastTime;
    const continuing = driving && direction === lastDirection && elapsed >= 0 && elapsed < 200;
    const start = continuing ? destination : flickable.contentY;
    flickable.cancelFlick();
    lastTime = now; lastDirection = direction;
    const minimum = flickable.originY;
    const maximum = Math.max(minimum, minimum + flickable.contentHeight - flickable.height);
    const travelLimit = Math.max(step, flickable.height * 2);
    const target = Math.max(minimum, Math.min(maximum,
      Math.max(flickable.contentY - travelLimit, Math.min(flickable.contentY + travelLimit,
        start - notches * step))));
    animateTo(target, duration);
  }
  function shiftOrigin(delta) {
    if (!delta) return;
    const wasDriving = driving, target = destination + delta;
    const remaining = Math.max(1, glide.duration - (Date.now() - startedAt));
    glide.stop(); flickable.contentY += delta;
    if (wasDriving) animateTo(target, remaining);
  }
  NumberAnimation { id: glide; target: root.flickable; property: "contentY"; easing.type: Easing.OutCubic }
  WheelHandler {
    target: null
    acceptedModifiers: Qt.NoModifier
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
      root.scrolled();
      if (event.pixelDelta.y || !event.angleDelta.y) {
        root.reset(); event.accepted = false; return;
      }
      root.scroll(event.angleDelta.y / 120, Date.now());
      event.accepted = true;
    }
  }
  Connections {
    target: root.flickable
    function onFlickingChanged() { if (root.flickable.flicking) root.reset(); }
    function onDraggingChanged() { if (root.flickable.dragging) root.reset(); }
  }
  onEnabledChanged: if (!enabled) reset()
}
