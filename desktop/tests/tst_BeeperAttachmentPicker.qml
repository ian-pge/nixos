import QtQuick
import QtTest
import Quickshell

ShellRoot {
  Window { id: window; visible: true; width: 100; height: 100 }
  SignalSpy { id: finished; signalName: "finished" }
  TestResult { id: results }
  TestCase {
    name: "BeeperAttachmentPicker"
    when: window.visible
    function test_process_data() {
      return [
        {tag: "selected", command: ["printf", '{"paths":["/tmp/a file.txt"]}'], paths: ["/tmp/a file.txt"], error: false},
        {tag: "multiple", command: ["printf", '{"paths":["/tmp/one","/tmp/two"]}'], paths: ["/tmp/one", "/tmp/two"], error: false},
        {tag: "cancelled", command: ["printf", '{"paths":[]}'], paths: [], error: false},
        {tag: "failed", command: ["bash", "-c", "printf 'Picker failed' >&2; exit 1"], paths: [], error: true},
        {tag: "invalid", command: ["printf", "bad JSON"], paths: [], error: true},
        {tag: "invalid_path", command: ["printf", '{"paths":[7]}'], paths: [], error: true},
        {tag: "missing", command: ["/does-not-exist/beeper-test-picker"], paths: [], error: true}
      ];
    }
    function test_process(data) {
      const pickerComponent = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperAttachmentPicker.qml");
      compare(pickerComponent.status, Component.Ready, pickerComponent.errorString());
      const picker = createTemporaryObject(pickerComponent, window.contentItem, {command: data.command});
      verify(picker !== null); finished.target = picker; finished.clear();
      picker.open(); tryCompare(finished, "count", 1);
      compare(finished.signalArguments[0][0], data.paths);
      compare(!!finished.signalArguments[0][1], data.error);
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function cleanupTestCase() {
      console.log("BeeperAttachmentPicker: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
  }
}
