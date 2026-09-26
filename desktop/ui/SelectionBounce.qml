import QtQuick

Translate {
  id: root

  property bool active: false
  property real distance: 6

  // Keep equal travel above/below rest, with a sharp velocity reversal at the
  // bottom: decelerate on the way up, then accelerate into the next impact.
  property SequentialAnimation bounce: SequentialAnimation {
    running: root.active
    loops: Animation.Infinite
    onStarted: returnToRest.stop()
    onStopped: returnToRest.restart()

    NumberAnimation {
      target: root
      property: "y"
      to: -root.distance
      duration: 300
      easing.type: Easing.OutQuad
    }
    NumberAnimation {
      target: root
      property: "y"
      to: root.distance
      duration: 220
      easing.type: Easing.InQuad
    }
  }

  property NumberAnimation returnToRest: NumberAnimation {
    target: root
    property: "y"
    to: 0
    duration: 140
    easing.type: Easing.OutCubic
  }
}
