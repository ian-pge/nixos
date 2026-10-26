import QtQuick
import "../../ui"
import "../../ui/Theme.js" as Theme

// Full build view: download and build bars, then the running Nix jobs.
// Every accent uses the update colour so the panel reads as one widget.
Item {
  id: root
  objectName: "updateBuildProgress"

  required property var progress
  property string title: ""
  // Replaces the percentage, e.g. with the cancellation hint.
  property string status: ""
  property string spinnerFrame: "loader-circle"
  readonly property color accent: Theme.sideUpdates
  readonly property int maxRows: 4

  readonly property var downloads: progress && progress.downloads ? progress.downloads : ({})
  readonly property var builds: progress && progress.builds ? progress.builds : ({})
  readonly property bool showDownloads: (downloads.expected || 0) > 0
    || (downloads.expectedBytes || 0) > 0
  readonly property bool showBuilds: (builds.expected || 0) > 0
  readonly property var running: progress && Array.isArray(progress.running)
    ? progress.running.slice(0, maxRows) : []
  readonly property int runningCount: progress ? (progress.runningCount || running.length) : 0

  readonly property int headerHeight: 40
  readonly property int sectionHeight: 40
  readonly property int rowHeight: 40
  readonly property int sectionsHeight: (showDownloads ? sectionHeight : 0)
    + (showBuilds ? sectionHeight : 0)
  implicitHeight: headerHeight + sectionsHeight
    + (running.length > 0 ? 24 + running.length * rowHeight : 0) + 10

  function formatBytes(value) {
    const units = ["B", "KB", "MB", "GB", "TB"];
    let amount = Math.max(0, value || 0);
    let unit = 0;
    while (amount >= 1000 && unit < units.length - 1) {
      amount /= 1000;
      ++unit;
    }
    const digits = unit === 0 || amount >= 100 ? 0 : 1;
    return amount.toFixed(digits).replace(/\.0$/, "") + " " + units[unit];
  }

  function formatDuration(seconds) {
    const total = Math.max(0, Math.floor(seconds || 0));
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor(total / 60) % 60;
    const rest = String(total % 60).padStart(2, "0");
    return hours > 0 ? hours + ":" + String(minutes).padStart(2, "0") + ":" + rest
      : minutes + ":" + rest;
  }

  function fraction(done, expected) {
    return expected > 0 ? Math.max(0, Math.min(1, done / expected)) : 0;
  }

  readonly property string statusText: status !== "" ? status : "BUILDING · " + (progress ? progress.percent || 0 : 0) + "%"
  readonly property string downloadsText: {
    const parts = [(downloads.done || 0) + " / " + (downloads.expected || 0)];
    if ((downloads.expectedBytes || 0) > 0)
      parts.push(formatBytes(downloads.bytes) + " / " + formatBytes(downloads.expectedBytes));
    if ((downloads.speed || 0) > 0)
      parts.push(formatBytes(downloads.speed) + "/s");
    return parts.join(" · ");
  }
  readonly property real downloadsFraction: (downloads.expectedBytes || 0) > 0
    ? fraction(downloads.bytes || 0, downloads.expectedBytes)
    : fraction(downloads.done || 0, downloads.expected || 0)

  function rowDetail(job) {
    if (job.kind === "download")
      return (job.expectedBytes || 0) > 0
        ? formatBytes(job.bytes) + " / " + formatBytes(job.expectedBytes)
        : "Fetching from cache";
    return job.log || "";
  }

  function rowStatus(job) {
    const label = job.kind === "download" ? "download" : (job.phase || "building");
    return label + " · " + formatDuration(job.elapsed);
  }

  component SectionLabel: Text {
    height: 16
    verticalAlignment: Text.AlignVCenter
    color: Theme.inactive
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 10
    font.bold: true
    font.letterSpacing: 0.6
  }

  component SectionValue: Text {
    height: 16
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignRight
    color: Theme.secondary
    elide: Text.ElideLeft
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 12
    font.bold: true
  }

  component Bar: Rectangle {
    property real value: 0
    height: 5
    radius: 2.5
    color: Theme.surfaceRaised
    Rectangle {
      width: parent.width * parent.value
      height: parent.height
      radius: parent.radius
      color: root.accent
      Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }
  }

  component Section: Item {
    property string label
    property string value
    property real amount: 0
    height: root.sectionHeight
    SectionLabel { anchors.left: parent.left; y: 4; text: parent.label }
    SectionValue {
      anchors.right: parent.right
      y: 4
      width: parent.width - 130
      text: parent.value
    }
    Bar { anchors.left: parent.left; anchors.right: parent.right; y: 25; value: parent.amount }
  }

  Icon {
    id: headerIcon
    size: 17
    spinning: true
    anchors.left: parent.left
    anchors.leftMargin: 16
    y: 9
    width: 20
    height: 20
    name: root.spinnerFrame
    color: root.accent
  }

  Text {
    anchors.left: headerIcon.right
    anchors.leftMargin: 10
    anchors.right: headerStatus.left
    anchors.rightMargin: 12
    y: 8
    height: 22
    verticalAlignment: Text.AlignVCenter
    text: root.title
    color: Theme.foreground
    elide: Text.ElideRight
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 14
    font.bold: true
  }

  Text {
    id: headerStatus
    objectName: "buildProgressStatus"
    anchors.right: parent.right
    anchors.rightMargin: 16
    y: 9
    height: 20
    verticalAlignment: Text.AlignVCenter
    text: root.statusText
    color: root.accent
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 11
    font.bold: true
  }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 16
    anchors.rightMargin: 16
    y: root.headerHeight

    Section {
      objectName: "buildProgressDownloads"
      width: parent.width
      visible: root.showDownloads
      label: "DOWNLOADS"
      value: root.downloadsText
      amount: root.downloadsFraction
    }

    Section {
      objectName: "buildProgressBuilds"
      width: parent.width
      visible: root.showBuilds
      label: "BUILDS"
      value: (root.builds.done || 0) + " / " + (root.builds.expected || 0)
      amount: root.fraction(root.builds.done || 0, root.builds.expected || 0)
    }

    Item {
      width: parent.width
      height: 24
      visible: root.running.length > 0
      SectionLabel { anchors.bottom: parent.bottom; text: "RUNNING · " + root.runningCount }
    }

    Repeater {
      objectName: "buildProgressRows"
      model: root.running

      delegate: Item {
        required property var modelData
        width: parent.width
        height: root.rowHeight

        Icon {
          id: rowIcon
          size: 13
          spinning: true
          x: 2
          y: 8
          width: 14
          height: 14
          name: root.spinnerFrame
          color: root.accent
        }

        Text {
          anchors.left: rowIcon.right
          anchors.leftMargin: 10
          anchors.right: rowStatus.left
          anchors.rightMargin: 10
          y: 5
          height: 20
          verticalAlignment: Text.AlignVCenter
          text: modelData.name || ""
          color: Theme.foreground
          elide: Text.ElideRight
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 13
          font.bold: true
        }

        Text {
          id: rowStatus
          anchors.right: parent.right
          y: 5
          height: 20
          verticalAlignment: Text.AlignVCenter
          text: root.rowStatus(modelData)
          color: Theme.secondary
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 12
          font.bold: true
        }

        Text {
          anchors.left: rowIcon.right
          anchors.leftMargin: 10
          anchors.right: parent.right
          y: 23
          height: 14
          verticalAlignment: Text.AlignVCenter
          text: root.rowDetail(modelData)
          color: Theme.secondary
          elide: Text.ElideRight
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 10
        }
      }
    }
  }
}
