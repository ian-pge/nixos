.pragma library

// Pure search and desktop identity rules shared by both launchers.
function normalizeText(value) {
  const lowered = (value ?? "").toString().toLowerCase();
  try {
    return lowered.normalize("NFKD").replace(/[\u0300-\u036f]/g, "");
  } catch (error) {
    return lowered;
  }
}

function fuzzyScore(candidate, query) {
  const name = candidate.normalizedName;
  const text = candidate.searchText;
  if (name === query)
    return 10000;

  let score = name.startsWith(query) ? 1200
    : name.includes(query) ? 700 : 0;
  let previous = -1;
  let streak = 0;
  let gaps = 0;

  for (let index = 0; index < query.length; ++index) {
    const position = text.indexOf(query[index], previous + 1);
    if (position < 0)
      return -1;
    const gap = previous < 0 ? position : position - previous - 1;
    gaps += gap;
    streak = gap === 0 ? streak + 1 : 0;
    score += 20 + streak * 14;
    if (position === 0 || " -_./".includes(text[position - 1]))
      score += 45;
    previous = position;
  }

  score -= gaps * 3;
  score -= Math.max(0, name.length - query.length) * 0.2;
  return score;
}

function normalizeIdentity(value) {
  return normalizeText(value).trim().replace(/\.desktop$/, "");
}

function identityAliases(value) {
  const identity = normalizeIdentity(value);
  if (identity === "")
    return [];
  const aliases = [identity];
  let match = identity.match(/^chrome-([a-z]+)-default$/);
  if (match !== null)
    aliases.push("crx_" + match[1]);
  match = identity.match(/^crx_([a-z]+)$/);
  if (match !== null)
    aliases.push("chrome-" + match[1] + "-default");
  return aliases;
}
