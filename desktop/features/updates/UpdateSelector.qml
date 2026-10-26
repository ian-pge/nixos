import QtQuick
import "../../ui"
import "../../ui/Layout.js" as Layout
import "../../ui/Theme.js" as Theme

FocusScope {
  id: root
  objectName: "updateSelector"

  required property var updates
  required property var auth
  property string spinnerFrame: "loader-circle"
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
  // Once Nix starts realising, the build expands into the full progress view.
  readonly property bool buildMode: progressMode && updates.phase === "building"
    && !!updates.progress
  readonly property bool singleLine: !buildMode && (authMode || successMode
    || cleaningMode || progressMode || (listMode ? compactStatusMode : !changesMode))
  function uiSize(value) { return singleLine ? Theme.barSize(value) : value; }
  readonly property bool updateProcessing: updates.busy
  readonly property bool cancelHint: updates.cancelPending && updates.cancellable
  readonly property string cancelHintText: "PRESS Q AGAIN"
  readonly property string phaseLabel: {
    if (cancelHint) return cancelHintText;
    if (updates.phase === "cancelling") return "CANCELLING";
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
  readonly property string changesStatusText: cancelHint ? cancelHintText
    : updates.changes.length + " CHANGES"
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
  implicitHeight: buildMode ? buildView.implicitHeight
    : authMode || successMode || cleaningMode || progressMode ? uiSize(36)
    : listMode ? (compactStatusMode ? uiSize(36) : 52 + rowCount * 30 + 10)
    : changesMode ? Math.min(750,
      50 + Math.max(1, updates.changes.length) * 34)
    : uiSize(36)

  FontMetrics {
    id: titleMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: root.uiSize(14)
    font.bold: true
  }

  FontMetrics {
    id: rowTitleMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: root.uiSize(13)
    font.bold: true
  }

  FontMetrics {
    id: dateMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: root.uiSize(12)
    font.bold: true
  }

  FontMetrics {
    id: statusMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: root.uiSize(11)
    font.bold: true
  }

  FontMetrics {
    id: kindMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: root.uiSize(10)
    font.bold: true
  }

  FontMetrics {
    id: versionMetrics
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: root.uiSize(10)
  }

  function headerWidth(title, status) {
    return uiSize(16) + uiSize(20) + uiSize(10) + titleMetrics.advanceWidth(title) + uiSize(12)
      + statusMetrics.advanceWidth(status) + uiSize(16);
  }

  function listContentWidth() {
    let width = headerWidth(listTitleText, listStatusText);
    for (let index = 0; index < availableUpdates.length; ++index) {
      const update = availableUpdates[index];
      width = Math.max(width, uiSize(64)
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
      width = Math.max(width, uiSize(80)
        + rowTitleMetrics.advanceWidth(change.name || "")
        + versionMetrics.advanceWidth(versions)
        + kindMetrics.advanceWidth((change.kind || "").toUpperCase()));
    }
    return width;
  }

  function adaptiveWidth() {
    if (buildMode)
      return 480;
    if (authMode) {
      const authContentWidth = uiSize(16) + uiSize(20) + uiSize(10)
        + rowTitleMetrics.advanceWidth(authLabelText) + uiSize(10) + uiSize(120)
        + uiSize(10) + uiSize(42) + uiSize(16);
      return Layout.boundedWidth(authContentWidth, uiSize(400), uiSize(480));
    }
    if (cleaningMode) {
      return Layout.boundedWidth(
        headerWidth(completionTitleText, completionStatusText), uiSize(280), uiSize(360));
    }
    if (successMode) {
      return Layout.boundedWidth(
        headerWidth(completionTitleText, completionStatusText), uiSize(240), uiSize(480));
    }
    if (listMode) {
      return Layout.boundedWidth(listContentWidth(),
        uiSize(compactStatusMode ? 220 : 280), uiSize(compactStatusMode ? 280 : 480));
    }
    if (changesMode)
      return Layout.boundedWidth(changesContentWidth(), uiSize(320), uiSize(480));
    if (progressMode) {
      return Layout.boundedWidth(
        headerWidth(progressTitleText, phaseLabel), uiSize(240), uiSize(480));
    }
    return uiSize(280);
  }

  function changeColor(kind) {
    if (kind === "added") return Theme.sideGpu;
    if (kind === "removed") return Theme.error;
    if (kind === "downgraded") return Theme.sideDisk;
    if (kind === "changed") return Theme.yellow;
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
    } else if (event.key === Qt.Key_Q && updates.cancellable) {
      // Before installation, q cancels and restores flake.lock (pressed twice).
      updates.requestCancel();
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
      anchors.leftMargin: root.uiSize(16)
      y: root.singleLine ? (parent.height - height) / 2 : 9
      width: root.uiSize(20)
      height: root.uiSize(20)

      Icon {
        id: checkingIcon
        anchors.fill: parent
        visible: updates.checking
        name: root.spinnerFrame; spinning: true
        color: Theme.sideUpdates
        size: root.uiSize(17)
      }

      Icon {

        size: root.uiSize(17)
        anchors.fill: parent
        visible: !updates.checking

        name: updates.checkFailed ? "triangle-alert"
          : updates.rebootRequired ? "refresh-cw"
          : availableUpdates.length > 0 ? "download" : "package"
        color: updates.checkFailed ? Theme.error : Theme.sideUpdates

      }
    }

    Text {
      anchors.left: updateIcon.right
      anchors.leftMargin: root.uiSize(10)
      objectName: "updatesTitle"
      anchors.right: root.singleLine ? listStatus.left : undefined
      anchors.rightMargin: root.uiSize(12)
      elide: Text.ElideRight
      y: root.singleLine ? (parent.height - height) / 2 : 8
      height: root.uiSize(22)
      verticalAlignment: Text.AlignVCenter
      text: root.listTitleText
      color: Theme.foreground
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(14)
      font.bold: true
    }

    Text {
      id: listStatus
      objectName: "updatesStatus"
      anchors.right: parent.right
      anchors.rightMargin: root.uiSize(16)
      y: root.singleLine ? (parent.height - height) / 2 : 9
      height: root.uiSize(20)
      verticalAlignment: Text.AlignVCenter
      text: root.listStatusText
      color: updates.checkFailed ? Theme.error
        : updates.checking || availableUpdates.length > 0
          ? Theme.sideUpdates : Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(11)
      font.bold: true
    }

    Rectangle {
      visible: !root.compactStatusMode
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.uiSize(14)
      anchors.rightMargin: root.uiSize(14)
      y: root.uiSize(40)
      height: root.uiSize(1)
      color: Theme.surfaceRaised
    }

    Item {
      id: updateViewport
      visible: !root.compactStatusMode
      anchors.left: parent.left
      anchors.right: parent.right
      y: root.uiSize(42)
      height: Math.max(0, root.height - y)
      clip: true

      Column {
        id: updateRows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.uiSize(16)
        anchors.rightMargin: root.uiSize(16)
        y: root.uiSize(6)
        spacing: 0

        Repeater {
          model: root.availableUpdates

          Item {
            required property var modelData
            width: updateRows.width
            height: root.uiSize(30)

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: root.uiSize(7)
              height: root.uiSize(7)
              radius: root.uiSize(3.5)
              color: Theme.sideUpdates
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: root.uiSize(16)
              anchors.right: updateDate.left
              anchors.rightMargin: root.uiSize(16)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              color: Theme.foreground
              elide: Text.ElideRight
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: root.uiSize(13)
              font.bold: true
            }

            Text {
              id: updateDate
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.date
              color: Theme.secondary
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: root.uiSize(12)
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
    visible: root.progressMode && !root.buildMode

    Icon {

      size: root.uiSize(17)
      id: progressIcon
      spinning: root.updateProcessing
      anchors.left: parent.left
      anchors.leftMargin: root.uiSize(16)
      y: root.singleLine ? (parent.height - height) / 2 : 9
      width: root.uiSize(20)
      height: root.uiSize(20)

      name: root.updateProcessing ? root.spinnerFrame
        : updates.phase === "error" ? "triangle-alert"
        : updates.phase === "success" ? "circle-check" : "terminal"
      color: updates.phase === "error"
        ? Theme.error : Theme.sideUpdates

    }

    Text {
      anchors.left: progressIcon.right
      anchors.leftMargin: root.uiSize(10)
      anchors.right: progressStatus.left
      anchors.rightMargin: root.uiSize(12)
      y: root.singleLine ? (parent.height - height) / 2 : 8
      height: root.uiSize(22)
      verticalAlignment: Text.AlignVCenter
      text: root.progressTitleText
      color: Theme.foreground
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(14)
      font.bold: true
    }

    Text {
      id: progressStatus
      anchors.right: parent.right
      anchors.rightMargin: root.uiSize(16)
      y: root.singleLine ? (parent.height - height) / 2 : 9
      height: root.uiSize(20)
      verticalAlignment: Text.AlignVCenter
      text: root.phaseLabel
      color: updates.phase === "error"
        ? Theme.error : Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(11)
      font.bold: true
    }
  }

  UpdateBuildProgress {
    id: buildView
    anchors.fill: parent
    visible: root.buildMode
    progress: updates.progress
    title: root.progressTitleText
    status: root.cancelHint ? root.cancelHintText : ""
    spinnerFrame: root.spinnerFrame
  }

  Item {
    id: changesView
    anchors.fill: parent
    visible: root.changesMode

    Icon {

      size: root.uiSize(17)
      id: changesIcon
      spinning: updates.phase === "installing"
      anchors.left: parent.left
      anchors.leftMargin: root.uiSize(16)
      y: root.singleLine ? (parent.height - height) / 2 : 9
      width: root.uiSize(20)
      height: root.uiSize(20)

      name: updates.phase === "installing"
        ? root.spinnerFrame
        : updates.phase === "success" ? "circle-check"
        : updates.phase === "error" ? "triangle-alert"
        : "download"
      color: updates.phase === "error"
        ? Theme.error : Theme.sideUpdates

    }

    Text {
      anchors.left: changesIcon.right
      anchors.leftMargin: root.uiSize(10)
      anchors.right: changesStatus.left
      anchors.rightMargin: root.uiSize(12)
      y: root.singleLine ? (parent.height - height) / 2 : 8
      height: root.uiSize(22)
      verticalAlignment: Text.AlignVCenter
      text: root.changesTitle()
      color: Theme.foreground
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(14)
      font.bold: true
    }

    Text {
      id: changesStatus
      anchors.right: parent.right
      anchors.rightMargin: root.uiSize(16)
      y: root.singleLine ? (parent.height - height) / 2 : 9
      height: root.uiSize(20)
      verticalAlignment: Text.AlignVCenter
      text: root.changesStatusText
      color: updates.phase === "error"
        ? Theme.error : Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(11)
      font.bold: true
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.uiSize(14)
      anchors.rightMargin: root.uiSize(14)
      y: root.uiSize(40)
      height: root.uiSize(1)
      color: Theme.surfaceRaised
    }

    ListView {
      id: changeList
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: root.uiSize(42)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.uiSize(8)
      anchors.leftMargin: root.uiSize(16)
      anchors.rightMargin: root.uiSize(16)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: updates.changes
      highlightMoveDuration: 100

      delegate: Item {
        required property var modelData
        width: changeList.width
        height: root.uiSize(34)

        Rectangle {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: root.uiSize(7)
          height: root.uiSize(7)
          radius: root.uiSize(3.5)
          color: root.changeColor(modelData.kind)
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: root.uiSize(16)
          width: root.uiSize(168)
          anchors.verticalCenter: parent.verticalCenter
          height: root.uiSize(22)
          verticalAlignment: Text.AlignVCenter
          text: modelData.name
          color: Theme.foreground
          elide: Text.ElideRight
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: root.uiSize(13)
          font.bold: true
        }

        Text {
          id: versionsText
          anchors.left: parent.left
          anchors.leftMargin: root.uiSize(194)
          anchors.right: kindText.left
          anchors.rightMargin: root.uiSize(10)
          anchors.verticalCenter: parent.verticalCenter
          height: root.uiSize(20)
          verticalAlignment: Text.AlignVCenter
          text: root.versionText(modelData.oldVersions) + "  →  "
            + root.versionText(modelData.newVersions)
          color: Theme.secondary
          elide: Text.ElideMiddle
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: root.uiSize(10)
        }

        Text {
          id: kindText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: root.uiSize(18)
          verticalAlignment: Text.AlignVCenter
          text: modelData.kind.toUpperCase()
          color: root.changeColor(modelData.kind)
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: root.uiSize(10)
          font.bold: true
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.uiSize(1)
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
        font.pixelSize: root.uiSize(13)
        font.bold: true
      }
    }

  }

  Item {
    id: completionView
    anchors.fill: parent
    visible: root.successMode || root.cleaningMode

    Icon {

      size: root.uiSize(17)
      id: completionIcon
      spinning: root.cleaningMode
      anchors.left: parent.left
      anchors.leftMargin: root.uiSize(16)
      anchors.verticalCenter: parent.verticalCenter
      width: root.uiSize(20)
      height: root.uiSize(20)

      name: root.cleaningMode ? root.spinnerFrame : "circle-check"
      color: Theme.sideUpdates

    }

    Text {
      anchors.left: completionIcon.right
      anchors.leftMargin: root.uiSize(10)
      anchors.right: completionStatus.left
      anchors.rightMargin: root.uiSize(12)
      anchors.verticalCenter: parent.verticalCenter
      height: root.uiSize(22)
      verticalAlignment: Text.AlignVCenter
      text: root.completionTitleText
      color: Theme.foreground
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(14)
      font.bold: true
    }

    Text {
      id: completionStatus
      anchors.right: parent.right
      anchors.rightMargin: root.uiSize(16)
      anchors.verticalCenter: parent.verticalCenter
      height: root.uiSize(20)
      verticalAlignment: Text.AlignVCenter
      text: root.completionStatusText
      color: Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(11)
      font.bold: true
    }
  }

  Item {
    id: authView
    anchors.fill: parent
    visible: root.authMode

    Icon {

      size: root.uiSize(18)
      id: authIcon
      anchors.left: parent.left
      anchors.leftMargin: root.uiSize(16)
      anchors.verticalCenter: parent.verticalCenter
      width: root.uiSize(20)
      height: root.uiSize(20)

      name: "lock-keyhole"
      color: Theme.sideUpdates

    }

    Text {
      id: authLabel
      anchors.left: authIcon.right
      anchors.leftMargin: root.uiSize(10)
      anchors.verticalCenter: parent.verticalCenter
      width: root.uiSize(138)
      height: root.uiSize(22)
      verticalAlignment: Text.AlignVCenter
      text: root.authLabelText
      color: auth.supplementaryIsError
        ? Theme.error : Theme.foreground
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(13)
      font.bold: true
    }

    Rectangle {
      anchors.left: authLabel.right
      anchors.leftMargin: root.uiSize(10)
      anchors.right: authSubmit.left
      anchors.rightMargin: root.uiSize(10)
      anchors.verticalCenter: parent.verticalCenter
      height: root.uiSize(26)
      radius: root.uiSize(8)
      color: Theme.surface
      border.width: root.uiSize(1)
      border.color: Theme.sideUpdates

      Text {
        anchors.left: parent.left
        anchors.leftMargin: root.uiSize(10)
        anchors.right: parent.right
        anchors.rightMargin: root.uiSize(10)
        anchors.verticalCenter: parent.verticalCenter
        text: auth.input.length === 0 ? "Password…"
          : auth.responseVisible
            ? auth.input
            : "•".repeat(auth.input.length)
        color: auth.input.length === 0
          ? Theme.secondary : Theme.foreground
        elide: Text.ElideLeft
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: root.uiSize(13)
      }
    }

    Text {
      id: authSubmit
      anchors.right: parent.right
      anchors.rightMargin: root.uiSize(16)
      anchors.verticalCenter: parent.verticalCenter
      width: root.uiSize(42)
      height: root.uiSize(20)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: "ENTER"
      color: Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(10)
      font.bold: true
    }
  }
}
