/*
  Synchronizacja przez GameRadar: strona na GitHub Pages w zwykłej przeglądarce ↔ OBS (inna przeglądarka, inna pamięć).
    • ustawienia ('obsGameOverlay.v1')   – kanał /settings (ten sam co pilot z telefonu),
    • strony z Kreatora, stany, widoczność – kanał /kv.
  Ustawienia łączą się POLE PO POLU: wysyłamy tylko to, co zmieniło się tutaj, doklejone do najnowszego stanu z GameRadara,
  a cudzą zmianę przyjmujemy, nie gubiąc własnych, jeszcze niewysłanych. (Dawniej wygrywał cały obiekt wysłany jako ostatni –
  starsza kopia z innego miejsca potrafiła cofnąć świeżą zmianę i ekran „przeskakiwał”.)
  W jednej przeglądarce synchronizuje tylko jedna strona naraz (Web Locks) – reszta czyta tę samą pamięć.
  Wczytują go: strony serwisu (site/*.html) i główne widoki w OBS (stage.html, page.html).
*/
(function () {
  // ---------------------------------------------------------------- migracje ustawień (settingsVersion)
  // Jedno miejsce na zmiany formatu: każdy krok przerabia ustawienia z wersji n-1 na n. Nowy format = nowy krok na końcu
  // listy (nigdy nie zmieniaj starych kroków). Uruchamia je synchronizacja (lokalne i te z GameRadara), więc każde stare
  // ustawienia – z pamięci przeglądarki, z OBS albo z kopii zapasowej – dochodzą do bieżącego formatu.
  const MIGRATIONS = [
    // 1: porządki z 1.4x – tryb «discord» i ręczny bez gry → auto; fuzja z gry: dawne fuseV/patch/fuse → «fuse-half»
    st => {
      if (st.mode === 'discord' || (st.mode === 'manual' && !st.game)) st.mode = 'auto';
      if (['patch', 'fuse'].includes(st.gameMode) || (st.fuseV !== 4 && !['game', 'off', 'fuse-game', 'fuse-half'].includes(st.gameMode))) st.gameMode = 'fuse-half';
      st.fuseV = 4;
    },
    // 2: usunięte funkcje (Discord/Lanyard, jedna scena „Start streamu”, przełączniki funkcji) – martwe klucze precz
    st => { for (const k of ['discordId', 'oneScene', 'featDiscord', 'featTwitch', 'featDetect', 'featObs']) delete st[k]; },
  ];
  const SETTINGS_VERSION = MIGRATIONS.length;
  function migrate(st) {
    st = st && typeof st === 'object' ? { ...st } : {};
    const from = +st.settingsVersion || 0;
    if (from >= SETTINGS_VERSION) return { st, changed: false };
    for (let v = from; v < SETTINGS_VERSION; v++) { try { MIGRATIONS[v](st); } catch (e) {} }
    st.settingsVersion = SETTINGS_VERSION;
    return { st, changed: true };
  }
  window.VMMigrate = window.VMMigrate || { migrate, VERSION: SETTINGS_VERSION };
  // tylko strona główna karty – ramki w środku (podglądy, stage.html w OBS) korzystają z tej samej pamięci przeglądarki
  if (window.VMSync || window.top !== window) return;
  const SET = 'obsGameOverlay.v1', KV = ['obsGameOverlay.pages', 'obsGameOverlay.pageState', 'obsGameOverlay.pageVis', 'obsGameOverlay.notes'], STATE = 'obsGameOverlay.syncState';
  const CLIENT = Math.random().toString(36).slice(2);
  const raw = k => { try { return localStorage.getItem(k); } catch (e) { return null; } };
  const parse = t => { try { return JSON.parse(t) || {}; } catch (e) { return {}; } };
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const hub = () => { const s = parse(raw(SET)); return window.vmHub ? window.vmHub(s.localUrl) : 'http://localhost:7777'; };
  let bc = null; try { bc = new BroadcastChannel('obsGameOverlay'); } catch (e) {}
  const known = {};               // ostatni tekst, który ta strona widziała / zapisała
  let base = null;                // ustawienia ostatnio uzgodnione z GameRadarem (obiekt)
  let setRev = null, kvRev = 0, ok = null, busy = false, leader = false;
  const listeners = [];
  const status = v => {
    if (ok !== v) { ok = v; listeners.forEach(f => { try { f(v); } catch (e) {} }); }
    if (leader) try { localStorage.setItem(STATE, JSON.stringify({ ok: v, at: Date.now() })); } catch (e) {}
  };
  // zmiany lokalne względem stanu uzgodnionego: { pole: wartość | undefined (usunięte) }
  function diff(local) {
    const ch = {}, b = base || {};
    for (const k of new Set([...Object.keys(local), ...Object.keys(b)])) if (!same(local[k], b[k])) ch[k] = local[k];
    return ch;
  }
  function overlay(obj, ch) { const o = { ...obj }; for (const [k, v] of Object.entries(ch)) { if (v === undefined) delete o[k]; else o[k] = v; } return o; }
  function write(key, val) {
    known[key] = val;
    try { if (raw(key) !== val) localStorage.setItem(key, val); } catch (e) { return; }
    if (bc) bc.postMessage(key === SET ? 'update' : { type: 'pages', what: 'sync' });
    try { window.dispatchEvent(new CustomEvent('vm-sync', { detail: key })); } catch (e) {}
  }
  const getSet = async () => (await fetch(hub() + '/settings', { cache: 'no-store' })).json();
  const postSet = async settings => (await fetch(hub() + '/settings', { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify({ client: CLIENT, settings }) })).json();

  // wysyłka: tylko zmienione pola, doklejone do najnowszego stanu z GameRadara
  async function pushSet() {
    const before = raw(SET), local = parse(before), ch = diff(local);
    if (!Object.keys(ch).length) { known[SET] = before; return; }
    const cur = await getSet();
    const merged = overlay(cur && cur.settings ? cur.settings : (base || {}), ch);
    const j = await postSet(merged);
    if (!j.ok) return;
    setRev = j.rev; base = merged;
    // w trakcie wysyłki mogło się tu coś jeszcze zmienić – dokładamy i wyślemy przy następnym przebiegu
    const now = raw(SET), late = now !== before ? (() => { const a = parse(before), b2 = parse(now), c = {}; for (const k of new Set([...Object.keys(a), ...Object.keys(b2)])) if (!same(a[k], b2[k])) c[k] = b2[k]; return c; })() : {};
    write(SET, JSON.stringify(overlay(merged, late)));
    if (Object.keys(late).length) known[SET] = JSON.stringify(merged);
  }
  async function pushKv(key, val) {
    const j = await (await fetch(hub() + '/kv', { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify({ client: CLIENT, key, val }) })).json();
    if (j.ok) known[key] = val;
  }
  async function pull() {
    try {
      if (!busy) {
        busy = true;
        try {
          const j = await getSet();
          if (j && j.settings && j.rev !== setRev && j.from !== CLIENT) {
            // cudza zmiana: bierzemy ją, ale własne niewysłane pola zostają (i pójdą przy następnym przebiegu)
            const ch = base ? diff(parse(raw(SET))) : {};
            setRev = j.rev; base = j.settings;
            write(SET, JSON.stringify(migrate(overlay(j.settings, ch)).st));
            if (Object.keys(ch).length) known[SET] = JSON.stringify(j.settings);
          } else if (j) {
            setRev = j.rev;
            if (j.settings && base === null) base = j.settings;
            if (!j.settings && raw(SET)) { base = {}; await pushSet(); }      // GameRadar jeszcze nic nie ma – daj mu nasze
          }
          const k = await (await fetch(hub() + '/kv?since=' + kvRev, { cache: 'no-store' })).json();
          if (k && k.items) {
            for (const [key, e] of Object.entries(k.items)) if (e.from !== CLIENT && typeof e.val === 'string') write(key, e.val);
            if (!kvRev) for (const key of KV) if (!k.items[key] && raw(key)) await pushKv(key, raw(key));
            kvRev = k.rev;
          }
        } finally { busy = false; }
      }
      status(true);
    } catch (e) { status(false); }
    setTimeout(pull, ok === false ? 6000 : 2000);
  }
  // lokalne zmiany (z tej strony albo z innych kart tej przeglądarki)
  async function scan() {
    if (busy) return;
    busy = true;
    try {
      for (const key of [SET, ...KV]) {
        const v = raw(key);
        if (v == null) continue;
        if (known[key] === undefined) { known[key] = v; continue; }
        if (v !== known[key]) { if (key === SET) await pushSet(); else await pushKv(key, v); }
      }
      status(true);
    } catch (e) { status(false); } finally { busy = false; }
  }
  function lead() {
    try { const m = migrate(parse(raw(SET))); if (m.changed && raw(SET)) localStorage.setItem(SET, JSON.stringify(m.st)); } catch (e) {}
    setInterval(scan, 700); setTimeout(() => { scan(); pull(); }, 300);
  }
  // jedna synchronizująca strona na przeglądarkę; pozostałe tylko pokazują stan
  function follow() {
    const tick = () => { if (leader) return; const s = parse(raw(STATE)); status(!!s.ok && Date.now() - (s.at || 0) < 15000); };
    setInterval(tick, 2000); setTimeout(tick, 400);
  }
  if (navigator.locks && navigator.locks.request) {
    navigator.locks.request('vincent-media-sync', () => { leader = true; lead(); return new Promise(() => {}); });
    setTimeout(() => { if (!leader) follow(); }, 600);
  } else { leader = true; lead(); }
  window.VMSync = { onStatus(f) { listeners.push(f); if (ok !== null) f(ok); }, get ok() { return ok; }, client: CLIENT };
})();
