import Quickshell
import QtQuick
import "../../ui/Theme.js" as Theme
import "../../ui"

FocusScope {
  id: root

  required property var controller
  signal closeRequested()
  readonly property var results: controller.results
  implicitWidth: 480
  implicitHeight: 398

  function syncSearchText() {
    if (searchInput.text !== controller.query) {
      searchInput.text = controller.query;
      searchInput.cursorPosition = searchInput.text.length;
    }
  }

  function revealSelection() {
    if (controller.selectedIndex >= 0 && results.length > 0)
      appList.positionViewAtIndex(controller.selectedIndex,
        ListView.Contain);
  }

  onEnabledChanged: {
    if (enabled) {
      syncSearchText();
      Qt.callLater(() => {
        searchInput.forceActiveFocus();
        revealSelection();
      });
    }
  }

  Connections {
    target: controller

    function onQueryChanged() {
      root.syncSearchText();
    }

    function onResultsChanged() {
      Qt.callLater(() => root.revealSelection());
    }

    function onSelectedIndexChanged() {
      root.revealSelection();
    }
  }

  Item {
    anchors.fill: parent

    Text {
      id: searchIcon
      anchors.left: parent.left
      anchors.leftMargin: 16
      y: 9
      width: 22
      height: 24
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: "󰍉"
      color: Theme.sideApplications
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true
    }

    TextInput {
      id: searchInput
      objectName: "appSearchInput"
      anchors.left: searchIcon.right
      anchors.leftMargin: 10
      anchors.right: resultCount.left
      anchors.rightMargin: 12
      y: 7
      height: 28
      verticalAlignment: TextInput.AlignVCenter
      color: Theme.foreground
      selectionColor: Theme.sideApplications
      selectedTextColor: Theme.background
      clip: true
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
      cursorVisible: activeFocus

      onTextEdited: controller.setQuery(text)

      Keys.onPressed: event => {
        const control = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Down
            || (control && (event.key === Qt.Key_N || event.key === Qt.Key_J))
            || event.key === Qt.Key_Tab) {
          controller.moveSelection(1);
          event.accepted = true;
        } else if (event.key === Qt.Key_Up
            || (control && (event.key === Qt.Key_P || event.key === Qt.Key_K))
            || (event.key === Qt.Key_Backtab)) {
          controller.moveSelection(-1);
          event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
          controller.moveSelection(8);
          event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) {
          controller.moveSelection(-8);
          event.accepted = true;
        } else if (event.key === Qt.Key_Home && control) {
          controller.selectedIndex = 0;
          event.accepted = true;
        } else if (event.key === Qt.Key_End && control
            && controller.results.length > 0) {
          controller.selectedIndex
            = controller.results.length - 1;
          event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          controller.launchSelected(controller.selectedIndex,
            control !== 0);
          event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
          root.closeRequested();
          event.accepted = true;
        }
      }
    }

    Text {
      anchors.left: searchInput.left
      anchors.right: searchInput.right
      y: searchInput.y
      height: searchInput.height
      visible: searchInput.text === ""
      verticalAlignment: Text.AlignVCenter
      text: "Search applications…"
      color: Theme.inactive
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      id: resultCount
      anchors.right: parent.right
      anchors.rightMargin: 16
      y: 9
      width: 88
      height: 24
      horizontalAlignment: Text.AlignRight
      verticalAlignment: Text.AlignVCenter
      text: results.length + (results.length === 1 ? " APP" : " APPS")
      color: Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 10
      font.bold: true
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      y: 41
      height: 1
      color: Theme.surfaceRaised
    }

    ListView {
      id: appList
      anchors.left: parent.left
      anchors.right: parent.right
      y: 48
      height: 342
      clip: true
      model: root.results
      currentIndex: controller.selectedIndex
      boundsBehavior: Flickable.StopAtBounds
      highlightMoveDuration: 120
      highlightResizeDuration: 120

      delegate: Item {
        id: appRow
        required property var modelData
        required property int index
        readonly property var entry: modelData.entry
        readonly property bool selected: index === controller.selectedIndex
        readonly property int toplevelRevision: controller.toplevelRevision
        readonly property var runningToplevel: {
          const revision = toplevelRevision;
          return controller.toplevelFor(entry);
        }

        width: appList.width
        height: 42

        Item {
          anchors.fill: parent

          SelectionSurface {
            objectName: "appSelection" + appRow.index
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            radius: 10
            selected: appRow.selected
            accent: Theme.sideApplications
          }

          SelectionSurface {
            id: iconFrame
            objectName: "appIconFrame" + appRow.index
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 30
            radius: 8
            selected: appRow.selected
            accent: Theme.sideApplications
            tintOpacity: 0.08
            fallbackColor: Theme.surfaceSelected
            idleColor: GlassState.enabled ? Qt.alpha(Theme.foreground, 0.04) : Theme.surface

            Image {
              id: appIcon
              anchors.fill: parent
              anchors.margins: 3
              source: Quickshell.iconPath(appRow.entry.icon,
                "application-x-executable")
              sourceSize.width: 24
              sourceSize.height: 24
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: true
            }

            Text {
              visible: appIcon.status === Image.Error
              anchors.centerIn: parent
              text: "󰀻"
              color: appRow.selected ? Theme.sideApplications : Theme.inactive
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 15
              font.bold: true
            }
          }

          Text {
            anchors.left: iconFrame.right
            anchors.leftMargin: 11
            anchors.right: runningDot.left
            anchors.rightMargin: 12
            y: 4
            height: 18
            verticalAlignment: Text.AlignVCenter
            text: appRow.entry.name
            color: appRow.selected ? Theme.selectedForeground : Theme.foreground
            Behavior on color { ColorAnimation { duration: 120 } }
            elide: Text.ElideRight
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: 13
            font.bold: true
          }

          Text {
            anchors.left: iconFrame.right
            anchors.leftMargin: 11
            anchors.right: runningDot.left
            anchors.rightMargin: 12
            y: 21
            height: 15
            verticalAlignment: Text.AlignVCenter
            text: appRow.entry.genericName !== "" ? appRow.entry.genericName
              : appRow.entry.comment
            color: Theme.secondary
            elide: Text.ElideRight
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: 10
            font.bold: true
          }

          Rectangle {
            id: runningDot
            anchors.right: parent.right
            anchors.rightMargin: 21
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 3.5
            visible: appRow.runningToplevel !== null
            color: Theme.sideApplications
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: controller.launchSelected(appRow.index)
        }
      }

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
          if (event.angleDelta.y < 0)
            controller.moveSelection(1);
          else if (event.angleDelta.y > 0)
            controller.moveSelection(-1);
        }
      }
    }

    Text {
      visible: results.length === 0
      anchors.left: parent.left
      anchors.right: parent.right
      y: 165
      height: 40
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: "No matching applications"
      color: Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 13
      font.bold: true
    }
  }
}
