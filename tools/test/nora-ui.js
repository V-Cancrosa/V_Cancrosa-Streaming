const { chromium } = require('playwright');
(async () => { const b = await chromium.launch({ args: ['--allow-file-access-from-files'] }); const p = await b.newPage({ viewport: { width: 560, height: 760 }, deviceScaleFactor: 1 });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file://' + process.cwd() + '/nora/ui/index.html'); await p.waitForTimeout(3000);
  await p.screenshot({ path: process.argv[2] + '/nora.png' }); console.log('errs', errs); await b.close(); })();
