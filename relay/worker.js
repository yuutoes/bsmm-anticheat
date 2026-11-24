// BSMM report relay - Cloudflare Worker
//
// Sits between the anti-cheat scripts, the Discord staff channel and the staff website.
// Nothing the player's PC sends is trusted on its own: a report is only accepted for a check that
// staff started, the relay works out the verdict itself, and it compares what the PC claims with
// what it already knows (the verified Roblox account, earlier checks, how long the scan took).
//
// Bindings (Settings > Bindings / Variables and Secrets):
//   DB               D1 database
//   ADMIN_SECRET     secret, 32+ characters: the only thing that can create or revoke API keys
//   SCRIPT_BASE_URL  optional: where BSMM-Check.ps1 and BSMM-Monitor.ps1 are read from
//
// Admin (Authorization: Bearer <ADMIN_SECRET>):
//   POST   /admin/keys        { name, webhook_url?, view_url? }  -> { id, name, key }   key is shown once
//   GET    /admin/keys
//   DELETE /admin/keys/<id>   revoke
// Bots and the staff website (Authorization: Bearer <API key>):
//   POST   /v1/checks         { mode?, roblox_id?, player?, requested_by?, matches? } -> { id, code, command, expires_at }
//   GET    /v1/checks         ?q= &verdict= &mode= &before= &limit=
//   GET    /v1/checks/<id>    the full report
// The player's PC:
//   GET    /run               the command every player pastes: asks for their code, then loads /c/<code>
//   GET    /c/<code>          the script, once, with this check's signing key inside
//   POST   /v1/report         signed PC check result
//   POST   /v1/live           signed live monitor update

const MAX_BODY = 1_500_000;                 // bytes per request
const PER_MINUTE = 20;                      // unauthenticated requests per IP per minute
const CHECKS_PER_MINUTE = 30;               // checks one API key can start per minute
const CODE_TTL = 10 * 60_000;               // how long a code can be used to download the script
const REPORT_WINDOW = 45 * 60_000;          // a PC check has to report this soon after the download
const LIVE_WINDOW = 8 * 3_600_000;          // a live monitor can update for this long
const MIN_SCAN_SECONDS = 20;                // a real PC check never finishes faster than this
const RETENTION = 90 * 86_400_000;          // reports older than this are deleted
const DEFAULT_SCRIPTS = 'https://raw.githubusercontent.com/yuutoes/bsmm-anticheat/main';
const SCRIPT_FILES = { check: 'BSMM-Check.ps1', monitor: 'BSMM-Monitor.ps1' };

const ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const CHECK_ID = /^BSMM-[2-9A-HJ-NP-Z]{8}$/;
const CODE = /^[2-9A-HJ-NP-Z]{20}$/;
const API_KEY = /^bsmm_[A-Za-z0-9_-]{43}$/;
const ROBLOX_ID = /^\d{1,20}$/;
const DISCORD_WEBHOOK = /^https:\/\/(?:ptb\.|canary\.)?discord(?:app)?\.com\/api\/webhooks\/\d{15,25}\/[\w-]{20,200}$/;

// Trust score: starts at 100, these are subtracted.
const UNTRUSTED_REPORT = new Set(['fast_scan', 'missing_checks', 'version_mismatch']);

// Program activity: when each program ran on the PC, compared with the matches the bot says the player was in.
const MAX_PROGRAMS = 1200;
const MAX_MATCHES = 25;
const MATCH_LEAD = 10 * 60_000; // a program started this long before a match counts as part of it
const MATCH_LENGTH = 90 * 60_000; // assumed length of a match that has no end time yet
const CLOCK_TOLERANCE = 120; // seconds the PC clock may be off before its times are corrected
const PROGRAM_SOURCES = ['running', 'prefetch', 'bam', 'launch', 'exit', 'userassist', 'journal'];
const LAST_RUN_SOURCES = ['launch', 'userassist']; // one entry per program that stays once written, so a missing one was removed
const SIGNATURES = ['signed', 'unsigned', 'missing', 'unknown'];
const FILE_HASH = /^[0-9a-f]{64}$/;
const MAX_HASHES = 90; // D1 allows 100 bound values in one statement
const FLAGGED_FAILS = 2;    // a PC whose own scan failed this many checks counts as flagged when programs are compared
const SHARED_MARGIN = 0.25; // how much more common than usual a program must be on flagged PCs to be held against anyone
const WEIGHTS = { fail: 18, failCap: 60, warn: 4, warnCap: 28, notAdmin: 10, liveFail: 10, liveWarn: 3, liveCap: 40 };
const LABELS = [
  { below: 40, label: 'HIGH RISK', color: 0xfb4d6d },
  { below: 70, label: 'SUSPICIOUS', color: 0xf97316 },
  { below: 90, label: 'REVIEW', color: 0xfbbf24 },
  { below: 101, label: 'TRUSTED', color: 0x34d399 },
];

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS tenants (
     id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, key_hash TEXT NOT NULL UNIQUE,
     webhook_url TEXT, view_url TEXT, created_at INTEGER NOT NULL, disabled INTEGER NOT NULL DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS checks (
     id TEXT PRIMARY KEY, tenant_id INTEGER NOT NULL, code TEXT NOT NULL UNIQUE, mode TEXT NOT NULL, key TEXT NOT NULL,
     player TEXT, roblox_id TEXT, requested_by TEXT, matches TEXT, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
     fetched_at INTEGER, fetch_ip TEXT, script_version TEXT, script_hash TEXT, expected_checks TEXT,
     reported_at INTEGER, live_seq INTEGER NOT NULL DEFAULT 0, ended_at INTEGER, message_id TEXT,
     score INTEGER, label TEXT, failed INTEGER, review INTEGER, flag_count INTEGER,
     pc_hash TEXT, account_ids TEXT, search TEXT, report TEXT)`,
  'CREATE INDEX IF NOT EXISTS checks_tenant_time ON checks (tenant_id, created_at DESC, id DESC)',
  'CREATE INDEX IF NOT EXISTS checks_tenant_pc ON checks (tenant_id, pc_hash)',
  'CREATE INDEX IF NOT EXISTS checks_tenant_player ON checks (tenant_id, roblox_id)',
  `CREATE TABLE IF NOT EXISTS program_sightings (
     tenant_id INTEGER NOT NULL, hash TEXT NOT NULL, check_id TEXT NOT NULL, seen_at INTEGER NOT NULL,
     PRIMARY KEY (tenant_id, hash, check_id))`,
];

const prepared = new WeakSet();
async function ensureSchema(env) {
  if (prepared.has(env.DB)) return;
  await env.DB.batch(SCHEMA.map((sql) => env.DB.prepare(sql)));
  prepared.add(env.DB);
}

class Refused extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof Refused) return json({ error: error.message }, error.status);
      console.error('relay error', error);
      return json({ error: 'internal error' }, 500);
    }
  },
};

async function route(request, env) {
  const url = new URL(request.url);
  const path = url.pathname;
  const method = request.method;
  if (method === 'GET' && path === '/') return new Response('BSMM relay OK');
  if (!env.DB || !env.ADMIN_SECRET) return json({ error: 'relay not configured' }, 500);

  if (path.startsWith('/admin/')) {
    await requireAdmin(request, env);
    await ensureSchema(env);
    const id = path.match(/^\/admin\/keys\/(\d{1,9})$/);
    if (method === 'POST' && path === '/admin/keys') return createKey(request, env);
    if (method === 'GET' && path === '/admin/keys') return listKeys(env);
    if (method === 'DELETE' && id) return revokeKey(env, Number(id[1]));
    throw new Refused(404, 'not found');
  }

  if (path === '/v1/checks' || path.startsWith('/v1/checks/')) {
    const tenant = await requireTenant(request, env);
    const id = path.match(/^\/v1\/checks\/([^/]+)$/);
    if (method === 'POST' && path === '/v1/checks') return createCheck(request, env, tenant, url.origin);
    if (method === 'GET' && path === '/v1/checks') return listChecks(env, tenant, url.searchParams);
    if (method === 'GET' && id && CHECK_ID.test(id[1])) return readCheck(env, tenant, id[1]);
    throw new Refused(404, 'not found');
  }

  const code = path.match(/^\/c\/([^/]+)$/);
  const start = path === '/run';
  const fromPc = (method === 'GET' && (code || start)) || (method === 'POST' && (path === '/v1/report' || path === '/v1/live'));
  if (!fromPc) throw new Refused(404, 'not found');
  if (await limited(request, env)) throw new Refused(429, 'rate limited');
  if (start) return startScript(request, url.origin);
  if (code) return serveScript(request, env, code[1], url.origin);
  return path === '/v1/report' ? fileReport(request, env) : liveUpdate(request, env);
}

// ---------------------------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------------------------

function bearer(request) {
  const header = request.headers.get('authorization') || '';
  return header.startsWith('Bearer ') ? header.slice(7).trim() : '';
}

async function requireAdmin(request, env) {
  const secret = String(env.ADMIN_SECRET);
  const given = bearer(request);
  if (secret.length < 32 || !given || !safeEqual(await sha256(given), await sha256(secret))) throw new Refused(401, 'unauthorised');
}

async function requireTenant(request, env) {
  const key = bearer(request);
  if (!API_KEY.test(key)) throw new Refused(401, 'unauthorised');
  const tenant = await env.DB.prepare('SELECT id, name, webhook_url, view_url FROM tenants WHERE key_hash = ? AND disabled = 0').bind(await sha256(key)).first();
  if (!tenant) throw new Refused(401, 'unauthorised');
  return tenant;
}

async function createKey(request, env) {
  const body = await readJson(request);
  const name = text(body.name, 64);
  if (!name) throw new Refused(400, 'name is required');
  const webhook = body.webhook_url ? String(body.webhook_url).trim().split('?')[0] : null;
  if (webhook && !DISCORD_WEBHOOK.test(webhook)) throw new Refused(400, 'webhook_url must be a Discord webhook');
  const view = body.view_url ? String(body.view_url).trim().replace(/\/+$/, '') : null;
  if (view && !/^https:\/\/[a-z0-9.-]+(?::\d+)?(?:\/[\w./-]*)?$/i.test(view)) throw new Refused(400, 'view_url must be an https address');

  const key = 'bsmm_' + base64url(crypto.getRandomValues(new Uint8Array(32)));
  const made = await env.DB.prepare('INSERT INTO tenants (name, key_hash, webhook_url, view_url, created_at) VALUES (?, ?, ?, ?, ?) RETURNING id')
    .bind(name, await sha256(key), webhook, view, Date.now()).first();
  return json({ id: made.id, name, key }, 201);
}

async function listKeys(env) {
  const { results } = await env.DB.prepare('SELECT id, name, created_at, disabled, webhook_url IS NOT NULL AS has_webhook, view_url FROM tenants ORDER BY id').all();
  return json({ keys: results.map((row) => ({ ...row, disabled: Boolean(row.disabled), has_webhook: Boolean(row.has_webhook) })) });
}

async function revokeKey(env, id) {
  const { meta } = await env.DB.prepare('UPDATE tenants SET disabled = 1 WHERE id = ?').bind(id).run();
  if (!meta.changes) throw new Refused(404, 'not found');
  return json({ ok: true });
}

// ---------------------------------------------------------------------------------------------
// Starting a check and handing out the script
// ---------------------------------------------------------------------------------------------

async function createCheck(request, env, tenant, origin) {
  const body = await readJson(request);
  const mode = body.mode === undefined ? 'check' : body.mode;
  if (mode !== 'check' && mode !== 'monitor') throw new Refused(400, 'mode must be check or monitor');
  const robloxId = body.roblox_id === undefined || body.roblox_id === null ? null : String(body.roblox_id);
  if (robloxId !== null && !ROBLOX_ID.test(robloxId)) throw new Refused(400, 'roblox_id must be a number');
  const player = text(body.player, 64) || null;
  const requestedBy = text(body.requested_by, 64) || null;
  const matches = cleanMatches(body.matches);

  const now = Date.now();
  await env.DB.prepare('DELETE FROM checks WHERE tenant_id = ? AND created_at < ?').bind(tenant.id, now - RETENTION).run();
  const recent = await env.DB.prepare('SELECT COUNT(*) AS n FROM checks WHERE tenant_id = ? AND created_at > ?').bind(tenant.id, now - 60_000).first();
  if (recent.n >= CHECKS_PER_MINUTE) throw new Refused(429, 'rate limited');

  const id = 'BSMM-' + randomText(8);
  const code = randomText(20);
  const expires = now + CODE_TTL;
  await env.DB.prepare(
    'INSERT INTO checks (id, tenant_id, code, mode, key, player, roblox_id, requested_by, matches, created_at, expires_at, search) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  ).bind(id, tenant.id, code, mode, hex(crypto.getRandomValues(new Uint8Array(32))), player, robloxId, requestedBy, matches.length ? JSON.stringify(matches) : null, now, expires, searchText([id, player, requestedBy, robloxId])).run();

  return json({ id, code, command: `irm ${origin}/c/${code} | iex`, expires_at: expires }, 201);
}

// The player's recent matches, from the league's own records. They stay on the relay: the script is
// never told which times it is being compared against.
function cleanMatches(value) {
  if (value === undefined || value === null) return [];
  const refused = new Refused(400, `matches must be a list of up to ${MAX_MATCHES} items with id and started_at (unix seconds)`);
  if (!Array.isArray(value) || value.length > MAX_MATCHES) throw refused;
  return value.map((match) => {
    const item = match && typeof match === 'object' ? match : {};
    const id = text(String(item.id ?? ''), 40);
    const started = stamp(item.started_at);
    const ended = item.ended_at === undefined || item.ended_at === null ? null : stamp(item.ended_at);
    if (!id || !started || (ended === null ? item.ended_at != null : ended < started)) throw refused;
    return { id, started_at: started, ended_at: ended };
  });
}

const scriptCache = new Map();
async function scriptSource(env, mode) {
  const url = `${String(env.SCRIPT_BASE_URL || DEFAULT_SCRIPTS).replace(/\/+$/, '')}/${SCRIPT_FILES[mode]}`;
  const cached = scriptCache.get(url);
  if (cached && Date.now() - cached.at < 60_000) return cached.source;
  const response = await fetch(url);
  if (!response.ok) return null;
  const source = (await response.text()).replace(/^\uFEFF/, '');
  scriptCache.set(url, { source, at: Date.now() });
  return source;
}

// The response is piped straight into PowerShell, so every outcome has to be a runnable script.
function scriptMessage(message) {
  return new Response(`Write-Host '${message}' -ForegroundColor Yellow\r\n`, { headers: SCRIPT_HEADERS });
}

const SCRIPT_HEADERS = { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' };
const notPowerShell = (request) => (/powershell/i.test(request.headers.get('user-agent') || '')
  ? null
  : new Response('Paste the whole command into PowerShell. Opening this address in a browser does nothing.', { headers: { 'cache-control': 'no-store' } }));

// The command every player pastes: it asks for their one-time code, then loads that check.
// It is the same for everyone, so it holds no session and says nothing about the checks.
function startScript(request, origin) {
  const lines = [
    "$code = ((Read-Host 'Paste the code BSMM staff gave you, then press Enter') -replace '[^A-Za-z0-9]', '').ToUpper()",
    `if ($code) { irm "${origin}/c/$code" | iex } else { Write-Host 'No code entered. Run the command again when you have your code.' -ForegroundColor Yellow }`,
  ];
  return notPowerShell(request) || new Response(lines.join('\r\n') + '\r\n', { headers: SCRIPT_HEADERS });
}

async function serveScript(request, env, code, origin) {
  // Link previews and browsers must not use up the code: only PowerShell gets the script.
  const refused = notPowerShell(request);
  if (refused) return refused;
  const invalid = 'This BSMM check code is invalid, expired or already used. Ask staff for a new one.';
  if (!CODE.test(code)) return scriptMessage(invalid);

  const now = Date.now();
  const check = await env.DB.prepare(
    `UPDATE checks SET fetched_at = ?, fetch_ip = ? WHERE code = ? AND fetched_at IS NULL AND expires_at > ?
       AND tenant_id IN (SELECT id FROM tenants WHERE disabled = 0) RETURNING id, key, mode`,
  ).bind(now, clientIp(request), code, now).first();
  if (!check) return scriptMessage(invalid);

  const source = await scriptSource(env, check.mode).catch(() => null);
  if (!source) {
    await env.DB.prepare('UPDATE checks SET fetched_at = NULL, fetch_ip = NULL WHERE id = ?').bind(check.id).run();
    return scriptMessage('The BSMM check could not be loaded. Wait a moment and run the same command again.');
  }
  const version = (source.match(/\bVersion\s*=\s*'([\d.]{1,16})'/) || [])[1] || '';
  const expected = [...source.matchAll(/@\{\s*Name\s*=\s*'([^']{1,64})';\s*Caption\s*=/g)].map((match) => match[1]);
  await env.DB.prepare('UPDATE checks SET script_version = ?, script_hash = ?, expected_checks = ? WHERE id = ?')
    .bind(version, await sha256(source), JSON.stringify(expected), check.id).run();

  const session = `$global:BsmmSession = @{ Id = '${check.id}'; Key = '${check.key}'; Relay = '${origin}'; Mode = '${check.mode}' }\r\n`;
  return new Response(session + source, { headers: SCRIPT_HEADERS });
}

// ---------------------------------------------------------------------------------------------
// Reports from the player's PC
// ---------------------------------------------------------------------------------------------

// Every refusal looks the same, so a caller learns nothing about which checks exist.
async function signedBody(request, env, mode) {
  const refused = new Refused(401, 'unauthorised');
  if (Number(request.headers.get('content-length') || 0) > MAX_BODY) throw new Refused(413, 'too large');
  const raw = await request.text();
  if (raw.length > MAX_BODY) throw new Refused(413, 'too large');

  const id = request.headers.get('x-bsmm-check') || '';
  const seqText = request.headers.get('x-bsmm-seq') || '0';
  const signature = request.headers.get('x-bsmm-sig') || '';
  if (!CHECK_ID.test(id) || !/^\d{1,9}$/.test(seqText) || !/^[0-9a-f]{64}$/.test(signature)) throw refused;

  const check = await env.DB.prepare(
    `SELECT c.*, t.name AS tenant_name, t.webhook_url, t.view_url FROM checks c JOIN tenants t ON t.id = c.tenant_id
      WHERE c.id = ? AND t.disabled = 0`,
  ).bind(id).first();
  if (!check || !check.key || check.mode !== mode || !check.fetched_at) throw refused;
  if (!safeEqual(signature, await hmac(check.key, `${id}.${seqText}.${await sha256(raw)}`))) throw refused;

  let body;
  try { body = JSON.parse(raw); } catch { throw new Refused(400, 'bad report'); }
  if (!body || typeof body !== 'object') throw new Refused(400, 'bad report');
  return { check, body, seq: Number(seqText), refused };
}

async function fileReport(request, env) {
  const { check, body, seq, refused } = await signedBody(request, env, 'check');
  const now = Date.now();
  if (seq !== 0 || now - check.fetched_at > REPORT_WINDOW) throw refused;
  const report = cleanReport(body);
  if (!report.checks.length) throw new Refused(400, 'bad report');

  const claimed = await env.DB.prepare('UPDATE checks SET reported_at = ? WHERE id = ? AND reported_at IS NULL RETURNING id').bind(now, check.id).first();
  if (!claimed) throw refused;

  const view = await assemble(env, check, report, { now, ip: clientIp(request) });
  view.verdict = verdictOf(view);
  const messageId = await postDiscord(check, reportMessage(view, check), { name: `${check.id}-system-check.txt`, text: reportLog(view, check) });
  await saveReport(env, check, view, { key: '', message_id: messageId, fetch_ip: null });
  return json({ ok: true, id: check.id });
}

async function liveUpdate(request, env) {
  const { check, body, seq, refused } = await signedBody(request, env, 'monitor');
  const now = Date.now();
  if (check.ended_at || now - check.fetched_at > LIVE_WINDOW || seq < 1) throw refused;
  const state = body.state === 'ENDED' ? 'ENDED' : 'RUNNING';
  const live = cleanLive(body, state);

  const claimed = await env.DB.prepare('UPDATE checks SET live_seq = ? WHERE id = ? AND live_seq < ? AND ended_at IS NULL RETURNING id').bind(seq, check.id, seq).first();
  if (!claimed) throw refused;

  // Identity and history are judged once, on the first update, and kept for the rest of the match.
  let view = check.report ? JSON.parse(check.report) : null;
  if (!view) view = await assemble(env, check, cleanReport(body), { now, ip: clientIp(request) });
  view.live = live;
  view.verdict = verdictOf(view);

  const message = liveMessage(view, check);
  let messageId = check.message_id;
  if (messageId) await postDiscord(check, message, null, messageId);
  else messageId = await postDiscord(check, message);

  const changes = { message_id: messageId, reported_at: check.reported_at || now };
  if (state === 'ENDED') {
    Object.assign(changes, { ended_at: now, key: '', fetch_ip: null });
    await postDiscord(check, endedMessage(view, check), { name: `${check.id}-live-monitor.txt`, text: liveLog(view, check) });
  }
  await saveReport(env, check, view, changes);
  return json({ ok: true, id: check.id });
}

const str = (value, max) => (typeof value === 'string' ? value.replace(/`/g, "'").replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '').slice(0, max) : '');
const text = (value, max) => str(value, max).replace(/\s+/g, ' ').trim();
const list = (value, max) => (Array.isArray(value) ? value.slice(0, max) : []);
const whole = (value, max) => { const n = Math.floor(Number(value)); return Number.isFinite(n) && n >= 0 && n <= max ? n : 0; };
const stamp = (seconds) => { const n = whole(seconds, 4_000_000_000); return n ? n * 1000 : null; };
const robloxId = (value) => (ROBLOX_ID.test(String(value ?? '')) ? String(value) : null);

const LEVELS = [['FAILURE', 'FAIL'], ['WARNING', 'WARN'], ['SUCCESS', 'PASS'], ['INFO', 'INFO']];
function parseLine(value) {
  const line = text(value, 700);
  for (const [prefix, level] of LEVELS) {
    if (line.startsWith(prefix)) return { level, text: line.slice(prefix.length).replace(/^:\s*/, '') };
  }
  return { level: 'INFO', text: line };
}

// Shapes whatever the PC sent into known fields with bounded sizes. Nothing else is kept.
function cleanReport(body) {
  const checks = list(body.checks, 150).filter((check) => check && typeof check === 'object').map((check) => {
    const lines = list(check.lines, 300).map(parseLine).filter((line) => line.text);
    const status = lines.some((line) => line.level === 'FAIL') ? 'FAIL' : lines.some((line) => line.level === 'WARN') || !lines.length ? 'WARN' : 'PASS';
    return { name: text(check.name, 64) || 'Unnamed check', status, lines };
  });
  const facts = {};
  for (const [key, value] of Object.entries(body.facts && typeof body.facts === 'object' ? body.facts : {}).slice(0, 8)) {
    if (text(key, 24) && text(value, 200)) facts[text(key, 24)] = text(value, 200);
  }
  const roblox = body.roblox && typeof body.roblox === 'object' ? body.roblox : {};
  const accounts = new Map();
  for (const item of list(roblox.accounts, 40)) {
    const id = robloxId(item && item.id);
    if (!id) continue;
    const entry = accounts.get(id) || { id, sources: [], last: null };
    for (const source of list(item.sources, 3)) if (['switcher', 'logs', 'studio'].includes(source) && !entry.sources.includes(source)) entry.sources.push(source);
    entry.last = Math.max(entry.last || 0, stamp(item.last) || 0) || null;
    accounts.set(id, entry);
  }
  const games = list(roblox.games, 12).map((game) => ({ placeId: robloxId(game && game.placeId), universeId: robloxId(game && game.universeId), at: stamp(game && game.at), userId: robloxId(game && game.userId) }))
    .filter((game) => game.placeId);
  const current = robloxId(roblox.userId);
  if (current && !accounts.has(current)) accounts.set(current, { id: current, sources: [], last: null });

  const programs = new Map();
  for (const item of list(body.programs, 6000)) {
    if (!item || typeof item !== 'object') continue;
    const path = text(item.path, 300);
    const at = stamp(item.at);
    if (!path || !at || !PROGRAM_SOURCES.includes(item.src)) continue;
    const key = `${item.src}|${at}|${path.toLowerCase()}`;
    if (programs.has(key)) continue;
    const run = { path, name: path.split(/[\\/]/).pop(), at, src: item.src, sig: SIGNATURES.includes(item.sig) ? item.sig : 'unknown', signer: text(item.signer, 60), runs: whole(item.runs, 1_000_000) };
    if (FILE_HASH.test(item.hash)) run.hash = item.hash;
    programs.set(key, run);
  }
  const runs = [...programs.values()].sort((a, b) => b.at - a.at);

  return {
    clock: stamp(body.clock),
    programs: runs.slice(0, MAX_PROGRAMS),
    programsComplete: runs.length <= MAX_PROGRAMS,
    version: text(body.v, 16),
    seconds: whole(body.seconds, 36_000),
    admin: body.admin === true,
    facts,
    checks,
    current,
    accounts: [...accounts.values()],
    games,
    pc: /^[0-9a-f]{64}$/.test(String(body.pc || '')) ? String(body.pc) : null,
  };
}

function cleanLive(body, state) {
  const counts = body.counts && typeof body.counts === 'object' ? body.counts : {};
  const alert = (value) => {
    const line = text(value, 300);
    const match = line.match(/^\[([^\]]{1,24})\]\s*\[(FAIL|WARN|INFO)\]\s*(.*)$/);
    return match ? { at: match[1], level: match[2], text: match[3] } : { at: '', level: 'INFO', text: line };
  };
  return {
    state,
    elapsed: whole(body.elapsed, 86_400),
    counts: { fail: whole(counts.fail, 100_000), warn: whole(counts.warn, 100_000), info: whole(counts.info, 100_000) },
    alerts: list(body.recent, 30).map(alert).filter((entry) => entry.text),
    log: state === 'ENDED' ? list(body.log, 2500).map(alert).filter((entry) => entry.text) : [],
  };
}

// ---------------------------------------------------------------------------------------------
// What the relay works out for itself
// ---------------------------------------------------------------------------------------------

async function assemble(env, check, report, { now, ip }) {
  const flags = [];
  const flag = (level, code, message) => flags.push({ level, code, text: message });
  const scanSeconds = Math.round((now - check.fetched_at) / 1000);

  if (check.mode === 'check') {
    if (scanSeconds < MIN_SCAN_SECONDS) flag('FAIL', 'fast_scan', `The report arrived ${scanSeconds}s after the script was downloaded. A real scan takes longer.`);
    const expected = safeParse(check.expected_checks, []);
    const seen = new Set(report.checks.map((item) => item.name));
    const missing = expected.filter((name) => !seen.has(name));
    if (missing.length) flag('FAIL', 'missing_checks', `${missing.length} of ${expected.length} checks are missing from the report: ${missing.slice(0, 6).join(', ')}${missing.length > 6 ? '...' : ''}`);
  }
  if (check.script_version && report.version !== check.script_version) {
    flag('FAIL', 'version_mismatch', `The report says script version ${report.version || 'unknown'}, but the relay served ${check.script_version}.`);
  }
  if (check.fetch_ip && ip !== check.fetch_ip) flag('WARN', 'ip_changed', 'The report came from a different IP address than the script download.');

  // History: what earlier checks from this league saw on this PC and for this player.
  const ids = report.accounts.map((account) => account.id);
  let pcSeen = [];
  if (report.pc) {
    pcSeen = (await env.DB.prepare(
      `SELECT id, player, roblox_id, reported_at, score, label, account_ids FROM checks
        WHERE tenant_id = ? AND pc_hash = ? AND id != ? ORDER BY reported_at DESC LIMIT 25`,
    ).bind(check.tenant_id, report.pc, check.id).all()).results;
  }
  const gone = [...new Set(pcSeen.flatMap((row) => String(row.account_ids || '').split(',').filter(Boolean)))].filter((id) => !ids.includes(id)).slice(0, 8);

  // Names come from Roblox, never from the player's PC.
  const [users, games] = await Promise.all([
    robloxUsers([...new Set([...ids, check.roblox_id, ...gone].filter(Boolean))]),
    robloxGames([...new Set(report.games.map((game) => game.universeId).filter(Boolean))]),
  ]);
  const person = (id) => (id ? { id, name: users.get(id)?.name ?? null, displayName: users.get(id)?.displayName ?? null } : null);
  const named = (id) => (users.get(id)?.name ? `${users.get(id).name} (${id})` : id);

  if (check.roblox_id) {
    if (!ids.length) flag('WARN', 'no_account', 'No Roblox account data was found on this PC.');
    else if (report.current !== check.roblox_id) {
      if (ids.includes(check.roblox_id)) flag('WARN', 'account_not_active', `The verified account ${named(check.roblox_id)} has been used on this PC, but ${report.current ? named(report.current) : 'no account'} is the one logged in.`);
      else flag('FAIL', 'account_mismatch', `The verified account ${named(check.roblox_id)} has never been used on this PC. Logged in: ${report.current ? named(report.current) : 'nobody'}.`);
    }
  }
  const others = [...new Set(pcSeen.filter((row) => row.roblox_id && check.roblox_id && row.roblox_id !== check.roblox_id).map((row) => row.player || row.roblox_id))];
  if (others.length) flag('WARN', 'pc_shared', `This PC was also checked for: ${others.slice(0, 5).join(', ')}.`);
  if (gone.length) flag('WARN', 'accounts_removed', `Accounts seen on this PC in an earlier check are no longer there: ${gone.map(named).join(', ')}.`);
  if (report.pc && check.roblox_id) {
    const last = await env.DB.prepare(
      `SELECT id, pc_hash, reported_at FROM checks WHERE tenant_id = ? AND roblox_id = ? AND id != ? AND pc_hash IS NOT NULL
        ORDER BY reported_at DESC LIMIT 1`,
    ).bind(check.tenant_id, check.roblox_id, check.id).first();
    if (last && last.pc_hash !== report.pc) flag('WARN', 'pc_changed', `This is a different PC from this player's last check (${last.id}).`);
  }

  const programs = await programActivity(env, check, report, now, flag);
  await sharedPrograms(env, check, report, now, flag);

  return {
    programs,
    flags,
    timing: { issued: check.created_at, downloaded: check.fetched_at, reported: now, scan_seconds: scanSeconds },
    script: { version: check.script_version || null, reported_version: report.version || null, hash: check.script_hash || null },
    seconds: report.seconds,
    admin: report.admin,
    facts: report.facts,
    roblox: {
      expected: person(check.roblox_id),
      current: person(report.current),
      accounts: report.accounts.map((account) => ({ ...person(account.id), sources: account.sources, last: account.last })),
      games: report.games.map((game) => ({ ...game, name: games.get(game.universeId) ?? null })),
    },
    pc: { hash: report.pc, seen: pcSeen.map((row) => ({ id: row.id, player: row.player, roblox_id: row.roblox_id, at: row.reported_at, score: row.score, label: row.label })) },
    checks: report.checks,
    live: null,
  };
}

const span = (seconds) => (seconds < 60 ? `${seconds}s` : seconds < 3600 ? `${Math.floor(seconds / 60)}m ${seconds % 60}s` : `${Math.floor(seconds / 3600)}h ${Math.floor(seconds / 60) % 60}m`);
const plural = (count, word) => `${count} ${word}${count === 1 ? '' : word.endsWith('ch') ? 'es' : 's'}`;

// When each program ran, on the relay's clock, and which of the player's matches it ran around.
async function programActivity(env, check, report, now, flag) {
  // Program times come from the PC's clock. When that clock is off, move them onto ours.
  const skew = report.clock ? Math.round((now - report.clock) / 1000) : 0;
  const shift = Math.abs(skew) > CLOCK_TOLERANCE ? skew : 0;
  if (shift) flag('WARN', 'clock_skew', `The PC clock is ${span(Math.abs(shift))} ${shift > 0 ? 'behind' : 'ahead'}. Program times were corrected to real time.`);
  const runs = report.programs.map((run) => ({ ...run, at: run.at + shift * 1000 }));

  const matches = safeParse(check.matches, []).map((match) => {
    const end = Math.min(match.ended_at ?? match.started_at + MATCH_LENGTH, now);
    const started = (run) => run.at >= match.started_at - MATCH_LEAD && run.at <= end;
    const inside = (run) => {
      if (run.src === 'exit') return run.at >= match.started_at && run.at <= end + MATCH_LEAD;
      // Still running at the check, so it ran for the whole match however long ago it started.
      if (run.src === 'running' && run.sig !== 'signed') return run.at <= end;
      return started(run);
    };
    const found = runs.filter(inside).sort((a, b) => a.at - b.at).slice(0, 80);
    return { ...match, runs: found.map((run) => ({ ...run, offset: Math.round((run.at - match.started_at) / 1000) })) };
  }).sort((a, b) => b.started_at - a.started_at);

  // Signed programs are listed for staff but never count against the player.
  const suspects = new Map();
  for (const match of matches) {
    const once = new Map(match.runs.filter((run) => run.sig !== 'signed').map((run) => [run.path.toLowerCase(), run]));
    for (const [key, run] of once) {
      const entry = suspects.get(key) || { name: run.name, missing: false, matches: 0 };
      entry.matches += 1;
      entry.missing ||= run.sig === 'missing';
      suspects.set(key, entry);
    }
  }
  const ranked = [...suspects.values()].sort((a, b) => b.matches - a.matches);
  const deleted = ranked.filter((entry) => entry.missing && entry.matches >= 2);
  const others = ranked.filter((entry) => !deleted.includes(entry));
  const label = (entry) => `${entry.name} (${entry.matches} of ${plural(matches.length, 'match')})`;
  if (deleted.length) flag('FAIL', 'match_program_deleted', `Programs that ran around several matches and have since been deleted: ${deleted.slice(0, 5).map(label).join(', ')}.`);
  if (others.length) flag('WARN', 'match_programs', `Programs without a trusted signature ran around this player's matches: ${others.slice(0, 6).map(label).join(', ')}${others.length > 6 ? ` and ${others.length - 6} more` : ''}.`);

  // A wipe: programs that were in the launch history at the last check of this PC and are gone now.
  if (report.pc && runs.length) {
    const before = await env.DB.prepare(
      `SELECT report, script_version FROM checks WHERE tenant_id = ? AND pc_hash = ? AND id != ? AND report IS NOT NULL
        ORDER BY reported_at DESC, created_at DESC LIMIT 1`,
    ).bind(check.tenant_id, report.pc, check.id).first();
    const earlier = before && before.script_version === check.script_version ? safeParse(before.report, null)?.programs?.runs ?? [] : [];
    const have = new Set(runs.map((run) => `${run.src}|${run.path.toLowerCase()}`));
    const oldest = (src) => Math.min(...runs.filter((run) => run.src === src).map((run) => run.at));
    const removed = [...new Map(earlier
      .filter((run) => LAST_RUN_SOURCES.includes(run.src) && !have.has(`${run.src}|${run.path.toLowerCase()}`) && (report.programsComplete || run.at >= oldest(run.src)))
      .map((run) => [run.path.toLowerCase(), run.name])).values()];
    if (removed.length) flag('WARN', 'history_removed', `${plural(removed.length, 'program')} that ${removed.length === 1 ? 'was' : 'were'} in this PC's launch history at the last check ${removed.length === 1 ? 'is' : 'are'} no longer in it: ${removed.slice(0, 6).join(', ')}${removed.length > 6 ? '...' : ''}.`);
  }

  return { skew_seconds: shift, runs, matches };
}

// Programs nobody has named as a cheat still give themselves away by the company they keep: an unsigned
// program is fingerprinted by the script, and one that mostly turns up on flagged PCs is itself flagged,
// whatever it is called. A PC counts as flagged only for what its own scan found, never for a flag raised
// here, so this cannot feed on itself. A program is held against a player only when it is clearly more
// common on flagged PCs than flagged PCs are in the league, so a league that mostly checks suspects does
// not end up blaming whatever launcher they all use.
async function sharedPrograms(env, check, report, now, flag) {
  const mine = new Map(report.programs.filter((run) => run.hash).map((run) => [run.hash, run.name]));
  if (!mine.size) return;
  const hashes = [...mine.keys()].slice(0, MAX_HASHES);
  await ensureSchema(env);
  await env.DB.prepare('DELETE FROM program_sightings WHERE tenant_id = ? AND seen_at < ?').bind(check.tenant_id, now - RETENTION).run();

  const [league, { results }] = await Promise.all([
    env.DB.prepare('SELECT COUNT(*) AS checks, COALESCE(SUM(failed >= ?), 0) AS flagged FROM checks WHERE tenant_id = ? AND id != ? AND reported_at IS NOT NULL')
      .bind(FLAGGED_FAILS, check.tenant_id, check.id).first(),
    env.DB.prepare(
      `SELECT s.hash, c.id, c.pc_hash, c.failed FROM program_sightings s JOIN checks c ON c.id = s.check_id
        WHERE s.tenant_id = ? AND s.check_id != ? AND s.hash IN (${hashes.map(() => '?').join(', ')})`,
    ).bind(check.tenant_id, check.id, ...hashes).all(),
  ]);
  const usual = league.checks ? league.flagged / league.checks : 0;

  // One entry per other PC, flagged if any of its checks was.
  const seen = new Map();
  for (const row of results) {
    if (report.pc && row.pc_hash === report.pc) continue;
    const pcs = seen.get(row.hash) || new Map();
    const pc = row.pc_hash || row.id;
    pcs.set(pc, pcs.get(pc) || row.failed >= FLAGGED_FAILS);
    seen.set(row.hash, pcs);
  }
  const shared = [...seen].map(([hash, pcs]) => ({ name: mine.get(hash), pcs: pcs.size, flagged: [...pcs.values()].filter(Boolean).length }))
    .map((entry) => ({ ...entry, share: entry.flagged / entry.pcs }))
    .filter((entry) => entry.flagged >= 2 && entry.share >= Math.max(0.5, usual + SHARED_MARGIN))
    .sort((a, b) => b.flagged - a.flagged);
  if (shared.length) {
    // Two flagged PCs is worth a look. Three, with at most one clean PC in four, counts against the player.
    const level = shared.some((entry) => entry.flagged >= 3 && entry.share >= 0.75) ? 'FAIL' : 'WARN';
    flag(level, 'shared_program', `Programs without a trusted signature that mostly turn up on flagged PCs: ${shared.slice(0, 5).map((entry) => `${entry.name} (${plural(entry.pcs, 'other PC')}, ${entry.flagged} flagged)`).join(', ')}${shared.length > 5 ? ` and ${shared.length - 5} more` : ''}.`);
  }

  await env.DB.batch(hashes.map((hash) => env.DB.prepare('INSERT OR IGNORE INTO program_sightings (tenant_id, hash, check_id, seen_at) VALUES (?, ?, ?, ?)').bind(check.tenant_id, hash, check.id, now)));
}

function verdictOf(view) {
  const count = (items, level) => items.filter((item) => (item.level || item.status) === level).length;
  const failed = count(view.checks, 'FAIL') + count(view.flags, 'FAIL');
  const review = count(view.checks, 'WARN') + count(view.flags, 'WARN');
  let score = 100 - Math.min(WEIGHTS.failCap, failed * WEIGHTS.fail) - Math.min(WEIGHTS.warnCap, review * WEIGHTS.warn);
  if (!view.admin) score -= WEIGHTS.notAdmin;
  if (view.live) score -= Math.min(WEIGHTS.liveCap, view.live.counts.fail * WEIGHTS.liveFail + view.live.counts.warn * WEIGHTS.liveWarn);
  // A report that cannot be the real scan says nothing about the PC, however clean it looks.
  if (view.flags.some((item) => UNTRUSTED_REPORT.has(item.code))) score = Math.min(score, 25);
  score = Math.max(0, Math.min(100, score));
  return { score, label: LABELS.find((entry) => score < entry.below).label };
}

async function robloxUsers(ids) {
  const found = new Map();
  if (!ids.length) return found;
  try {
    const response = await fetch('https://users.roblox.com/v1/users', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ userIds: ids.slice(0, 50).map(Number), excludeBannedUsers: false }),
    });
    if (response.ok) for (const user of (await response.json()).data || []) found.set(String(user.id), { name: text(user.name, 40), displayName: text(user.displayName, 40) });
  } catch {}
  return found;
}

async function robloxGames(universeIds) {
  const found = new Map();
  if (!universeIds.length) return found;
  try {
    const response = await fetch(`https://games.roblox.com/v1/games?universeIds=${universeIds.slice(0, 12).join(',')}`);
    if (response.ok) for (const game of (await response.json()).data || []) found.set(String(game.id), text(game.name, 100));
  } catch {}
  return found;
}

async function saveReport(env, check, view, changes) {
  // A PC check counts its checks; a live monitor has none and counts its alerts.
  const failed = view.checks.filter((item) => item.status === 'FAIL').length + (view.live?.counts.fail ?? 0);
  const review = view.checks.filter((item) => item.status === 'WARN').length + (view.live?.counts.warn ?? 0);
  const accounts = view.roblox.accounts;
  const columns = {
    report: JSON.stringify(view),
    score: view.verdict.score,
    label: view.verdict.label,
    failed,
    review,
    flag_count: view.flags.length,
    pc_hash: view.pc.hash,
    account_ids: accounts.map((account) => account.id).join(','),
    search: searchText([check.id, check.player, check.requested_by, check.roblox_id, view.pc.hash, ...accounts.flatMap((account) => [account.id, account.name, account.displayName])]),
    ...changes,
  };
  const names = Object.keys(columns);
  await env.DB.prepare(`UPDATE checks SET ${names.map((name) => `${name} = ?`).join(', ')} WHERE id = ?`).bind(...names.map((name) => columns[name] ?? null), check.id).run();
}

const searchText = (parts) => parts.filter(Boolean).join(' ').toLowerCase();

// ---------------------------------------------------------------------------------------------
// Reading reports (bots and the staff website)
// ---------------------------------------------------------------------------------------------

function statusOf(row, now) {
  if (row.ended_at) return 'ended';
  if (row.reported_at) return row.mode === 'monitor' ? 'live' : 'reported';
  if (row.fetched_at) return now - row.fetched_at > (row.mode === 'monitor' ? LIVE_WINDOW : REPORT_WINDOW) ? 'no_report' : 'downloaded';
  return row.expires_at < now ? 'expired' : 'pending';
}

function summary(row, now) {
  return {
    id: row.id,
    mode: row.mode,
    status: statusOf(row, now),
    player: row.player,
    roblox_id: row.roblox_id,
    requested_by: row.requested_by,
    created_at: row.created_at,
    fetched_at: row.fetched_at,
    reported_at: row.reported_at,
    ended_at: row.ended_at,
    verdict: row.label ? { score: row.score, label: row.label } : null,
    failed: row.failed ?? 0,
    review: row.review ?? 0,
    flag_count: row.flag_count ?? 0,
  };
}

const SUMMARY_COLUMNS = 'id, mode, player, roblox_id, requested_by, created_at, expires_at, fetched_at, reported_at, ended_at, score, label, failed, review, flag_count';

async function listChecks(env, tenant, params) {
  const now = Date.now();
  const where = ['tenant_id = ?'];
  const args = [tenant.id];
  const query = text(params.get('q') || '', 80).toLowerCase();
  if (query) { where.push("search LIKE ? ESCAPE '\\'"); args.push(`%${query.replace(/[\\%_]/g, '\\$&')}%`); }
  const verdict = params.get('verdict');
  if (verdict) { if (!LABELS.some((entry) => entry.label === verdict)) throw new Refused(400, 'bad verdict'); where.push('label = ?'); args.push(verdict); }
  const mode = params.get('mode');
  if (mode) { if (!SCRIPT_FILES[mode]) throw new Refused(400, 'bad mode'); where.push('mode = ?'); args.push(mode); }
  const before = params.get('before');
  if (before) {
    const cursor = before.match(/^(\d{1,16})_(BSMM-[2-9A-HJ-NP-Z]{8})$/);
    if (!cursor) throw new Refused(400, 'bad cursor');
    where.push('(created_at < ? OR (created_at = ? AND id < ?))');
    args.push(Number(cursor[1]), Number(cursor[1]), cursor[2]);
  }
  const limit = Math.min(50, Math.max(1, whole(params.get('limit') || 25, 50) || 25));

  const { results } = await env.DB.prepare(`SELECT ${SUMMARY_COLUMNS} FROM checks WHERE ${where.join(' AND ')} ORDER BY created_at DESC, id DESC LIMIT ?`).bind(...args, limit + 1).all();
  const page = results.slice(0, limit);
  const last = page[page.length - 1];
  const totals = await env.DB.prepare(
    `SELECT COUNT(*) AS total,
            SUM(CASE WHEN label = 'HIGH RISK' THEN 1 ELSE 0 END) AS high,
            SUM(CASE WHEN label = 'SUSPICIOUS' THEN 1 ELSE 0 END) AS suspicious,
            SUM(CASE WHEN label = 'REVIEW' THEN 1 ELSE 0 END) AS review,
            SUM(CASE WHEN label = 'TRUSTED' THEN 1 ELSE 0 END) AS trusted,
            SUM(CASE WHEN reported_at IS NULL AND fetched_at IS NOT NULL AND fetched_at < ? THEN 1 ELSE 0 END) AS no_report
       FROM checks WHERE tenant_id = ? AND created_at > ?`,
  ).bind(now - REPORT_WINDOW, tenant.id, now - 30 * 86_400_000).first();

  return json({
    checks: page.map((row) => summary(row, now)),
    next: results.length > limit ? `${last.created_at}_${last.id}` : null,
    totals: { all: totals.total, highRisk: totals.high ?? 0, suspicious: totals.suspicious ?? 0, review: totals.review ?? 0, trusted: totals.trusted ?? 0, noReport: totals.no_report ?? 0 },
  });
}

async function readCheck(env, tenant, id) {
  const row = await env.DB.prepare(`SELECT ${SUMMARY_COLUMNS}, report FROM checks WHERE id = ? AND tenant_id = ?`).bind(id, tenant.id).first();
  if (!row) throw new Refused(404, 'not found');
  const view = safeParse(row.report, null);
  const base = summary(row, Date.now());
  if (!view) return json({ ...base, flags: [], checks: [], roblox: null, pc: null, facts: {}, timing: null, script: null, live: null });
  const { verdict, ...detail } = view;
  return json({ ...base, ...detail, pc: { ...view.pc, hash: view.pc.hash ? view.pc.hash.slice(0, 12) : null } });
}

// ---------------------------------------------------------------------------------------------
// Discord
// ---------------------------------------------------------------------------------------------

async function postDiscord(check, payload, file = null, editId = null) {
  if (!check.webhook_url) return null;
  const body = { username: 'BSMM Anti-Cheat', ...payload, allowed_mentions: { parse: [] } };
  let init;
  if (file) {
    const form = new FormData();
    form.append('payload_json', JSON.stringify(body));
    form.append('files[0]', new Blob([file.text.slice(0, 1_000_000)], { type: 'text/plain' }), file.name);
    init = { method: 'POST', body: form };
  } else {
    init = { method: editId ? 'PATCH' : 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) };
  }
  try {
    const response = await fetch(editId ? `${check.webhook_url}/messages/${editId}` : `${check.webhook_url}?wait=true`, init);
    if (!response.ok) return null;
    return editId || String((await response.json()).id || '') || null;
  } catch {
    return null;
  }
}

const cut = (value, max) => (value.length <= max ? value : value.slice(0, Math.max(0, max - 3)) + '...');
const colorOf = (label) => LABELS.find((entry) => entry.label === label).color;
const nameOf = (person) => (person ? (person.name ? `${person.name} (${person.id})` : person.id) : 'none found');

function identityLines(view, check) {
  const lines = [`**Roblox** ${nameOf(view.roblox.current)}`];
  const alts = view.roblox.accounts.filter((account) => account.id !== view.roblox.current?.id);
  if (alts.length) lines.push(`**Other accounts on this PC (${alts.length})** ${cut(alts.map(nameOf).join(', '), 600)}`);
  const game = view.roblox.games[0];
  if (game) lines.push(`**Last game** ${game.name || 'Unknown game'} (place ${game.placeId})${game.at ? ` <t:${Math.floor(game.at / 1000)}:R>` : ''}`);
  if (check.view_url) lines.push(`**Full report** ${check.view_url}/${check.id}`);
  return lines;
}

function flagField(view) {
  if (!view.flags.length) return [];
  return [{ name: `Relay flags (${view.flags.length})`, value: cut(view.flags.map((item) => `${item.level === 'FAIL' ? 'FAIL' : 'WARN'}  ${item.text}`).join('\n'), 1000) }];
}

const SIGNATURE_TEXT = { signed: 'signed', unsigned: 'unsigned', missing: 'file deleted', unknown: 'signature not readable' };
const SOURCE_TEXT = { running: 'started', exit: 'closed' };

// As many whole lines as fit, then a count of the rest.
function fitLines(lines, max) {
  let out = '';
  for (const [index, line] of lines.entries()) {
    if (out.length + line.length + 1 > max - 30) return `${out}+${lines.length - index} more on the full report`;
    out += `${line}\n`;
  }
  return out.trimEnd();
}

// Discord shows <t:unix:R> as "35 seconds ago" and keeps it counting for everyone who reads the message.
function programFields(view) {
  const line = (run) => { const at = Math.floor(run.at / 1000); return `\`${cut(run.name, 40)}\` ${SIGNATURE_TEXT[run.sig]}, ${SOURCE_TEXT[run.src] || 'ran'} <t:${at}:T> (<t:${at}:R>)`; };
  const fields = [];

  // One line per program: its run around the newest match, and how many other matches it was in.
  const around = new Map();
  for (const match of view.programs.matches) {
    for (const run of match.runs.filter((item) => item.sig !== 'signed')) {
      const entry = around.get(run.path.toLowerCase()) || { run, match, seen: new Set() };
      entry.seen.add(match.id);
      around.set(run.path.toLowerCase(), entry);
    }
  }
  const lines = [...around.values()].sort((a, b) => b.seen.size - a.seen.size).map(({ run, match, seen }) =>
    `${line(run)}, ${span(Math.abs(run.offset))} ${run.offset < 0 ? 'before' : 'into'} match ${match.id}${seen.size > 1 ? `, and ${plural(seen.size - 1, 'other match')}` : ''}`);
  if (lines.length) fields.push({ name: `Programs around matches (${lines.length})`, value: fitLines(lines, 800) });

  const latest = view.programs.runs.filter((run) => run.sig !== 'signed').slice(0, 5).map(line);
  if (latest.length) fields.push({ name: 'Last programs without a trusted signature', value: fitLines(latest, 500) });
  return fields;
}

// Discord refuses a message whose embeds hold more than 6000 characters in total.
const EMBED_BUDGET = 5800;
const embedSize = (embed) => (embed.title?.length ?? 0) + (embed.description?.length ?? 0) + (embed.footer?.text.length ?? 0)
  + (embed.fields ?? []).reduce((sum, field) => sum + field.name.length + field.value.length, 0);

function reportMessage(view, check) {
  const { score, label } = view.verdict;
  const failed = view.checks.filter((item) => item.status === 'FAIL');
  const review = view.checks.filter((item) => item.status === 'WARN');
  const downloadDelay = Math.round((view.timing.downloaded - view.timing.issued) / 1000);
  const description = [
    ...identityLines(view, check),
    `Requested by ${check.requested_by || 'staff'}, downloaded ${downloadDelay}s after the code was issued, reported ${view.timing.scan_seconds}s after the download.`,
  ].join('\n');

  const fields = [...flagField(view), ...programFields(view)];
  if (review.length) fields.push({ name: `Review (${review.length})`, value: cut(review.map((item) => item.name).join(', '), 500) });
  const facts = Object.entries(view.facts).map(([key, value]) => `${key}: ${value}`);
  facts.push(`Admin: ${view.admin ? 'yes' : 'NO, checks incomplete'}`);
  fields.push({ name: 'System', value: cut(facts.join(' | '), 600) });

  const embeds = [{
    title: cut(`${label} ${score}/100 \u00b7 ${check.player || view.roblox.current?.name || 'Unknown player'}`, 250),
    description: cut(description, 1500),
    color: colorOf(label),
    fields,
    footer: { text: `${check.id} \u00b7 PC check v${view.script.version || '?'} \u00b7 ${failed.length} failed, ${review.length} to review, ${view.checks.length} checks` },
    timestamp: new Date(view.timing.reported).toISOString(),
  }];

  if (failed.length) {
    const room = Math.min(2600, EMBED_BUDGET - embedSize(embeds[0]) - 60);
    let body = '';
    for (const item of failed) {
      const findings = [...new Map(item.lines.filter((line) => line.level === 'FAIL').map((line) => [line.text.toLowerCase(), line.text])).values()];
      let block = `${item.name}\n` + findings.slice(0, 3).map((finding) => `  ${cut(finding, 170)}\n`).join('');
      if (findings.length > 3) block += `  +${findings.length - 3} more in the log\n`;
      if (body.length + block.length > room) { body += '...more in the log\n'; break; }
      body += block;
    }
    embeds.push({ title: `Failed (${failed.length})`, description: '```text\n' + body + '```', color: colorOf(label) });
  }
  return { embeds };
}

function liveMessage(view, check) {
  const { score, label } = view.verdict;
  const live = view.live;
  const recent = live.alerts.filter((entry) => entry.level !== 'INFO').slice(-12).map((entry) => `${entry.level}  ${entry.at ? entry.at + '  ' : ''}${cut(entry.text, 180)}`).join('\n');
  const clock = `${String(Math.floor(live.elapsed / 3600)).padStart(2, '0')}:${String(Math.floor(live.elapsed / 60) % 60).padStart(2, '0')}:${String(live.elapsed % 60).padStart(2, '0')}`;
  return {
    embeds: [{
      title: cut(`Live monitor ${live.state} \u00b7 ${label} ${score}/100 \u00b7 ${check.player || view.roblox.current?.name || 'Unknown player'}`, 250),
      description: cut([...identityLines(view, check), '```text\n' + (cut(recent, 2400) || 'No suspicious activity so far.') + '\n```'].join('\n'), 3600),
      color: live.state === 'RUNNING' ? 0x7aa2f7 : colorOf(label),
      fields: [
        ...flagField(view),
        { name: 'Monitoring for', value: clock, inline: true },
        { name: 'Alerts', value: `${live.counts.fail} fail / ${live.counts.warn} warn / ${live.counts.info} info`, inline: true },
      ],
      footer: { text: `${check.id} \u00b7 if this stops updating before the match ends, the window was closed` },
      timestamp: new Date().toISOString(),
    }],
  };
}

function endedMessage(view, check) {
  const { score, label } = view.verdict;
  return {
    embeds: [{
      title: cut(`Match finished \u00b7 ${label} ${score}/100 \u00b7 ${check.player || view.roblox.current?.name || 'Unknown player'}`, 250),
      description: `${view.live.counts.fail} fail and ${view.live.counts.warn} warn alerts during the match. The full log is attached.`,
      color: colorOf(label),
      footer: { text: check.id },
      timestamp: new Date().toISOString(),
    }],
  };
}

function logHeader(view, check) {
  return [
    `Report ${check.id}  |  Player ${check.player || 'not given'}  |  ${check.tenant_name}`,
    `Trust score: ${view.verdict.score}/100 (${view.verdict.label})`,
    `Roblox account: ${nameOf(view.roblox.current)}`,
    ...view.roblox.accounts.filter((account) => account.id !== view.roblox.current?.id).map((account) => `Other account: ${nameOf(account)} [${account.sources.join(', ')}]`),
    ...view.flags.map((item) => `Relay flag [${item.level}]: ${item.text}`),
  ];
}

// Every program run with its exact time: readable, as a unix value, and as an age when the report arrived.
function programLog(view) {
  const { runs, matches, skew_seconds: skew } = view.programs;
  if (!runs.length) return [];
  const utc = (ms) => new Date(ms).toISOString().replace('T', ' ').slice(0, 19) + ' UTC';
  const row = (run, note) => `  ${utc(run.at)}  unix ${Math.floor(run.at / 1000)}  ${note.padEnd(26)}  ${(SOURCE_TEXT[run.src] || 'ran').padEnd(7)}  ${run.src.padEnd(10)}  ${SIGNATURE_TEXT[run.sig].padEnd(22)}  ${run.path}${run.signer ? `  [${run.signer}]` : ''}${run.runs ? `  (${plural(run.runs, 'run')})` : ''}`;
  const lines = ['', `Program activity (${runs.length} ${runs.length === 1 ? 'entry' : 'entries'}, newest first)${skew ? `, times corrected by ${skew}s because the PC clock is off` : ''}`];
  for (const match of matches) {
    lines.push('', `Match ${match.id}: started ${utc(match.started_at)} (unix ${Math.floor(match.started_at / 1000)}), ${match.ended_at ? `ended ${utc(match.ended_at)}` : 'no end time'}, ${plural(match.runs.length, 'program')}`);
    for (const run of match.runs) lines.push(row(run, `${span(Math.abs(run.offset))} ${run.offset < 0 ? 'before the start' : 'after the start'}`));
  }
  lines.push('', 'All program runs');
  for (const run of runs) lines.push(row(run, `${span(Math.max(0, Math.round((view.timing.reported - run.at) / 1000)))} before the report`));
  return lines;
}

function reportLog(view, check) {
  const order = { FAIL: 0, WARN: 1, PASS: 2 };
  const lines = [...logHeader(view, check), ...Object.entries(view.facts).map(([key, value]) => `${key}: ${value}`), ''];
  for (const item of [...view.checks].sort((a, b) => order[a.status] - order[b.status])) {
    lines.push(`[${item.status}] ${item.name}`);
    for (const line of item.lines) lines.push(`    ${line.level}: ${line.text}`);
  }
  return [...lines, ...programLog(view)].join('\r\n');
}

function liveLog(view, check) {
  return [...logHeader(view, check), '', ...view.live.log.map((entry) => `${entry.at ? `[${entry.at}] ` : ''}[${entry.level}] ${entry.text}`), ...programLog(view)].join('\r\n');
}

// ---------------------------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------------------------

async function readJson(request) {
  if (Number(request.headers.get('content-length') || 0) > 10_000) throw new Refused(413, 'too large');
  try {
    const body = JSON.parse(await request.text());
    if (body && typeof body === 'object' && !Array.isArray(body)) return body;
  } catch {}
  throw new Refused(400, 'bad request');
}

function safeParse(value, fallback) {
  try { return value ? JSON.parse(value) : fallback; } catch { return fallback; }
}

const hex = (bytes) => [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
const base64url = (bytes) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const randomText = (length) => [...crypto.getRandomValues(new Uint8Array(length))].map((byte) => ALPHABET[byte & 31]).join('');
const clientIp = (request) => request.headers.get('cf-connecting-ip') || 'unknown';

async function sha256(value) {
  return hex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))));
}

async function hmac(key, message) {
  const encoder = new TextEncoder();
  const imported = await crypto.subtle.importKey('raw', encoder.encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return hex(new Uint8Array(await crypto.subtle.sign('HMAC', imported, encoder.encode(message))));
}

function safeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Uses Cloudflare's rate-limit binding if configured (see wrangler.toml), otherwise a per-instance counter.
const hits = new Map();
async function limited(request, env) {
  const ip = clientIp(request);
  if (env.REPORT_LIMITER) {
    const { success } = await env.REPORT_LIMITER.limit({ key: ip });
    return !success;
  }
  const now = Date.now();
  const recent = (hits.get(ip) || []).filter((time) => now - time < 60_000);
  recent.push(now);
  hits.set(ip, recent);
  if (hits.size > 5000) hits.clear();
  return recent.length > PER_MINUTE;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' } });
}
