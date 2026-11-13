const HOST = 'com.quickshell.spelling';

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.id !== chrome.runtime.id || !sender.tab || !['correct', 'status', 'decide', 'wait'].includes(message?.action)
      || typeof message.text !== 'string' || new TextEncoder().encode(message.text).length > 8000
      || !['qwen', 'openai'].includes(message.provider)) return false;
  // Proofreading and its explicit review; no general shell or chat access.
  chrome.runtime.sendNativeMessage(HOST, {action: message.action, text: message.text, provider: message.provider,
    reportId: message.reportId, status: message.status, review: message.review}, result => {
    const error = chrome.runtime.lastError;
    if (error) reply({ok: false, error: 'Le moteur local est indisponible. Applique la configuration NixOS et vérifie Ollama.'});
    else reply(result);
  });
  return true;
});
