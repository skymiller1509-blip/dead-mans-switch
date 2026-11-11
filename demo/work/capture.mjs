// Capture Dead Man's Switch demo stills via raw CDP (chrome-headless-shell).
// Local pages (cards + frontend) need no proxy; explorer pages go through
// the proxy shim on 127.0.0.1:18080 (start it first: node proxy_shim.mjs).
import { spawn } from 'node:child_process';
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';

const CHROME = '/home/hatch/workspace/tools/browsers/chrome-headless-shell/linux-157.0.8103.50/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = '/home/hatch/workspace/hackathons/reactive/dead-mans-switch/demo';
const FRAMES = `${BASE}/frames`;
const FRONTEND = '/home/hatch/workspace/hackathons/reactive/dead-mans-switch/frontend';
const CARDS = `${BASE}/work/cards`;
const PORT = 8937, DBG = 9237;
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
mkdirSync(FRAMES, { recursive: true });

const server = spawn('python3', ['-m', 'http.server', String(PORT), '--directory', FRONTEND], { stdio: 'ignore' });
const chrome = spawn(CHROME, [
  '--no-sandbox', '--disable-gpu', '--ignore-certificate-errors',
  `--remote-debugging-port=${DBG}`, '--user-data-dir=/tmp/chrome-prof-dms',
  '--proxy-server=http://127.0.0.1:18080',
  '--window-size=1920,1080', 'about:blank'
], { stdio: 'ignore' });

async function getWsUrl() {
  for (let i = 0; i < 40; i++) {
    try { const r = await fetch(`http://localhost:${DBG}/json/version`); const j = await r.json(); if (j.webSocketDebuggerUrl) return j.webSocketDebuggerUrl; } catch {}
    await sleep(500);
  }
  throw new Error('chrome debug port never came up');
}

const ws = new WebSocket(await getWsUrl());
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let nextId = 0; const pending = new Map();
ws.onmessage = (ev) => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } };
function send(method, params = {}, sessionId) {
  return new Promise((resolve) => { const id = ++nextId; pending.set(id, resolve); ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) })); });
}

async function openTab(url) {
  const t = await send('Target.createTarget', { url });
  const att = await send('Target.attachToTarget', { targetId: t.result.targetId, flatten: true });
  const S = att.result.sessionId;
  await send('Page.enable', {}, S);
  await send('Runtime.enable', {}, S);
  await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false }, S);
  return S;
}
async function evl(S, expr) {
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }, S);
  if (r.result?.exceptionDetails) console.log('  EVAL ERR', JSON.stringify(r.result.exceptionDetails).slice(0, 200));
  return r.result?.result?.value;
}
async function shot(S, name) {
  const r = await send('Page.captureScreenshot', { format: 'png' }, S);
  writeFileSync(`${FRAMES}/${name}.png`, Buffer.from(r.result.data, 'base64'));
  console.log('shot', name);
}

// ---- 1. Card stills ----
for (const n of ['01_hook', '02_fix', '03_how', '04_proof1', '05_proof2', '06_end']) {
  const S = await openTab(`file://${CARDS}/${n}.html`);
  await sleep(700);
  await shot(S, n);
}

// ---- 2. Frontend, filled in, widened for video ----
const S = await openTab(`http://localhost:${PORT}/index.html`);
await sleep(1200);
await evl(S, `(() => {
  document.body.style.maxWidth = '1100px';
  document.getElementById('heir').value = '0xBDDf45e79f9c3e0D2F0Ec8680519e998Dd44f098';
  document.getElementById('days').value = '30';
  document.getElementById('amount').value = '0.01';
  document.getElementById('status').textContent =
    'Owner: 0x791F80c3425beD85E86202571e276dF5B1339166\\n' +
    'Heir: 0xBDDf45e79f9c3e0D2F0Ec8680519e998Dd44f098\\n' +
    'Balance: 0.01 ETH\\n' +
    'Inactivity period: 30.0 days\\n' +
    'Last activity: just now (0.00 days ago)\\n' +
    'Released: no\\nInactive now: no';
  return true;
})()`);
await sleep(500);
await shot(S, '07_frontend');

// ---- 3. Explorer pages (best effort) ----
async function explorerShot(name, url, waitText, waitMs) {
  try {
    const T = await openTab(url);
    let ok = false;
    for (let i = 0; i < waitMs / 1000; i++) {
      const t = await evl(T, `document.body ? document.body.innerText.slice(0,4000) : ''`);
      if (t && t.includes(waitText)) { ok = true; break; }
      await sleep(1000);
    }
    console.log(name, 'ready:', ok);
    await sleep(1500);
    await shot(T, name);
  } catch (e) { console.log(name, 'FAILED', String(e).slice(0, 200)); }
}

await explorerShot('08_explorer_lasna',
  'https://lasna.reactscan.net/tx/0x6ec7671aa3f46a8c2b8c97c22068d6a110de4c8b43c6b73f820db47b7ef430bd',
  '0x6ec7671aa3f46a8c2b8c97c22068d6a110de4c8b43c6b73f820db47b7ef430bd', 60000);
await explorerShot('09_explorer_basescan',
  'https://sepolia.basescan.org/tx/0x5f5dee168ed06a393bcaeb35537a5ba8e46875e5d61d65acc4f6c1f7ca7921ae',
  '0x5f5dee168ed06a393bcaeb35537a5ba8e46875e5d61d65acc4f6c1f7ca7921ae', 60000);

ws.close(); chrome.kill(); server.kill();
console.log('CAPTURE DONE');
