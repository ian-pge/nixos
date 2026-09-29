import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// Pure checks of the Vim editing core; no Qt is involved.
const context = vm.createContext({});
vm.runInContext(readFileSync(new URL("../ui/VimCore.js", import.meta.url), "utf8")
  .replace(/^\.(?:pragma|import).*$/gm, ""), context);
const core = context;
const plain = value => JSON.parse(JSON.stringify(value));

const named = {
  "<Esc>": {key: "Escape"}, "<CR>": {key: "Return"}, "<S-CR>": {key: "Return", shift: true},
  "<BS>": {key: "Backspace"}, "<Del>": {key: "Delete"}, "<Left>": {key: "Left"}, "<Right>": {key: "Right"},
  "<Up>": {key: "Up"}, "<Down>": {key: "Down"}, "<C-r>": {key: "r", ctrl: true, text: "\u0012"},
  "<C-v>": {key: "v", ctrl: true, text: "\u0016"}, "<latch>": {key: "", text: ""}
};

// A field that behaves like Qt's: unhandled insert-mode keys type text.
function editor(text, cursor, mode = "normal", options = {}) {
  const state = core.create(options);
  if (mode === "normal") state.mode = "normal";
  const field = {state, text, cursor, selection: null, copies: [], submits: 0, passed: []};
  field.press = (...sequence) => {
    for (const item of sequence) {
      const keys = item.match(/<(?:[A-Z][A-Za-z-]*|latch)>|[\s\S]/gu).flatMap(key => named[key] || key.length < 2 ? [key] : Array.from(key));
      for (const key of keys) {
        const input = named[key] || {text: key, key: ""};
        const result = core.handleKey(field.state, {text: field.text, cursor: field.cursor}, input, field.view);
        if (!result.handled) {
          field.passed.push(key);
          if (field.state.mode === "insert" && input.text && !input.ctrl && input.key !== "Return") {
            field.text = field.text.slice(0, field.cursor) + input.text + field.text.slice(field.cursor);
            field.cursor += input.text.length;
          }
          continue;
        }
        if (result.text !== undefined) field.text = result.text;
        field.cursor = result.cursor;
        field.selection = result.selection ? plain(result.selection) : null;
        if (result.copy !== undefined) field.copies.push(result.copy);
        if (result.submit) field.submits++;
      }
    }
    return field;
  };
  field.selected = () => field.selection ? field.text.slice(field.selection.start, field.selection.end) : "";
  return field;
}
function check(text, cursor, keys, expectedText, expectedCursor, options) {
  const field = editor(text, cursor, "normal", options).press(...keys);
  assert.equal(field.text, expectedText, JSON.stringify(keys) + " text");
  if (expectedCursor !== undefined) assert.equal(field.cursor, expectedCursor, JSON.stringify(keys) + " cursor");
  return field;
}

// Modes: Escape leaves insert one character to the left, then belongs to the owner.
{
  const field = editor("hello", 5, "insert").press("<Esc>");
  assert.equal(field.state.mode, "normal"); assert.equal(field.cursor, 4);
  field.press("<Esc>");
  assert.deepEqual(field.passed, ["<Esc>"]);
  assert.equal(editor("ab\ncd", 3, "insert").press("<Esc>").cursor, 3);
  const typed = editor("", 0, "insert").press("salut", "<Esc>");
  assert.equal(typed.text, "salut"); assert.equal(typed.cursor, 4);
}

// Character motions stay inside the line and step over whole characters.
check("abc\ndef", 1, ["h", "h", "h"], "abc\ndef", 0);
check("abc\ndef", 1, ["l", "l", "l"], "abc\ndef", 2);
check("  indent", 7, ["^"], "  indent", 2);
check("  indent", 7, ["0"], "  indent", 0);
check("one\ntwo three", 4, ["$"], "one\ntwo three", 12);
check("a👩🏽‍💻b", 0, ["l"], "a👩🏽‍💻b", 1);
check("a👩🏽‍💻b", 0, ["l", "l"], "a👩🏽‍💻b", 1 + "👩🏽‍💻".length);
check("a👩🏽‍💻b", 1, ["x"], "ab", 1);
check("🇫🇷🇧🇪", 0, ["x"], "🇧🇪", 0);
check("été", 0, ["x"], "té", 0);

// Word motions treat accented letters as word characters and punctuation apart.
check("déjà-vu, très bien", 0, ["w"], "déjà-vu, très bien", 4);
check("déjà-vu, très bien", 0, ["W"], "déjà-vu, très bien", 9);
check("déjà-vu, très bien", 0, ["e"], "déjà-vu, très bien", 3);
check("déjà-vu, très bien", 0, ["E"], "déjà-vu, très bien", 7);
check("déjà-vu, très bien", 14, ["b"], "déjà-vu, très bien", 9);
check("déjà-vu, très bien", 14, ["B"], "déjà-vu, très bien", 9);
check("one two\n\nthree", 4, ["w"], "one two\n\nthree", 8);
check("one two\n\nthree", 4, ["w", "w"], "one two\n\nthree", 9);
check("one two three", 0, ["2w"], "one two three", 8);

// Vertical motions without a display keep the column across text lines.
check("abcdef\nab\nabcdef", 4, ["j"], "abcdef\nab\nabcdef", 8);
check("abcdef\nab\nabcdef", 4, ["j", "j"], "abcdef\nab\nabcdef", 14);
check("a\nb\nc\nd", 0, ["G"], "a\nb\nc\nd", 6);
check("a\nb\nc\nd", 6, ["gg"], "a\nb\nc\nd", 0);
check("a\nb\nc\nd", 0, ["3G"], "a\nb\nc\nd", 4);

// A display view drives plain j/k; operators still take whole lines.
{
  const field = editor("a long wrapped line", 2);
  const calls = [];
  field.view = {vertical: (position, lines, goalX) => { calls.push([position, lines, goalX]); return {position: position + 7 * lines, goalX: 42}; }};
  field.press("j");
  assert.equal(field.cursor, 9);
  field.press("j");
  assert.deepEqual(calls, [[2, 1, -1], [9, 1, 42]]);
  field.press("l", "j");
  assert.equal(calls[2][2], -1);
  const lines = editor("one\ntwo\nthree", 0);
  lines.view = field.view;
  lines.press("dj");
  assert.equal(lines.text, "three");
}

// Find motions within the line, with ; and , repeats.
check("a,b,c,d", 0, ["f,"], "a,b,c,d", 1);
check("a,b,c,d", 0, ["2f,"], "a,b,c,d", 3);
check("a,b,c,d", 0, ["f,", ";"], "a,b,c,d", 3);
check("a,b,c,d", 0, ["f,", ";", ","], "a,b,c,d", 1);
check("a,b,c,d", 0, ["t,", ";"], "a,b,c,d", 2);
check("a,b,c,d", 6, ["F,"], "a,b,c,d", 5);
check("a,b,c,d", 6, ["T,"], "a,b,c,d", 6);
check("a,b\nc,d", 0, ["2f,"], "a,b\nc,d", 0);

// Operators with motions, counts and the Vim special cases.
check("one two three", 0, ["dw"], "two three", 0);
check("one two three", 0, ["d2w"], "three", 0);
check("one two three", 0, ["2dw"], "three", 0);
check("one two\nthree", 4, ["dw"], "one \nthree", 3);
check("one two three", 0, ["cw", "ONE", "<Esc>"], "ONE two three", 2);
check("one two three", 0, ["c2w", "X", "<Esc>"], "X three", 0);
check("one two three", 4, ["d$"], "one ", 3);
check("one two three", 4, ["D"], "one ", 3);
check("one two three", 4, ["C", "end", "<Esc>"], "one end", 6);
check("one two three", 8, ["db"], "one three", 4);
check("one two three", 0, ["de"], " two three", 0);
check("a,b,c", 0, ["dt,"], ",b,c", 0);
check("a,b,c", 0, ["df,"], "b,c", 0);
check("a,b,c", 0, ["ct,", "Z", "<Esc>"], "Z,b,c", 0);
check("abcdef", 1, ["3x"], "aef", 1);
check("abc", 2, ["5x"], "ab", 1);
check("abcdef", 4, ["2X"], "abef", 2);
check("abc", 1, ["s", "Z", "<Esc>"], "aZc", 1);
check("abc", 1, ["dh"], "bc", 0);

// Linewise operators.
check("one\ntwo\nthree", 4, ["dd"], "one\nthree", 4);
check("one\ntwo\nthree", 8, ["dd"], "one\ntwo", 4);
check("one\ntwo\nthree", 0, ["2dd"], "three", 0);
check("one\ntwo\nthree", 0, ["9dd"], "", 0);
check("one\ntwo\nthree", 4, ["dk"], "three", 0);
check("one\ntwo", 4, ["dj"], "one\ntwo", 4);
check("one\n  two\nthree", 0, ["dj"], "three", 0);
check("one\ntwo", 4, ["cc", "new", "<Esc>"], "one\nnew", 6);
check("one\ntwo", 0, ["S", "x", "<Esc>"], "x\ntwo", 0);
check("one\ntwo\nthree", 0, ["dG"], "", 0);
check("one\ntwo\nthree", 8, ["dgg"], "", 0);

// Yank and paste, charwise and linewise, with the clipboard mirror.
{
  const field = check("one\ntwo", 0, ["yy", "p"], "one\none\ntwo", 4);
  assert.deepEqual(field.copies, ["one"]);
  check("one\ntwo", 4, ["yy", "P"], "one\ntwo\ntwo", 4);
  check("one\ntwo", 0, ["yy", "2p"], "one\none\none\ntwo", 4);
  check("ab", 0, ["x", "p"], "ba", 1);
  check("ab", 1, ["x", "P"], "ba", 0);
  check("one two", 0, ["yw", "P"], "one one two", 3);
  const yank = check("one two", 4, ["yiw"], "one two", 4);
  assert.deepEqual(yank.copies, ["two"]);
  const rest = check("one two", 0, ["Y"], "one two", 0);
  assert.deepEqual(rest.copies, ["one two"]);
  const deleted = check("one two", 0, ["dw"], "two", 0);
  assert.deepEqual(deleted.copies, []);
  check("one two", 0, ["dw", "$", "p"], "twoone ", 6);
}

// Text objects.
check("say hello world", 5, ["diw"], "say  world", 4);
check("say hello world", 5, ["daw"], "say world", 4);
check("say hello", 5, ["daw"], "say", 2);
check("say hello world", 5, ["ciw", "bye", "<Esc>"], "say bye world", 6);
check("a déjà-vu b", 3, ["diW"], "a  b", 2);
check('say "hi there" now', 7, ['di"'], 'say "" now', 5);
check('say "hi there" now', 0, ['ci"', "yo", "<Esc>"], 'say "yo" now', 6);
check('say "hi" now', 6, ['da"'], "say now", 4);
check("f(a, (b), c)", 6, ["di("], "f(a, (), c)", 6);
check("f(a, (b), c)", 2, ["dib"], "f()", 2);
check("f(a, (b), c)", 2, ["da("], "f", 0);
check("x[1, 2]", 3, ["di["], "x[]", 2);
check("{\n  a\n}", 4, ["di{"], "{\n}", 2);
check("{\n  a\n}", 4, ["ci{", "b", "<Esc>"], "{\nb\n}", 2);
check("<b>", 1, ["ci<", "i", "<Esc>"], "<i>", 1);
check("no brackets", 2, ["di("], "no brackets", 2);

// Single-character edits.
check("abc", 0, ["rx"], "xbc", 0);
check("abc", 0, ["3rx"], "xxx", 2);
check("abc", 0, ["4rx"], "abc", 0);
check("abc", 1, ["r<CR>"], "a\nc", 2);
check("abc", 0, ["r<Esc>"], "abc", 0);
check("aBc", 0, ["~"], "ABc", 1);
check("aBc", 0, ["3~"], "AbC", 2);
check("one\n  two\nthree", 0, ["J"], "one two\nthree", 3);
check("one\ntwo\nthree", 0, ["3J"], "one two three", 7);
check("one \ntwo", 0, ["J"], "one two", 4);
check("one\n)", 0, ["J"], "one)", 3);
check("one", 0, ["J"], "one", 0);

// Entering insert mode.
check("abc", 1, ["i", "X", "<Esc>"], "aXbc", 1);
check("abc", 1, ["a", "X", "<Esc>"], "abXc", 2);
check("  abc", 4, ["I", "X", "<Esc>"], "  Xabc", 2);
check("abc", 0, ["A", "X", "<Esc>"], "abcX", 3);
check("one\ntwo", 0, ["o", "X", "<Esc>"], "one\nX\ntwo", 4);
check("one\ntwo", 4, ["O", "X", "<Esc>"], "one\nX\ntwo", 4);
check("", 0, ["a", "X", "<Esc>"], "X", 0);
check("one", 0, ["o"], "one", 0, {multiline: false});
check("one", 0, ["J"], "one", 0, {multiline: false});

// Visual modes.
{
  const field = editor("one two three", 4).press("v", "e");
  assert.equal(field.state.mode, "visual"); assert.equal(field.selected(), "two");
  field.press("y");
  assert.equal(field.state.mode, "normal"); assert.deepEqual(field.copies, ["two"]); assert.equal(field.cursor, 4);
  check("one two three", 4, ["ve", "d"], "one  three", 4);
  check("one two three", 4, ["viw", "c", "2", "<Esc>"], "one 2 three", 4);
  const swapped = editor("one two", 2).press("v", "b", "o");
  assert.equal(swapped.cursor, 2); assert.equal(swapped.selected(), "one");
  check("one\ntwo\nthree", 4, ["V", "j", "d"], "one", 0);
  check("one\ntwo", 0, ["V", "y", "j", "p"], "one\ntwo\none", 8);
  check("one two", 0, ["yiw", "w", "viw", "p"], "one one", 6);
  check("one two", 0, ["yiw", "w", "viw", "p", "0", "viw", "p"], "two one", 2);
  check("one two", 0, ["yiw", "w", "viw", "P", "0", "viw", "P"], "one one", 2);
  check("Hello World", 0, ["v", "$", "~"], "hELLO wORLD", 0);
  check("Hello World", 0, ["v", "$", "u"], "hello world", 0);
  check("Hello World", 0, ["v", "e", "U"], "HELLO World", 0);
  check("one\ntwo\nthree", 0, ["V", "j", "J"], "one two\nthree", 3);
  const lines = editor("one\ntwo", 1).press("V");
  assert.equal(lines.selected(), "one");
  lines.press("v"); assert.equal(lines.state.mode, "visual"); assert.equal(lines.selected(), "n");
  lines.press("<Esc>"); assert.equal(lines.state.mode, "normal"); assert.equal(lines.selection, null);
}

// Undo and redo: one step per command and per insert session.
{
  const field = check("one two three", 0, ["dw", "dw"], "three", 0);
  field.press("u"); assert.equal(field.text, "two three");
  field.press("u"); assert.equal(field.text, "one two three"); assert.equal(field.cursor, 0);
  field.press("u"); assert.equal(field.text, "one two three");
  field.press("<C-r>"); assert.equal(field.text, "two three");
  field.press("<C-r>", "<C-r>"); assert.equal(field.text, "three");
  const session = check("one two", 4, ["cw", "deux", "<Esc>", "u"], "one two", 4);
  session.press("<C-r>"); assert.equal(session.text, "one deux");
  check("abc", 0, ["rx", "u"], "abc", 0);
  check("abc", 0, ["i", "<Esc>", "x", "u"], "abc", 0);
  const branch = check("abc", 0, ["x", "u", "x", "<C-r>"], "bc", 0);
  assert.equal(branch.state.redo.length, 0);
  const reset = editor("keep", 0);
  reset.press("x"); core.reset(reset.state, {text: reset.text, cursor: 0});
  assert.equal(reset.state.mode, "insert"); reset.press("<Esc>", "u"); assert.equal(reset.text, "eep");
}

// Enter submits outside insert mode and returns to insert; Shift+Enter is inert.
{
  const field = editor("hello", 2).press("<S-CR>");
  assert.equal(field.submits, 0); assert.equal(field.state.mode, "normal");
  field.press("<CR>");
  assert.equal(field.submits, 1); assert.equal(field.state.mode, "insert");
  assert.deepEqual(editor("hi", 0, "insert").press("<CR>").passed, ["<CR>"]);
}

// Unknown keys are swallowed, bare level latches keep a pending command,
// Ctrl combinations other than redo pass through to the owner.
{
  check("one two", 0, ["z"], "one two", 0);
  check("one two", 0, ["d", "z", "w"], "one two", 4);
  check("one two", 0, ["d", "<latch>", "w"], "two", 0);
  check("one two", 0, ["é", "x"], "ne two", 0);
  const passed = editor("one", 0).press("<C-v>", "<latch>");
  assert.deepEqual(passed.passed, ["<C-v>", "<latch>"]);
  check("one two", 0, ["d", "<Esc>", "w"], "one two", 4);
}

// Search: / builds a plain, case-insensitive pattern; Enter jumps after the
// cursor with wrap-around; n and N repeat; nothing here edits the text.
{
  const field = editor("Salut toi, salut moi", 3).press("/");
  assert.deepEqual(plain(field.state.search), {pattern: ""});
  field.press("SAL");
  assert.equal(field.state.search.pattern, "SAL"); assert.equal(field.cursor, 3);
  assert.equal(field.text, "Salut toi, salut moi");
  field.press("<CR>");
  assert.equal(field.state.search, null); assert.equal(field.cursor, 11); assert.equal(field.state.lastSearch, "SAL");
  field.press("n"); assert.equal(field.cursor, 0);
  field.press("n"); assert.equal(field.cursor, 11);
  field.press("N"); assert.equal(field.cursor, 0);
  field.press("N"); assert.equal(field.cursor, 11);
  field.press("2n"); assert.equal(field.cursor, 11);
  field.press("/", "<CR>"); assert.equal(field.cursor, 0);
  const cancelled = editor("abc abc", 0).press("/", "abc", "<Esc>");
  assert.equal(cancelled.state.search, null); assert.equal(cancelled.cursor, 0); assert.equal(cancelled.state.lastSearch, "");
  const erased = editor("abc", 0).press("/", "ab", "<BS>");
  assert.equal(erased.state.search.pattern, "a");
  erased.press("<BS>", "<BS>"); assert.equal(erased.state.search, null);
  const missing = editor("abc", 1).press("/", "zz", "<CR>");
  assert.equal(missing.cursor, 1); assert.equal(missing.state.lastSearch, "zz");
  check("a.b axb", 0, ["/", "x", "<CR>"], "a.b axb", 5);
  check("axb a.b", 0, ["/", ".", "<CR>"], "axb a.b", 5);
  check("été ÉTÉ", 0, ["/", "été", "<CR>"], "été ÉTÉ", 4);
  check("one two", 0, ["/", "two", "<CR>", "dw"], "one ", 3);
  check("abc", 0, ["n", "N"], "abc", 0);
  check("abc", 0, ["d/"], "abc", 0);
  const typing = editor("x", 0).press("/", "<C-v>", "<latch>", "y");
  assert.deepEqual(typing.passed, ["<C-v>", "<latch>"]); assert.equal(typing.state.search.pattern, "y");
  const reset = editor("abc", 0).press("/", "a");
  core.reset(reset.state, {text: reset.text, cursor: 0}); assert.equal(reset.state.search, null);
}
assert.deepEqual(plain(core.searchMatches("Abc abc ABC", "abc")), [{start: 0, end: 3}, {start: 4, end: 7}, {start: 8, end: 11}]);
assert.deepEqual(plain(core.searchMatches("abc", "")), []);
assert.equal(core.nextMatch("ab ab ab", "ab", 3, true), 6);
assert.equal(core.nextMatch("ab ab ab", "ab", 6, true), 0);
assert.equal(core.nextMatch("ab ab ab", "ab", 3, false), 0);
assert.equal(core.nextMatch("ab ab ab", "ab", 0, false), 6);
assert.equal(core.nextMatch("ab", "zz", 0, true), -1);

// Outside edits drop history that no longer matches.
{
  const field = check("one two", 0, ["dw"], "two", 0);
  field.text = "changed"; core.forget(field.state);
  field.press("u"); assert.equal(field.text, "changed");
}

// Characters, clamping and minimal replacements.
assert.equal(core.clampNormal("abc\n\nx", 3), 2);
assert.equal(core.clampNormal("abc\n\nx", 4), 4);
assert.equal(core.nextBoundary("👩🏽‍💻!", 0), "👩🏽‍💻".length);
assert.equal(core.previousBoundary("a👩🏽‍💻", 1 + "👩🏽‍💻".length), 1);
assert.deepEqual(plain(core.diff("one two", "one 2")), {start: 4, end: 7, text: "2"});
assert.deepEqual(plain(core.diff("abc", "abc")), {start: 3, end: 3, text: ""});
assert.deepEqual(plain(core.diff("x😀y", "x😁y")), {start: 1, end: 3, text: "😁"});
assert.deepEqual(plain(core.diff("😀", "😀😀")), {start: 2, end: 2, text: "😀"});
{
  for (const [before, after] of [["x😀y", "x😁y"], ["😀a", "😁a"], ["a😀", "a😁"], ["", "abc"], ["abc", ""]]) {
    const change = core.diff(before, after);
    assert.equal(before.slice(0, change.start) + change.text + before.slice(change.end), after);
  }
}

console.log("vim core: all checks passed");
