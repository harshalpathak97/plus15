// node server/ai-proxy/test.mjs
import assert from 'node:assert/strict';
import worker, { validate } from './worker.js';

const ok = { model: 'moonshotai/kimi-k3', messages: [{ role: 'user', content: 'hi' }] };

// Allowed fields only, stream forced, numbers clamped.
const v = validate({ ...ok, max_tokens: 99999, temperature: 7, stream: false, tools: [1], n: 50 });
assert.deepEqual(Object.keys(v).sort(), ['max_tokens', 'messages', 'model', 'stream', 'temperature']);
assert.equal(v.max_tokens, 1600);
assert.equal(v.temperature, 1);
assert.equal(v.stream, true);
assert.equal(validate({ ...ok, max_tokens: -5 }).max_tokens, 1);
assert.equal(validate({ ...ok, max_tokens: 'lots' }).max_tokens, 700);
assert.deepEqual(validate({ ...ok, messages: [{ role: 'user', content: 'x', name: 'y' }] }).messages,
  [{ role: 'user', content: 'x' }]);

// Rejected shapes.
for (const bad of [
  null, 'x', {},
  { ...ok, model: 'meta/llama-3.1-405b-instruct' },
  { ...ok, messages: [] },
  { ...ok, messages: 'hi' },
  { ...ok, messages: [{ role: 'tool', content: 'x' }] },
  { ...ok, messages: [{ role: 'user', content: { a: 1 } }] },
  { ...ok, messages: [null] },
  { ...ok, messages: Array(21).fill({ role: 'user', content: 'x' }) },
  { ...ok, messages: [{ role: 'user', content: 'x'.repeat(100_001) }] },
]) assert.equal(validate(bad), null, JSON.stringify(bad)?.slice(0, 80));

// Routing, method, rate limit, bad JSON — upstream is never reached for these.
const env = (allowed = true) => ({ NVIDIA_API_KEY: 'k', LIMITER: { limit: async () => ({ success: allowed }) } });
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

console.log('ai-proxy: all checks passed');
