(() => {
  'use strict';
  const plain = element => element instanceof HTMLTextAreaElement || element instanceof HTMLInputElement;
  function field(element) {
    if (!(element instanceof HTMLElement)) return null;
    if (plain(element)) {
      if (element.disabled || element.readOnly || element instanceof HTMLInputElement && !['text', 'search', 'url', 'tel'].includes(element.type)) return null;
      if (/(?:password|one-time-code|cc-number|cc-csc)/i.test(element.autocomplete || '')) return null;
      return element;
    }
    if (!element.isContentEditable || element.closest('[aria-readonly="true"]')) return null;
    while (element.parentElement?.isContentEditable) element = element.parentElement;
    return element;
  }
  function active() {
    let element = document.activeElement;
    while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement;
    return field(element);
  }
  function layout(target) {
    let text = '';
    const segments = [];
    function newline() { if (text && !text.endsWith('\n')) text += '\n'; }
    function walk(node) {
      if (text.length > 128000) throw Error('Ce champ est trop long.');
      if (node.nodeType === Node.TEXT_NODE) {
        segments.push({node, start: text.length, end: text.length + node.data.length}); text += node.data; return;
      }
      if (!(node instanceof Element) || node !== target && (node.getAttribute('contenteditable') === 'false' || node.hidden)
          || ['SCRIPT', 'STYLE', 'TEMPLATE'].includes(node.tagName)) return;
      if (node.tagName === 'BR') { text += '\n'; return; }
      const style = getComputedStyle(node);
      if (style.display === 'none' || style.visibility === 'hidden') return;
      const block = node !== target && ['block', 'list-item', 'table-row'].includes(style.display);
      if (block) newline();
      for (const child of node.childNodes) walk(child);
      if (block) newline();
    }
    walk(target);
    return {text, segments};
  }
  function selectionFor(target) { return target.getRootNode().getSelection?.() || window.getSelection(); }
  function offsetAt(map, node, offset) {
    const segment = map.segments.find(s => s.node === node);
    if (segment) return segment.start + offset;
    const point = document.createRange(); point.setStart(node, offset); point.collapse(true);
    for (const s of map.segments) if (point.comparePoint(s.node, 0) >= 0) return s.start;
    return map.text.length;
  }
  function capture(target) {
    if (!target?.isConnected || field(target) !== target) throw Error('Place le curseur dans un champ de texte modifiable.');
    let text, start, end, map = null, fingerprint = null;
    if (plain(target)) {
      text = target.value; start = target.selectionStart; end = target.selectionEnd;
      if (typeof start !== 'number' || typeof end !== 'number') throw Error('Ce type de champ ne permet pas la correction.');
    } else {
      map = layout(target); text = map.text; fingerprint = target.innerHTML;
      const selection = selectionFor(target);
      if (!selection?.rangeCount) throw Error('Place le curseur dans le texte à corriger.');
      const range = selection.getRangeAt(0);
      if (!target.contains(range.startContainer) || !target.contains(range.endContainer)) throw Error('La sélection dépasse le champ de texte.');
      start = offsetAt(map, range.startContainer, range.startOffset);
      end = offsetAt(map, range.endContainer, range.endOffset);
    }
    const selected = start !== end;
    return {target, text, start: selected ? start : 0, end: selected ? end : text.length,
      caretStart: start, caretEnd: end, map, fingerprint, source: selected ? text.slice(start, end) : text};
  }
  function unchanged(snapshot, checkSelection = true, requireWindowFocus = true) {
    try {
      if (active() !== snapshot.target || requireWindowFocus && !document.hasFocus()) return false;
      const now = capture(snapshot.target);
      return now.text === snapshot.text && now.fingerprint === snapshot.fingerprint
        && (!checkSelection || now.caretStart === snapshot.caretStart && now.caretEnd === snapshot.caretEnd);
    } catch { return false; }
  }
  function utf16(text, codepoints) { return Array.from(text).slice(0, codepoints).join('').length; }
  function plan(snapshot, result) {
    if (typeof result?.text !== 'string' || !Array.isArray(result.edits) || result.edits.length > 100) throw Error('Réponse de correction invalide.');
    let source = snapshot.source, previous = 0;
    const length = Array.from(source).length;
    const edits = result.edits.map(edit => {
      if (!Number.isInteger(edit.start) || !Number.isInteger(edit.end) || edit.start < previous || edit.end < edit.start
          || edit.end > length || typeof edit.replacement !== 'string' || edit.replacement.length > 100) throw Error('Correction invalide.');
      previous = edit.end;
      return {start: snapshot.start + utf16(source, edit.start), end: snapshot.start + utf16(source, edit.end), replacement: edit.replacement};
    });
    for (const edit of [...edits].reverse()) source = source.slice(0, edit.start - snapshot.start) + edit.replacement + source.slice(edit.end - snapshot.start);
    if (source !== result.text) throw Error('Correction incohérente, texte conservé.');
    return edits;
  }
  function adjusted(offset, edits) {
    let delta = 0;
    for (const edit of edits) {
      if (offset >= edit.end) delta += edit.replacement.length - (edit.end - edit.start);
      else if (offset > edit.start) return edit.start + delta + edit.replacement.length;
    }
    return offset + delta;
  }
  function setSelection(target, start, end) {
    if (active() !== target) return;
    if (plain(target)) { target.setSelectionRange(start, end); return; }
    const map = layout(target);
    function point(offset) {
      for (const s of map.segments) if (offset <= s.end) return [s.node, Math.max(0, offset - s.start)];
      const last = map.segments.at(-1); return last ? [last.node, last.node.length] : [target, 0];
    }
    const range = document.createRange(); range.setStart(...point(start)); range.setEnd(...point(end));
    const selection = selectionFor(target); selection.removeAllRanges(); selection.addRange(range);
  }
  function apply(snapshot, edits, restoreSelection = null, requireWindowFocus = true) {
    if (!unchanged(snapshot, false, requireWindowFocus)) throw Error('Le champ ou le texte a changé : correction annulée.');
    const target = snapshot.target;
    let after = snapshot.text, delta = 0;
    const inverse = edits.map(edit => {
      const start = edit.start + delta;
      delta += edit.replacement.length - (edit.end - edit.start);
      return {start, end: start + edit.replacement.length, replacement: snapshot.text.slice(edit.start, edit.end)};
    });
    for (const edit of [...edits].reverse()) after = after.slice(0, edit.start) + edit.replacement + after.slice(edit.end);
    const patches = [];
    if (!plain(target)) {
      for (const edit of edits) {
        const segment = snapshot.map.segments.find(s => edit.start >= s.start && edit.end <= s.end);
        if (!segment) throw Error('Cette mise en forme demande une correction manuelle. Le texte est conservé.');
        patches.push({node: segment.node, start: edit.start - segment.start, length: edit.end - edit.start, text: edit.replacement});
      }
    } else if (target.maxLength >= 0 && after.length > target.maxLength) throw Error('La correction dépasserait la longueur autorisée.');
    const before = new InputEvent('beforeinput', {bubbles: true, composed: true, cancelable: true, inputType: 'insertReplacementText'});
    if (!target.dispatchEvent(before) || !unchanged(snapshot, false, requireWindowFocus)) throw Error('Cet éditeur a refusé la modification.');
    if (plain(target)) {
      const prototype = target instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      Object.getOwnPropertyDescriptor(prototype, 'value').set.call(target, after);
    } else {
      for (const patch of patches.reverse()) patch.node.replaceData(patch.start, patch.length, patch.text);
    }
    const positions = restoreSelection || [adjusted(snapshot.caretStart, edits), adjusted(snapshot.caretEnd, edits)];
    setSelection(target, ...positions);
    target.dispatchEvent(new InputEvent('input', {bubbles: true, composed: true, inputType: 'insertReplacementText'}));
    const current = capture(target);
    if (current.text !== after) throw Error('Cet éditeur a modifié le résultat. Vérifie le texte affiché.');
    return {snapshot: current, inverse, selection: [snapshot.caretStart, snapshot.caretEnd]};
  }
  globalThis.QwenEditor = Object.freeze({active, field, capture, unchanged, plan, apply});
})();
