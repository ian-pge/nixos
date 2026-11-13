pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property bool speechDetected
  required property color accent
  property var spectrumLevels: []
  property bool active: true
  property real sizeScale: 1

  readonly property int barCount: 19
  readonly property real barWidth: 2.2 * sizeScale
  readonly property real barSpacing: 3.2 * sizeScale
  implicitWidth: barCount * barWidth + (barCount - 1) * barSpacing
  implicitHeight: 22 * sizeScale

  function level(index) {
    if (!active || !speechDetected || spectrumLevels.length !== barCount)
      return 0;
    const value = spectrumLevels[index];
    const left = spectrumLevels[Math.max(0, index - 1)];
    const right = spectrumLevels[Math.min(barCount - 1, index + 1)];
    // Blend neighbours slightly, with a fixed taper at the outer edges.
    // Neither this profile nor the spectrum's dB scale adapts to past sounds.
    const taper = 0.6 + 0.4 * Math.sin(Math.PI * index / (barCount - 1));
    return Math.max(0, Math.min(1, (0.7 * value + 0.15 * (left + right)) * taper));
  }

  Row {
    anchors.centerIn: parent
    height: parent.height
    spacing: root.barSpacing

    Repeater {
      model: root.barCount
      delegate: Rectangle {
        required property int index
        objectName: "voiceBar" + index
        readonly property real targetHeight: root.barWidth
          + root.level(index) * Math.max(0, root.height - 2 * root.sizeScale - root.barWidth)
        anchors.verticalCenter: parent.verticalCenter
        width: root.barWidth
        height: targetHeight
        radius: width / 2
        color: root.accent
        opacity: 0.65 + 0.35 * root.level(index)

        // Qt interpolates at the display's refresh rate. No scrolling or
        // autonomous oscillation; silence settles into a stationary dot row.
        Behavior on height {
          id: heightMotion
          enabled: root.active
          NumberAnimation {
            duration: heightMotion.targetValue > heightMotion.targetProperty.object.height ? 80 : 180
            easing.type: Easing.OutCubic
          }
        }
        Behavior on opacity { NumberAnimation { duration: 150 } }
      }
    }
  }
}
