/*
  Własne ułożenie elementów scen (edytor: editor.html).
  Zapis w ustawieniach: s.layoutEdit[`${layout}:${dirCzatu}`] = { game: [x, y, w, h], avatar: [...], ... } (obraz 1920×1080).
  Brak wpisu = automatyczne ułożenie (zależne od czatu, jak dotąd).
*/
(function () {
  const W = 1920, H = 1080;
  const chatLay = s => (window.OverlayChat && window.OverlayChat.layoutOf ? window.OverlayChat.layoutOf(s) : { dir: 'v', side: 'right' });
  const keyOf = (layout, L) => layout + ':' + (L.dir === 'h' ? 'h' : 'v');

  // elementy, które da się przesuwać w danym układzie (ratio = zablokowane proporcje)
  function elements(layout, L, s) {
    const alertsOwn = !(s.alertsInChat !== false && L.dir === 'v');
    if (layout === 'game-frame') return [
      { id: 'game', name: 'Okno gry', ratio: 16 / 9 },
      { id: 'avatar', name: 'Avatar', ratio: 1 },
      ...(L.dir === 'v' ? [{ id: 'chat', name: 'Czat' }] : []),
      { id: 'bar', name: 'Pasek: zdarzenia i linki' },
      ...(alertsOwn ? [{ id: 'alerts', name: 'Alerty' }] : [])];
    if (layout === 'talk') return [
      { id: 'avatar', name: 'Avatar', ratio: 1 },
      { id: 'col', name: L.dir === 'v' ? 'Temat, linki i czat' : 'Temat i linki' },
      ...(alertsOwn ? [{ id: 'alerts', name: 'Alerty' }] : [])];
    return [{ id: 'alerts', name: 'Alerty' }];
  }

  // ułożenie automatyczne – te same liczby co w CSS układów
  function defaults(layout, L, s) {
    const mirror = L.dir === 'v' && L.side === 'left', top = L.dir === 'h' && L.side === 'top';
    if (layout === 'game-frame') {
      const gx = mirror ? 440 : 40, ax = mirror ? 40 : 1510, y = top ? 70 : 40;
      const noAv = (s.avatarMode || 'art') === 'none';
      return {
        game: [gx, y, 1440, 810], avatar: [ax, y, 370, 370],
        chat: noAv ? [ax, 40, 370, 1000] : [ax, 440, 370, 600],
        bar: L.dir === 'h' ? (top ? [1510, 470, 370, 420] : [40, 880, 1440, 130]) : [gx, 880, 1440, 160],
        alerts: L.dir === 'h' ? (top ? [40, 895, 1440, 170] : [1500, 440, 390, 540]) : [40, 858, 1440, 200],
      };
    }
    if (layout === 'talk') return { avatar: [mirror ? 1030 : 110, 150, 780, 780], col: [mirror ? 80 : 1000, 90, 840, 950], alerts: [1000, 30, 840, 340] };
    return { alerts: [420, 24, 1080, 300] };
  }

  // własne ułożenie (pełne, z domyślnymi tam, gdzie nic nie zmieniono) albo null
  function custom(s, layout, L) {
    L = L || chatLay(s);
    const o = s.layoutEdit && s.layoutEdit[keyOf(layout, L)];
    if (!o || !Object.keys(o).length) return null;
    const d = defaults(layout, L, s), r = {};
    for (const k of Object.keys(d)) r[k] = Array.isArray(o[k]) && o[k].length === 4 ? o[k].map(Number) : d[k];
    return r;
  }

  // nadaje elementom pozycję z edytora (albo ją zdejmuje); ids: id elementu → id w DOM
  function apply(s, layout, L, ids) {
    const r = custom(s, layout, L);
    for (const [k, domId] of Object.entries(ids)) {
      const el = document.getElementById(domId); if (!el) continue;
      const st = el.style, v = r && r[k];
      if (v && !(k === 'chat' && L.dir === 'h')) { st.left = v[0] + 'px'; st.top = v[1] + 'px'; st.width = v[2] + 'px'; st.height = v[3] + 'px'; st.bottom = 'auto'; st.right = 'auto'; }
      else { st.left = st.top = st.width = st.height = st.bottom = st.right = ''; }
    }
    document.body.classList.toggle('lay-custom', !!r);
    return r;
  }

  window.VMLayout = { W, H, keyOf, elements, defaults, custom, apply, chatLay };
})();
