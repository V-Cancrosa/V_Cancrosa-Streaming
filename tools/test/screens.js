const { chromium } = require('playwright');
(async () => { const b = await chromium.launch({ args: ['--allow-file-access-from-files'] }); const p = await b.newPage({ viewport: { width: 1600, height: 1000 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.addInitScript(() => { if (!localStorage.getItem('obsGameOverlay.v1')) localStorage.setItem('obsGameOverlay.v1', JSON.stringify({ theme: 'g-myr', sceneHero: true, stage: 'screen', scene: 'prep', mode: 'manual', game: 'Red Alert 3' })); });
  await p.goto('file://' + process.cwd() + '/site/screens.html'); await p.waitForTimeout(3000);
  // ustawienia ekranu + uwaga
  await p.click('.cell[data-id="prep"] details summary'); await p.fill('[data-t="big"][data-k="prep"]', 'ROZGRZEWKA'); await p.press('[data-t="big"][data-k="prep"]', 'Tab');
  await p.uncheck('[data-hero="prep"]');
  await p.click('.cell[data-id="prep"] details:nth-of-type(2) summary'); await p.fill('[data-note="prep"]', 'herb zasłania czat'); await p.click('[data-save="prep"]');
  await p.waitForTimeout(2500);
  await p.screenshot({ path: process.argv[2] + '/rg1.png' });
  const big = await p.evaluate(() => document.querySelector('[data-pv="prep"] iframe').contentDocument.getElementById('name').dataset.text + ' | hero: ' + document.querySelector('[data-pv="prep"] iframe').contentDocument.getElementById('hero').className);
  console.log('big:', big);
  await p.click('#notesBtn'); await p.waitForTimeout(300); await p.screenshot({ path: process.argv[2] + '/rg2.png' });
  await p.evaluate(() => navigator.clipboard && 0);
  console.log('errs', errs); await b.close(); })();
