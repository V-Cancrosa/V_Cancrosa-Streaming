/*
  Strony z kreatora (builder.html) – wspólny silnik dla kreatora i odtwarzacza (page.html).
  Strona: { id, name, w, h (≤ 1920×1080), bg, els: [ { id, type, x, y, w, h, p: {…właściwości}, show: {…kiedy widać}, anim } ] }
  Zapis: localStorage 'obsGameOverlay.pages' (lista stron) + BroadcastChannel {type:'pages'}.
  Teksty mogą mieć znaczniki: {gra} {postac} {godzina} {data} {odliczanie} {follow} {sub} {raid} {user} {n}
*/
(function () {
  const KEY = 'obsGameOverlay.pages', MAXW = 1920, MAXH = 1080;
  const read = (k, fb) => { try { return JSON.parse(localStorage.getItem(k)) ?? fb; } catch (e) { return fb; } };
  const uid = () => Math.random().toString(36).slice(2, 9);
  let bc = null; try { bc = new BroadcastChannel('obsGameOverlay'); } catch (e) {}

  function list() { const l = read(KEY, []); return Array.isArray(l) ? l : []; }
  function get(id) { return list().find(p => p.id === id) || null; }
  function saveAll(l) { try { localStorage.setItem(KEY, JSON.stringify(l)); } catch (e) { return false; } if (bc) bc.postMessage({ type: 'pages' }); return true; }
  function put(page) { const l = list(), i = l.findIndex(p => p.id === page.id); page.w = Math.min(MAXW, Math.max(50, Math.round(page.w))); page.h = Math.min(MAXH, Math.max(50, Math.round(page.h))); if (i < 0) l.push(page); else l[i] = page; return saveAll(l); }
  function remove(id) { saveAll(list().filter(p => p.id !== id)); }

  // --- elementy: domyślne właściwości i pola w panelu właściwości ---
  // pole: [klucz, etykieta, rodzaj, opcje]; rodzaje: text, area, num, color, sel, bool
  const COLOR = ['color', 'Kolor'];
  const TYPES = {
    text: { name: 'Napis', icon: 'T', size: [700, 120], p: { text: 'Witaj na streamie {postac}!', font: 'persona', size: 64, weight: 800, color: '#ffffff', align: 'left', shadow: true, upper: false },
      f: [['text', 'Treść (znaczniki: {gra} {postac} {godzina} {odliczanie} {follow}…)', 'area'], ['font', 'Czcionka', 'sel', [['persona', 'jak postać'], ['Inter', 'Inter'], ['Space Grotesk', 'Space Grotesk'], ['Anton', 'Anton'], ['Fraunces', 'Fraunces'], ['Nunito', 'Nunito'], ['Space Mono', 'Space Mono'], ['IBM Plex Mono', 'IBM Plex Mono'], ['Orbitron', 'Orbitron'], ['Rajdhani', 'Rajdhani'], ['Caveat', 'Caveat'], ['Tiny5', 'Tiny5 (piksele)']]],
        ['size', 'Wielkość', 'num'], ['weight', 'Grubość', 'sel', [[400, 'zwykła'], [600, 'średnia'], [800, 'gruba'], [900, 'najgrubsza']]], ['color', ...COLOR.slice(1), 'color'], ['align', 'Wyrównanie', 'sel', [['left', 'do lewej'], ['center', 'środek'], ['right', 'do prawej']]], ['shadow', 'Poświata', 'bool'], ['upper', 'WIELKIE LITERY', 'bool']] },
    box: { name: 'Kształt', icon: '▭', size: [600, 300], p: { fill: 'panel', radius: 18, border: 2, borderColor: 'accent', opacity: 100, glass: true },
      f: [['fill', 'Wypełnienie', 'sel', [['panel', 'ciemny panel'], ['accent', 'kolor postaci'], ['grad', 'gradient postaci'], ['none', 'brak'], ['custom', 'własny kolor ↓']]], ['custom', 'Własny kolor', 'color'], ['radius', 'Zaokrąglenie', 'num'], ['border', 'Ramka (px)', 'num'], ['borderColor', 'Kolor ramki', 'color'], ['opacity', 'Krycie %', 'num'], ['glass', 'Rozmycie tła (szkło)', 'bool']] },
    image: { name: 'Obrazek', icon: '🖼', size: [400, 400], p: { src: '', fit: 'contain', radius: 0 },
      f: [['src', 'Adres obrazka (https://… albo file:///…)', 'text'], ['fit', 'Dopasowanie', 'sel', [['contain', 'cały'], ['cover', 'wypełnij']]], ['radius', 'Zaokrąglenie', 'num']] },
    persona: { name: 'Postać', icon: '🦊', size: [500, 600], p: { flip: false, glow: true },
      f: [['flip', 'Odbij w poziomie', 'bool'], ['glow', 'Poświata', 'bool']] },
    game: { name: 'Gra (okładka)', icon: '🎮', size: [460, 215], p: { kind: 'header', radius: 12 },
      f: [['kind', 'Rodzaj', 'sel', [['header', 'okładka pozioma'], ['logo', 'logo'], ['icon', 'ikona programu']]], ['radius', 'Zaokrąglenie', 'num']] },
    countdown: { name: 'Odliczanie', icon: '⏱', size: [420, 140], p: { size: 110, color: 'accent', font: 'persona', zero: 'Zaraz!' },
      f: [['size', 'Wielkość', 'num'], ['color', 'Kolor', 'color'], ['font', 'Czcionka', 'sel', [['persona', 'jak postać'], ['Orbitron', 'Orbitron'], ['Space Mono', 'Space Mono'], ['Anton', 'Anton']]], ['zero', 'Napis po zerze', 'text']] },
    clock: { name: 'Zegar', icon: '🕒', size: [300, 100], p: { size: 64, color: '#ffffff', secs: false },
      f: [['size', 'Wielkość', 'num'], ['color', 'Kolor', 'color'], ['secs', 'Sekundy', 'bool']] },
    socials: { name: 'Linki', icon: '🔗', size: [900, 60], p: { size: 22, cols: 6 },
      f: [['size', 'Wielkość', 'num'], ['cols', 'Kolumn', 'num']] },
    chat: { name: 'Czat', icon: '💬', size: [420, 640], p: { size: 18 },
      f: [['size', 'Wielkość tekstu', 'num']] },
    alerts: { name: 'Miejsce na alerty', icon: '🔔', size: [900, 260], p: {},
      f: [] },
  };
  const ANIMS = [['fade', 'wyłania się (ease-out)'], ['pop', 'od skali 0,95'], ['slide-l', 'wjeżdża z lewej'], ['slide-r', 'wjeżdża z prawej'], ['slide-u', 'wjeżdża z dołu'], ['none', 'bez animacji']];
  const SHOW = [['always', 'zawsze'], ['flag', 'gdy włączę w panelu'], ['alert', 'przy alercie'], ['command', 'na komendę z czatu'], ['scene', 'na ekranie (etap)']];

  function newEl(type, page) {
    const T = TYPES[type], [w, h] = T.size;
    return { id: uid(), type, name: T.name, x: Math.round((page.w - Math.min(w, page.w)) / 2), y: Math.round((page.h - Math.min(h, page.h)) / 2), w: Math.min(w, page.w), h: Math.min(h, page.h),
      p: JSON.parse(JSON.stringify(T.p)), show: { when: 'always', alert: 'follow', cmd: '!hej', secs: 8, scene: 'brb' }, anim: 'fade' };
  }
  function newPage(name, w = 1920, h = 1080) { return { id: uid(), name: name || 'Nowa strona', w, h, bg: 'none', els: [] }; }

  // szablony na start
  const TEMPLATES = {
    blank: () => newPage('Pusta strona'),
    welcome: () => { const p = newPage('Ekran powitalny'); p.bg = 'theme';
      const per = newEl('persona', p); Object.assign(per, { x: 1180, y: 160, w: 640, h: 860 });
      const t = newEl('text', p); Object.assign(t, { x: 120, y: 300, w: 1000, h: 110 }); t.p.text = 'Zaraz zaczynamy'; t.p.size = 96;
      const s = newEl('text', p); Object.assign(s, { x: 120, y: 420, w: 1000, h: 60 }); s.p.text = 'Prowadzi {postac} · dziś: {gra}'; s.p.size = 36; s.p.weight = 600; s.p.color = 'accent'; s.p.shadow = false;
      const c = newEl('countdown', p); Object.assign(c, { x: 120, y: 520, w: 520, h: 150 });
      const l = newEl('socials', p); Object.assign(l, { x: 120, y: 960, w: 1000, h: 60 });
      p.els.push(per, t, s, c, l); return p; },
    bar: () => { const p = newPage('Pasek z linkami', 1920, 120);
      const b = newEl('box', p); Object.assign(b, { x: 0, y: 0, w: 1920, h: 120 }); b.p.radius = 0; b.p.border = 0;
      const l = newEl('socials', p); Object.assign(l, { x: 40, y: 30, w: 1500, h: 60 });
      const k = newEl('clock', p); Object.assign(k, { x: 1600, y: 10, w: 280, h: 100 }); k.p.size = 54;
      p.els.push(b, l, k); return p; },
    follow: () => { const p = newPage('Podziękowanie za follow', 900, 260);
      const b = newEl('box', p); Object.assign(b, { x: 0, y: 0, w: 900, h: 260 }); b.show.when = 'alert'; b.anim = 'pop';
      const t = newEl('text', p); Object.assign(t, { x: 40, y: 50, w: 820, h: 90 }); t.p.text = 'Dzięki za follow, {user}!'; t.p.size = 56; t.show.when = 'alert'; t.anim = 'slide-u';
      const s = newEl('text', p); Object.assign(s, { x: 40, y: 150, w: 820, h: 60 }); s.p.text = '{postac} macha łapą'; s.p.size = 30; s.p.weight = 600; s.p.color = 'accent'; s.show.when = 'alert'; s.anim = 'fade';
      p.els.push(b, t, s); return p; },
  };

  // --- dane do znaczników ---
  const FONT = { vince: "'Space Mono', monospace", chip: "'Nunito', sans-serif", ragnar: "'Anton', 'Inter', sans-serif", toro: "'Fraunces', serif", myr: "'IBM Plex Mono', monospace", zarin: "'Space Grotesk', sans-serif" };
  const ART = { vince: 'themes/fursona/vince.webp', chip: 'themes/fursona/chip.webp', ragnar: 'themes/fursona/ragnar-full.webp', toro: 'themes/fursona/toro-full.webp' };
  let session = {};
  function ctx(extra) {
    const C = window.VMClient, s = C ? C.settings() : {}, th = C ? C.applyTheme(document.body.dataset.base || '') : null;
    const det = read('obsGameOverlay.detected', {}) || {};
    const g = (s.mode === 'manual' && s.game) || (det.local && det.local.game && det.local.game.name) || s.game || '';
    let pd = th && (th.persona || (th.def && th.def.group === 'fursona' ? th.def : null));
    // nakładka jeszcze nie ogłosiła motywu (np. kreator bez OBS) – postać z ustawień panelu
    if (!pd && String(s.theme || '').startsWith('g-') && window.OverlayGameThemes && window.OverlayGameThemes.byId) pd = window.OverlayGameThemes.byId(s.theme) || null;
    const last = k => { const a = session[k]; return a && a.length ? a[a.length - 1].user : '—'; };
    const now = new Date(), until = +s.sceneUntil || 0, left = Math.max(0, until - Date.now());
    const mm = Math.floor(left / 60000), ss = Math.floor(left / 1000) % 60;
    return Object.assign({ s, th, persona: pd ? pd.id : (th ? th.id : ''), postac: pd ? pd.name : '', gra: g, steam: s.gameSteam || '', gameId: s.gameId || '',
      godzina: now.toLocaleTimeString('pl-PL', { hour: '2-digit', minute: '2-digit' }), data: now.toLocaleDateString('pl-PL', { day: 'numeric', month: 'long' }),
      odliczanie: until ? (left ? `${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}` : '') : '', left, until,
      follow: last('follow'), sub: last('sub'), raid: last('raid'), user: '', n: '' }, extra || {});
  }
  const fill = (t, c) => String(t || '').replace(/\{(\w+)\}/g, (m, k) => (k in c && c[k] !== undefined ? c[k] : m));
  const col = v => v === 'accent' ? 'var(--accent)' : v === 'accent2' ? 'var(--accent2)' : v === 'g1' ? 'var(--g1, var(--accent2))' : (v || '#fff');
  const font = (f, c) => f === 'persona' || !f ? (FONT[c.persona] || "'Inter', sans-serif") : `'${f}', sans-serif`;

  // --- rysowanie jednego elementu (div o rozmiarze elementu) ---
  function drawEl(d, el, c, live) {
    const p = el.p || {}, st = d.style;
    d.className = 'vmp-el vmp-' + el.type;
    Object.assign(st, { left: el.x + 'px', top: el.y + 'px', width: el.w + 'px', height: el.h + 'px' });
    const key = JSON.stringify([el.type, p, el.w, el.h, el.type === 'text' || el.type === 'countdown' || el.type === 'clock' || el.type === 'persona' || el.type === 'game' ? [c.persona, c.gra, c.godzina, c.odliczanie, c.follow, c.sub, c.user, c.postac, c.steam] : 0]);
    if (d.dataset.k === key) return; d.dataset.k = key;
    if (el.type === 'chat' && d.dataset.mounted) return;
    d.textContent = '';
    if (el.type === 'text') {
      Object.assign(st, { font: `${p.weight || 800} ${p.size || 48}px/1.1 ${font(p.font, c)}`, color: col(p.color), textAlign: p.align || 'left', textTransform: p.upper ? 'uppercase' : 'none',
        textShadow: p.shadow ? '0 0 24px color-mix(in srgb, var(--accent) 55%, transparent), 0 2px 6px rgba(0,0,0,.6)' : 'none', overflowWrap: 'anywhere', whiteSpace: 'pre-wrap', display: 'flex', alignItems: 'center', justifyContent: p.align === 'center' ? 'center' : p.align === 'right' ? 'flex-end' : 'flex-start' });
      const span = document.createElement('span'); span.textContent = fill(p.text, c); d.appendChild(span);
    } else if (el.type === 'box') {
      const bg = p.fill === 'accent' ? 'var(--accent)' : p.fill === 'grad' ? 'linear-gradient(135deg, var(--accent), var(--g1, var(--accent2)))' : p.fill === 'none' ? 'transparent' : p.fill === 'custom' ? (p.custom || '#222') : 'linear-gradient(135deg, rgba(10,10,16,.86), rgba(20,16,30,.78))';
      Object.assign(st, { background: bg, borderRadius: (p.radius || 0) + 'px', border: p.border ? `${p.border}px solid ${col(p.borderColor)}` : 'none', opacity: (p.opacity ?? 100) / 100,
        backdropFilter: p.glass ? 'blur(14px)' : 'none', boxShadow: p.border ? '0 0 22px color-mix(in srgb, var(--accent) 35%, transparent)' : 'none' });
    } else if (el.type === 'image') {
      if (p.src) { const i = new Image(); i.src = p.src; i.alt = ''; Object.assign(i.style, { width: '100%', height: '100%', objectFit: p.fit || 'contain', borderRadius: (p.radius || 0) + 'px' }); d.appendChild(i); }
      else if (!live) d.innerHTML = '<div class="vmp-ph">wpisz adres obrazka</div>';
    } else if (el.type === 'persona') {
      const src = ART[c.persona];
      if (src) { const i = new Image(); i.src = src; i.alt = ''; Object.assign(i.style, { width: '100%', height: '100%', objectFit: 'contain', objectPosition: '50% 100%', transform: p.flip ? 'scaleX(-1)' : 'none', filter: p.glow ? 'drop-shadow(0 0 28px color-mix(in srgb, var(--accent) 55%, transparent))' : 'none' }); d.appendChild(i); }
      else if (c.th && c.th.def && c.th.def.emblem) { d.innerHTML = c.th.def.emblem; const svg = d.querySelector('svg'); if (svg) { svg.removeAttribute('class'); Object.assign(svg.style, { width: '100%', height: '100%' }); } }
    } else if (el.type === 'game') {
      const hub = window.vmHub ? window.vmHub(c.s.localUrl) : 'http://localhost:7777';
      const src = p.kind === 'icon' ? (c.gameId ? hub + '/icon?id=' + encodeURIComponent(c.gameId) : '') : c.steam ? hub + '/art?id=' + encodeURIComponent(c.steam) + '&k=' + (p.kind === 'logo' ? 'logo' : 'header') : '';
      if (src) { const i = new Image(); i.src = src; i.alt = c.gra; i.onerror = () => { d.innerHTML = ''; d.appendChild(Object.assign(document.createElement('b'), { textContent: c.gra })); }; Object.assign(i.style, { width: '100%', height: '100%', objectFit: 'contain', borderRadius: (p.radius || 0) + 'px' }); d.appendChild(i); }
      else { Object.assign(st, { display: 'grid', placeItems: 'center', font: `800 40px/1.1 ${font('persona', c)}`, textAlign: 'center' }); d.textContent = c.gra || (live ? '' : 'okładka gry'); }
    } else if (el.type === 'countdown') {
      Object.assign(st, { font: `800 ${p.size || 100}px/1 ${font(p.font, c)}`, color: col(p.color), display: 'flex', alignItems: 'center', fontVariantNumeric: 'tabular-nums', textShadow: '0 0 30px color-mix(in srgb, var(--accent) 50%, transparent)' });
      d.textContent = c.odliczanie || (c.until ? p.zero || '' : (live ? '' : '05:00'));
    } else if (el.type === 'clock') {
      Object.assign(st, { font: `700 ${p.size || 60}px/1 ${font('persona', c)}`, color: col(p.color), display: 'flex', alignItems: 'center', fontVariantNumeric: 'tabular-nums' });
      d.textContent = p.secs ? new Date().toLocaleTimeString('pl-PL') : c.godzina;
    } else if (el.type === 'socials') {
      Object.assign(st, { fontSize: (p.size || 22) + 'px', display: 'grid', gridTemplateColumns: `repeat(${p.cols || 6}, auto)`, gap: '8px 28px', alignContent: 'center', justifyContent: 'start', color: '#fff' });
      if (window.VMSocials) window.VMSocials.render(d, c.s.socials);
    } else if (el.type === 'chat') {
      st.fontSize = (p.size || 18) + 'px';
      if (live && window.OverlayChat) { d.dataset.mounted = '1'; d.chat = window.OverlayChat.mount(d, { mode: 'panel', life: 14 }); }
      else d.innerHTML = '<div class="vmp-ph">czat</div>';
    } else if (el.type === 'alerts') {
      if (!live) d.innerHTML = '<div class="vmp-ph">tu pokażą się alerty</div>';
    }
  }

  // tło strony
  function drawBg(root, page) {
    root.style.width = page.w + 'px'; root.style.height = page.h + 'px';
    root.style.background = page.bg === 'theme' ? 'radial-gradient(circle at 20% 20%, color-mix(in srgb, var(--accent) 35%, transparent), transparent 55%), radial-gradient(circle at 85% 90%, color-mix(in srgb, var(--g1, var(--accent2)) 30%, transparent), transparent 55%), #0b0b10'
      : page.bg === 'dark' ? '#0b0b10' : page.bg && page.bg[0] === '#' ? page.bg : 'transparent';
  }

  const CSS = `
  .vmp-root { position: relative; overflow: hidden; }
  .vmp-el { position: absolute; box-sizing: border-box; }
  .vmp-el.hid { visibility: hidden; }
  .vmp-ph { position: absolute; inset: 0; display: grid; place-items: center; border: 2px dashed rgba(255,255,255,.35); border-radius: 10px; color: rgba(255,255,255,.6); font: 600 22px/1.2 Inter, sans-serif; text-align: center; }
  .vmp-socials a, .vmp-socials span { color: inherit; text-decoration: none; }
  @keyframes vmp-fade { from { opacity: 0; transform: translateY(8px); } }
  @keyframes vmp-pop { from { opacity: 0; transform: scale(.95); } }
  @keyframes vmp-slide-l { from { opacity: 0; transform: translateX(-60px); } }
  @keyframes vmp-slide-r { from { opacity: 0; transform: translateX(60px); } }
  @keyframes vmp-slide-u { from { opacity: 0; transform: translateY(50px); } }
  @keyframes vmp-out { to { opacity: 0; transform: translateY(-8px); } }
  .vmp-in-fade { animation: vmp-fade 250ms cubic-bezier(.22,1,.36,1) both; } .vmp-in-pop { animation: vmp-pop 250ms cubic-bezier(.22,1,.36,1) both; }
  .vmp-in-slide-l { animation: vmp-slide-l 300ms cubic-bezier(.22,1,.36,1) both; } .vmp-in-slide-r { animation: vmp-slide-r 300ms cubic-bezier(.22,1,.36,1) both; }
  .vmp-in-slide-u { animation: vmp-slide-u 300ms cubic-bezier(.22,1,.36,1) both; }
  .vmp-out { animation: vmp-out 200ms cubic-bezier(.55,0,1,.45) both; }`;
  function injectCss() { if (document.getElementById('vmp-css')) return; const st = document.createElement('style'); st.id = 'vmp-css'; st.textContent = CSS; document.head.appendChild(st); }

  window.VMPages = { KEY, MAXW, MAXH, TYPES, ANIMS, SHOW, TEMPLATES, list, get, put, remove, saveAll, newEl, newPage, uid, ctx, fill, drawEl, drawBg, injectCss,
    setSession(v) { session = v || {}; } };
})();
