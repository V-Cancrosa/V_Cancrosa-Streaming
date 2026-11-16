/*
  Serwis Vincent-Media: wspólny szkielet stron w site/ – menu, stan połączeń, ustawienia, podgląd widoku 1920×1080.
  Ustawienia zapisują się w tej przeglądarce i przez wykrywacz (themes/sync.js) trafiają do OBS.
*/
(function () {
  const KEY = 'obsGameOverlay.v1';
  // menu w grupach (['-', nazwa] = nagłówek grupy)
  const NAV = [
    ['live.html', '●', 'Na żywo'],
    ['index.html', '⌂', 'Start'],
    ['-', 'Show'],
    ['games.html', '🎮', 'Gry i programy'],
    ['look.html', '🦊', 'Postać i wygląd'],
    ['voice.html', '🔊', 'Głos postaci'],
    ['screens.html', '⏱', 'Ekrany'],
    ['-', 'Studio'],
    ['obs.html', '🎬', 'OBS'],
    ['bot.html', '🤖', 'Bot czatu'],
    ['layouts.html', '✥', 'Ułożenie scen'],
    ['creator.html', '✦', 'Kreator stron'],
    ['-', 'Więcej'],
    ['settings.html', '⚙', 'Wszystkie ustawienia'],
    ['pilot.html', '🎛', 'Pilot (telefon)'],
    ['log.html', '📜', 'Dziennik'],
  ];
  const here = location.pathname.split('/').pop() || 'index.html';
  const $ = id => document.getElementById(id);
  const esc = t => String(t ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  let bc = null; try { bc = new BroadcastChannel('obsGameOverlay'); } catch (e) {}

  // --- ustawienia ---
  const get = () => { try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { return {}; } };
  function set(patch) { const s = { ...get(), ...patch }; try { localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) {} if (bc) bc.postMessage('update'); return s; }
  const hub = () => (window.vmHub ? window.vmHub(get().localUrl) : 'http://localhost:7777');
  const onChange = f => { if (bc) bc.addEventListener('message', e => { if (e.data === 'update') f(); }); window.addEventListener('vm-sync', f); window.addEventListener('storage', e => { if (e.key === KEY) f(); }); };

  // --- menu i stan ---
  function shell() {
    const nav = document.querySelector('.nav'); if (!nav) return;
    nav.innerHTML = `<div class="brand">Vincent-Media<small>stream · ${esc(window.VM_VERSION || '')}</small></div>` +
      NAV.map(([href, ic, name]) => href === '-' ? `<div class="sep">${ic}</div>` : `<a href="${href}"${href === here ? ' aria-current="page"' : ''}><i>${ic}</i>${name}</a>`).join('') +
      `<div class="stat"><span><i class="dot" id="stDet"></i>GameRadar <b id="stDetT">…</b></span><span><i class="dot" id="stSync"></i>Połączenie z OBS <b id="stSyncT">…</b></span></div>
      <a class="nora" href="nora://start" title="Uruchamia aplikację Nora na tym komputerze (włącz w Norze: «Uruchamianie ze strony»)">▶ Nora</a>
      <button class="kill" id="killBtn" title="Kończy transmisję i nagrywanie (jeśli trwają), zamyka OBS i GameRadar">⏻ Zamknij OBS i GameRadar</button>`;
    document.getElementById('killBtn').onclick = annihilate;
  }
  async function ping() {
    let ok = false;
    try { const r = await fetch(hub() + '/game', { cache: 'no-store' }); ok = r.ok; if (r.status === 403) { $('stDetT').textContent = 'nie ufa tej stronie'; $('stDet').className = 'dot bad'; setTimeout(ping, 8000); return; } } catch (e) {}
    if ($('stDet')) { $('stDet').className = 'dot ' + (ok ? 'ok' : 'bad'); $('stDetT').textContent = ok ? 'działa' : 'nie odpowiada'; }
    setTimeout(ping, ok ? 8000 : 4000);
  }
  function syncStatus() {
    if (!window.VMSync) return;
    window.VMSync.onStatus(v => { if (!$('stSync')) return; $('stSync').className = 'dot ' + (v ? 'ok' : 'bad'); $('stSyncT').textContent = v ? 'zmiany idą do OBS' : 'brak (wykrywacz?)'; });
  }

  // --- „zamykamy budę”: transmisja i nagrywanie stop (przez OBS WebSocket), potem GameRadar zamyka OBS i siebie ---
  const loadScript = src => new Promise(ok => { if (window.OverlayOBS) return ok(); const sc = document.createElement('script'); sc.src = src; sc.onload = ok; sc.onerror = ok; document.head.appendChild(sc); });
  async function annihilate() {
    if (!confirm('Zamknąć OBS i GameRadar?')) return;
    const b = document.getElementById('killBtn'); b.disabled = true; b.textContent = 'Zamykam…';
    try {
      await loadScript('../themes/obsws.js');
      if (window.OverlayOBS) {
        const cfg = await window.OverlayOBS.config(get());
        const obs = window.OverlayOBS.connect({ ...cfg, onStatus: () => {} });
        await new Promise(r => setTimeout(r, 1500));
        let st = {}, rec = {}; try { st = await obs.call('GetStreamStatus'); rec = await obs.call('GetRecordStatus'); } catch (e) {}
        if (st.outputActive || rec.outputActive) {
          if (!confirm((st.outputActive ? 'Transmisja trwa' : 'Nagrywanie trwa') + '. Zakończyć ' + (st.outputActive && rec.outputActive ? 'transmisję i nagrywanie' : st.outputActive ? 'transmisję' : 'nagrywanie') + ' i zamknąć wszystko?')) { b.disabled = false; b.textContent = '⏻ Zamknij OBS i GameRadar'; try { obs.close(); } catch (e) {} return; }
          try { if (st.outputActive) await obs.call('StopStream'); if (rec.outputActive) await obs.call('StopRecord'); } catch (e) {}
          await new Promise(r => setTimeout(r, 3000));      // OBS domyka plik nagrania
        }
        try { obs.close(); } catch (e) {}
      }
      const r = await fetch(hub() + '/shutdown', { cache: 'no-store' });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      b.textContent = '✓ Zamknięte – do zobaczenia!'; toast('OBS i GameRadar zamykają się. Wrócą, gdy sam je uruchomisz.');
    } catch (e) { b.disabled = false; b.textContent = '⏻ Zamknij OBS i GameRadar'; toast('GameRadar nie odpowiada – zamknij OBS ręcznie.'); }
  }

  // --- podgląd widoku 1920×1080 ---
  // numer wersji w adresie podglądu: po aktualizacji przeglądarka nie pokaże starej kopii z pamięci
  const withV = u => u + (u.includes('?') ? '&' : '?') + 'v=' + encodeURIComponent(window.VM_VERSION || '');
  // views: [{ id, name, urls: ['../stage.html', …], obs: '../stage.html', hint }]
  function preview(box, views, pick) {
    let cur = views.find(v => v.id === pick) || views[0];
    box.classList.add('preview');
    box.innerHTML = `<div class="pv" id="pvBox"></div>
      <div class="pvbar">${views.length > 1 ? `<span class="seg" id="pvSeg">${views.map(v => `<button data-v="${esc(v.id)}">${esc(v.name)}</button>`).join('')}</span>` : ''}
        <span style="flex:1"></span><button id="pvOpen" title="Otwórz widok w pełnym rozmiarze">⤢ 1920×1080</button><button id="pvCopy" title="Adres do źródła przeglądarki w OBS">⧉ Adres do OBS</button></div>
      <p class="hint" id="pvHint" style="margin-top:6px"></p>`;
    const fit = () => { const w = $('pvBox').clientWidth; for (const f of $('pvBox').querySelectorAll('iframe')) f.style.transform = `scale(${w / 1920})`; };
    function show(v) {
      cur = v;
      // widoki z grą są przezroczyste tam, gdzie OBS podkłada grę – w podglądzie podkładamy „obraz gry”;
      // bez wybranej/wykrytej gry karta „Teraz gram” dostaje przykładową nazwę (tylko w podglądzie)
      const g = get(), noGame = !(g.mode === 'manual' && g.game) && !((JSON.parse(localStorage.getItem('obsGameOverlay.detected') || 'null') || {}).local || {}).game;
      $('pvBox').classList.toggle('game', !!v.game);
      $('pvBox').innerHTML = v.urls.map(u => `<iframe src="${esc(withV(noGame && /overlay\.html$/.test(u) ? u + '?game=' + encodeURIComponent('Twoja gra') : u))}" title="${esc(v.name)}" tabindex="-1"></iframe>`).join('');
      if ($('pvSeg')) for (const b of $('pvSeg').children) b.setAttribute('aria-pressed', b.dataset.v === v.id);
      $('pvHint').innerHTML = v.hint || '';
      fit();
    }
    if ($('pvSeg')) $('pvSeg').onclick = e => { const b = e.target.closest('[data-v]'); if (b) show(views.find(v => v.id === b.dataset.v)); };
    $('pvOpen').onclick = () => window.open(new URL(cur.obs || cur.urls[0], location.href).href, '_blank', 'width=1280,height=760');
    $('pvCopy').onclick = async () => { const u = new URL(cur.obs || cur.urls[0], location.href).href; try { await navigator.clipboard.writeText(u); toast('Skopiowano: ' + u.split('/').pop()); } catch (e) { prompt('Adres do OBS (źródło przeglądarki 1920×1080):', u); } };
    if (window.ResizeObserver) new ResizeObserver(fit).observe($('pvBox')); else addEventListener('resize', fit);
    show(cur);
    return { show: id => show(views.find(v => v.id === id) || cur) };
  }
  function toast(msg) {
    let t = document.querySelector('.toast'); if (!t) { t = document.createElement('div'); t.className = 'toast'; document.body.appendChild(t); }
    t.textContent = msg; t.classList.add('on'); clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.remove('on'), 1800);
  }

  window.VMSite = { get, set, hub, onChange, preview, toast, esc, $, withV };
  document.addEventListener('DOMContentLoaded', () => { shell(); ping(); syncStatus(); });
})();
