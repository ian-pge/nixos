import QtQuick
import Quickshell

Scope {
  id: root

  // Tests inject inert transports and disable the startup/periodic checker.
  property bool autoCheckEnabled: true
  property var operationProcess: operationCommand
  property var statusProcess: statusCommand
  property var updateCommand: ["quickshell-update-installer"]
  property var cleanCommand: ["quickshell-nix-cleaner"]
  property var checkCommand: ["quickshell-update-checker"]
  property var forceCheckCommand: ["quickshell-update-checker", "force"]

  property var updates: []
  property bool checking: false
  property bool checkFailed: false
  property bool rebootRequired: false
  property string icon: ""
  readonly property string displayedIcon: phase === "awaitingInstall" ? "󰌾"
    : phase === "error" ? "" : icon
  property string phase: "idle"
  property string message: ""
  property string operation: "update"
  property var changes: []
  property var counts: ({})
  property bool summaryReady: false
  property bool awaitingPolkit: false
  readonly property bool busy: phase === "updating" || phase === "building"
    || phase === "preparingAuth" || phase === "installing" || phase === "cleaning"

  property bool operationRunning: false
  property int operationGeneration: 0
  property bool statusRunning: false
  property int statusGeneration: 0
  property bool statusKnown: false
  property bool refreshPending: false
  signal presentationRequested()
  signal closeRequested()

  function resetSummary() {
    changes = [];
    counts = {};
    summaryReady = false;
  }

  function beginOperation(kind) {
    if (operationRunning || statusRunning || checking)
      return false;
    if (kind === "update" && (rebootRequired || updates.length === 0))
      return false;
    operation = kind;
    resetSummary();
    phase = kind === "clean" ? "cleaning" : "updating";
    message = kind === "clean" ? "Cleaning Nix generations and store"
      : "Starting NixOS update";
    awaitingPolkit = kind === "clean";
    operationRunning = true;
    const generation = ++operationGeneration;
    presentationRequested();
    operationProcess.exec(kind === "clean" ? cleanCommand : updateCommand, generation);
    return true;
  }

  function startUpdate() { return beginOperation("update"); }
  function startClean() { return beginOperation("clean"); }

  // This is the only place sending the helper's installation confirmation.
  // Receiving a diff, opening a panel or authenticating never calls it.
  function installUpdate() {
    if (!operationRunning || !operationProcess.running
        || operation !== "update" || phase !== "awaitingInstall")
      return;
    phase = "preparingAuth";
    message = "Preparing authentication";
    awaitingPolkit = true;
    operationProcess.write("install\n");
  }

  function handleEnter() {
    if (checking)
      return;
    if (phase === "idle") {
      if (updates.length > 0 && !rebootRequired) startUpdate();
      else closeRequested();
    } else if (phase === "awaitingInstall") {
      installUpdate();
    } else if (phase === "success" && !operationRunning) {
      phase = "idle";
      message = "";
      operation = "update";
      resetSummary();
      closeRequested();
    } else if (phase === "error" && !operationRunning) {
      if (operation === "clean") startClean();
      else startUpdate();
    }
  }

  function acceptOperationLine(line, generation) {
    if (!operationRunning || generation !== operationGeneration)
      return;
    if (phase === "success" || phase === "error")
      return;
    const marker = "@@QS_UPDATE@@";
    if (!line.startsWith(marker))
      return;
    try {
      const event = JSON.parse(line.slice(marker.length));
      const allowed = operation === "clean" ? ["cleaning", "success", "error"]
        : ["updating", "building", "awaitingInstall", "installing", "success", "error"];
      if (!event || (event.phase && !allowed.includes(event.phase)))
        return;
      phase = event.phase || phase;
      message = typeof event.message === "string" ? event.message : "";
      if (Array.isArray(event.changes)) {
        changes = event.changes;
        counts = event.counts || {};
        summaryReady = true;
      }
      if (phase === "success") {
        awaitingPolkit = false;
        if (operation === "update") rebootRequired = true;
        refreshPending = true;
      } else if (phase === "error") {
        awaitingPolkit = false;
      }
    } catch (error) {
      console.warn("Unable to parse update event:", error);
    }
  }

  function finishOperation(exitCode, exitStatus, output, generation) {
    if (!operationRunning || generation !== operationGeneration)
      return;
    operationRunning = false;
    if (phase !== "error" && (phase !== "success" || exitCode !== 0 || exitStatus !== 0)) {
      phase = "error";
      const label = operation === "clean" ? "cleanup" : "update";
      message = exitCode === 0 ? "The " + label + " stopped unexpectedly"
        : "The " + label + " process exited with code " + exitCode;
    }
    awaitingPolkit = false;
    if (refreshPending) {
      refreshPending = false;
      refreshStatus();
    }
  }

  function beginStatus(force) {
    if (statusRunning || operationRunning)
      return false;
    statusRunning = true;
    checking = force || !statusKnown;
    checkFailed = false;
    statusProcess.exec(force ? forceCheckCommand : checkCommand, ++statusGeneration);
    return true;
  }

  function refreshStatus() { return beginStatus(false); }
  function forceStatus() { return beginStatus(true); }

  function finishStatus(exitCode, exitStatus, output, generation) {
    if (!statusRunning || generation !== statusGeneration)
      return;
    statusRunning = false;
    statusKnown = true;
    try {
      if (exitCode !== 0 || exitStatus !== 0)
        throw new Error("Update checker exited unsuccessfully");
      const status = JSON.parse(output.trim());
      if (!status || !Array.isArray(status.updates))
        throw new Error("Invalid update status");
      checkFailed = status.state === "error";
      rebootRequired = status.state === "reboot-required";
      updates = status.updates;
      icon = checkFailed ? "" : rebootRequired ? "󰜉"
        : status.hasUpdates ? "" : "";
    } catch (error) {
      checkFailed = true;
      // A failed checker cannot disprove a successfully installed generation.
      icon = "";
      updates = [];
    }
    checking = false;
  }

  Component.onCompleted: { if (autoCheckEnabled) refreshStatus(); }

  UpdateCommand { id: operationCommand }
  UpdateCommand { id: statusCommand; captureOutput: true }
  Connections {
    target: root.operationProcess
    function onLineRead(line, generation) { root.acceptOperationLine(line, generation); }
    function onFinished(exitCode, exitStatus, output, generation) {
      root.finishOperation(exitCode, exitStatus, output, generation);
    }
  }
  Connections {
    target: root.statusProcess
    function onFinished(exitCode, exitStatus, output, generation) {
      root.finishStatus(exitCode, exitStatus, output, generation);
    }
  }
  Timer {
    interval: 1800000
    repeat: true
    running: root.autoCheckEnabled
    onTriggered: root.refreshStatus()
  }
}
