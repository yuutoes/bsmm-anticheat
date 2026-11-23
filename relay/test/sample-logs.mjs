// Writes invented PC check logs for local development of the staff website.
// Every log is produced by running the real relay code, so the shape always matches production.
//
//   node --no-warnings test/sample-logs.mjs <output.json>
//
// All players, accounts, paths and findings here are made up.
import { readFileSync, writeFileSync } from 'node:fs';
import { createRelay } from './harness.mjs';

const output = process.argv[2];
if (!output) throw new Error('usage: node test/sample-logs.mjs <output.json>');

const source = readFileSync(new URL('../../BSMM-Check.ps1', import.meta.url), 'utf8');
const NAMES = [...source.matchAll(/@\{\s*Name\s*=\s*'([^']{1,64})';\s*Caption\s*=/g)].map((match) => match[1]);
const VERSION = source.match(/\bVersion\s*=\s*'([\d.]+)'/)[1];

// The website's sample players (lib/sample-stats.ts) use these ids, so reports link to their profiles.
const playerId = (index) => String(9_000_000_000_000_000 + index + 1);
const PLAYERS = ['Vortex', 'Kairo', 'Nyx', 'Blitz', 'Rook', 'Echo', 'Halo', 'Frost', 'Drift', 'Onyx', 'Quill', 'Raze', 'Tide', 'Volt', 'Moth', 'Jinx', 'Crow', 'Fable', 'Grit', 'Pike', 'Lumen', 'Sable', 'Wisp'];
const id = (name) => playerId(PLAYERS.indexOf(name));
const ALTS = { '9000000000000100': 'vtx_smurf', '9000000000000101': 'xVortexAlt', '9000000000000102': 'echo2nd', '9000000000000103': 'quill_practice', '9000000000000104': 'h4lo_backup', '9000000000000105': 'totallynothalo' };
const users = { ...Object.fromEntries(PLAYERS.map((name) => [id(name), name])), ...ALTS };
const games = { 7001: 'BloxStrike', 7002: 'BloxStrike Aim Trainer', 7003: 'Arsenal', 7004: 'Rivals' };

const HOUR = 3_600_000;
const NOW = Date.now();
let clock = NOW;
Date.now = () => clock;

const relay = createRelay({ script: source, users, games });
const { key } = await relay.tenant('BSMM');
const pc = (seed) => seed.repeat(64).slice(0, 64);

// What an untouched PC reports. Anything a scenario does not override comes from here.
const QUIET = {
  'PowerShell Modules': ['SUCCESS: Defender and CIM modules loaded'],
  'CPU & GPU': ['INFO: CPU -> AMD Ryzen 7 5800X 8-Core Processor', 'INFO: GPU -> NVIDIA GeForce RTX 3070'],
  'Roblox Client Version': ['INFO: Client Status (ACTIVE - PID 14212)', 'SUCCESS: Build Hash -> version-3f2a1c9be4d14a07', 'SUCCESS: File Version -> 0.701.0.7010642 (x64)', 'INFO: Executable -> %USERPROFILE%\\AppData\\Local\\Roblox\\Versions\\version-3f2a1c9be4d14a07\\RobloxPlayerBeta.exe'],
  'Session': ['SUCCESS: Session looks normal', 'INFO: Logged on 3h 12m ago', 'INFO: Last restart 3h 14m ago'],
  'Session Environment': ['SUCCESS: Not a virtual machine or remote session'],
  'UAC & Prompts': ['SUCCESS: UAC prompts are on'],
  'Window Animations': ['SUCCESS: Window animations are on'],
  'Displays & Desktops': ['SUCCESS: One display, one desktop'],
  'Recording Software (OBS)': ['SUCCESS: No OBS scripts or scene-switch hotkeys'],
  'Windows Defender': ['SUCCESS: Real-time protection is on', 'SUCCESS: Tamper protection is on', 'INFO: Definitions updated today'],
  'Defender Exclusions': ['SUCCESS: No Defender exclusions'],
  'Kernel Drivers': ['SUCCESS: 214 kernel drivers verified'],
  'Vulnerable Drivers': ['SUCCESS: No known vulnerable drivers loaded'],
  'Script Integrity': ['SUCCESS: No signs that this check was hooked, redirected or modified'],
  'Root Certificates': ['SUCCESS: No user-installed root certificates'],
  'Process Scan': ['SUCCESS: 187 processes scanned, none suspicious'],
  'Roblox Modules': ['SUCCESS: 96 modules loaded in Roblox, all signed'],
  'Roblox Tamper & Logs': ['SUCCESS: Roblox install, certificate pinning and logs show no tampering', 'INFO: Read 12 Roblox log file(s)'],
  'FastFlags (ClientAppSettings)': ['SUCCESS: No FastFlag overrides'],
  'Code Fingerprints': ['SUCCESS: No cheat code found inside programs', 'INFO: Looked inside 143 programs'],
  'Execution History (BAM/DAM)': ['SUCCESS: No cheat names in the run history', 'INFO: 61 programs ran in the last 7 days'],
  'Prefetch Health': ['SUCCESS: Prefetch is enabled and intact (212 files)'],
  'USN Journal': ['SUCCESS: Change journal is active and goes back 11 days'],
  'Long-term History': ['SUCCESS: Nothing suspicious in Amcache, SRUM or the Defender log', 'INFO: 30 days of history read'],
  'Command History': ['SUCCESS: No cleanup or bypass commands in the history'],
};
const checks = (overrides = {}) => {
  for (const name of Object.keys(overrides)) if (!NAMES.includes(name)) throw new Error(`unknown check: ${name}`);
  return NAMES.map((name) => ({ name, lines: overrides[name] ?? QUIET[name] ?? ['SUCCESS: Nothing suspicious found'] }));
};
const seconds = (ms) => Math.floor(ms / 1000);
const account = (userId, sources, agoHours = 1) => ({ id: userId, sources, last: seconds(clock - agoHours * HOUR) });
const game = (universeId, userId, agoHours) => ({ placeId: String(universeId * 10), universeId: String(universeId), at: seconds(clock - agoHours * HOUR), userId });
const facts = (uptime, running = true) => ({ Windows: 'Windows 11 Home build 26100.2314', Uptime: uptime, Roblox: `version-3f2a1c9be4d14a07 (${running ? 'running' : 'not running'})` });

// ---- program activity: what was run on the PC and when, and the matches the bot knows about -----

const HOME = '%USERPROFILE%';
const ROBLOX = [`${HOME}\\AppData\\Local\\Roblox\\Versions\\version-3f2a1c9be4d14a07\\RobloxPlayerBeta.exe`, 'Roblox Corporation'];
const APPS = [
  ROBLOX,
  [`${HOME}\\AppData\\Local\\Discord\\app-1.0.9175\\Discord.exe`, 'Discord Inc.'],
  ['C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', 'Google LLC'],
  ['C:\\Program Files (x86)\\Steam\\steam.exe', 'Valve Corp.'],
  [`${HOME}\\AppData\\Roaming\\Spotify\\Spotify.exe`, 'Spotify AB'],
  ['C:\\Program Files\\NVIDIA Corporation\\NVIDIA app\\CEF\\NVIDIA app.exe', 'NVIDIA Corporation'],
  ['C:\\Program Files\\Microsoft VS Code\\Code.exe', 'Microsoft Corporation'],
  ['C:\\Program Files\\Mozilla Firefox\\firefox.exe', 'Mozilla Corporation'],
  ['C:\\Program Files\\LGHUB\\lghub.exe', 'Logitech Inc'],
  ['C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', 'Microsoft Corporation'],
];
// Scenario values can be functions, so "minutes ago" is measured from each scenario's own time.
const lazy = (value) => (typeof value === 'function' ? value() : value);
const ago = (minutes) => seconds(clock - minutes * 60_000);
const match = (name, startedMinutesAgo, minutes) => ({ id: name, started_at: ago(startedMinutesAgo), ...(minutes ? { ended_at: ago(startedMinutesAgo - minutes) } : {}) });
const ran = (path, minutes, src = 'prefetch', sig = 'unsigned', runs = 0) => ({ path, at: ago(minutes), src, sig, runs });

// What an ordinary PC reports: the programs running now and the run history Windows keeps.
// Without administrator rights Prefetch and BAM cannot be read, so only the other sources appear.
let issued = []; // the matches the current scenario's check was created with
function activity({ uptime = 192, matches = issued, admin = true, extra = [] } = {}) {
  const entry = ([path, signer], minutes, src, runs = 0) => ({ path, at: ago(minutes), src, sig: 'signed', signer, runs });
  const out = [];
  APPS.forEach((app, index) => {
    const last = 4 + index * 17;
    if (index < 6) out.push(entry(app, Math.min(last, uptime - 1 - index), 'running'));
    out.push(entry(app, last, 'launch'));
    if (index < 7) out.push(entry(app, last, 'userassist', 12 + index * 9));
    if (admin) for (let day = 0; day < 4; day += 1) out.push(entry(app, last + day * (1440 - index * 31), day ? 'prefetch' : 'bam'));
  });
  // Roblox is opened a minute or two before each match.
  if (admin) for (const game of matches) out.push({ ...entry(ROBLOX, 0, 'prefetch'), at: game.started_at - 95 });
  return [...out, ...extra];
}
const runningOnly = (programs) => programs.filter((program) => program.src === 'running');

// Starts a check `hoursAgo` in the past and walks the clock forward through each step.
async function start(hoursAgo, issue, downloadAfter = 14) {
  clock = NOW - hoursAgo * HOUR;
  const request = lazy(issue);
  issued = request.matches ?? [];
  const check = await relay.issue(key, request);
  if (downloadAfter === null) return { check, session: null };
  clock += downloadAfter * 1000;
  return { check, session: (await relay.download(check.code)).session };
}
async function pcCheck(hoursAgo, issue, body, { scan = 96, ip } = {}) {
  const { session } = await start(hoursAgo, issue);
  clock += scan * 1000;
  if (ip) relay.setIp(ip);
  const sent = await relay.send(session, { v: VERSION, seconds: scan - 4, admin: true, facts: facts('3h 12m'), clock: seconds(clock), ...lazy(body) });
  relay.setIp('203.0.113.7');
  if (sent.status !== 200) throw new Error(`report refused: ${sent.status} ${sent.text}`);
}
async function monitor(hoursAgo, issue, body, updates) {
  const { session } = await start(hoursAgo, () => ({ ...lazy(issue), mode: 'monitor' }));
  let seq = 0;
  let first = null;
  for (const update of updates) {
    clock += update.after * 1000;
    first ??= { clock: seconds(clock), ...lazy(body) };
    const sent = await relay.send(session, { v: VERSION, admin: true, facts: facts('1h 40m'), ...first, ...update.body }, { path: '/v1/live', seq: ++seq });
    if (sent.status !== 200) throw new Error(`live update refused: ${sent.status} ${sent.text}`);
  }
}

// ---- oldest first, so the relay's history checks see earlier reports ------------------------------

let played = () => [match('BS-4602', 1480, 38), match('BS-4611', 175, 44)];
await pcCheck(216, () => ({ roblox_id: id('Vortex'), player: 'Vortex', requested_by: 'Mara', matches: played() }), () => ({
  checks: checks({ 'Displays & Desktops': ['WARNING: 2 displays connected'] }),
  roblox: { userId: id('Vortex'), accounts: [account(id('Vortex'), ['switcher', 'logs']), account('9000000000000100', ['switcher', 'logs'], 30)], games: [game(7001, id('Vortex'), 2), game(7002, '9000000000000100', 30)] },
  pc: pc('1f'),
  programs: activity(),
}));

played = () => [match('BS-4640', 130, 40)];
await pcCheck(190, () => ({ roblox_id: id('Drift'), player: 'Drift', requested_by: 'Dex', matches: played() }), () => ({
  checks: checks(),
  roblox: { userId: id('Drift'), accounts: [account(id('Drift'), ['switcher', 'logs', 'studio'])], games: [game(7001, id('Drift'), 1), game(7003, id('Drift'), 20)] },
  pc: pc('7a'),
  programs: activity(),
}));

await start(150, { roblox_id: id('Onyx'), player: 'Onyx', requested_by: 'Dex' }, null);

// The same PC as Vortex. A loader was opened here five hours before this check; it is in the launch
// history now and gone from it at Vortex's next check.
played = () => [match('BS-4722', 200, 40)];
await pcCheck(120, () => ({ roblox_id: id('Jinx'), player: 'Jinx', requested_by: 'Mara', matches: played() }), () => ({
  checks: checks({ 'UAC & Prompts': ['WARNING: UAC prompts are turned off - programs can run as administrator without asking'] }),
  roblox: { userId: id('Jinx'), accounts: [account(id('Jinx'), ['switcher', 'logs'])], games: [game(7001, id('Jinx'), 1)] },
  pc: pc('1f'),
  programs: activity({ extra: [ran(`${HOME}\\Downloads\\mx-loader\\mx-loader.exe`, 300, 'launch'), ran(`${HOME}\\Downloads\\mx-loader\\mx-loader.exe`, 300, 'userassist', 'unsigned', 3)] }),
}));

await monitor(96, () => ({ roblox_id: id('Rook'), player: 'Rook', requested_by: 'Ivo', matches: [match('BS-4733', 2)] }), () => ({
  roblox: { userId: id('Rook'), accounts: [account(id('Rook'), ['switcher', 'logs'])], games: [game(7001, id('Rook'), 0)] },
  pc: pc('8c'),
  programs: runningOnly(activity()),
}), [
  { after: 70, body: { state: 'RUNNING', elapsed: 2, counts: { fail: 0, warn: 0, info: 1 }, recent: ['[19:02:11] [INFO] BSMM live monitor started'] } },
  { after: 1800, body: { state: 'RUNNING', elapsed: 1802, counts: { fail: 0, warn: 0, info: 2 }, recent: ['[19:20:40] [INFO] USB device connected'] } },
  { after: 1500, body: { state: 'ENDED', elapsed: 3302, counts: { fail: 0, warn: 0, info: 3 }, recent: [], log: ['[19:02:11] [INFO] BSMM live monitor started', '[19:20:40] [INFO] USB device connected', '[19:57:13] [INFO] BSMM monitor stopped after 00:55:02 (0 fail, 0 warn, 3 info)'] } },
]);

// Not run as administrator, so only the sources that need no rights; and a PC clock 47 minutes behind.
const BEHIND = 47 * 60;
played = () => [match('BS-4790', 75, 41)];
await pcCheck(72, () => ({ roblox_id: id('Halo'), player: 'Halo', requested_by: 'Ivo', matches: played() }), () => ({
  clock: seconds(clock) - BEHIND,
  programs: activity({ uptime: 6, admin: false, extra: [ran(`${HOME}\\Desktop\\cfg-tool.exe`, 79, 'launch')] }).map((program) => ({ ...program, at: program.at - BEHIND })),
  admin: false,
  facts: facts('0h 06m', false),
  checks: checks({
    'Session': ['WARNING: The PC was restarted 6 minutes before the check', 'INFO: Logged on 5m ago'],
    'Execution History (BAM/DAM)': ['WARNING: Run history could not be read without administrator rights'],
    'Long-term History': ['WARNING: Amcache and SRUM need administrator rights'],
    'Roblox Client Version': ['INFO: Client Status (Inactive/Last Installed)', 'SUCCESS: Build Hash -> version-3f2a1c9be4d14a07', 'SUCCESS: File Version -> 0.701.0.7010642 (x64)'],
  }),
  roblox: { userId: '9000000000000105', accounts: [account('9000000000000105', ['switcher', 'logs']), account('9000000000000104', ['switcher'], 50)], games: [game(7004, '9000000000000105', 3)] },
  pc: pc('6d'),
}));

// A harmless unsigned program, hours away from any match: listed, never flagged.
played = () => [match('BS-4821', 1500, 39), match('BS-4830', 160, 43)];
await pcCheck(48, () => ({ roblox_id: id('Quill'), player: 'Quill', requested_by: 'Mara', matches: played() }), () => ({
  checks: checks(),
  roblox: { userId: id('Quill'), accounts: [account(id('Quill'), ['switcher', 'logs']), account('9000000000000103', ['switcher'], 90)], games: [game(7001, id('Quill'), 1), game(7002, id('Quill'), 26)] },
  pc: pc('9e'),
  programs: activity({ extra: [ran('C:\\Program Files\\7-Zip\\7zFM.exe', 610), ran('C:\\Program Files\\7-Zip\\7zFM.exe', 610, 'launch')] }),
}));

await monitor(28, () => ({ roblox_id: id('Frost'), player: 'Frost', requested_by: 'Dex', matches: [match('BS-4842', 2)] }), () => ({
  roblox: { userId: id('Frost'), accounts: [account(id('Frost'), ['switcher', 'logs'])], games: [game(7001, id('Frost'), 0)] },
  pc: pc('5b'),
  programs: runningOnly(activity()),
}), [
  { after: 65, body: { state: 'RUNNING', elapsed: 2, counts: { fail: 0, warn: 0, info: 1 }, recent: ['[21:14:03] [INFO] BSMM live monitor started'] } },
  { after: 900, body: { state: 'RUNNING', elapsed: 902, counts: { fail: 1, warn: 1, info: 1 }, recent: ['[21:22:48] [WARN] New program started mid-match from Downloads -> %USERPROFILE%\\Downloads\\fps_unlock.exe', "[21:23:02] [FAIL] Transparent click-through overlay window 'ov' from untrusted path (PID 11840) -> %USERPROFILE%\\Downloads\\fps_unlock.exe"] } },
  { after: 1260, body: { state: 'ENDED', elapsed: 2162, counts: { fail: 2, warn: 1, info: 2 }, recent: [], log: [
    '[21:14:03] [INFO] BSMM live monitor started',
    '[21:22:48] [WARN] New program started mid-match from Downloads -> %USERPROFILE%\\Downloads\\fps_unlock.exe',
    "[21:23:02] [FAIL] Transparent click-through overlay window 'ov' from untrusted path (PID 11840) -> %USERPROFILE%\\Downloads\\fps_unlock.exe",
    '[21:41:30] [FAIL] Roblox connected to a program on this PC (127.0.0.1:6969) - how executors talk to Roblox',
    '[21:50:05] [INFO] BSMM monitor stopped after 00:36:02 (2 fail, 1 warn, 2 info)',
  ] } },
]);

await start(9, { roblox_id: id('Raze'), player: 'Raze', requested_by: 'Ivo' });

// A swapped script: three checks reported, six seconds after the download.
await pcCheck(5, () => ({ roblox_id: id('Blitz'), player: 'Blitz', requested_by: 'Mara', matches: [match('BS-4855', 140, 42)] }), () => ({
  seconds: 3,
  checks: checks().slice(0, 3),
  roblox: { userId: id('Blitz'), accounts: [account(id('Blitz'), ['switcher'])], games: [] },
  pc: pc('4a'),
}), { scan: 6 });

// An unsigned macro tool that starts with Windows, so it was running through both matches.
played = () => [match('BS-4861', 150, 39), match('BS-4868', 45, 36)];
const PAD = `${HOME}\\AppData\\Roaming\\macro-pad\\pad.exe`;
await pcCheck(3, () => ({ roblox_id: id('Echo'), player: 'Echo', requested_by: 'Dex', matches: played() }), () => ({
  programs: activity({ extra: [ran(PAD, 190, 'running'), ran(PAD, 190, 'launch'), ran(PAD, 190, 'userassist', 'unsigned', 41), ran(PAD, 1630), ran(PAD, 3070)] }),
  checks: checks({
    'UAC & Prompts': ['WARNING: UAC prompts are turned off - programs can run as administrator without asking'],
    'Window Animations': ['WARNING: Window animations are off - an overlay can be closed without a visible fade'],
    'Root Certificates': ["WARNING: Root certificate installed in user store 'Fiddler Root' (issued 2026-03-02, 9A41C0DE...)"],
    'Autorun / Persistence': ['WARNING: Unsigned program starts with Windows -> %USERPROFILE%\\AppData\\Roaming\\macro-pad\\pad.exe', 'INFO: 14 autorun entries read'],
  }),
  roblox: { userId: id('Echo'), accounts: [account(id('Echo'), ['switcher', 'logs']), account('9000000000000102', ['logs'], 40)], games: [game(7001, id('Echo'), 0.3), game(7003, '9000000000000102', 40)] },
  pc: pc('3c'),
}), { ip: '198.51.100.24' });

played = () => [match('BS-4871', 1490, 40), match('BS-4874', 95, 41), match('BS-4879', 48, 38)];
await pcCheck(0.9, () => ({ roblox_id: id('Kairo'), player: 'Kairo', requested_by: 'Mara', matches: played() }), () => ({
  checks: checks(),
  roblox: { userId: id('Kairo'), accounts: [account(id('Kairo'), ['switcher', 'logs'])], games: [game(7001, id('Kairo'), 0.2), game(7002, id('Kairo'), 5)] },
  pc: pc('2b'),
  programs: activity(),
}));

// A cheat opened a minute or two before each of three matches, closed after the last one, then deleted.
// The PC was restarted 19 minutes before the check, so nothing running is older than that.
played = () => [match('BS-4866', 1560, 41), match('BS-4877', 185, 46), match('BS-4881', 55, 33)];
const MATCHA = `${HOME}\\Downloads\\matcha-external\\matcha.exe`;
const SVC = `${HOME}\\Desktop\\svc_host.exe`;
await pcCheck(0.2, () => ({ roblox_id: id('Vortex'), player: 'Vortex', requested_by: 'Mara', matches: played() }), () => ({
  programs: activity({ uptime: 19, extra: [
    ran(MATCHA, 1564, 'prefetch', 'missing'), ran(MATCHA, 189, 'prefetch', 'missing'), ran(MATCHA, 58.5, 'prefetch', 'missing'),
    ran(MATCHA, 58.5, 'launch', 'missing'), ran(MATCHA, 58.5, 'bam', 'missing'), ran(MATCHA, 21, 'exit', 'missing'),
    ran(SVC, 1563.5), ran(SVC, 188.5), ran(SVC, 58), ran(SVC, 58, 'launch'), ran(SVC, 16, 'running'),
  ] }),
  facts: facts('0h 19m'),
  checks: checks({
    'Session': ['WARNING: The PC was restarted 19 minutes before the check', 'INFO: Logged on 18m ago'],
    'Defender Exclusions': ['FAILURE: Defender exclusion -> %USERPROFILE%\\Desktop\\svc_host.exe', 'FAILURE: Defender exclusion -> %USERPROFILE%\\AppData\\Local\\Temp\\mx'],
    'Defender History': ['FAILURE: Defender blocked Trojan:Win64/Injector 2 days ago, then it was allowed -> %USERPROFILE%\\Downloads\\mx-loader.zip'],
    'Vulnerable Drivers': ['FAILURE: Known vulnerable driver loaded (iqvw64e.sys) - the usual way kernel cheats get in -> C:\\Windows\\Temp\\iqvw64e.sys'],
    'Driver Install Log': ['WARNING: A kernel driver was installed 21 minutes ago -> C:\\Windows\\Temp\\iqvw64e.sys'],
    'Cheat Files & Shortcuts': ['FAILURE: Cheat-named folder [matcha] -> %USERPROFILE%\\Downloads\\matcha-external', 'FAILURE: Cheat-named shortcut [matcha] -> %USERPROFILE%\\AppData\\Roaming\\Microsoft\\Windows\\Recent\\matcha.lnk', 'INFO: 4,812 files looked at'],
    'Code Fingerprints': ['FAILURE: Executor Lua functions inside a program (getgenv, hookmetamethod, 14 more) -> %USERPROFILE%\\Desktop\\svc_host.exe', 'FAILURE: Program is packed with VMProtect and talks to a KeyAuth loader -> %USERPROFILE%\\Desktop\\svc_host.exe', 'INFO: Looked inside 143 programs'],
    'Service Memory Traces': ['FAILURE: [Explorer] opened or showed since boot [matcha] -> %USERPROFILE%\\Downloads\\matcha-external\\matcha.exe', 'FAILURE: [Task Scheduler] ran since boot -> %USERPROFILE%\\Desktop\\svc_host.exe'],
    'Change Journal Evidence': ['FAILURE: Program deleted 4 minutes before the check -> %USERPROFILE%\\Downloads\\matcha-external\\matcha.exe', 'WARNING: imgui.ini written 31 minutes ago, then deleted -> %USERPROFILE%\\Downloads\\matcha-external\\imgui.ini'],
    'Prefetch Health': ['WARNING: 38 Prefetch files were deleted in the last hour'],
    'Roblox Bridge & Proxy': ['WARNING: Roblox tried to reach a server on this PC 3 time(s) (executor bridges run a local server)'],
    'Program Launch Traces': ['WARNING: Program ran from Downloads and no longer exists -> %USERPROFILE%\\Downloads\\matcha-external\\matcha.exe', 'INFO: 212 launch records read'],
  }),
  roblox: { userId: id('Vortex'), accounts: [account(id('Vortex'), ['switcher', 'logs']), account('9000000000000101', ['logs', 'studio'], 6)], games: [game(7001, id('Vortex'), 0.4), game(7004, '9000000000000101', 6), game(7002, id('Vortex'), 22)] },
  pc: pc('1f'),
}));

await monitor(0.12, () => ({ roblox_id: id('Tide'), player: 'Tide', requested_by: 'Dex', matches: [match('BS-4884', 2)] }), () => ({
  roblox: { userId: id('Tide'), accounts: [account(id('Tide'), ['switcher', 'logs'])], games: [game(7001, id('Tide'), 0)] },
  pc: pc('ab'),
  programs: [...runningOnly(activity()), ran(`${HOME}\\Documents\\AutoHotkey\\crosshair.exe`, 41, 'running')],
}), [
  { after: 60, body: { state: 'RUNNING', elapsed: 2, counts: { fail: 0, warn: 0, info: 1 }, recent: ['[22:40:10] [INFO] BSMM live monitor started'] } },
  { after: 240, body: { state: 'RUNNING', elapsed: 242, counts: { fail: 0, warn: 1, info: 1 }, recent: ['[22:43:55] [WARN] New PCIe device appeared mid-match (no driver) - worth a look'] } },
]);

await start(0.02, { roblox_id: id('Wisp'), player: 'Wisp', requested_by: 'Ivo' }, null);

// ---- read everything back the way the website does --------------------------------------------------

clock = NOW;
const list = (await relay.call('GET', '/v1/checks?limit=50', { key })).json;
const details = {};
for (const check of list.checks) details[check.id] = (await relay.call('GET', `/v1/checks/${check.id}`, { key })).json;

writeFileSync(output, JSON.stringify({ generatedAt: NOW, list, details }));
console.log(`${list.checks.length} sample checks written to ${output}`);
for (const check of list.checks) console.log(`  ${check.id}  ${check.status.padEnd(10)} ${String(check.verdict?.score ?? '-').padStart(3)} ${(check.verdict?.label ?? '').padEnd(10)} ${check.mode.padEnd(7)} ${check.player}  flags=${details[check.id].flags.map((flag) => flag.code).join(',')}`);
