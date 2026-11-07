// NDP Web 0.3 - libkss-js decoding + AudioWorklet PCM playback.
(() => {
  const RATE = 44100;
  let modulePromise, context, node, player, song;
  let currentGeneration = 0;
  let playing = false, preparing = false, seeking = false, ended = false;
  let duration = 0, position = 0, generated = 0, buffered = 0, underruns = 0;
  let infinityLoop = false;
  let refillTimer = null;
  // Coalesce repeated F2/F4 presses: decoder seeks are expensive and asynchronous.
  let nudgeTarget = null, nudgeTimer = null, nudgeBase = null;
  const clock = v => {
    const t = Math.max(0, Math.floor(Number.isFinite(v) ? v : 0));
    return `${String(Math.floor(t / 60)).padStart(2,'0')}:${String(t % 60).padStart(2,'0')}`;
  };
  function updateUI() {
    const seek = document.getElementById('ndp-seek');
    if (seek && !seek.matches(':active')) {
      seek.max = String(Math.max(0.001, duration));
      seek.value = String(Math.min(duration, position));
    }
    const time = document.getElementById('ndp-playtime');
    if (time) time.textContent = `${clock(position)} / ${clock(duration)}${infinityLoop ? ' (ループ)' : ''}`;
  }
  async function importLib() {
    modulePromise ??= import('https://esm.sh/libkss-js@2.2.1');
    const mod = await modulePromise;
    const api = mod.KSS && mod.KSSPlay ? mod : mod.default;
    if (!api?.KSS || !api?.KSSPlay) throw new Error('libkss-js APIを取得できません。');
    await api.KSSPlay.initialize();
    return api;
  }
  function base64Bytes(b64) {
    const raw = atob(b64), out = new Uint8Array(raw.length);
    for (let i=0; i<raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }
  function refill() {
    if (!player || !node || !playing || seeking || ended) return;
    // Decoder runs on main thread; limit each refill to prevent long stalls.
    let chunks = 0;
    while (buffered < RATE * 0.65 && chunks++ < 8) {
      const count = 4096;
      let samples;
      try { samples = player.calc(count); }
      catch (e) { console.error('NDP decode error', e); playing = false; break; }
      const pcm = new Float32Array(count);
      for (let i=0;i<count;i++) pcm[i] = (samples[i] || 0) / 32768;
      node.port.postMessage({type:'buffer',samples:pcm.buffer}, [pcm.buffer]);
      buffered += count;
      generated += count;
    }
  }
  async function ensureAudio() {
    if (context && context.state !== 'closed') {
      if (context.state !== 'running') await context.resume();
      return;
    }
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) throw new Error('このブラウザはWeb Audioに対応していません。');
    context = new Ctx({sampleRate:RATE});
    if (!context.audioWorklet) throw new Error('AudioWorkletが利用できません。HTTPSまたはlocalhostで開いてください。');
    await context.audioWorklet.addModule(new URL('ndp-audio-worklet.js', document.baseURI).href);
    node = new AudioWorkletNode(context, 'ndp-audio-processor', {numberOfInputs:0,numberOfOutputs:1,outputChannelCount:[1]});
    node.port.onmessage = ({data}) => {
      if (data.type !== 'progress') return;
      buffered = Math.max(0, data.buffered);
      underruns = data.underruns;
      position = data.played / RATE;
      if (!infinityLoop && duration > 0 && position >= duration && playing) {
        playing = false; ended = true; node.port.postMessage({type:'active', value:false});
      } else if (playing && !seeking) refill();
      updateUI();
      window.ndpEditor?.updatePlaybackPosition?.(position);
    };
    node.connect(context.destination);
    await context.resume();
  }
  function clearDecoder() {
    if (player) { player.release(); player = null; }
    if (song) { song.release(); song = null; }
  }
  function resetAudio(positionSamples = 0) {
    playing = false;
    if (node) node.port.postMessage({type:'reset',position:positionSamples});
    generated = positionSamples;
    buffered = 0;
    position = positionSamples/RATE;
    ended = false;
    updateUI();
    window.ndpEditor?.updatePlaybackPosition?.(position);
  }
  function flushNudge() {
    if (nudgeTimer !== null) { clearTimeout(nudgeTimer); nudgeTimer = null; }
    const target = nudgeTarget;
    nudgeTarget = null;
    if (target !== null) {
      nudgeBase = target;
      void window.ndpPlayer.seek(target).catch(console.error).finally(() => {
        if (nudgeTarget === null && nudgeBase === target) nudgeBase = null;
      });
    }
  }
  window.ndpPlayer = {
    // Called at the start of a user click, before WASM compilation.
    async unlock() { await ensureAudio(); },
    async play(base64, seconds, loop = false) {
      if (nudgeTimer !== null) { clearTimeout(nudgeTimer); nudgeTimer = null; }
      nudgeTarget = null; nudgeBase = null;
      const token = ++currentGeneration;
      preparing = true;
      resetAudio(); clearDecoder();
      try {
        await ensureAudio();
        const {KSS, KSSPlay} = await importLib();
        if (token !== currentGeneration) return;
        song = await KSS.createUniqueInstance(base64Bytes(base64),'ndp-web.kss');
        if (token !== currentGeneration) { song.release(); song = null; return; }
        player = new KSSPlay(RATE);
        player.setData(song);
        player.reset(null);
        duration = Math.max(0, Number(seconds) || 0);
        infinityLoop = !!loop;
        node.port.postMessage({type:'reset', position:0});
        playing = true;
        seeking = false;
        ended = false;
        refill();
        node.port.postMessage({type:'active',value:true});
        if (refillTimer) clearInterval(refillTimer);
        refillTimer = setInterval(() => { if (playing) refill(); }, 40);
        updateUI();
      } finally { preparing = false; }
    },
    async playFrom(base64, seconds, loop, startSeconds) {
      await this.play(base64, seconds, loop);
      const start=Math.min(Math.max(0,Number(startSeconds)||0),seconds);
      if (start>0) await this.seek(start);
    },
    async pause() {
      playing = false;
      if (node) node.port.postMessage({type:'active',value:false});
    },
    async resume() {
      if (!player) return;
      await ensureAudio();
      if (ended) await this.seek(0);
      playing = true;
      refill();
      node.port.postMessage({type:'active',value:true});
    },
    async stop() {
      if (nudgeTimer !== null) { clearTimeout(nudgeTimer); nudgeTimer = null; }
      nudgeTarget = null; nudgeBase = null;
      ++currentGeneration;
      seeking = false;
      resetAudio();
      clearDecoder();
      if (refillTimer) {clearInterval(refillTimer); refillTimer = null;}
      duration = 0;
      infinityLoop = false;
      updateUI();
    },
    async seek(seconds) {
      if (!player || !node || preparing) return;
      const token = ++currentGeneration;
      const wasPlaying = playing;
      seeking = true;
      resetAudio();
      player.reset(null);
      const destination = Math.floor(Math.min(duration,Math.max(0,Number(seconds)||0))*RATE);
      let remaining = destination;
      while (remaining > 0 && token === currentGeneration) {
        const n = Math.min(remaining, RATE);
        player.calcSilent(n);
        remaining -= n;
        await new Promise(resolve => setTimeout(resolve,0));
      }
      if (token !== currentGeneration) return;
      resetAudio(destination);
      seeking = false;
      playing = wasPlaying;
      if (playing) { refill(); node.port.postMessage({type:'active',value:true}); }
    },
    seekFromInput(value) { return this.seek(Number(value)); },
    // F2/F4: move by one second of music time for each keydown, including repeat.
    // Keep the accumulated target while key repeats, and decode only after a short pause.
    nudge(delta) {
      if (!player || !node || preparing || !(duration > 0)) return;
      const base = nudgeTarget ?? nudgeBase ?? position;
      nudgeTarget = Math.min(Math.max(0, base + delta), Math.max(0, duration - 0.1));
      if (nudgeTimer !== null) clearTimeout(nudgeTimer);
      nudgeTimer = setTimeout(flushNudge, 110);
    },
    flushNudge,
    focusError(line, fragment) {
      const input = document.getElementById('ndp-editor');
      if (!input || line < 1) return;
      const lines = input.value.split('\n');
      const index = Math.min(lines.length-1, Math.max(0, line-1));
      let offset = 0;
      for (let i=0;i<index;i++) offset += lines[i].length+1;
      const content = lines[index].replace(/\r$/, '');
      const hint = String(fragment || '').trim();
      let start = -1;
      if (hint && hint.length <= content.length) start = content.indexOf(hint);
      const a = offset + (start < 0 ? 0 : start);
      const b = offset + (start < 0 ? content.length : start + hint.length);
      input.focus(); input.setSelectionRange(a,b);
      // move textarea scroll so line is visible
      const computed = getComputedStyle(input);
      const lineHeight = parseFloat(computed.lineHeight) || 22;
      input.scrollTop = Math.max(0,index*lineHeight-input.clientHeight/3);
    },
    getState() { return { loaded: !!player, playing, position, duration, underruns }; }
  };
})();
