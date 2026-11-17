import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

ListView {
  id: control
  implicitHeight: Math.min(contentHeight, 360)
  clip: true
  spacing: 8
  boundsBehavior: Flickable.StopAtBounds
  keyNavigationEnabled: false
  signal activated(int index)
  onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
  function moveSelection(delta) {
    if (count) currentIndex = (Math.max(0, currentIndex) + delta + count) % count;
  }
  Keys.onPressed: event => {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
    if (event.key === Qt.Key_J || event.key === Qt.Key_Down) moveSelection(1);
    else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) moveSelection(-1);
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (!event.isAutoRepeat && currentIndex >= 0 && currentIndex < count) activated(currentIndex);
    } else return;
    event.accepted = true;
  }
  AcceleratedScroll { flickable: control }
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
  delegate: BeeperButton {
    id: option
    required property var modelData
    required property int index
    readonly property var network: Format.networkBadge(modelData.network)
    objectName: "beeperNetworkOption"
    width: control.width; height: 64
    focusPolicy: Qt.NoFocus
    accent: Theme.beeperNetworkColors[network.key] || Theme.secondary
    prominent: index === control.currentIndex
    Accessible.name: network.name
    onClicked: { control.currentIndex = index; control.activated(index); }
    contentItem: RowLayout {
      spacing: 14
      BeeperNetworkBadge {
        network: option.modelData.network; showsName: false
        Layout.preferredWidth: 40; Layout.preferredHeight: 40
      }
      Text {
        Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText
        text: option.network.name; color: option.accent
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.label; weight: Font.Medium }
      }
    }
  }
}
