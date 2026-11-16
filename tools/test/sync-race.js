// dwie „przeglądarki” (osobne konteksty) + udawany GameRadar z /settings: zmiany pole po polu nie mogą się cofać
const { chromium } = require('playwright'); const http = require('http');
let store = null, rev = 0, from = '';
const srv = http.createServer((q, r) => { let b = ''; q.on('data', d => b += d); q.on('end', () => {
  const h = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'content-type': 'application/json' };
  if (q.method === 'OPTIONS') { r.writeHead(200, h); return r.end('{}'); }
  const u = new URL(q.url, 'http://x');
  if (u.pathname === '/settings') { if (q.method === 'POST') { const d = JSON.parse(b); store = d.settings; rev++; from = d.client; r.writeHead(200, h); return r.end(JSON.stringify({ ok: true, rev })); } r.writeHead(200, h); return r.end(JSON.stringify({ rev, from, settings: store })); }
  if (u.pathname === '/kv') { r.writeHead(200, h); return r.end(q.method === 'POST' ? '{"ok":true}' : JSON.stringify({ rev: 0, items: {} })); }
  r.writeHead(200, h); r.end('{"ok":true}'); }); }).listen(7799);
(async () => {
  const b = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const mk = async () => { const c = await b.newContext(); const p = await c.newPage(); await p.addInitScript(() => localStorage.setItem('obsGameOverlay.v1', JSON.stringify({ localUrl: 'http://localhost:7799', stage: 'game', a: 1 })));
    await p.goto('file://' + process.cwd() + '/site/screens.html'); return p; };
  const A = await mk(), B = await mk();
  await A.waitForTimeout(2500);
  const set = (p, patch) => p.evaluate(x => { const s = JSON.parse(localStorage.getItem('obsGameOverlay.v1')); localStorage.setItem('obsGameOverlay.v1', JSON.stringify({ ...s, ...x })); }, patch);
  // A i B zmieniają różne pola niemal jednocześnie
  await set(A, { stage: 'screen', scene: 'prep' }); await set(B, { sceneHero: true });
  await A.waitForTimeout(400); await set(A, { cdMin: 10 });
  await A.waitForTimeout(6000);
  const get = p => p.evaluate(() => JSON.parse(localStorage.getItem('obsGameOverlay.v1')));
  const a = await get(A), bb = await get(B);
  const pick = o => ({ stage: o.stage, scene: o.scene, sceneHero: o.sceneHero, cdMin: o.cdMin });
  console.log('A', JSON.stringify(pick(a))); console.log('B', JSON.stringify(pick(bb))); console.log('srv', JSON.stringify(pick(store)), 'rev', rev);
  await b.close(); srv.close();
})();
