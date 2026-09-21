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

    function init() {
      sheet.pageIndex = 0;
      wait(0);
    }

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
      compare(w.color.a, 1);
      compare(w.opacity, 1);
      compare(w.border.color.a, 1);
      const labels = w.children.filter(child => child.visible && (child.text === "w" || child.text === "é"));
      compare(labels.length, 2);
      for (const label of labels) {
        compare(label.opacity, 1);
        compare(label.color.a, 1);
      }
      const help = keycap(sheet, "'");
      verify(help !== null);
      compare(help.color.a, 1);
      compare(help.border.color.a, 1);
      verify(!sheet.activeFocus);
    }

    function test_cycle_wraps_both_directions() {
      compare(sheet.page.name, "Clavier");
      sheet.cyclePage(1);
      compare(sheet.page.name, "Navigateur");
      sheet.cyclePage(1);
      compare(sheet.page.name, "Vim");
      sheet.cyclePage(1);
      compare(sheet.page.name, "Clavier");
      sheet.cyclePage(-1);
      compare(sheet.page.name, "Vim");
      verify(!sheet.activeFocus);
    }

    function test_browser_custom_bindings_and_vim_are_distinct() {
      sheet.pageIndex = 1;
      wait(0);
      compare(keycap(sheet, "J").shortcut.shifted, "Onglet →");
      compare(keycap(sheet, "K").shortcut.shifted, "Onglet ←");
      compare(keycap(sheet, "X").shortcut.plain, "Fermer");
      compare(keycap(sheet, "X").shortcut.shifted, "Rouvrir");
      compare(sheet.page.cards.length, 3);
      sheet.pageIndex = 2;
      wait(0);
      compare(keycap(sheet, "J").shortcut.plain, "Curseur ↓");
      compare(keycap(sheet, "J").shortcut.shifted, "Joindre");
      compare(keycap(sheet, "X").shortcut.plain, "Effacer car.");
      compare(sheet.page.cards[0].entries[2][0], ":wq → Entrée");
    }

    function test_pages_fit_panel_data() {
      return [{ tag: "layout", page: 0 }, { tag: "browser", page: 1 }, { tag: "vim", page: 2 }];
    }

    function test_pages_fit_panel(data) {
      sheet.pageIndex = data.page;
      wait(30);
      verify(sheet.implicitHeight > 500 && sheet.implicitHeight < 950);
      verify(!sheet.activeFocus);
      function check(item) {
        if (!item.visible) return;
        if (item.text !== undefined && item.text.length > 0) {
          const point = item.mapToItem(sheet, 0, 0);
          verify(point.x >= 0 && point.y >= 0, "Label inside top/left bounds: " + item.text);
          verify(point.x + item.width <= sheet.width + 1, "Label inside right bound: " + item.text);
          verify(point.y + item.height <= sheet.height + 1, "Label inside bottom bound: " + item.text);
          verify(!item.truncated, "Label not truncated: " + item.text);
          verify(item.contentWidth <= item.width + 1, "Label fits its own width: " + item.text);
        }
        for (const child of item.children || []) check(child);
      }
      check(sheet);
    }
  }
}
