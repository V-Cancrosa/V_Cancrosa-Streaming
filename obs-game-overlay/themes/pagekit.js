/*
  Strony z Kreatora (builder.html) – wspólny silnik Kreatora, odtwarzacza (page.html) i pilota (page.html?pilot=1).
  Wzorowane na Bubble.io: elementy wizualne, kontenery, pola formularza + Workflow („Kiedy… → Zrób…”) + Dane (stany).

  Strona: { id, name, w, h (≤ 1920×1080), bg, els: [el], wf: [workflow] }
  Element: { id, type, name, x, y, w, h, p: {…}, visible (widoczny na start), anim, pilotOnly }
  Workflow: { id, on: { type: click|alert|command|every|stage, el, alert, cmd, secs, scene }, do: [ { type: show|hide|toggle|set|add|pulse|page, el, secs, key, value, page } ] }
  Wspólny stan (wszystkie kopie strony – OBS, podgląd, pilot – widzą to samo):
    localStorage 'obsGameOverlay.pages'     – strony
    localStorage 'obsGameOverlay.pageState' – stany (Dane), np. { smierci: 3, user: "Ala" } → w napisach {smierci}, {user}
    localStorage 'obsGameOverlay.pageVis'   – widoczność i pulsowanie elementów { elId: { on, until, pulse } }
*/
(function () {
  const KEY = 'obsGameOverlay.pages', STATE = 'obsGameOverlay.pageState', VIS = 'obsGameOverlay.pageVis', DONE = 'obsGameOverlay.wfDone';
  const MAXW = 1920, MAXH = 1080;
  const read = (k, fb) => { try { return JSON.parse(localStorage.getItem(k)) ?? fb; } catch (e) { return fb; } };
  const write = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} };
  const uid = () => Math.random().toString(36).slice(2, 9);
  const arr = v => Array.isArray(v) ? v : v && Array.isArray(v.value) ? v.value : v && typeof v === 'object' ? [v] : [];
  let bc = null; try { bc = new BroadcastChannel('obsGameOverlay'); } catch (e) {}
  const ping = what => { if (bc) bc.postMessage({ type: 'pages', what }); };

  // ---------------------------------------------------------------- strony
  function list() { const l = read(KEY, []); return Array.isArray(l) ? l.map(migrate) : []; }
  function get(id) { return list().find(p => p.id === id) || null; }
  function saveAll(l) { write(KEY, l); ping('pages'); return true; }
  function put(page) {
    const l = list(), i = l.findIndex(p => p.id === page.id);
    page.w = Math.min(MAXW, Math.max(50, Math.round(page.w))); page.h = Math.min(MAXH, Math.max(50, Math.round(page.h)));
    if (i < 0) l.push(page); else l[i] = page; return saveAll(l);
  }
  function remove(id) { saveAll(list().filter(p => p.id !== id)); }
  // strony z pierwszej wersji Kreatora: „Kiedy widać” → Workflow
  function migrate(p) {
    if (!p || p.v === 2) return p;
    p.v = 2; p.wf = p.wf || [];
    for (const el of p.els || []) {
      if (el.type === 'box') el.type = 'shape';
      const w = el.show; delete el.show;
      if (!w || w.when === 'always') { el.visible = true; continue; }
      el.visible = false;
      if (w.when === 'alert') p.wf.push({ id: uid(), on: { type: 'alert', alert: w.alert || 'any' }, do: [{ type: 'set', key: 'user', value: '{user}' }, { type: 'show', el: el.id, secs: w.secs || 8 }] });
      if (w.when === 'command') p.wf.push({ id: uid(), on: { type: 'command', cmd: w.cmd || '!hej' }, do: [{ type: 'set', key: 'user', value: '{user}' }, { type: 'show', el: el.id, secs: w.secs || 8 }] });
      if (w.when === 'scene') p.wf.push({ id: uid(), on: { type: 'stage', scene: w.scene || 'brb' }, do: [{ type: 'show', el: el.id, secs: 0 }] });
      if (w.when === 'flag') { el.visible = false; }
    }
    return p;
  }

  // ---------------------------------------------------------------- elementy (jak paleta Bubble)
  // pole: [klucz, etykieta, rodzaj, opcje]; rodzaje: text, area, num, color, sel, bool, state
  const FONTS = [['persona', 'jak postać'], ['Inter', 'Inter'], ['Space Grotesk', 'Space Grotesk'], ['Anton', 'Anton'], ['Fraunces', 'Fraunces'], ['Nunito', 'Nunito'], ['Space Mono', 'Space Mono'], ['IBM Plex Mono', 'IBM Plex Mono'], ['Orbitron', 'Orbitron'], ['Rajdhani', 'Rajdhani'], ['Caveat', 'Caveat'], ['Tiny5', 'Tiny5 (piksele)']];
  const FILL = ['fill', 'Wypełnienie', 'sel', [['panel', 'ciemny panel'], ['accent', 'kolor postaci'], ['grad', 'gradient postaci'], ['none', 'brak'], ['custom', 'własny kolor ↓']]];
  const BOXF = [FILL, ['custom', 'Własny kolor', 'color'], ['radius', 'Zaokrąglenie', 'num'], ['border', 'Ramka (px)', 'num'], ['borderColor', 'Kolor ramki', 'color'], ['opacity', 'Krycie %', 'num'], ['glass', 'Rozmycie tła (szkło)', 'bool']];
  const BOXP = { fill: 'panel', radius: 18, border: 2, borderColor: 'accent', opacity: 100, glass: true };
  const TXTF = [['font', 'Czcionka', 'sel', FONTS], ['size', 'Wielkość', 'num'], ['weight', 'Grubość', 'sel', [[400, 'zwykła'], [600, 'średnia'], [800, 'gruba'], [900, 'najgrubsza']]], ['color', 'Kolor', 'color'], ['align', 'Wyrównanie', 'sel', [['left', 'do lewej'], ['center', 'środek'], ['right', 'do prawej']]]];
  const CATS = [['vis', 'Elementy wizualne'], ['box', 'Kontenery'], ['form', 'Pola formularza'], ['stream', 'Stream']];
  const TYPES = {
    // wizualne
    text: { cat: 'vis', name: 'Tekst', icon: 'T', size: [700, 110], p: { text: 'Nowy tekst', font: 'persona', size: 56, weight: 800, color: '#ffffff', align: 'left', shadow: true, upper: false },
      f: [['text', 'Treść', 'area'], ...TXTF, ['shadow', 'Poświata', 'bool'], ['upper', 'WIELKIE LITERY', 'bool']] },
    button: { cat: 'vis', name: 'Przycisk', icon: '⏺', size: [300, 80], p: { label: 'Kliknij', style: 'accent', size: 26, radius: 14, font: 'persona' },
      f: [['label', 'Napis', 'text'], ['style', 'Styl', 'sel', [['accent', 'pełny (kolor postaci)'], ['outline', 'obrys'], ['dark', 'ciemny']]], ['size', 'Wielkość tekstu', 'num'], ['radius', 'Zaokrąglenie', 'num'], ['font', 'Czcionka', 'sel', FONTS]] },
    icon: { cat: 'vis', name: 'Ikona', icon: '★', size: [120, 120], p: { glyph: '🦊', color: '#ffffff' },
      f: [['glyph', 'Ikona (emoji albo znak)', 'text'], ['color', 'Kolor (dla znaków)', 'color']] },
    image: { cat: 'vis', name: 'Obrazek', icon: '🖼', size: [400, 400], p: { src: '', fit: 'contain', radius: 0 },
      f: [['src', 'Adres obrazka (https://… albo file:///…)', 'text'], ['fit', 'Dopasowanie', 'sel', [['contain', 'cały'], ['cover', 'wypełnij']]], ['radius', 'Zaokrąglenie', 'num']] },
    shape: { cat: 'vis', name: 'Kształt', icon: '▭', size: [500, 260], p: { ...BOXP }, f: BOXF },
    video: { cat: 'vis', name: 'Wideo', icon: '▶', size: [640, 360], p: { src: '', fit: 'cover', loop: true, muted: true, radius: 12 },
      f: [['src', 'Adres wideo (mp4/webm)', 'text'], ['fit', 'Dopasowanie', 'sel', [['cover', 'wypełnij'], ['contain', 'całe']]], ['loop', 'W pętli', 'bool'], ['muted', 'Bez dźwięku', 'bool'], ['radius', 'Zaokrąglenie', 'num']] },
    html: { cat: 'vis', name: 'HTML', icon: '</>', size: [500, 300], p: { code: '<div style="font:700 40px sans-serif;color:#fff">Własny HTML</div>' },
      f: [['code', 'Kod HTML (z CSS i JS)', 'area']] },
    // kontenery
    group: { cat: 'box', name: 'Grupa', icon: '▣', size: [700, 400], p: { ...BOXP, fill: 'none', border: 0, glass: false },
      f: BOXF, hint: 'Elementy położone na grupie należą do niej: przesuwają się razem z nią i znikają razem z nią.' },
    repeat: { cat: 'box', name: 'Grupa powtarzalna', icon: '☰', size: [500, 360], p: { source: 'follow', rows: 5, dir: 'v', cell: '{user}', size: 30, color: '#ffffff', font: 'persona', cellBg: true, gap: 10 },
      f: [['source', 'Dane', 'sel', [['follow', 'ostatnie followy'], ['sub', 'ostatnie suby'], ['gift', 'prezenty subów'], ['cheer', 'bitsy'], ['raid', 'raidy'], ['chatters', 'osoby na czacie'], ['chat', 'ostatnie wiadomości czatu']]],
        ['cell', 'Komórka – tekst ({user}, {n}, {text})', 'text'], ['rows', 'Ile pozycji', 'num'], ['dir', 'Układ', 'sel', [['v', 'kolumna'], ['h', 'wiersz']]], ['gap', 'Odstęp', 'num'], ['size', 'Wielkość tekstu', 'num'], ['color', 'Kolor', 'color'], ['font', 'Czcionka', 'sel', FONTS], ['cellBg', 'Tło komórek', 'bool']] },
    popup: { cat: 'box', name: 'Popup', icon: '◳', size: [800, 300], visible: false, p: { ...BOXP, dim: true },
      f: [...BOXF, ['dim', 'Przyciemnij resztę strony', 'bool']], hint: 'Popup jest ukryty na start – pokaż go w Workflow (np. przy alercie).' },
    // formularze (działają w pilocie i w przeglądarce; na streamie widać tylko wygląd)
    input: { cat: 'form', name: 'Pole tekstowe', icon: '⌨', size: [500, 70], p: { placeholder: 'Wpisz…', key: 'tekst', size: 24 },
      f: [['placeholder', 'Podpowiedź', 'text'], ['key', 'Zapisuje do stanu', 'state'], ['size', 'Wielkość tekstu', 'num']] },
    checkbox: { cat: 'form', name: 'Checkbox', icon: '☑', size: [360, 60], p: { label: 'Włączone', key: 'wlaczone', size: 24 },
      f: [['label', 'Napis', 'text'], ['key', 'Zapisuje do stanu', 'state'], ['size', 'Wielkość tekstu', 'num']] },
    dropdown: { cat: 'form', name: 'Lista wyboru', icon: '▾', size: [420, 70], p: { options: 'Tak, Nie, Może', key: 'wybor', size: 24 },
      f: [['options', 'Opcje (po przecinku)', 'text'], ['key', 'Zapisuje do stanu', 'state'], ['size', 'Wielkość tekstu', 'num']] },
    // stream
    persona: { cat: 'stream', name: 'Postać', icon: '🦊', size: [500, 600], p: { flip: false, glow: true }, f: [['flip', 'Odbij w poziomie', 'bool'], ['glow', 'Poświata', 'bool']] },
    game: { cat: 'stream', name: 'Gra', icon: '🎮', size: [460, 215], p: { kind: 'header', radius: 12 },
      f: [['kind', 'Rodzaj', 'sel', [['header', 'okładka pozioma'], ['logo', 'logo'], ['icon', 'ikona programu']]], ['radius', 'Zaokrąglenie', 'num']] },
    countdown: { cat: 'stream', name: 'Odliczanie', icon: '⏱', size: [420, 140], p: { size: 110, color: 'accent', font: 'persona', zero: 'Zaraz!' },
      f: [['size', 'Wielkość', 'num'], ['color', 'Kolor', 'color'], ['font', 'Czcionka', 'sel', FONTS], ['zero', 'Napis po zerze', 'text']], hint: 'Liczy do czasu ustawionego w Sterowanie → Ekrany.' },
    clock: { cat: 'stream', name: 'Zegar', icon: '🕒', size: [300, 100], p: { size: 64, color: '#ffffff', secs: false }, f: [['size', 'Wielkość', 'num'], ['color', 'Kolor', 'color'], ['secs', 'Sekundy', 'bool']] },
    socials: { cat: 'stream', name: 'Linki', icon: '🔗', size: [900, 60], p: { size: 22, cols: 6 }, f: [['size', 'Wielkość', 'num'], ['cols', 'Kolumn', 'num']] },
    chat: { cat: 'stream', name: 'Czat', icon: '💬', size: [420, 640], p: { size: 18 }, f: [['size', 'Wielkość tekstu', 'num']] },
    alerts: { cat: 'stream', name: 'Miejsce na alerty', icon: '🔔', size: [900, 260], p: {}, f: [], hint: 'Tu pojawi się karta alertu, gdy ta strona jest na wizji.' },
  };
  const ANIMS = [['fade', 'wyłania się'], ['pop', 'od skali 0,95'], ['slide-l', 'wjeżdża z lewej'], ['slide-r', 'wjeżdża z prawej'], ['slide-u', 'wjeżdża z dołu'], ['none', 'bez animacji']];
  // Workflow
  const EVENTS = [['click', 'Kliknięto element'], ['alert', 'Przyszedł alert'], ['command', 'Ktoś napisał komendę na czacie'], ['every', 'Co jakiś czas'], ['stage', 'Zmienił się ekran (etap)']];
  const ACTIONS = [['show', 'Pokaż element'], ['hide', 'Ukryj element'], ['toggle', 'Przełącz element'], ['pulse', 'Mrugnij elementem'], ['set', 'Ustaw stan'], ['add', 'Dodaj do stanu (licznik)'], ['page', 'Pokaż stronę na streamie']];
  const ALERT_T = [['any', 'każdy'], ['follow', 'follow'], ['sub', 'sub / resub / gift'], ['cheer', 'bitsy'], ['raid', 'raid'], ['redeem', 'punkty kanału']];
  const STAGES = [['prep', 'przygotowania'], ['soon', 'stream za…'], ['start', 'zaraz zaczynamy'], ['late', 'spóźnienie'], ['vote', 'głosowanie'], ['brb', 'przerwa'], ['brb-late', 'przerwa się przedłuża'], ['end', 'koniec']];

  function newEl(type, page, at) {
    const T = TYPES[type], [w0, h0] = T.size, w = Math.min(w0, page.w), h = Math.min(h0, page.h);
    const x = at ? at[0] - w / 2 : (page.w - w) / 2, y = at ? at[1] - h / 2 : (page.h - h) / 2;
    return { id: uid(), type, name: T.name, x: Math.round(Math.max(0, Math.min(page.w - w, x))), y: Math.round(Math.max(0, Math.min(page.h - h, y))), w, h,
      p: JSON.parse(JSON.stringify(T.p)), visible: T.visible !== false, anim: type === 'popup' ? 'pop' : 'fade', pilotOnly: false };
  }
  function newPage(name, w = 1920, h = 1080) { return { v: 2, id: uid(), name: name || 'Nowa strona', w, h, bg: 'none', els: [], wf: [] }; }
  const put2 = (p, el, o) => { Object.assign(el, o); p.els.push(el); return el; };

  // ---------------------------------------------------------------- szablony („Co robimy?”)
  const TEMPLATES = [
    ['welcome', 'Ekran „zaraz zaczynamy”', 'Postać, napis, odliczanie i linki – na cały ekran.', () => {
      const p = newPage('Zaraz zaczynamy'); p.bg = 'theme';
      put2(p, newEl('persona', p), { x: 1180, y: 160, w: 640, h: 860 });
      const t = put2(p, newEl('text', p), { x: 120, y: 300, w: 1000, h: 110 }); t.p.text = 'Zaraz zaczynamy'; t.p.size = 96;
      const s = put2(p, newEl('text', p), { x: 120, y: 420, w: 1000, h: 60 }); Object.assign(s.p, { text: 'Prowadzi {postac} · dziś: {gra}', size: 36, weight: 600, color: 'accent', shadow: false });
      put2(p, newEl('countdown', p), { x: 120, y: 520, w: 520, h: 150 });
      put2(p, newEl('socials', p), { x: 120, y: 960, w: 1000, h: 60 });
      return p; }],
    ['deaths', 'Licznik śmierci', 'Widz pisze !smierc → licznik +1 i mruga, !reset zeruje. Pod spodem przyciski widoczne tylko w pilocie.', () => {
      const p = newPage('Licznik śmierci', 600, 270);
      put2(p, newEl('shape', p), { x: 0, y: 0, w: 600, h: 180 });
      put2(p, newEl('icon', p), { x: 24, y: 30, w: 120, h: 120 }).p.glyph = '💀';
      const t = put2(p, newEl('text', p), { x: 160, y: 35, w: 420, h: 110, name: 'Licznik' }); Object.assign(t.p, { text: 'Śmierci: {smierci}', size: 54 });
      const b1 = put2(p, newEl('button', p), { x: 0, y: 200, w: 290, h: 64, pilotOnly: true, name: 'Przycisk +1' }); b1.p.label = '＋1 śmierć';
      const b2 = put2(p, newEl('button', p), { x: 310, y: 200, w: 290, h: 64, pilotOnly: true, name: 'Przycisk zeruj' }); Object.assign(b2.p, { label: 'Zeruj', style: 'outline' });
      p.wf.push({ id: uid(), on: { type: 'command', cmd: '!smierc' }, do: [{ type: 'add', key: 'smierci', value: 1 }, { type: 'pulse', el: t.id }] });
      p.wf.push({ id: uid(), on: { type: 'click', el: b1.id }, do: [{ type: 'add', key: 'smierci', value: 1 }, { type: 'pulse', el: t.id }] });
      p.wf.push({ id: uid(), on: { type: 'command', cmd: '!reset' }, do: [{ type: 'set', key: 'smierci', value: '0' }] });
      p.wf.push({ id: uid(), on: { type: 'click', el: b2.id }, do: [{ type: 'set', key: 'smierci', value: '0' }] });
      setState({ smierci: getState().smierci ?? 0 });
      return p; }],
    ['thanks', 'Podziękowanie za follow', 'Popup z nickiem wyskakuje przy followie na 8 sekund.', () => {
      const p = newPage('Podziękowanie za follow', 900, 260);
      const pop = put2(p, newEl('popup', p), { x: 0, y: 0, w: 900, h: 260, name: 'Popup follow' }); pop.p.dim = false;
      const t = put2(p, newEl('text', p), { x: 40, y: 50, w: 820, h: 90 }); Object.assign(t.p, { text: 'Dzięki za follow, {user}!', size: 56, align: 'center' }); t.anim = 'slide-u';
      const s = put2(p, newEl('text', p), { x: 40, y: 150, w: 820, h: 60 }); Object.assign(s.p, { text: '{postac} macha łapą', size: 30, weight: 600, color: 'accent', shadow: false, align: 'center' });
      p.wf.push({ id: uid(), on: { type: 'alert', alert: 'follow' }, do: [{ type: 'set', key: 'user', value: '{user}' }, { type: 'show', el: pop.id, secs: 8 }] });
      return p; }],
    ['recent', 'Ostatni followerzy', 'Lista ostatnich followów z tej transmisji (Grupa powtarzalna).', () => {
      const p = newPage('Ostatni followerzy', 520, 460);
      put2(p, newEl('shape', p), { x: 0, y: 0, w: 520, h: 460 });
      const t = put2(p, newEl('text', p), { x: 30, y: 20, w: 460, h: 60 }); Object.assign(t.p, { text: 'Nowi w watasze', size: 34, color: 'accent' });
      put2(p, newEl('repeat', p), { x: 30, y: 100, w: 460, h: 330 });
      return p; }],
    ['bar', 'Pasek z linkami i zegarem', 'Wąski pasek na dół albo górę ekranu.', () => {
      const p = newPage('Pasek z linkami', 1920, 120);
      const b = put2(p, newEl('shape', p), { x: 0, y: 0, w: 1920, h: 120 }); b.p.radius = 0; b.p.border = 0;
      put2(p, newEl('socials', p), { x: 40, y: 30, w: 1500, h: 60 });
      put2(p, newEl('clock', p), { x: 1600, y: 10, w: 280, h: 100 }).p.size = 54;
      return p; }],
    ['pilot', 'Pilot (przyciski do sterowania)', 'Strona z przyciskami do klikania w panelu: Twórz → 🎛 Pilot.', () => {
      const p = newPage('Pilot', 900, 500); p.bg = 'dark';
      const t = put2(p, newEl('text', p), { x: 40, y: 30, w: 820, h: 70 }); Object.assign(t.p, { text: 'Pilot · {godzina}', size: 44 });
      const b1 = put2(p, newEl('button', p), { x: 40, y: 140, w: 400, h: 90 }); b1.p.label = 'Na stream: Zaraz zaczynamy';
      const b2 = put2(p, newEl('button', p), { x: 460, y: 140, w: 400, h: 90 }); Object.assign(b2.p, { label: '＋1 śmierć', style: 'outline' });
      const i = put2(p, newEl('input', p), { x: 40, y: 280, w: 820, h: 80 }); Object.assign(i.p, { placeholder: 'Temat streama…', key: 'temat' });
      put2(p, newEl('text', p), { x: 40, y: 390, w: 820, h: 70 }).p.text = 'Temat: {temat}';
      p.wf.push({ id: uid(), on: { type: 'click', el: b2.id }, do: [{ type: 'add', key: 'smierci', value: 1 }] });
      p.wf.push({ id: uid(), on: { type: 'click', el: b1.id }, do: [{ type: 'page', page: '' }] });
      return p; }],
    ['blank', 'Pusta strona', 'Zaczynasz od zera.', () => newPage('Pusta strona')],
  ];

  // ---------------------------------------------------------------- stany i widoczność (wspólne dla wszystkich kopii)
  const getState = () => read(STATE, {}) || {};
  function setState(o) { write(STATE, { ...getState(), ...o }); ping('state'); }
  const getVis = () => read(VIS, {}) || {};
  function setVis(id, v) { const all = getVis(); all[id] = { ...(all[id] || {}), ...v }; write(VIS, all); ping('vis'); }
  // czy element jest widoczny: stan z Workflow, a bez niego – „widoczny na start”
  function isOn(el, vis) {
    const v = (vis || getVis())[el.id];
    if (v && v.until && v.until < Date.now()) return el.visible !== false;   // „na N sekund” minęło → wraca do stanu ze startu
    return v && typeof v.on === 'boolean' ? v.on : el.visible !== false;
  }
  // ten sam workflow nie może zadziałać kilka razy (OBS, podgląd i pilot dostają to samo zdarzenie)
  function once(key) {
    const d = read(DONE, {}) || {}, now = Date.now();
    if (d[key]) return false;
    for (const k of Object.keys(d)) if (now - d[k] > 300000) delete d[k];
    d[key] = now; write(DONE, d); return true;
  }
  // wykonanie akcji (ev = dane zdarzenia: user, n, text)
  function run(page, wf, ev) {
    for (const a of wf.do || []) {
      const el = a.el && page.els.find(e => e.id === a.el);
      if (a.type === 'show' && el) setVis(el.id, { on: true, until: a.secs ? Date.now() + a.secs * 1000 : 0 });
      if (a.type === 'hide' && el) setVis(el.id, { on: false, until: a.secs ? Date.now() + a.secs * 1000 : 0 });
      if (a.type === 'toggle' && el) setVis(el.id, { on: !isOn(el), until: 0 });
      if (a.type === 'pulse' && el) setVis(el.id, { pulse: Date.now() });
      if (a.type === 'set' && a.key) setState({ [a.key]: fill(a.value, { ...ctxLite(), ...(ev || {}) }) });
      if (a.type === 'add' && a.key) { const cur = parseFloat(getState()[a.key]) || 0; setState({ [a.key]: cur + (parseFloat(a.value) || 0) }); }
      if (a.type === 'page') {
        try { const k = 'obsGameOverlay.v1', s = read(k, {}); s.stage = 'page'; s.pageId = a.page || page.id; write(k, s); if (bc) bc.postMessage('update'); } catch (e) {}
      }
    }
  }

  // ---------------------------------------------------------------- dane do znaczników
  const FONT = { vince: "'Space Mono', monospace", chip: "'Nunito', sans-serif", ragnar: "'Anton', 'Inter', sans-serif", toro: "'Fraunces', serif", myr: "'IBM Plex Mono', monospace", zarin: "'Space Grotesk', sans-serif" };
  const ART = { vince: 'themes/fursona/vince.webp', chip: 'themes/fursona/chip.webp', ragnar: 'themes/fursona/ragnar-full.webp', toro: 'themes/fursona/toro-full.webp' };
  let session = {}, chatLog = [];
  const TOKENS = [['gra', 'gra'], ['postac', 'postać'], ['godzina', 'godzina'], ['data', 'data'], ['odliczanie', 'odliczanie'], ['follow', 'ostatni follow'], ['sub', 'ostatni sub'], ['raid', 'ostatni raid'], ['user', 'nick z alertu/komendy (stan)']];
  function ctxLite() { const now = new Date(); return { godzina: now.toLocaleTimeString('pl-PL', { hour: '2-digit', minute: '2-digit' }), data: now.toLocaleDateString('pl-PL', { day: 'numeric', month: 'long' }) }; }
  function ctx() {
    const C = window.VMClient, s = C ? C.settings() : {}, th = C ? C.applyTheme(document.body.dataset.base || '') : null;
    const det = read('obsGameOverlay.detected', {}) || {};
    const g = (s.mode === 'manual' && s.game) || (det.local && det.local.game && det.local.game.name) || s.game || '';
    let pd = th && (th.persona || (th.def && th.def.group === 'fursona' ? th.def : null));
    if (!pd && String(s.theme || '').startsWith('g-') && window.OverlayGameThemes && window.OverlayGameThemes.byId) pd = window.OverlayGameThemes.byId(s.theme) || null;
    const last = k => { const a = arr(session[k]); return a.length ? a[a.length - 1].user : '—'; };
    const until = +s.sceneUntil || 0, left = Math.max(0, until - Date.now()), mm = Math.floor(left / 60000), ss = Math.floor(left / 1000) % 60;
    return { ...getState(), ...ctxLite(), s, th, persona: pd ? pd.id : (th ? th.id : ''), postac: pd ? pd.name : '', gra: g, steam: s.gameSteam || '', gameId: s.gameId || '',
      odliczanie: until ? (left ? `${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}` : '') : '', left, until,
      follow: last('follow'), sub: last('sub'), raid: last('raid') };
  }
  const fill = (t, c) => String(t ?? '').replace(/\{([\wąćęłńóśźż]+)\}/gi, (m, k) => (k in c && c[k] !== undefined && typeof c[k] !== 'object' ? c[k] : m));
  const col = v => v === 'accent' ? 'var(--accent)' : v === 'accent2' ? 'var(--accent2)' : (v || '#fff');
  const font = (f, c) => f === 'persona' || !f ? (FONT[c.persona] || "'Inter', sans-serif") : `'${f}', sans-serif`;
  const boxBg = p => p.fill === 'accent' ? 'var(--accent)' : p.fill === 'grad' ? 'linear-gradient(135deg, var(--accent), var(--g1, var(--accent2)))' : p.fill === 'none' ? 'transparent' : p.fill === 'custom' ? (p.custom || '#222') : 'linear-gradient(135deg, rgba(10,10,16,.86), rgba(20,16,30,.78))';
  function boxStyle(st, p) {
    Object.assign(st, { background: boxBg(p), borderRadius: (p.radius || 0) + 'px', border: p.border ? `${p.border}px solid ${col(p.borderColor)}` : 'none', opacity: (p.opacity ?? 100) / 100,
      backdropFilter: p.glass ? 'blur(14px)' : 'none', boxShadow: p.border ? '0 0 22px color-mix(in srgb, var(--accent) 35%, transparent)' : 'none' });
  }
  const mk = (tag, css, txt) => { const e = document.createElement(tag); if (css) Object.assign(e.style, css); if (txt != null) e.textContent = txt; return e; };

  // ---------------------------------------------------------------- rysowanie elementu (mode: 'edit' | 'live' | 'pilot')
  function drawEl(d, el, c, mode) {
    const p = el.p || {}, st = d.style, live = mode !== 'edit';
    d.className = 'vmp-el vmp-' + el.type; d.dataset.id = el.id;
    Object.assign(st, { left: el.x + 'px', top: el.y + 'px', width: el.w + 'px', height: el.h + 'px' });
    const dyn = ['text', 'button', 'countdown', 'clock', 'persona', 'game', 'repeat', 'input', 'checkbox', 'dropdown'].includes(el.type);
    const key = JSON.stringify([el.type, p, el.w, el.h, mode, dyn ? [c.persona, c.gra, c.godzina, c.odliczanie, c.follow, c.sub, c.postac, c.steam, getState(), el.type === 'repeat' ? [session[p.source], chatLog.length] : 0] : 0]);
    if (d.dataset.k === key) return; d.dataset.k = key;
    if (el.type === 'chat' && d.dataset.mounted) return;
    if ((el.type === 'input' || el.type === 'dropdown') && mode === 'pilot' && d.contains(document.activeElement)) return;
    d.textContent = ''; d.removeAttribute('style'); Object.assign(st, { left: el.x + 'px', top: el.y + 'px', width: el.w + 'px', height: el.h + 'px' });
    const T = el.type;
    if (T === 'text') {
      Object.assign(st, { font: `${p.weight || 800} ${p.size || 48}px/1.1 ${font(p.font, c)}`, color: col(p.color), textAlign: p.align || 'left', textTransform: p.upper ? 'uppercase' : 'none',
        textShadow: p.shadow ? '0 0 24px color-mix(in srgb, var(--accent) 55%, transparent), 0 2px 6px rgba(0,0,0,.6)' : 'none', overflowWrap: 'anywhere', whiteSpace: 'pre-wrap', display: 'flex', alignItems: 'center', justifyContent: p.align === 'center' ? 'center' : p.align === 'right' ? 'flex-end' : 'flex-start' });
      d.appendChild(mk('span', null, fill(p.text, c)));
    } else if (T === 'button') {
      const b = mk('button', { width: '100%', height: '100%', borderRadius: (p.radius || 0) + 'px', font: `700 ${p.size || 24}px/1.1 ${font(p.font, c)}`, cursor: mode === 'pilot' ? 'pointer' : 'default',
        background: p.style === 'accent' ? 'var(--accent)' : p.style === 'dark' ? '#16171d' : 'transparent', color: '#fff', border: p.style === 'outline' ? '3px solid var(--accent)' : '0',
        boxShadow: p.style === 'accent' ? '0 6px 20px color-mix(in srgb, var(--accent) 45%, transparent)' : 'none' }, fill(p.label, c));
      b.className = 'vmp-btn'; b.tabIndex = mode === 'pilot' ? 0 : -1; d.appendChild(b);
    } else if (T === 'icon') {
      Object.assign(st, { display: 'grid', placeItems: 'center', fontSize: Math.round(Math.min(el.w, el.h) * .8) + 'px', lineHeight: 1, color: col(p.color) }); d.textContent = p.glyph || '★';
    } else if (T === 'shape' || T === 'group' || T === 'popup') {
      boxStyle(st, p);
      if (T === 'group' && mode === 'edit' && p.fill === 'none' && !p.border) st.outline = '2px dashed rgba(255,255,255,.18)';
    } else if (T === 'image') {
      if (p.src) d.appendChild(Object.assign(mk('img', { width: '100%', height: '100%', objectFit: p.fit || 'contain', borderRadius: (p.radius || 0) + 'px' }), { src: p.src, alt: '' }));
      else if (!live) d.innerHTML = '<div class="vmp-ph">wpisz adres obrazka</div>';
    } else if (T === 'video') {
      if (p.src) { const v = Object.assign(mk('video', { width: '100%', height: '100%', objectFit: p.fit || 'cover', borderRadius: (p.radius || 0) + 'px' }), { src: p.src, autoplay: true, loop: !!p.loop, muted: p.muted !== false, playsInline: true }); v.muted = p.muted !== false; d.appendChild(v); }
      else if (!live) d.innerHTML = '<div class="vmp-ph">wpisz adres wideo</div>';
    } else if (T === 'html') {
      const f = Object.assign(mk('iframe', { width: '100%', height: '100%', border: '0', background: 'transparent', pointerEvents: mode === 'pilot' ? 'auto' : 'none' }), { srcdoc: '<style>html,body{margin:0;background:transparent;overflow:hidden}</style>' + (p.code || '') });
      f.setAttribute('sandbox', 'allow-scripts'); d.appendChild(f);
    } else if (T === 'repeat') {
      const data = p.source === 'chat' ? chatLog.slice(-(p.rows || 5)) : arr(session[p.source]).slice(-(p.rows || 5)).reverse();
      const rows = data.length ? data : (live ? [] : [{ user: 'Wilczek_88', n: 1 }, { user: 'Lisica', n: 3 }, { user: 'ToroFan', n: 1 }]);
      Object.assign(st, { display: 'flex', flexDirection: p.dir === 'h' ? 'row' : 'column', gap: (p.gap ?? 10) + 'px', overflow: 'hidden', font: `700 ${p.size || 28}px/1.2 ${font(p.font, c)}`, color: col(p.color) });
      for (const r of rows) d.appendChild(mk('div', { padding: p.cellBg ? '8px 14px' : '0', borderRadius: '10px', background: p.cellBg ? 'rgba(255,255,255,.07)' : 'none', borderLeft: p.cellBg ? '4px solid var(--accent)' : '0', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 'none', animation: live ? 'vmp-fade 250ms cubic-bezier(.22,1,.36,1) both' : 'none' }, fill(p.cell || '{user}', { ...c, user: r.user, n: r.n, text: r.text || '' })));
    } else if (T === 'input') {
      const i = Object.assign(mk('input', { width: '100%', height: '100%', boxSizing: 'border-box', padding: '0 16px', borderRadius: '12px', border: '2px solid color-mix(in srgb, var(--accent) 60%, transparent)', background: 'rgba(10,10,16,.85)', color: '#fff', font: `500 ${p.size || 24}px Inter, sans-serif` }),
        { placeholder: p.placeholder || '', value: getState()[p.key] ?? '', readOnly: mode !== 'pilot' });
      i.className = 'vmp-in'; d.appendChild(i);
    } else if (T === 'checkbox') {
      const l = mk('label', { display: 'flex', alignItems: 'center', gap: '14px', height: '100%', font: `600 ${p.size || 24}px Inter, sans-serif`, color: '#fff', cursor: mode === 'pilot' ? 'pointer' : 'default' });
      const i = Object.assign(mk('input', { width: (p.size || 24) * 1.2 + 'px', height: (p.size || 24) * 1.2 + 'px', accentColor: 'var(--accent)' }), { type: 'checkbox', checked: !!getState()[p.key], disabled: mode !== 'pilot' });
      i.className = 'vmp-in'; l.append(i, mk('span', null, fill(p.label, c))); d.appendChild(l);
    } else if (T === 'dropdown') {
      const sel = mk('select', { width: '100%', height: '100%', padding: '0 14px', borderRadius: '12px', border: '2px solid color-mix(in srgb, var(--accent) 60%, transparent)', background: 'rgba(10,10,16,.85)', color: '#fff', font: `500 ${p.size || 24}px Inter, sans-serif` });
      for (const o of String(p.options || '').split(',').map(x => x.trim()).filter(Boolean)) sel.appendChild(Object.assign(mk('option', null, o), { value: o }));
      sel.value = getState()[p.key] ?? sel.value; sel.disabled = mode !== 'pilot'; sel.className = 'vmp-in'; d.appendChild(sel);
    } else if (T === 'persona') {
      const src = ART[c.persona];
      if (src) d.appendChild(Object.assign(mk('img', { width: '100%', height: '100%', objectFit: 'contain', objectPosition: '50% 100%', transform: p.flip ? 'scaleX(-1)' : 'none', filter: p.glow ? 'drop-shadow(0 0 28px color-mix(in srgb, var(--accent) 55%, transparent))' : 'none' }), { src, alt: '' }));
      else if (c.th && c.th.def && c.th.def.emblem) { d.innerHTML = c.th.def.emblem; const svg = d.querySelector('svg'); if (svg) { svg.removeAttribute('class'); Object.assign(svg.style, { width: '100%', height: '100%' }); } }
    } else if (T === 'game') {
      const hub = window.vmHub ? window.vmHub(c.s.localUrl) : 'http://localhost:7777';
      const src = p.kind === 'icon' ? (c.gameId ? hub + '/icon?id=' + encodeURIComponent(c.gameId) : '') : c.steam ? hub + '/art?id=' + encodeURIComponent(c.steam) + '&k=' + (p.kind === 'logo' ? 'logo' : 'header') : '';
      const txt = () => { d.textContent = c.gra || (live ? '' : 'okładka gry'); Object.assign(st, { display: 'grid', placeItems: 'center', font: `800 40px/1.1 ${font('persona', c)}`, textAlign: 'center' }); };
      if (src) { const i = Object.assign(mk('img', { width: '100%', height: '100%', objectFit: 'contain', borderRadius: (p.radius || 0) + 'px' }), { src, alt: c.gra }); i.onerror = txt; d.appendChild(i); } else txt();
    } else if (T === 'countdown') {
      Object.assign(st, { font: `800 ${p.size || 100}px/1 ${font(p.font, c)}`, color: col(p.color), display: 'flex', alignItems: 'center', fontVariantNumeric: 'tabular-nums', textShadow: '0 0 30px color-mix(in srgb, var(--accent) 50%, transparent)' });
      d.textContent = c.odliczanie || (c.until ? p.zero || '' : (live ? '' : '05:00'));
    } else if (T === 'clock') {
      Object.assign(st, { font: `700 ${p.size || 60}px/1 ${font('persona', c)}`, color: col(p.color), display: 'flex', alignItems: 'center', fontVariantNumeric: 'tabular-nums' });
      d.textContent = p.secs ? new Date().toLocaleTimeString('pl-PL') : c.godzina;
    } else if (T === 'socials') {
      Object.assign(st, { fontSize: (p.size || 22) + 'px', display: 'grid', gridTemplateColumns: `repeat(${p.cols || 6}, auto)`, gap: '8px 28px', alignContent: 'center', justifyContent: 'start', color: '#fff' });
      if (window.VMSocials) window.VMSocials.render(d, c.s.socials);
    } else if (T === 'chat') {
      st.fontSize = (p.size || 18) + 'px';
      if (live && window.OverlayChat) { d.dataset.mounted = '1'; d.chat = window.OverlayChat.mount(d, { mode: 'panel', life: 14 }); }
      else d.innerHTML = '<div class="vmp-ph">czat</div>';
    } else if (T === 'alerts') {
      if (!live) d.innerHTML = '<div class="vmp-ph">tu pokażą się alerty</div>';
    }
  }
  function drawBg(root, page) {
    root.style.width = page.w + 'px'; root.style.height = page.h + 'px';
    root.style.background = page.bg === 'theme' ? 'radial-gradient(circle at 20% 20%, color-mix(in srgb, var(--accent) 35%, transparent), transparent 55%), radial-gradient(circle at 85% 90%, color-mix(in srgb, var(--g1, var(--accent2)) 30%, transparent), transparent 55%), #0b0b10'
      : page.bg === 'dark' ? '#0b0b10' : page.bg && page.bg[0] === '#' ? page.bg : 'transparent';
  }
  // grupa/popup zawiera element, gdy ten leży w całości na niej i jest wyżej w warstwach
  function parentsOf(page, el) {
    const i = page.els.indexOf(el);
    return page.els.filter((g, j) => j < i && (g.type === 'group' || g.type === 'popup') && el.x >= g.x && el.y >= g.y && el.x + el.w <= g.x + g.w && el.y + el.h <= g.y + g.h);
  }
  function childrenOf(page, g) { return page.els.filter(e => e !== g && parentsOf(page, e).includes(g)); }

  const CSS = `
  .vmp-root { position: relative; overflow: hidden; }
  .vmp-el { position: absolute; box-sizing: border-box; }
  .vmp-el.hid { visibility: hidden; }
  .vmp-dim { position: absolute; inset: 0; background: rgba(0,0,0,.55); pointer-events: none; }
  .vmp-ph { position: absolute; inset: 0; display: grid; place-items: center; border: 2px dashed rgba(255,255,255,.35); border-radius: 10px; color: rgba(255,255,255,.6); font: 600 22px/1.2 Inter, sans-serif; text-align: center; }
  .vmp-socials a, .vmp-socials span { color: inherit; text-decoration: none; }
  .vmp-btn { transition: transform 120ms cubic-bezier(.22,1,.36,1); } .vmp-btn:active { transform: scale(.97); }
  @keyframes vmp-fade { from { opacity: 0; transform: translateY(8px); } }
  @keyframes vmp-pop { from { opacity: 0; transform: scale(.95); } }
  @keyframes vmp-slide-l { from { opacity: 0; transform: translateX(-60px); } }
  @keyframes vmp-slide-r { from { opacity: 0; transform: translateX(60px); } }
  @keyframes vmp-slide-u { from { opacity: 0; transform: translateY(50px); } }
  @keyframes vmp-out { to { opacity: 0; transform: translateY(-8px); } }
  @keyframes vmp-pulse { 50% { transform: scale(1.08); filter: brightness(1.3); } }
  .vmp-in-fade { animation: vmp-fade 250ms cubic-bezier(.22,1,.36,1) both; } .vmp-in-pop { animation: vmp-pop 250ms cubic-bezier(.22,1,.36,1) both; }
  .vmp-in-slide-l { animation: vmp-slide-l 300ms cubic-bezier(.22,1,.36,1) both; } .vmp-in-slide-r { animation: vmp-slide-r 300ms cubic-bezier(.22,1,.36,1) both; }
  .vmp-in-slide-u { animation: vmp-slide-u 300ms cubic-bezier(.22,1,.36,1) both; }
  .vmp-out { animation: vmp-out 200ms cubic-bezier(.55,0,1,.45) both; }
  .vmp-pulse { animation: vmp-pulse 400ms ease-in-out 2; }`;
  function injectCss() { if (document.getElementById('vmp-css')) return; const st = document.createElement('style'); st.id = 'vmp-css'; st.textContent = CSS; document.head.appendChild(st); }

  window.VMPages = { KEY, STATE, VIS, MAXW, MAXH, CATS, TYPES, ANIMS, EVENTS, ACTIONS, ALERT_T, STAGES, TEMPLATES, TOKENS,
    list, get, put, remove, saveAll, migrate, newEl, newPage, uid, ctx, fill, drawEl, drawBg, injectCss, parentsOf, childrenOf,
    getState, setState, getVis, setVis, isOn, once, run, arr,
    setSession(v) { session = v || {}; }, pushChat(ev) { chatLog.push({ user: ev.user || '', text: ev.text || '' }); if (chatLog.length > 40) chatLog.shift(); } };
})();
