/*
  Fuzje szyte na miarę: konkretna postać + konkretna gra dostają własny, unikalny pomysł zamiast ogólnych „sąsiadów”.
  GT.combo(r) → { key, html } albo null. Nakładka wstawia html do #combo i dodaje klasy „combo cb-<postać>-<gra>”.
  Grafika narysowana od zera (SVG/CSS), CC0. Townscaper – paleta dachów jak w grze.

  Townscaper:
    vince  – architekt: plan miasteczka na kalce; złote linie kreślą domki, które po kolei wypełniają się kolorem;
             jego portret to okno w kamieniczce z dachem
    ragnar – korektor 128 BPM: słupki to wieże z domków, które rosną i maleją w rytmie
    toro   – most z łukami i przęsłami nad wodą pod kartą, w każdym łuku lampion
    chip   – piernikowe miasteczko: lukrowane dachy, cukierkowe okna, para z kominów
    myr    – matryca LED (jak wizjer) rysuje panoramę miasteczka, w oknach zapalają się kolorowe światełka
    zarin  – domki skręcone ze złomu: blachy z nitami pomalowane w kolory palety i wiatraczek z wentylatora
*/
(function () {
  const GT = window.OverlayGameThemes;
  if (!GT) return;
  const PAL = ['#e05a4f', '#f0a04b', '#f4d35e', '#b8d86b', '#6cc18e', '#4fb3a8', '#5ab8d8', '#6a8fd8', '#9b7bd0', '#d98bb5'];
  const INK = '#3b4a52';
  const svg = (w, h, body, cls = '', par = 'xMidYMax meet') => `<svg class="${cls}" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="${par}">${body}</svg>`;
  // domek: ściany + dach (trójkąt albo schodkowy) + okienka
  function house(x, base, w, h, wall, roof, o = {}) {
    const top = base - h, rh = Math.round(w * 0.55);
    const st = o.stroke || INK, sw = o.sw || 2;
    const roofP = o.flat ? `M${x - 2} ${top} h${w + 4} v-${Math.round(rh / 3)} h-${w + 4} Z` : `M${x - 3} ${top} L${x + w / 2} ${top - rh} L${x + w + 3} ${top} Z`;
    let win = '';
    for (let yy = top + 7; yy < base - 9; yy += 13) for (let xx = x + 5; xx < x + w - 6; xx += 10) win += `<rect class="${o.winCls || ''}" x="${xx}" y="${yy}" width="5" height="7" rx="1" fill="${o.win || '#fffbe8'}"/>`;
    return `<g class="${o.cls || ''}" style="${o.style || ''}"><rect x="${x}" y="${top}" width="${w}" height="${h}" fill="${wall}" stroke="${st}" stroke-width="${sw}"/>${win}<path d="${roofP}" fill="${roof}" stroke="${st}" stroke-width="${sw}" stroke-linejoin="round"/></g>`;
  }
  const row = (n, fn) => Array.from({ length: n }, (_, i) => fn(i)).join('');

  const C = {
    // ------------------------------------------------ Vince: plan architekta, domki kreślone i wypełniane kolorem
    'vince+tsc': () => {
      let x = 6, out = '';
      const W = [26, 34, 22, 30, 38, 24, 32, 28, 36, 22, 30, 26];
      W.forEach((w, i) => {
        const h = 14 + ((i * 7) % 4) * 6;
        out += `<g class="cbv-h" style="--i:${i}">` +
          house(x, 52, w, h, PAL[i % PAL.length], PAL[(i + 4) % PAL.length], { stroke: '#e3a43f', sw: 1.6, cls: 'cbv-fill' }) +
          house(x, 52, w, h, 'none', 'none', { stroke: '#e3a43f', sw: 1.4, cls: 'cbv-line', win: 'none' }) + '</g>';
        x += w + 8;
      });
      return `<div class="cbv-plan">${svg(x + 4, 56, `<path d="M0 54 H${x + 4}" stroke="#e3a43f" stroke-width="1.5" stroke-dasharray="6 4"/>${out}<text x="${x - 2}" y="10" text-anchor="end" font-family="Space Mono, monospace" font-size="7" fill="#8a857c" letter-spacing="1.5">PLAN · TOWNSCAPER · VC-001</text>`, 'cbv-svg', 'xMinYMax meet')}</div>
        <div class="cbv-roof">${svg(140, 46, `<path d="M4 44 L70 4 L136 44 Z" fill="${PAL[0]}" stroke="${INK}" stroke-width="3" stroke-linejoin="round"/><rect x="98" y="10" width="12" height="20" fill="${PAL[7]}" stroke="${INK}" stroke-width="2.5"/><circle cx="70" cy="28" r="6" fill="#fffbe8" stroke="${INK}" stroke-width="2"/>`)}</div>`;
    },
    // ------------------------------------------------ Ragnar: korektor z wież z domków (128 BPM)
    'ragnar+tsc': () => `<div class="cbr-eq">${row(9, i => {
      let b = '';
      for (let k = 0; k < 4; k++) { const y = 62 - k * 12; b += `<rect x="3" y="${y}" width="18" height="12" fill="${PAL[(i + k) % 10]}" stroke="${INK}" stroke-width="2"/><rect x="9" y="${y + 3}" width="6" height="6" rx="1" fill="#fffbe8"/>`; }
      b += `<path d="M1 26 L12 13 L23 26 Z" fill="${PAL[(i + 5) % 10]}" stroke="${INK}" stroke-width="2" stroke-linejoin="round"/>`;
      return `<div class="cbr-col" style="--i:${i}">${svg(24, 74, b, 'cbr-svg', 'xMidYMax meet')}</div>`;
    })}</div>`,
    // ------------------------------------------------ Toro: most z łukami nad wodą, lampiony w łukach
    'toro+tsc': () => {
      const n = 9, span = 66, w = n * span;
      let arches = '', lamps = '';
      for (let i = 0; i < n; i++) {
        const x = i * span;
        arches += `<path d="M${x} 6 H${x + span} V40 H${x + span - 8} Q${x + span - 8} 16 ${x + span / 2} 16 Q${x + 8} 16 ${x + 8} 40 H${x} Z" fill="${i % 2 ? '#f4efe4' : '#ece3cf'}" stroke="${INK}" stroke-width="2"/>`;
        lamps += `<g class="cbt-lamp" style="--i:${i}"><path d="M${x + span / 2} 16 v8" stroke="${INK}" stroke-width="1.5"/><rect x="${x + span / 2 - 5}" y="24" width="10" height="12" rx="3" fill="#ffc864" stroke="#7a4a1a" stroke-width="1.5"/></g>`;
      }
      return `<div class="cbt-bridge">${svg(w, 58, `<rect x="0" y="40" width="${w}" height="18" fill="#8fd2c8"/><path class="cbt-wave" d="M0 48 ${row(Math.ceil(w / 20) + 2, k => `q5 -4 10 0 t10 0`)}" fill="none" stroke="#e8fbf7" stroke-width="2"/>${arches}<path d="M0 6 H${w}" stroke="${INK}" stroke-width="3"/>${row(n + 1, k => `<rect x="${k * span - 3}" y="0" width="6" height="8" fill="${PAL[(k * 3) % 10]}" stroke="${INK}" stroke-width="1.5"/>`)}${lamps}`, 'cbt-svg', 'none')}</div>`;
    },
    // ------------------------------------------------ Chip: piernikowe miasteczko z lukrem
    'chip+tsc': () => {
      let x = 4, out = '';
      [30, 24, 36, 26, 32, 22].forEach((w, i) => {
        const h = 18 + (i % 3) * 7, top = 56 - h, rh = Math.round(w * 0.55);
        out += `<g class="cbc-h" style="--i:${i}"><rect x="${x}" y="${top}" width="${w}" height="${h}" rx="3" fill="#b8743a" stroke="#4a2a17" stroke-width="2.5"/>
          <path d="M${x - 3} ${top + 1} L${x + w / 2} ${top - rh} L${x + w + 3} ${top + 1} Z" fill="${PAL[(i * 3) % 10]}" stroke="#4a2a17" stroke-width="2.5" stroke-linejoin="round"/>
          <path d="M${x} ${top + 2} q3 5 6 0 t6 0 t6 0 t6 0 t6 0 t6 0" fill="none" stroke="#fffaf0" stroke-width="2.4" stroke-linecap="round" clip-path="inset(0 ${-w}px 0 0)"/>
          <rect x="${x + w / 2 - 4}" y="${56 - 11}" width="8" height="11" rx="4" fill="#fffaf0"/>
          <circle cx="${x + 6}" cy="${top + h / 2}" r="2.6" fill="${PAL[(i + 5) % 10]}"/><circle cx="${x + w - 6}" cy="${top + h / 2}" r="2.6" fill="${PAL[(i + 2) % 10]}"/>
          <path class="cbc-steam" d="M${x + w - 8} ${top - rh + 6} q-4 -6 0 -12 q4 -6 0 -12" fill="none" stroke="#fffaf0" stroke-width="2" stroke-linecap="round" opacity=".8"/></g>`;
        x += w + 10;
      });
      return `<div class="cbc-town">${svg(x, 58, out, 'cbc-svg', 'xMinYMax meet')}</div>`;
    },
    // ------------------------------------------------ Myr: panorama z diod LED, okna zapalają się na kolorowo
    'myr+tsc': () => {
      const P = 4, cols = 80, rows = 13, skyline = [];
      // zarys domków: wysokość kolumny i dach
      let c = 0, k = 0;
      while (c < cols) { const w = 6 + (k * 5) % 6, h = 5 + (k * 3) % 6; for (let j = 0; j < w && c < cols; j++, c++) skyline.push({ h: h + (j === Math.floor(w / 2) ? 2 : j === Math.floor(w / 2) - 1 || j === Math.floor(w / 2) + 1 ? 1 : 0), edge: j === 0 || j === w - 1, win: j % 3 === 1 }); c++; skyline.push({ h: 0 }); k++; }
      let dots = '', wins = '';
      skyline.slice(0, cols).forEach((s, x) => {
        for (let y = 0; y < rows; y++) {
          const fromBottom = rows - 1 - y;
          if (!s.h || fromBottom >= s.h) continue;
          const roof = fromBottom >= s.h - 2, isWin = s.win && !roof && fromBottom % 3 === 1 && fromBottom > 0;
          if (isWin) wins += `<circle class="cbm-win" style="--i:${(x * 7 + y * 13) % 17};--c:${PAL[(x + y) % 10]}" cx="${x * P + 2}" cy="${y * P + 2}" r="1.5"/>`;
          else if (s.edge || roof || fromBottom === 0) dots += `M${x * P + 2} ${y * P + 2}h0`;
        }
      });
      return `<div class="cbm-led">${svg(cols * P, rows * P, `<path d="${dots}" stroke="#ffad5c" stroke-width="2.6" stroke-linecap="round" class="cbm-dots"/>${wins}`, 'cbm-svg', 'xMidYMid meet')}</div>`;
    },
    // ------------------------------------------------ Zarin: domki ze złomu, blachy z nitami w kolorach palety, wiatraczek
    'zarin+tsc': () => {
      let x = 4, out = '';
      [30, 26, 34, 24].forEach((w, i) => {
        const h = 20 + (i % 2) * 9, top = 58 - h;
        out += `<g><rect x="${x}" y="${top}" width="${w}" height="${h}" fill="#8a9097" stroke="#3a3f45" stroke-width="2"/>
          <rect x="${x + 2}" y="${top + h * 0.45}" width="${w - 4}" height="${h * 0.3}" fill="${PAL[(i * 3 + 1) % 10]}" opacity=".85"/>
          <path d="M${x - 3} ${top} L${x + w / 2} ${top - 13} L${x + w + 3} ${top} Z" fill="${PAL[(i * 3 + 5) % 10]}" stroke="#3a3f45" stroke-width="2" stroke-linejoin="round"/>
          ${row(4, r => `<circle cx="${r % 2 ? x + w - 3 : x + 3}" cy="${r < 2 ? top + 3 : 58 - 3}" r="1.4" fill="#3a3f45"/>`)}
          <rect x="${x + w / 2 - 4}" y="${top + 5}" width="8" height="6" fill="#cfe8f2" stroke="#3a3f45" stroke-width="1.2"/></g>`;
        x += w + 9;
      });
      out += `<g transform="translate(${x + 8} 6)"><path d="M8 52 L12 20 L16 52 Z" fill="#5a6068" stroke="#3a3f45" stroke-width="1.5"/>
        <g class="cbz-fan"><path d="M12 20 C9 9 13 1 19 1 C17 9 15 15 12 20 Z M12 20 C23 17 31 21 31 27 C23 25 17 23 12 20 Z M12 20 C15 31 11 39 5 39 C7 31 9 25 12 20 Z M12 20 C1 23 -7 19 -7 13 C1 15 7 17 12 20 Z" fill="#9aa4ad"/></g><circle cx="12" cy="20" r="3" fill="#2fd46b"/></g>`;
      return `<div class="cbz-yard">${svg(x + 44, 60, out, 'cbz-svg', 'xMinYMax meet')}</div>`;
    }
  };

  // r = wynik fuzji (themes/fusion.js): postać prowadzi (def albo persona), gra jako dodatek (game)
  GT.combo = function (r) {
    if (!r) return null;
    const p = r.persona || (r.def && r.def.group === 'fursona' ? r.def : null);
    const g = r.game || (r.def && r.def.group !== 'fursona' ? r.def : null);
    if (!p || !g || r.mode === 'game' || r.mode === 'off') return null;
    const key = p.id + '+' + (g.variantOf || g.id);
    return C[key] ? { key, cls: 'cb-' + key.replace('+', '-'), html: C[key]() } : null;
  };
  GT.combos = Object.keys(C);
})();
