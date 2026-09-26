import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui/Theme.js" as Theme

Rectangle {
  id: root
  objectName: "beeperMessageSearchBar"
  required property var controller
  property bool locating: false
  property color accent: Theme.secondary
  readonly property bool compact: width < 300
  readonly property string briefCounter: controller.errorText || !controller.query.trim() ? ""
    : locating || controller.loading ? "…"
    : (controller.index >= 0 ? (controller.index + 1) + "/" : "") + controller.results.length + (controller.hasMore ? "+" : "")
  property alias input: field
  signal acceptRequested()
  signal closeRequested()
  implicitHeight: column.implicitHeight + 8
  visible: controller.opened
  color: Theme.surface; radius: 18
  function edit() { field.forceActiveFocus(); field.selectAll(); }
  ColumnLayout {
    id: column
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
    spacing: 4
    RowLayout {
      Layout.fillWidth: true; spacing: 8
      TextField {
        id: field
        objectName: "beeperMessageSearchInput"
        Layout.fillWidth: true; Layout.minimumWidth: 0
        implicitHeight: 40
        text: root.controller.query
        placeholderText: root.compact ? "Search…" : "Search in this conversation…"
        color: Theme.foreground; placeholderTextColor: Theme.inactive
        selectionColor: Qt.alpha(root.accent, 0.4); selectedTextColor: Theme.foreground
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control }
        leftPadding: 12; selectByMouse: true; background: null
        onTextEdited: root.controller.query = text
        onAccepted: if (!inputMethodComposing) root.acceptRequested()
        Keys.onEscapePressed: root.closeRequested()
      }
      Text {
        objectName: "beeperMessageSearchCounter"
        text: root.compact ? root.briefCounter : root.locating ? "Loading history…" : root.controller.counter
        color: Theme.secondary
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
      }
      BeeperButton {
        text: "×"; accent: root.accent
        implicitWidth: 32; implicitHeight: 32
        Accessible.name: "Close conversation search"
        onClicked: root.closeRequested()
      }
    }
    Text {
      Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
      visible: !!root.controller.errorText
      text: root.controller.errorText; color: Theme.error; wrapMode: Text.Wrap
      font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
    }
  }
}
