// Enrich Claude Code's get_usage response with its dedicated, read-only reset
// query. The CLI runs first and owns OAuth refresh; this helper never refreshes,
// writes credentials, submits a prompt or redeems a grant.
import {spawn, execFile} from 'node:child_process';
import {readFile, mkdir, writeFile, rename, rm} from 'node:fs/promises';
import {createHash, randomUUID} from 'node:crypto';
import {homedir} from 'node:os';
import {join, resolve, dirname} from 'node:path';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';

const resetUrl = 'https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1';
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

async function accessToken(env, read) {
  let token = env.CLAUDE_CODE_OAUTH_TOKEN;
  if (!token) {
    const directory = env.CLAUDE_CONFIG_DIR || join(homedir(), '.claude');
    const credentials = JSON.parse(await read(join(directory, '.credentials.json'), 'utf8'));
    token = credentials.claudeAiOauth?.accessToken;
  }
  if (typeof token !== 'string' || !token || /[\r\n]/.test(token))
    throw new Error('Claude access token unavailable');
  return token;
}

export async function readResetStatus({version, env = process.env, read = readFile, request = fetch}) {
  // A fixed HTTPS destination, no redirects and no token in argv or diagnostics.
  // Match the installed CLI's version: the service gates reset eligibility by UA.
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Claude version unavailable');
  const token = await accessToken(env, read);
  const response = await request(resetUrl, {
    method: 'GET',
    headers: {Authorization: `Bearer ${token}`, 'anthropic-beta': 'oauth-2025-04-20',
      'User-Agent': `claude-cli/${version} (external, cli)`},
    signal: AbortSignal.timeout(5000), redirect: 'error'
  });
  if (!response.ok) {
    const error = new Error('Claude reset read failed');
    error.status = response.status;
    error.retryAfter = response.headers?.get?.('retry-after');
    throw error;
  }
  const status = (await response.json()).cedar_ember;
  if (!object(status) || !Array.isArray(status.grants))
    throw new Error('Claude reset status unavailable');
  // Only forward what the widget needs, not account/grant identifiers.
  return {grants: status.grants.map(grant => object(grant)
    ? {resets_left: grant.resets_left, starts_at: grant.starts_at, ends_at: grant.ends_at}
    : null)};
}

async function writeCache(path, value) {
  await mkdir(dirname(path), {recursive: true, mode: 0o700});
  const temporary = path + '.' + randomUUID();
  try {
    await writeFile(temporary, JSON.stringify(value), {mode: 0o600});
    await rename(temporary, path);
  } finally { await rm(temporary, {force: true}); }
}

// Survives shell restarts without persisting credentials. A changed access
// token invalidates the cache; expired readings are never reported as fresh.
export async function readCachedResetStatus(options, storage = {}) {
  const env = options.env ?? process.env;
  const token = await accessToken(env, options.read ?? readFile);
  const identity = createHash('sha256').update(token).digest('hex');
  const path = join(env.XDG_CACHE_HOME || join(homedir(), '.cache'), 'quickshell', 'claude-resets.json');
  const load = storage.load ?? (async () => JSON.parse(await readFile(path, 'utf8')));
  const save = storage.save ?? (value => writeCache(path, value));
  const now = storage.now ?? Date.now();
  let cache;
  try { cache = await load(); } catch {}
  if (cache?.version === 1 && cache.identity === identity
      && Number.isFinite(cache.checkedAt) && cache.checkedAt <= now) {
    if (now - cache.checkedAt < 300000 && object(cache.status) && Array.isArray(cache.status.grants))
      return cache.status;
    if (Number.isFinite(cache.retryAt) && cache.retryAt > now)
      throw new Error('Claude reset read cooling down');
  }
  try {
    const status = await readResetStatus({...options, env: {...env, CLAUDE_CODE_OAUTH_TOKEN: token}});
    try { await save({version: 1, identity, checkedAt: now, status}); } catch {}
    return status;
  } catch (error) {
    const seconds = typeof error.retryAfter === 'string' && /^\d+$/.test(error.retryAfter)
      ? Number(error.retryAfter) : null;
    const date = typeof error.retryAfter === 'string' ? Date.parse(error.retryAfter) : NaN;
    const requested = seconds !== null ? seconds * 1000 : Number.isFinite(date) ? date - now : 900000;
    const delay = error.status === 429 ? Math.max(60000, Math.min(3600000, requested)) : 60000;
    try { await save({version: 1, identity, checkedAt: now, retryAt: now + delay, status: null}); } catch {}
    throw error;
  }
}

export async function enrichUsage(message, readStatus, warn = () => {}) {
  const response = message?.type === 'control_response' ? message.response : null;
  const usage = response?.subtype === 'success' ? response.response : null;
  if (!object(usage?.rate_limits) || usage.rate_limits_available === false) return message;
  // Future CLIs may supply it themselves. Never replace an explicit zero.
  if (object(usage.rate_limits.cedar_ember)) return message;
  try {
    const status = await readStatus();
    return {...message, response: {...response, response: {...usage,
      rate_limits: {...usage.rate_limits, cedar_ember: status}}}};
  } catch {
    // A network/auth failure must preserve the usable quota reading. Do not
    // print the exception: fetch/credential errors can contain private data.
    warn('Claude reset credits unavailable; keeping quota reading');
    return {...message, response: {...response, response: {...usage, reset_credits_unavailable: true}}};
  }
}

async function main() {
  const [cli, ...args] = process.argv.slice(2);
  if (!cli) throw new Error('Missing Claude executable');
  const child = spawn(cli, args, {stdio: ['pipe', 'pipe', 'inherit']});
  const stop = signal => { child.kill(signal); };
  process.once('SIGTERM', () => stop('SIGTERM'));
  process.once('SIGINT', () => stop('SIGINT'));
  child.stdin.on('error', () => {}); // The CLI may exit before stdin closes.
  const exited = new Promise(resolveExit => {
    child.once('error', () => resolveExit(1));
    child.once('exit', code => resolveExit(code ?? 1));
  });
  process.stdin.pipe(child.stdin);
  // Start version discovery alongside initialization; no credential is read
  // until get_usage has completed (including any CLI-owned OAuth refresh).
  const version = promisify(execFile)(cli, ['--version'], {timeout: 3000})
    .then(({stdout}) => stdout.trim().match(/^(\d+\.\d+\.\d+)\b/)?.[1] ?? '')
    .catch(() => '');
  for await (const line of createInterface({input: child.stdout})) {
    let message;
    try { message = JSON.parse(line); } catch { continue; }
    const result = await enrichUsage(message,
      async () => readCachedResetStatus({version: await version}),
      warning => process.stderr.write(warning + '\n'));
    process.stdout.write(JSON.stringify(result) + '\n');
  }
  process.stdin.unpipe(child.stdin);
  process.stdin.pause();
  process.exitCode = await exited;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { process.stderr.write('Claude usage collector failed\n'); process.exitCode = 1; });
}
