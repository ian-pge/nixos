// Pure protocol and formatting checks; no CLI is started and nothing leaves the machine.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const limits = vm.createContext({});
vm.runInContext(readFileSync(new URL("../features/usage/UsageLimits.js", import.meta.url), "utf8")
  .replace(/^\.(?:pragma|import).*$/gm, ""), limits);
const plain = value => JSON.parse(JSON.stringify(value));
const hour = 3600000, day = 24 * hour;

// Claude Code: initialize, then one get_usage request that skips the transcript scan.
const claudeContext = {};
const [initialize] = plain(limits.claude.opening());
assert.deepEqual(initialize, { type: "control_request", request_id: limits.claudeInitializeId,
  request: { subtype: "initialize" } });
for (const noise of [null, "text", { type: "system", subtype: "hook_started" },
  { type: "control_response", response: { request_id: "someone-else", subtype: "success" } }])
  assert.equal(limits.claude.step(noise, claudeContext), null, "Unrelated output is ignored");
const next = plain(limits.claude.step({ type: "control_response", response: { subtype: "success",
  request_id: limits.claudeInitializeId, response: { account: { subscriptionType: "Claude Max",
  email: "private@example.org" } } } }, claudeContext));
assert.deepEqual(next, { send: [{ type: "control_request", request_id: limits.claudeUsageId,
  request: { subtype: "get_usage", skip_behaviors: true } }] });
assert.deepEqual(plain(claudeContext), { plan: "Claude Max" }, "Only the plan is kept from the account");

// Shape returned by Claude Code 2.1.283 (identifiers and unrelated fields removed).
const usage = {
  subscription_type: "max", rate_limits_available: true, behaviors: null,
  rate_limits: {
    five_hour: { utilization: 3, resets_at: "2026-09-28T18:30:00.153503+00:00" },
    seven_day: { utilization: 10, resets_at: "2026-10-02T10:00:00.153524+00:00" },
    limits: [
      { kind: "session", group: "session", percent: 3, severity: "normal",
        resets_at: "2026-09-28T18:30:00.153503+00:00", scope: null, is_active: false },
      { kind: "weekly_all", group: "weekly", percent: 10, severity: "normal",
        resets_at: "2026-10-02T10:00:00.153524+00:00", scope: null, is_active: false },
      { kind: "weekly_scoped", group: "weekly", percent: 15, severity: "normal",
        resets_at: "2026-10-02T10:00:00.153695+00:00",
        scope: { model: { id: null, display_name: "Fable" }, surface: null }, is_active: true },
      { kind: "future_kind", percent: null, resets_at: null }
    ],
    model_scoped: [{ display_name: "Fable", utilization: 15, resets_at: "2026-10-02T10:00:00+00:00" }]
  }
};
const claude = plain(limits.claude.step({ type: "control_response", response: { subtype: "success",
  request_id: limits.claudeUsageId, response: usage } }, claudeContext));
assert.equal(claude.done, true);
assert.equal(claude.error, "");
assert.equal(claude.snapshot.plan, "Claude Max");
assert.deepEqual(claude.snapshot.limits.map(row => [row.label, row.percent, row.reached]), [
  ["Session en cours", 3, false], ["Semaine · tous les modèles", 10, false], ["Semaine · Fable", 15, false]]);
assert.equal(claude.snapshot.limits[0].resetsAt, Date.parse("2026-09-28T18:30:00.153503+00:00"));
assert.equal(claude.snapshot.blocked, false);
const unknownClaudeResets = {text: "Réinitialisations : voir Claude", alert: false,
  url: "https://claude.ai/settings/usage"};
assert.deepEqual(claude.snapshot.notes, [unknownClaudeResets],
  "Missing reset data must not imply there are no credits");

// Claude's reset-grant status can be null in a real get_usage response.
const resetNow = Date.parse("2026-09-30T00:00:00Z");
for (const status of [null, undefined, {}, {eligible: false}])
  assert.deepEqual(plain(limits.claudeResetCredits(status, resetNow)), unknownClaudeResets);
const resetGrants = {eligible: true, grants: [
  {resets_left: 1, ends_at: "2026-10-15T00:00:00Z"},
  {resets_left: 2, ends_at: "2026-09-29T00:00:00Z"}]};
assert.deepEqual(plain(limits.claudeResetCredits(resetGrants, resetNow)),
  {text: "1 crédit de réinitialisation", alert: false}, "Expired grants are excluded");
assert.deepEqual(plain(limits.claudeResetCredits({grants: [{resets_left: 1}, {resets_left: 2}]}, resetNow)),
  {text: "3 crédits de réinitialisation", alert: false});
assert.deepEqual(plain(limits.claudeResetCredits({grants: []}, resetNow)),
  {text: "0 crédits de réinitialisation", alert: false}, "An explicit empty grant list is a known zero");
for (const remaining of [null, "1", -1, 0.5, Infinity])
  assert.deepEqual(plain(limits.claudeResetCredits({grants: [{resets_left: remaining}]}, resetNow)),
    unknownClaudeResets, "A malformed count stays unknown");
assert.deepEqual(plain(limits.claudeSnapshot({...usage, rate_limits: {...usage.rate_limits,
  cedar_ember: {eligible: true, grants: [{resets_left: 1}]}}}, "").snapshot.notes),
  [{text: "1 crédit de réinitialisation", alert: false}]);

// Snapshot answers can omit server rows; the named windows remain usable.
const snapshot = plain(limits.claudeSnapshot({ subscription_type: "pro", rate_limits: {
  limits: [], five_hour: { utilization: 100, resets_at: "2026-09-28T18:30:00Z" },
  seven_day: { utilization: 42.4, resets_at: null }, seven_day_opus: { utilization: 7, resets_at: null },
  seven_day_sonnet: null } }, ""));
assert.equal(snapshot.snapshot.plan, "Claude Pro");
assert.deepEqual(snapshot.snapshot.limits.map(row => [row.label, row.percent, row.resetsAt, row.reached]), [
  ["Session en cours", 100, Date.parse("2026-09-28T18:30:00Z"), true],
  ["Semaine · tous les modèles", 42.4, null, false], ["Semaine · Opus", 7, null, false]]);
assert.equal(snapshot.snapshot.blocked, true);

assert.equal(limits.claudeSnapshot({ rate_limits_available: false, rate_limits: null }).error,
  "Aucune limite d’abonnement pour ce compte");
assert.equal(limits.claudeSnapshot({ rate_limits_available: true, rate_limits: null }).error,
  "Limites Claude indisponibles");
assert.equal(limits.claudeSnapshot({ rate_limits: { limits: [{ kind: "session" }] } }).error,
  "Limites Claude indisponibles", "Rows without a percentage are never shown as 0 %");
assert.equal(limits.claudeSnapshot("nope").error, "Réponse inattendue de Claude Code");
const refused = limits.claude.step({ type: "control_response", response: { subtype: "error",
  request_id: limits.claudeUsageId, error: "Unknown control request" } }, {});
assert.equal(refused.error, "Claude Code a refusé la lecture");
assert.equal(refused.detail, "Unknown control request");
assert.equal(limits.claude.step({ type: "control_response", response: { subtype: "error",
  request_id: limits.claudeInitializeId, error: "boom" } }, {}).error, "Claude Code n’a pas pu démarrer");

// Codex app-server: initialize, the initialized notification, then one read.
const [codexInitialize] = plain(limits.codex.opening());
assert.equal(codexInitialize.method, "initialize");
assert.equal(codexInitialize.id, limits.codexInitializeId);
assert.equal(codexInitialize.params.clientInfo.name, "quickshell_usage");
assert.equal(limits.codex.step({ method: "remoteControl/status/changed", params: {} }), null);
assert.equal(limits.codex.step({ id: limits.codexInitializeId, method: "item/tool/requestUserInput" }), null,
  "A server request is not mistaken for our reply");
assert.deepEqual(plain(limits.codex.step({ id: limits.codexInitializeId, result: { userAgent: "codex" } })), {
  send: [{ method: "initialized" }, { id: limits.codexRateLimitsId, method: "account/rateLimits/read",
    params: { excludeResetCreditDetails: true } }] });
assert.equal(limits.codex.step({ id: 99, result: {} }), null);

// Shape returned by codex-cli 0.157.1 (account identifier removed).
const rateLimits = {
  ordinaryUsageAllowed: true,
  rateLimits: { limitId: "codex", limitName: null, planType: "prolite", rateLimitReachedType: null,
    primary: { usedPercent: 94, windowDurationMins: 10080, resetsAt: 1791047867 },
    secondary: { usedPercent: 12, windowDurationMins: 300, resetsAt: 1790620000 },
    credits: { hasCredits: false, unlimited: false, balance: "0" } },
  rateLimitsByLimitId: { base_model_inference: { limitName: "gpt-reserve",
    primary: { usedPercent: 0, windowDurationMins: 10080, resetsAt: 1791207439 } } },
  rateLimitResetCredits: { availableCount: 1, credits: null }, rateLimitUpsell: null
};
const codex = plain(limits.codex.step({ id: limits.codexRateLimitsId, result: rateLimits }));
assert.equal(codex.error, "");
assert.equal(codex.snapshot.plan, "ChatGPT Pro Lite");
assert.deepEqual(codex.snapshot.limits.map(row => [row.label, row.percent, row.resetsAt]), [
  ["5 heures", 12, 1790620000000], ["Semaine", 94, 1791047867000]], "Shortest window first");
assert.deepEqual(codex.snapshot.notes, [{ text: "1 crédit de réinitialisation", alert: false }]);
assert.equal(codex.snapshot.blocked, false);

const reached = plain(limits.codexSnapshot({ ordinaryUsageAllowed: false, rateLimitResetCredits: { availableCount: 2 },
  rateLimits: { planType: "self_serve_business_prolite", rateLimitReachedType: "rate_limit_reached",
    primary: { usedPercent: 100, windowDurationMins: 60, resetsAt: null }, secondary: null } }));
assert.equal(reached.snapshot.plan, "ChatGPT Business");
assert.deepEqual(reached.snapshot.limits.map(row => [row.label, row.reached]), [["1 heure", true]]);
assert.deepEqual(reached.snapshot.notes, [{ text: "Limite atteinte", alert: true },
  { text: "2 crédits de réinitialisation", alert: false }]);
assert.equal(reached.snapshot.blocked, true);
const blocked = plain(limits.codexSnapshot({ ordinaryUsageAllowed: false, rateLimits: {
  primary: { usedPercent: 40, windowDurationMins: 2880, resetsAt: null } } }));
assert.deepEqual(blocked.snapshot.notes, [{ text: "Usage bloqué", alert: true }]);
assert.equal(blocked.snapshot.limits[0].label, "2 jours");
assert.equal(blocked.snapshot.plan, "", "An unknown plan is left blank");
assert.equal(limits.codexSnapshot({ rateLimits: { primary: null, secondary: { windowDurationMins: 300 } } }).error,
  "Limites Codex indisponibles");
assert.equal(limits.codexSnapshot(null).error, "Réponse inattendue de Codex");
const rpcError = limits.codex.step({ id: limits.codexRateLimitsId,
  error: { code: -32600, message: "authentication required" } });
assert.equal(rpcError.error, "Limites Codex indisponibles");
assert.equal(rpcError.detail, "authentication required");
assert.equal(limits.codex.step({ id: limits.codexInitializeId, error: { message: "bad" } }).error,
  "Codex n’a pas pu démarrer");

// French display text, in local time.
const now = new Date(2026, 8, 28, 15, 42, 10).getTime();
assert.equal(limits.percentText(15.4), "15 %");
assert.equal(limits.percentText(99.6), "99 %");
assert.equal(limits.percentText(100), "100 %");
assert.equal(limits.percentText(null), "—");
assert.equal(limits.resetText(null, now), "");
assert.equal(limits.resetText(now - 1, now), "Réinitialisée");
assert.equal(limits.resetText(now + 20000, now), "Réinitialisation dans 1 min");
assert.equal(limits.resetText(now + 12 * 60000, now), "Réinitialisation dans 12 min");
assert.equal(limits.resetText(now + 4 * hour + 5 * 60000, now), "Réinitialisation dans 4 h 05");
assert.equal(limits.resetText(now + 3 * hour, now), "Réinitialisation dans 3 h");
assert.equal(limits.resetText(new Date(2026, 9, 2, 12, 0).getTime(), now), "Réinitialisation ven. 2 oct. à 12:00");
assert.equal(limits.updateText(0, now), "");
assert.equal(limits.updateText(new Date(2026, 8, 28, 9, 5).getTime(), now), "Màj 09:05");
assert.equal(limits.updateText(new Date(2026, 8, 27, 23, 59).getTime(), now), "Màj 27/09 23:59");
assert.equal(limits.expired({ limits: [{ resetsAt: now + day }, { resetsAt: null }] }, now), false);
assert.equal(limits.expired({ limits: [{ resetsAt: now - 1 }] }, now), true);
assert.equal(limits.expired(null, now), false);
console.log("PASS: Claude and Codex usage protocols, validation, snapshot fallback, plans, notes and French reset times");
