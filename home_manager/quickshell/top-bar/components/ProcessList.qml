pragma ComponentBehavior: Bound
import QtQuick
import "Theme.js" as Theme

Item {
  id: root
  property var rows: null
  property string heading: ""
  property string metric: "cpu"
  property string emptyText: "Mesure en cours…"
  readonly property var entries: Array.isArray(rows) ? rows.slice(0, 5) : []
  readonly property color accent: Theme.sideSystem
  implicitHeight: 24 + Math.max(1, entries.length) * 20
  height: implicitHeight

  function bytes(value) {
    if (typeof value !== "number" || !isFinite(value)) return "—";
    const gib = value >= 1073741824;
    return (value / (gib ? 1073741824 : 1048576)).toLocaleString(Qt.locale("fr_FR"), "f", gib ? 1 : 0)
      + (gib ? " Gio" : " Mio");
  }
  function percent(value) {
    return typeof value === "number" && isFinite(value)
      ? value.toLocaleString(Qt.locale("fr_FR"), "f", value < 10 ? 1 : 0) + " %" : "—";
  }
  component Label: Text {
    font.family: "Ubuntu Nerd Font"; font.pixelSize: 11
    color: Theme.secondary; textFormat: Text.PlainText
    elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
  }
  Label {
    objectName: "processHeading"
    width: parent.width; height: 20
    text: root.heading; color: root.accent
  }
  Label {
    objectName: "processEmpty"
    y: 24; width: parent.width; height: 20
    visible: root.entries.length === 0
    text: root.rows === null ? root.emptyText : "Aucun processus"
  }
  Repeater {
    model: root.entries
    delegate: Item {
      id: row
      required property int index
      required property var modelData
      objectName: "processRow" + index
      y: 24 + index * 20; width: root.width; height: 20
      Label {
        objectName: "processName"
        width: Math.max(0, pidLabel.x - 8); height: parent.height
        text: row.modelData.name; color: Theme.foreground
      }
      Label {
        id: pidLabel
        objectName: "processPid"
        x: Math.max(0, reading.x - width - 8); width: 52; height: parent.height
        text: row.modelData.pid; font.pixelSize: 9
        horizontalAlignment: Text.AlignRight
      }
      Label {
        id: reading
        objectName: "processReading"
        anchors.right: parent.right
        width: root.metric === "gpu" ? 122 : 72; height: parent.height
        horizontalAlignment: Text.AlignRight; color: root.accent
        text: root.metric === "memory" || root.metric === "vram" ? root.bytes(row.modelData.memoryBytes)
          : root.metric === "gpu" ? root.percent(row.modelData.usage) + " · " + root.bytes(row.modelData.memoryBytes)
          : root.percent(row.modelData.usage)
      }
    }
  }
}
