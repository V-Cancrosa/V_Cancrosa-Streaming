/*
  Automoderacja czatu – wykrywanie (kokpit w OBS i w przeglądarce); kary wykonuje GameRadar (/bot/act, moduł bota),
  który pilnuje, żeby jedna wiadomość dostała jedną karę, i stopniuje je (ostrzeżenie → timeout → dłuższy).
  VMAutomod.check(ev, settings) → 'hate' | 'words' | 'caps' | 'links' | 'spam' | null
  Bez kontroli: właściciel kanału, moderatorzy, VIP-y, boty kanału (Moobot…), wiadomości bota Nory; linki wolno też subskrybentom.
  Ustawienia: bot { on, automod { on, words, caps, links, spam, timeout } } – strona serwisu «Bot czatu».
*/
(function () {
  const recent = new Map();     // login → [{ t, at }] – powtarzane wiadomości
  const LINK = /(https?:\/\/|www\.)\S+|\b[\w-]{2,}\.(com|pl|net|org|gg|io|ly|me|xyz|ru|co|link|shop|store|site|online|live|top|info|biz)\b(\/\S*)?/i;
  function check(ev, s) {
    const b = (s && s.bot) || {}, am = b.automod || {};
    if (!b.on || am.on === false || !ev || ev.type !== 'chat' || ev.test || ev.bot || ev.hidden || ev.command) return null;
    const badges = (ev.badges || []).map(String);
    if (badges.some(x => ['broadcaster', 'moderator', 'vip'].includes(x))) return null;
    const text = String(ev.text || '');
    if (am.words !== false && window.VMWords) {
      const c = window.VMWords.check(text);
      if (c && c.level === 'hard') return 'hate';
      if (c && (c.level === 'soft' || c.level === 'insult')) return 'words';
    }
    if (am.caps !== false) {
      const letters = text.replace(/[^\p{L}]/gu, '');
      if (letters.length >= 12 && letters.replace(/[^\p{Lu}]/gu, '').length / letters.length >= 0.7) return 'caps';
    }
    if (am.links !== false && LINK.test(text) && !badges.some(x => ['subscriber', 'founder'].includes(x)) && !/clips\.twitch\.tv|twitch\.tv\/\w+\/clip/i.test(text)) return 'links';
    if (am.spam !== false) {
      if (/(.)\1{19,}/u.test(text)) return 'spam';
      const key = String(ev.login || ev.user || ''), norm = text.toLowerCase().replace(/\s+/g, ' ').trim(), now = Date.now();
      const list = (recent.get(key) || []).filter(x => now - x.at < 60000); list.push({ t: norm, at: now }); recent.set(key, list);
      if (norm.length >= 3 && list.filter(x => x.t === norm).length >= 3) return 'spam';
    }
    return null;
  }
  window.VMAutomod = { check };
})();
