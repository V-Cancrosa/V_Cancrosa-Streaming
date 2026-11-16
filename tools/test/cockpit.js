const { chromium } = require('playwright');
(async () => {
  const br = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const pg = await br.newPage({ viewport: { width: 1500, height: 950 } });
  const errs = []; pg.on('pageerror', e => errs.push(e.message));
  const hits = [];
  let n = 0;
  await pg.route(/localhost:7777\//, r => { const u = new URL(r.request().url()); hits.push(u.pathname + u.search.slice(0, 60)); let body = { ok: true };
    if (u.pathname === '/events') { if (!u.searchParams.has('after')) body = { last: 3 }; else if (n++ === 0) body = { last: 3, events: [
      { id: 1, type: 'chat', user: 'LisekPL', color: '#ff7f50', text: 'Siema Vince! Co dziś gramy?', msgId: 'm1', userId: '111', at: Date.now() },
      { id: 2, type: 'chat', user: 'spam_bot22', text: 'Best viewers at cheap-viewers dot com', msgId: 'm2', userId: '222', flag: { level: 'suspect', reasons: ['link'] }, at: Date.now() },
      { id: 3, type: 'cheer', user: 'Ragnarok', amount: 500, message: 'Super stream!', at: Date.now() }] }; else body = { last: 3, events: [] }; }
    else if (u.pathname === '/vote') body = { active: false, a: '', b: '', va: 0, vb: 0, winner: '' };
    else if (u.pathname === '/audience') body = { live: true, viewers: 12 };
    else if (u.pathname === '/obsws') body = { ok: true, url: 'ws://127.0.0.1:4455', password: 'tajne123' };
    r.fulfill({ contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) }); });
  await pg.goto('file://' + process.cwd() + '/site/live.html');
  await pg.evaluate(() => localStorage.setItem('obsGameOverlay.v1', JSON.stringify({ theme: 'g-vince', stage: 'screen', scene: 'prep' })));
  n = 0; await pg.reload(); n = 0; await pg.waitForTimeout(2500);
  await pg.screenshot({ path: process.argv[2] + '/live1.png' });
  await pg.click('#bNext'); await pg.waitForTimeout(2500);
  console.log('after next:', await pg.evaluate(() => { const s = JSON.parse(localStorage.getItem('obsGameOverlay.v1')); return [s.stage, s.scene, !!s.sceneUntil]; }));
  await pg.click('[data-go="game"]'); await pg.waitForTimeout(2500);
  console.log('after game:', await pg.evaluate(() => JSON.parse(localStorage.getItem('obsGameOverlay.v1')).stage));
  await pg.click('#mMic'); await pg.click('#bStream'); await pg.waitForTimeout(800);
  await pg.click('#bPanic'); await pg.waitForTimeout(500);
  await pg.hover('.msg'); await pg.click('.msg [data-mod="delete"]'); await pg.waitForTimeout(300);
  await pg.click('[data-replay="3"]'); await pg.waitForTimeout(300);
  await pg.screenshot({ path: process.argv[2] + '/live2.png' });
  const ph = await br.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
  await ph.route(/localhost:7777\//, r => r.fulfill({ contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: '{"ok":true}' }));
  await ph.goto('file://' + process.cwd() + '/site/live.html'); await ph.waitForTimeout(1500);
  await ph.screenshot({ path: process.argv[2] + '/live-phone.png', fullPage: true });
  console.log('scroll width', await ph.evaluate(() => document.documentElement.scrollWidth));
  console.log(hits.filter(h => !/^\/(events|vote|audience)/.test(h)).join('\n')); console.log('errs', errs);
  await br.close();
})();
