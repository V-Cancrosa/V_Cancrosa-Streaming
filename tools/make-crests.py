#!/usr/bin/env python3
"""Herby postaci bez artów (Myr-35, Zarin) jako SVG: themes/fursona/myr-crest.svg, zarin-crest.svg.
Rysunek własny (motywy: wizjer protogena z diodami; trzy pióra Avali w pierścieniu). Użycie: python3 tools/make-crests.py"""
import math, pathlib
OUT = pathlib.Path(__file__).resolve().parent.parent / 'obs-game-overlay' / 'themes' / 'fursona'

# czcionka 5×7 z diod (tylko potrzebne znaki)
F = {
 'M': ['10001','11011','10101','10101','10001','10001','10001'], 'Y': ['10001','10001','01010','00100','00100','00100','00100'],
 'R': ['11110','10001','10001','11110','10100','10010','10001'], '-': ['00000','00000','00000','11111','00000','00000','00000'],
 '3': ['11110','00001','00001','01110','00001','00001','11110'], '5': ['11111','10000','11110','00001','00001','10001','01110'],
}
def led_text(txt, x0, y0, p, fill, gap=1):
    out = []; x = x0
    for ch in txt:
        g = F[ch]
        for r, row in enumerate(g):
            for c, v in enumerate(row):
                if v == '1': out.append(f'<rect x="{x + c * p:.1f}" y="{y0 + r * p:.1f}" width="{p - 1.2:.1f}" height="{p - 1.2:.1f}" rx="1" fill="{fill}"/>')
        x += (5 + gap) * p
    return ''.join(out)
def led_cells(cells, ox, oy, p, fill):
    return ''.join(f'<rect x="{ox + c * p:.1f}" y="{oy + r * p:.1f}" width="{p - 1.4:.1f}" height="{p - 1.4:.1f}" rx="1.2" fill="{fill}"/>' for r, c in cells)

def myr():
    O, C, D = '#d9823f', '#ede6d6', '#1c1f23'
    # oczy (łuki ^ ^) i usta (zygzak w) z diod, siatka 4.4 px
    eye = [(2,0),(1,1),(0,2),(1,3),(2,4)]           # „>” obrócone: kształt łuku
    eyeL = [(r, c) for r, c in [(0,2),(1,1),(1,3),(2,0),(2,4)]]
    mouth = [(0,0),(1,1),(2,2),(1,3),(0,4),(1,5),(2,6),(1,7),(0,8)]
    p = 9
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="sh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a2f36"/><stop offset="1" stop-color="{D}"/></linearGradient>
    <linearGradient id="vi" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#0b0c0f"/><stop offset="1" stop-color="#16181d"/></linearGradient>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>
  <!-- tarcza: kanciasta, ścięte narożniki -->
  <path d="M104 34 H408 L462 88 V262 C462 340 380 410 256 482 C132 410 50 340 50 262 V88 Z" fill="url(#sh)" stroke="{O}" stroke-width="12" stroke-linejoin="round"/>
  <path d="M114 58 H398 L438 98 V258 C438 326 366 388 256 452 C146 388 74 326 74 258 V98 Z" fill="none" stroke="{C}" stroke-opacity=".35" stroke-width="3"/>
  <!-- obwody -->
  <g stroke="{O}" stroke-width="4" fill="none" stroke-linecap="round" opacity=".85">
    <path d="M74 150 H118 L134 166 H150"/><circle cx="74" cy="150" r="6" fill="{O}"/>
    <path d="M438 150 H394 L378 166 H362"/><circle cx="438" cy="150" r="6" fill="{O}"/>
    <path d="M92 230 H128 L146 212"/><circle cx="92" cy="230" r="5" fill="{O}"/>
    <path d="M420 230 H384 L366 212"/><circle cx="420" cy="230" r="5" fill="{O}"/>
  </g>
  <!-- uszy protogena -->
  <path d="M168 132 L150 62 L214 108 Z" fill="{C}" stroke="{D}" stroke-width="5" stroke-linejoin="round"/>
  <path d="M344 132 L362 62 L298 108 Z" fill="{C}" stroke="{D}" stroke-width="5" stroke-linejoin="round"/>
  <path d="M166 118 L158 84 L190 106 Z" fill="{O}"/><path d="M346 118 L354 84 L322 106 Z" fill="{O}"/>
  <!-- skorupa głowy i wizjer -->
  <path d="M150 128 C178 98 334 98 362 128 C384 152 388 214 372 252 C356 290 312 306 256 306 C200 306 156 290 140 252 C124 214 128 152 150 128 Z" fill="{C}" stroke="{D}" stroke-width="6"/>
  <path d="M166 146 C196 124 316 124 346 146 C362 160 364 210 352 236 C340 262 304 278 256 278 C208 278 172 262 160 236 C148 210 150 160 166 146 Z" fill="url(#vi)"/>
  <g filter="url(#glow)">
    {led_cells(eyeL, 190, 170, p, O)}
    {led_cells(eyeL, 278, 170, p, O)}
    {led_cells(mouth, 216, 226, p, O)}
  </g>
  <!-- ranga: trzy pasy -->
  <g fill="{O}"><path d="M196 330 L256 352 L316 330 L316 342 L256 364 L196 342 Z"/><path d="M196 352 L256 374 L316 352 L316 364 L256 386 L196 364 Z" opacity=".75"/><path d="M196 374 L256 396 L316 374 L316 386 L256 408 L196 386 Z" opacity=".5"/></g>
  <!-- MYR-35 z diod -->
  <rect x="140" y="410" width="232" height="50" rx="7" fill="{D}" stroke="{O}" stroke-width="3"/>
  <g filter="url(#glow)">{led_text('MYR-35', 154, 417, 5.6, C, gap=1)}</g>
</svg>'''
    return svg

def zarin():
    G, T, D, H = '#2fd46b', '#1fc7b5', '#14171b', '#7d8186'
    def feather(angle, length=200, width=34, bx=256, by=338):
        # pióro: gołą dutka u nasady, asymetryczna chorągiewka z zaokrąglonym końcem i rozszczepieniami
        L, w, q = length, width, 30            # q – długość dutki
        vane = (f'M0 {-q} C{-w*0.9:.1f} {-q-L*0.18:.1f} {-w*1.05:.1f} {-L*0.62:.1f} {-w*0.55:.1f} {-L*0.9:.1f} '
                f'C{-w*0.3:.1f} {-L*1.02:.1f} {w*0.35:.1f} {-L*1.03:.1f} {w*0.55:.1f} {-L*0.9:.1f} '
                f'C{w*0.85:.1f} {-L*0.62:.1f} {w*0.7:.1f} {-q-L*0.18:.1f} 0 {-q} Z')
        # rozszczepienia: wąskie ciemne kliny wchodzące od krawędzi ukośnie w stronę końca
        cuts = ''.join(f'<path d="M{s*w*1.2:.1f} {-L*f+10:.1f} L{s*w*0.18:.1f} {-L*f-16:.1f} L{s*w*1.2:.1f} {-L*f-2:.1f} Z" fill="{D}"/>'
                       for s, f in [(-1, .42), (-1, .7), (1, .55), (1, .32)])
        return (f'<g transform="translate({bx} {by}) rotate({angle})"><clipPath id="c{angle}"><path d="{vane}"/></clipPath>'
                f'<path d="{vane}" fill="url(#fe)"/><g clip-path="url(#c{angle})">{cuts}</g>'
                f'<path d="{vane}" fill="none" stroke="{D}" stroke-width="4"/>'
                f'<path d="M0 0 C1 {-L*0.4:.1f} -2 {-L*0.7:.1f} -1 {-L*0.93:.1f}" stroke="#e8fff1" stroke-width="4" stroke-linecap="round" fill="none" opacity=".9"/></g>')
    ring = ''.join(f'<path d="{arc(256, 236, 196, a + 8, a + 82)}" fill="none" stroke="url(#ri)" stroke-width="20" stroke-linecap="round"/>' for a in (0, 90, 180, 270))
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="fe" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="{T}"/><stop offset="1" stop-color="{G}"/></linearGradient>
    <linearGradient id="ri" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{G}"/><stop offset="1" stop-color="{T}"/></linearGradient>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>
  <circle cx="256" cy="236" r="184" fill="{D}" opacity=".92"/>
  <g filter="url(#glow)">{ring}</g>
  <circle cx="256" cy="236" r="164" fill="none" stroke="{T}" stroke-opacity=".3" stroke-width="2" stroke-dasharray="4 10"/>
  {feather(-46, 176, 30)}{feather(46, 176, 30)}{feather(0, 214, 36)}
  <circle cx="256" cy="338" r="13" fill="{D}" stroke="{G}" stroke-width="5"/>
  <!-- płyta kadłuba z nazwą -->
  <rect x="136" y="402" width="240" height="70" rx="6" fill="{H}" stroke="#3a3f45" stroke-width="5"/>
  <rect x="136" y="446" width="240" height="12" fill="#5e7a5a" opacity=".9"/>
  <text x="256" y="446" text-anchor="middle" font-family="'Saira Stencil One', Impact, 'Arial Black', sans-serif" font-size="40" letter-spacing="8" fill="#e6e1d3">ZARIN</text>
  <g fill="#3a3f45"><circle cx="148" cy="414" r="4"/><circle cx="364" cy="414" r="4"/><circle cx="148" cy="462" r="4"/><circle cx="364" cy="462" r="4"/></g>
</svg>'''
    return svg

def arc(cx, cy, r, a0, a1):
    p = lambda a: (cx + r * math.cos(math.radians(a - 90)), cy + r * math.sin(math.radians(a - 90)))
    (x0, y0), (x1, y1) = p(a0), p(a1)
    return f'M{x0:.1f} {y0:.1f} A{r} {r} 0 0 1 {x1:.1f} {y1:.1f}'

if __name__ == '__main__':
    (OUT / 'myr-crest.svg').write_text(myr(), encoding='utf-8')
    (OUT / 'zarin-crest.svg').write_text(zarin(), encoding='utf-8')
    print('ok')
