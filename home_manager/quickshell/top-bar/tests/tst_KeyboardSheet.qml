import QtQuick
import QtTest
import "../components"

Item {
  width: 1280
  height: 720
  KeyboardSheet { id: sheet }

  TestCase {
    name: "KeyboardSheet"
    when: windowShown

    function keycap(item, label) {
      if (item.modelData && item.modelData.label === label && item.radius === 10)
        return item;
      for (const child of item.children || []) {
        const result = keycap(child, label);
        if (result) return result;
      }
      return null;
    }

    function test_transparent_panel_readable_keys() {
      compare(sheet.color.a, 0);
      compare(sheet.border.width, 0);
      compare(sheet.opacity, 1);
      const w = keycap(sheet, "W");
      verify(w !== null);
      fuzzyCompare(w.color.a, 0.45, 0.01);
      compare(w.opacity, 1);
      verify(w.border.color.a > 0);
      const labels = w.children.filter(child => child.text === "w" || child.text === "é");
      compare(labels.length, 2);
      for (const label of labels) {
        compare(label.opacity, 1);
        compare(label.color.a, 1);
      }
      verify(!sheet.activeFocus);
    }
  }
}
