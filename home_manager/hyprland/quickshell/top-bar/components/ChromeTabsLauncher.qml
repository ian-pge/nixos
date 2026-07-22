import QtQuick

FocusScope {
  id: root

  required property var statusData
  readonly property var results: statusData.chromeTabResults
  implicitWidth: 480
  implicitHeight: 398

  function syncSearchText() {
    if (searchInput.text !== statusData.chromeTabsQuery) {
      searchInput.text = statusData.chromeTabsQuery;
      searchInput.cursorPosition = searchInput.text.length;
    }
  }

  function revealSelection() {
    if (statusData.chromeTabsSelectedIndex >= 0 && results.length > 0)
      tabList.positionViewAtIndex(statusData.chromeTabsSelectedIndex,
        ListView.Contain);
  }

  function urlLabel(value) {
    const url = (value || "").toString();
    if (url === "")
      return "No URL";
    const match = url.match(/^[a-z]+:\/\/(?:www\.)?([^/]+)(.*)$/i);
    if (match === null)
      return url;
    return match[1] + (match[2] === "/" ? "" : match[2]);
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
    target: statusData

    function onChromeTabsQueryChanged() {
      root.syncSearchText();
    }

    function onChromeTabResultsChanged() {
      Qt.callLater(() => root.revealSelection());
    }

    function onChromeTabsSelectedIndexChanged() {
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
      color: "#ff33cc"
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true
    }

    TextInput {
      id: searchInput
      anchors.left: searchIcon.right
      anchors.leftMargin: 10
      anchors.right: resultCount.left
      anchors.rightMargin: 12
      y: 7
      height: 28
      verticalAlignment: TextInput.AlignVCenter
      color: "#cad3f5"
      selectionColor: "#ff33cc"
      selectedTextColor: "#181926"
      clip: true
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
      cursorVisible: activeFocus

      onTextEdited: statusData.setChromeTabsQuery(text)

      Keys.onPressed: event => {
        const control = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Down || (control && event.key === Qt.Key_N)
            || event.key === Qt.Key_Tab) {
          statusData.moveChromeTabsSelection(1);
          event.accepted = true;
        } else if (event.key === Qt.Key_Up || (control && event.key === Qt.Key_P)
            || event.key === Qt.Key_Backtab) {
          statusData.moveChromeTabsSelection(-1);
          event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
          statusData.moveChromeTabsSelection(8);
          event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) {
          statusData.moveChromeTabsSelection(-8);
          event.accepted = true;
        } else if (event.key === Qt.Key_Home && control) {
          statusData.chromeTabsSelectedIndex = 0;
          event.accepted = true;
        } else if (event.key === Qt.Key_End && control
            && results.length > 0) {
          statusData.chromeTabsSelectedIndex = results.length - 1;
          event.accepted = true;
        } else if (event.key === Qt.Key_W && control) {
          statusData.closeSelectedChromeTab();
          event.accepted = true;
        } else if (event.key === Qt.Key_R && control) {
          statusData.requestChromeTabs();
          event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          statusData.activateSelectedChromeTab();
          event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
          statusData.hideChromeTabs();
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
      text: "Search Chrome tabs…"
      color: "#6e738d"
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
      text: statusData.chromeTabsLoading ? "LOADING"
        : results.length + (results.length === 1 ? " TAB" : " TABS")
      color: statusData.chromeTabsMessage !== "" ? "#ed8796" : "#a6da95"
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
      color: "#363a4f"
    }

    ListView {
      id: tabList
      anchors.left: parent.left
      anchors.right: parent.right
      y: 48
      height: 342
      clip: true
      model: root.results
      currentIndex: statusData.chromeTabsSelectedIndex
      boundsBehavior: Flickable.StopAtBounds
      highlightMoveDuration: 120
      highlightResizeDuration: 120

      delegate: Item {
        id: tabRow
        required property var modelData
        required property int index
        readonly property var tab: modelData.tab
        readonly property bool selected: index === statusData.chromeTabsSelectedIndex

        width: tabList.width
        height: 42

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 8
          anchors.topMargin: 2
          anchors.bottomMargin: 2
          radius: 10
          color: tabRow.selected ? "#363a4f" : "transparent"

          Behavior on color { ColorAnimation { duration: 90 } }
        }

        Rectangle {
          id: iconFrame
          anchors.left: parent.left
          anchors.leftMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          width: 30
          height: 30
          radius: 8
          color: tabRow.selected ? "#494d64" : "#24273a"

          Text {
            anchors.centerIn: parent
            text: ""
            color: tabRow.tab.active ? "#a6da95" : "#8aadf4"
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: 17
            font.bold: true
          }
        }

        Text {
          anchors.left: iconFrame.right
          anchors.leftMargin: 11
          anchors.right: stateIcons.left
          anchors.rightMargin: 10
          y: 4
          height: 18
          verticalAlignment: Text.AlignVCenter
          text: tabRow.tab.title || "Untitled tab"
          color: tabRow.selected ? "#ffffff" : "#cad3f5"
          elide: Text.ElideRight
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 13
          font.bold: true
        }

        Text {
          anchors.left: iconFrame.right
          anchors.leftMargin: 11
          anchors.right: stateIcons.left
          anchors.rightMargin: 10
          y: 21
          height: 15
          verticalAlignment: Text.AlignVCenter
          text: root.urlLabel(tabRow.tab.url)
          color: "#939ab7"
          elide: Text.ElideRight
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 10
          font.bold: true
        }

        Row {
          id: stateIcons
          anchors.right: launchHint.left
          anchors.rightMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6

          Text {
            visible: tabRow.tab.pinned
            text: "󰐃"
            color: "#f5a97f"
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: 12
            font.bold: true
          }

          Rectangle {
            visible: tabRow.tab.active
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 3.5
            color: "#a6da95"
          }
        }

        Text {
          id: launchHint
          anchors.right: parent.right
          anchors.rightMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          width: 24
          horizontalAlignment: Text.AlignHCenter
          text: tabRow.selected ? "󰌑" : ""
          color: "#ff33cc"
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 14
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
              statusData.closeSelectedChromeTab(tabRow.index);
            else
              statusData.activateSelectedChromeTab(tabRow.index);
          }
        }
      }

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
          if (event.angleDelta.y < 0)
            statusData.moveChromeTabsSelection(1);
          else if (event.angleDelta.y > 0)
            statusData.moveChromeTabsSelection(-1);
        }
      }
    }

    Text {
      visible: results.length === 0
      anchors.left: parent.left
      anchors.right: parent.right
      y: 165
      height: 58
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: statusData.chromeTabsLoading ? "Loading Chrome tabs…"
        : statusData.chromeTabsMessage !== ""
          ? statusData.chromeTabsMessage
          : statusData.chromeTabCatalog.length === 0
            ? "No Chrome tabs found"
            : "No matching Chrome tabs"
      color: statusData.chromeTabsMessage !== "" ? "#ed8796" : "#939ab7"
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 13
      font.bold: true
      wrapMode: Text.Wrap
    }
  }
}
