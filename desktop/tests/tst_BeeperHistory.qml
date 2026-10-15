import QtQuick
import QtTest
import Quickshell

// Native history layout with deterministic bubble sizes and no accounts/media.
ShellRoot {
  id: fixture
  property var model: null
  property var history: null
  Window { id: window; width: 400; height: 240; visible: true }
  Component {
    id: bubble
    Item {
      id: item
      required property var row
      required property int index
      property real textScale: 1
      property bool viewportReady: false
      property bool inViewport: false
      property bool inVisibleViewport: false
      property int measurements: 0
      property real rowSize: 30
      onRowChanged: if (row) rowSize = row.size
      signal heightInvalidated(var changedItem)
      onHeightChanged: heightInvalidated(item)
      width: 400; height: rowSize * textScale
      function forceMessageLayout() { ++measurements; }
    }
  }
  TestResult { id: results }
  TestCase {
    name: "BeeperHistory"
    when: window.visible
    function create(path, parent, properties) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../" + path);
      compare(component.status, Component.Ready, component.errorString());
      const object = component.createObject(parent, properties); verify(object !== null); return object;
    }
    function init() {
      model = create("ui/KeyedListModel.qml", fixture, {});
      history = create("features/messenger/BeeperHistory.qml", window.contentItem,
        {width: 400, height: 240, model: model, delegate: bubble});
      model.rows = Array.from({length: 100}, (_, i) => ({id: "row-" + i, size: 30}));
      tryCompare(history, "loading", false); wait(20);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      model.rows = []; tryCompare(history, "createdCount", 0); wait(0);
      history.destroy(); model.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperHistory: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_edit_only_measures_the_changed_bubble_and_repositions_its_successors() {
      const items = Array.from({length: 100}, (_, i) => history.itemAtIndex(i));
      const measured = items.map(item => item.measurements);
      const previousY = items[71].y, previousHeight = history.contentHeight;
      model.rows = model.rows.map((row, i) => i === 70 ? Object.assign({}, row, {size: 45}) : row);
      tryCompare(history, "contentHeight", previousHeight + 15);
      for (let i = 0; i < 100; ++i) {
        compare(history.itemAtIndex(i), items[i]);
        if (i !== 70) compare(items[i].measurements, measured[i]);
      }
      verify(items[70].measurements > measured[70]); compare(items[71].y, previousY + 15);
    }
    function test_prepend_and_noop_refresh_do_not_remeasure_existing_bubbles() {
      const retained = history.itemAtIndex(50), measured = retained.measurements;
      model.rows = [{id: "older-a", size: 30}, {id: "older-b", size: 30}].concat(model.rows);
      tryCompare(history, "loading", false); wait(20);
      compare(history.itemAtIndex(52), retained); compare(retained.measurements, measured);
      model.rows = model.rows.slice(); wait(20);
      compare(retained.measurements, measured);
    }
    function test_zoom_prioritizes_visible_bubbles_and_preserves_the_reading_anchor() {
      history.positionViewAtIndex(50, ListView.Beginning); history.updateViewport();
      history.textScale = 1.4;
      compare(history.itemAtIndex(50).textScale, 1.4);
      compare(history.itemAtIndex(0).textScale, 1);
      verify(history.rescaling);
      tryCompare(history, "rescaling", false, 5000); wait(20);
      compare(history.indexAt(1, history.contentY + 12), 50);
      for (let i = 0; i < 100; ++i) compare(history.itemAtIndex(i).textScale, 1.4);
    }
    function test_zoom_keeps_the_latest_messages_at_the_bottom() {
      history.positionViewAtEnd(); history.updateViewport();
      history.textScale = 1.5;
      tryCompare(history, "rescaling", false, 5000); wait(20);
      verify(history.atYEnd);
    }
    function test_new_zoom_and_history_changes_replace_pending_work() {
      history.textScale = 1.5; wait(20); history.textScale = 1.2;
      model.rows = [{id: "older", size: 40}].concat(model.rows.slice(3));
      tryCompare(history, "loading", false); tryCompare(history, "rescaling", false, 5000);
      for (let i = 0; i < model.count; ++i) compare(history.itemAtIndex(i).textScale, 1.2);
      history.textScale = 1.8; model.rows = [];
      tryCompare(history, "rescaling", false); compare(history.count, 0);
    }
  }
}
