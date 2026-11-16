const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ args: ['--allow-file-access-from-files'] });
  const pages = ['panel.html','overlay.html','scenes.html?scene=start','layouts.html?layout=talk','stage.html','alerts.html','censor.html','builder.html','page.html','site/index.html','site/look.html','site/games.html','site/screens.html','site/layouts.html','site/creator.html','site/settings.html','site/pilot.html','site/voice.html','site/live.html','site/obs.html','site/log.html','site/bot.html'];
  for (const u of pages) {
    const pg = await b.newPage({ viewport: { width: 1600, height: 900 } });
    const errs = []; pg.on('pageerror', e => errs.push(e.message));
    await pg.goto('file://' + process.cwd() + '/' + u); await pg.waitForTimeout(1500);
    console.log(u.padEnd(28), errs.length ? 'ERR ' + errs.slice(0,3).join(' | ') : 'ok');
    await pg.close();
  }
  await b.close();
})();
