// Test harness: runs relay/worker.js against an in-memory SQLite database and a fake network.
import { createHmac, createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import worker from '../worker.js';

export const ADMIN = 'admin-secret-admin-secret-admin-secret-0001';
export const RELAY = 'https://relay.test';
export const PS_AGENT = 'Mozilla/5.0 (Windows NT; Windows NT 10.0; en-US) WindowsPowerShell/5.1.26100.1';

export const SCRIPT = [
  '$script:Brand = @{',
  "    Version = '1.3.0'",
  '}',
  '$script:SystemChecks = @(',
  "    @{ Name = 'Alpha';  Caption = 'a'; Run = { } },",
  "    @{ Name = 'Beta';   Caption = 'b'; Run = { } },",
  "    @{ Name = 'Gamma';  Caption = 'c'; Run = { } }",
  ')',
].join('\r\n');

// The slice of the D1 API the worker uses, backed by node:sqlite.
function d1(db) {
  const statement = (sql, args = []) => ({
    bind: (...next) => statement(sql, next),
    first: async () => db.prepare(sql).get(...args) ?? null,
    all: async () => ({ results: db.prepare(sql).all(...args) }),
    run: async () => ({ meta: { changes: Number(db.prepare(sql).run(...args).changes) } }),
  });
  return {
    prepare: (sql) => statement(sql),
    batch: async (list) => { for (const item of list) await item.run(); },
  };
}

// Options: `script` replaces the served script; `users` and `games` name Roblox ids ({ id: name }).
export function createRelay({ script = SCRIPT, users = {}, games = {} } = {}) {
  const sqlite = new DatabaseSync(':memory:');
  const env = { DB: d1(sqlite), ADMIN_SECRET: ADMIN, SCRIPT_BASE_URL: 'https://scripts.test', REPORT_LIMITER: { limit: async () => ({ success: true }) } };
  const discord = [];          // every request the relay sent to a Discord webhook
  const net = { scriptOk: true, robloxOk: true, discordOk: true };

  globalThis.fetch = async (input, init = {}) => {
    const url = String(input);
    if (url.startsWith('https://scripts.test/')) {
      return net.scriptOk ? new Response(script) : new Response('gone', { status: 404 });
    }
    if (url.startsWith('https://discord.com/api/webhooks/')) {
      if (!net.discordOk) return new Response('{}', { status: 500 });
      let payload = null;
      let file = null;
      if (init.body instanceof FormData) {
        payload = JSON.parse(init.body.get('payload_json'));
        const blob = init.body.get('files[0]');
        if (blob) file = { name: blob.name, text: await blob.text() };
      } else {
        payload = JSON.parse(init.body);
      }
      discord.push({ url, method: init.method, payload, file });
      return Response.json({ id: String(900000000000000000n + BigInt(discord.length)) });
    }
    if (url.startsWith('https://users.roblox.com/')) {
      if (!net.robloxOk) return new Response('{}', { status: 503 });
      const ids = JSON.parse(init.body).userIds;
      return Response.json({ data: ids.map((id) => ({ id, name: users[id] ?? `user${id}`, displayName: users[id] ?? `User ${id}` })) });
    }
    if (url.startsWith('https://games.roblox.com/')) {
      if (!net.robloxOk) return new Response('{}', { status: 503 });
      const ids = new URL(url).searchParams.get('universeIds').split(',');
      return Response.json({ data: ids.map((id) => ({ id: Number(id), name: games[id] ?? `Game ${id}`, rootPlaceId: Number(id) * 10 })) });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  let ip = '203.0.113.7';
  let issued = 0;
  const call = async (method, path, { key, body, headers = {}, raw } = {}) => {
    const init = { method, headers: { 'cf-connecting-ip': ip, ...headers } };
    if (key) init.headers.authorization = `Bearer ${key}`;
    if (raw !== undefined) init.body = raw;
    else if (body !== undefined) { init.body = JSON.stringify(body); init.headers['content-type'] = 'application/json'; }
    const response = await worker.fetch(new Request(RELAY + path, init), env);
    const text = await response.text();
    let json = null;
    try { json = JSON.parse(text); } catch {}
    return { status: response.status, text, json, headers: response.headers };
  };

  const relay = {
    env, discord, net, call, sqlite,
    setIp: (next) => { ip = next; },
    sql: (query, ...args) => sqlite.prepare(query).all(...args),

    async tenant(name = 'BSMM', extra = {}) {
      const made = await call('POST', '/admin/keys', { key: ADMIN, body: { name, webhook_url: 'https://discord.com/api/webhooks/123456789012345678/token-abc-0123456789abcdefghij', ...extra } });
      if (made.status !== 201) throw new Error(`tenant: ${made.status} ${made.text}`);
      return made.json;
    },

    async issue(key, body = {}) {
      const made = await call('POST', '/v1/checks', { key, body });
      if (made.status !== 201) throw new Error(`issue: ${made.status} ${made.text}`);
      // Checks made in the same millisecond would list in a random order; space them out.
      sqlite.prepare('UPDATE checks SET created_at = created_at + ? WHERE id = ?').run(++issued, made.json.id);
      return made.json;
    },

    // Downloads the script like PowerShell would and returns the session the relay embedded.
    async download(code) {
      const got = await call('GET', `/c/${code}`, { headers: { 'user-agent': PS_AGENT } });
      const match = got.text.match(/Id = '([^']+)'; Key = '([^']+)'; Relay = '([^']+)'; Mode = '([^']+)'/);
      return { ...got, session: match ? { id: match[1], key: match[2], relay: match[3], mode: match[4] } : null };
    },

    // Issue + download, with the download moved into the past so the scan looks like it took `seconds`.
    async started(key, body = {}, seconds = 90) {
      const check = await relay.issue(key, body);
      const { session } = await relay.download(check.code);
      sqlite.prepare('UPDATE checks SET fetched_at = fetched_at - ? WHERE id = ?').run(seconds * 1000, check.id);
      return { check, session };
    },

    send(session, body, { path = '/v1/report', seq = 0, sig, key = session.key } = {}) {
      const raw = JSON.stringify(body);
      const digest = createHash('sha256').update(raw).digest('hex');
      const signature = sig ?? createHmac('sha256', key).update(`${session.id}.${seq}.${digest}`).digest('hex');
      return call('POST', path, { raw, headers: { 'content-type': 'application/json', 'x-bsmm-check': session.id, 'x-bsmm-seq': String(seq), 'x-bsmm-sig': signature } });
    },
  };
  return relay;
}

export function report(overrides = {}) {
  return {
    v: '1.3.0',
    seconds: 78,
    admin: true,
    facts: { Windows: 'Windows 11 Pro build 26100.2314', Uptime: '3h 12m', Roblox: 'version-abc123 (running)' },
    checks: [
      { name: 'Alpha', lines: ['SUCCESS: nothing found'] },
      { name: 'Beta', lines: ['SUCCESS: nothing found', 'INFO: read 4 files'] },
      { name: 'Gamma', lines: ['SUCCESS: nothing found'] },
    ],
    roblox: {
      userId: '1001',
      accounts: [{ id: '1001', sources: ['switcher', 'logs'], last: 1795000000 }],
      games: [{ placeId: '555', universeId: '77', at: 1795000000, userId: '1001' }],
    },
    pc: 'a'.repeat(64),
    ...overrides,
  };
}
