import QtQuick
import QtTest
import Quickshell

// Synthetic participant pictures and in-memory data only: no real accounts.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var messageItem: null
  property var format: null
  Component.onCompleted: format = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../features/messenger/BeeperFormat.js" as F; QtObject { property var library: F }', fixture).library
  Window { id: window; width: 860; height: 620; visible: true; color: "#181926" }
  TestResult { id: results }
  TestCase {
    name: "BeeperPeople"
    when: window.visible && fixture.format !== null
    function picture(color) {
      return "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="80" height="80" fill="' + color + '"/><circle cx="40" cy="30" r="14" fill="#24273a"/><ellipse cx="40" cy="75" rx="27" ry="26" fill="#24273a"/></svg>');
    }
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props); verify(item !== null); return item;
    }
    function row(overrides) {
      return Object.assign({id: "m1", chatID: "group", senderID: "self", isSender: true,
        text: "On se retrouve demain ?", timestamp: "2026-09-26T14:32:00Z",
        reactions: [{participantID: "camille", reactionKey: "👍", emoji: true}, {participantID: "noe", reactionKey: "👍", emoji: true}],
        seen: {camille: true, noe: true, self: true}}, overrides || {});
    }
    function show(overrides) {
      beeperData.messages = [row(overrides)];
      messageItem = create("../features/messenger/BeeperMessage.qml", window.contentItem,
        {x: 20, y: 20, width: 800, beeperData: beeperData, message: beeperData.messages[0], networkAccent: "#b7bdf8"});
      messageItem.forceMessageLayout(); wait(25);
      return messageItem;
    }
    function chips() {
      return Array.from(findChild(messageItem, "beeperMessageReactions").children).filter(item => item.objectName === "beeperMessageReaction");
    }
    function readers() {
      return Array.from(findChild(messageItem, "beeperMessageReadReceipt").children).filter(item => item.objectName === "beeperReaderAvatar");
    }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      beeperData.accounts = [{id: "account", user: {id: "account-self", fullName: "My account", imgURL: picture("#a6da95")}}];
      beeperData.chats = [{id: "group", title: "Friends", type: "group", network: "Telegram", accountID: "account", imgURL: picture("#eed49f"), participants: {items: [
        {id: "self", fullName: "Me", isSelf: true},
        {id: "camille", fullName: "Camille", isSelf: false, imgURL: picture("#f5bde6")},
        {id: "noe", fullName: "Noé", isSelf: false, imgURL: picture("#8aadf4")},
        {id: "alex", fullName: "Alex Martin", isSelf: false}
      ]}}];
      beeperData.currentChatID = "group";
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      if (messageItem) { messageItem.destroy(); messageItem = null; }
      beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperPeople: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_each_reactor_has_an_emoji_and_their_own_photo() {
      show(); compare(chips().length, 2);
      compare(chips()[0].modelData.person.id, "camille"); compare(chips()[1].modelData.person.id, "noe");
      for (const chip of chips()) {
        compare(findChild(chip, "beeperReactionEmoji").text, "👍");
        compare(chip.radius, chip.height / 2);
        const avatar = findChild(chip, "beeperReactionAvatar");
        compare(avatar.width, avatar.height); compare(avatar.diameter, 26);
        tryCompare(avatar, "imageReady", true); compare(avatar.avatarSource, chip.modelData.person.imgURL);
        verify(!findChild(avatar, "beeperNetworkBadge").visible);
        verify(chip.tooltipText.includes(chip.modelData.person.title));
      }
      verify(chips()[0].modelData.person.imgURL !== chips()[1].modelData.person.imgURL);
    }
    function test_read_receipts_are_miniature_avatars_without_a_visible_name_label() {
      show(); compare(readers().length, 2);
      const flow = findChild(messageItem, "beeperMessageReadReceipt");
      verify(flow.text === undefined, "No Read by text remains below the bubble");
      for (const avatar of readers()) {
        verify(avatar.modelData.id !== "self"); compare(avatar.width, avatar.height); compare(avatar.diameter, 22);
        tryCompare(avatar, "imageReady", true); verify(avatar.tooltipText.startsWith("Read by "));
      }
      const bubble = findChild(messageItem, "beeperMessageBubble");
      verify(flow.y >= bubble.y + bubble.height);
      compare(flow.layoutDirection, Qt.RightToLeft);
    }
    function test_missing_photos_use_initials_and_unknown_people_never_use_group_or_sender_photos() {
      show({reactions: [{participantID: "alex", reactionKey: "❤️"}, {participantID: "missing", reactionKey: "🔥"}], seen: {alex: true, missing: true}});
      compare(chips()[0].modelData.person.title, "Alex Martin");
      compare(chips()[1].modelData.person.title, "missing");
      for (const chip of chips()) compare(findChild(chip, "beeperReactionAvatar").avatarSource, "");
      for (const avatar of readers()) compare(avatar.avatarSource, "");
      compare(fixture.format.initials(readers()[0].modelData.title), "AM");
    }
    function test_own_reactions_use_our_account_photo_but_our_read_receipt_is_hidden() {
      show({reactions: [{participantID: "self", reactionKey: "😂"}, {participantID: "account-self", reactionKey: "💜"}], seen: {self: true, "account-self": true}});
      for (const chip of chips()) {
        compare(chip.modelData.person.title, "You");
        compare(findChild(chip, "beeperReactionAvatar").avatarSource, beeperData.accounts[0].user.imgURL);
      }
      compare(readers().length, 0); verify(!findChild(messageItem, "beeperMessageReadReceipt").visible);
    }
    function test_aggregate_and_anonymous_data_does_not_invent_people() {
      show({reactions: [{reactionKey: "👍", count: 4}], seen: true});
      compare(chips().length, 1); compare(chips()[0].modelData.count, 4); verify(chips()[0].modelData.person.anonymous);
      compare(readers().length, 1); verify(readers()[0].modelData.anonymous);
      compare(readers()[0].avatarSource, ""); compare(readers()[0].modelData.title, "?");
      verify(readers()[0].tooltipText.includes("unavailable"));
    }
    function test_network_independent_readers_keep_only_confirmed_people() {
      for (const network of ["Telegram", "WhatsApp", "Signal", "Instagram", "Messenger", "Google Messages", "Unknown"]) {
        const chat = Object.assign({}, beeperData.currentChat, {network: network});
        const readers = fixture.format.messageReaders({senderID: "camille", seen: {self: true, "account-self": true, camille: true, noe: "2026-09-26T14:32:00Z", alex: false}}, chat, beeperData.accounts);
        compare(readers.length, 1, network); compare(readers[0].id, "noe"); verify(!!readers[0].imgURL);
        compare(fixture.format.messageReaders({isSender: true, sendStatus: {status: "SUCCESS", deliveredToUsers: ["noe"]}}, chat, beeperData.accounts).length, 0);
        compare(fixture.format.messageReaders({seen: true}, chat, beeperData.accounts).length, 0);
      }
    }
    function test_private_boolean_receipt_uses_the_peer_photo() {
      const chat = {id: "private", type: "single", title: "Private peer", imgURL: picture("#f5bde6")};
      let profiles = fixture.format.messageReaders({isSender: true, seen: true}, chat, beeperData.accounts);
      compare(profiles.length, 1); compare(profiles[0].title, "Private peer"); compare(profiles[0].imgURL, chat.imgURL);
      chat.participants = {items: [{id: "peer", fullName: "Peer Name", isSelf: false}]};
      profiles = fixture.format.messageReaders({isSender: true, seen: true}, chat, beeperData.accounts);
      compare(profiles[0].title, "Peer Name"); compare(profiles[0].imgURL, chat.imgURL);
    }
    function test_telegram_cumulative_receipts_carry_photos_without_marking_newer_messages() {
      const chat = Object.assign({}, beeperData.currentChat, {type: "single"});
      const rows = [
        {id: "older", isSender: true, timestamp: "2026-09-26T13:00:00Z"},
        {id: "marker", isSender: true, timestamp: "2026-09-26T14:00:00Z", seen: {camille: true}},
        {id: "newer", isSender: true, timestamp: "2026-09-26T15:00:00Z"}
      ];
      const profiles = fixture.format.readReceiptReaders(rows, chat, beeperData.accounts);
      compare(profiles.older[0].id, "camille"); compare(profiles.older[0].imgURL, profiles.marker[0].imgURL);
      compare(profiles.newer.length, 0);
    }
    function test_reactions_deduplicate_only_the_same_person_and_key_and_keep_custom_images_separate() {
      show({reactions: [
        {participantID: "camille", reactionKey: "👍"}, {participantID: "camille", reactionKey: "👍"},
        {participantID: "noe", reactionKey: "👍"}, {participantID: "camille", reactionKey: "custom", imgURL: picture("#eed49f")}
      ]});
      compare(chips().length, 3);
      const custom = chips()[2];
      tryCompare(findChild(custom, "beeperReactionImage"), "status", Image.Ready);
      verify(!findChild(custom, "beeperReactionEmoji").visible);
      verify(findChild(custom, "beeperReactionAvatar").avatarSource !== custom.modelData.imgURL);
    }
    function test_avatar_sources_update_without_recreating_the_message_and_stop_offscreen() {
      show(); const old = readers()[0].avatarSource;
      beeperData.chats = beeperData.chats.map(chat => Object.assign({}, chat, {participants: {items: chat.participants.items.map(person => person.id === "camille" ? Object.assign({}, person, {imgURL: picture("#eed49f")}) : person)}}));
      tryVerify(() => readers()[0].avatarSource !== old);
      compare(findChild(chips()[0], "beeperReactionAvatar").avatarSource, readers()[0].avatarSource);
      messageItem.renderMedia = false;
      for (const avatar of readers()) { verify(!avatar.imageEnabled); tryCompare(avatar, "imageReady", false); }
      for (const chip of chips()) verify(!findChild(chip, "beeperReactionAvatar").imageEnabled);
      compare(beeperData.requests.filter(request => ["read", "unread", "react"].includes(request.method)).length, 0);
    }
    function test_wrapping_preserves_left_reactions_right_time_and_no_overlap_at_large_text_sizes() {
      show({reactions: Array.from({length: 12}, (_, index) => ({participantID: "person-" + index, reactionKey: "👍"}))});
      for (const width of [800, 320, 220]) {
        for (const scale of [1, 1.8]) {
          for (const outgoing of [false, true]) {
            messageItem.width = width; messageItem.textScale = scale;
            messageItem.message = Object.assign({}, messageItem.message, {isSender: outgoing});
            messageItem.forceMessageLayout(); wait(30);
            const meta = findChild(messageItem, "beeperMessageMeta"), time = findChild(messageItem, "beeperMessageTime");
            const position = time.mapToItem(meta, 0, 0);
            fuzzyCompare(position.x + time.width, meta.width, 0.5);
            compare(chips()[0].x, 0);
            for (const chip of chips()) {
              verify(chip.x >= 0 && chip.x + chip.width <= meta.width + 0.5);
              verify(chip.x + chip.width <= position.x || chip.y + chip.height <= position.y,
                "Reaction pills must not overlap the timestamp");
            }
            const bubble = findChild(messageItem, "beeperMessageBubble"), point = meta.mapToItem(bubble, 0, 0);
            verify(point.y + meta.height <= bubble.height + 0.5);
          }
        }
      }
    }
    function test_z_visual_preview() {
      const path = Quickshell.env("BEEPER_PEOPLE_SCREENSHOT");
      if (!path) return;
      show();
      const second = create("../features/messenger/BeeperMessage.qml", window.contentItem, {
        x: 20, y: 190, width: 800, beeperData: beeperData, networkAccent: "#b7bdf8",
        message: row({id: "m2", senderID: "camille", senderName: "Camille", isSender: false, text: "Oui ! À demain ✨", seen: {noe: true},
          reactions: [{participantID: "self", reactionKey: "💜"}, {participantID: "noe", reactionKey: "👍"}]})
      });
      try {
        second.forceMessageLayout(); wait(250);
        let saved = false;
        verify(window.contentItem.grabToImage(result => { saved = result.saveToFile(path); }));
        tryVerify(() => saved, 3000);
      } finally { second.destroy(); }
    }
  }
}
