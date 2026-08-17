pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  required property real energy
  required property bool speechDetected
  required property color accent
  property bool active: true
  property real elapsedSeconds: 0
  property real peakReference: minimumPeakReference
  property real normalizedEnergy: 0
  property var barLevels: []

  readonly property int minimumBarCount: 18
  readonly property real barWidth: 3
  readonly property real barSpacing: 2
  readonly property real noiseFloor: 0.006
  readonly property real minimumPeakReference: 0.015
  readonly property int barCount: Math.max(minimumBarCount,
    Math.floor((width + barSpacing) / (barWidth + barSpacing)))

  implicitWidth: minimumBarCount * barWidth
    + (minimumBarCount - 1) * barSpacing
  implicitHeight: 22

  function clamp(value) {
    return Math.max(0, Math.min(1, value));
  }

  function seeded(index, salt) {
    const value = Math.sin((index + 1) * 12.9898
      + salt * 78.233) * 43758.5453;
    return value - Math.floor(value);
  }

  function targetLevel(index) {
    if (!active || !speechDetected)
      return 0;

    const primarySpeed = 6.5 + seeded(index, 2) * 4.5;
    const secondarySpeed = 3.0 + seeded(index, 3) * 3.0;
    const primaryPhase = seeded(index, 4) * Math.PI * 2;
    const secondaryPhase = seeded(index, 5) * Math.PI * 2;
    const primary = 0.5 + 0.5 * Math.sin(
      elapsedSeconds * primarySpeed + primaryPhase);
    const secondary = 0.5 + 0.5 * Math.sin(
      elapsedSeconds * secondarySpeed + secondaryPhase);
    const movement = Math.pow(primary * 0.72 + secondary * 0.28, 1.45);
    const response = 0.55 + seeded(index, 1) * 0.9;
    const activity = Math.pow(normalizedEnergy, response);

    return clamp(activity * (0.04 + movement * 0.96));
  }

  function updateNormalization() {
    const input = clamp(energy);

    if (speechDetected && input > peakReference) {
      peakReference += (input - peakReference) * 0.65;
    } else {
      peakReference = Math.max(minimumPeakReference,
        peakReference * 0.992);
    }

    if (!active || !speechDetected) {
      normalizedEnergy = 0;
      return;
    }

    const usablePeak = Math.max(minimumPeakReference, peakReference);
    const usableRange = Math.max(0.001, usablePeak - noiseFloor);
    const relativeEnergy = clamp((input - noiseFloor) / usableRange);
    normalizedEnergy = Math.pow(relativeEnergy, 0.55);
  }

  function updateBars() {
    elapsedSeconds += animationTimer.interval / 1000;
    updateNormalization();
    const levels = [];

    for (let index = 0; index < barCount; ++index) {
      const target = targetLevel(index);
      const current = typeof barLevels[index] === "number"
        ? barLevels[index] : 0;
      const smoothing = target > current ? 0.46 : 0.2;
      const next = current + (target - current) * smoothing;
      levels.push(next < 0.001 ? 0 : next);
    }

    barLevels = levels;
  }

  function resetBars() {
    elapsedSeconds = 0;
    peakReference = minimumPeakReference;
    normalizedEnergy = 0;
    const levels = [];
    for (let index = 0; index < barCount; ++index)
      levels.push(0);
    barLevels = levels;
  }

  onActiveChanged: resetBars()
  onBarCountChanged: resetBars()
  Component.onCompleted: resetBars()

  Timer {
    id: animationTimer
    interval: 33
    repeat: true
    running: root.active
    triggeredOnStart: true
    onTriggered: root.updateBars()
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    height: parent.height
    spacing: root.barSpacing

    Repeater {
      id: barRepeater
      model: root.barCount

      delegate: Rectangle {
        required property int index
        readonly property real level: root.barLevels.length > index
          ? root.barLevels[index] : 0

        anchors.verticalCenter: parent.verticalCenter
        width: root.barWidth
        height: root.barWidth
          + Math.pow(level, 0.78) * (root.height - 2 - root.barWidth)
        radius: width / 2
        color: root.accent
      }
    }
  }
}
