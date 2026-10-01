pragma ComponentBehavior: Bound
import QtQuick
import "../ui/Theme.js" as Theme
import "../features/usage/UsageLimits.js" as Limits

BarBlock {
  id: root
  objectName: "usageBlock"
  required property var controller
  circularContent: true
  accent: Theme.usageAccent

  component QuotaDial: BarDial {
    id: dial
    required property var source
    required property string windowKey
    property bool showResetBadge: true
    readonly property var resetCredits: source.snapshot?.resetCredits ?? null
    readonly property var quota: Limits.barWindow(source.snapshot, windowKey)
    readonly property var remaining: Limits.remainingPercent(quota, root.controller.now)
    value: remaining
    accent: remaining === 0 ? Theme.error : root.accent
    interactive: false
    accessibleText: Limits.quotaTooltip(label, source, quota, root.controller.now)

    Rectangle {
      id: counter
      objectName: "resetCreditsBadge"
      visible: dial.showResetBadge && dial.resetCredits !== null && dial.resetCredits > 0
      z: 2
      x: dial.width - width + Theme.barSize(1)
      y: -Theme.barSize(2)
      width: Math.max(Theme.barSize(12), countLabel.implicitWidth + Theme.barSize(4))
      height: Theme.barSize(12)
      radius: height / 2
      color: root.accent
      // Keep the opaque badge inside the block's rendering bounds. A second
      // glass region here would refract the underlying capsule a second time.
      Accessible.role: Accessible.Indicator
      Accessible.name: dial.source.name + ": " + (dial.resetCredits === null
        ? "nombre de resets indisponible" : Limits.plural(dial.resetCredits, "reset disponible", "resets disponibles"))

      Text {
        id: countLabel
        objectName: "resetCreditsCount"
        anchors.centerIn: parent
        text: dial.resetCredits > 0 ? String(dial.resetCredits) : ""
        color: Theme.background
        font.family: "Ubuntu"
        font.pixelSize: Theme.barSize(9)
        font.bold: true
      }
    }
  }

  Row {
    spacing: Theme.barSize(4)
    QuotaDial {
      objectName: "gptUsageDial"
      label: "GPT / Codex"
      source: root.controller.codex
      windowKey: "codex"
      logoSource: Qt.resolvedUrl("../features/usage/icons/codex.svg")
    }
    QuotaDial {
      objectName: "claudeFiveHourDial"
      label: "Claude · 5 h"
      source: root.controller.claude
      windowKey: "five_hour"
      showResetBadge: false
      logoSource: Qt.resolvedUrl("../features/usage/icons/claude.svg")
    }
    QuotaDial {
      objectName: "claudeWeeklyDial"
      label: "Claude · semaine"
      source: root.controller.claude
      windowKey: "seven_day"
      logoSource: Qt.resolvedUrl("../features/usage/icons/claude.svg")
    }
  }
}
