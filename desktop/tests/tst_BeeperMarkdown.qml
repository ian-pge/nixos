import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var message: null
  property var opened: []
  Window { id: window; visible: true; width: 920; height: 900; color: "#181926"
    Rectangle { anchors.fill: parent; color: "#181926" }
  }
  TestResult { id: results }
  TestCase {
    name: "BeeperMarkdown"
    when: window.visible
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      if (message) { message.destroy(); message = null; wait(0); }
    }
    function cleanupTestCase() {
      console.log("BeeperMarkdown: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function show(source, html, props = {}) {
      if (message) { message.destroy(); message = null; wait(0); }
      fixture.opened = [];
      const c = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperMessage.qml");
      compare(c.status, Component.Ready, c.errorString());
      message = c.createObject(window.contentItem, {x: 10, y: 15, width: 900, networkAccent: "#8aadf4",
        message: Object.assign({id: "reply", chatID: "local:qwen", senderID: "assistant", senderName: "Qwen", text: source, plainText: source, markdownHTML: html}, props),
        linkOpener: url => fixture.opened = fixture.opened.concat([url])});
      verify(message !== null); wait(40);
    }
    function view() { return findChild(message, "beeperMarkdownBody"); }
    function rendered() { return view().textEdit.getText(0, view().textEdit.length); }
    function test_formats_and_copy_preserve_the_original_source() {
      const source = "# Bonjour\n\nDu **gras**, du *texte* et du `code`.\n\n- premier\n- second";
      show(source, "<h1>Bonjour</h1><p>Du <strong>gras</strong>, du <em>texte</em> et du <code>code</code>.</p><ul><li>premier</li><li>second</li></ul>");
      verify(message.markdownBody); verify(!findChild(message, "messageBody").visible);
      verify(rendered().includes("Bonjour")); verify(rendered().includes("gras"));
      verify(!rendered().includes("**")); compare(message.plainBody, source);
      const editor = view().textEdit;
      editor.select(0, 7); compare(message.selectedText, "Bonjour"); verify(!editor.activeFocus);
      message.clearTextSelection(); compare(message.selectedText, "");
    }
    function test_tables_code_and_links_stay_in_one_bubble() {
      show("# Exemple\nhttps://example.test", '<h2>Exemple</h2><p>Un <a href="https://example.test">lien</a> et <code>du code</code>.</p><pre><code>if (a &lt; 2) {\n  print("bonjour");\n}</code></pre><table><thead><tr><th>Modèle</th><th>Mémoire</th></tr></thead><tbody><tr><td>Qwen</td><td>4 Go</td></tr></tbody></table><blockquote><p>Une citation.</p></blockquote>');
      verify(!message.hasLinkCards); verify(rendered().includes("Qwen")); verify(rendered().includes("print"));
      const editor = view().textEdit;
      let linkPoint = null;
      for (let y = 2; y < editor.height && !linkPoint; y += 4)
        for (let x = 2; x < editor.width; x += 4)
          if (editor.linkAt(x, y) === "https://example.test") { linkPoint = {x: x, y: y}; break; }
      verify(linkPoint !== null);
      mouseClick(editor, linkPoint.x, linkPoint.y); compare(fixture.opened, ["https://example.test"]);
      view().activateLink("file:///etc/passwd"); view().activateLink("javascript:alert(1)"); compare(fixture.opened.length, 1);
      verify(message.height > 180); verify(message.height < 850);
      const path = Quickshell.env("QS_MARKDOWN_SCREENSHOT");
      if (path) grabImage(window.contentItem).save(path);
    }
    function test_streaming_preserves_selection_then_catches_up() {
      show("Bonjour", "<p>Bonjour</p>");
      const originalView = view(), editor = originalView.textEdit;
      editor.select(0, 7);
      message.message = Object.assign({}, message.message, {plainText: "Bonjour **tout le monde**", markdownHTML: "<p>Bonjour <strong>tout le monde</strong></p>"});
      wait(20); compare(view(), originalView); compare(message.selectedText, "Bonjour");
      verify(!rendered().includes("monde"));
      message.clearTextSelection(); wait(20); verify(rendered().includes("tout le monde"));
    }
    function test_search_zoom_and_hidden_measurement_keep_layout_sound() {
      show("Un résumé & du code", "<h2>Un résumé</h2><p>Un résumé &amp; du <code>code</code>.</p>");
      const before = message.height, width = findChild(message, "beeperMessageBubble").width;
      message.searchQuery = "resume code"; wait(30);
      compare(message.height, before); compare(findChild(message, "beeperMessageBubble").width, width);
      verify(view().textEdit.text.includes("background-color")); verify(rendered().includes("&"));
      message.renderMedia = false; message.visible = false; message.forceMessageLayout(); wait(20); compare(message.height, before);
      message.renderMedia = true; message.visible = true;
      message.textScale = 1.5; wait(30); verify(message.height > before);
    }
    function test_long_code_is_contained_and_remote_messages_stay_plain() {
      show("code", "<pre><code>" + "very_long_identifier_".repeat(30) + "</code></pre>");
      message.width = 360; wait(40);
      verify(view().width < 360); verify(view().height > 0);
      show("**literal**", "<strong>literal</strong>", {chatID: "remote"});
      verify(!message.markdownBody); compare(findChild(message, "messageBody").text, "**literal**");
    }
    function test_wide_table_has_horizontal_room_without_widening_the_bubble() {
      show("table", "<table><tr>" + "<td>Column</td>".repeat(20) + "</tr></table>");
      message.width = 360; wait(40);
      verify(view().width < 360);
      verify(view().overflowing);
      verify(view().height >= view().textEdit.implicitHeight + 10);
    }
  }
}
