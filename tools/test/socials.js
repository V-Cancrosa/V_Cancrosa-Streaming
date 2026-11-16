const { chromium } = require('playwright');
(async () => { const b = await chromium.launch({ args: ['--allow-file-access-from-files'] }); const errs = [];
  for (const w of ['vince', 'chip', 'ragnar', 'toro', 'myr', 'zarin']) { const p = await b.newPage({ viewport: { width: 1920, height: 1080 } }); p.on('pageerror', e => errs.push(w + ': ' + e.message));
    await p.addInitScript(x => localStorage.setItem('obsGameOverlay.v1', JSON.stringify({ theme: 'g-' + x, sceneHero: true, chatDir: 'off', gameMode: 'off' })), w);
    await p.goto('file://' + process.cwd() + '/scenes.html?scene=brb'); await p.waitForTimeout(2000);
    await p.screenshot({ path: process.argv[2] + '/soc-' + w + '.png', clip: { x: 760, y: 0, width: 1160, height: 620 } }); await p.close(); }
  console.log('errs', errs); await b.close(); })();
