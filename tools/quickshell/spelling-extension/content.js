(() => {
  'use strict';
  const editor = globalThis.QwenEditor;
  let busy = false, undo = null, reportId = '', provider = 'qwen', cancelReview = null, reviewKey = '';
  const request = (action, extra = {}) => chrome.runtime.sendMessage({action, text: '', provider, reportId, ...extra});
  function status(text, state = 'error') { void request('status', {text, status: state}).catch(() => {}); }
  async function correct(target, selectedProvider) {
    if (busy) return;
    provider = selectedProvider; reportId = crypto.randomUUID();
    let observer, cancelled = false;
    const cancel = () => {
      if (cancelled) return;
      cancelled = true;
      void request('decide', {status:'reject'}).catch(() => {});
    };
    const focus = () => { if (editor.active() !== target) cancel(); };
    try {
      const snapshot = editor.capture(target);
      if (!snapshot.source.trim()) return;
      if (new TextEncoder().encode(snapshot.source).length > 8000) { status('Sélectionne un passage de moins de 8 Ko.'); return; }
      busy = true; cancelReview = cancel;
      window.addEventListener('pagehide', cancel, {once:true});
      target.addEventListener('input', cancel, true);
      document.addEventListener('focusin', focus, true);
      observer = new MutationObserver(cancel); observer.observe(target, {subtree: true, characterData: true, childList: true});
      const response = await request('correct', {text:snapshot.source, review:true});
      if (cancelled || response?.result?.cancelled) { await request('decide', {status:'reject'}); return; }
      if (!response?.ok) throw Error(response?.error || 'Le moteur n’a pas répondu.');
      if (response.result.reportId !== reportId) throw Error('La prévisualisation de correction a changé.');
      const edits = editor.plan(snapshot, response.result);
      // Wait for Enter in the source field or in Quickshell. Merely displaying
      // a model response never authorizes a change to the page.
      let decision = '';
      while (!cancelled && !decision) {
        const review = await request('wait');
        if (!review?.ok) throw Error(review?.error || 'La prévisualisation est indisponible.');
        decision = review.result?.decision || '';
      }
      if (cancelled || decision !== 'accept') return;
      // Quickshell can own keyboard focus while reviewing. The same editable
      // element, text, DOM and caret must still be intact in this page.
      if (!editor.unchanged(snapshot, true, false)) { status('Le texte ou le curseur a changé : propositions non appliquées.', 'cancelled'); return; }
      if (!edits.length) { status('', 'unchanged'); return; }
      observer.disconnect(); target.removeEventListener('input', cancel, true);
      undo = {...editor.apply(snapshot, edits, null, false), reportId, provider};
      status('', 'applied');
    } catch (error) {
      if (!cancelled) status(error.message || 'Correction indisponible.');
    } finally {
      busy = false; cancelReview = null; observer?.disconnect(); target.removeEventListener('input', cancel, true);
      document.removeEventListener('focusin', focus, true);
      window.removeEventListener('pagehide', cancel);
    }
  }
  document.addEventListener('keydown', event => {
    if (!event.isTrusted || event.isComposing) return;
    if (reviewKey === event.key) { event.preventDefault(); event.stopImmediatePropagation(); return; }
    if (busy && !event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey && ['Enter','Escape'].includes(event.key)) {
      event.preventDefault(); event.stopImmediatePropagation();
      reviewKey = event.key;
      if (!event.repeat) {
        if (event.key === 'Escape') cancelReview?.();
        else void request('decide', {status:'accept'}).catch(() => {});
      }
      return;
    }
    if (event.repeat || !event.altKey || event.metaKey || event.key !== 'Tab') return;
    const target = editor.active();
    if (!target) return;
    event.preventDefault(); event.stopImmediatePropagation();
    if (!event.shiftKey) { void correct(target, event.ctrlKey ? 'qwen' : 'openai'); return; }
    if (busy) return;
    if (!undo || undo.snapshot.target !== target || !editor.unchanged(undo.snapshot, false)) { status('Aucune correction inchangée à annuler dans ce champ.'); return; }
    try { editor.apply(editor.capture(target), undo.inverse, undo.selection); reportId = undo.reportId; provider = undo.provider; undo = null; status('Texte original restauré.', 'undone'); }
    catch (error) { status(error.message); }
  }, true);
  document.addEventListener('keyup', event => {
    if (event.isTrusted && event.key === reviewKey) { reviewKey = ''; event.preventDefault(); event.stopImmediatePropagation(); }
  }, true);
})();
