import QtQuick

// Pure presentation clock shared by bar spinners, with no service dependencies.
QtObject {
  id: root
  property bool running: false
  property int index: 0
  readonly property var frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  readonly property string frame: frames[index]
  onRunningChanged: if (running) index = 0
  property Timer ticker: Timer {
    interval: 80; repeat: true; running: root.running
    onTriggered: root.index = (root.index + 1) % root.frames.length
  }
}
