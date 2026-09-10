pragma ComponentBehavior: Bound
import QtQuick
import "Theme.js" as Theme

FocusScope {
  id: root

  required property var statusData
  property string selectedKey: ""
  readonly property var rows: sectionRows("OUTPUTS", statusData.audioOutputs)
    .concat(sectionRows("MICROPHONE", statusData.audioInputs))
  readonly property int selectedIndex: rows.findIndex(row => row.key === selectedKey)
  readonly property string deviceCountText: statusData.audioOutputs.length
    + " OUT · " + statusData.audioInputs.length + " IN"

  implicitWidth: 480
  implicitHeight: Math.min(398, 58 + rows.reduce((height, row) =>
    height + (row.header ? 28 : 42), 0))

  function sectionRows(section, nodes) {
    const rows = [{ section: section, header: true, node: null, key: section }];
    const sorted = nodes.slice().sort((a, b) =>
      statusData.audioDeviceLabel(a).localeCompare(statusData.audioDeviceLabel(b))
      || a.name.localeCompare(b.name));
    for (const node of sorted)
      rows.push({ section: section, header: false, node: node, key: node.name });
    if (sorted.length === 0)
      rows.push({ section: section, header: false, node: null, key: section + "-empty" });
    return rows;
  }

  function selectSection(section) {
    const candidates = rows.filter(row => row.section === section && row.node !== null);
    const active = section === "OUTPUTS" ? statusData.audioSink : statusData.microphoneSource;
    const candidate = candidates.find(row => row.node === active) || candidates[0];
    if (candidate)
      selectedKey = candidate.key;
  }

  function syncSelection(reset = false) {
    if (!reset && rows.some(row => row.node !== null && row.key === selectedKey))
      return;
    selectedKey = "";
    selectSection(statusData.audioOutputs.length > 0 ? "OUTPUTS" : "MICROPHONE");
  }

  function moveSelection(delta) {
    const candidates = rows.filter(row => row.node !== null);
    if (candidates.length === 0)
      return;
    const index = candidates.findIndex(row => row.key === selectedKey);
    selectedKey = candidates[(Math.max(0, index) + delta + candidates.length)
      % candidates.length].key;
  }

  function revealSelection() {
    if (selectedIndex >= 0)
      deviceList.positionViewAtIndex(selectedIndex, ListView.Contain);
  }

  onRowsChanged: Qt.callLater(() => {
    syncSelection();
    revealSelection();
  })
  onSelectedIndexChanged: Qt.callLater(revealSelection)
  onEnabledChanged: {
    if (enabled) {
      syncSelection(true);
      Qt.callLater(() => {
        root.forceActiveFocus();
        revealSelection();
      });
    }
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
      moveSelection(1);
    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
      moveSelection(-1);
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      const section = selectedIndex >= 0 ? rows[selectedIndex].section : "";
      selectSection(section === "OUTPUTS" ? "MICROPHONE" : "OUTPUTS");
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (selectedIndex >= 0)
        statusData.selectAudioDevice(rows[selectedIndex].node);
    } else if (event.key === Qt.Key_Escape) {
      statusData.hideAudioSelector();
    } else {
      return;
    }
    event.accepted = true;
  }

  Text {
    id: titleIcon
    anchors.left: parent.left
    anchors.leftMargin: 16
    y: 9
    width: 22
    height: 24
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: "󰕾"
    color: Theme.sideVolume
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 17
    font.bold: true
  }

  Text {
    anchors.left: titleIcon.right
    anchors.leftMargin: 10
    anchors.verticalCenter: titleIcon.verticalCenter
    text: "AUDIO"
    color: Theme.foreground
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 14
    font.bold: true
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: 16
    anchors.verticalCenter: titleIcon.verticalCenter
    text: root.deviceCountText
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
    id: deviceList
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: 48
    anchors.bottomMargin: 10
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.rows
    currentIndex: root.selectedIndex

    delegate: Item {
      id: row
      required property var modelData
      readonly property var node: modelData.node
      readonly property bool selected: node !== null && modelData.key === root.selectedKey
      readonly property bool active: node !== null && node === (node.isSink
        ? root.statusData.audioSink : root.statusData.microphoneSource)
      width: deviceList.width
      height: modelData.header ? 28 : 42

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        radius: 10
        color: row.selected ? Theme.surfaceRaised : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        visible: row.modelData.header
        text: row.modelData.section
        color: Theme.sideVolume
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 11
        font.bold: true
      }

      Text {
        id: deviceIcon
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        horizontalAlignment: Text.AlignHCenter
        visible: row.node !== null
        text: row.modelData.section === "OUTPUTS" ? "󰓃" : "󰍬"
        color: row.active ? Theme.sideVolume : Theme.inactive
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 18
      }

      Text {
        anchors.left: deviceIcon.right
        anchors.leftMargin: 10
        anchors.right: activeMark.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: !row.modelData.header
        text: row.node !== null ? root.statusData.audioDeviceLabel(row.node)
          : row.modelData.section === "OUTPUTS" ? "No audio outputs" : "No microphones"
        color: row.node === null || !row.node.ready ? Theme.inactive
          : row.selected ? Theme.selectedForeground : Theme.foreground
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 13
        font.bold: true
      }

      Text {
        id: activeMark
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        text: row.active ? "" : ""
        color: Theme.sideVolume
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 14
      }

      MouseArea {
        anchors.fill: parent
        enabled: row.node !== null && row.node.ready
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.selectedKey = row.modelData.key;
          root.statusData.selectAudioDevice(row.node);
        }
      }
    }
  }
}
