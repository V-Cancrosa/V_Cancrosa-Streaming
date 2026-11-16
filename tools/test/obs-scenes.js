const { chromium } = require('playwright');
(async () => { const b = await chromium.launch({ args: ['--allow-file-access-from-files'] }); const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.route(/localhost:7777\//, r => { const u = new URL(r.request().url()); let body = { ok: true };
    if (u.pathname === '/obsws') body = { ok: true, url: 'ws://127.0.0.1:4455', password: 'tajne123' };
    if (u.pathname === '/twitch/streamkey') body = { ok: true, key: 'k' };
    r.fulfill({ contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) }); });
  await p.goto('file://' + process.cwd() + '/site/obs.html'); await p.waitForTimeout(2500);
  console.log('before:', await p.evaluate(() => [...document.querySelectorAll('.chk')].map(c => c.querySelector('b').textContent + ': ' + c.querySelector('p').textContent).join('\n')));
  await p.click('[data-fix="scenes"]'); await p.waitForTimeout(5000);
  console.log('after:', await p.evaluate(() => document.querySelector('#ic-scenes').className + ' ' + [...document.querySelectorAll('.chk')].find(c => c.textContent.includes('Sceny')).querySelector('p').textContent));
  // kokpit: etap → scena OBS
  const l = await b.newPage(); l.on('pageerror', e => errs.push('live: ' + e.message));
  await l.route(/localhost:7777\//, r => r.fulfill({ contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: new URL(r.request().url()).pathname === '/obsws' ? '{"ok":true,"url":"ws://127.0.0.1:4455","password":"tajne123"}' : '{"ok":true}' }));
  await l.goto('file://' + process.cwd() + '/site/live.html'); await l.waitForTimeout(2500);
  await l.click('[data-go="brb"]'); await l.waitForTimeout(2500);
  await l.click('[data-go="game"]'); await l.waitForTimeout(2500);
  console.log('errs', errs); await b.close(); })();
