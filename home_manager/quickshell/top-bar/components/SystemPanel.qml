pragma ComponentBehavior: Bound
import QtQuick
import "Theme.js" as Theme

FocusScope {
  id: root
  required property var statusData
  readonly property var telemetry: statusData.systemTelemetry
  readonly property var system: telemetry.systemFresh ? telemetry.system : null
  readonly property var gpu: telemetry.gpuFresh ? telemetry.gpu : null
  readonly property bool swapVisible: (system?.swapUsedBytes ?? 0) > 0
  implicitHeight: footer.y + footer.height + 12

  function value(number, decimals, unit) {
    return typeof number === "number" && isFinite(number)
      ? number.toLocaleString(Qt.locale("fr_FR"), "f", decimals) + unit : "—";
  }
  function memory(used, total) {
    if (typeof used !== "number" || typeof total !== "number" || total <= 0)
      return "—";
    return value(used / 1073741824, 1, "") + " / " + value(total / 1073741824, 1, " Gio");
  }
  function focusWhenEnabled() {
    if (enabled && visible)
      Qt.callLater(() => { if (root.enabled && root.visible) root.forceActiveFocus(); });
  }
  onEnabledChanged: focusWhenEnabled()
  onVisibleChanged: focusWhenEnabled()
  Component.onCompleted: focusWhenEnabled()
  Keys.onEscapePressed: event => { statusData.hideSystemPanel(); event.accepted = true; }

  component Label: Text {
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 11
    height: 18
    textFormat: Text.PlainText
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
  }
  component Heading: Item {
    property string title
    property string value
    height: 22
    Label {
      anchors.left: parent.left
      width: Math.max(0, parent.width - reading.width - 8)
      height: parent.height
      text: parent.title
      font.pixelSize: 13; font.bold: true
      color: Theme.sideSystem
    }
    Label {
      id: reading
      anchors.right: parent.right
      height: parent.height
      text: parent.value
      font.pixelSize: 16; font.bold: true
      color: Theme.sideSystem
    }
  }
  component Divider: Rectangle {
    x: 14; width: parent.width - 28; height: 1
    color: Theme.surfaceRaised
  }

  Label {
    x: 16; y: 12; width: 22; height: 24
    text: ""; font.pixelSize: 18
    color: Theme.sideSystem
  }
  Label {
    objectName: "systemTitle"
    x: 44; y: 12; width: parent.width - x - 16; height: 24
    text: "Système"; font.pixelSize: 14; font.bold: true
    color: Theme.foreground
  }
  Divider { y: 46 }

  Item {
    id: cpuSection
    objectName: "cpuSection"
    x: 16; y: 58; width: parent.width - 32; height: cpuProcesses.y + cpuProcesses.height
    Heading {
      objectName: "cpuHeading"
      width: parent.width
      title: "  CPU"; value: root.value(root.system?.cpu, 0, " %")
    }
    Label {
      objectName: "cpuModel"
      y: 25; width: parent.width
      text: root.telemetry.system?.cpuName || "Processeur"
    }
    Label {
      objectName: "cpuDetails"
      y: 46; width: parent.width
      text: "Temp. " + root.value(root.system?.cpuTemperatureC, 0, " °C")
        + "   ·   Fréq. moy. " + root.value(root.system?.cpuFrequencyMHz === null
          || root.system === null ? null : root.system.cpuFrequencyMHz / 1000, 2, " GHz")
    }
    ProcessList {
      id: cpuProcesses
      objectName: "cpuProcesses"
      y: 72; width: parent.width
      heading: "Top CPU · 100 % = 1 cœur"
      rows: root.telemetry.processTopFresh ? root.telemetry.processTop.cpu : null
      emptyText: root.system === null || root.telemetry.processTop?.error ? "Processus indisponibles" : "Mesure en cours…"
    }
  }
  Divider { y: cpuSection.y + cpuSection.height + 12 }

  Item {
    id: memorySection
    objectName: "memorySection"
    x: 16; y: cpuSection.y + cpuSection.height + 24
    width: parent.width - 32; height: memoryProcesses.y + memoryProcesses.height
    Heading {
      objectName: "memoryHeading"
      width: parent.width
      title: "   RAM"; value: root.value(root.system?.memory, 0, " %")
    }
    Label {
      objectName: "memoryDetails"
      y: 29; width: parent.width
      text: root.memory(root.system?.memoryUsedBytes, root.system?.memoryTotalBytes)
      color: Theme.foreground; font.pixelSize: 12
    }
    Label {
      objectName: "swapDetails"
      y: 51; width: parent.width; visible: root.swapVisible
      text: "Swap  " + root.memory(root.system?.swapUsedBytes, root.system?.swapTotalBytes)
    }
    ProcessList {
      id: memoryProcesses
      objectName: "memoryProcesses"
      y: root.swapVisible ? 82 : 58; width: parent.width
      heading: "Top RAM · mémoire résidente"
      metric: "memory"
      rows: root.telemetry.processTopFresh ? root.telemetry.processTop.memory : null
      emptyText: root.system === null || root.telemetry.processTop?.error ? "Processus indisponibles" : "Mesure en cours…"
    }
  }
  Divider { y: memorySection.y + memorySection.height + 12 }

  Item {
    id: gpuSection
    objectName: "gpuSection"
    x: 16; y: memorySection.y + memorySection.height + 24
    width: parent.width - 32; height: gpuProcesses.y + gpuProcesses.height
    Heading {
      objectName: "gpuHeading"
      width: parent.width
      title: "  GPU"
      value: root.gpu?.poweredOn === false ? "Veille" : root.value(root.gpu?.usage, 0, " %")
    }
    Label {
      objectName: "gpuModel"
      y: 25; width: parent.width
      text: root.telemetry.gpu?.name || "Carte graphique"
    }
    Label {
      objectName: "gpuDetails"
      y: 46; width: parent.width
      text: "Temp. " + root.value(root.gpu?.temperatureC, 0, " °C")
        + "   ·   VRAM " + root.memory(root.gpu?.memoryUsedBytes, root.gpu?.memoryTotalBytes)
    }
    ProcessList {
      id: gpuProcesses
      objectName: "gpuProcesses"
      y: 72; width: parent.width
      metric: root.telemetry.gpuTopFresh && root.telemetry.gpuTop.sort === "vram" ? "vram" : "gpu"
      heading: metric === "vram" ? "Top VRAM · charge par processus indisponible" : "Top GPU · charge 3D/calcul · VRAM"
      rows: root.telemetry.gpuTopFresh ? root.telemetry.gpuTop.rows : null
      emptyText: root.gpu?.poweredOn === false ? "Carte en veille"
        : root.gpu === null || root.telemetry.gpuTop?.error ? "Processus indisponibles" : "Mesure en cours…"
    }
  }
  Label {
    id: footer
    objectName: "systemFooter"
    x: 16; y: gpuSection.y + gpuSection.height + 12
    width: parent.width - 32; height: 16
    text: "Top 5 · actualisation toutes les 2 s"
    font.pixelSize: 10
  }
}
