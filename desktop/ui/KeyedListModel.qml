import QtQuick

// Apply snapshot changes to a native model instead of replacing a JS-array
// model. Unchanged delegates (and their media players) keep their identity.
ListModel {
  id: root
  dynamicRoles: true
  property var rows: []
  property var keys: []
  property var snapshots: []
  // Opt in only when changed rows (including nested data) are replaced.
  property bool immutableRows: false
  property var sources: []
  // Views without playing media may reuse row slots for large view changes.
  // Histories and attachment models retain their delegates by identity.
  property int bulkThreshold: 0
  property bool bulkUpdating: false
  property string roleName: "row"
  property bool ready: false
  signal updating(bool structural)
  signal updated(bool structural, var changedIndexes, int firstChanged)
  onRowsChanged: if (ready) reconcile()
  Component.onCompleted: { ready = true; reconcile(); }

  function planChanges(inputKeys) {
    const retained = Object.create(null);
    for (const key of inputKeys) retained[key] = true;
    const currentKeys = keys.slice(), operations = [];
    let removedCount = 0;
    for (let end = currentKeys.length - 1; end >= 0; --end) {
      if (retained[currentKeys[end]]) continue;
      let start = end;
      while (start > 0 && !retained[currentKeys[start - 1]]) --start;
      const length = end - start + 1;
      operations.push({kind: "remove", index: start, length: length});
      removedCount += length;
      if (bulkThreshold > 0 && (operations.length > bulkThreshold || removedCount > bulkThreshold)) return null;
      currentKeys.splice(start, length);
      end = start;
    }
    const existing = Object.create(null);
    for (const key of currentKeys) existing[key] = true;
    for (let index = 0; index < inputKeys.length; ++index) {
      const key = inputKeys[index];
      if (currentKeys[index] !== key) {
        const previous = currentKeys.indexOf(key, index + 1);
        if (previous >= 0) {
          let length = 1;
          while (previous + length < currentKeys.length && index + length < inputKeys.length
              && currentKeys[previous + length] === inputKeys[index + length]) ++length;
          const gap = previous - index;
          const from = length > gap ? index : previous;
          const to = length > gap ? index + length : index;
          const moved = Math.min(length, gap);
          operations.push({kind: "move", from: from, to: to, length: moved});
          currentKeys.splice(to, 0, ...currentKeys.splice(from, moved));
        } else {
          let length = 1;
          while (index + length < inputKeys.length && !existing[inputKeys[index + length]]) ++length;
          operations.push({kind: "insert", index: index, length: length});
          currentKeys.splice(index, 0, ...inputKeys.slice(index, index + length));
          index += length - 1;
        }
        if (bulkThreshold > 0 && operations.length > bulkThreshold) return null;
      }
    }
    return operations;
  }
  function reconcile() {
    const input = rows || [];
    const inputKeys = input.map(row => JSON.stringify([row.chatID || "", row.id]));
    const operations = planChanges(inputKeys), changedIndexes = [];
    const structural = operations === null || operations.length > 0;
    bulkUpdating = operations === null;
    updating(structural);
    let firstChanged = input.length;
    let currentSnapshots = snapshots.slice(), currentSources = sources.slice();
    if (bulkUpdating) {
      const retainedCount = Math.min(count, input.length);
      const nextSnapshots = input.map(row => JSON.stringify(row));
      if (count > input.length) remove(input.length, count - input.length);
      for (let index = 0; index < retainedCount; ++index)
        if (nextSnapshots[index] !== currentSnapshots[index]) set(index, {[roleName]: input[index]});
      if (input.length > retainedCount) append(input.slice(retainedCount).map(row => ({[roleName]: row})));
      currentSnapshots = nextSnapshots; currentSources = input.slice();
      firstChanged = 0;
    } else for (const operation of operations) {
      const index = operation.index, length = operation.length;
      if (operation.kind === "remove") {
        remove(index, length); currentSnapshots.splice(index, length); currentSources.splice(index, length);
        firstChanged = Math.min(firstChanged, index);
      } else if (operation.kind === "move") {
        move(operation.from, operation.to, length);
        currentSnapshots.splice(operation.to, 0, ...currentSnapshots.splice(operation.from, length));
        currentSources.splice(operation.to, 0, ...currentSources.splice(operation.from, length));
        firstChanged = Math.min(firstChanged, operation.from, operation.to);
      } else {
        const added = input.slice(index, index + length);
        insert(index, added.map(row => ({[roleName]: row})));
        currentSnapshots.splice(index, 0, ...added.map(row => JSON.stringify(row)));
        currentSources.splice(index, 0, ...added);
        firstChanged = Math.min(firstChanged, index);
        for (let i = index; i < index + length; ++i) changedIndexes.push(i);
      }
    }
    for (let index = 0; index < input.length; ++index) {
      const row = input[index];
      if (immutableRows && currentSources[index] === row) continue;
      const snapshot = JSON.stringify(row);
      if (currentSnapshots[index] !== snapshot) {
        set(index, {[roleName]: row}); currentSnapshots[index] = snapshot;
        changedIndexes.push(index); firstChanged = Math.min(firstChanged, index);
      }
      currentSources[index] = row;
    }
    keys = inputKeys; snapshots = currentSnapshots; sources = currentSources;
    updated(structural, changedIndexes, firstChanged);
    bulkUpdating = false;
  }
}
