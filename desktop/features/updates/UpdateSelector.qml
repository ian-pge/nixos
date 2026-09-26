import QtQuick
import "../../ui/Layout.js" as Layout
import "../../ui/Theme.js" as Theme

FocusScope {
  id: root

  required property var updates
  required property var auth
  property string spinnerFrame: "⠋"
  signal closeRequested()
  readonly property var availableUpdates: updates.updates
  readonly property int rowCount: Math.max(1, availableUpdates.length)
  readonly property bool authMode: auth.active
  readonly property bool successMode: !authMode
    && updates.phase === "success"
  readonly property bool cleaningMode: !authMode
    && updates.phase === "cleaning"
  readonly property bool listMode: !authMode
    && updates.phase === "idle"
  readonly property bool compactStatusMode: listMode
    && (updates.checking || availableUpdates.length === 0)
  readonly property bool changesMode: !authMode && !successMode
    && updates.summaryReady
  readonly property bool progressMode: !authMode && !successMode && !cleaningMode
    && !listMode && !changesMode
  readonly property bool updateProcessing: updates.busy
  readonly property string phaseLabel: {
    if (updates.phase === "updating") return "UPDATING";
    if (updates.phase === "building") return "BUILDING";
    if (updates.phase === "awaitingInstall") return "READY";
    if (updates.phase === "preparingAuth") return "AUTH";
    if (updates.phase === "installing") return "INSTALLING";
    if (updates.phase === "cleaning") return "CLEANING";
    if (updates.phase === "success")
      return updates.operation === "clean" ? "COMPLETE" : "REBOOT";
    if (updates.phase === "error") return "ERROR";
    return "UPDATE";
  }
  readonly property string listTitleText: updates.checking
    ? "Checking for updates…"
    : updates.checkFailed ? "Update check failed"
    : updates.rebootRequired ? "Update ready" : "NixOS updates"
  readonly property string listStatusText: updates.checking ? "CHECKING"
    : updates.checkFailed ? "ERROR"
      : updates.rebootRequired ? "REBOOT"
      : availableUpdates.length > 0 ? availableUpdates.length + " AVAILABLE" : "UP TO DATE"
  readonly property string progressTitleText:
    updates.message || "NixOS update"
  readonly property string changesStatusText:
    updates.changes.length + " CHANGES"
  readonly property string completionTitleText:
    cleaningMode || updates.operation === "clean"
      ? updates.message
      : updates.message || "Update ready — reboot required"
  readonly property string completionStatusText: cleaningMode ? "CLEANING"
    : updates.operation === "clean" ? "CLEANED" : "REBOOT"
  readonly property string authLabelText:
    auth.supplementaryMessage !== ""
      ? auth.supplementaryMessage : auth.prompt

  implicitWidth: adaptiveWidth()
  implicitHeight: authMode || successMode || cleaningMode || progressMode ? 36
    : listMode ? (compactStatusMode ? 36 : 52 + rowCount * 30 + 10)
    : changesMode ? Math.min(750,
      50 + Math.max(1, updates.changes.length) * 34)
    : 36

  FontMetrics {
    id: titleMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 14
    font.bold: true
  }

  FontMetrics {
    id: rowTitleMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 13
    font.bold: true
  }

  FontMetrics {
    id: dateMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 12
    font.bold: true
  }

  FontMetrics {
    id: statusMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 11
    font.bold: true
  }

  FontMetrics {
    id: kindMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 10
    font.bold: true
  }

  FontMetrics {
    id: versionMetrics
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: 10
  }

  function headerWidth(title, status) {
    return 16 + 20 + 10 + titleMetrics.advanceWidth(title) + 12
      + statusMetrics.advanceWidth(status) + 16;
  }

  function listContentWidth() {
    let width = headerWidth(listTitleText, listStatusText);
    for (let index = 0; index < availableUpdates.length; ++index) {
      const update = availableUpdates[index];
      width = Math.max(width, 64
        + rowTitleMetrics.advanceWidth(update.name || "")
        + dateMetrics.advanceWidth(update.date || ""));
    }
    return width;
  }

  function changesContentWidth() {
    let width = headerWidth(changesTitle(), changesStatusText);
    const changes = updates.changes;
    for (let index = 0; index < changes.length; ++index) {
      const change = changes[index];
      const versions = versionText(change.oldVersions) + "  →  "
        + versionText(change.newVersions);
      width = Math.max(width, 80
        + rowTitleMetrics.advanceWidth(change.name || "")
        + versionMetrics.advanceWidth(versions)
        + kindMetrics.advanceWidth((change.kind || "").toUpperCase()));
    }
    return width;
  }

  function adaptiveWidth() {
    if (authMode) {
      const authContentWidth = 16 + 20 + 10
        + rowTitleMetrics.advanceWidth(authLabelText) + 10 + 120 + 10 + 42 + 16;
      return Layout.boundedWidth(authContentWidth, 400, 480);
    }
    if (cleaningMode) {
      return Layout.boundedWidth(
        headerWidth(completionTitleText, completionStatusText), 280, 360);
    }
    if (successMode) {
      return Layout.boundedWidth(
        headerWidth(completionTitleText, completionStatusText), 240, 480);
    }
    if (listMode) {
      return Layout.boundedWidth(listContentWidth(),
        compactStatusMode ? 220 : 280, compactStatusMode ? 280 : 480);
    }
    if (changesMode)
      return Layout.boundedWidth(changesContentWidth(), 320, 480);
    if (progressMode) {
      return Layout.boundedWidth(
        headerWidth(progressTitleText, phaseLabel), 240, 480);
    }
    return 280;
  }

  function changeColor(kind) {
    if (kind === "added") return Theme.sideGpu;
    if (kind === "removed") return Theme.error;
    if (kind === "downgraded") return Theme.sideDisk;
    if (kind === "changed") return Theme.sideBrightness;
    return Theme.sideUpdates;
  }

  function versionText(versions) {
    if (versions === undefined || versions === null || versions.length === 0)
      return "∅";
    const visible = [];
    for (let index = 0; index < versions.length; index++)
      visible.push(versions[index] === "" ? "∅" : versions[index]);
    return visible.join(", ");
  }

  function scrollChanges(delta) {
    const maximum = Math.max(0, changeList.contentHeight - changeList.height);
    changeList.contentY = Math.max(0,
      Math.min(maximum, changeList.contentY + delta * 34));
  }

  function changesTitle() {
    if (updates.phase === "success") return "Update ready";
    if (updates.phase === "installing")
      return "Installing boot generation";
    if (updates.phase === "error") return "Installation failed";
    return "Package changes";
  }

  onEnabledChanged: {
    if (enabled)
      Qt.callLater(() => root.forceActiveFocus());
  }

  onChangesModeChanged: {
    if (changesMode)
      Qt.callLater(() => {
        changeList.currentIndex = -1;
        changeList.contentY = 0;
      });
  }

  Keys.onPressed: event => {
    if (authMode) {
      if (event.key === Qt.Key_Escape) {
        auth.clearInput();
        root.closeRequested();
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        auth.submitResponse();
      } else if (event.key === Qt.Key_Backspace) {
        auth.eraseInput();
      } else if (event.key === Qt.Key_U
          && (event.modifiers & Qt.ControlModifier)) {
        auth.input = "";
      } else if (event.text.length > 0
          && !(event.modifiers
            & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        auth.appendInput(event.text);
      }
      event.accepted = true;
      return;
    }

    if (changesMode && event.key === Qt.Key_J) {
      root.scrollChanges(1);
      event.accepted = true;
    } else if (changesMode && event.key === Qt.Key_K) {
      root.scrollChanges(-1);
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      updates.handleEnter();
      event.accepted = true;
    } else if (event.key === Qt.Key_C && root.listMode
        && !updates.checking) {
      updates.startClean();
      event.accepted = true;
    } else if (event.key === Qt.Key_R && listMode) {
      updates.forceStatus();
      event.accepted = true;
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
      root.closeRequested();
      event.accepted = true;
    }
  }

  Item {
    id: listView
    anchors.fill: parent
    visible: root.listMode

    Item {
      id: updateIcon
      anchors.left: parent.left
      anchors.leftMargin: 16
      y: 9
      width: 20
      height: 20

      Text {
        id: checkingIcon
        anchors.fill: parent
        visible: updates.checking
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.spinnerFrame
        color: Theme.sideUpdates
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 17
        font.bold: true
      }

      Text {
        anchors.fill: parent
        visible: !updates.checking
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: updates.checkFailed ? ""
          : updates.rebootRequired ? "󰜉"
          : availableUpdates.length > 0 ? "" : ""
        color: updates.checkFailed ? Theme.error : Theme.sideUpdates
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 17
        font.bold: true
      }
    }

    Text {
      anchors.left: updateIcon.right
      anchors.leftMargin: 10
      y: 8
      height: 22
      verticalAlignment: Text.AlignVCenter
      text: root.listTitleText
      color: Theme.foreground
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: 16
      y: 9
      height: 20
      verticalAlignment: Text.AlignVCenter
      text: root.listStatusText
      color: updates.checkFailed ? Theme.error
        : updates.checking || availableUpdates.length > 0
          ? Theme.sideUpdates : Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 11
      font.bold: true
    }

    Rectangle {
      visible: !root.compactStatusMode
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      y: 40
      height: 1
      color: Theme.surfaceRaised
    }

    Item {
      id: updateViewport
      visible: !root.compactStatusMode
      anchors.left: parent.left
      anchors.right: parent.right
      y: 42
      height: Math.max(0, root.height - y)
      clip: true

      Column {
        id: updateRows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        y: 6
        spacing: 0

        Repeater {
          model: root.availableUpdates

          Item {
            required property var modelData
            width: updateRows.width
            height: 30

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: 7
              height: 7
              radius: 3.5
              color: Theme.sideUpdates
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 16
              anchors.right: updateDate.left
              anchors.rightMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              color: Theme.foreground
              elide: Text.ElideRight
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 13
              font.bold: true
            }

            Text {
              id: updateDate
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.date
              color: Theme.secondary
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 12
              font.bold: true
            }
          }
        }
      }
    }
  }

  Item {
    id: progressView
    anchors.fill: parent
    visible: root.progressMode

    Text {
      id: progressIcon
      anchors.left: parent.left
      anchors.leftMargin: 16
      y: 9
      width: 20
      height: 20
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: root.updateProcessing ? root.spinnerFrame
        : updates.phase === "error" ? ""
        : updates.phase === "success" ? "" : "󰆍"
      color: updates.phase === "error"
        ? Theme.error : Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true

    }

    Text {
      anchors.left: progressIcon.right
      anchors.leftMargin: 10
      anchors.right: progressStatus.left
      anchors.rightMargin: 12
      y: 8
      height: 22
      verticalAlignment: Text.AlignVCenter
      text: root.progressTitleText
      color: Theme.foreground
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      id: progressStatus
      anchors.right: parent.right
      anchors.rightMargin: 16
      y: 9
      height: 20
      verticalAlignment: Text.AlignVCenter
      text: root.phaseLabel
      color: updates.phase === "error"
        ? Theme.error : Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 11
      font.bold: true
    }
  }

  Item {
    id: changesView
    anchors.fill: parent
    visible: root.changesMode

    Text {
      id: changesIcon
      anchors.left: parent.left
      anchors.leftMargin: 16
      y: 9
      width: 20
      height: 20
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: updates.phase === "installing"
        ? root.spinnerFrame
        : updates.phase === "success" ? ""
        : updates.phase === "error" ? ""
        : ""
      color: updates.phase === "error"
        ? Theme.error : Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true

    }

    Text {
      anchors.left: changesIcon.right
      anchors.leftMargin: 10
      anchors.right: changesStatus.left
      anchors.rightMargin: 12
      y: 8
      height: 22
      verticalAlignment: Text.AlignVCenter
      text: root.changesTitle()
      color: Theme.foreground
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      id: changesStatus
      anchors.right: parent.right
      anchors.rightMargin: 16
      y: 9
      height: 20
      verticalAlignment: Text.AlignVCenter
      text: root.changesStatusText
      color: updates.phase === "error"
        ? Theme.error : Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 11
      font.bold: true
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      y: 40
      height: 1
      color: Theme.surfaceRaised
    }

    ListView {
      id: changeList
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 42
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 8
      anchors.leftMargin: 16
      anchors.rightMargin: 16
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: updates.changes
      highlightMoveDuration: 100

      delegate: Item {
        required property var modelData
        width: changeList.width
        height: 34

        Rectangle {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: 7
          height: 7
          radius: 3.5
          color: root.changeColor(modelData.kind)
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 16
          width: 168
          anchors.verticalCenter: parent.verticalCenter
          height: 22
          verticalAlignment: Text.AlignVCenter
          text: modelData.name
          color: Theme.foreground
          elide: Text.ElideRight
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 13
          font.bold: true
        }

        Text {
          id: versionsText
          anchors.left: parent.left
          anchors.leftMargin: 194
          anchors.right: kindText.left
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          height: 20
          verticalAlignment: Text.AlignVCenter
          text: root.versionText(modelData.oldVersions) + "  →  "
            + root.versionText(modelData.newVersions)
          color: Theme.secondary
          elide: Text.ElideMiddle
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 10
        }

        Text {
          id: kindText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: 18
          verticalAlignment: Text.AlignVCenter
          text: modelData.kind.toUpperCase()
          color: root.changeColor(modelData.kind)
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 10
          font.bold: true
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: Theme.surfaceRaised
          opacity: 0.55
        }
      }

      Text {
        visible: updates.changes.length === 0
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "No package version changes"
        color: Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 13
        font.bold: true
      }
    }

  }

  Item {
    id: completionView
    anchors.fill: parent
    visible: root.successMode || root.cleaningMode

    Text {
      id: completionIcon
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      width: 20
      height: 20
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: root.cleaningMode ? root.spinnerFrame : ""
      color: Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true

    }

    Text {
      anchors.left: completionIcon.right
      anchors.leftMargin: 10
      anchors.right: completionStatus.left
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      height: 22
      verticalAlignment: Text.AlignVCenter
      text: root.completionTitleText
      color: Theme.foreground
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      id: completionStatus
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      height: 20
      verticalAlignment: Text.AlignVCenter
      text: root.completionStatusText
      color: Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 11
      font.bold: true
    }
  }

  Item {
    id: authView
    anchors.fill: parent
    visible: root.authMode

    Text {
      id: authIcon
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      width: 20
      height: 20
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: "󰌾"
      color: Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 18
      font.bold: true
    }

    Text {
      id: authLabel
      anchors.left: authIcon.right
      anchors.leftMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      width: 138
      height: 22
      verticalAlignment: Text.AlignVCenter
      text: root.authLabelText
      color: auth.supplementaryIsError
        ? Theme.error : Theme.foreground
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 13
      font.bold: true
    }

    Rectangle {
      anchors.left: authLabel.right
      anchors.leftMargin: 10
      anchors.right: authSubmit.left
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      height: 26
      radius: 8
      color: Theme.surface
      border.width: 1
      border.color: Theme.sideUpdates

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: auth.input.length === 0 ? "Password…"
          : auth.responseVisible
            ? auth.input
            : "•".repeat(auth.input.length)
        color: auth.input.length === 0
          ? Theme.secondary : Theme.foreground
        elide: Text.ElideLeft
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 13
      }
    }

    Text {
      id: authSubmit
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      width: 42
      height: 20
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: "ENTER"
      color: Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 10
      font.bold: true
    }
  }
}
