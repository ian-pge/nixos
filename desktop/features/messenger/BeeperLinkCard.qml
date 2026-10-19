import QtQuick
import QtQuick.Controls
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Button {
  id: root
  objectName: "beeperMessageLink"
  required property var link
  property bool outgoing: false
  property real textScale: 1
  property color accent: Theme.sideApplications
  property string searchQuery: ""
  readonly property bool searchMatch: Format.searchTextRanges(link.url + " " + link.title, searchQuery).length > 0
  readonly property color textColor: outgoing ? Theme.background : Theme.foreground
  signal openRequested(string url)
  signal copyRequested(string url)
  implicitWidth: 380 * Math.min(textScale, 1.3)
  implicitHeight: Math.max(72 * textScale, labels.implicitHeight + 20)
  focusPolicy: Qt.TabFocus
  padding: 10
  Accessible.name: link.title + " · " + link.address
  onClicked: root.openRequested(link.url)
  background: Rectangle {
    radius: 12
    color: root.outgoing ? Qt.alpha(Theme.background, root.down ? 0.16 : root.hovered ? 0.12 : 0.07) : root.down ? Theme.surfaceSelected : root.hovered ? Theme.surfaceRaised : Qt.alpha(root.accent, 0.08)
    border.width: root.searchMatch ? 2 : 1
    border.color: root.searchMatch ? Theme.yellow : Qt.alpha(root.outgoing ? Theme.background : root.accent, root.activeFocus ? 0.6 : 0.16)
  }
  contentItem: Item {
    Rectangle {
      id: badge
      anchors {
        left: parent.left
        verticalCenter: parent.verticalCenter
      }
      width: Math.min(40 * root.textScale, root.availableWidth * 0.25)
      height: width
      radius: 10 * root.textScale
      color: root.link.video ? "#e93d4f" : Qt.alpha(root.accent, 0.2)
      Icon {
        anchors.centerIn: parent
        size: Math.min(22 * root.textScale, badge.width * 0.65)
        name: root.link.video ? "play" : "globe"
        color: root.link.video ? "white" : root.textColor
      }
    }
    Column {
      id: labels
      anchors {
        left: badge.right
        right: external.left
        verticalCenter: parent.verticalCenter
        leftMargin: 12
        rightMargin: 10
      }
      spacing: 3
      Text {
        objectName: "beeperLinkTitle"
        width: parent.width
        text: root.link.title
        textFormat: Text.PlainText
        color: root.textColor
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font {
          family: "Ubuntu Nerd Font"
          pixelSize: Theme.beeperFont.control * root.textScale
          weight: Font.DemiBold
        }
      }
      Text {
        objectName: "beeperLinkAddress"
        width: parent.width
        text: root.link.address === root.link.title ? "Ouvrir le lien" : root.link.address
        textFormat: Text.PlainText
        color: root.outgoing ? Qt.alpha(Theme.background, 0.7) : Theme.secondary
        elide: Text.ElideRight
        font {
          family: "Ubuntu Nerd Font"
          pixelSize: Theme.beeperFont.caption * root.textScale
        }
      }
    }
    Icon {
      id: external
      anchors {
        right: parent.right
        verticalCenter: parent.verticalCenter
      }
      name: "external-link"
      size: 16 * root.textScale
      color: Qt.alpha(root.textColor, root.hovered ? 1 : 0.55)
    }
  }
  HoverHandler {
    cursorShape: Qt.PointingHandCursor
  }
  ToolTip {
    visible: root.hovered
    delay: 500
    text: root.link.url
    contentItem: Text {
      text: root.link.url
      textFormat: Text.PlainText
      color: Theme.foreground
      font.pixelSize: Theme.beeperFont.caption
    }
    background: Rectangle {
      radius: 8
      color: Theme.surfaceRaised
    }
  }
  TapHandler {
    acceptedButtons: Qt.RightButton
    onTapped: linkMenu.popup()
  }
  Menu {
    id: linkMenu
    objectName: "beeperLinkMenu"
    MenuItem {
      text: "Ouvrir le lien"
      onTriggered: root.openRequested(root.link.url)
    }
    MenuItem {
      objectName: "beeperLinkCopy"
      text: "Copier le lien"
      onTriggered: root.copyRequested(root.link.url)
    }
  }
}
