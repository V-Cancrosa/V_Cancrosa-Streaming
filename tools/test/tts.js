const { chromium } = require('playwright');
function wav(sec = 0.4) { const sr = 16000, n = Math.floor(sr * sec), b = Buffer.alloc(44 + n * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * 2, 4); b.write('WAVEfmt ', 8); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(sr, 24); b.writeUInt32LE(sr * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) b.writeInt16LE(Math.round(Math.sin(i / 8) * 8000), 44 + i * 2); return b; }
(async () => {
  const br = await chromium.launch({ args: ['--allow-file-access-from-files', '--autoplay-policy=no-user-gesture-required'] });
  const pg = await br.newPage({ viewport: { width: 1400, height: 900 } });
  const reqs = []; const errs = []; pg.on('pageerror', e => errs.push(e.message));
  await pg.route(/localhost:7777\/tts/, r => { const u = new URL(r.request().url()); reqs.push(u.pathname + ' ' + (u.searchParams.get('voice') || '') + ' ' + (u.searchParams.get('text') || ''));
    if (u.pathname === '/tts/voices') return r.fulfill({ contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify({ ok: true, voices: [{ id: 'PL-F', name: 'Paulina', lang: 'pl-PL', gender: 'female' }, { id: 'PL-M', name: 'Adam', lang: 'pl-PL', gender: 'male' }, { id: 'EN-M', name: 'David', lang: 'en-US', gender: 'male' }, { id: 'EN-F', name: 'Zira', lang: 'en-US', gender: 'female' }] }) });
    return r.fulfill({ contentType: 'audio/wav', headers: { 'access-control-allow-origin': '*' }, body: wav() }); });
  await pg.goto('file://' + process.cwd() + '/site/voice.html'); await pg.waitForTimeout(800);
  await pg.screenshot({ path: process.argv[2] + '/voice.png' });
  await pg.click('[data-who="myr"]'); await pg.click('#sayGo'); await pg.waitForTimeout(2500);
  console.log(await pg.evaluate(() => [VMTTS.detect('Thanks for the follow, mate'), VMTTS.detect('dzieki ziom'), VMTTS.clean('Cheer100 looool http://x.pl aaaaaaaa'), VMTTS.clean('😀😀')]));
  // alert z wiadomością od bitsów
  const a = await br.newPage(); a.on('pageerror', e => errs.push('alerts: ' + e.message));
  await a.route(/localhost:7777\/tts/, r => pg.route ? (reqs.push('A ' + new URL(r.request().url()).searchParams.get('text')), r.fulfill(new URL(r.request().url()).pathname === '/tts/voices' ? { contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: '{"ok":true,"voices":[{"id":"PL-M","name":"Adam","lang":"pl-PL","gender":"male"}]}' } : { contentType: 'audio/wav', headers: { 'access-control-allow-origin': '*' }, body: wav(0.2) })) : 0);
  await a.goto('file://' + process.cwd() + '/alerts.html'); await a.waitForTimeout(800);
  await a.evaluate(() => new BroadcastChannel('obsGameOverlay').postMessage({ type: 'alert', event: { type: 'cheer', user: 'Lis', amount: 500, message: 'Cheer500 Super stream, keep going!' } }));
  await a.waitForTimeout(3000);
  console.log(reqs.join('\n')); console.log('errs', errs);
  await br.close();
})();
