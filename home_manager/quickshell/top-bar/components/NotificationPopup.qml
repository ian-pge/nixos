pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import QtQuick.Effects
import "Layout.js" as Layout
import "Theme.js" as Theme

Item {
  id: root

  required property var notificationData
  property real maximumWidth: 480
  readonly property var notification: notificationData.presented
  readonly property string appName: notification !== null ? notification.appName : ""
  readonly property string title: notification !== null ? notification.summary : ""
  readonly property string body: notification !== null ? notification.body : ""
  readonly property string photo: notification !== null ? notification.image : ""
  readonly property string appIcon: notification !== null ? notification.appIcon : ""

  readonly property real naturalTextWidth: Math.max(
    measureLines(appMetrics, appName),
    measureLines(titleMetrics, title),
    measureLines(bodyMetrics, body))

  // Measure unwrapped lines, never the content width of the animated card.
  implicitWidth: Layout.boundedWidth(16 + 42 + 12 + naturalTextWidth + 16, 160, 480)
  readonly property int textCount: (appName !== "" ? 1 : 0)
    + (title !== "" ? 1 : 0) + (body !== "" ? 1 : 0)
  readonly property real textHeight: (appName !== "" ? appLabel.implicitHeight : 0)
    + (title !== "" ? titleLabel.implicitHeight : 0)
    + (body !== "" ? bodyMeasure.implicitHeight : 0)
    + Math.max(0, textCount - 1) * textColumn.spacing
  implicitHeight: Math.min(180, Math.max(80, textHeight + 28))

  FontMetrics { id: appMetrics; font: appLabel.font }
  FontMetrics { id: titleMetrics; font: titleLabel.font }
  FontMetrics { id: bodyMetrics; font: bodyLabel.font }

  function measureLines(metrics, text) {
    return Layout.widestText(metrics, text.split(/\r\n|[\r\n\u2028\u2029]/));
  }

  // Lay out the final height at the capped destination width, not mid-morph.
  Text {
    id: bodyMeasure
    visible: false
    width: Math.max(1, Math.min(root.implicitWidth, root.maximumWidth) - 16 - 42 - 12 - 16)
    text: root.body
    font: bodyLabel.font
    textFormat: bodyLabel.textFormat
    wrapMode: bodyLabel.wrapMode
    maximumLineCount: bodyLabel.maximumLineCount
    elide: bodyLabel.elide
  }

  Rectangle {
    id: avatarFrame
    x: 16
    y: 16
    width: 42
    height: 42
    radius: 21
    color: Theme.surfaceRaised

    Image {
      id: avatar
      anchors.fill: parent
      source: root.photo
      asynchronous: true
      fillMode: Image.PreserveAspectCrop
      sourceSize: Qt.size(84, 84)
      visible: status === Image.Ready
      layer.enabled: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: avatarMask
      }
    }

    Item {
      id: avatarMask
      anchors.fill: parent
      layer.enabled: true
      visible: false
      Rectangle { anchors.fill: parent; radius: width / 2; color: "white" }
    }

    Image {
      id: fallbackIcon
      anchors.fill: parent
      anchors.margins: 8
      visible: avatar.status !== Image.Ready
      source: root.appIcon === "" ? ""
        : root.appIcon.startsWith("/") ? "file://" + root.appIcon
        : root.appIcon.includes(":") ? root.appIcon : Quickshell.iconPath(root.appIcon)
      sourceSize: Qt.size(26, 26)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }

    Text {
      anchors.centerIn: parent
      visible: avatar.status !== Image.Ready && fallbackIcon.status !== Image.Ready
      text: "󰂚"
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 23
      color: Theme.state
    }
  }

  Column {
    id: textColumn
    anchors.left: avatarFrame.right
    anchors.leftMargin: 12
    anchors.right: parent.right
    anchors.rightMargin: 16
    y: 14
    spacing: 4

    Text {
      id: appLabel
      width: parent.width
      text: root.appName
      visible: text !== ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 10
      font.bold: true
    }

    Text {
      id: titleLabel
      width: parent.width
      text: root.title
      visible: text !== ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Theme.foreground
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      id: bodyLabel
      width: parent.width
      text: root.body
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      maximumLineCount: 4
      elide: Text.ElideRight
      color: Theme.foreground
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 13
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onWheel: event => event.accepted = true
    onClicked: root.notificationData.activate()
  }
}
