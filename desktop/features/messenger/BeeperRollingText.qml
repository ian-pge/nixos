import QtQuick

// Two fixed text layouts; only their position/opacity changes while rolling.
// Public text always contains the latest value, including during interruption.
Item {
  id: root
  property string text: ""
  property font font
  property color color: "white"
  property bool animateChanges: enabled && visible
  property int duration: 140
  property real travel: height
  property int horizontalAlignment: Text.AlignHCenter
  property string displayedText: ""
  property string outgoingText: ""
  property real progress: 1
  property int direction: 1
  property bool ready: false
  readonly property bool running: roll.running
  implicitWidth: Math.max(incoming.implicitWidth, outgoing.visible ? outgoing.implicitWidth : 0)
  implicitHeight: incoming.implicitHeight
  clip: true

  function updateText() {
    if (!ready) return;
    const previous = progress < 0.5 ? outgoingText : displayedText;
    roll.stop();
    outgoingText = previous;
    displayedText = text;
    direction = Number(text) < Number(previous) ? -1 : 1;
    if (animateChanges && previous && previous !== text) {
      progress = 0;
      roll.start();
    } else progress = 1;
  }
  onTextChanged: updateText()
  onAnimateChangesChanged: if (!animateChanges) { roll.stop(); progress = 1; }
  Component.onCompleted: { displayedText = text; outgoingText = text; ready = true; }

  NumberAnimation {
    id: roll
    target: root; property: "progress"; to: 1
    duration: root.duration; easing.type: Easing.OutCubic
  }
  Text {
    id: outgoing
    width: root.width; height: root.height
    y: -root.direction * root.travel * root.progress
    visible: root.progress < 1
    opacity: 1 - root.progress
    text: root.outgoingText; textFormat: Text.PlainText
    font: root.font; color: root.color
    horizontalAlignment: root.horizontalAlignment; verticalAlignment: Text.AlignVCenter
  }
  Text {
    id: incoming
    width: root.width; height: root.height
    y: root.direction * root.travel * (1 - root.progress)
    opacity: root.progress
    text: root.displayedText; textFormat: Text.PlainText
    font: root.font; color: root.color
    horizontalAlignment: root.horizontalAlignment; verticalAlignment: Text.AlignVCenter
  }
}
