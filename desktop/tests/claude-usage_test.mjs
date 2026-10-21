// Dedicated reset reader: all network/credential access is injected and fake.
import assert from 'node:assert/strict';
import {readResetStatus, readCachedResetStatus, enrichUsage} from '../../tools/quickshell/usage/claude-usage.mjs';

const secret = 'test-access-token';
const requests = [];
const reads = [];
const options = {
  version: '2.1.304', env: {CLAUDE_CONFIG_DIR: '/fake/claude'},
  read: async (path, encoding) => {
    reads.push([path, encoding]);
    return JSON.stringify({claudeAiOauth: {accessToken: secret, refreshToken: 'never-used'}});
  },
  request: async (url, init) => {
    requests.push([url, init]);
    return {ok: true, json: async () => ({cedar_ember: {eligible: true, grants: [
      {id: 'private-grant', resets_left: 1, starts_at: '2026-09-22T16:00:00Z',
        ends_at: '2026-10-22T16:00:00Z'}]}, account: 'private-account'})};
  }
};
const status = await readResetStatus(options);
assert.deepEqual(reads, [['/fake/claude/.credentials.json', 'utf8']]);
assert.deepEqual(status, {grants: [{resets_left: 1, starts_at: '2026-09-22T16:00:00Z',
  ends_at: '2026-10-22T16:00:00Z'}]});
assert.equal(requests[0][0], 'https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1');
assert.equal(requests[0][1].method, 'GET');
assert.equal(requests[0][1].redirect, 'error');
assert.equal(requests[0][1].headers.Authorization, 'Bearer ' + secret);
assert.equal(requests[0][1].headers['User-Agent'], 'claude-cli/2.1.304 (external, cli)');
assert.equal(requests[0][1].headers['anthropic-beta'], 'oauth-2025-04-20');
assert.ok(requests[0][1].signal instanceof AbortSignal);
assert.doesNotMatch(JSON.stringify(status), /private|token|never-used/);

await readResetStatus({...options, env: {CLAUDE_CODE_OAUTH_TOKEN: 'environment-token'},
  read: async () => assert.fail('Explicit OAuth tokens must not read the credential file'),
  request: async (_url, init) => {
    assert.equal(init.headers.Authorization, 'Bearer environment-token');
    return {ok: true, json: async () => ({cedar_ember: {grants: []}})};
  }});
for (const credentials of ['invalid json', '{}', '{"claudeAiOauth":{"accessToken":42}}']) {
  await assert.rejects(readResetStatus({...options, read: async () => credentials,
    request: async () => assert.fail('Missing credentials must not reach the network')}));
}
await assert.rejects(readResetStatus({...options, version: 'unknown',
  read: async () => assert.fail('Invalid versions must fail before reading credentials')}));
for (const body of [{}, {cedar_ember: null}, {cedar_ember: {}}, {cedar_ember: {grants: 'wrong'}}])
  await assert.rejects(readResetStatus({...options,
    request: async () => ({ok: true, json: async () => body})}));
for (const code of [401, 403, 429, 500]) {
  let attempts = 0;
  await assert.rejects(readResetStatus({...options, request: async () => {
    attempts++;
    return {ok: false, status: code, json: async () => assert.fail('Error bodies are not read')};
  }}));
  assert.equal(attempts, 1, 'No token refresh or retry storm');
}

const usage = {type: 'control_response', response: {subtype: 'success', request_id: 'usage',
  response: {subscription_type: 'max', rate_limits_available: true,
    rate_limits: {five_hour: {utilization: 8}, cedar_ember: null}}}};
const enriched = await enrichUsage(usage, async () => status);
assert.deepEqual(enriched.response.response.rate_limits.cedar_ember, status);
assert.deepEqual(enriched.response.response.rate_limits.five_hour, {utilization: 8});
assert.equal(enriched.response.request_id, 'usage');
assert.equal(usage.response.response.rate_limits.cedar_ember, null, 'Input stays unchanged');
const warnings = [];
const failed = await enrichUsage(usage, async () => {throw new Error(secret);}, warning => warnings.push(warning));
assert.equal(failed.response.response.reset_credits_unavailable, true);
assert.deepEqual(failed.response.response.rate_limits, usage.response.response.rate_limits);
assert.deepEqual(warnings, ['Claude reset credits unavailable; keeping quota reading']);
assert.ok(!warnings.join().includes(secret));
const knownZero = structuredClone(usage);
knownZero.response.response.rate_limits.cedar_ember = {grants: []};
const noSubscription = structuredClone(usage);
noSubscription.response.response.rate_limits_available = false;
for (const message of [knownZero, noSubscription, {type: 'system'},
  {type: 'control_response', response: {subtype: 'success', response: {account: {}}}},
  {type: 'control_response', response: {subtype: 'error', error: 'refused'}}]) {
  assert.equal(await enrichUsage(message, async () => assert.fail('No reset query expected')), message);
}
// A fresh reading survives restarts; rate limits do not trigger repeated calls.
let cache, calls = 0;
const storage = {now: 1000000, load: async () => cache, save: async value => {cache = value}};
const cachedOptions = {...options, env: {CLAUDE_CODE_OAUTH_TOKEN: secret}, request: async () => {
  calls++;
  return {ok: true, json: async () => ({cedar_ember: status})};
}};
assert.deepEqual(await readCachedResetStatus(cachedOptions, storage), status);
assert.deepEqual(await readCachedResetStatus(cachedOptions, {...storage, now: storage.now + 299999}), status);
assert.equal(calls, 1);
assert.ok(!JSON.stringify(cache).includes(secret), 'No credential is persisted');
const throttled = {...cachedOptions, request: async () => {
  calls++;
  return {ok: false, status: 429, headers: {get: () => '900'}};
}};
const later = storage.now + 300000;
await assert.rejects(readCachedResetStatus(throttled, {...storage, now: later}));
assert.equal(cache.retryAt, later + 900000);
assert.equal(cache.status, null, 'No stale balance is presented as current');
await assert.rejects(readCachedResetStatus(throttled, {...storage, now: later + 899999}));
assert.equal(calls, 2, 'Backoff also survives a new collector process');
assert.deepEqual(await readCachedResetStatus(cachedOptions, {...storage, now: later + 900000}), status);
assert.equal(calls, 3, 'A new read is allowed once Retry-After expires');
await readCachedResetStatus({...cachedOptions, env: {CLAUDE_CODE_OAUTH_TOKEN: 'different-account'}},
  {...storage, now: later + 900001});
assert.equal(calls, 4, 'A different credential cannot inherit a previous balance');
cache = {version: 1, identity: cache.identity, checkedAt: later + 999999, status};
await readCachedResetStatus({...cachedOptions, env: {CLAUDE_CODE_OAUTH_TOKEN: 'different-account'}},
  {...storage, now: later + 900002});
assert.equal(calls, 5, 'A future-dated cache is ignored');
const brokenStorage = {...storage, load: async () => {throw new Error('unreadable')},
  save: async () => {throw new Error('read-only directory')}};
assert.deepEqual(await readCachedResetStatus(cachedOptions, brokenStorage), status,
  'Cache I/O failure must not discard a successful live read');
console.log('PASS: Claude reset query, private cache, rate-limit backoff, account isolation and quota fallback');
