// Ask AI proxy: holds the NVIDIA key so it never ships in the app, and only
// forwards requests shaped like the app's own (our models, capped size/tokens).
const UPSTREAM = 'https://integrate.api.nvidia.com/v1/chat/completions';
const MODELS = new Set(['moonshotai/kimi-k3', 'openai/gpt-oss-20b', 'meta/llama-3.2-11b-vision-instruct']);
const ROLES = new Set(['system', 'user', 'assistant']);
const MAX_MESSAGES = 20;
const MAX_CHARS = 100_000; // real system prompt is ~14k; 9 turns of history on top
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
  return {
    model: body.model,
    messages: msgs.map(({ role, content }) => ({ role, content })),
    stream: true,
    temperature: num(body.temperature, 0, 1, 0.4),
    max_tokens: Math.round(num(body.max_tokens, 1, MAX_TOKENS, 700)),
  };
}

const fail = (status) => new Response(null, { status });

export default {
  async fetch(request, env) {
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

    const res = await fetch(UPSTREAM, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.NVIDIA_API_KEY}`,
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
