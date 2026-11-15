/*
  Automatyczna konfiguracja OBS przez OBS WebSocket (na działającym OBS, bez zamykania go).
  VMObsSetup.check(obs, { hub }) → [{ id, title, ok, detail, idle, restart, fix: async () => tekst }]
    idle    – poprawka tylko poza transmisją i nagrywaniem (OBS nie zmienia wtedy obrazu ani wyjścia)
    restart – zmiana działa od następnego uruchomienia OBS
  Sprawdza: obraz 1920×1080 / 60 kl./s, scenę «VM · Stream» z kompletem źródeł w dobrej kolejności,
  filtry mikrofonu (Popraw głos), usługę Twitch z kluczem transmisji (pobieranym od Twitcha przez GameRadar),
  wyjście: tryb prosty, koder karty graficznej, 6000 kb/s obrazu i 160 kb/s dźwięku, dźwięk 48 kHz.
*/
(function () {
  const STREAM = 'VM · Stream', CAP = 'VM · Gra (automatycznie)';
  const BASE = new URL('../', (document.currentScript && document.currentScript.src) || location.href).href;
  // źródła w «VM · Stream» od dołu do góry
  const SOURCES = [
    { name: CAP, kind: 'window_capture', settings: { capture_cursor: false }, optional: true },
    { name: 'VM · Scena', kind: 'browser_source', file: 'stage.html' },
    { name: 'VM · Alerty', kind: 'browser_source', file: 'alerts.html', audio: true },
    { name: 'VM · Przejścia', kind: 'browser_source', file: 'transition.html' },
  ];
  const VOICE_FX = [
    ['VM · Redukcja szumów', 'noise_suppress_filter_v2', { method: 'rnnoise' }],
    ['VM · Bramka szumów', 'noise_gate_filter', { open_threshold: -36, close_threshold: -44, attack_time: 25, hold_time: 200, release_time: 150 }],
    ['VM · Kompresor', 'compressor_filter', { ratio: 4, threshold: -20, attack_time: 6, release_time: 60, output_gain: 4 }],
    ['VM · Limiter', 'limiter_filter', { threshold: -3, release_time: 60 }],
  ];
  const MIC_KINDS = ['wasapi_input_capture', 'coreaudio_input_capture', 'pulse_input_capture'];
  // koder: z karty graficznej tego komputera (przeglądarka zna jej nazwę)
  function gpu() {
    try {
      const gl = document.createElement('canvas').getContext('webgl'); const x = gl && gl.getExtension('WEBGL_debug_renderer_info');
      const r = x ? gl.getParameter(x.UNMASKED_RENDERER_WEBGL) : '';
      if (/nvidia|geforce|rtx|gtx/i.test(r)) return { id: 'nvenc', name: 'NVIDIA NVENC', gpu: r };
      if (/amd|radeon/i.test(r)) return { id: 'amd', name: 'AMD (karta graficzna)', gpu: r };
      if (/intel/i.test(r)) return { id: 'qsv', name: 'Intel QuickSync', gpu: r };
      return { id: 'x264', name: 'procesor (x264)', gpu: r };
    } catch (e) { return { id: 'x264', name: 'procesor (x264)', gpu: '' }; }
  }
  const P = (obs, c, n) => obs.call('GetProfileParameter', { parameterCategory: c, parameterName: n }).then(r => r.parameterValue, () => null);
  const SETP = (obs, c, n, v) => obs.call('SetProfileParameter', { parameterCategory: c, parameterName: n, parameterValue: String(v) });

  async function micInput(obs) {
    const inputs = (await obs.call('GetInputList')).inputs || [];
    let sp = {}; try { sp = await obs.call('GetSpecialInputs'); } catch (e) {}
    const mics = inputs.filter(i => MIC_KINDS.includes(i.inputKind)).map(i => i.inputName);
    return (sp.mic1 && mics.includes(sp.mic1) ? sp.mic1 : '') || mics.find(n => n === 'VM · Mikrofon') || mics[0] || '';
  }

  async function check(obs, opts = {}) {
    const hub = opts.hub || 'http://localhost:7777';
    const out = [];
    // 1. obraz
    try {
      const v = await obs.call('GetVideoSettings'), fps = v.fpsNumerator / v.fpsDenominator;
      const ok = v.baseWidth === 1920 && v.baseHeight === 1080 && v.outputWidth === 1920 && v.outputHeight === 1080 && Math.abs(fps - 60) < 0.5;
      out.push({ id: 'video', title: 'Obraz 1920×1080, 60 kl./s', ok, idle: true, detail: ok ? 'tak jak trzeba' : `teraz ${v.baseWidth}×${v.baseHeight} → ${v.outputWidth}×${v.outputHeight}, ${Math.round(fps)} kl./s`,
        fix: async () => { await obs.call('SetVideoSettings', { baseWidth: 1920, baseHeight: 1080, outputWidth: 1920, outputHeight: 1080, fpsNumerator: 60, fpsDenominator: 1 }); return 'ustawione'; } });
    } catch (e) { out.push({ id: 'video', title: 'Obraz 1920×1080, 60 kl./s', ok: false, detail: 'OBS nie odpowiada: ' + e.message }); }

    // 2. scena «VM · Stream»
    try {
      const scenes = ((await obs.call('GetSceneList')).scenes || []).map(s => s.sceneName);
      const has = scenes.includes(STREAM);
      const items = has ? ((await obs.call('GetSceneItemList', { sceneName: STREAM })).sceneItems || []) : [];
      const names = items.slice().sort((a, b) => a.sceneItemIndex - b.sceneItemIndex).map(i => i.sourceName);
      const missing = SOURCES.filter(s => !s.optional && !names.includes(s.name)).map(s => s.name.replace('VM · ', ''));
      const order = SOURCES.map(s => names.indexOf(s.name)).filter(i => i >= 0), sorted = order.every((v, i) => !i || v > order[i - 1]);
      const ok = has && !missing.length && sorted;
      out.push({ id: 'scene', title: 'Scena „VM · Stream”', ok, detail: ok ? 'gra, ekrany, alerty i przejścia w dobrej kolejności' : !has ? 'nie ma jej – utworzę' : missing.length ? 'brakuje: ' + missing.join(', ') : 'źródła w złej kolejności (alerty muszą być nad grą)',
        fix: async () => {
          if (!(((await obs.call('GetSceneList')).scenes || []).some(s => s.sceneName === STREAM))) await obs.call('CreateScene', { sceneName: STREAM });
          const vs = await obs.call('GetVideoSettings');
          const all = ((await obs.call('GetInputList')).inputs || []).map(i => i.inputName);
          let cur = ((await obs.call('GetSceneItemList', { sceneName: STREAM })).sceneItems || []);
          for (const s of SOURCES) {
            if (cur.some(i => i.sourceName === s.name)) continue;
            if (s.optional && !all.includes(s.name)) continue;           // przechwytywanie gry dodaje kokpit/panel, gdy wykryje grę
            let id;
            if (all.includes(s.name)) id = (await obs.call('CreateSceneItem', { sceneName: STREAM, sourceName: s.name })).sceneItemId;
            else id = (await obs.call('CreateInput', { sceneName: STREAM, inputName: s.name, inputKind: s.kind, inputSettings: s.file ? { url: BASE + s.file, width: 1920, height: 1080, is_local_file: false, reroute_audio: !!s.audio, shutdown: false } : (s.settings || {}) })).sceneItemId;
            if (s.kind === 'browser_source') await obs.call('SetSceneItemTransform', { sceneName: STREAM, sceneItemId: id, sceneItemTransform: { positionX: 0, positionY: 0, boundsType: 'OBS_BOUNDS_STRETCH', boundsWidth: vs.baseWidth, boundsHeight: vs.baseHeight } });
          }
          // kolejność: od dołu do góry jak w SOURCES (reszta Twoich źródeł zostaje nad nimi)
          cur = ((await obs.call('GetSceneItemList', { sceneName: STREAM })).sceneItems || []);
          let idx = 0;
          for (const s of SOURCES) { const it = cur.find(i => i.sourceName === s.name); if (it) await obs.call('SetSceneItemIndex', { sceneName: STREAM, sceneItemId: it.sceneItemId, sceneItemIndex: idx++ }); }
          return 'scena gotowa';
        } });
    } catch (e) { out.push({ id: 'scene', title: 'Scena „VM · Stream”', ok: false, detail: 'OBS nie odpowiada: ' + e.message }); }

    // 3. mikrofon
    try {
      const mic = await micInput(obs);
      const f = mic ? ((await obs.call('GetSourceFilterList', { sourceName: mic })).filters || []).map(x => x.filterName) : [];
      const ok = !!mic && VOICE_FX.every(([n]) => f.includes(n));
      out.push({ id: 'mic', title: 'Mikrofon: czysty głos', ok, detail: !mic ? 'OBS nie ma mikrofonu – dodam „VM · Mikrofon”' : ok ? `„${mic}”: redukcja szumów → bramka → kompresor → limiter` : `„${mic}” bez filtrów – dodam redukcję szumów, bramkę, kompresor i limiter`,
        fix: async () => {
          let m = await micInput(obs);
          if (!m) { m = 'VM · Mikrofon'; await obs.call('CreateInput', { sceneName: STREAM, inputName: m, inputKind: 'wasapi_input_capture', inputSettings: { device_id: 'default' } }); }
          const have = ((await obs.call('GetSourceFilterList', { sourceName: m })).filters || []).map(x => x.filterName);
          for (let i = 0; i < VOICE_FX.length; i++) {
            const [n, kind, set] = VOICE_FX[i];
            if (!have.includes(n)) await obs.call('CreateSourceFilter', { sourceName: m, filterName: n, filterKind: kind, filterSettings: set });
            await obs.call('SetSourceFilterIndex', { sourceName: m, filterName: n, filterIndex: i });
          }
          return 'filtry na „' + m + '”';
        } });
    } catch (e) { out.push({ id: 'mic', title: 'Mikrofon: czysty głos', ok: false, detail: 'OBS nie odpowiada: ' + e.message }); }

    // 4. Twitch i klucz transmisji
    try {
      const sv = await obs.call('GetStreamServiceSettings'), st = sv.streamServiceSettings || {};
      const ok = sv.streamServiceType === 'rtmp_common' && /twitch/i.test(st.service || '') && !!st.key;
      out.push({ id: 'service', title: 'Transmisja na Twitcha', ok, idle: true, detail: ok ? 'Twitch, klucz ustawiony' : !/twitch/i.test(st.service || '') ? 'usługa to nie Twitch – ustawię Twitch z Twoim kluczem' : 'brak klucza transmisji – pobiorę go od Twitcha',
        fix: async () => {
          let j; try { j = await (await fetch(hub + '/twitch/streamkey', { cache: 'no-store' })).json(); } catch (e) { throw new Error('GameRadar nie odpowiada – klucz bierzemy od Twitcha przez niego'); }
          if (!j.ok) throw Object.assign(new Error(j.relogin ? 'zaloguj się ponownie do Twitcha (nowe uprawnienie: klucz transmisji)' : (j.error || 'Twitch odmówił')), { relogin: !!j.relogin });
          await obs.call('SetStreamServiceSettings', { streamServiceType: 'rtmp_common', streamServiceSettings: { service: 'Twitch', server: 'auto', key: j.key } });
          return 'Twitch z Twoim kluczem';
        } });
    } catch (e) { out.push({ id: 'service', title: 'Transmisja na Twitcha', ok: false, detail: 'OBS nie odpowiada: ' + e.message }); }

    // 5. wyjście: koder i bitrate pod Twitcha
    try {
      const g = gpu();
      const [mode, enc, vb, ab, sr] = await Promise.all([P(obs, 'Output', 'Mode'), P(obs, 'SimpleOutput', 'StreamEncoder'), P(obs, 'SimpleOutput', 'VBitrate'), P(obs, 'SimpleOutput', 'ABitrate'), P(obs, 'Audio', 'SampleRate')]);
      const simple = !mode || mode === 'Simple';
      const ok = simple && enc === g.id && +vb >= 5500 && +vb <= 6000 && +ab >= 160 && (!sr || +sr === 48000);
      out.push({ id: 'output', title: 'Jakość transmisji', ok, idle: true, restart: true,
        detail: ok ? `${g.name}, 6000 kb/s, dźwięk 160 kb/s, 48 kHz` : (simple ? '' : 'tryb zaawansowany wyjścia – przełączę na prosty · ') + `teraz: ${enc || '?'}, ${vb || '?'} kb/s → ${g.name}, 6000 kb/s, dźwięk 160 kb/s, 48 kHz`,
        fix: async () => {
          await SETP(obs, 'Output', 'Mode', 'Simple');
          await SETP(obs, 'SimpleOutput', 'StreamEncoder', g.id);
          await SETP(obs, 'SimpleOutput', 'VBitrate', 6000);
          await SETP(obs, 'SimpleOutput', 'ABitrate', 160);
          await SETP(obs, 'SimpleOutput', 'RecQuality', 'Stream');
          await SETP(obs, 'Audio', 'SampleRate', 48000);
          return 'zapisane – działa od następnego uruchomienia OBS';
        } });
    } catch (e) { out.push({ id: 'output', title: 'Jakość transmisji', ok: false, detail: 'OBS nie odpowiada: ' + e.message }); }
    return out;
  }

  // poprawka tylko poza transmisją/nagrywaniem dla rzeczy oznaczonych «idle»
  async function busy(obs) {
    try { const [a, b] = await Promise.all([obs.call('GetStreamStatus'), obs.call('GetRecordStatus')]); return a.outputActive ? 'trwa transmisja' : b.outputActive ? 'trwa nagrywanie' : ''; } catch (e) { return ''; }
  }

  window.VMObsSetup = { check, busy, VOICE_FX, STREAM, CAP, gpu };
})();
