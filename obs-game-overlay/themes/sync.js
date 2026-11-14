/*
  Synchronizacja przez wykrywacz: strona na GitHub Pages w zwykłej przeglądarce ↔ OBS (inna przeglądarka, inna pamięć).
    • ustawienia ('obsGameOverlay.v1')   – kanał /settings (ten sam co panel w OBS i pilot z telefonu),
    • strony z Kreatora, stany, widoczność – kanał /kv.
  Zmiana lokalna → wysyłka; zmiana z innego miejsca → zapis do localStorage + powiadomienie stron w tej przeglądarce.
  Wczytują go: strony serwisu (site/*.html) i główne widoki w OBS (stage.html, page.html), więc OBS dostaje zmiany
  nawet wtedy, gdy dok z panelem jest zamknięty.
*/
(function () {
  // tylko strona główna karty – ramki w środku (podglądy, stage.html w OBS) korzystają z tej samej pamięci przeglądarki
  if (window.VMSync || window.top !== window) return;
  const SET = 'obsGameOverlay.v1', KV = ['obsGameOverlay.pages', 'obsGameOverlay.pageState', 'obsGameOverlay.pageVis'];
  const CLIENT = Math.random().toString(36).slice(2);
  const raw = k => { try { return localStorage.getItem(k); } catch (e) { return null; } };
  const hub = () => { let s = {}; try { s = JSON.parse(raw(SET)) || {}; } catch (e) {} return window.vmHub ? window.vmHub(s.localUrl) : 'http://localhost:7777'; };
  let bc = null; try { bc = new BroadcastChannel('obsGameOverlay'); } catch (e) {}
  const known = {};               // ostatnia wartość uzgodniona z wykrywaczem (tekst)
  let setRev = null, kvRev = 0, ok = null, lastErr = 0;
  const listeners = [];
  const status = v => { if (ok !== v) { ok = v; listeners.forEach(f => { try { f(v); } catch (e) {} }); } };

  function apply(key, val) {
    known[key] = val;
    try { if (raw(key) !== val) localStorage.setItem(key, val); } catch (e) { return; }
    if (bc) bc.postMessage(key === SET ? 'update' : { type: 'pages', what: 'sync' });
    try { window.dispatchEvent(new CustomEvent('vm-sync', { detail: key })); } catch (e) {}
  }
  async function push(key, val) {
    try {
      if (key === SET) {
        let settings = null; try { settings = JSON.parse(val); } catch (e) { return; }
        const j = await (await fetch(hub() + '/settings', { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify({ client: CLIENT, settings }) })).json();
        if (j.ok) { setRev = j.rev; known[key] = val; }
      } else {
        const j = await (await fetch(hub() + '/kv', { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify({ client: CLIENT, key, val }) })).json();
        if (j.ok) known[key] = val;
      }
      status(true);
    } catch (e) { status(false); }
  }
  async function pull() {
    try {
      const j = await (await fetch(hub() + '/settings', { cache: 'no-store' })).json();
      if (j && j.settings && j.rev !== setRev && j.from !== CLIENT) { setRev = j.rev; apply(SET, JSON.stringify(j.settings)); }
      else if (j) setRev = j.rev;
      if (j && !j.settings && raw(SET)) push(SET, raw(SET));            // wykrywacz jeszcze nic nie ma – daj mu nasze
      const k = await (await fetch(hub() + '/kv?since=' + kvRev, { cache: 'no-store' })).json();
      if (k && k.items) {
        for (const [key, e] of Object.entries(k.items)) if (e.from !== CLIENT && typeof e.val === 'string') apply(key, e.val);
        // pierwsze połączenie: czego wykrywacz nie ma, wysyłamy
        if (!kvRev) for (const key of KV) if (!k.items[key] && raw(key)) push(key, raw(key));
        kvRev = k.rev;
      }
      status(true);
    } catch (e) { status(false); }
    setTimeout(pull, ok === false ? 6000 : 2000);
  }
  // lokalne zmiany (z tej strony albo z innych kart tej przeglądarki)
  function scan() {
    for (const key of [SET, ...KV]) {
      const v = raw(key);
      if (v == null) continue;
      if (known[key] === undefined) { known[key] = v; continue; }
      if (v !== known[key]) { known[key] = v; push(key, v); }
    }
  }
  setInterval(scan, 700);
  setTimeout(() => { scan(); pull(); }, 300);
  window.VMSync = { onStatus(f) { listeners.push(f); if (ok !== null) f(ok); }, get ok() { return ok; }, client: CLIENT };
})();
