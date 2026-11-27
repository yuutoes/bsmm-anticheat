import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ADMIN, PS_AGENT, createRelay, report } from './harness.mjs';

const flagCodes = (detail) => detail.flags.map((flag) => flag.code).sort();

async function reported(relay, key, issue = {}, body = {}, seconds = 90) {
  const { check, session } = await relay.started(key, issue, seconds);
  const sent = await relay.send(session, report(body));
  assert.equal(sent.status, 200, sent.text);
  const detail = (await relay.call('GET', `/v1/checks/${check.id}`, { key })).json;
  return { check, session, detail };
}

// ---------------------------------------------------------------- API keys

test('only the admin secret can create API keys', async () => {
  const relay = createRelay();
  const body = { name: 'Other league' };
  assert.equal((await relay.call('POST', '/admin/keys', { body })).status, 401);
  assert.equal((await relay.call('POST', '/admin/keys', { key: 'x'.repeat(43), body })).status, 401);
  assert.equal((await relay.call('POST', '/admin/keys', { key: ADMIN.slice(0, -1) + 'X', body })).status, 401);
  assert.equal((await relay.call('POST', '/admin/keys', { key: ADMIN, body })).status, 201);
});

test('an API key is shown once and only its hash is stored', async () => {
  const relay = createRelay();
  const tenant = await relay.tenant();
  assert.match(tenant.key, /^bsmm_[A-Za-z0-9_-]{43}$/);
  const stored = JSON.stringify(relay.sql('SELECT * FROM tenants'));
  assert.ok(!stored.includes(tenant.key));
  const listed = await relay.call('GET', '/admin/keys', { key: ADMIN });
  assert.ok(!listed.text.includes(tenant.key));
  assert.ok(!listed.text.includes('token-abc'), 'the webhook is never sent back');
});

test('guessed, malformed and revoked keys are refused', async () => {
  const relay = createRelay();
  const tenant = await relay.tenant();
  assert.equal((await relay.call('POST', '/v1/checks', { body: {} })).status, 401);
  assert.equal((await relay.call('POST', '/v1/checks', { key: 'bsmm_' + 'A'.repeat(43), body: {} })).status, 401);
  assert.equal((await relay.call('POST', '/v1/checks', { key: tenant.key + 'x', body: {} })).status, 401);
  assert.equal((await relay.call('POST', '/v1/checks', { key: tenant.key, body: {} })).status, 201);

  assert.equal((await relay.call('DELETE', `/admin/keys/${tenant.id}`, { key: ADMIN })).status, 200);
  assert.equal((await relay.call('POST', '/v1/checks', { key: tenant.key, body: {} })).status, 401);
});

test('a webhook must be a Discord webhook', async () => {
  const relay = createRelay();
  for (const webhook_url of ['http://169.254.169.254/latest', 'https://evil.example/api/webhooks/1/x', 'https://discord.com.evil.example/api/webhooks/123456789012345678/x']) {
    const made = await relay.call('POST', '/admin/keys', { key: ADMIN, body: { name: 'x', webhook_url } });
    assert.equal(made.status, 400, webhook_url);
  }
});

// ---------------------------------------------------------------- one-time codes

test('creating a check returns a one-time command', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const check = await relay.issue(key, { roblox_id: '1001', player: 'Tester', requested_by: 'Mod' });
  assert.match(check.id, /^BSMM-[2-9A-HJ-NP-Z]{8}$/);
  assert.match(check.code, /^[2-9A-HJ-NP-Z]{20}$/);
  assert.equal(check.command, `irm https://relay.test/c/${check.code} | iex`);
  assert.equal((await relay.call('POST', '/v1/checks', { key, body: { roblox_id: 'abc' } })).status, 400);
  assert.equal((await relay.call('POST', '/v1/checks', { key, body: { mode: 'other' } })).status, 400);
});

test('the script is served once, with a session only the relay knows', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const check = await relay.issue(key);

  const first = await relay.download(check.code);
  assert.equal(first.session.id, check.id);
  assert.match(first.session.key, /^[0-9a-f]{64}$/);
  assert.equal(first.session.relay, 'https://relay.test');
  assert.ok(first.text.includes("$script:SystemChecks"));

  const second = await relay.download(check.code);
  assert.equal(second.session, null);
  assert.ok(!second.text.includes(first.session.key));
  assert.match(second.text, /invalid, expired or already used/);
});

test('a browser or link preview does not use up the code', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const check = await relay.issue(key);
  const preview = await relay.call('GET', `/c/${check.code}`, { headers: { 'user-agent': 'Mozilla/5.0 (compatible; Discordbot/2.0)' } });
  assert.ok(!preview.text.includes('Key ='));
  assert.equal((await relay.download(check.code)).session.id, check.id);
});

test('the fixed start command asks for the code, then loads that check', async () => {
  const relay = createRelay();
  const start = await relay.call('GET', '/run', { headers: { 'user-agent': PS_AGENT } });
  assert.equal(start.status, 200);
  assert.match(start.text, /Read-Host/);
  assert.ok(start.text.includes('irm "https://relay.test/c/$code" | iex'));
  assert.ok(!/Key =|SystemChecks/.test(start.text), 'the start script holds no session and no checks');
  const guard = start.text.indexOf('Is64BitProcess');
  assert.ok(guard >= 0 && guard < start.text.indexOf('Read-Host'), '32-bit PowerShell is turned away before the code is asked for');

  const browser = await relay.call('GET', '/run', { headers: { 'user-agent': 'Mozilla/5.0 Chrome/130.0' } });
  assert.ok(!browser.text.includes('Read-Host'));
  assert.equal((await relay.call('POST', '/run')).status, 404);
});

test('an expired or unknown code serves no script', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const check = await relay.issue(key);
  relay.sqlite.prepare('UPDATE checks SET expires_at = 1 WHERE id = ?').run(check.id);
  assert.equal((await relay.download(check.code)).session, null);
  assert.equal((await relay.download('Z'.repeat(20))).session, null);
});

test('a failed script download leaves the code usable', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const check = await relay.issue(key);
  relay.env.SCRIPT_BASE_URL = 'https://scripts.test/not-cached';
  relay.net.scriptOk = false;
  assert.equal((await relay.download(check.code)).session, null);
  relay.net.scriptOk = true;
  assert.equal((await relay.download(check.code)).session.id, check.id);
});

// ---------------------------------------------------------------- signed reports

test('a signed report is accepted once and posted to the tenant webhook', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { check, session } = await relay.started(key, { roblox_id: '1001', player: 'Tester' });

  const sent = await relay.send(session, report());
  assert.equal(sent.status, 200);
  assert.deepEqual(sent.json, { ok: true, id: check.id }, 'the verdict is not sent back to the player');
  assert.equal(relay.discord.length, 1);
  assert.equal(relay.discord[0].file.name, `${check.id}-system-check.txt`);
  assert.deepEqual(relay.discord[0].payload.allowed_mentions, { parse: [] });

  assert.equal((await relay.send(session, report())).status, 401, 'replay');
  assert.equal(relay.discord.length, 1);
});

test('unsigned, forged and tampered reports are refused', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { session } = await relay.started(key);
  const other = await relay.started(key);

  assert.equal((await relay.send(session, report(), { sig: '' })).status, 401);
  assert.equal((await relay.send(session, report(), { sig: '0'.repeat(64) })).status, 401);
  assert.equal((await relay.send(session, report(), { key: other.session.key })).status, 401, "another check's key");
  assert.equal((await relay.send(session, report(), { seq: 1 })).status, 401, 'a PC check takes no sequence number');
  assert.equal((await relay.send({ ...session, id: 'BSMM-ZZZZZZZZ' }, report())).status, 401, 'unknown check');
  assert.equal(relay.discord.length, 0);
  assert.equal((await relay.send(session, report())).status, 200, 'refusals do not burn the check');
});

test('a report needs a downloaded script and has to arrive in time', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const early = await relay.issue(key);
  const row = relay.sql('SELECT key FROM checks WHERE id = ?', early.id)[0];
  assert.equal((await relay.send({ id: early.id, key: row.key }, report())).status, 401, 'never downloaded');

  const late = await relay.started(key, {}, 3 * 3600);
  assert.equal((await relay.send(late.session, report())).status, 401, 'too late');
});

test('oversized and malformed bodies are refused', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { session } = await relay.started(key);
  assert.equal((await relay.send(session, { junk: 'x'.repeat(2_000_000) })).status, 413);
  assert.equal((await relay.send(session, { v: '1.3.0' })).status, 400);
});

// ---------------------------------------------------------------- server-side verdict

test('a clean report from the verified account is trusted', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { detail } = await reported(relay, key, { roblox_id: '1001', player: 'Tester' });
  assert.equal(detail.status, 'reported');
  assert.deepEqual(detail.verdict, { score: 100, label: 'TRUSTED' });
  assert.deepEqual(detail.flags, []);
  assert.equal(detail.roblox.current.name, 'user1001');
  assert.equal(detail.roblox.games[0].name, 'Game 77');
});

test('the relay derives each check status from its lines, not from the client', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { detail } = await reported(relay, key, {}, {
    checks: [
      { name: 'Alpha', status: 'PASS', lines: ['FAILURE: cheat loader found -> C:\\x.exe'] },
      { name: 'Beta', status: 'PASS', lines: ['WARNING: odd setting'] },
      { name: 'Gamma', lines: ['SUCCESS: nothing found'] },
    ],
  });
  assert.deepEqual(detail.checks.map((check) => check.status), ['FAIL', 'WARN', 'PASS']);
  assert.deepEqual(detail.checks[0].lines[0], { level: 'FAIL', text: 'cheat loader found -> C:\\x.exe' });
  assert.equal(detail.failed, 1);
  assert.equal(detail.review, 1);
  assert.equal(detail.verdict.score, 78);
});

test('a scan that finished too fast is flagged', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { detail } = await reported(relay, key, {}, {}, 4);
  assert.deepEqual(flagCodes(detail), ['fast_scan']);
  assert.equal(detail.verdict.label, 'HIGH RISK', 'a report that cannot be the real scan is never better than high risk');
  assert.equal(detail.verdict.score, 25);
});

test('missing checks and a wrong script version are flagged', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { detail } = await reported(relay, key, {}, { v: '1.2.0', checks: [{ name: 'Alpha', lines: ['SUCCESS: ok'] }] });
  assert.deepEqual(flagCodes(detail), ['missing_checks', 'version_mismatch']);
  assert.match(detail.flags.find((flag) => flag.code === 'missing_checks').text, /Beta, Gamma/);
  assert.equal(detail.verdict.label, 'HIGH RISK');
});

test('a report from another IP address is flagged', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { check, session } = await relay.started(key);
  relay.setIp('198.51.100.9');
  await relay.send(session, report());
  const detail = (await relay.call('GET', `/v1/checks/${check.id}`, { key })).json;
  assert.deepEqual(flagCodes(detail), ['ip_changed']);
  assert.ok(!JSON.stringify(detail).includes('203.0.113.7'), 'IP addresses are not exposed');
});

test('the logged-in account is checked against the verified one', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();

  const stranger = await reported(relay, key, { roblox_id: '2002' }, { pc: 'b'.repeat(64) });
  assert.deepEqual(flagCodes(stranger.detail), ['account_mismatch']);
  assert.equal(stranger.detail.flags[0].level, 'FAIL');

  const alt = await reported(relay, key, { roblox_id: '3003' }, {
    pc: 'c'.repeat(64),
    roblox: { userId: '1001', accounts: [{ id: '1001', sources: ['switcher'] }, { id: '3003', sources: ['logs'] }], games: [] },
  });
  assert.deepEqual(flagCodes(alt.detail), ['account_not_active']);
  assert.equal(alt.detail.flags[0].level, 'WARN');

  const none = await reported(relay, key, { roblox_id: '4004' }, { pc: 'd'.repeat(64), roblox: { userId: null, accounts: [], games: [] } });
  assert.deepEqual(flagCodes(none.detail), ['no_account']);
});

test('history flags a shared PC, a new PC and accounts that vanished', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const two = { userId: '1001', accounts: [{ id: '1001', sources: ['switcher'] }, { id: '5005', sources: ['switcher'] }], games: [] };
  await reported(relay, key, { roblox_id: '1001', player: 'First' }, { roblox: two });

  const again = await reported(relay, key, { roblox_id: '1001', player: 'First' });
  assert.deepEqual(flagCodes(again.detail), ['accounts_removed']);
  assert.match(again.detail.flags[0].text, /user5005 \(5005\)/, 'accounts are named, not just numbered');

  const shared = await reported(relay, key, { roblox_id: '6006', player: 'Second' }, { roblox: { userId: '6006', accounts: [{ id: '6006', sources: ['logs'] }], games: [] } });
  assert.ok(flagCodes(shared.detail).includes('pc_shared'));
  assert.equal(shared.detail.pc.seen.length, 2);

  const moved = await reported(relay, key, { roblox_id: '1001', player: 'First' }, { pc: 'e'.repeat(64) });
  assert.ok(flagCodes(moved.detail).includes('pc_changed'));
});

test('Roblox being unreachable does not lose the report', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  relay.net.robloxOk = false;
  const { detail } = await reported(relay, key, { roblox_id: '1001' });
  assert.equal(detail.verdict.label, 'TRUSTED');
  assert.equal(detail.roblox.current.id, '1001');
  assert.equal(detail.roblox.current.name, null);
});

test('a Discord outage does not lose the report', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  relay.net.discordOk = false;
  const { detail } = await reported(relay, key);
  assert.equal(detail.status, 'reported');
});

// ---------------------------------------------------------------- Discord layout

test('the Discord message leads with the verdict and groups findings by check', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant('BSMM', { view_url: 'https://site.test/staff/pc-checks' });
  const { check } = await reported(relay, key, { roblox_id: '1001', player: 'Tester', requested_by: 'Mod' }, {
    checks: [
      { name: 'Alpha', lines: ['FAILURE: Forged root `cert` (user store)', 'FAILURE: Forged root `cert` (user store)', 'FAILURE: two', 'FAILURE: three', 'FAILURE: four', 'FAILURE: five'] },
      { name: 'Beta', lines: ['WARNING: odd setting'] },
      { name: 'Gamma', lines: ['SUCCESS: fine'] },
    ],
  });
  const { payload, file } = relay.discord[0];
  const [summary, failed] = payload.embeds;
  assert.match(summary.title, /^REVIEW 78\/100 . Tester$/);
  assert.match(summary.description, /user1001/);
  assert.match(summary.description, /Mod/);
  assert.ok(summary.description.includes(`https://site.test/staff/pc-checks/${check.id}`));
  assert.equal(summary.fields.find((field) => field.name.startsWith('Review')).value, 'Beta');
  assert.match(failed.title, /^Failed \(1\)$/);
  assert.equal(failed.description.match(/Forged root/g).length, 1, 'duplicate findings are shown once');
  assert.match(failed.description, /\+2 more/);
  assert.ok(!failed.description.replace(/^```text\n|```$/g, '').includes('`'), 'backticks cannot break the code block');
  assert.ok(JSON.stringify(payload.embeds).length < 5900);
  assert.match(file.text, /\[FAIL\] Alpha/);
  assert.match(file.text, /five/);
});

// ---------------------------------------------------------------- program activity

const unix = () => Math.floor(Date.now() / 1000);
const ran = (path, secondsAgo, extra = {}) => ({ path, at: unix() - secondsAgo, src: 'prefetch', sig: 'unsigned', ...extra });
const near = (actual, expected, message) => assert.ok(Math.abs(actual - expected) <= 3000, `${message}: ${actual} vs ${expected}`);

test('every program run is kept with its exact time, newest first', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const old = ran('C:\\Tools\\Old Tool.exe', 3600, { runs: 12 });
  const fresh = ran('C:\\Games\\steam.exe', 35, { src: 'running', sig: 'signed', signer: 'Valve Corp.' });
  const { detail } = await reported(relay, key, { roblox_id: '1001' }, {
    clock: unix(),
    programs: [old, fresh, old, { path: '', at: unix() }, ran('C:\\x.exe', 10, { src: 'made-up' }), { path: 'C:\\y.exe', at: 'soon', src: 'bam' }, 'junk'],
  });
  const { runs } = detail.programs;
  assert.deepEqual(runs.map((run) => run.name), ['steam.exe', 'Old Tool.exe'], 'bad entries and duplicates are dropped');
  assert.deepEqual(runs[0], { path: 'C:\\Games\\steam.exe', name: 'steam.exe', at: fresh.at * 1000, src: 'running', sig: 'signed', signer: 'Valve Corp.', runs: 0 });
  assert.deepEqual(runs[1], { path: 'C:\\Tools\\Old Tool.exe', name: 'Old Tool.exe', at: old.at * 1000, src: 'prefetch', sig: 'unsigned', signer: '', runs: 12 });
  assert.deepEqual(flagCodes(detail), [], 'programs alone are not a finding');
});

test('a report without program data still reads back the same way', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { detail } = await reported(relay, key, { roblox_id: '1001' });
  assert.deepEqual(detail.programs, { skew_seconds: 0, runs: [], matches: [] });
});

test('programs are lined up against the matches the bot says the player was in', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const first = { id: '4812', started_at: unix() - 7200, ended_at: unix() - 5400 };
  const second = { id: '4813', started_at: unix() - 3000 };
  const loader = 'C:\\Users\\kid\\Downloads\\loader.exe';
  const { detail, check } = await reported(relay, key, { roblox_id: '1001', matches: [first, second] }, {
    clock: unix(),
    programs: [
      ran(loader, 7200 + 130),
      ran(loader, 3000 + 60),
      ran('C:\\Program Files\\Discord\\Discord.exe', 7200 + 100, { sig: 'signed', signer: 'Discord Inc.' }),
      ran('C:\\Tools\\unrelated.exe', 86_400),
      ran('C:\\Tools\\rgb.exe', 36_000, { src: 'running' }),
      ran('C:\\Tools\\late.exe', 5400 - 30),
      ran('C:\\Tools\\crashed.exe', 3000 - 120, { src: 'exit' }),
    ],
  });

  assert.deepEqual(detail.programs.matches.map((match) => match.id), ['4813', '4812'], 'newest match first');
  const [later, earlier] = detail.programs.matches;
  assert.equal(earlier.started_at, first.started_at * 1000);
  assert.equal(earlier.ended_at, first.ended_at * 1000);
  assert.equal(later.ended_at, null, 'a match that is still running has no end');
  assert.deepEqual(earlier.runs.map((run) => run.name), ['rgb.exe', 'loader.exe', 'Discord.exe'], 'in time order; a program started after the match ended is not part of it');
  assert.equal(earlier.runs[1].offset, -130, 'seconds before the match started');
  assert.deepEqual(later.runs.map((run) => run.name), ['rgb.exe', 'loader.exe', 'crashed.exe']);
  assert.ok(later.runs.find((run) => run.name === 'crashed.exe').offset > 0, 'closed during the match');

  assert.deepEqual(flagCodes(detail), ['match_programs']);
  const flag = detail.flags[0];
  assert.equal(flag.level, 'WARN');
  assert.match(flag.text, /loader\.exe \(2 of 2 matches\)/);
  assert.match(flag.text, /rgb\.exe \(2 of 2 matches\)/);
  assert.ok(!flag.text.includes('Discord'), 'signed programs are listed but never flagged');
  assert.ok(!flag.text.includes('unrelated'));

  const served = relay.sql('SELECT matches FROM checks WHERE id = ?', check.id)[0].matches;
  assert.ok(served.includes('4812'));
});

test('the player is never told which matches are being compared', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const check = await relay.issue(key, { matches: [{ id: 'secret-match-77', started_at: unix() - 600 }] });
  assert.ok(!JSON.stringify(check).includes('secret-match-77'));
  assert.ok(!(await relay.download(check.code)).text.includes('secret-match-77'));
});

test('badly formed matches are refused when the check is created', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  for (const matches of ['4812', [{ id: '4812' }], [{ id: '4812', started_at: 'yesterday' }], [{ started_at: unix() }], Array(26).fill({ id: '1', started_at: unix() })]) {
    assert.equal((await relay.call('POST', '/v1/checks', { key, body: { matches } })).status, 400, JSON.stringify(matches).slice(0, 60));
  }
});

test('a deleted program that ran around two matches fails the check', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const matches = [{ id: '1', started_at: unix() - 7200, ended_at: unix() - 5400 }, { id: '2', started_at: unix() - 3000, ended_at: unix() - 1500 }];
  const gone = { sig: 'missing' };
  const { detail } = await reported(relay, key, { roblox_id: '1001', matches }, {
    clock: unix(),
    programs: [ran('C:\\Temp\\mx.exe', 7200 + 90, gone), ran('C:\\Temp\\mx.exe', 3000 + 45, gone), ran('C:\\Temp\\once.exe', 3000 + 20, gone)],
  });
  assert.deepEqual(flagCodes(detail), ['match_program_deleted', 'match_programs']);
  const flag = detail.flags.find((item) => item.code === 'match_program_deleted');
  assert.equal(flag.level, 'FAIL');
  assert.match(flag.text, /mx\.exe/);
  assert.ok(!flag.text.includes('once.exe'), 'one match is not a pattern');
});

test('a PC clock that is off is corrected and flagged', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const behind = 3600;
  const { detail } = await reported(relay, key, { roblox_id: '1001' }, {
    clock: unix() - behind,
    programs: [ran('C:\\Tools\\a.exe', behind + 60)],
  });
  assert.deepEqual(flagCodes(detail), ['clock_skew']);
  near(detail.programs.skew_seconds * 1000, behind * 1000, 'skew');
  near(detail.programs.runs[0].at, Date.now() - 60_000, 'the run is placed at its real time');

  const fine = await reported(relay, key, { roblox_id: '2002' }, { pc: 'e'.repeat(64), roblox: { userId: '2002', accounts: [{ id: '2002', sources: ['logs'] }], games: [] }, clock: unix() - 20, programs: [ran('C:\\Tools\\a.exe', 80)] });
  assert.deepEqual(flagCodes(fine.detail), [], 'a few seconds of drift is normal');
  assert.equal(fine.detail.programs.skew_seconds, 0);
});

test('launch history that disappears between two checks of the same PC is flagged', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const launch = { src: 'launch' };
  const kept = ran('C:\\Tools\\kept.exe', 4000, launch);
  await reported(relay, key, { roblox_id: '1001' }, {
    clock: unix(),
    programs: [ran('C:\\Tools\\wiped.exe', 5000, launch), kept, ran('C:\\Tools\\older.exe', 90_000, { src: 'userassist' }), ran('C:\\Tools\\rolled.exe', 9000, { src: 'bam' })],
  });

  const again = await reported(relay, key, { roblox_id: '1001' }, { clock: unix(), programs: [kept, ran('C:\\Tools\\new.exe', 100, launch)] });
  assert.deepEqual(flagCodes(again.detail), ['history_removed']);
  const flag = again.detail.flags[0];
  assert.equal(flag.level, 'WARN');
  assert.match(flag.text, /^2 programs/);
  assert.match(flag.text, /wiped\.exe/);
  assert.match(flag.text, /older\.exe/);
  assert.ok(!flag.text.includes('rolled.exe'), 'history that Windows itself rolls over is not counted');

  const same = await reported(relay, key, { roblox_id: '1001' }, { clock: unix(), programs: [kept, ran('C:\\Tools\\new.exe', 100, launch)] });
  assert.deepEqual(flagCodes(same.detail), [], 'only the change since the last check is flagged');
});

test('Discord shows when programs ran, as times that count up on their own', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const match = { id: '4812', started_at: unix() - 3000, ended_at: unix() - 1500 };
  const loader = ran('C:\\Users\\kid\\Downloads\\loader.exe', 3000 + 130);
  const recent = ran('C:\\Users\\kid\\Desktop\\closed.exe', 35, { sig: 'missing', src: 'exit' });
  await reported(relay, key, { roblox_id: '1001', player: 'Tester', matches: [match] }, {
    clock: unix(),
    programs: [loader, recent, ran('C:\\Program Files\\Discord\\Discord.exe', 20, { sig: 'signed', signer: 'Discord Inc.' })],
  });
  const { payload, file } = relay.discord[0];
  const fields = payload.embeds[0].fields;
  const around = fields.find((field) => field.name.startsWith('Programs around matches'));
  assert.ok(around.value.includes('loader.exe'));
  assert.ok(around.value.includes(`<t:${loader.at}:R>`), 'Discord renders this as "52 minutes ago"');
  assert.match(around.value, /2m 10s before match 4812/);
  const latest = fields.find((field) => field.name.startsWith('Last programs'));
  assert.ok(latest.value.includes(`closed.exe`));
  assert.ok(latest.value.includes(`<t:${recent.at}:R>`));
  assert.ok(!latest.value.includes('Discord.exe'), 'signed programs stay out of the summary');
  assert.ok(JSON.stringify(payload.embeds).length < 5900);

  assert.match(file.text, /Program activity/);
  assert.ok(file.text.includes(`unix ${recent.at}`), 'the log keeps the exact time');
  assert.match(file.text, /3[0-9]s before the report/);
  assert.ok(file.text.includes('C:\\Program Files\\Discord\\Discord.exe'), 'the log lists everything');
});

// ---------------------------------------------------------------- programs shared between PCs

const hashOf = (letter) => letter.repeat(64);
const pcOf = (n) => String(n).padStart(64, '0');
const flaggedChecks = [
  { name: 'Alpha', lines: ['FAILURE: one'] },
  { name: 'Beta', lines: ['FAILURE: two'] },
  { name: 'Gamma', lines: ['FAILURE: three'] },
];
// A check of its own PC and player that ran the given programs; `flagged` gives it findings of its own.
const pcReport = (relay, key, n, programs, flagged = false, extra = {}) => reported(relay, key, { roblox_id: String(3000 + n) }, {
  pc: pcOf(n),
  roblox: { userId: String(3000 + n), accounts: [{ id: String(3000 + n), sources: ['logs'] }], games: [] },
  clock: unix(),
  programs,
  ...(flagged ? { checks: flaggedChecks } : {}),
  ...extra,
});
// The league's ordinary players: clean PCs running something everyone has.
const cleanPcs = async (relay, key, from, count) => {
  for (let n = from; n < from + count; n++) await pcReport(relay, key, n, [ran('C:\\Tools\\rgb.exe', 900, { hash: hashOf('9') })]);
};

test('an unsigned program that mostly turns up on flagged PCs is flagged without knowing its name', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const tool = (name) => ran(`C:\\Users\\kid\\Downloads\\${name}`, 500, { hash: hashOf('c') });
  await cleanPcs(relay, key, 50, 5);

  const first = await pcReport(relay, key, 1, [tool('helper.exe')], true);
  assert.equal(first.detail.verdict.label, 'SUSPICIOUS');
  assert.deepEqual(flagCodes(first.detail), [], 'the first PC to show a program has nothing to compare with');
  const second = await pcReport(relay, key, 2, [tool('helper.exe')], true);
  assert.deepEqual(flagCodes(second.detail), [], 'one flagged PC is not a pattern');

  const third = await pcReport(relay, key, 3, [tool('renamed.exe')]);
  assert.deepEqual(flagCodes(third.detail), ['shared_program']);
  const warn = third.detail.flags[0];
  assert.equal(warn.level, 'WARN');
  assert.match(warn.text, /renamed\.exe \(2 other PCs, 2 flagged\)/, 'matched by fingerprint, shown under the name on this PC');
  assert.equal(third.detail.verdict.label, 'TRUSTED', 'a warning alone does not flag the PC that got it');

  await pcReport(relay, key, 4, [tool('helper.exe')], true);
  const fifth = await pcReport(relay, key, 5, [tool('again.exe')]);
  const fail = fifth.detail.flags.find((flag) => flag.code === 'shared_program');
  assert.equal(fail.level, 'FAIL');
  assert.match(fail.text, /again\.exe \(4 other PCs, 3 flagged\)/);
  assert.equal(fifth.detail.programs.runs[0].hash, hashOf('c'), 'the fingerprint is kept with the run');
});

test('a program that trusted PCs also run is not held against anyone', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const common = ran('C:\\Tools\\rgb.exe', 500, { hash: hashOf('d') });
  await pcReport(relay, key, 1, [common], true);
  await pcReport(relay, key, 2, [common], true);
  for (const n of [3, 4, 5]) await pcReport(relay, key, n, [common]);
  const { detail } = await pcReport(relay, key, 6, [common]);
  assert.deepEqual(flagCodes(detail), [], '2 flagged PCs out of 5 is not a pattern');
});

test('in a league where most checked PCs are flagged, sharing a program with them means nothing', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const launcher = ran('C:\\Tools\\launcher.exe', 500, { hash: hashOf('a') });
  for (const n of [1, 2, 3, 4]) await pcReport(relay, key, n, [launcher], true);
  const { detail } = await pcReport(relay, key, 5, [launcher]);
  assert.deepEqual(flagCodes(detail), [], 'the program is no more common on flagged PCs than any PC is flagged');
});

test('a flag for a shared program never makes its own evidence', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const tool = ran('C:\\Temp\\t.exe', 500, { hash: hashOf('b') });
  await cleanPcs(relay, key, 50, 8);
  for (const n of [1, 2, 3]) await pcReport(relay, key, n, [tool], true);
  // These PCs have nothing against them except the program itself.
  for (const n of [4, 5, 6]) {
    const { detail } = await pcReport(relay, key, n, [tool]);
    assert.equal(detail.flags.find((flag) => flag.code === 'shared_program').text.match(/(\d+) flagged/)[1], '3', 'only PCs with findings of their own count as flagged');
  }
});

test('the same PC checked twice, other leagues and malformed fingerprints do not count', async () => {
  const relay = createRelay();
  const a = await relay.tenant('League A');
  const b = await relay.tenant('League B');
  const tool = ran('C:\\Temp\\x.exe', 500, { hash: hashOf('e') });

  await pcReport(relay, a.key, 1, [tool], true);
  const again = await pcReport(relay, a.key, 1, [tool], true);
  assert.ok(!flagCodes(again.detail).includes('shared_program'), 'a PC is not compared with its own earlier checks');

  const other = await pcReport(relay, b.key, 2, [tool]);
  assert.deepEqual(flagCodes(other.detail), [], 'leagues never see each other');

  const bad = await pcReport(relay, a.key, 3, [ran('C:\\Temp\\y.exe', 500, { hash: 'not-a-hash' }), ran('C:\\Temp\\z.exe', 400)]);
  assert.ok(bad.detail.programs.runs.every((run) => !('hash' in run)), 'a fingerprint is kept only when it is a SHA-256');
  assert.deepEqual(flagCodes(bad.detail), []);
});

test('fingerprints are forgotten when they are older than the reports they came from', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const tool = ran('C:\\Temp\\x.exe', 500, { hash: hashOf('f') });
  await pcReport(relay, key, 1, [tool], true);
  relay.sqlite.prepare('UPDATE program_sightings SET seen_at = seen_at - ?').run(91 * 86_400_000);
  const { detail } = await pcReport(relay, key, 2, [tool]);
  assert.deepEqual(flagCodes(detail), []);
  assert.equal(relay.sql('SELECT COUNT(*) AS n FROM program_sightings')[0].n, 1, 'only the new sighting is left');
});

// A file found loaded inside another program is reported apart from the programs that ran.
const loadedInto = (name, host, letter = 'c') => ({ path: `C:\\Users\\kid\\AppData\\Local\\Temp\\${name}`, host, hash: hashOf(letter) });

test('a file loaded inside another program is compared between PCs whatever it is called', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  await cleanPcs(relay, key, 50, 5);

  await pcReport(relay, key, 1, [], true, { loaded: [loadedInto('d3d9.dll', 'Discord.exe')] });
  await pcReport(relay, key, 2, [], true, { loaded: [loadedInto('version.dll', 'steam.exe')] });
  const third = await pcReport(relay, key, 3, [], false, { loaded: [loadedInto('discord_hook.dll', 'Discord.exe')] });
  assert.deepEqual(flagCodes(third.detail), ['shared_program']);
  assert.equal(third.detail.flags[0].level, 'WARN');
  assert.match(third.detail.flags[0].text, /discord_hook\.dll in Discord\.exe \(2 other PCs, 2 flagged\)/);

  await pcReport(relay, key, 4, [ran('C:\\Users\\kid\\Desktop\\tool.exe', 500, { hash: hashOf('c') })], true);
  const fifth = await pcReport(relay, key, 5, [], false, { loaded: [loadedInto('x.dll', 'explorer.exe')] });
  assert.equal(fifth.detail.flags.find((flag) => flag.code === 'shared_program').level, 'FAIL', 'the same file seen as a program on another PC counts too');
});

test('badly formed loaded files are ignored', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  for (const loaded of ['nope', [null, 7, {}], [{ path: 'C:\\a.dll', host: 'a.exe', hash: 'short' }], [{ hash: hashOf('c') }]]) {
    const { detail } = await pcReport(relay, key, 1, [], false, { loaded });
    assert.deepEqual(flagCodes(detail), []);
  }
  assert.equal(relay.sql('SELECT COUNT(*) AS n FROM program_sightings')[0].n, 0, 'a fingerprint with no file name is not kept');
});

test('a file the live monitor sees loaded during a match is remembered for later checks', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  await cleanPcs(relay, key, 50, 5);

  for (const n of [1, 2]) {
    const { check, session } = await relay.started(key, { mode: 'monitor', roblox_id: String(3000 + n) });
    const live = (extra) => ({ v: '1.3.0', state: 'RUNNING', elapsed: 60, admin: true, counts: { fail: 0, warn: 0, info: 1 }, recent: [], roblox: report().roblox, pc: pcOf(n), ...extra });
    assert.equal((await relay.send(session, live(), { path: '/v1/live', seq: 1 })).status, 200);
    const seen = { counts: { fail: 2, warn: 0, info: 1 }, loaded: [loadedInto('helper.dll', 'Discord.exe'), { hash: 'nope' }] };
    assert.equal((await relay.send(session, live(seen), { path: '/v1/live', seq: 2 })).status, 200);
    assert.equal((await relay.send(session, live(seen), { path: '/v1/live', seq: 3 })).status, 200);
    assert.equal(relay.sql('SELECT COUNT(*) AS n FROM program_sightings WHERE check_id = ?', check.id)[0].n, 1, 'kept once however often it is sent');
  }

  const { detail } = await pcReport(relay, key, 3, [], false, { loaded: [loadedInto('other.dll', 'chrome.exe')] });
  assert.match(detail.flags.find((flag) => flag.code === 'shared_program').text, /other\.dll in chrome\.exe \(2 other PCs, 2 flagged\)/);
});

// ---------------------------------------------------------------- reading reports

test('a key only sees its own checks', async () => {
  const relay = createRelay();
  const a = await relay.tenant('League A');
  const b = await relay.tenant('League B');
  const { check } = await reported(relay, a.key, { roblox_id: '1001', player: 'Tester' });

  assert.equal((await relay.call('GET', `/v1/checks/${check.id}`, { key: b.key })).status, 404);
  assert.deepEqual((await relay.call('GET', '/v1/checks', { key: b.key })).json.checks, []);
  assert.equal((await relay.call('GET', `/v1/checks/${check.id}`)).status, 401);

  const other = await reported(relay, b.key, { roblox_id: '9009', player: 'Elsewhere' }, { roblox: { userId: '9009', accounts: [], games: [] } });
  assert.ok(!flagCodes(other.detail).includes('pc_shared'), 'history never crosses tenants');
});

test('the list can be searched, filtered and paged', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  await reported(relay, key, { roblox_id: '1001', player: 'Alice' });
  await reported(relay, key, { roblox_id: '2002', player: 'Bob_100%' }, {
    pc: 'b'.repeat(64),
    roblox: { userId: '2002', accounts: [{ id: '2002', sources: ['switcher'] }], games: [] },
    checks: [{ name: 'Alpha', lines: ['FAILURE: cheat loader found'] }, { name: 'Beta', lines: ['SUCCESS: ok'] }, { name: 'Gamma', lines: ['SUCCESS: ok'] }],
  });
  await relay.issue(key, { player: 'Carol' });

  const all = (await relay.call('GET', '/v1/checks', { key })).json;
  assert.equal(all.checks.length, 3);
  assert.equal(all.totals.all, 3);
  assert.equal(all.checks[0].player, 'Carol');
  assert.equal(all.checks[0].status, 'pending');
  assert.ok(!('key' in all.checks[0]) && !('code' in all.checks[0]) && !('report' in all.checks[0]));

  const names = async (query) => (await relay.call('GET', `/v1/checks?${query}`, { key })).json.checks.map((check) => check.player);
  assert.deepEqual(await names('q=alice'), ['Alice']);
  assert.deepEqual(await names('q=user1001'), ['Alice'], 'resolved account names are searchable');
  assert.deepEqual(await names('q=' + encodeURIComponent('100%')), ['Bob_100%'], 'wildcards are literal');
  assert.deepEqual(await names('q=%25'), ['Bob_100%']);
  assert.deepEqual(await names('verdict=REVIEW'), ['Bob_100%']);
  assert.deepEqual(await names('verdict=TRUSTED'), ['Alice']);

  const page = (await relay.call('GET', '/v1/checks?limit=2', { key })).json;
  assert.equal(page.checks.length, 2);
  const rest = (await relay.call('GET', `/v1/checks?limit=2&before=${page.next}`, { key })).json;
  assert.deepEqual(rest.checks.map((check) => check.player), ['Alice']);
  assert.equal(rest.next, null);
});

test('a downloaded script with no report shows as abandoned', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { check } = await relay.started(key, { player: 'Ghost' }, 3 * 3600);
  const detail = (await relay.call('GET', `/v1/checks/${check.id}`, { key })).json;
  assert.equal(detail.status, 'no_report');
  assert.equal((await relay.call('GET', '/v1/checks', { key })).json.totals.noReport, 1);
});

test('old checks are deleted when new ones are created', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const old = await relay.issue(key);
  relay.sqlite.prepare('UPDATE checks SET created_at = created_at - ? WHERE id = ?').run(91 * 86_400_000, old.id);
  await relay.issue(key);
  assert.equal((await relay.call('GET', `/v1/checks/${old.id}`, { key })).status, 404);
});

// ---------------------------------------------------------------- live monitor

test('the live monitor creates one message, edits it, then closes', async () => {
  const relay = createRelay();
  const { key } = await relay.tenant();
  const { check, session } = await relay.started(key, { mode: 'monitor', roblox_id: '1001', player: 'Tester' });
  const live = (state, extra = {}) => ({ v: '1.3.0', state, elapsed: 60, admin: true, counts: { fail: 0, warn: 0, info: 1 }, recent: [], roblox: report().roblox, pc: 'a'.repeat(64), ...extra });

  assert.equal((await relay.send(session, report())).status, 401, 'a monitor session cannot file a PC check');
  assert.equal((await relay.send(session, live('RUNNING'), { path: '/v1/live', seq: 1 })).status, 200);
  assert.equal(relay.discord.at(-1).method, 'POST');

  const alert = live('RUNNING', { elapsed: 180, counts: { fail: 1, warn: 0, info: 1 }, recent: ['[12:00:01] [FAIL] overlay window from untrusted path'] });
  assert.equal((await relay.send(session, alert, { path: '/v1/live', seq: 2 })).status, 200);
  assert.equal(relay.discord.at(-1).method, 'PATCH');
  assert.ok(relay.discord.at(-1).url.includes('/messages/'));
  assert.equal((await relay.send(session, alert, { path: '/v1/live', seq: 2 })).status, 401, 'replayed update');

  let detail = (await relay.call('GET', `/v1/checks/${check.id}`, { key })).json;
  assert.equal(detail.status, 'live');
  assert.equal(detail.verdict.score, 90);
  assert.equal(detail.live.alerts[0].level, 'FAIL');
  assert.equal(detail.failed, 1, 'the list counts live alerts, a monitor has no checks of its own');

  const ended = live('ENDED', { elapsed: 600, counts: { fail: 1, warn: 0, info: 1 }, log: ['[12:00:01] [FAIL] overlay window from untrusted path', '[12:05:00] [INFO] stopped'] });
  assert.equal((await relay.send(session, ended, { path: '/v1/live', seq: 3 })).status, 200);
  assert.equal(relay.discord.at(-1).file.name, `${check.id}-live-monitor.txt`);
  detail = (await relay.call('GET', `/v1/checks/${check.id}`, { key })).json;
  assert.equal(detail.status, 'ended');
  assert.equal(detail.live.log.length, 2);
  assert.equal((await relay.send(session, live('RUNNING'), { path: '/v1/live', seq: 4 })).status, 401, 'closed');
});

test('the health check and unknown routes reveal nothing', async () => {
  const relay = createRelay();
  assert.equal((await relay.call('GET', '/')).text, 'BSMM relay OK');
  assert.equal((await relay.call('POST', '/report', { body: { embeds: [{ title: 'BSMM' }] } })).status, 404, 'the old open endpoint is gone');
  assert.equal((await relay.call('GET', '/v1/nope')).status, 404);
});
