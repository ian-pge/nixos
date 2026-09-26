import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var model: null
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../ui/KeyedListModel.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    model = component.createObject(fixture);
  }
  SignalSpy { id: resetSpy; target: fixture.model; signalName: "modelReset" }
  SignalSpy { id: changedSpy; target: fixture.model; signalName: "dataChanged" }
  TestResult { id: results }
  TestCase {
    name: "KeyedListModel"
    when: fixture.model !== null
    function init() { fixture.model.rows = []; resetSpy.clear(); changedSpy.clear(); }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function cleanupTestCase() {
      console.log("KeyedListModel: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_identical_snapshots_never_reset_or_reassign_rows() {
      const rows = [{id: "a", text: "Message", attachments: [{type: "audio", duration: 34}]}, {id: "b", text: "Next"}];
      fixture.model.rows = rows;
      changedSpy.clear(); fixture.model.rows = JSON.parse(JSON.stringify(rows));
      compare(fixture.model.count, 2); compare(resetSpy.count, 0); compare(changedSpy.count, 0);
      compare(fixture.model.get(0).row.attachments[0].duration, 34);
    }
    function test_insert_move_edit_delete_keep_order_without_reset() {
      fixture.model.rows = [{id: "a", text: "A"}, {id: "b", text: "B"}];
      fixture.model.rows = [{id: "c", text: "C"}, {id: "b", text: "Edited"}, {id: "a", text: "A"}];
      compare(fixture.model.count, 3); compare(fixture.model.get(0).row.id, "c");
      compare(fixture.model.get(1).row.text, "Edited"); compare(fixture.model.get(2).row.id, "a");
      fixture.model.rows = [{id: "a", text: "A"}];
      compare(fixture.model.count, 1); compare(fixture.model.get(0).row.id, "a"); compare(resetSpy.count, 0);
    }
  }
}
