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
    readonly property bool resetReadFailed: source.snapshot?.resetCreditsUnavailable === true
    readonly property bool hasResetBadge: showResetBadge && (resetCredits > 0 || resetReadFailed)
    readonly property var quota: Limits.barWindow(source.snapshot, windowKey)
    readonly property var remaining: Limits.remainingPercent(quota, root.controller.now)
    value: remaining
    accent: remaining === 0 ? Theme.error : root.accent
    interactive: false
    accessibleText: Limits.quotaTooltip(label, source, quota, root.controller.now)
    tooltipOverride: showResetBadge && resetReadFailed
      ? (remaining === null ? "—" : Math.round(remaining) + "%") + "\nResets : vérification temporairement indisponible"
      : ""

    DialBadge {
      id: counter
      objectName: "resetCreditsBadge"
      visible: dial.hasResetBadge
      z: 2
      compact: true
      x: dial.width - width - Theme.barSize(3)
      y: Theme.barSize(2)
      color: root.accent
      labelObjectName: "resetCreditsCount"
      text: dial.resetReadFailed ? "?" : dial.resetCredits > 0 ? String(dial.resetCredits) : ""
      // Overlay inside the dial: the counter never adds a gap or moves its countdown.
      // No second glass region, which would refract the capsule again.
      Accessible.role: Accessible.Indicator
      Accessible.name: dial.source.name + ": " + (dial.resetCredits === null
        ? "nombre de resets indisponible" : Limits.plural(dial.resetCredits, "reset disponible", "resets disponibles"))

    }
  }

  component QuotaRow: Item {
    id: row
    property alias source: dial.source
    property alias windowKey: dial.windowKey
    property alias label: dial.label
    property alias logoSource: dial.logoSource
    property alias dialName: dial.objectName
    property alias showResetBadge: dial.showResetBadge
    // Each reading keeps its countdown within one widget-height cell.
    implicitHeight: Theme.barSize(32)
    implicitWidth: dial.width + (countdown.text !== ""
      ? Theme.barSize(4) + countdown.width + Theme.barSize(2) : 0)

    QuotaDial {
      id: dial
      anchors.verticalCenter: parent.verticalCenter
    }
    TextMetrics {
      id: countdownMetrics
      font: countdown.font
      text: countdown.text
    }
    Text {
      id: countdown
      objectName: dial.objectName + "Countdown"
      x: dial.width + Theme.barSize(4)
      anchors.verticalCenter: parent.verticalCenter
      // Hidden countdowns reserve neither text width nor spacing.
      width: text !== "" ? Math.ceil(countdownMetrics.advanceWidth) : 0
      text: Limits.quotaResetText(dial.quota, root.controller.now)
      visible: text !== ""
      color: dial.quota?.resetsAt > root.controller.now ? Theme.foreground : Theme.secondary
      font.family: "Ubuntu"
      font.pixelSize: Theme.barSize(16)
      horizontalAlignment: Text.AlignLeft
      elide: Text.ElideRight
      textFormat: Text.PlainText
      Accessible.role: Accessible.StaticText
      Accessible.name: dial.label + " · Reset automatique : " + text
    }
  }

  Row {
    spacing: Theme.barSize(4)
    QuotaRow {
      dialName: "gptUsageDial"
      label: "GPT / Codex"
      source: root.controller.codex
      windowKey: "codex"
      logoSource: Qt.resolvedUrl("../features/usage/icons/codex.svg")
    }
    QuotaRow {
      dialName: "claudeFiveHourDial"
      label: "Claude · 5 h"
      source: root.controller.claude
      windowKey: "five_hour"
      showResetBadge: false
      logoSource: Qt.resolvedUrl("../features/usage/icons/claude.svg")
    }
    QuotaRow {
      dialName: "claudeWeeklyDial"
      label: "Claude · semaine"
      source: root.controller.claude
      windowKey: "seven_day"
      logoSource: Qt.resolvedUrl("../features/usage/icons/claude.svg")
    }
  }
}
