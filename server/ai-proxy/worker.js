// Ask +15 proxy: holds the Gemini API key so it never ships in the app, and only
// forwards requests shaped like the app's own (our models, capped size/tokens).
// Gemini's OpenAI-compatible endpoint, so the app's streaming code is unchanged.
const UPSTREAM = 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
const MODELS = new Set(['gemini-3.5-flash-lite', 'gemini-flash-lite-latest', 'gemini-3.8-flash']);
const ROLES = new Set(['system', 'user', 'assistant']);
const MAX_MESSAGES = 20;
const MAX_CHARS = 40_000; // real system prompt is ~16k; 9 turns of history on top
const MAX_TOKENS = 1600;

/** The upstream body built from allowed fields only, or null if [body] isn't one the app sends. */
export function validate(body) {
  if (!body || typeof body !== 'object' || !MODELS.has(body.model)) return null;
  const msgs = body.messages;
  if (!Array.isArray(msgs) || msgs.length === 0 || msgs.length > MAX_MESSAGES) return null;
  let chars = 0;
  for (const m of msgs) {
    if (!m || !ROLES.has(m.role) || typeof m.content !== 'string') return null;
    chars += m.content.length;
  }
  if (chars > MAX_CHARS) return null;
  const num = (v, lo, hi, d) => (typeof v === 'number' && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d);
  const out = {
    model: body.model,
    messages: msgs.map(({ role, content }) => ({ role, content })),
    stream: true,
    temperature: num(body.temperature, 0, 1, 0.4),
    max_tokens: Math.round(num(body.max_tokens, 1, MAX_TOKENS, 700)),
  };
  // Full flash models think first; keep that short so answers start quickly.
  if (!body.model.includes('lite')) out.reasoning_effort = 'low';
  return out;
}

const fail = (status) => new Response(null, { status });

/** Upstream calls allowed per UTC day across all users (override with the DAILY_CAP var). */
const DAILY_CAP = 2000;

/**
 * True when today's global budget is spent; otherwise counts this request.
 * Skipped when no USAGE KV namespace is bound (local dev, tests).
 * ponytail: KV read-then-write undercounts under bursts and allows ~1 write/s
 * per key; move to a Durable Object counter if the cap must be exact.
 */
export async function overDailyCap(env, ctx) {
  if (!env.USAGE) return false;
  const key = `day:${new Date().toISOString().slice(0, 10)}`;
  const used = Number(await env.USAGE.get(key)) || 0;
  // DAILY_CAP = "0" is a kill switch.
  if (used >= (env.DAILY_CAP != null ? Number(env.DAILY_CAP) : DAILY_CAP)) return true;
  const put = env.USAGE.put(key, String(used + 1), { expirationTtl: 172_800 }).catch(() => {});
  if (ctx?.waitUntil) ctx.waitUntil(put);
  else await put;
  return false;
}

export default {
  async fetch(request, env, ctx) {
    if (new URL(request.url).pathname !== '/v1/chat/completions') return fail(404);
    if (request.method !== 'POST') return fail(405);
    const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
    if (!(await env.LIMITER.limit({ key: ip })).success) return fail(429);
    if (Number(request.headers.get('Content-Length') ?? 0) > MAX_CHARS * 4) return fail(413);

    let body;
    try {
      body = validate(await request.json());
    } catch {
      body = null;
    }
    if (!body) return fail(400);
    if (await overDailyCap(env, ctx)) return fail(429);

    const res = await fetch(UPSTREAM, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.GEMINI_API_KEY}`,
        'Content-Type': 'application/json',
        Accept: 'text/event-stream',
      },
      body: JSON.stringify(body),
    });
    // Upstream error bodies can carry account details; pass the status only.
    if (!res.ok) return fail(res.status === 429 ? 429 : 502);
    return new Response(res.body, {
      headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store' },
    });
  },
};
