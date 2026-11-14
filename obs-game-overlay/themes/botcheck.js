/*
  Ocena wiadomości z czatu – te same reguły co w wykrywaczu (detector.ps1 → Get-ChatFlag), żeby testy
  w panelu i na stronie demo działały też bez wykrywacza. Wynik: null albo { level: 'watch'|'suspect', score, reasons[] }.
    ev.accountAgeDays – wiek konta (w testach podawany ręcznie; na żywo bierze go wykrywacz z Twitcha)
    ctx: { first: pierwsza wiadomość tej osoby, category: kategoria na Twitchu, gaming: czy coś jest uruchomione, lang }
*/
(function () {
  const NON_GAME = ['art', 'software and game development', 'makers & crafting', 'just chatting', 'music', 'science & technology', 'talk shows & podcasts', 'food & drink'];
  const seen = new Map();          // login → liczba wiadomości (dla „pierwszej wiadomości”)
  const recent = [];               // ostatnie teksty (ten sam tekst od kilku kont)
  const T = {
    pl: { h: 'konto ma {n} h', d: 'konto ma {n} dni', link1: 'link na początku znajomości', link: 'link', ad: 'tekst jak z reklamy widzów/followów',
      generic: 'ogólnikowe „fajny stream” na dzień dobry', mismatch: 'pisze o graniu, a kategoria to „{c}”', mismatch2: 'pisze o graniu, a nic nie jest uruchomione',
      alpha: 'inny alfabet', copy: 'ten sam tekst od kilku kont', gen: 'nick jak z generatora', rep: 'powtarza ten sam tekst' },
    en: { h: 'account is {n} h old', d: 'account is {n} days old', link1: 'link in a first message', link: 'link', ad: 'reads like a viewer/follower ad',
      generic: 'generic "nice stream" as a first message', mismatch: 'talks about playing, but the category is "{c}"', mismatch2: 'talks about playing, but nothing is running',
      alpha: 'different alphabet', copy: 'same text from several accounts', gen: 'generated-looking name', rep: 'repeats the same text' }
  };
  const GOOD = ['nightbot', 'streamelements', 'streamlabs', 'fossabot', 'moobot', 'wizebot', 'sery_bot', 'soundalerts', 'botrixoficial', 'commanderroot', 'pretzelrocks', 'kofistreambot', 'blerp', 'streamstickers', 'tangiabot', 'own3d', 'creatisbot', 'frostytoolsdotcom', 'lumiastream', 'restreambot', 'botisimo', 'deepbot', 'phantombot', 'coebot', 'ankhbot', 'vivbot', 'super_timer_bot'];
  // nick jak z generatora (ten sam test co w wykrywaczu)
  function botName(l) {
    l = String(l || '').toLowerCase();
    if (/^[a-z]+_?\d{4,}$/.test(l) || /\d{6,}/.test(l)) return true;
    const letters = l.replace(/[^a-z]/g, ''), digits = l.replace(/[^0-9]/g, '').length;
    if (l.length >= 10 && digits >= 3 && letters.length >= 5 && letters.replace(/[^aeiouy]/g, '').length / letters.length < 0.2) return true;
    return letters.length >= 8 && /[bcdfghjklmnpqrstvwxz]{6,}/.test(letters);
  }
  const userTexts = new Map();
  const strip = t => String(t || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\u0142/g, 'l');

  function check(ev, ctx = {}) {
    if (!ev || ev.type !== 'chat') return null;
    const tr = T[ctx.lang === 'en' ? 'en' : 'pl'], f = (k, o = {}) => tr[k].replace(/\{(\w)\}/g, (_, x) => o[x]);
    if ((ev.badges || []).some(b => ['broadcaster', 'moderator', 'vip', 'subscriber', 'founder'].includes(b))) return null;
    const login = String(ev.login || ev.user || '').toLowerCase();
    if (GOOD.includes(login)) return null;
    const n = seen.get(login) || 0; seen.set(login, n + 1);
    const first = ctx.first != null ? ctx.first : n === 0, early = n < 3;
    const t = strip(ev.text);
    let score = 0; const why = [];
    const age = ev.accountAgeDays;
    if (age != null && age >= 0) {
      if (age < 2) { score += 3; why.push(f('h', { n: Math.round(age * 24) })); }
      else if (age < 14) { score += 2; why.push(f('d', { n: Math.round(age) })); }
      else if (age < 60 && first) { score += 1; why.push(f('d', { n: Math.round(age) })); }
    }
    if (early && botName(login)) { score += 1; why.push(tr.gen); }
    const own = t.replace(/\W+/g, ' ').trim();
    if (own.length >= 6) { const h = (userTexts.get(login) || []).filter(x => Date.now() - x.at < 600000); if (h.filter(x => x.text === own).length >= 2) { score += 2; why.push(tr.rep); } h.push({ text: own, at: Date.now() }); userTexts.set(login, h.slice(-8)); }
    if (/(https?:\/\/|www\.|\b[a-z0-9-]+\s?\.\s?(com|net|org|ru|xyz|io|gg|ly|shop|site|online|top)\b|discord\.gg)/.test(t)) { score += early ? 3 : 1; why.push(early ? tr.link1 : tr.link); }
    if (/(viewers|followers|follows|promot|cheap|streamboo|dogehype|bigfollows|grow your (channel|stream)|kup (widzow|followow)|rozkrec\w* kanal|remove the space|only ?fans|crypto|nft|forex)/.test(t)) { score += 4; why.push(tr.ad); }
    if (first && /^\W*(hi|hello|hey|yo|siema|czesc|hej|witam)?\W*(streamer|bro|friend)?\W*(fajnie|super|swietnie|dobrze|niezle|ladnie|nice|great|good|cool|awesome|amazing|love)\W+(grasz|gra|stream\w*|content|gameplay|game|play\w*|channel|kanal|vibe|video)\b/.test(t)) { score += 2; why.push(tr.generic); }
    const cat = String(ctx.category || '').toLowerCase();
    if (!ctx.gaming && cat && NON_GAME.includes(cat) && /\b(grasz|grac|gra\b|gierk|gameplay|game|play(ing)?|gg|level|boss)/.test(t)) { score += 3; why.push(f('mismatch', { c: ctx.category })); }
    else if (!ctx.gaming && !cat && first && /\b(grasz|gameplay|playing)\b/.test(t)) { score += 2; why.push(tr.mismatch2); }
    if (first && /[\u0400-\u04ff\u0600-\u06ff\u0900-\u097f\u0e00-\u0e7f]/.test(ev.text || '') && !/[a-z]{3}/i.test(ev.text || '')) { score += 1; why.push(tr.alpha); }
    const norm = t.replace(/\W+/g, ' ').trim(), now = Date.now();
    while (recent.length && now - recent[0].at > 60000) recent.shift();
    if (norm.length >= 12) { if (recent.some(r => r.text === norm && r.login !== login)) { score += 2; why.push(tr.copy); } recent.push({ text: norm, login, at: now }); }
    if (score < 2) return null;
    return { level: score >= 4 ? 'suspect' : 'watch', score, reasons: why, ageDays: age, first };
  }
  window.OverlayBotCheck = { check, reset() { seen.clear(); recent.length = 0; } };
})();
