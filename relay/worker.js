// BSMM report relay - Cloudflare Worker
//
// The anti-cheat scripts send their reports here instead of straight to Discord,
// so the Discord webhook never appears in the public scripts.
//
// Setup: add ONE secret to the Worker (Settings > Variables and Secrets):
//   WEBHOOK_URL = your Discord webhook URL
//
// Endpoints used by the scripts:
//   POST  /report        new message (JSON, or multipart with one .txt log)  -> { id, key }
//   PATCH /report/<id>   edit a message this relay created (needs X-Edit-Key) -> { id, key }
//   GET   /              health check

const TITLE_PREFIX = 'BSMM';        // first embed title must start with this (your brand name)
const MAX_BODY = 1_500_000;         // bytes per request
const MAX_FILE = 1_000_000;         // bytes per attached log
const PER_MINUTE = 20;              // requests per IP per minute
const FILE_NAME = /^BSMM-[A-Z0-9]{8}-(system-check|live-monitor)\.txt$/;
const SNOWFLAKE = /^\d{15,25}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/') return new Response('BSMM relay OK');
    if (!env.WEBHOOK_URL) return json({ error: 'relay not configured' }, 500);
    if (await limited(request, env)) return json({ error: 'rate limited' }, 429);
    if (Number(request.headers.get('content-length') || 0) > MAX_BODY) return json({ error: 'too large' }, 413);

    try {
      if (request.method === 'POST' && url.pathname === '/report') return await create(request, env);
      const m = url.pathname.match(/^\/report\/([^/]+)$/);
      if (request.method === 'PATCH' && m && SNOWFLAKE.test(m[1])) return await edit(request, env, m[1]);
      return json({ error: 'not found' }, 404);
    } catch (e) {
      return json({ error: 'rejected: ' + String(e.message || e).slice(0, 80) }, 400);
    }
  },
};

function webhookBase(env) {
  return String(env.WEBHOOK_URL).trim().split('?')[0].replace(/\/+$/, '');
}

// Only BSMM-shaped messages get through: embeds only, no pings, no images or links, fixed sender name.
function clean(p) {
  if (!p || typeof p !== 'object' || !Array.isArray(p.embeds)) throw new Error('no embeds');
  if (p.embeds.length < 1 || p.embeds.length > 4) throw new Error('embed count');
  if (typeof p.embeds[0].title !== 'string' || !p.embeds[0].title.startsWith(TITLE_PREFIX)) throw new Error('not a report');
  const str = (v, max) => (typeof v === 'string' ? v.slice(0, max) : undefined);
  const embeds = p.embeds.map((e) => {
    const out = { title: str(e.title, 256), description: str(e.description, 4096) };
    if (Number.isInteger(e.color) && e.color >= 0 && e.color <= 0xffffff) out.color = e.color;
    if (typeof e.timestamp === 'string' && !Number.isNaN(Date.parse(e.timestamp))) out.timestamp = e.timestamp;
    if (e.footer && typeof e.footer.text === 'string') out.footer = { text: e.footer.text.slice(0, 2048) };
    if (Array.isArray(e.fields)) {
      out.fields = e.fields.slice(0, 25).map((f) => ({
        name: str(f && f.name, 256) || '-',
        value: str(f && f.value, 1024) || '-',
        inline: Boolean(f && f.inline),
      }));
    }
    return out;
  });
  if (JSON.stringify(embeds).length > 7000) throw new Error('too long');
  return { username: 'BSMM Anti-Cheat', embeds, allowed_mentions: { parse: [] } };
}

async function create(request, env) {
  const type = request.headers.get('content-type') || '';
  let init;
  if (type.startsWith('application/json')) {
    init = { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(clean(await request.json())) };
  } else if (type.startsWith('multipart/form-data')) {
    const form = await request.formData();
    const payload = clean(JSON.parse(String(form.get('payload_json') || '')));
    const out = new FormData();
    out.append('payload_json', JSON.stringify(payload));
    const file = form.get('files[0]');
    if (file) {
      if (typeof file === 'string' || !FILE_NAME.test(file.name || '') || file.size > MAX_FILE) throw new Error('bad attachment');
      out.append('files[0]', new Blob([await file.text()], { type: 'text/plain' }), file.name);
    }
    init = { method: 'POST', body: out };
  } else {
    throw new Error('content type');
  }
  const res = await fetch(webhookBase(env) + '?wait=true', init);
  if (res.status === 429) return json({ error: 'discord rate limited' }, 429, { 'Retry-After': res.headers.get('Retry-After') || '2' });
  if (!res.ok) return json({ error: 'discord ' + res.status }, 502);
  const msg = await res.json();
  return json({ id: msg.id, key: await sign(env, msg.id) });
}

async function edit(request, env, id) {
  const key = request.headers.get('x-edit-key') || '';
  if (!(await safeEqual(key, await sign(env, id)))) return json({ error: 'forbidden' }, 403);
  const { username, ...payload } = clean(await request.json());   // edits cannot change the sender name
  const res = await fetch(webhookBase(env) + '/messages/' + id, {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (res.status === 429) return json({ error: 'discord rate limited' }, 429, { 'Retry-After': res.headers.get('Retry-After') || '2' });
  if (!res.ok) return json({ error: 'discord ' + res.status }, 502);
  return json({ id, key });
}

// Edit keys stop anyone from changing messages they did not create.
async function sign(env, id) {
  const enc = new TextEncoder();
  const k = await crypto.subtle.importKey('raw', enc.encode(String(env.WEBHOOK_URL)), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', k, enc.encode('edit:' + id)));
  return [...sig.slice(0, 16)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Uses Cloudflare's rate-limit binding if configured (see wrangler.toml), otherwise a per-instance counter.
const hits = new Map();
async function limited(request, env) {
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  if (env.REPORT_LIMITER) {
    const { success } = await env.REPORT_LIMITER.limit({ key: ip });
    return !success;
  }
  const now = Date.now();
  const recent = (hits.get(ip) || []).filter((t) => now - t < 60_000);
  recent.push(now);
  hits.set(ip, recent);
  if (hits.size > 5000) hits.clear();
  return recent.length > PER_MINUTE;
}

function json(obj, status = 200, extra = {}) {
  return new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json', ...extra } });
}
