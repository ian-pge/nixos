import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var message: null
  property var format: null
  property var opened: []
  readonly property string firstUrl: "https://youtu.be/ABCDEFGHIJK?si=sharing-parameter"
  readonly property string secondUrl: "https://youtu.be/LMNOPQRSTUV?si=another-parameter"
  Component.onCompleted: format = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../features/messenger/BeeperFormat.js" as F; QtObject { property var library: F }', fixture).library
  Window { id: window; visible: true; width: 900; height: 700; color: "#181926" }
  SignalSpy { id: copied; target: fixture.message; signalName: "copyLinkRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperLinks"
    when: window.visible && fixture.format !== null
    function init() { fixture.opened = []; }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); if (message) { message.destroy(); message = null; wait(0); } }
    function cleanupTestCase() { console.log("BeeperLinks: " + results.passCount + " passed, " + results.failCount + " failed"); Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0)); }
    function show(text, links = []) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperMessage.qml");
      compare(component.status, Component.Ready, component.errorString());
      message = component.createObject(window.contentItem, {x: 20, y: 20, width: 850, networkAccent: "#a6da95",
        message: {id: "links", isSender: true, text: text, links: links},
        linkOpener: url => { fixture.opened = fixture.opened.concat([url]); }});
      verify(message !== null); wait(30); copied.clear();
    }
    function descendants(item, name) {
      let items = [];
      for (const child of item.children || []) {
        if (child.objectName === name) items.push(child);
        items = items.concat(descendants(child, name));
      }
      return items;
    }
    function test_plain_urls_become_compact_cards_in_message_order() {
      const original = "Regarde ces vidéos dans cet ordre\n\n\n" + fixture.firstUrl + "\n\n\net\n\n\n" + fixture.secondUrl;
      show(original);
      compare(message.plainBody, original, "Copy/edit keeps the exact original message");
      compare(message.linkedParts.map(part => part.kind), ["text", "link", "text", "link"]);
      const cards = descendants(message, "beeperMessageLink"); compare(cards.length, 2);
      compare(cards[0].link.url, fixture.firstUrl); compare(cards[1].link.url, fixture.secondUrl);
      compare(findChild(cards[0], "beeperLinkTitle").text, "Vidéo YouTube");
      compare(findChild(cards[0], "beeperLinkAddress").text, "youtu.be/ABCDEFGHIJK");
      verify(cards[0].mapToItem(message, 0, 0).y < cards[1].mapToItem(message, 0, 0).y);
      verify(message.height < 300, "Blank lines around URLs must not make an enormous bubble");
      verify(!findChild(message, "messageBody").visible);
      mouseClick(cards[0]); compare(fixture.opened, [fixture.firstUrl]);
    }
    function test_metadata_title_is_used_without_a_duplicate_card_or_html() {
      const title = '<b>A useful video</b>';
      show("Look " + fixture.firstUrl, [{url: fixture.firstUrl, title: title}]);
      const cards = descendants(message, "beeperMessageLink"); compare(cards.length, 1);
      const label = findChild(cards[0], "beeperLinkTitle");
      compare(label.text, title); compare(label.textFormat, Text.PlainText);
      compare(fixture.format.linkPresentation({url: "https://youtube.com@evil.example/video"}).site, "evil.example");
      compare(fixture.format.linkPresentation({url: "javascript:alert(1)"}), null);
      compare(fixture.format.messageParts({text: '<img src="https://not-loaded.invalid/pixel">'}), []);
      compare(fixture.format.messageParts({text: '`https://example.test/code`'}), []);
    }
    function test_copy_menu_keeps_complete_url_and_search_keeps_geometry() {
      show(fixture.firstUrl);
      const card = findChild(message, "beeperMessageLink"), bubble = findChild(message, "beeperMessageBubble");
      const width = bubble.width, height = bubble.height;
      message.searchQuery = "sharing-parameter"; verify(card.searchMatch); wait(20);
      compare(bubble.width, width); compare(bubble.height, height);
      mouseClick(card, card.width / 2, card.height / 2, Qt.RightButton);
      const menu = findChild(card, "beeperLinkMenu"); tryCompare(menu, "opened", true);
      mouseClick(findChild(card, "beeperLinkCopy"));
      compare(copied.count, 1); compare(copied.signalArguments[0][0], fixture.firstUrl);
      compare(fixture.opened.length, 0);
    }
    function test_prose_around_cards_stays_selectable() {
      show("Bonjour tout le monde\n" + fixture.firstUrl);
      const paragraph = findChild(message, "beeperLinkParagraph"); mouseMove(paragraph, 4, 4);
      tryVerify(() => findChild(paragraph, "beeperMessageTextSelection") !== null);
      const selection = findChild(paragraph, "beeperMessageTextSelection");
      selection.select(0, 7); compare(message.selectedText, "Bonjour"); verify(!selection.activeFocus);
      message.clearTextSelection(); compare(message.selectedText, "");
    }
    function test_plain_message_geometry_is_stable_while_history_measures_it_hidden() {
      show("An ordinary message with enough words to wrap inside a conversation bubble.");
      verify(!message.hasLinkCards);
      const width = message.preferredContentWidth, height = message.height;
      message.visible = false; wait(30);
      compare(message.preferredContentWidth, width); compare(message.height, height);
      message.visible = true; wait(30);
      compare(message.preferredContentWidth, width); compare(message.height, height);
    }
    function test_cards_fit_received_and_sent_messages_at_different_widths() {
      show(fixture.firstUrl, [{url: fixture.firstUrl, title: "A long video title that should wrap inside the card without stretching the conversation"}]);
      for (const outgoing of [false, true]) for (const width of [850, 360, 260]) for (const scale of [1, 1.8]) {
        message.textScale = scale;
        message.message = Object.assign({}, message.message, {isSender: outgoing}); message.width = width; wait(20);
        const card = findChild(message, "beeperMessageLink"), bubble = findChild(message, "beeperMessageBubble");
        verify(card.width <= bubble.width - 28); verify(bubble.width <= width - 42);
        verify(card.height >= 72); verify(findChild(card, "beeperLinkTitle").width > 0);
      }
    }
    function test_z_capture() {
      const path = Quickshell.env("BEEPER_LINK_SCREENSHOT"); if (!path) return;
      show("Regarde ces vidéos dans cet ordre\n\n\n" + fixture.firstUrl + "\n\n\net\n\n" + fixture.secondUrl,
        [{url: fixture.firstUrl, title: "Le futur des mathématiques"}, {url: fixture.secondUrl, title: "Comprendre le rétro-engineering"}]);
      let captured = false;
      verify(window.contentItem.grabToImage(result => { verify(result.saveToFile(path)); captured = true; }));
      tryVerify(() => captured);
    }
  }
}
