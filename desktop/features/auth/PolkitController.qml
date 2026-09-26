import QtQuick
import Quickshell
import Quickshell.Services.Polkit

// Generic authentication only: the shell decides where it is presented and
// what panel/monitor to restore. No knowledge of updates or their lifecycle.
Scope {
  id: root
  property bool serviceEnabled: true
  property var agent: nativeAgent.item
  readonly property var flow: agent && agent.isActive ? agent.flow : null
  readonly property bool active: flow !== null && flow !== undefined
  property string input: ""
  readonly property string message: active ? (flow.message || "Authentication required") : ""
  readonly property string prompt: active ? (flow.inputPrompt || "Password") : "Password"
  readonly property string supplementaryMessage: active ? (flow.supplementaryMessage || "") : ""
  readonly property bool supplementaryIsError: active && flow.supplementaryIsError
  readonly property bool responseVisible: active && flow.responseVisible
  readonly property bool responseRequired: active && flow.isResponseRequired
  property var requestFlow: null
  signal requestStarted()
  signal requestFinished()

  function clearInput() { input = ""; }
  function appendInput(text) { if (responseRequired) input += text; }
  function eraseInput() { input = input.slice(0, -1); }
  function submitResponse() {
    if (!responseRequired)
      return;
    const response = input;
    clearInput();
    flow.submit(response);
  }
  function cancelRequest() {
    clearInput();
    if (active)
      flow.cancelAuthenticationRequest();
  }

  function syncRequest() {
    const nextFlow = flow || null;
    if (requestFlow === nextFlow)
      return;
    clearInput();
    if (requestFlow !== null) {
      requestFlow = null;
      requestFinished();
    }
    // Inspect this flow directly: the derived active binding may still carry
    // its previous value while onFlowChanged is being dispatched.
    if (nextFlow !== null) {
      requestFlow = nextFlow;
      requestStarted();
    }
  }
  onFlowChanged: syncRequest()
  Component.onDestruction: clearInput()

  // Not instantiated at all by the isolated test fixture.
  Loader {
    id: nativeAgent
    active: root.serviceEnabled
    sourceComponent: Component { PolkitAgent {} }
  }
  Connections {
    target: root.agent
    function onAuthenticationRequestStarted() { root.syncRequest(); }
  }
  Connections {
    target: root.flow
    function onIsResponseRequiredChanged() { root.clearInput(); }
    function onAuthenticationFailed() { root.clearInput(); }
    function onAuthenticationRequestCancelled() { root.clearInput(); }
  }
}
