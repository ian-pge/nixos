import QtQuick

// Apply snapshot changes to a native model instead of replacing a JS-array
// model. Unchanged delegates (and their media players) keep their identity.
ListModel {
  id: root
  dynamicRoles: true
  property var rows: []
  property var keys: []
  property var snapshots: []
  property bool ready: false
  signal updating()
  signal updated()
  onRowsChanged: if (ready) reconcile()
  Component.onCompleted: { ready = true; reconcile(); }

  function reconcile() {
    updating();
    const input = rows || [];
    for (let index = 0; index < input.length; ++index) {
      const row = input[index];
      const key = JSON.stringify([row.chatID || "", row.id]);
      const snapshot = JSON.stringify(row);
      if (keys[index] !== key) {
        const previous = keys.indexOf(key, index + 1);
        if (previous >= 0) {
          move(previous, index, 1);
          keys.splice(index, 0, keys.splice(previous, 1)[0]);
          snapshots.splice(index, 0, snapshots.splice(previous, 1)[0]);
        } else {
          insert(index, {row: row});
          keys.splice(index, 0, key); snapshots.splice(index, 0, snapshot);
        }
      }
      if (snapshots[index] !== snapshot) {
        set(index, {row: row}); snapshots[index] = snapshot;
      }
    }
    if (count > input.length) remove(input.length, count - input.length);
    keys.length = input.length; snapshots.length = input.length;
    updated();
  }
}
