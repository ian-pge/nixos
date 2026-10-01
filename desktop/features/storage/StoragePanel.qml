pragma ComponentBehavior: Bound
import QtQuick
import "../../ui/Theme.js" as Theme
import "Storage.js" as Storage

FocusScope {
  id: root
  required property var controller
  signal closeRequested()
  readonly property var snapshot: controller.snapshot
  readonly property var rows: Storage.rows(snapshot)
  readonly property real measuredBytes: Storage.sum(rows)
  readonly property bool partial: snapshot !== null && Storage.incomplete(rows)
  readonly property var colors: ({docker: Theme.sideApplications, nix: Theme.sideSystem,
    applications: Theme.sideDisk, personal: Theme.sideNotifications,
    vm: Theme.sideWeather, other: Theme.inactive})
  implicitHeight: footer.y + footer.height + 12

  function focusWhenEnabled() {
    if (enabled && visible)
      Qt.callLater(() => { if (root.enabled && root.visible) root.forceActiveFocus(); });
  }
  onEnabledChanged: focusWhenEnabled()
  onVisibleChanged: focusWhenEnabled()
  Component.onCompleted: focusWhenEnabled()
  Keys.onPressed: event => {
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) root.closeRequested();
    else if (event.key === Qt.Key_R) root.controller.refresh(true);
    else return;
    event.accepted = true;
  }

  component Label: Text {
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 11
    height: 18
    textFormat: Text.PlainText
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
  }
  Label {
    x: 16; y: 12; width: 22; height: 24
    text: ""; font.pixelSize: 18; color: Theme.sideDisk
  }
  Label {
    objectName: "storageTitle"
    x: 44; y: 12; width: parent.width - x - 16; height: 24
    text: "Stockage"; font.pixelSize: 14; font.bold: true
    color: Theme.foreground
  }
  Rectangle { x: 14; y: 46; width: parent.width - 28; height: 1; color: Theme.surfaceRaised }
  Label {
    objectName: "storageDiskUsed"
    x: 16; y: 56; width: parent.width - 32; height: 23
    text: Storage.formatBytes(root.snapshot?.disk?.usedBytes) + " utilisés"
    font.pixelSize: 17; font.bold: true; color: Theme.sideDisk
  }
  Label {
    objectName: "storageDiskFree"
    x: 16; y: 80; width: parent.width - 32
    text: Storage.formatBytes(root.snapshot?.disk?.availableBytes) + " libres sur "
      + Storage.formatBytes(root.snapshot?.disk?.totalBytes)
  }
  StorageChart {
    id: chart
    objectName: "storageChart"
    y: 104; anchors.horizontalCenter: parent.horizontalCenter
    width: 146; height: 146
    rows: root.rows; colors: root.colors; loading: root.controller.loading
  }
  Label {
    id: chartHeading
    objectName: "storageChartHeading"
    x: 16; y: chart.y + chart.height + 8; width: parent.width - 32
    text: root.snapshot === null ? root.controller.loading ? "Mesure en cours…" : "Répartition indisponible"
      : root.partial ? "Mesure partielle · répartition estimée"
      : root.snapshot.estimated ? "Répartition estimée" : "Répartition des fichiers mesurés"
    horizontalAlignment: Text.AlignHCenter
  }
  Item {
    id: legend
    objectName: "storageLegend"
    x: 16; y: chartHeading.y + chartHeading.height + 10
    width: parent.width - 32
    height: root.rows.reduce((total, row) => total + row.height, 0)
    Repeater {
      model: root.rows
      delegate: Item {
        id: row
        required property var modelData
        objectName: "storageRow_" + modelData.id
        y: modelData.y; width: legend.width; height: modelData.height
        Accessible.role: Accessible.StaticText
        Accessible.name: modelData.label.replace("\n", " ") + ": " + amount.text
        Rectangle {
          x: 0; y: 6; width: 8; height: 8; radius: 4
          color: root.colors[row.modelData.id]
        }
        Label {
          objectName: "storageCategoryLabel"
          x: 16; width: Math.max(0, amount.x - x - 8)
          height: row.modelData.id === "personal" ? 34 : 20
          text: row.modelData.label
          color: Theme.foreground; font.pixelSize: 12
        }
        Label {
          id: amount
          objectName: "storageCategoryBytes"
          anchors.right: parent.right; width: implicitWidth; height: 20
          text: (row.modelData.partial && row.modelData.bytes !== null ? "≥ " : "")
            + Storage.formatBytes(row.modelData.bytes)
          color: Theme.foreground; font.pixelSize: 12
        }
        Label {
          objectName: "storageCategoryPercent"
          anchors.right: parent.right; y: 18; height: 13
          text: Storage.percent(row.modelData.bytes, root.measuredBytes)
          font.pixelSize: 9
        }
        Label {
          objectName: "storageApplicationsDetail"
          x: 16; y: 34; width: Math.max(0, parent.width - x); height: 14
          visible: row.modelData.id === "applications"
          text: "Caches " + Storage.formatBytes(row.modelData.cacheBytes)
            + " · Données " + Storage.formatBytes(row.modelData.dataBytes)
          font.pixelSize: 10
        }
      }
    }
  }
  Label {
    id: note
    objectName: "storageNote"
    x: 16; y: legend.y + legend.height + 2; width: parent.width - 32
    height: visible ? 28 : 0
    visible: root.snapshot !== null && (root.partial || root.snapshot.estimated)
    text: root.partial ? "Certaines données restent à mesurer."
      : root.snapshot?.estimated ? "Les fichiers partagés peuvent être comptés plusieurs fois." : ""
    wrapMode: Text.WordWrap
    verticalAlignment: Text.AlignTop
    font.pixelSize: 10
  }
  Label {
    id: errorLabel
    objectName: "storageError"
    x: 16; y: note.y + note.height; width: parent.width - 32
    height: visible ? 30 : 0
    visible: root.controller.error !== ""
    text: root.snapshot !== null ? "Échec de l’actualisation · dernière mesure conservée" : root.controller.error
    color: Theme.error; wrapMode: Text.WordWrap
    font.pixelSize: 10
  }
  Item {
    id: footer
    x: 16; y: errorLabel.y + errorLabel.height + 6
    width: parent.width - 32; height: 24
    Label {
      objectName: "storageUpdated"
      width: Math.max(0, refreshButton.x - 8); height: parent.height
      text: root.controller.loading ? "Mesure en cours…"
        : Storage.timestamp(root.controller.updatedAt, root.controller.now)
      font.pixelSize: 10
    }
    Rectangle {
      id: refreshButton
      objectName: "storageRefresh"
      anchors.right: parent.right
      width: 102; height: 24; radius: 6
      color: pointer.containsMouse ? Theme.surfaceRaised : "transparent"
      enabled: root.enabled && !root.controller.loading
      Accessible.role: Accessible.Button
      Accessible.name: "Actualiser le stockage"
      Accessible.onPressAction: if (refreshButton.enabled) root.controller.refresh(true)
      Label {
        anchors.fill: parent
        text: "Actualiser · R"; horizontalAlignment: Text.AlignHCenter
        color: refreshButton.enabled ? Theme.sideDisk : Theme.inactive
      }
      MouseArea {
        id: pointer
        anchors.fill: parent; hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.controller.refresh(true)
      }
    }
  }
}
