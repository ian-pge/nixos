.pragma library

// Vim-style modal editing over a plain text buffer, sized for chat messages.
// Pure logic without Qt: callers pass the text, the cursor and one key, then
// apply the returned text, cursor and selection. Positions are UTF-16 offsets
// like Qt's text items, but motions and edits step over whole characters:
// combining accents, emoji with skin tones or ZWJ sequences, and flags.
//
// handleKey() returns {handled} and, when the key was consumed:
//   text       the new text, only present when the command changed it
//   cursor     the insert caret, or the character under the normal block
//   selection  {start, end} in visual modes, end exclusive
//   copy       text to mirror on the system clipboard after a yank
//   submit     true when Enter was pressed outside insert mode
// Undo history is kept here, one step per Vim command or insert session,
// because Qt's own undo splits a replacement into separate steps.
// While a / search is being typed, state.search holds {pattern}.

var historyLimit = 200;
var singleCommands = ["x", "X", "<Del>", "s", "S", "D", "C", "Y", "p", "P", "u", "<C-r>",
  "J", "~", "i", "a", "I", "A", "o", "O", "v", "V", "<CR>", "<S-CR>", "<Tab>", "n", "N"];
var visualCommands = ["<Esc>", "d", "x", "<Del>", "X", "D", "c", "s", "C", "S", "y", "Y",
  "p", "P", "~", "u", "U", "J", "o", "v", "V", "<CR>", "<S-CR>", "<Tab>"];
var simpleMotions = ["h", "l", "j", "k", "w", "b", "e", "W", "B", "E", "0", "^", "$", "G",
  ";", ",", " ", "<BS>", "<Left>", "<Right>", "<Up>", "<Down>", "<Home>", "<End>"];
var objectKeys = ["w", "W", "\"", "'", "`", "(", ")", "b", "[", "]", "{", "}", "B", "<", ">"];

function create(options) {
  return {
    mode: "insert", keys: [], anchor: 0, cursor: 0, goalX: -1, goalColumn: -1,
    register: {text: "", linewise: false}, lastFind: null,
    search: null, lastSearch: "",
    undo: [], redo: [], insertBase: null,
    multiline: !options || options.multiline !== false
  };
}

// Back to insert mode with a fresh history, e.g. when the field gains focus.
function reset(state, buffer) {
  state.mode = "insert"; state.keys = []; state.undo = []; state.redo = [];
  state.search = null;
  state.insertBase = buffer ? {text: buffer.text, cursor: buffer.cursor} : null;
  resetGoal(state);
}

// Drops history that no longer matches the text after an outside edit.
function forget(state) {
  state.undo = []; state.redo = []; state.insertBase = null; state.keys = [];
  state.search = null;
  if (state.mode !== "insert") state.mode = "normal";
}

function handleKey(state, buffer, input, view) {
  const key = token(input);
  if (state.mode === "insert") return key === "<Esc>" ? leaveInsert(state, buffer) : {handled: false};
  // Modifier presses and level latches carry no text: keep any pending command.
  if (!key) return {handled: false};
  if (state.search) return searchKey(state, buffer, key);
  if (state.mode === "normal" && key === "/" && !state.keys.length) {
    state.search = {pattern: ""};
    return hold(state, buffer);
  }
  // A bare Escape in normal mode belongs to the owner, e.g. to leave the field.
  if (state.mode === "normal" && key === "<Esc>" && !state.keys.length) return {handled: false};
  state.keys.push(key);
  const command = state.mode === "normal" ? parseNormal(state.keys) : parseVisual(state.keys);
  if (command.status === "incomplete") return hold(state, buffer);
  state.keys = [];
  if (command.status === "invalid") return hold(state, buffer);
  return run(state, buffer, command, view || null);
}

// ------------------------------------------------------------------ keys

function token(input) {
  if (!input) return "";
  if (input.ctrl || input.meta) return input.ctrl && !input.meta && input.key === "r" ? "<C-r>" : "";
  switch (input.key) {
  case "Escape": return "<Esc>";
  case "Return": case "Enter": return input.shift ? "<S-CR>" : "<CR>";
  case "Backspace": return "<BS>";
  case "Delete": return "<Del>";
  case "Left": return "<Left>";
  case "Right": return "<Right>";
  case "Up": return "<Up>";
  case "Down": return "<Down>";
  case "Home": return "<Home>";
  case "End": return "<End>";
  case "Tab": return "<Tab>";
  }
  const text = input.text || "";
  return text && text.charCodeAt(0) >= 0x20 && text.charCodeAt(0) !== 0x7F ? text : "";
}

function isNamed(key) { return /^<[A-Z][A-Za-z-]*>$/.test(key); }

function parseCount(keys, index) {
  let digits = "";
  while (index < keys.length && /^[0-9]$/.test(keys[index]) && (digits || keys[index] !== "0"))
    digits += keys[index++];
  return {count: digits ? Number(digits) : 0, next: index};
}

function parseMotion(keys, index) {
  if (index >= keys.length) return {status: "incomplete"};
  const key = keys[index];
  if (simpleMotions.indexOf(key) >= 0) return {status: "complete", motion: key, next: index + 1};
  if (key === "g") {
    if (index + 1 >= keys.length) return {status: "incomplete"};
    return keys[index + 1] === "g" ? {status: "complete", motion: "gg", next: index + 2} : {status: "invalid"};
  }
  if (["f", "F", "t", "T"].indexOf(key) >= 0) {
    if (index + 1 >= keys.length) return {status: "incomplete"};
    const character = keys[index + 1];
    return isNamed(character) ? {status: "invalid"}
      : {status: "complete", motion: key, character: character, next: index + 2};
  }
  return {status: "invalid"};
}

function parseObject(keys, index) {
  if (index + 1 >= keys.length) return {status: "incomplete"};
  return objectKeys.indexOf(keys[index + 1]) >= 0
    ? {status: "complete", object: keys[index] + keys[index + 1], next: index + 2} : {status: "invalid"};
}

function parseNormal(keys) {
  const first = parseCount(keys, 0);
  let index = first.next;
  if (index >= keys.length) return {status: "incomplete"};
  const key = keys[index];
  if (key === "d" || key === "c" || key === "y") {
    const second = parseCount(keys, index + 1);
    const at = second.next;
    if (at >= keys.length) return {status: "incomplete"};
    const count = (first.count || 1) * (second.count || 1);
    const explicitCount = first.count > 0 || second.count > 0;
    if (keys[at] === key) return {status: "complete", operator: key, linewise: true, count: count};
    if (keys[at] === "i" || keys[at] === "a") {
      const object = parseObject(keys, at);
      return object.status === "complete"
        ? {status: "complete", operator: key, object: object.object, count: count} : object;
    }
    const motion = parseMotion(keys, at);
    if (motion.status !== "complete") return motion;
    return {status: "complete", operator: key, motion: motion.motion, character: motion.character,
      count: count, explicitCount: explicitCount};
  }
  const motion = parseMotion(keys, index);
  if (motion.status === "complete")
    return {status: "complete", motion: motion.motion, character: motion.character,
      count: first.count || 1, explicitCount: first.count > 0};
  if (motion.status === "incomplete") return motion;
  if (key === "r") {
    if (index + 1 >= keys.length) return {status: "incomplete"};
    const character = keys[index + 1];
    if (character === "<CR>") return {status: "complete", command: "r", character: "\n", count: first.count || 1};
    return isNamed(character) ? {status: "invalid"}
      : {status: "complete", command: "r", character: character, count: first.count || 1};
  }
  if (singleCommands.indexOf(key) >= 0)
    return {status: "complete", command: key, count: first.count || 1};
  return {status: "invalid"};
}

function parseVisual(keys) {
  const first = parseCount(keys, 0);
  const index = first.next;
  if (index >= keys.length) return {status: "incomplete"};
  const key = keys[index];
  if (key === "i" || key === "a") {
    const object = parseObject(keys, index);
    return object.status === "complete" ? {status: "complete", object: object.object, count: 1} : object;
  }
  const motion = parseMotion(keys, index);
  if (motion.status === "complete")
    return {status: "complete", motion: motion.motion, character: motion.character,
      count: first.count || 1, explicitCount: first.count > 0};
  if (motion.status === "incomplete") return motion;
  if (visualCommands.indexOf(key) >= 0) return {status: "complete", command: key, count: first.count || 1};
  return {status: "invalid"};
}

// ----------------------------------------------------------------- search

// Keys typed after / in normal mode build the pattern. Enter jumps to the
// next match after the cursor, wrapping around; Escape, or Backspace on an
// empty pattern, cancels. An empty pattern repeats the previous search.
function searchKey(state, buffer, key) {
  const search = state.search;
  if (key === "<Esc>") state.search = null;
  else if (key === "<BS>") {
    if (!search.pattern) state.search = null;
    else search.pattern = search.pattern.slice(0, previousBoundary(search.pattern, search.pattern.length));
  } else if (key === "<CR>") {
    state.search = null;
    const pattern = search.pattern || state.lastSearch;
    if (pattern) {
      state.lastSearch = pattern;
      resetGoal(state);
      const found = nextMatch(buffer.text, pattern, clampNormal(buffer.text, buffer.cursor), true);
      if (found >= 0) return {handled: true, cursor: clampNormal(buffer.text, found)};
    }
  } else if (!isNamed(key)) search.pattern += key;
  return hold(state, buffer);
}

// Plain-text matches of pattern, ignoring case, left to right.
function searchMatches(text, pattern) {
  const matches = [];
  if (!pattern) return matches;
  const expression = new RegExp(pattern.replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&"), "gi");
  let match;
  while ((match = expression.exec(text)) !== null)
    matches.push({start: match.index, end: match.index + match[0].length});
  return matches;
}

// Start of the next match after position, or the previous one before it,
// wrapping around the text; -1 when the pattern does not occur.
function nextMatch(text, pattern, position, forward) {
  const matches = searchMatches(text, pattern);
  if (!matches.length) return -1;
  if (forward) {
    for (const match of matches) if (match.start > position) return match.start;
    return matches[0].start;
  }
  for (let index = matches.length - 1; index >= 0; --index)
    if (matches[index].start < position) return matches[index].start;
  return matches[matches.length - 1].start;
}

// -------------------------------------------------------------- execution

function hold(state, buffer) {
  const text = buffer.text;
  if (state.mode === "normal") return {handled: true, cursor: clampNormal(text, buffer.cursor)};
  return {handled: true, cursor: state.cursor, selection: visualRange(state, text)};
}

function leaveInsert(state, buffer) {
  const text = buffer.text;
  if (state.insertBase && state.insertBase.text !== text) remember(state, state.insertBase);
  state.insertBase = null; state.mode = "normal"; state.keys = [];
  resetGoal(state);
  const position = Math.max(0, Math.min(buffer.cursor, text.length));
  const cursor = position > lineStart(text, position) ? previousBoundary(text, position) : position;
  return {handled: true, cursor: clampNormal(text, cursor)};
}

function run(state, buffer, command, view) {
  const text = buffer.text;
  const visual = state.mode !== "normal";
  const origin = visual ? state.cursor : clampNormal(text, buffer.cursor);
  const outcome = visual ? runVisual(state, text, command, view) : runNormal(state, text, origin, command, view);
  if (!outcome.vertical) resetGoal(state);
  const next = outcome.text === undefined ? text : outcome.text;
  if (outcome.insert) {
    state.insertBase = {text: text, cursor: origin};
    state.mode = "insert";
  } else if (!outcome.restore && next !== text) remember(state, {text: text, cursor: origin});
  const result = {handled: true};
  if (next !== text) result.text = next;
  if (state.mode === "visual" || state.mode === "visual-line") {
    result.cursor = state.cursor;
    result.selection = visualRange(state, next);
  } else result.cursor = state.mode === "insert" ? outcome.cursor : clampNormal(next, outcome.cursor);
  if (outcome.copy !== undefined) result.copy = outcome.copy;
  if (outcome.submit) result.submit = true;
  return result;
}

function runNormal(state, text, position, command, view) {
  if (command.operator) return operate(state, text, position, command, view);
  if (command.motion) {
    const target = motion(state, text, position, command, view, false);
    return target ? {cursor: target.position, vertical: target.vertical} : {cursor: position};
  }
  const count = command.count;
  switch (command.command) {
  case "x": case "<Del>": return operateRange(state, text, position, "d", forwardInLine(text, position, count));
  case "X": return operateRange(state, text, position, "d", backwardInLine(text, position, count));
  case "s": return operateRange(state, text, position, "c", forwardInLine(text, position, count));
  case "S": return operateRange(state, text, position, "c", lineRange(text, position, count));
  case "D": return operateRange(state, text, position, "d", toLineEnd(text, position, count));
  case "C": return operateRange(state, text, position, "c", toLineEnd(text, position, count));
  // Y copies to the end of the line, as in Neovim and Zed.
  case "Y": return operateRange(state, text, position, "y", toLineEnd(text, position, count));
  case "p": case "P": return paste(state, text, position, command.command === "P", count);
  case "n": case "N": {
    let at = position;
    for (let n = 0; n < count && state.lastSearch; ++n) {
      const found = nextMatch(text, state.lastSearch, at, command.command === "n");
      if (found < 0) break;
      at = found;
    }
    return {cursor: at};
  }
  case "u": return restore(state.undo, state.redo, text, position);
  case "<C-r>": return restore(state.redo, state.undo, text, position);
  case "J": return state.multiline ? join(text, position, Math.max(2, count)) : {cursor: position};
  case "~": return transformCharacters(text, position, count);
  case "r":
    if (command.character === "\n" && !state.multiline) return {cursor: position};
    return replaceCharacters(text, position, count, command.character);
  case "i": return {cursor: position, insert: true};
  case "a": return {cursor: lineStart(text, position) === lineEnd(text, position) ? position : nextBoundary(text, position), insert: true};
  case "I": return {cursor: firstNonBlank(text, position), insert: true};
  case "A": return {cursor: lineEnd(text, position), insert: true};
  case "o": case "O": {
    if (!state.multiline) return {cursor: position};
    const below = command.command === "o";
    const at = below ? lineEnd(text, position) : lineStart(text, position);
    return {text: text.slice(0, at) + "\n" + text.slice(at), cursor: below ? at + 1 : at, insert: true};
  }
  case "v": case "V":
    state.mode = command.command === "v" ? "visual" : "visual-line";
    state.anchor = position; state.cursor = position;
    return {cursor: position};
  case "<CR>":
    state.mode = "insert"; state.insertBase = null;
    return {cursor: position, submit: true};
  }
  return {cursor: position};
}

function runVisual(state, text, command, view) {
  const position = state.cursor;
  if (command.motion) {
    const target = motion(state, text, position, command, view, false);
    if (target) state.cursor = clampNormal(text, target.position);
    return {cursor: state.cursor, vertical: !!(target && target.vertical)};
  }
  if (command.object) {
    const range = objectRange(text, position, command.object);
    if (range && range.end > range.start) {
      state.anchor = range.start;
      state.cursor = previousBoundary(text, range.end);
    }
    return {cursor: state.cursor};
  }
  const range = visualRange(state, text);
  const name = command.command;
  if (name === "<CR>" || name === "<S-CR>" || name === "<Tab>") return {cursor: position};
  if (name === "o") {
    const anchor = state.anchor;
    state.anchor = state.cursor; state.cursor = anchor;
    return {cursor: state.cursor};
  }
  if (name === "v" || name === "V") {
    const wanted = name === "v" ? "visual" : "visual-line";
    state.mode = state.mode === wanted ? "normal" : wanted;
    return {cursor: position};
  }
  state.mode = "normal";
  switch (name) {
  case "<Esc>": return {cursor: position};
  case "d": case "x": case "<Del>": return operateRange(state, text, position, "d", range);
  case "X": case "D": return operateRange(state, text, position, "d", linesOf(text, range));
  case "c": case "s": return operateRange(state, text, position, "c", range);
  case "C": case "S": return operateRange(state, text, position, "c", linesOf(text, range));
  case "y": case "Y": {
    const yanked = operateRange(state, text, position, "y", name === "Y" ? linesOf(text, range) : range);
    yanked.cursor = name === "Y" ? lineStart(text, range.start) : range.start;
    return yanked;
  }
  case "p": case "P": return replaceSelection(state, text, range, name === "p");
  case "~": case "u": case "U": {
    const original = text.slice(range.start, range.end);
    const changed = name === "~" ? swapCase(original) : name === "u" ? original.toLowerCase() : original.toUpperCase();
    return {text: text.slice(0, range.start) + changed + text.slice(range.end), cursor: range.start};
  }
  case "J": {
    if (!state.multiline) return {cursor: range.start};
    const lines = lineNumber(text, Math.max(range.start, range.end - 1)) - lineNumber(text, range.start) + 1;
    return join(text, range.start, Math.max(2, lines));
  }
  }
  return {cursor: position};
}

function operate(state, text, position, command, view) {
  const operator = command.operator;
  let range = null;
  if (command.linewise) range = lineRange(text, position, command.count);
  else if (command.object) range = objectRange(text, position, command.object);
  else if (operator === "c" && (command.motion === "w" || command.motion === "W") && charClass(text, position, false) !== 0) {
    // cw on a word changes to its end, like ce, and keeps the following space.
    const big = command.motion === "W";
    let end = wordEndHere(text, position, big);
    for (let n = 1; n < command.count; ++n) end = wordEnd(text, end, big);
    range = {start: position, end: nextBoundary(text, end), linewise: false};
  } else {
    const target = motion(state, text, position, command, view, true);
    if (!target) return {cursor: position};
    range = motionRange(text, position, target);
  }
  return operateRange(state, text, position, operator, range);
}

function operateRange(state, text, position, operator, range) {
  if (!range) return {cursor: position};
  if (range.linewise) {
    const lines = text.slice(range.start, range.end);
    setRegister(state, lines, true);
    if (operator === "y")
      return {cursor: range.start < lineStart(text, position) ? range.start : position, copy: lines};
    if (operator === "c")
      return {text: text.slice(0, range.start) + text.slice(range.end), cursor: range.start, insert: true};
    let from = range.start, to = range.end;
    if (to < text.length) to += 1;
    else if (from > 0) from -= 1;
    const next = text.slice(0, from) + text.slice(to);
    return {text: next, cursor: firstNonBlank(next, Math.min(range.start, next.length))};
  }
  if (range.end <= range.start)
    return operator === "c" ? {cursor: range.start, insert: true} : {cursor: position};
  const chunk = text.slice(range.start, range.end);
  setRegister(state, chunk, false);
  if (operator === "y") return {cursor: range.start, copy: chunk};
  return {text: text.slice(0, range.start) + text.slice(range.end), cursor: range.start, insert: operator === "c"};
}

function setRegister(state, text, linewise) {
  state.register = {text: text, linewise: linewise && state.multiline};
}

function paste(state, text, position, before, count) {
  const register = state.register;
  if (!register.text && !register.linewise) return {cursor: position};
  if (register.linewise) {
    const block = Array(count).fill(register.text).join("\n");
    if (before) {
      const at = lineStart(text, position);
      const next = text.slice(0, at) + block + "\n" + text.slice(at);
      return {text: next, cursor: firstNonBlank(next, at)};
    }
    const at = lineEnd(text, position);
    const next = text.slice(0, at) + "\n" + block + text.slice(at);
    return {text: next, cursor: firstNonBlank(next, at + 1)};
  }
  const chunk = register.text.repeat(count);
  const at = before || lineStart(text, position) === lineEnd(text, position) ? position : nextBoundary(text, position);
  const next = text.slice(0, at) + chunk + text.slice(at);
  return {text: next, cursor: previousBoundary(next, at + chunk.length)};
}

function replaceSelection(state, text, range, swapRegister) {
  const register = state.register;
  const inserted = register.linewise && !range.linewise ? "\n" + register.text + "\n" : register.text;
  const removed = text.slice(range.start, range.end);
  const next = text.slice(0, range.start) + inserted + text.slice(range.end);
  // Visual p keeps the replaced text, as in Vim; P leaves the register alone.
  if (swapRegister) setRegister(state, removed, range.linewise);
  return {text: next, cursor: inserted ? previousBoundary(next, range.start + inserted.length) : range.start};
}

function restore(from, to, text, position) {
  if (!from.length) return {cursor: position};
  const snapshot = from.pop();
  to.push({text: text, cursor: position});
  return {text: snapshot.text, cursor: snapshot.cursor, restore: true};
}

function remember(state, snapshot) {
  state.undo.push(snapshot);
  if (state.undo.length > historyLimit) state.undo.shift();
  state.redo = [];
}

function join(text, position, count) {
  let next = text, cursor = position, joined = false;
  for (let n = 1; n < count; ++n) {
    const end = lineEnd(next, cursor);
    if (end >= next.length) break;
    let after = end + 1;
    while (after < next.length && (next[after] === " " || next[after] === "\t")) after++;
    const start = lineStart(next, end);
    const blankBefore = end > start && (next[end - 1] === " " || next[end - 1] === "\t");
    const bare = end === start || blankBefore || after >= next.length || next[after] === "\n" || next[after] === ")";
    next = next.slice(0, end) + (bare ? "" : " ") + next.slice(after);
    cursor = end; joined = true;
  }
  return joined ? {text: next, cursor: cursor} : {cursor: position};
}

function transformCharacters(text, position, count) {
  const end = forwardInLine(text, position, count).end;
  if (end <= position) return {cursor: position};
  const changed = swapCase(text.slice(position, end));
  return {text: text.slice(0, position) + changed + text.slice(end), cursor: position + changed.length};
}

function replaceCharacters(text, position, count, character) {
  const stop = lineEnd(text, position);
  let end = position;
  for (let n = 0; n < count; ++n) {
    if (end >= stop) return {cursor: position};
    end = nextBoundary(text, end);
  }
  const replacement = character === "\n" ? "\n" : character.repeat(count);
  const next = text.slice(0, position) + replacement + text.slice(end);
  return {text: next, cursor: character === "\n" ? position + 1 : position + replacement.length - character.length};
}

function swapCase(value) {
  let out = "";
  for (const character of value) {
    const lower = character.toLowerCase();
    out += character === lower ? character.toUpperCase() : lower;
  }
  return out;
}

// ---------------------------------------------------------------- motions

// Returns {position, kind, word, vertical}, or null when the motion fails.
function motion(state, text, position, command, view, operator) {
  const count = command.count;
  const key = command.motion;
  switch (key) {
  case "h": case "<Left>": case "<BS>":
    return {position: backwardInLine(text, position, count).start, kind: "exclusive"};
  case "l": case "<Right>": case " ":
    return {position: forwardInLine(text, position, count).end, kind: "exclusive"};
  case "j": case "<Down>": return vertical(state, text, position, count, view, operator);
  case "k": case "<Up>": return vertical(state, text, position, -count, view, operator);
  case "w": case "W": {
    let target = position;
    for (let n = 0; n < count; ++n) target = wordForward(text, target, key === "W");
    return {position: target, kind: "exclusive", word: true};
  }
  case "b": case "B": {
    let target = position;
    for (let n = 0; n < count; ++n) target = wordBackward(text, target, key === "B");
    return {position: target, kind: "exclusive"};
  }
  case "e": case "E": {
    let target = position;
    for (let n = 0; n < count; ++n) target = wordEnd(text, target, key === "E");
    return {position: target, kind: "inclusive"};
  }
  case "0": case "<Home>": return {position: lineStart(text, position), kind: "exclusive"};
  case "^": return {position: firstNonBlank(text, position), kind: "exclusive"};
  case "$": case "<End>": return {position: toLineEnd(text, position, count).end, kind: "exclusive"};
  case "gg": case "G": {
    const last = lineCount(text) - 1;
    const line = command.explicitCount ? Math.min(count - 1, last) : key === "gg" ? 0 : last;
    return {position: firstNonBlank(text, startOfLine(text, line)), kind: "linewise"};
  }
  case "f": case "F": case "t": case "T": {
    const find = {character: command.character, forward: key === "f" || key === "t", till: key === "t" || key === "T"};
    state.lastFind = find;
    return findMotion(text, position, find, find.forward, count, false);
  }
  case ";": case ",": {
    const find = state.lastFind;
    return find ? findMotion(text, position, find, key === ";" ? find.forward : !find.forward, count, true) : null;
  }
  }
  return null;
}

// Plain j/k follow the lines as displayed, through the owner's view. With an
// operator they take whole text lines, as in Vim.
function vertical(state, text, position, lines, view, operator) {
  if (operator) {
    const line = lineNumber(text, position) + lines;
    if (line < 0 || line >= lineCount(text)) return null;
    return {position: startOfLine(text, line), kind: "linewise"};
  }
  if (view && view.vertical) {
    const moved = view.vertical(position, lines, state.goalX);
    state.goalX = moved.goalX;
    return {position: moved.position, kind: "linewise", vertical: true};
  }
  const line = Math.max(0, Math.min(lineCount(text) - 1, lineNumber(text, position) + lines));
  if (state.goalColumn < 0) state.goalColumn = column(text, position);
  return {position: atColumn(text, startOfLine(text, line), state.goalColumn), kind: "linewise", vertical: true};
}

function resetGoal(state) { state.goalX = -1; state.goalColumn = -1; }

function motionRange(text, position, target) {
  if (target.kind === "linewise") {
    const first = Math.min(position, target.position), last = Math.max(position, target.position);
    return {start: lineStart(text, first), end: lineEnd(text, last), linewise: true};
  }
  const start = Math.min(position, target.position);
  let end = Math.max(position, target.position);
  if (target.kind === "inclusive") end = nextBoundary(text, end);
  if (target.word) {
    // dw on the last word of a line stops at the line break.
    const newline = text.indexOf("\n", start);
    if (newline > start && newline < end) end = newline;
  }
  return {start: start, end: end, linewise: false};
}

function findMotion(text, position, find, forward, count, repeat) {
  const found = findInLine(text, position, find.character, forward, count, find.till, repeat);
  return found < 0 ? null : {position: found, kind: forward ? "inclusive" : "exclusive"};
}

function findInLine(text, position, target, forward, count, till, repeat) {
  const start = lineStart(text, position), end = lineEnd(text, position);
  let from = position;
  // A repeated t or T skips the adjacent match instead of staying put.
  if (till && repeat) from = forward ? Math.min(end, nextBoundary(text, from)) : Math.max(start, previousBoundary(text, from));
  let found = -1;
  for (let n = 0; n < count; ++n) {
    found = -1;
    if (forward) {
      for (let at = nextBoundary(text, from); at < end; at = nextBoundary(text, at))
        if (text.slice(at, nextBoundary(text, at)) === target) { found = at; break; }
    } else {
      for (let at = previousBoundary(text, from); at >= start && at < from; at = previousBoundary(text, at)) {
        if (text.slice(at, nextBoundary(text, at)) === target) { found = at; break; }
        if (at === start) break;
      }
    }
    if (found < 0) return -1;
    from = found;
  }
  if (!till) return found;
  return forward ? previousBoundary(text, found) : nextBoundary(text, found);
}

function forwardInLine(text, position, count) {
  const stop = lineEnd(text, position);
  let end = position;
  for (let n = 0; n < count && end < stop; ++n) end = nextBoundary(text, end);
  return {start: position, end: end, linewise: false};
}

function backwardInLine(text, position, count) {
  const stop = lineStart(text, position);
  let start = position;
  for (let n = 0; n < count && start > stop; ++n) start = previousBoundary(text, start);
  return {start: start, end: position, linewise: false};
}

function toLineEnd(text, position, count) {
  let at = position;
  for (let n = 1; n < count; ++n) {
    const end = lineEnd(text, at);
    if (end >= text.length) break;
    at = end + 1;
  }
  return {start: position, end: lineEnd(text, at), linewise: false};
}

function lineRange(text, position, count) {
  const range = toLineEnd(text, position, count);
  return {start: lineStart(text, position), end: range.end, linewise: true};
}

function linesOf(text, range) {
  return {start: lineStart(text, range.start), end: lineEnd(text, Math.max(range.start, range.end - 1)), linewise: true};
}

function visualRange(state, text) {
  const first = Math.min(state.anchor, state.cursor), last = Math.max(state.anchor, state.cursor);
  if (state.mode === "visual-line") return {start: lineStart(text, first), end: lineEnd(text, last), linewise: true};
  return {start: first, end: Math.min(text.length, nextBoundary(text, last)), linewise: false};
}

// ----------------------------------------------------------------- words

// 0 blank, 1 word characters, 2 punctuation, 3 emoji and other symbols.
function charClass(text, position, big) {
  if (position >= text.length) return 0;
  const point = text.codePointAt(position);
  if (point === 0x20 || point === 0x09 || point === 0x0A || point === 0x0D || point === 0xA0 || point === 0x3000) return 0;
  if (big) return 1;
  if (point === 0x5F || (point >= 0x30 && point <= 0x39)) return 1;
  const character = String.fromCodePoint(point);
  if (character.toLowerCase() !== character.toUpperCase()) return 1;
  if (point < 0xC0 || point === 0xD7 || point === 0xF7) return 2;
  if (point >= 0x2000 && point <= 0x2BFF) return point >= 0x2600 && point <= 0x27BF ? 3 : 2;
  if (point >= 0x3001 && point <= 0x303F) return 2;
  return point > 0xFFFF ? 3 : 1;
}

function isEmptyLine(text, position) {
  return (position === 0 || text[position - 1] === "\n") && (position === text.length || text[position] === "\n");
}

function wordForward(text, position, big) {
  const length = text.length;
  let at = position;
  const kind = charClass(text, at, big);
  if (kind !== 0) while (at < length && charClass(text, at, big) === kind) at = nextBoundary(text, at);
  while (at < length && charClass(text, at, big) === 0) {
    if (at !== position && isEmptyLine(text, at)) return at;
    at = nextBoundary(text, at);
  }
  return at;
}

function wordBackward(text, position, big) {
  let at = previousBoundary(text, position);
  if (at === position) return position;
  while (at > 0 && charClass(text, at, big) === 0) {
    if (isEmptyLine(text, at)) return at;
    at = previousBoundary(text, at);
  }
  const kind = charClass(text, at, big);
  if (kind === 0) return at;
  while (at > 0) {
    const before = previousBoundary(text, at);
    if (charClass(text, before, big) !== kind) break;
    at = before;
  }
  return at;
}

function wordEnd(text, position, big) {
  const length = text.length;
  let at = nextBoundary(text, position);
  while (at < length && charClass(text, at, big) === 0) at = nextBoundary(text, at);
  if (at >= length) return position;
  const kind = charClass(text, at, big);
  let last = at;
  while (at < length && charClass(text, at, big) === kind) { last = at; at = nextBoundary(text, at); }
  return last;
}

function wordEndHere(text, position, big) {
  const kind = charClass(text, position, big);
  let last = position, at = nextBoundary(text, position);
  while (at < text.length && charClass(text, at, big) === kind) { last = at; at = nextBoundary(text, at); }
  return last;
}

// ---------------------------------------------------------- text objects

function objectRange(text, position, object) {
  const around = object[0] === "a";
  switch (object[1]) {
  case "w": return wordObject(text, position, false, around);
  case "W": return wordObject(text, position, true, around);
  case "\"": case "'": case "`": return quoteObject(text, position, object[1], around);
  case "(": case ")": case "b": return bracketObject(text, position, "(", ")", around);
  case "[": case "]": return bracketObject(text, position, "[", "]", around);
  case "{": case "}": case "B": return bracketObject(text, position, "{", "}", around);
  case "<": case ">": return bracketObject(text, position, "<", ">", around);
  }
  return null;
}

function isBlank(character) { return character === " " || character === "\t"; }

function wordObject(text, position, big, around) {
  const start = lineStart(text, position), end = lineEnd(text, position);
  if (start === end) return null;
  const at = clampNormal(text, position);
  const kind = charClass(text, at, big);
  let from = at, to = nextBoundary(text, at);
  while (from > start && charClass(text, previousBoundary(text, from), big) === kind) from = previousBoundary(text, from);
  while (to < end && charClass(text, to, big) === kind) to = nextBoundary(text, to);
  if (!around) return {start: from, end: to, linewise: false};
  if (kind === 0) {
    if (to < end) {
      const next = charClass(text, to, big);
      while (to < end && charClass(text, to, big) === next) to = nextBoundary(text, to);
    }
    return {start: from, end: to, linewise: false};
  }
  let trailing = to;
  while (trailing < end && isBlank(text[trailing])) trailing++;
  if (trailing > to) return {start: from, end: trailing, linewise: false};
  while (from > start && isBlank(text[from - 1])) from--;
  return {start: from, end: to, linewise: false};
}

function quoteObject(text, position, quote, around) {
  const start = lineStart(text, position), end = lineEnd(text, position);
  const quotes = [];
  for (let at = start; at < end; ++at)
    if (text[at] === quote && (at === start || text[at - 1] !== "\\")) quotes.push(at);
  let open = -1, close = -1;
  for (let n = 0; n + 1 < quotes.length; n += 2) {
    if (position <= quotes[n + 1]) { open = quotes[n]; close = quotes[n + 1]; break; }
  }
  if (open < 0) return null;
  if (!around) return {start: open + 1, end: close, linewise: false};
  let from = open, to = close + 1;
  let trailing = to;
  while (trailing < end && isBlank(text[trailing])) trailing++;
  if (trailing > to) to = trailing;
  else while (from > start && isBlank(text[from - 1])) from--;
  return {start: from, end: to, linewise: false};
}

function bracketObject(text, position, open, close, around) {
  let from = -1;
  if (text[position] === open) from = position;
  else {
    let depth = 0;
    for (let at = position - 1; at >= 0; --at) {
      if (text[at] === close) depth++;
      else if (text[at] === open) { if (!depth) { from = at; break; } depth--; }
    }
  }
  if (from < 0) return null;
  let to = -1, depth = 0;
  for (let at = from + 1; at < text.length; ++at) {
    if (text[at] === open) depth++;
    else if (text[at] === close) { if (!depth) { to = at; break; } depth--; }
  }
  if (to < 0) return null;
  if (around) return {start: from, end: to + 1, linewise: false};
  let start = from + 1, end = to;
  // A block written over several lines keeps its brackets on their own
  // lines: its inside is then whole lines, as in Vim.
  const opensLine = text[start] === "\n";
  if (opensLine) start++;
  let before = end;
  while (before > start && isBlank(text[before - 1])) before--;
  const closesLine = before > start && text[before - 1] === "\n";
  if (closesLine) end = before - 1;
  return {start: start, end: Math.max(start, end), linewise: opensLine && closesLine && end > start};
}

// ----------------------------------------------------------------- text

function isExtender(point) {
  return point === 0x200D || point === 0x20E3
    || (point >= 0x0300 && point <= 0x036F) || (point >= 0x1AB0 && point <= 0x1AFF)
    || (point >= 0x1DC0 && point <= 0x1DFF) || (point >= 0x20D0 && point <= 0x20FF)
    || (point >= 0xFE00 && point <= 0xFE0F) || (point >= 0xFE20 && point <= 0xFE2F)
    || (point >= 0x1F3FB && point <= 0x1F3FF) || (point >= 0xE0020 && point <= 0xE007F)
    || (point >= 0xE0100 && point <= 0xE01EF);
}

function isRegional(point) { return point >= 0x1F1E6 && point <= 0x1F1FF; }
function units(point) { return point > 0xFFFF ? 2 : 1; }

// End of the character starting at position: a base code point with its
// combining marks, variation selectors, skin tones and ZWJ continuations,
// or a pair of regional indicators forming a flag.
function nextBoundary(text, position) {
  if (position >= text.length) return text.length;
  const first = text.codePointAt(position);
  let at = position + units(first);
  if (first === 0x0A) return at;
  if (isRegional(first) && at < text.length && isRegional(text.codePointAt(at))) return at + 2;
  while (at < text.length) {
    const point = text.codePointAt(at);
    if (point === 0x200D) {
      at += 1;
      if (at < text.length && text.charCodeAt(at) !== 0x0A) at += units(text.codePointAt(at));
    } else if (isExtender(point)) at += units(point);
    else break;
  }
  return at;
}

// Start of the character containing position.
function characterStart(text, position) {
  if (position <= 0) return 0;
  if (position >= text.length) return text.length;
  // Fast path: a plain character not joined to the previous one.
  if (text.charCodeAt(position) < 0x300 && text.charCodeAt(position - 1) !== 0x200D) return position;
  let at = lineStart(text, position), start = at;
  while (at <= position && at < text.length) { start = at; at = nextBoundary(text, at); }
  return start;
}

function previousBoundary(text, position) {
  if (position <= 0) return 0;
  return characterStart(text, Math.min(position, text.length) - 1);
}

// Normal mode rests on a character, never after the end of a line.
function clampNormal(text, position) {
  const at = Math.max(0, Math.min(position, text.length));
  const start = lineStart(text, at), end = lineEnd(text, at);
  if (end === start) return start;
  return characterStart(text, Math.min(at, end - 1));
}

function lineStart(text, position) { return position <= 0 ? 0 : text.lastIndexOf("\n", position - 1) + 1; }
function lineEnd(text, position) { const end = text.indexOf("\n", position); return end < 0 ? text.length : end; }

function firstNonBlank(text, position) {
  const end = lineEnd(text, position);
  let at = lineStart(text, position);
  while (at < end && isBlank(text[at])) at++;
  return at;
}

function lineNumber(text, position) {
  let line = 0, at = text.indexOf("\n");
  while (at >= 0 && at < position) { line++; at = text.indexOf("\n", at + 1); }
  return line;
}

function lineCount(text) { return lineNumber(text, text.length) + 1; }

function startOfLine(text, line) {
  let at = 0;
  for (let n = 0; n < line; ++n) {
    const end = text.indexOf("\n", at);
    if (end < 0) return at;
    at = end + 1;
  }
  return at;
}

function column(text, position) {
  let count = 0;
  for (let at = lineStart(text, position); at < position; at = nextBoundary(text, at)) count++;
  return count;
}

function atColumn(text, start, wanted) {
  const end = lineEnd(text, start);
  let at = start;
  for (let n = 0; n < wanted && at < end; ++n) at = nextBoundary(text, at);
  return at;
}

// Smallest single replacement turning previous into next, so the owner edits
// the field in place instead of reassigning its text binding.
function diff(previous, next) {
  const shortest = Math.min(previous.length, next.length);
  let start = 0;
  while (start < shortest && previous.charCodeAt(start) === next.charCodeAt(start)) start++;
  if (start > 0 && start < previous.length && isLowSurrogate(previous.charCodeAt(start))) start--;
  let tail = 0;
  while (tail < shortest - start
      && previous.charCodeAt(previous.length - 1 - tail) === next.charCodeAt(next.length - 1 - tail)) tail++;
  if (tail > 0 && isLowSurrogate(previous.charCodeAt(previous.length - tail))
      && previous.length - tail - 1 >= start && isHighSurrogate(previous.charCodeAt(previous.length - tail - 1))) tail--;
  return {start: start, end: previous.length - tail, text: next.slice(start, next.length - tail)};
}

function isHighSurrogate(unit) { return unit >= 0xD800 && unit <= 0xDBFF; }
function isLowSurrogate(unit) { return unit >= 0xDC00 && unit <= 0xDFFF; }
