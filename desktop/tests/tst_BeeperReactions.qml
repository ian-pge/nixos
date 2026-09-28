import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var reactions: null
  Window { id: window; width: 600; height: 240; visible: true }
  SignalSpy { id: scaleChanges; signalName: "scaleChanged" }
  SignalSpy { id: opacityChanges; signalName: "opacityChanged" }
  TestResult { id: results }
  TestCase {
    name: "BeeperReactions"
    when: window.visible
    function reaction(person, emoji, count) {
      return {key: emoji || "👍", imgURL: "", count: count || 1,
        person: {id: person, title: person, imgURL: "", anonymous: false, isSelf: false}};
    }
    function chips() {
      return Array.from(reactions.children).filter(child => child.objectName === "beeperMessageReaction");
    }
    function show(people) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperReactions.qml");
      compare(component.status, Component.Ready, component.errorString());
      reactions = component.createObject(window.contentItem, {
        x: 10, y: 30, width: 500, messageIdentity: "chat-message", people: people || []
      });
      verify(reactions !== null); reactions.forceLayout();
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      if (reactions) { reactions.destroy(); reactions = null; }
      wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperReactions: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_initial_and_new_reactions_are_immediately_visible_without_animation() {
      show([reaction("camille")]);
      const existing = chips()[0];
      compare(existing.scale, 1); compare(existing.opacity, 1);
      reactions.people = [reaction("camille"), reaction("noe", "💜")];
      compare(reactions.count, 2);
      compare(chips()[0], existing);
      const added = chips()[1]; compare(added.scale, 1); compare(added.opacity, 1);
      scaleChanges.target = added; opacityChanges.target = added;
      scaleChanges.clear(); opacityChanges.clear();
      reactions.forceLayout();
      const width = reactions.width, height = reactions.implicitHeight, chipWidth = added.width;
      wait(200);
      compare(scaleChanges.count, 0); compare(opacityChanges.count, 0);
      compare(reactions.width, width); compare(reactions.implicitHeight, height); compare(added.width, chipWidth);
      compare(added.scale, 1); compare(added.opacity, 1);
    }
    function test_refresh_reorder_profiles_and_counts_keep_the_same_pills() {
      show([reaction("camille"), reaction("noe", "💜")]);
      const camille = chips()[0], noe = chips()[1];
      const avatar = findChild(camille, "beeperReactionAvatar");
      const update = reaction("camille", "👍", 3);
      update.person.title = "Camille Renamed";
      reactions.people = [reaction("noe", "💜"), update];
      tryVerify(() => chips()[0] === noe);
      compare(chips()[1], camille); compare(findChild(camille, "beeperReactionAvatar"), avatar);
      compare(camille.modelData.count, 3); compare(camille.modelData.person.title, "Camille Renamed");
      compare(camille.scale, 1); compare(noe.scale, 1);
      reactions.people = JSON.parse(JSON.stringify(reactions.people)); wait(0);
      compare(chips()[0], noe); compare(chips()[1], camille);
      compare(camille.opacity, 1); compare(noe.opacity, 1);
    }
    function test_removal_releases_layout_immediately() {
      show([reaction("camille"), reaction("noe", "💜")]);
      const kept = chips()[1], originalWidth = reactions.totalWidth;
      reactions.people = [reaction("noe", "💜")];
      compare(reactions.count, 1);
      compare(chips()[0], kept); verify(reactions.totalWidth < originalWidth);
      compare(kept.scale, 1); compare(kept.opacity, 1);
    }
    function test_hidden_updates_are_immediate_and_do_not_replay_when_visible() {
      show([reaction("camille")]); reactions.visible = false;
      reactions.people = [reaction("noe", "💜")];
      compare(reactions.count, 1); compare(chips()[0].modelData.person.id, "noe");
      reactions.visible = true; wait(20);
      compare(chips()[0].scale, 1); compare(chips()[0].opacity, 1);
      reactions.people = [];
      compare(reactions.count, 0);
    }
    function test_rapid_toggling_has_no_delayed_changes() {
      show([reaction("camille")]);
      for (let index = 0; index < 6; ++index) {
        reactions.people = []; compare(reactions.count, 0);
        reactions.people = [reaction("camille")]; compare(reactions.count, 1);
        compare(chips()[0].scale, 1); compare(chips()[0].opacity, 1);
      }
      wait(200); compare(reactions.count, 1); compare(chips()[0].opacity, 1);
      reactions.people = []; compare(reactions.count, 0);
      wait(180); compare(reactions.count, 0);
    }
    function test_different_message_never_replays_history() {
      show([reaction("camille")]);
      const first = chips()[0];
      reactions.messageIdentity = "another-message";
      reactions.people = [reaction("camille"), reaction("noe", "💜")];
      tryCompare(reactions, "count", 2);
      verify(chips()[0] !== first);
      for (const chip of chips()) { compare(chip.scale, 1); compare(chip.opacity, 1); }
    }
  }
}
