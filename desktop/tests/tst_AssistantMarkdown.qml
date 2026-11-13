import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var message: null
  property var opened: []
  property var mathRenderer: null
  Window { id: window; visible: true; width: 920; height: 900; color: "#181926"
    Rectangle { anchors.fill: parent; color: "#181926" }
  }
  TestResult { id: results }
  TestCase {
    name: "AssistantMarkdown"
    when: window.visible
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      if (message) { message.destroy(); message = null; wait(0); }
      if (mathRenderer) { mathRenderer.destroy(); mathRenderer = null; wait(0); }
    }
    function cleanupTestCase() {
      console.log("AssistantMarkdown: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function show(source, html, props = {}) {
      if (message) { message.destroy(); message = null; wait(0); }
      fixture.opened = [];
      if (!mathRenderer) {
        const mathComponent = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/assistant/AssistantMath.qml");
        compare(mathComponent.status, Component.Ready, mathComponent.errorString());
        mathRenderer = mathComponent.createObject(fixture);
      }
      const c = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/assistant/AssistantMessage.qml");
      compare(c.status, Component.Ready, c.errorString());
      message = c.createObject(window.contentItem, {x: 10, y: 15, width: 900, baseSize: 20,
        mathRenderer: fixture.mathRenderer,
        message: Object.assign({id: "reply", role: "assistant", isSender: false, state: "complete", text: source, html: html}, props)});
      verify(message !== null);
      message.openRequested.connect(url => fixture.opened = fixture.opened.concat([url]));
      wait(40);
    }
    function view() { return findChild(message, "assistantMessageBody"); }
    function rendered() { return view().textEdit.getText(0, view().textEdit.length); }
    function test_formats_and_copy_preserve_the_original_source() {
      const source = "# Bonjour\n\nDu **gras**, du *texte* et du `code`.\n\n- premier\n- second";
      show(source, "<h1>Bonjour</h1><p>Du <strong>gras</strong>, du <em>texte</em> et du <code>code</code>.</p><ul><li>premier</li><li>second</li></ul>");
      verify(rendered().includes("Bonjour")); verify(rendered().includes("gras"));
      verify(!rendered().includes("**")); compare(message.message.text, source);
      const editor = view().textEdit;
      editor.select(0, 7); compare(message.selectedText, "Bonjour"); verify(!editor.activeFocus);
      message.clearTextSelection(); compare(message.selectedText, "");
    }
    function test_tables_code_and_links_stay_in_one_bubble() {
      show("# Exemple\nhttps://example.test", '<h2>Exemple</h2><p>Un <a href="https://example.test">lien</a> et <code>du code</code>.</p><pre><code>if (a &lt; 2) {\n  print("bonjour");\n}</code></pre><table><thead><tr><th>Modèle</th><th>Mémoire</th></tr></thead><tbody><tr><td>Qwen</td><td>4 Go</td></tr></tbody></table><blockquote><p>Une citation.</p></blockquote>');
      verify(rendered().includes("Qwen")); verify(rendered().includes("print"));
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
      message.message = Object.assign({}, message.message, {text: "Bonjour **tout le monde**", html: "<p>Bonjour <strong>tout le monde</strong></p>"});
      wait(20); compare(view(), originalView); compare(message.selectedText, "Bonjour");
      verify(!rendered().includes("monde"));
      message.clearTextSelection(); wait(20); verify(rendered().includes("tout le monde"));
    }
    function test_search_zoom_and_hidden_measurement_keep_layout_sound() {
      show("Un résumé & du code", "<h2>Un résumé</h2><p>Un résumé &amp; du <code>code</code>.</p>");
      const before = message.height, width = findChild(message, "assistantBubble").width;
      message.searchQuery = "resume code"; wait(30);
      compare(message.height, before); compare(findChild(message, "assistantBubble").width, width);
      verify(view().textEdit.text.includes("background-color")); verify(rendered().includes("&"));
      message.visible = false; wait(20); compare(message.height, before);
      message.visible = true;
      message.textScale = 1.5; wait(30); verify(message.height > before);
    }
    function test_long_code_is_contained_and_user_text_stays_literal() {
      show("code", "<pre><code>" + "very_long_identifier_".repeat(30) + "</code></pre>");
      message.width = 360; wait(40);
      verify(view().width < 360); verify(view().height > 0);
      show("**literal** <b>", "<p style=\"white-space:pre-wrap\">**literal** &lt;b&gt;</p>", {role: "user", isSender: true});
      verify(rendered().includes("**literal** <b>"));
    }
    function test_wide_table_has_horizontal_room_without_widening_the_bubble() {
      show("table", "<table><tr>" + "<td>Column</td>".repeat(20) + "</tr></table>");
      message.width = 360; wait(40);
      verify(view().width < 360);
      verify(view().overflowing);
      verify(view().height >= view().textEdit.implicitHeight + 10);
    }
    function math(tex, display = true) {
      const utf8 = encodeURIComponent(tex).replace(/%([0-9A-F]{2})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
      const bytes = new Uint8Array(Array.from(utf8, c => c.charCodeAt(0)));
      const encoded = Array.from(new Uint8Array(Qt.btoa(bytes.buffer)), byte => String.fromCharCode(byte)).join("");
      return '<span data-math="' + encoded + '" data-display="' + (display ? '1' : '0') + '">'
        + (display ? '$$' : '$') + tex + (display ? '$$' : '$') + '</span>';
    }
    function test_math_svg_copy_zoom_and_streaming() {
      const square = '(A-B)^2=A^2-2AB+B^2', fraction = '\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}';
      const html = '<h2>2. Le carré d’une différence</h2><p>' + math(square) + '</p><p><strong>À retenir :</strong> un signe moins au milieu.</p><p>Les racines : ' + math(fraction) + '</p>';
      show('$$' + square + '$$', html);
      tryVerify(() => (view().renderedHTML.match(/data:image\/svg\+xml/g) || []).length === 2, 10000);
      verify(!rendered().includes('$$')); verify(!rendered().includes('\\frac'));
      view().textEdit.selectAll();
      verify(message.selectedText.includes('$$' + square + '$$'));
      verify(message.selectedText.includes('$$' + fraction + '$$'));
      message.clearTextSelection();
      const before = view().height;
      message.textScale = 1.5;
      tryVerify(() => view().height > before);
      message.textScale = 1; wait(30);
      const screenshot = Quickshell.env("QS_MATH_SCREENSHOT");
      if (screenshot) grabImage(window.contentItem).save(screenshot);
      view().textEdit.select(0, 5);
      const frozen = view().renderedHTML;
      message.message = Object.assign({}, message.message, {html: html + '<p>' + math('x_i^2', false) + '</p>'});
      wait(30); compare(view().renderedHTML, frozen);
      message.clearTextSelection();
      tryVerify(() => (view().renderedHTML.match(/data:image\/svg\+xml/g) || []).length === 3, 10000);
    }
    function test_invalid_math_keeps_a_readable_fallback() {
      show('invalid', '<p>' + math('\\unknowncommand{x}') + '</p>');
      tryVerify(() => mathRenderer.revision > 0, 10000);
      verify(rendered().includes('\\unknowncommand'));
      verify(!view().renderedHTML.includes('<img'));
    }
    function test_selected_math_after_another_expression_keeps_unicode() {
      const tex = '\\text{énergie}=mc^2';
      show('unicode', '<p>' + math('x^2') + '</p><p>Ensuite ' + math(tex, false) + '</p>');
      tryVerify(() => (view().renderedHTML.match(/data:image\/svg\+xml/g) || []).length === 2, 10000);
      const text = rendered(), index = text.lastIndexOf('\ufffc');
      verify(index >= 0);
      view().textEdit.select(index, index + 1);
      compare(message.selectedText, '$' + tex + '$');
    }
    function test_inline_identities_in_a_list_render_in_full() {
      const formulas = ['(a + b)^2 = a^2 + 2ab + b^2', '(a - b)^2 = a^2 - 2ab + b^2', '(a + b)(a - b) = a^2 - b^2'];
      const labels = ["Le carré d'une somme", "Le carré d'une différence", "Le produit de la somme et de la différence"];
      show('identities', '<p>Voici les trois identités :</p><ol>' + formulas.map((tex, i) => '<li><strong>' + labels[i] + '</strong> : ' + math(tex, false) + '</li>').join('')
        + '</ol><p>Un exemple : ' + math('102 \\times 98', false) + ' en posant ' + math('a = 100', false) + '.</p>');
      tryVerify(() => (view().renderedHTML.match(/data:image\/svg\+xml/g) || []).length === 5, 10000);
      const widths = [], pattern = /<img [^>]* width="(\d+)"/g;
      let match;
      while ((match = pattern.exec(view().renderedHTML))) widths.push(Number(match[1]));
      verify(widths[0] > 180 && widths[1] > 180 && widths[2] > 180, 'The identities must extend past their first term');
      verify(widths[3] > 65 && widths[4] > 50);
      view().textEdit.selectAll();
      for (const tex of formulas) verify(message.selectedText.includes('$' + tex + '$'));
      message.clearTextSelection();
      const screenshot = Quickshell.env('QS_INLINE_MATH_SCREENSHOT');
      if (screenshot) grabImage(window.contentItem).save(screenshot);
    }
  }
}
