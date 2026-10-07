// node server/ai-proxy/test.mjs
import assert from 'node:assert/strict';
import worker, { validate, overDailyCap } from './worker.js';

const ok = { model: 'gemini-3.5-flash-lite', messages: [{ role: 'user', content: 'hi' }] };

// Allowed fields only, stream forced, numbers clamped.
const v = validate({ ...ok, max_tokens: 99999, temperature: 7, stream: false, tools: [1], n: 50 });
assert.deepEqual(Object.keys(v).sort(), ['max_tokens', 'messages', 'model', 'stream', 'temperature']);
assert.equal(v.max_tokens, 1600);
assert.equal(v.temperature, 1);
assert.equal(v.stream, true);
assert.equal(validate({ ...ok, max_tokens: -5 }).max_tokens, 1);
assert.equal(validate({ ...ok, max_tokens: 'lots' }).max_tokens, 700);
assert.equal(validate(ok).reasoning_effort, undefined); // lite: no thinking
assert.equal(validate({ ...ok, model: 'gemini-3.8-flash' }).reasoning_effort, 'low');
assert.deepEqual(validate({ ...ok, messages: [{ role: 'user', content: 'x', name: 'y' }] }).messages,
  [{ role: 'user', content: 'x' }]);

// Rejected shapes.
for (const bad of [
  null, 'x', {},
  { ...ok, model: 'gemini-3.1-pro-preview' },
  { ...ok, messages: [] },
  { ...ok, messages: 'hi' },
  { ...ok, messages: [{ role: 'tool', content: 'x' }] },
  { ...ok, messages: [{ role: 'user', content: { a: 1 } }] },
  { ...ok, messages: [null] },
  { ...ok, messages: Array(21).fill({ role: 'user', content: 'x' }) },
  { ...ok, messages: [{ role: 'user', content: 'x'.repeat(40_001) }] },
]) assert.equal(validate(bad), null, JSON.stringify(bad)?.slice(0, 80));

// Routing, method, rate limit, bad JSON — upstream is never reached for these.
const env = (allowed = true) => ({ GEMINI_API_KEY: 'k', LIMITER: { limit: async () => ({ success: allowed }) } });
const req = (path, init) => new Request(`https://w.dev${path}`, init);
const post = (body) => ({ method: 'POST', body });
assert.equal((await worker.fetch(req('/', post('{}')), env())).status, 404);
assert.equal((await worker.fetch(req('/v1/chat/completions'), env())).status, 405);
assert.equal((await worker.fetch(req('/v1/chat/completions', post(JSON.stringify(ok))), env(false))).status, 429);
assert.equal((await worker.fetch(req('/v1/chat/completions', post('not json')), env())).status, 400);
assert.equal((await worker.fetch(req('/v1/chat/completions', post('{"model":"x"}')), env())).status, 400);

// Upstream gets the key server-side; its error body is not passed back.
let sent;
globalThis.fetch = async (url, init) => {
  sent = { url, init };
  return new Response('{"error":"account 123 over quota"}', { status: 402 });
};
const r = await worker.fetch(req('/v1/chat/completions', post(JSON.stringify(ok))), env());
assert.equal(r.status, 502);
assert.equal(await r.text(), '');
assert.equal(sent.init.headers.Authorization, 'Bearer k');
assert.equal(JSON.parse(sent.init.body).stream, true);

// Global daily cap: counts valid requests, refuses once spent, skipped without KV.
const kv = () => {
  const m = new Map();
  return { get: async (k) => m.get(k) ?? null, put: async (k, v) => void m.set(k, v) };
};
assert.equal(await overDailyCap({}), false);
const capped = { USAGE: kv(), DAILY_CAP: '2' };
assert.equal(await overDailyCap(capped), false);
assert.equal(await overDailyCap(capped), false);
assert.equal(await overDailyCap(capped), true);
const spent = { ...env(), USAGE: kv(), DAILY_CAP: '0' };
assert.equal((await worker.fetch(req('/v1/chat/completions', post(JSON.stringify(ok))), spent)).status, 429);

console.log('ai-proxy: all checks passed');
