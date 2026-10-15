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
  SignalSpy { id: movedSpy; target: fixture.model; signalName: "rowsMoved" }
  SignalSpy { id: removedSpy; target: fixture.model; signalName: "rowsRemoved" }
  SignalSpy { id: insertedSpy; target: fixture.model; signalName: "rowsInserted" }
  SignalSpy { id: updatedSpy; target: fixture.model; signalName: "updated" }
  TestResult { id: results }
  TestCase {
    name: "KeyedListModel"
    when: fixture.model !== null
    function init() { fixture.model.rows = []; fixture.model.immutableRows = false; fixture.model.bulkThreshold = 0; resetSpy.clear(); changedSpy.clear(); }
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
    function rows(count) { return Array.from({length: count}, (_, i) => ({id: "row-" + i, text: "Row " + i})); }
    function verifyRows(expected, allowReset = false) {
      compare(fixture.model.count, expected.length);
      for (let i = 0; i < expected.length; ++i) {
        compare(JSON.parse(JSON.stringify(fixture.model.get(i).row)), expected[i]);
        compare(fixture.model.keys[i], JSON.stringify([expected[i].chatID || "", expected[i].id]));
        compare(fixture.model.snapshots[i], JSON.stringify(expected[i]));
      }
      if (!allowReset) compare(resetSpy.count, 0);
    }
    function test_remove_a_run_without_moving_survivors_data() {
      return [{tag: "first", from: 0, count: 1}, {tag: "middle", from: 500, count: 1},
        {tag: "several", from: 20, count: 35}, {tag: "last", from: 999, count: 1},
        {tag: "all", from: 0, count: 1000}];
    }
    function test_remove_a_run_without_moving_survivors(data) {
      const before = rows(1000); fixture.model.rows = before;
      movedSpy.clear(); removedSpy.clear(); changedSpy.clear();
      const after = before.slice(0, data.from).concat(before.slice(data.from + data.count));
      fixture.model.rows = after;
      compare(movedSpy.count, 0); compare(removedSpy.count, 1); compare(changedSpy.count, 0);
      verifyRows(after);
    }
    function test_rotate_a_section_with_one_native_move_data() {
      return [{tag: "first-to-last", offset: 1}, {tag: "last-to-first", offset: 999},
        {tag: "whole-section", offset: 350}];
    }
    function test_rotate_a_section_with_one_native_move(data) {
      const before = rows(1000); fixture.model.rows = before;
      movedSpy.clear(); removedSpy.clear(); changedSpy.clear();
      const after = before.slice(data.offset).concat(before.slice(0, data.offset));
      fixture.model.rows = after;
      compare(movedSpy.count, 1); compare(removedSpy.count, 0); compare(changedSpy.count, 0);
      verifyRows(after);
    }
    function test_mixed_edits_reorders_and_inserts_preserve_the_correct_snapshots() {
      const before = rows(12); fixture.model.rows = before;
      const after = [before[8], before[9], {id: "new", text: "New"}, before[3], before[4],
        Object.assign({}, before[1], {text: "Changed"}), before[11], before[0]];
      fixture.model.rows = after; verifyRows(after);
      fixture.model.rows = before; verifyRows(before);
      fixture.model.rows = before.slice().reverse(); verifyRows(before.slice().reverse());
    }
    function test_same_message_id_in_different_chats_stays_distinct() {
      const before = [{chatID: "a", id: "same", text: "A"}, {chatID: "b", id: "same", text: "B"}];
      fixture.model.rows = before;
      fixture.model.rows = before.slice().reverse(); verifyRows(before.slice().reverse());
      fixture.model.rows = [before[1]]; verifyRows([before[1]]);
    }
    function test_immutable_rows_keep_cached_snapshots_aligned_after_reordering() {
      fixture.model.immutableRows = true;
      const before = rows(20); fixture.model.rows = before;
      const changed = Object.assign({}, before[0], {text: "Changed"});
      const after = before.slice(1).concat([changed]);
      changedSpy.clear(); fixture.model.rows = after;
      compare(changedSpy.count, 1); verifyRows(after);
      fixture.model.rows = after.slice(2); verifyRows(after.slice(2));
      fixture.model.rows = after; verifyRows(after);
    }
    function test_mutable_rows_still_detect_in_place_nested_edits() {
      const rows = [{id: "a", attachment: {name: "Before"}}];
      fixture.model.rows = rows;
      rows[0].attachment.name = "After";
      fixture.model.rows = rows.slice();
      verifyRows(rows); compare(fixture.model.get(0).row.attachment.name, "After");
    }
    function test_initial_page_and_prepend_use_one_insertion_per_batch() {
      insertedSpy.clear(); fixture.model.rows = rows(1000);
      compare(insertedSpy.count, 1);
      insertedSpy.clear(); const before = fixture.model.rows;
      const after = [{id: "older-a"}, {id: "older-b"}].concat(before);
      fixture.model.rows = after; compare(insertedSpy.count, 1); verifyRows(after);
    }
    function test_bulk_opt_in_bounds_global_sort_and_filter_operations() {
      const before = rows(2000); fixture.model.rows = before; fixture.model.bulkThreshold = 32;
      movedSpy.clear(); removedSpy.clear(); insertedSpy.clear();
      const sorted = before.filter((_, i) => i % 2).concat(before.filter((_, i) => !(i % 2)));
      fixture.model.rows = sorted;
      compare(movedSpy.count, 0); compare(insertedSpy.count, 0); verifyRows(sorted);
      fixture.model.rows = before; movedSpy.clear(); removedSpy.clear(); insertedSpy.clear();
      const filtered = before.filter((_, i) => i % 2);
      fixture.model.rows = filtered;
      compare(movedSpy.count, 0); compare(insertedSpy.count, 0);
      compare(removedSpy.count, 1); verifyRows(filtered);
    }
    function test_layout_metadata_only_identifies_changed_rows() {
      const before = rows(20); fixture.model.rows = before; updatedSpy.clear();
      fixture.model.rows = before.map((row, i) => i === 12 ? Object.assign({}, row, {text: "Edited"}) : row);
      compare(updatedSpy.count, 1);
      compare(updatedSpy.signalArguments[0][0], false);
      compare(updatedSpy.signalArguments[0][1], [12]); compare(updatedSpy.signalArguments[0][2], 12);
      updatedSpy.clear(); fixture.model.rows = fixture.model.rows.slice();
      compare(updatedSpy.signalArguments[0][1], []);
    }
  }
}
