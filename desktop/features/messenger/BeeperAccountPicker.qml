import QtQuick
import QtQuick.Controls
import "../../ui"
import "../../ui/Theme.js" as Theme

ComboBox {
  id: control
  textRole: "network"
  valueRole: "id"
  implicitHeight: 42
  font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
  function navigate(event) {
    if (event.key === Qt.Key_J || event.key === Qt.Key_K) {
      event.key === Qt.Key_J ? incrementCurrentIndex() : decrementCurrentIndex();
      if (!popup.opened) activated(currentIndex);
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      activated(currentIndex); popup.close(); event.accepted = true;
    } else if (event.key === Qt.Key_Escape && popup.opened) { popup.close(); event.accepted = true; }
  }
  Keys.onPressed: event => navigate(event)
  background: Rectangle { radius: 8; color: control.activeFocus ? Qt.alpha(Theme.sideApplications, 0.16) : Qt.alpha(Theme.surface, 0.75) }
  contentItem: Text { text: control.displayText; color: Theme.secondary; leftPadding: 10; rightPadding: 20; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter; font: control.font }
  delegate: ItemDelegate {
    required property var modelData
    required property int index
    width: control.width
    implicitHeight: 42
    text: modelData.network || modelData.id
    contentItem: Text { text: parent.text; color: Theme.foreground; font: control.font; verticalAlignment: Text.AlignVCenter }
    background: Rectangle { radius: 6; color: index === control.currentIndex ? Qt.alpha(Theme.sideApplications, 0.16) : "transparent" }
    highlighted: index === control.currentIndex
  }
  popup: Popup {
    y: control.height + 5; width: control.width; padding: 5
    implicitHeight: Math.min(300, contentItem.implicitHeight + 10)
    background: Rectangle { radius: 10; color: Theme.surface }
    contentItem: ListView {
      id: accountsList
      clip: true; implicitHeight: contentHeight
      AcceleratedScroll { flickable: accountsList }
      model: control.popup.visible ? control.delegateModel : null
      currentIndex: control.currentIndex
      Keys.onPressed: event => control.navigate(event)
    }
  }
}
