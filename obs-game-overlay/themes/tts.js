/*
  Głos (TTS) postaci: GameRadar syntezuje mowę (za darmo, bez internetu, /tts) – domyślnie głosami neuronowymi Piper,
  zapasowo głosami Windows,
  a tutaj każda postać dostaje swoją barwę (wysokość, tempo) i efekt (robot, radio, pogłos, metal).
  Język wybiera się sam z tekstu: polski albo angielski – można mieszać w kratkę.

  VMTTS.say(tekst, { persona, lang, volume }) → Promise (kolejka; kończy się, gdy skończy mówić)
  VMTTS.voices() → [{ id, name, lang, gender }]    VMTTS.detect(tekst) → 'pl' | 'en'
  VMTTS.clean(tekst) → tekst do przeczytania albo '' (słowa nienawiści, same linki/emotki)
  VMTTS.PROFILES – barwy postaci   VMTTS.stop()
  Ustawienia (obsGameOverlay.v1): tts (true/false), ttsVolume (0–1), ttsEngine ('piper' domyślnie | 'windows'),
  ttsVoice: { 'pl': id, 'en': id, 'vince-pl': id, … }
*/
(function () {
  const KEY = 'obsGameOverlay.v1';
  const settings = () => { try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { return {}; } };
  const hub = () => (window.vmHub ? window.vmHub(settings().localUrl) : 'http://localhost:7777');

  // barwa postaci: g – płeć głosu, jaką woli (gdy jest wybór), rate – tempo, pitch – wysokość w %, fx – efekt
  const PROFILES = {
    _:      { name: 'Zwykły',  g: '',       rate: 1.0,  pitch: 0,   fx: '' },
    vince:  { name: 'Vince',   g: 'male',   rate: 0.95, pitch: -8,  fx: 'room' },
    chip:   { name: 'Chip',    g: 'female', rate: 1.12, pitch: 22,  fx: '' },
    ragnar: { name: 'Ragnar',  g: 'male',   rate: 1.08, pitch: 4,   fx: 'radio' },
    toro:   { name: 'Toro',    g: 'male',   rate: 0.88, pitch: -22, fx: 'hall' },
    myr:    { name: 'Myr-35',  g: 'female', rate: 0.98, pitch: -4,  fx: 'robot' },
    zarin:  { name: 'Zarin',   g: 'male',   rate: 0.96, pitch: -12, fx: 'metal' },
  };
  const FX_NAMES = { '': 'czysty', room: 'pokój', radio: 'radio', hall: 'sala', robot: 'robot', metal: 'metal' };

  // ---------------------------------------------------------------- tekst
  const PL_CH = /[ąćęłńóśźż]/i;
  const PL_W = /\b(i|w|z|na|nie|się|jest|to|że|jak|dzięki|dziękuję|dzieki|dziekuje|cześć|czesc|witaj|siema|co|ale|mam|już|juz|tak|dla|czy|bardzo|kocham|gra|graj|gramy|jest|był|bylo|dobra|dobry|fajnie|fajny|ziom|elo|no|ty|mi|mnie|jestem)\b/gi;
  const EN_W = /\b(the|and|you|is|are|to|of|it|this|that|thanks|thank|hello|hi|love|great|what|for|with|have|play|game|my|your|keep|going|good|nice|awesome|so|much|we|can|do|be|was|not|just|like|let's|lets|go|gg|lol|wow|amazing|stream|streamer|welcome|hey|yes|no|in|on|me|i'm|im)\b/gi;
  function detect(t) {
    t = String(t || '');
    if (PL_CH.test(t)) return 'pl';
    const pl = (t.match(PL_W) || []).length, en = (t.match(EN_W) || []).length;
    if (en > pl) return 'en';
    if (pl > en) return 'pl';
    return settings().lang === 'en' ? 'en' : 'pl';
  }
  function clean(t) {
    t = String(t || '');
    if (window.VMWords) { const c = window.VMWords.check(t); if (c.level === 'hard') return ''; if (c.level) t = c.masked; }
    t = t.replace(/https?:\/\/\S+|www\.\S+/gi, ' link ')
      .replace(/\bcheer\d+\b/gi, ' ')                       // „Cheer100” z bitsów
      .replace(/(.)\1{3,}/g, '$1$1$1')                      // aaaaaaa → aaa
      .replace(/(\S{25})\S+/g, '$1')                        // ciągi bez spacji
      .replace(/[*_#~`|<>]/g, ' ').replace(/\s+/g, ' ').trim();
    if (!/[\p{L}\p{N}]/u.test(t)) return '';                // same emotki/znaki
    return t.slice(0, 220);
  }

  // ---------------------------------------------------------------- głosy
  let voiceList = null, voiceAt = 0, piper = null;
  async function voices(force) {
    if (voiceList && !force && Date.now() - voiceAt < 60000) return voiceList;   // co minutę od nowa (np. po pobraniu głosów Piper)
    try { const j = await (await fetch(hub() + '/tts/voices', { cache: 'no-store' })).json(); voiceList = j.voices || []; piper = j.piper || null; voiceAt = Date.now(); }
    catch (e) { voiceList = null; return []; }
    return voiceList;
  }
  function pickVoice(list, persona, lang) {
    const s = settings().ttsVoice || {};
    const want = s[persona + '-' + lang] || s[lang];
    if (want && list.some(v => v.id === want)) return want;
    const eng = settings().ttsEngine === 'windows' ? 'windows' : 'piper';
    const byEng = list.filter(v => (v.engine || 'windows') === eng);
    const src = byEng.length ? byEng : list;                    // brak głosów Piper → głosy Windows
    const inLang = src.filter(v => (v.lang || '').toLowerCase().startsWith(lang));
    const pool = inLang.length ? inLang : src;
    const g = (PROFILES[persona] || PROFILES._).g;
    const v = (g && pool.find(x => x.gender === g)) || pool[0];
    return v ? v.id : '';
  }

  // ---------------------------------------------------------------- efekty (WebAudio)
  let ac = null;
  const ctx = () => { ac = ac || new (window.AudioContext || window.webkitAudioContext)(); if (ac.state === 'suspended') ac.resume(); return ac; };
  function impulse(a, sec, decay) {
    const n = Math.floor(a.sampleRate * sec), b = a.createBuffer(2, n, a.sampleRate);
    for (let c = 0; c < 2; c++) { const d = b.getChannelData(c); for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / n, decay); }
    return b;
  }
  // zwraca [wejście, wyjście] łańcucha efektu
  function chain(a, fx) {
    const inp = a.createGain(), out = a.createGain();
    const wet = (node, dry, w) => { const g1 = a.createGain(), g2 = a.createGain(); g1.gain.value = dry; g2.gain.value = w; inp.connect(g1).connect(out); inp.connect(node); node.connect(g2).connect(out); };
    if (fx === 'room' || fx === 'hall') {
      const cv = a.createConvolver(); cv.buffer = impulse(a, fx === 'hall' ? 2.4 : 0.7, fx === 'hall' ? 2.5 : 3.5);
      wet(cv, 1, fx === 'hall' ? 0.45 : 0.25);
    } else if (fx === 'radio') {
      const hp = a.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 380;
      const lp = a.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 3200;
      const sh = a.createWaveShaper(); const k = 6, n = 1024, c = new Float32Array(n);
      for (let i = 0; i < n; i++) { const x = i * 2 / n - 1; c[i] = (1 + k) * x / (1 + k * Math.abs(x)); }
      sh.curve = c; inp.connect(hp).connect(lp).connect(sh).connect(out); out.gain.value = 0.8;
    } else if (fx === 'robot') {
      // modulator pierścieniowy + krótkie metaliczne echo
      const ring = a.createGain(); ring.gain.value = 0;
      const osc = a.createOscillator(); osc.frequency.value = 52; osc.connect(ring.gain); osc.start();
      const d = a.createDelay(); d.delayTime.value = 0.012; const fb = a.createGain(); fb.gain.value = 0.35; d.connect(fb).connect(d);
      inp.connect(ring); ring.connect(d); const m = a.createGain(); m.gain.value = 0.55; ring.connect(m).connect(out); d.connect(out);
      const dry = a.createGain(); dry.gain.value = 0.35; inp.connect(dry).connect(out);
      inp._stop = () => { try { osc.stop(); } catch (e) {} };
    } else if (fx === 'metal') {
      const d = a.createDelay(); d.delayTime.value = 0.007; const fb = a.createGain(); fb.gain.value = 0.55; d.connect(fb).connect(d);
      const bp = a.createBiquadFilter(); bp.type = 'peaking'; bp.frequency.value = 2400; bp.gain.value = 6;
      inp.connect(bp); bp.connect(out); bp.connect(d); const w = a.createGain(); w.gain.value = 0.5; d.connect(w).connect(out);
    } else inp.connect(out);
    return [inp, out];
  }

  // ---------------------------------------------------------------- kolejka
  let q = Promise.resolve(), current = null, gen = 0;
  // zdania po polsku i po angielsku w jednym tekście: każda część swoim głosem
  function parts(text) {
    const out = [];
    for (const z of String(text || '').split(/(?<=[.!?…])\s+/)) {
      if (!z.trim()) continue;
      const l = detect(z), last = out[out.length - 1];
      if (last && last.lang === l) last.text += ' ' + z; else out.push({ text: z, lang: l });
    }
    return out;
  }
  function say(text, o = {}) {
    const my = gen;
    const segs = o.lang ? [{ text, lang: o.lang }] : parts(text);
    let job = q;
    for (const sg of segs) job = job.then(() => (my === gen ? speak(sg.text, { ...o, lang: sg.lang }) : null)).catch(() => {});
    q = job; return job;
  }
  async function speak(text, o) {
    const t = clean(text); if (!t) return;
    const s = settings();
    const vol = Math.max(0, Math.min(1, o.volume != null ? o.volume : (s.ttsVolume != null ? +s.ttsVolume : 0.9)));
    if (!vol) return;
    const persona = PROFILES[o.persona] ? o.persona : '_';
    const P = PROFILES[persona], lang = o.lang || detect(t);
    const list = await voices(); if (!list.length) return;
    const voice = pickVoice(list, persona, lang);
    const u = hub() + '/tts?text=' + encodeURIComponent(t) + '&voice=' + encodeURIComponent(voice) + '&rate=' + P.rate + '&pitch=' + P.pitch;
    const r = await fetch(u, { cache: 'no-store' }); if (!r.ok) return;
    const a = ctx(), buf = await a.decodeAudioData(await r.arrayBuffer());
    const src = a.createBufferSource(); src.buffer = buf;
    // Piper nie zmienia wysokości – robi to szybsze/wolniejsze odtwarzanie (GameRadar wydłużył mowę o tyle samo)
    if (voice.startsWith('piper:') && !r.headers.get('X-VM-Fallback')) src.playbackRate.value = Math.max(0.6, Math.min(1.6, 1 + P.pitch / 100));
    const [inp, out] = chain(a, o.fx != null ? o.fx : P.fx);
    const g = a.createGain(); g.gain.value = vol;
    src.connect(inp); out.connect(g).connect(a.destination);
    await new Promise(res => {
      current = { src, done: res };
      src.onended = () => { if (inp._stop) inp._stop(); setTimeout(() => { try { g.disconnect(); } catch (e) {} }, 2500); current = null; res(); };
      src.start();
    });
  }
  function stop() { gen++; q = Promise.resolve(); if (current) { try { current.src.stop(); } catch (e) {} current.done(); current = null; } }

  window.VMTTS = { say, stop, voices, detect, clean, PROFILES, FX_NAMES, piper: () => piper };
})();
