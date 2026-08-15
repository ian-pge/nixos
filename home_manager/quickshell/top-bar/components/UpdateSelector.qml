import QtQuick
import "Theme.js" as Theme

FocusScope {
  id: root

  required property var statusData
  readonly property var updates: statusData.nixUpdates
  readonly property int rowCount: Math.max(1, updates.length)
  readonly property bool authMode: statusData.polkitActive
  readonly property bool successMode: !authMode
    && statusData.nixUpdatePhase === "success"
  readonly property bool cleaningMode: !authMode
    && statusData.nixUpdatePhase === "cleaning"
  readonly property bool listMode: !authMode
    && statusData.nixUpdatePhase === "idle"
  readonly property bool compactStatusMode: listMode
    && (statusData.nixChecking || updates.length === 0)
  readonly property bool changesMode: !authMode && !successMode
    && statusData.nixUpdateSummaryReady
  readonly property bool consoleMode: !authMode && !successMode && !cleaningMode
    && !listMode && !changesMode
  readonly property bool updateSpinning: statusData.nixUpdateBusy
  readonly property string phaseLabel: {
    if (statusData.nixUpdatePhase === "updating") return "UPDATING";
    if (statusData.nixUpdatePhase === "building") return "BUILDING";
    if (statusData.nixUpdatePhase === "awaitingActivation") return "READY";
    if (statusData.nixUpdatePhase === "preparingAuth") return "AUTH";
    if (statusData.nixUpdatePhase === "activating") return "ACTIVATING";
    if (statusData.nixUpdatePhase === "cleaning") return "CLEANING";
    if (statusData.nixUpdatePhase === "success") return "COMPLETE";
    if (statusData.nixUpdatePhase === "error") return "ERROR";
    return "UPDATE";
  }
  implicitWidth: compactStatusMode ? 280 : cleaningMode ? 360 : 480
  implicitHeight: authMode || successMode || cleaningMode ? 36
    : listMode ? (compactStatusMode ? 36 : 52 + rowCount * 30 + 10)
    : changesMode ? Math.min(750,
      50 + Math.max(1, statusData.nixUpdateChanges.length) * 34)
    : 750

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
    if (statusData.nixUpdatePhase === "success") return "Update complete";
    if (statusData.nixUpdatePhase === "activating") return "Activating system";
    if (statusData.nixUpdatePhase === "error") return "Activation failed";
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
        statusData.hideUpdateSelector();
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        statusData.submitPolkitResponse();
      } else if (event.key === Qt.Key_Backspace) {
        statusData.erasePolkitInput();
      } else if (event.key === Qt.Key_U
          && (event.modifiers & Qt.ControlModifier)) {
        statusData.polkitInput = "";
      } else if (event.text.length > 0
          && !(event.modifiers
            & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        statusData.appendPolkitInput(event.text);
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
      statusData.handleNixUpdateEnter();
      event.accepted = true;
    } else if (event.key === Qt.Key_C && root.listMode
        && !statusData.nixChecking) {
      statusData.startNixClean();
      event.accepted = true;
    } else if (event.key === Qt.Key_R && listMode) {
      statusData.forceNixStatus();
      event.accepted = true;
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
      statusData.hideUpdateSelector();
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
        visible: statusData.nixChecking
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "󰑐"
        color: Theme.sideUpdates
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 17
        font.bold: true

        RotationAnimator on rotation {
          running: statusData.nixChecking
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
        }
      }

      Text {
        anchors.fill: parent
        visible: !statusData.nixChecking
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: statusData.nixCheckFailed ? ""
          : updates.length > 0 ? "" : ""
        color: statusData.nixCheckFailed ? Theme.error : Theme.sideUpdates
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
      text: statusData.nixChecking ? "Checking for updates…"
        : statusData.nixCheckFailed ? "Update check failed" : "NixOS updates"
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
      text: statusData.nixChecking ? "CHECKING"
        : statusData.nixCheckFailed ? "ERROR"
        : updates.length > 0 ? updates.length + " AVAILABLE" : "UP TO DATE"
      color: statusData.nixCheckFailed ? Theme.error
        : statusData.nixChecking || updates.length > 0
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
          model: root.updates

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
    id: consoleView
    anchors.fill: parent
    visible: root.consoleMode

    Text {
      id: consoleIcon
      anchors.left: parent.left
      anchors.leftMargin: 16
      y: 9
      width: 20
      height: 20
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: root.updateSpinning ? "󰑐"
        : statusData.nixUpdatePhase === "error" ? ""
        : statusData.nixUpdatePhase === "success" ? "" : "󰆍"
      color: statusData.nixUpdatePhase === "error"
        ? Theme.error : Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true

      RotationAnimator on rotation {
        running: root.updateSpinning
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        onStopped: consoleIcon.rotation = 0
      }
    }

    Text {
      anchors.left: consoleIcon.right
      anchors.leftMargin: 10
      anchors.right: consoleStatus.left
      anchors.rightMargin: 12
      y: 8
      height: 22
      verticalAlignment: Text.AlignVCenter
      text: statusData.nixUpdateMessage || "NixOS update"
      color: Theme.foreground
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      id: consoleStatus
      anchors.right: parent.right
      anchors.rightMargin: 16
      y: 9
      height: 20
      verticalAlignment: Text.AlignVCenter
      text: root.phaseLabel
      color: statusData.nixUpdatePhase === "error"
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

    Flickable {
      id: consoleFlick
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 42
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 8
      clip: true
      contentWidth: width
      contentHeight: Math.max(height, consoleText.paintedHeight + 20)
      boundsBehavior: Flickable.StopAtBounds

      onContentHeightChanged: Qt.callLater(() => {
        contentY = Math.max(0, contentHeight - height);
      })

      Text {
        id: consoleText
        x: 16
        y: 10
        width: consoleFlick.width - 32
        text: statusData.nixUpdateLog
        color: Theme.foreground
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
      }
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
      text: statusData.nixUpdatePhase === "success" ? ""
        : statusData.nixUpdatePhase === "error" ? ""
        : statusData.nixUpdatePhase === "activating" ? "󰑐" : ""
      color: statusData.nixUpdatePhase === "error"
        ? Theme.error : Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true

      RotationAnimator on rotation {
        running: statusData.nixUpdatePhase === "activating"
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        onStopped: changesIcon.rotation = 0
      }
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
      text: statusData.nixUpdateChanges.length + " CHANGES"
      color: statusData.nixUpdatePhase === "error"
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
      model: statusData.nixUpdateChanges
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
        visible: statusData.nixUpdateChanges.length === 0
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
      text: root.cleaningMode ? "󰔟" : ""
      color: Theme.sideUpdates
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true

      RotationAnimator on rotation {
        running: root.cleaningMode
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        onStopped: completionIcon.rotation = 0
      }
    }

    Text {
      anchors.left: completionIcon.right
      anchors.leftMargin: 10
      anchors.right: completionStatus.left
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      height: 22
      verticalAlignment: Text.AlignVCenter
      text: root.cleaningMode || statusData.nixOperation === "clean"
        ? statusData.nixUpdateMessage : "Update complete"
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
      text: root.cleaningMode ? "CLEANING"
        : statusData.nixOperation === "clean" ? "CLEANED" : "COMPLETE"
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
      text: statusData.polkitSupplementaryMessage !== ""
        ? statusData.polkitSupplementaryMessage
        : statusData.polkitPrompt
      color: statusData.polkitSupplementaryIsError
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
        text: statusData.polkitInput.length === 0 ? "Password…"
          : statusData.polkitResponseVisible
            ? statusData.polkitInput
            : "•".repeat(statusData.polkitInput.length)
        color: statusData.polkitInput.length === 0
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
