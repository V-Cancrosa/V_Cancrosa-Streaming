const http = require('http'), crypto = require('crypto');
const PASS = 'tajne123', salt = 'saltSALT', challenge = 'chalCHAL';
const sha = s => crypto.createHash('sha256').update(s).digest('base64');
const expected = sha(sha(PASS + salt) + challenge);
let inputs=['Pulpit','Mikrofon/Aux','VM · Alerty','VM · Gra (automatycznie)'], sceneItems={}, items0=()=>items, streaming=false, muted={}, video={baseWidth:2560,baseHeight:1440,outputWidth:1280,outputHeight:720,fpsNumerator:30,fpsDenominator:1}, prof={'Output|Mode':'Advanced','SimpleOutput|StreamEncoder':'x264','SimpleOutput|VBitrate':'2500'}, svc={streamServiceType:'rtmp_custom',streamServiceSettings:{}}, filters=[], items=[{sourceName:'VM · Alerty',sceneItemId:2,sceneItemIndex:0},{sourceName:'VM · Scena',sceneItemId:1,sceneItemIndex:1}], scenes = ['VM · Stream', 'Gra', 'VM · Przygotowania', 'VM · Zaraz zaczynamy', 'VM · Przerwa', 'VM · Rozmowa', 'VM · Koniec'], current = 'Gra';
const clients = new Set();
function frame(str) { const p = Buffer.from(str); let h; if (p.length < 126) h = Buffer.from([0x81, p.length]); else if (p.length < 65536) { h = Buffer.alloc(4); h[0] = 0x81; h[1] = 126; h.writeUInt16BE(p.length, 2); } else { h = Buffer.alloc(10); h[0] = 0x81; h[1] = 127; h.writeBigUInt64BE(BigInt(p.length), 2); } return Buffer.concat([h, p]); }
function send(sock, op, d) { sock.write(frame(JSON.stringify({ op, d }))); }
const srv = http.createServer();
srv.on('upgrade', (req, sock) => {
  const key = req.headers['sec-websocket-key'];
  const acc = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  sock.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${acc}\r\n\r\n`);
  const c = { sock, ident: false }; clients.add(c);
  send(sock, 0, { obsWebSocketVersion: '5.5.0', rpcVersion: 1, authentication: { challenge, salt } });
  let buf = Buffer.alloc(0);
  sock.on('data', d => {
    buf = Buffer.concat([buf, d]);
    while (buf.length >= 2) {
      let len = buf[1] & 127, off = 2; if (len === 126) { len = buf.readUInt16BE(2); off = 4; } else if (len === 127) { len = Number(buf.readBigUInt64BE(2)); off = 10; }
      const masked = buf[1] & 128; if (buf.length < off + (masked ? 4 : 0) + len) break;
      const mask = masked ? buf.slice(off, off + 4) : null; off += masked ? 4 : 0;
      const pl = Buffer.from(buf.slice(off, off + len)); if (mask) for (let i = 0; i < pl.length; i++) pl[i] ^= mask[i % 4];
      const opc = buf[0] & 15; buf = buf.slice(off + len);
      if (opc === 8) { sock.end(); clients.delete(c); return; }
      const m = JSON.parse(pl.toString());
      if (m.op === 1) { if (m.d.authentication !== expected) { console.log('AUTH FAIL'); sock.end(); return; } c.ident = true; console.log('AUTH OK subs=' + m.d.eventSubscriptions); send(sock, 2, { negotiatedRpcVersion: 1 }); }
      if (m.op === 6) {
        let data = {}; const t = m.d.requestType; const rd = m.d.requestData || {};
        if (t === 'GetSceneList') data = { currentProgramSceneName: current, scenes: scenes.slice().reverse().map((n, i) => ({ sceneName: n, sceneIndex: i })) };
        if (t === 'GetInputList') data = { inputs: inputs.map(n => ({ inputName: n, inputKind: n === 'Pulpit' ? 'wasapi_output_capture' : n === 'Mikrofon/Aux' ? 'wasapi_input_capture' : n.includes('Gra (auto') ? 'window_capture' : 'browser_source' })) };
        if (t === 'GetStreamStatus') data = { outputActive: streaming, outputDuration: streaming ? 65000 : 0 };
        if (t === 'GetRecordStatus') data = { outputActive: false };
        if (t === 'StartStream' || t === 'StopStream') { streaming = t === 'StartStream'; console.log(t); setTimeout(() => { for (const x of clients) if (x.ident) send(x.sock, 5, { eventType: 'StreamStateChanged', eventIntent: 64, eventData: { outputActive: streaming } }); }, 50); }
        if (t === 'GetInputMute') data = { inputMuted: !!muted[m.d.requestData.inputName] };
        if (t === 'ToggleInputMute') { const n = m.d.requestData.inputName; muted[n] = !muted[n]; data = { inputMuted: muted[n] }; console.log('MUTE ' + n + ' ' + muted[n]); }
        if (t === 'GetCurrentProgramScene') data = { currentProgramSceneName: current };
        if (t === 'GetSourceScreenshot') data = { imageData: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' };
        if (t === 'GetSceneItemList') { const n = rd.sceneName; if (n === 'VM · Stream') data = { sceneItems: items }; else data = { sceneItems: (sceneItems[n] || []) }; }
        if (t === 'SetSceneItemEnabled') console.log('CAPTURE ' + m.d.requestData.sceneItemEnabled);
        if (t === 'CreateScene') { scenes.push(rd.sceneName); console.log('SCENE+', rd.sceneName); }
        if (t === 'GetVideoSettings') data = video;
        if (t === 'SetVideoSettings') { video = { ...video, ...rd }; console.log('VIDEO', JSON.stringify(rd)); }
        if (t === 'GetProfileParameter') data = { parameterValue: prof[rd.parameterCategory + '|' + rd.parameterName] ?? null };
        if (t === 'SetProfileParameter') { prof[rd.parameterCategory + '|' + rd.parameterName] = rd.parameterValue; console.log('PROF', rd.parameterCategory, rd.parameterName, rd.parameterValue); }
        if (t === 'GetStreamServiceSettings') data = svc;
        if (t === 'SetStreamServiceSettings') { svc = rd; console.log('SVC', rd.streamServiceSettings.service, rd.streamServiceSettings.key ? 'key-set' : 'no-key'); }
        if (t === 'GetSpecialInputs') data = { mic1: 'Mikrofon/Aux' };
        if (t === 'GetSourceFilterList') data = { filters: filters.map(f => ({ filterName: f })) };
        if (t === 'CreateSourceFilter') { filters.push(rd.filterName); console.log('FILTER', rd.filterName); }
        if (t === 'CreateInput' || t === 'CreateSceneItem') { const n = rd.sceneName, nm = rd.inputName || rd.sourceName; if (t === 'CreateInput') { inputs.push(nm); console.log('INPUT', nm, (rd.inputSettings.url||'').split('/').pop()); } const arr = n === 'VM · Stream' ? items : (sceneItems[n] = sceneItems[n] || []); const id = 100 + Math.floor(Math.random()*1e6); arr.push({ sourceName: nm, sceneItemId: id, sceneItemIndex: arr.length }); data = { sceneItemId: id }; }
        
        if (t === 'SetSceneItemIndex') { const items = rd.sceneName === 'VM · Stream' ? items0() : (sceneItems[rd.sceneName] || []); const it = items.find(i => i.sceneItemId === rd.sceneItemId); const others = items.filter(i => i !== it).sort((a,b)=>a.sceneItemIndex-b.sceneItemIndex); others.splice(rd.sceneItemIndex, 0, it); others.forEach((x, i) => x.sceneItemIndex = i); }
        if (t === 'SetCurrentProgramScene') { current = m.d.requestData.sceneName; console.log('SCENE -> ' + current); for (const x of clients) if (x.ident) send(x.sock, 5, { eventType: 'CurrentProgramSceneChanged', eventIntent: 4, eventData: { sceneName: current } }); }
        send(sock, 7, { requestType: t, requestId: m.d.requestId, requestStatus: { result: true, code: 100 }, responseData: data });
      }
    }
  });
  sock.on('error', () => clients.delete(c)); sock.on('close', () => clients.delete(c));
});
let t0 = Date.now();
setInterval(() => { const loud = Math.floor((Date.now() - t0) / 1500) % 2 === 0; const mic = loud ? 0.5 : 0.001;
  for (const c of clients) if (c.ident) send(c.sock, 5, { eventType: 'InputVolumeMeters', eventIntent: 65536, eventData: { inputs: [{ inputName: 'Pulpit', inputLevelsMul: [[0.2, 0.3, 0.3]] }, { inputName: 'Mikrofon/Aux', inputLevelsMul: [[mic, mic, mic], [mic, mic, mic]] }] } }); }, 50);
srv.listen(4455, '127.0.0.1', () => console.log('OBS mock on 4455'));
