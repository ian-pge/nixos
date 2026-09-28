.pragma library

// Subscription limits come from each official CLI, already signed in with the
// user's own account: Claude Code's stream-json control protocol and Codex's
// app-server JSON-RPC. No credential file or private endpoint is read here.
// Both interfaces are marked experimental upstream, so every field is
// validated: an unexpected shape becomes an explicit error, never a guess.

var claudeInitializeId = "quickshell-usage-initialize";
var claudeUsageId = "quickshell-usage-read";
var codexInitializeId = 1;
var codexRateLimitsId = 2;

var weekdays = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."];
var months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août",
  "sept.", "oct.", "nov.", "déc."];

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function finite(value) {
  return typeof value === "number" && isFinite(value) ? value : null;
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function detail(value) {
  if (typeof value === "string") return value;
  if (isObject(value) && typeof value.message === "string") return value.message;
  return value === undefined || value === null ? "" : JSON.stringify(value);
}

function success(snapshot) {
  return { done: true, snapshot: snapshot, error: "", detail: "" };
}

function failure(error, reason) {
  return { done: true, snapshot: null, error: error, detail: detail(reason) };
}

function limit(label, percent, resetsAt) {
  return { label: label, percent: percent, resetsAt: resetsAt, reached: percent >= 100 };
}

// Alerts explain a block; other notes are neutral facts.
function note(text, alert) {
  return { text: text, alert: alert };
}

function isoTime(value) {
  if (typeof value !== "string") return null;
  var time = Date.parse(value);
  return isFinite(time) ? time : null;
}

function claudeScope(scope) {
  if (!isObject(scope)) return "";
  var parts = [scope.model, scope.surface];
  for (var index = 0; index < parts.length; ++index) {
    var name = isObject(parts[index]) ? text(parts[index].display_name) : text(parts[index]);
    if (name !== "") return name;
  }
  return "";
}

function claudeLabel(row) {
  var scope = claudeScope(row.scope);
  if (row.kind === "session") return "Session en cours";
  if (row.kind === "weekly_all") return "Semaine · tous les modèles";
  if (row.kind === "weekly_scoped" || row.group === "weekly")
    return scope !== "" ? "Semaine · " + scope : "Semaine";
  if (row.group === "session") return scope !== "" ? "Session · " + scope : "Session en cours";
  return scope !== "" ? scope : text(row.kind) || "Limite";
}

// Server-classified rows, including per-model weekly windows.
function claudeRows(rows) {
  var result = [];
  for (var index = 0; index < rows.length; ++index) {
    var row = rows[index];
    if (!isObject(row) || finite(row.percent) === null) continue;
    result.push(limit(claudeLabel(row), row.percent, isoTime(row.resets_at)));
  }
  return result;
}

// Older and snapshot answers only carry the named windows.
function claudeWindows(limits) {
  var result = [];
  function add(label, window) {
    if (isObject(window) && finite(window.utilization) !== null)
      result.push(limit(label, window.utilization, isoTime(window.resets_at)));
  }
  add("Session en cours", limits.five_hour);
  add("Semaine · tous les modèles", limits.seven_day);
  if (Array.isArray(limits.model_scoped)) {
    for (var index = 0; index < limits.model_scoped.length; ++index) {
      var window = limits.model_scoped[index];
      if (isObject(window) && text(window.display_name) !== "")
        add("Semaine · " + text(window.display_name), window);
    }
  } else {
    add("Semaine · Opus", limits.seven_day_opus);
    add("Semaine · Sonnet", limits.seven_day_sonnet);
  }
  return result;
}

function claudePlan(type) {
  var names = { pro: "Claude Pro", max: "Claude Max", team: "Claude Team", enterprise: "Claude Enterprise" };
  return names[type] || "";
}

function claudeSnapshot(usage, plan) {
  if (!isObject(usage)) return failure("Réponse inattendue de Claude Code");
  if (usage.rate_limits_available === false)
    return failure("Aucune limite d’abonnement pour ce compte");
  var limits = usage.rate_limits;
  if (!isObject(limits)) return failure("Limites Claude indisponibles");
  var rows = Array.isArray(limits.limits) ? claudeRows(limits.limits) : [];
  if (rows.length === 0) rows = claudeWindows(limits);
  if (rows.length === 0) return failure("Limites Claude indisponibles");
  return success({
    plan: text(plan) || claudePlan(usage.subscription_type),
    limits: rows,
    notes: [],
    blocked: rows.some(function(row) { return row.reached; })
  });
}

var claude = {
  opening: function() {
    return [{ type: "control_request", request_id: claudeInitializeId,
      request: { subtype: "initialize" } }];
  },
  // `context` belongs to one CLI run. Hook and system lines are ignored.
  step: function(message, context) {
    if (!isObject(message) || message.type !== "control_response" || !isObject(message.response))
      return null;
    var response = message.response;
    if (response.request_id === claudeInitializeId) {
      if (response.subtype !== "success")
        return failure("Claude Code n’a pas pu démarrer", response.error);
      var account = isObject(response.response) ? response.response.account : null;
      if (isObject(account)) context.plan = text(account.subscriptionType);
      // skip_behaviors avoids scanning a week of local transcripts.
      return { send: [{ type: "control_request", request_id: claudeUsageId,
        request: { subtype: "get_usage", skip_behaviors: true } }] };
    }
    if (response.request_id !== claudeUsageId) return null;
    if (response.subtype !== "success")
      return failure("Claude Code a refusé la lecture", response.error);
    return claudeSnapshot(response.response, context.plan);
  }
};

function plural(count, singular, pluralForm) {
  return count + " " + (count === 1 ? singular : pluralForm);
}

function durationLabel(minutes) {
  if (minutes === null || minutes <= 0) return "Limite";
  if (minutes === 10080) return "Semaine";
  if (minutes === 1440) return "Jour";
  if (minutes % 1440 === 0) return plural(minutes / 1440, "jour", "jours");
  if (minutes % 60 === 0) return plural(minutes / 60, "heure", "heures");
  return plural(minutes, "minute", "minutes");
}

function codexLimit(window) {
  if (!isObject(window) || finite(window.usedPercent) === null) return null;
  var minutes = finite(window.windowDurationMins);
  var resetsAt = finite(window.resetsAt);
  var row = limit(durationLabel(minutes), window.usedPercent, resetsAt === null ? null : resetsAt * 1000);
  row.minutes = minutes;
  return row;
}

function codexPlan(type) {
  var names = { free: "Free", go: "Go", plus: "Plus", pro: "Pro", prolite: "Pro Lite",
    team: "Team", business: "Business", enterprise: "Enterprise", edu: "Edu" };
  if (typeof type !== "string") return "";
  var name = names[type] || (type.indexOf("enterprise") === 0 ? "Enterprise"
    : type.indexOf("business") >= 0 ? "Business" : type.indexOf("edu") === 0 ? "Edu" : "");
  return name !== "" ? "ChatGPT " + name : "";
}

var codexReachedNotes = {
  rate_limit_reached: "Limite atteinte",
  workspace_owner_credits_depleted: "Crédits de l’espace de travail épuisés",
  workspace_member_credits_depleted: "Crédits de l’espace de travail épuisés",
  workspace_owner_usage_limit_reached: "Limite de l’espace de travail atteinte",
  workspace_member_usage_limit_reached: "Limite de l’espace de travail atteinte"
};

// Only the historical `codex` bucket is shown; experimental reserve buckets
// in rateLimitsByLimitId are not presented as ordinary limits.
function codexSnapshot(result) {
  if (!isObject(result) || !isObject(result.rateLimits))
    return failure("Réponse inattendue de Codex");
  var limits = result.rateLimits;
  var rows = [codexLimit(limits.primary), codexLimit(limits.secondary)]
    .filter(function(row) { return row !== null; })
    .sort(function(left, right) {
      return (left.minutes === null ? Infinity : left.minutes)
        - (right.minutes === null ? Infinity : right.minutes);
    });
  if (rows.length === 0) return failure("Limites Codex indisponibles");
  var notes = [];
  var reachedType = text(limits.rateLimitReachedType);
  if (reachedType !== "") notes.push(note(codexReachedNotes[reachedType] || "Limite atteinte", true));
  else if (result.ordinaryUsageAllowed === false) notes.push(note("Usage bloqué", true));
  var credits = isObject(result.rateLimitResetCredits)
    ? Number(result.rateLimitResetCredits.availableCount) : 0;
  if (isFinite(credits) && credits >= 1)
    notes.push(note(plural(credits, "crédit de réinitialisation", "crédits de réinitialisation"), false));
  return success({
    plan: codexPlan(limits.planType),
    limits: rows,
    notes: notes,
    blocked: reachedType !== "" || result.ordinaryUsageAllowed === false
      || rows.some(function(row) { return row.reached; })
  });
}

var codex = {
  opening: function() {
    return [{ id: codexInitializeId, method: "initialize", params: {
      clientInfo: { name: "quickshell_usage", title: "Quickshell", version: "1.0.0" },
      capabilities: null } }];
  },
  // Server notifications and requests carry a method; only our replies matter.
  step: function(message) {
    if (!isObject(message) || message.method !== undefined) return null;
    if (message.id === codexInitializeId) {
      if (message.error !== undefined) return failure("Codex n’a pas pu démarrer", message.error);
      return { send: [{ method: "initialized" }, { id: codexRateLimitsId,
        method: "account/rateLimits/read", params: { excludeResetCreditDetails: true } }] };
    }
    if (message.id !== codexRateLimitsId) return null;
    if (message.error !== undefined) return failure("Limites Codex indisponibles", message.error);
    return codexSnapshot(message.result);
  }
};

function pad(value) {
  return value < 10 ? "0" + value : String(value);
}

function clockText(date) {
  return pad(date.getHours()) + ":" + pad(date.getMinutes());
}

// Rounded down: 100 % only appears once the limit is actually reached.
function percentText(percent) {
  return finite(percent) === null ? "—" : Math.floor(percent) + " %";
}

// Rolling windows read best as a delay, longer ones as a local date.
function resetText(resetsAt, now) {
  if (finite(resetsAt) === null) return "";
  var minutes = Math.ceil((resetsAt - now) / 60000);
  if (minutes <= 0) return "Réinitialisée";
  if (minutes < 60) return "Réinitialisation dans " + minutes + " min";
  if (minutes < 1440) {
    var rest = minutes % 60;
    return "Réinitialisation dans " + Math.floor(minutes / 60) + " h" + (rest ? " " + pad(rest) : "");
  }
  var date = new Date(resetsAt);
  return "Réinitialisation " + weekdays[date.getDay()] + " " + date.getDate() + " "
    + months[date.getMonth()] + " à " + clockText(date);
}

function updateText(updatedAt, now) {
  if (finite(updatedAt) === null || updatedAt <= 0) return "";
  var date = new Date(updatedAt), today = new Date(now);
  var sameDay = date.getFullYear() === today.getFullYear() && date.getMonth() === today.getMonth()
    && date.getDate() === today.getDate();
  return "Màj " + (sameDay ? "" : pad(date.getDate()) + "/" + pad(date.getMonth() + 1) + " ") + clockText(date);
}

function expired(snapshot, now) {
  if (!isObject(snapshot) || !Array.isArray(snapshot.limits)) return false;
  return snapshot.limits.some(function(row) {
    return finite(row.resetsAt) !== null && row.resetsAt <= now;
  });
}
