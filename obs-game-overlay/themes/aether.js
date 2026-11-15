/*
  Tło „Aetheric Blueprint” dla ekranów Vince'a: obracające się heksagony, trójkąty i pierścienie z glifami,
  a przy alercie z centrum rozchodzi się fala, tym silniejsza, im wyższy poziom alertu (1–5).

  Na podstawie pracy „Aetheric Blueprint – Interactive Shader” autorstwa Techartist (VoXelo),
  https://codepen.io/VoXelo/pen/azOeJVo – licencja MIT. Zmiany: czysty WebGL zamiast Three.js,
  fala od alertów zamiast kliknięcia, kilka fal naraz, kolory z motywu (postać/gra), bez błysku na cały ekran,
  połowa rozdzielczości i najwyżej 30 klatek na sekundę, pauza, gdy tła nie widać.

  Użycie:  VMAether.start(rodzic, ['#7c5cff', '#00e1ff'])  → true, gdy WebGL działa
           VMAether.colors(a, b)   VMAether.pulse(poziom)   VMAether.still(true/false)   VMAether.stop()
*/
(function () {
  const VS = 'attribute vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }';
  const FS = `
precision highp float;
uniform vec2 res; uniform float time; uniform vec3 colA; uniform vec3 colB;
uniform vec4 pT; uniform vec4 pS;           // do 4 fal: czas startu i siła
#define PI 3.14159265359
mat2 rot(float a){ return mat2(cos(a), -sin(a), sin(a), cos(a)); }
float px;
float line(float a, float b, float w){ return smoothstep(a - w, a, b) - smoothstep(a, a + w, b); }
float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float pattern(vec2 uv){
  float pat = 0.0, dist = length(uv), ang = atan(uv.y, uv.x), w = px * 1.4;
  vec2 h = rot(time * 0.05) * uv;
  for (float i = 0.0; i < 6.0; i++) { float a = i * PI / 3.0; pat = max(pat, line(dot(h, vec2(cos(a), sin(a))), 0.0, w)); }
  vec2 t = rot(-time * 0.1) * uv;
  for (float i = 0.0; i < 3.0; i++) { vec2 q = rot(i * 2.0 * PI / 3.0) * t; pat = max(pat, line(q.y, -0.25, w)); pat = max(pat, line(q.y, 0.25, w)); }
  for (float i = 1.0; i < 8.0; i++) {
    float r = i * 0.12;
    if (abs(dist - r) < 0.01) {
      float n = 10.0 + i * 2.0, g = floor(ang * n) / n;
      if (sin(g * 50.0 + time * i) > 0.5) pat = max(pat, line(dist, r, w));
    }
  }
  vec2 e = uv * 30.0;
  pat += (sin(e.x) + cos(e.y)) * 0.05 * (1.0 - smoothstep(0.8, 0.9, dist));
  return clamp(pat, 0.0, 1.0);
}
float wave(float since, float s, float r, out float bloom){
  float dur = 2.0 + s * 1.2;
  bloom = 0.0;
  if (since <= 0.0 || since >= dur) return 0.0;
  float k = since / dur, amp = sin(k * PI) * s, wr = k * (1.2 + s * 0.8);
  float w = smoothstep(wr - 0.1, wr, r) - smoothstep(wr, wr + 0.1, r);
  bloom = w * w * amp;
  return w * amp;
}
void main(){
  px = 2.0 / min(res.x, res.y);
  vec2 uv = (gl_FragCoord.xy * 2.0 - res) / min(res.x, res.y) * 0.8;
  float r = length(uv), act = 0.0, bloom = 0.0, b;
  act += wave(time - pT.x, pS.x, r, b); bloom += b;
  act += wave(time - pT.y, pS.y, r, b); bloom += b;
  act += wave(time - pT.z, pS.z, r, b); bloom += b;
  act += wave(time - pT.w, pS.w, r, b); bloom += b;
  act = min(act, 1.2); bloom = min(bloom, 1.0);
  vec2 duv = r > 0.0 ? uv - normalize(uv) * act * 0.1 : uv;
  float pat = pattern(duv);
  float m = 0.5 + 0.5 * sin((r * 0.5 - time * 0.1) * 2.0 * PI);   // kolor płynie od środka: A ↔ B
  vec3 bp = mix(colA, colB, m);
  vec3 hot = mix(vec3(1.0), mix(colA, colB, 0.5), 0.35);
  vec3 c = vec3(hash(gl_FragCoord.xy) * 0.035);
  c += pat * bp * 0.42;
  c += pow(pat, 3.0) * bp * 0.25;
  c += act * pat * hot * 3.0;
  c += bloom * pat * hot * 3.0;
  c *= 1.0 - smoothstep(0.75, 1.6, length(uv * vec2(0.75, 1.0)));  // winieta: brzegi zostają ciemne pod czat i alerty
  gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}`;

  const hex = c => { const m = String(c || '').trim().match(/^#?([\da-f]{6}|[\da-f]{3})$/i); if (!m) return [0.49, 0.36, 1]; let h = m[1]; if (h.length === 3) h = h.replace(/./g, x => x + x); return [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16) / 255); };
  let gl = null, cv = null, prog = null, U = {}, raf = 0, last = 0, t0 = 0, vis = true, io = null, still = false;
  const pulses = [[-100, 0], [-100, 0], [-100, 0], [-100, 0]];
  let cols = [hex('#7c5cff'), hex('#00e1ff')];
  const now = () => (performance.now() - t0) / 1000;

  function size() {
    if (!cv) return;
    const w = Math.max(320, Math.round(cv.clientWidth * 0.5)), h = Math.max(180, Math.round(cv.clientHeight * 0.5));   // połowa rozdzielczości: tło i tak jest miękkie
    if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; gl.viewport(0, 0, w, h); }
  }
  function draw() {
    size();
    const t = now();
    gl.uniform2f(U.res, cv.width, cv.height);
    gl.uniform1f(U.time, t);
    gl.uniform3fv(U.colA, cols[0]); gl.uniform3fv(U.colB, cols[1]);
    gl.uniform4f(U.pT, pulses[0][0], pulses[1][0], pulses[2][0], pulses[3][0]);
    gl.uniform4f(U.pS, pulses[0][1], pulses[1][1], pulses[2][1], pulses[3][1]);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }
  function loop(ts) {
    raf = 0;
    if (!gl || still || !vis || document.hidden) return;
    raf = requestAnimationFrame(loop);
    if (ts - last < 1000 / 30 - 2) return;       // najwyżej 30 klatek
    last = ts;
    draw();
  }
  const kick = () => { if (gl && !raf && !still && vis && !document.hidden) raf = requestAnimationFrame(loop); };

  function start(parent, colors) {
    if (gl) { if (colors) api.colors(...colors); return true; }
    cv = document.createElement('canvas');
    cv.className = 'aether';
    cv.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block';
    parent.insertBefore(cv, parent.firstChild);
    gl = cv.getContext('webgl', { antialias: false, alpha: false, powerPreference: 'low-power', preserveDrawingBuffer: false });
    const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
    try {
      if (!gl) throw new Error('brak WebGL');
      prog = gl.createProgram();
      gl.attachShader(prog, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FS));
      gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
    } catch (e) { console.warn('[aether]', e.message); cv.remove(); cv = null; gl = null; return false; }
    gl.useProgram(prog);
    const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, 'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    for (const n of ['res', 'time', 'colA', 'colB', 'pT', 'pS']) U[n] = gl.getUniformLocation(prog, n);
    t0 = performance.now();
    // utrata kontekstu (np. sterownik GPU): nowe płótno po chwili
    cv.addEventListener('webglcontextlost', e => { e.preventDefault(); const p = cv.parentNode, c = cols, wasStill = still; api.stop(); setTimeout(() => { if (p && !gl) { start(p); cols = c; api.still(wasStill); } }, 1000); });
    // pauza, gdy tła nie widać (karta w tle, ukryty zestaw w stage.html, ukryte źródło)
    document.addEventListener('visibilitychange', kick);
    if (window.IntersectionObserver) { io = new IntersectionObserver(es => { vis = es.some(e => e.isIntersecting); kick(); }); io.observe(cv); }
    if (colors) api.colors(...colors);
    draw(); kick();
    return true;
  }

  const api = {
    start,
    colors(a, b) { cols = [hex(a), hex(b || a)]; if (gl && (still || !raf)) draw(); },
    // fala od alertu: poziom 1–5 → siła; legendarne (5) dostają echo
    pulse(tier) {
      if (!gl || still) return;
      const lv = Math.max(1, Math.min(5, Number(tier) || 1)), s = [0, 0.35, 0.5, 0.68, 0.85, 1][lv], t = now();
      const put = (at, str) => { let i = pulses.findIndex(p => t - p[0] > 4.5); if (i < 0) i = pulses.reduce((m, p, j) => (p[0] < pulses[m][0] ? j : m), 0); pulses[i] = [at, str]; };
      put(t, s);
      if (lv >= 5) put(t + 0.45, 0.55);
      kick();
    },
    still(on) { still = !!on; if (gl) { if (still) { cancelAnimationFrame(raf); raf = 0; draw(); } else kick(); } },
    stop() {
      cancelAnimationFrame(raf); raf = 0;
      if (io) io.disconnect(); io = null;
      document.removeEventListener('visibilitychange', kick);
      if (gl) { const x = gl.getExtension('WEBGL_lose_context'); if (x) x.loseContext(); }
      if (cv) cv.remove();
      gl = null; cv = null; prog = null;
    },
    get on() { return !!gl; },
  };
  window.VMAether = api;
})();
