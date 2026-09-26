import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme

Rectangle {
  id: root
  required property var beeperData
  property bool active: false
  property alias tokenInput: tokenField
  function focusInput(explicitRequest) {
    // The shell can explicitly enter this card before it owns keyboard focus.
    // Automatic state changes must still respect focus held by another widget.
    if (!visible || (!active && !explicitRequest)) return;
    if (beeperData.tokenRequired) tokenField.forceActiveFocus();
    else retryButton.forceActiveFocus();
  }
  signal connectRequested(string token)
  signal retryRequested()
  signal closeRequested()
  objectName: "beeperConnectionSurface"
  implicitWidth: 500
  implicitHeight: connectionContent.implicitHeight + 48
  radius: 20
  visible: !root.beeperData.connected && (root.beeperData.tokenRequired || root.beeperData.chats.length === 0)
  color: Theme.surface
  onVisibleChanged: if (visible && active) Qt.callLater(focusInput)
  onActiveChanged: if (active && visible) Qt.callLater(focusInput)
  MouseArea { anchors.fill: parent }
  ScrollView {
    id: connectionScroll
    objectName: "beeperConnectionScroll"
    anchors { fill: parent; margins: 24 }
    clip: true
    contentWidth: availableWidth
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    Binding { target: connectionScroll.contentItem; property: "boundsBehavior"; value: Flickable.StopAtBounds }
    ColumnLayout {
      id: connectionContent
      width: connectionScroll.availableWidth; spacing: 18
      Text {
        objectName: "beeperConnectionTitle"
        Layout.fillWidth: true; wrapMode: Text.Wrap
        text: root.beeperData.tokenRequired ? "Your conversations,\nyour way."
          : root.beeperData.state === "keyring-unavailable" ? "Waiting for\nthe keyring"
          : "Reconnecting…"
        color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.hero } lineHeight: 1.1
      }
      Text {
        Layout.fillWidth: true
        text: root.beeperData.tokenRequired
          ? "Enable the local API in Beeper Desktop, then paste your access token."
          : root.beeperData.state === "keyring-unavailable" || root.beeperData.state === "loading-token"
          ? "Your saved access token will be restored automatically when the keyring becomes available."
          : "Keep Beeper Desktop running with its local API enabled. Your saved access token will be reused automatically."
        wrapMode: Text.Wrap; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.label } lineHeight: 1.25
      }
      BusyIndicator { visible: !root.beeperData.tokenRequired; running: root.visible && visible; Layout.preferredWidth: 36; Layout.preferredHeight: 36; Layout.alignment: Qt.AlignHCenter }
      TextField { id: tokenField; objectName: "beeperToken"; visible: root.beeperData.tokenRequired; enabled: !root.beeperData.savingToken; Layout.fillWidth: true; implicitHeight: 50; echoMode: TextInput.Password; placeholderText: "Beeper API token"; color: Theme.foreground; placeholderTextColor: Theme.inactive; selectByMouse: true; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control } background: Rectangle { radius: 10; color: Theme.surfaceRaised } onAccepted: root.connectRequested(text) }
      Text { visible: !!text; Layout.fillWidth: true; text: root.beeperData.lastError || root.beeperData.statusMessage; wrapMode: Text.Wrap; color: root.beeperData.lastError ? Theme.error : Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
      Text { visible: root.beeperData.tokenRequired; Layout.fillWidth: true; text: "Turn off Beeper Desktop notifications and sounds: this app handles your alerts."; wrapMode: Text.Wrap; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
      Flow {
        Layout.fillWidth: true
        spacing: 6
        BeeperButton { visible: root.beeperData.tokenRequired; prominent: true; text: root.beeperData.savingToken ? "Connecting…" : "Connect to Beeper"; enabled: !root.beeperData.savingToken && !!tokenField.text.trim(); onClicked: root.connectRequested(tokenField.text) }
        BeeperButton { id: retryButton; objectName: "beeperReconnect"; text: "Retry"; enabled: !root.beeperData.savingToken; onClicked: root.retryRequested() }
        BeeperButton { objectName: "beeperConnectionClose"; text: "Close"; onClicked: root.closeRequested() }
      }
    }
  }
  AcceleratedScroll { flickable: connectionScroll.contentItem }
}
