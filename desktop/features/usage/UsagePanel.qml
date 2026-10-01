pragma ComponentBehavior: Bound
import QtQuick
import "../../ui/Theme.js" as Theme
import "UsageLimits.js" as Limits

// Claude and Codex plan limits. The view only reads its controller; closing
// is a request to the shell, and R asks for an immediate refresh.
FocusScope {
  id: root
  required property var controller
  property var linkOpener: url => Qt.openUrlExternally(url)
  signal closeRequested()
  implicitHeight: updateLabel.y + updateLabel.height + 12

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
  component Divider: Rectangle {
    x: 14; width: parent.width - 28; height: 1
    color: Theme.surfaceRaised
  }

  Label {
    x: 16; y: 12; width: 22; height: 24
    text: "󰊚"; font.pixelSize: 18
    color: Theme.usageAccent
  }
  Label {
    objectName: "usageTitle"
    x: 44; y: 12; width: parent.width - x - 16; height: 24
    text: "Limites d’utilisation"; font.pixelSize: 14; font.bold: true
    color: Theme.foreground
  }
  Divider { y: 46 }

  UsageSection {
    id: claudeSection
    objectName: "claudeSection"
    x: 16; y: 58; width: parent.width - 32; height: implicitHeight
    source: root.controller.claude
    logoSource: Qt.resolvedUrl("icons/claude.svg")
    now: root.controller.now
    onExternalLinkRequested: url => root.linkOpener(url)
  }
  Divider { y: claudeSection.y + claudeSection.height + 12 }
  UsageSection {
    id: codexSection
    objectName: "codexSection"
    x: 16; y: claudeSection.y + claudeSection.height + 24
    width: parent.width - 32; height: implicitHeight
    source: root.controller.codex
    logoSource: Qt.resolvedUrl("icons/codex.svg")
    now: root.controller.now
    onExternalLinkRequested: url => root.linkOpener(url)
  }

  Label {
    x: 16; y: updateLabel.y
    width: Math.max(0, updateLabel.x - x - 10); height: 16
    text: "Claude Code · Codex"
    font.pixelSize: 10
  }
  Label {
    id: updateLabel
    objectName: "updateLabel"
    anchors.right: parent.right
    anchors.rightMargin: 16
    y: codexSection.y + codexSection.height + 14; height: 16
    text: root.controller.loading ? "Actualisation…"
      : Limits.updateText(root.controller.updatedAt, root.controller.now)
    font.pixelSize: 10
  }
}
