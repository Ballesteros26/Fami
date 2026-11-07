// Textarea overlay syntax colors. The textarea remains the single editable input.
(() => {
  const escape = v => v.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  const tokenPattern = /("(?:[^"\\]|\\.)*"|#[A-Za-z][A-Za-z0-9_-]*|@[A-Za-z][A-Za-z0-9_+-]*|@[0-9]+|\$[A-Za-z][\w]*|\?[A-Za-z][\w]*|\b(?:[lLoOqQtTvVsSmMnNpP])[-+]?\d+(?:\.\d+)?|[a-gA-GrR][+#-]?(?:\d+|%\d+)?\.*)/g;
  function tokenKind(token) {
    return token.startsWith('"') ? 'string' : token.startsWith('#') ? 'header' :
      token.startsWith('$') || token.startsWith('?') ? 'macro' :
      token.startsWith('@') ? 'voice' : /^[a-grR]/.test(token) ? 'note' : 'command';
  }
  // Lexical comment state carries across newlines for /* ... */.
  // String literals take precedence, so comment delimiters inside quotes stay literal.
  function colorize(line, lineNumber, activeLines, activeNotes, playedLines, blockComment) {
    const noteColumns = activeNotes.get(lineNumber) || new Set();
    const active = activeLines.has(lineNumber) || noteColumns.size || playedLines.has(lineNumber);
    const track = /^[ \t]*([123Rr]{1,4})/.exec(line);
    const trackStart = track ? track[0].length - track[1].length : -1;
    const trackEnd = track ? track[0].length : -1;
    let out = '';
    function append(value, offset, kind) {
      if (!value) return;
      const cls = kind ? `mml-${kind}` : '';
      if (!active) {
        out += cls ? `<span class="${cls}">${escape(value)}</span>` : escape(value);
        return;
      }
      // Playback highlighting takes precedence over token coloring, as before.
      let contents = '';
      for (let i=0; i<value.length; i++) {
        const pos = offset+i;
        const playback = noteColumns.has(pos) ? 'ndp-playing-note' :
          track && pos>=trackStart && pos<trackEnd && activeLines.has(lineNumber) ? 'ndp-playing-track' :
          track && pos>=trackStart && pos<trackEnd && playedLines.has(lineNumber) ? 'ndp-played-track' : '';
        contents += playback ? `<span class="${playback}">${escape(value[i])}</span>` : escape(value[i]);
      }
      out += cls ? `<span class="${cls}">${contents}</span>` : contents;
    }
    function appendCode(value, offset) {
      tokenPattern.lastIndex = 0;
      let at = 0, match;
      while ((match = tokenPattern.exec(value))) {
        append(value.slice(at, match.index), offset+at);
        append(match[0], offset+match.index, tokenKind(match[0]));
        at = tokenPattern.lastIndex;
      }
      append(value.slice(at), offset+at);
    }
    let i=0, codeStart=0;
    while (i<line.length) {
      if (blockComment) {
        const end=line.indexOf('*/',i);
        if (end<0) { append(line.slice(i),i,'comment'); return {html:out,blockComment:true}; }
        append(line.slice(i,end+2),i,'comment');
        i=end+2; codeStart=i; blockComment=false;
        continue;
      }
      const ch=line[i];
      if (ch==='"') {
        // Skip a quoted string, including escaped quotes and comment characters.
        i++;
        while (i<line.length) {
          if (line[i]==='\\' && i+1<line.length) {i+=2;continue;}
          if (line[i++]==='"') break;
        }
        continue;
      }
      if (ch===';' || (ch==='/' && line[i+1]==='/')) {
        appendCode(line.slice(codeStart,i),codeStart);
        append(line.slice(i),i,'comment');
        return {html:out,blockComment:false};
      }
      if (ch==='/' && line[i+1]==='*') {
        appendCode(line.slice(codeStart,i),codeStart);
        blockComment=true;
        codeStart=i;
        continue;
      }
      i++;
    }
    if (blockComment) {
      // A /* was opened on this line but never closed.
      append(line.slice(codeStart),codeStart,'comment');
      return {html:out,blockComment:true};
    }
    appendCode(line.slice(codeStart),codeStart);
    return {html:out,blockComment:false};
  }
  // Save the current editor text in the browser, including an intentionally empty draft.
  // An explicit key keeps it separate from other browser applications.
  const draftKey = 'ndp-web:mml-draft:v1';
  const readDraft = () => {
    try { return localStorage.getItem(draftKey); } catch (_) { return null; }
  };
  let restoringShared = false;
  const saveDraft = value => {
    try { localStorage.setItem(draftKey, value); } catch (_) { /* Storage may be disabled. */ }
  };
  let tracking = null, enabled = true, autoScroll = true, scrollSuspended = false;
  let activeLines = new Set(), activeNotes = new Map(), playedLines = new Set();
  let lastPositions = [-1,-1,-1,-1], latestTime = 0;
  // The player may wrap its raw position for an infinite loop. Keep a separate
  // monotonic display/playback time so the global seek bar never has to choose
  // one track's @L position when tracks loop at different points.
  let playbackRawTime = 0, playbackTimeOffset = 0, playbackTimelineReady = false;
  let playbackHasAdvanced = false;
  let suppressLoopDetectionCount = 0;
  const findIndex = (events, time) => {
    let lo = 0, hi = events.length - 1, result = -1;
    while (lo <= hi) {const mid = (lo+hi)>>1; if (events[mid].time <= time) { result = mid; lo=mid+1; } else hi=mid-1;}
    return result;
  };
  function musicTimeFromReal(real) {
    const map = tracking?.realTimeMap;
    if (!map?.length) return real;
    const mapEnd = map[map.length-1];
    if (real > mapEnd) {
      // Slow-motion maps only cover the compiled first pass. After that, keep
      // absolute time moving instead of pinning every track to the final frame.
      return (map.length-1)/(tracking.fps||60) + (real-mapEnd);
    }
    let lo=0,hi=map.length-1;
    while(lo<hi){const mid=(lo+hi)>>1; if(map[mid] < real)lo=mid+1;else hi=mid;}
    return lo/(tracking.fps||60);
  }
  function formatPlaybackTime(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) seconds = 0;
    const whole = Math.floor(seconds);
    const minutes = Math.floor(whole / 60);
    const secs = whole % 60;
    return String(minutes).padStart(2,'0') + ':' + String(secs).padStart(2,'0');
  }
  function updatePlaybackTimeline(realSeconds) {
    realSeconds = Number.isFinite(realSeconds) ? Math.max(0, realSeconds) : 0;
    if (!playbackTimelineReady) {
      // The player can report a stale/pre-start position for a few callbacks when
      // playback is recreated. Use the first callback only as the new baseline.
      playbackRawTime = realSeconds;
      playbackTimelineReady = true;
    } else {
      const delta = realSeconds - playbackRawTime;
      if (delta > 0.05) playbackHasAdvanced = true;
      if (tracking?.loop && playbackHasAdvanced && suppressLoopDetectionCount <= 0 && delta < -0.25) {
        // Only a backward jump observed after real forward progress is a loop wrap.
        // Startup/seek position corrections therefore cannot inflate the timeline.
        playbackTimeOffset += -delta;
      }
    }
    if (suppressLoopDetectionCount > 0) suppressLoopDetectionCount--;
    playbackRawTime = realSeconds;
    const absolute = Math.max(0, realSeconds + playbackTimeOffset);

    // The player owns the global seek bar and play-time label.
    // This editor-side timeline is only for per-track playback highlighting.
    // Writing the same controls from here races with player.js on playback start.
    return absolute;
  }
  function resetPlaybackTimeline(realSeconds=0) {
    realSeconds = Number.isFinite(Number(realSeconds)) ? Math.max(0, Number(realSeconds)) : 0;
    playbackRawTime = realSeconds;
    playbackTimeOffset = 0;
    playbackTimelineReady = false;
    playbackHasAdvanced = false;
    // Playback recreation/seek may emit several stale callbacks. Ignore backward
    // loop detection until the new stream has settled, then require forward motion.
    suppressLoopDetectionCount = 12;
    // Do not touch the global seek bar/time label here; player.js owns them.
  }
  function seekFromInput(value) {
    const percent = Math.max(0, Math.min(100, Number(value) || 0));
    const target = (Math.max(0, Number(tracking?.duration) || 0) * percent) / 100;
    resetPlaybackTimeline(target);
    window.ndpPlayer?.seekFromInput?.(value);
  }
  function nudgePlayback(seconds) {
    // A deliberate rewind must not be mistaken for an automatic loop wrap.
    suppressLoopDetectionCount = Math.max(suppressLoopDetectionCount, 2);
    window.ndpPlayer?.nudge?.(seconds);
  }
  let scheduleRefresh = null;
  function requestRepaint() {
    if (scheduleRefresh) return;
    scheduleRefresh = requestAnimationFrame(() => {scheduleRefresh=null; render();});
  }
  function render() {
    const area=document.getElementById('ndp-editor');
    const highlight=document.getElementById('ndp-highlight');
    if (!area || !highlight) return;
    let blockComment = false;
    highlight.innerHTML = area.value.split('\n').map((line,i) => {
      const result = colorize(line,i+1,activeLines,activeNotes,playedLines,blockComment);
      blockComment = result.blockComment;
      return result.html;
    }).join('\n') + '\n';
    highlight.scrollTop=area.scrollTop;
    highlight.scrollLeft=area.scrollLeft;
  }
  function refreshPosition(realSeconds) {
    if (!tracking) return;
    latestTime = realSeconds;
    const absoluteRealSeconds = updatePlaybackTimeline(realSeconds);
    if (!enabled) return;
    const music = musicTimeFromReal(absoluteRealSeconds);
    const nextLines = new Set(), nextNotes = new Map();
    let scrollLine = -1;
    tracking.tracks.forEach((t,i) => {
      let time=music;
      if (tracking.loop && t.hasLoop && t.loopLength > 0 && time >= t.loopStart+t.loopLength)
        time=t.loopStart+((time-t.loopStart)%t.loopLength);
      const li=findIndex(t.lines,time);
      const ni=findIndex(t.notes,time);
      if (li>=0 && t.lines[li].line>0) {
        nextLines.add(t.lines[li].line);
        if (lastPositions[i]!==li) {
          lastPositions[i]=li;
          for (let j=0;j<li;j++) if(t.lines[j].line>0) playedLines.add(t.lines[j].line);
        }
        if (scrollLine<0 && i>0) scrollLine=t.lines[li].line;
      }
      if (ni>=0 && t.notes[ni].line>0 && t.notes[ni].column>=0) {
        if (!nextNotes.has(t.notes[ni].line)) nextNotes.set(t.notes[ni].line,new Set());
        nextNotes.get(t.notes[ni].line).add(t.notes[ni].column);
      }
    });
    activeLines=nextLines;activeNotes=nextNotes;
    const area=document.getElementById('ndp-editor');
    if (area && autoScroll && !scrollSuspended && scrollLine>0) {
      const height=parseFloat(getComputedStyle(area).lineHeight)||25;
      const y=(scrollLine-1)*height;
      if (y < area.scrollTop+height || y > area.scrollTop+area.clientHeight-height*3) area.scrollTop=Math.max(0,y-area.clientHeight/3);
    }
    requestRepaint();
  }
  function init() {
    const area=document.getElementById('ndp-editor');
    const highlight=document.getElementById('ndp-highlight');
    if (!area || !highlight || area.dataset.highlightBound) return;
    area.dataset.highlightBound='1';
    const repaint = render;
    area.addEventListener('input', () => { if (!restoringShared) saveDraft(area.value); clearTracking(); repaint(); });
    area.addEventListener('wheel', () => {scrollSuspended=true;}, {passive:true});
    area.addEventListener('pointerdown', () => {scrollSuspended=true;});
    area.addEventListener('keydown', e => {if (['ArrowUp','ArrowDown','PageUp','PageDown','Home','End'].includes(e.key))scrollSuspended=true;});
    // The editor uses Tab as a literal MML indentation character, not focus navigation.
    // Shift+Tab remains available for keyboard focus navigation.
    area.addEventListener('keydown', e => {
      if (e.key !== 'Tab' || e.shiftKey || e.ctrlKey || e.altKey || e.metaKey || e.isComposing) return;
      e.preventDefault();
      e.stopPropagation();
      const start = area.selectionStart;
      const end = area.selectionEnd;
      area.setRangeText('\t', start, end, 'end');
      // Notify the Blazor @bind:oninput model, draft saver and syntax highlighter.
      area.dispatchEvent(new Event('input', { bubbles: true }));
    });

    // Native textareas keep part of the horizontal offset when the caret is back at column 0.
    // Normalize that edge only; do not disturb ordinary horizontal navigation.
    const snapLeftAtLineStart = () => {
      const caret = area.selectionStart;
      const start = area.value.lastIndexOf('\n', Math.max(0, caret - 1)) + 1;
      if (caret <= start + 1 && area.scrollLeft > 0) {
        area.scrollLeft = 0;
        highlight.scrollLeft = 0;
      }
    };
    area.addEventListener('keyup', snapLeftAtLineStart);
    area.addEventListener('click', snapLeftAtLineStart);
    area.addEventListener('select', snapLeftAtLineStart);
    const draft = readDraft();
    if (draft !== null) {
      area.value = draft;
      // Keep the Blazor @bind="Mml" model in sync with the restored text.
      area.dispatchEvent(new Event('input', { bubbles: true }));
    }
    area.addEventListener('scroll', () => {highlight.scrollTop=area.scrollTop;highlight.scrollLeft=area.scrollLeft;});
    repaint();
  }
  function clearTracking() {tracking=null;activeLines=new Set();activeNotes=new Map();playedLines=new Set();lastPositions=[-1,-1,-1,-1];latestTime=0;requestRepaint();}
  document.addEventListener('DOMContentLoaded', init);

  // Matches Windows NDP's SetHelpWord mapping (NdpForm.Help.cs).
  const helpWords = {"#ADJUST-PI":"h_adjustpianoroll","#ADDRESS-D":"h_address-define","#ADDRESS_D":"h_address-define","#ADDRESSD":"h_address-define","#ADDRESS-S":"h_address-se","#ADDRESS_S":"h_address-se","#ADDRESSS":"h_address-se","#RHYTHM-A":"h_rhythm_atoz","#RHYTHM_A":"h_rhythm_atoz","#RHYTHMAT":"h_rhythm_atoz","#SCROLL-T":"h_scrolltrack","#SCROLL_T":"h_scrolltrack","#SCROLLTR":"h_scrolltrack","#EXPAND-M":"h_expandmemory","#EXPAND_M":"h_expandmemory","#EXPANDME":"h_expandmemory","#LOOP-PI":"h_looppianoroll","#RESET-V":"h_resetvib","#RESET-P":"h_resetpitchenv","#HENV-MO":"h_henv-mode","#HENV_MO":"h_henv-mode","#HENVMOD":"h_henv-mode","#SKIP-SE":"h_skipse","#SKIP_SE":"h_skipse","#SKIPSE":"h_skipse","#SKIP-D":"h_skipdefine","#SKIP_D":"h_skipdefine","#SKIPD":"h_skipdefine","#SKIP-F":"h_skipf","#SKIP_F":"h_skipf","#SKIPF":"h_skipf","#ARRA":"h_arranger","#COMP":"h_composer","#DEFA":"h_default-off","#FAST":"h_fast-forward","#JUMP":"h_jump-offset","#KEYS":"h_keyshift","#KEY-":"h_key-sign","#KEY_":"h_key-sign","#MEMO":"h_memo","#MUTE":"h_mute","#OCTA":"h_octave-rev","#PROG":"h_programmer","#RAND":"h_random-seed","#REPE":"h_repeat-mode","#RV-O":"h_rv-offset","#RV_O":"h_rv-offset","#SOLO":"h_solo","#SEEK":"h_seektime","#SHAR":"h_sharp-frame","#SEED":"h_seed","#TEMP":"h_tempo","#TRAC":"h_track-rev","#TIME":"h_timebase","#TRAN":"h_transpose","#TITL":"h_title","#V-OF":"h_v-offset","#V_OF":"h_v-offset","#INCL":"h_includevoice","#BSAV":"h_bsave","VI-":"viminus","VI+":"viplus","@RV":"at_rv","@RR":"at_rr","@RL":"at_rl","@RA":"at_ra","@RN":"at_rn","@RD":"at_rd","@FO":"at_fo","@RM":"at_rm","@D>":"at_d_f","@D+":"at_d_p","@D<":"at_d_b","@DR":"at_dr","@ON":"at_on","@OF":"at_off","@NO":"at_no","@MD":"at_md","@R:":"voicer","@Q%":"at_qmin","@Q+":"at_qplus","LA-":"la_minus","@AS":"arp_slur","@AR":"arp_rest","@QA":"at_qa","@QS":"_/quantizeseq/at_qs","@QM":"q_mode","P_K":"p_k","P_Q":"p_q","P_R":"p_r","P_W":"p_w","/*":"comment_multiline","*/":"comment_multiline","@F":"at_f","@I":"at_i","@L":"at_l","@T":"at_t","@Q":"at_q","@K":"at_k","@E":"_/voice2/at_voice","@-":"at_voiceoff","V+":"vplus","V-":"vminus","VO":"vo","VI":"viplus","KS":"ks","@P":"_/pitchenv/at_p","@M":"_/modulation/at_m","@N":"_/noteenv1/at_n","@A":"_/noteenv2/at_n","@R":"_/voicer/at_r","@D":"at_d","@C":"at_c","@G":"glissmode","M+":"mplus","M-":"mminus","L-":"lminus","LA":"la","MO":"mo","MC":"mnote","MD":"mnote","ME":"mnote","MF":"mnote","MG":"mnote","MA":"mnote","MB":"mnote","MKS":"_/henvseq/mkseq","MKA":"_/henvseq/mka","MK":"mk","VA":"va","VS":"_/volumeseq/vs","SS":"_/henvseq/ss","SA":"_/henvseq/sa","QA":"qa","QS":"_/quantizeseq/qs","M\\\\S":"_/henvseq/mdetuneseq","M\\\\A":"_/henvseq/mdetunea","M\\\\":"mdetune","J=":"j_str","TS":"ts","!S":"_/se_register/se","!A":"allsync","H-":"henv_harf","H+":"henv_unison","//":"comment","T":"t","C":"note","D":"note","E":"note","F":"note","G":"note","A":"note","B":"note","R":"sub/r","L":"l",".":"dot","^":"tie","&":"slur","(":"legato_on",")":"legato_off","+":"plus","-":"minus","=":"equal","#":"sharp","%":"percent","O":"o","<":"o_down",">":"o_up","Q":"q","@":"_/voice1/at_voice","V":"v","P":"p","_":"p2","[":"repeat","/":"sub/slash","]":"repeat","*":"mixmode","N":"n","~":"random","S":"s","M":"m","Y":"y","K":"k","J":"j","$":"_/macro/macroread","?":"_/stepmacro/stepmacroselect","X":"stepmacroread","{":"multiline","}":"multiline",":":"sub/colon","|":"bar",";":"comment","'":"sub/apos","\\\\S":"_/detuneseq/detune_s","\\\\A":"_/detuneseq/detune_a"};
  const helpKeys = Object.keys(helpWords).sort((a,b) => b.length-a.length);
  const helpBase = 'https://ndp.squares.net/web/help.html';
  function helpAnchorForCommand(token, definitionSide) {
    const word = token.toUpperCase();
    let key = helpKeys.find(k => word === k);
    if (!key && word.startsWith('#')) key = helpKeys.find(k => k.startsWith('#') && word.startsWith(k));
    if (!key) key = helpKeys.find(k => word.startsWith(k));
    if (!key) return null;
    let target = helpWords[key];
    if (target.startsWith('_/')) {
      const parts = target.split('/');
      target = definitionSide ? parts[1] : parts[2];
    }
    return target;
  }
  function getHelpLookupAtCaret() {
    const area = document.getElementById('ndp-editor');
    if (!area) return {url:helpBase, offset:0, character:"", token:"", anchor:null};
    const offset = area.selectionStart;
    const text = area.value;
    const lineStart = text.lastIndexOf('\n',Math.max(0,offset-1))+1;
    const lineEndFound = text.indexOf('\n',offset);
    const line = text.slice(lineStart,lineEndFound < 0 ? undefined : lineEndFound);
    const pos = offset-lineStart;
    // Preserve the previous heuristic without a redundant conditional.
    // Proper definition/use context requires the Windows MML parser; do not guess here.
    const definitionSide = pos < 3;
    // Inspect command tokens at the caret or immediately before its arguments.
    // Single-letter MML commands must not be swallowed into words (e.g. [vcde]).
    // Match special multi-letter commands first; notes and v/o/l remain separate.
    const pattern = /#[A-Za-z][\w-]*|@[A-Za-z][\w+<>%-]*|@[0-9]+|\\[A-Za-z]?|\/\*|\*\/|\/\/|(?:MKS|MKA|M\\S|M\\A|VI[+-]|LA-|@Q%|TS|VO|VI|KS|LA|MO|MC|MD|ME|MF|MG|MA|MB|MK|VA|VS|SS|SA|QA|QS|P_[KQRW]|H[+-]|J=)|[A-Za-z]|[^\s]/g;
    const matches = Array.from(line.matchAll(pattern));
    // At a boundary, the character to the right wins over the previous token.
    let chosen = matches.find(m=>m.index <= pos && pos < m.index+m[0].length);
    if (!chosen) chosen = matches.filter(m=>m.index+m[0].length <= pos).pop();
    if (!chosen) return {url:helpBase, offset, character:line[pos] || "", token:"", anchor:null};
    // When the caret sits on a command character (e.g. the 'o' in '[o4'),
    // use that character over the preceding '[' repeat delimiter.
    // This direct character check also avoids a fallback choosing a prior token.
    const caretCharacter = line[pos] || "";
    const caretToken = chosen[0];
    let anchor = helpAnchorForCommand(caretToken, definitionSide);
    if (caretCharacter && /^[A-Za-z]$/.test(caretCharacter) &&
        chosen.index === pos && caretToken.length === 1) {
      anchor = helpAnchorForCommand(caretCharacter, definitionSide);
    }
    // If caret is in a numeric argument, look back for the preceding command.
    if (!anchor) {
      const prior=matches.filter(m=>m.index < chosen.index && chosen.index-(m.index+m[0].length) <= 12).reverse();
      for (const m of prior) {
        if (m[0] === ',' || /^[-+0-9]/.test(m[0])) continue;
        anchor=helpAnchorForCommand(m[0],definitionSide);
        if (anchor) break;
      }
    }
    return {url:anchor ? helpBase+'#'+encodeURIComponent(anchor) : helpBase, offset, character:caretCharacter, token:caretToken, anchor};
  }
  function getHelpUrlAtCaret() { return getHelpLookupAtCaret().url; }
  function debugCaretHelp() { return getHelpLookupAtCaret(); }
  function openCaretHelp() {
    // Triggered by a direct click or F1 keydown, to keep popup blockers happy.
    window.open(getHelpUrlAtCaret(), 'ndp-online-help');
  }

  // Install F1 capture immediately when this script is parsed, before Blazor starts.
  // Opening a tab must happen synchronously in the key event (popup-blocker safe).
  window.addEventListener('keydown', event => {
    if (event.key === 'F1' || event.code === 'F1' || event.keyCode === 112) {
      if (event.ctrlKey || event.shiftKey || event.altKey || event.metaKey || event.repeat || event.isComposing) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      openCaretHelp();
    }
  }, true);

  let playbackShortcutHandler = null;
  function bindPlaybackShortcuts(dotNetRef) {
    if (playbackShortcutHandler) window.removeEventListener('keydown', playbackShortcutHandler, true);
    playbackShortcutHandler = (event) => {
      if (event.isComposing || event.altKey || event.metaKey) return;
      // F2/F4 intentionally accept auto-repeat; other shortcuts do not.
      const rewind = event.key === 'F2' || event.code === 'F2' || event.keyCode === 113;
      const forward = event.key === 'F4' || event.code === 'F4' || event.keyCode === 115;
      if ((rewind || forward) && !event.ctrlKey && !event.shiftKey) {
        event.preventDefault();
        event.stopImmediatePropagation();
        nudgePlayback(rewind ? -1 : 1);
        return;
      }
      if (event.repeat) return;
      const key = event.key;
      const code = event.code;
      const isF5 = key === 'F5' || code === 'F5' || event.keyCode === 116;
      const jumpFunction = /^(F[6-9]|F10)$/.test(key) ? Number(key.slice(1)) - 5
        : /^(F[6-9]|F10)$/.test(code) ? Number(code.slice(1)) - 5
        : event.keyCode >= 117 && event.keyCode <= 121 ? event.keyCode - 116 : 0;
      const isF3 = key === 'F3' || code === 'F3' || event.keyCode === 114;
      const isEscape = key === 'Escape' || code === 'Escape' || event.keyCode === 27;
      if (!isF5 && !isF3 && !isEscape && !jumpFunction) return;
      // Keep other Ctrl shortcuts (including Ctrl+R) under browser control.
      if ((isF3 || isEscape) && (event.ctrlKey || event.shiftKey)) return;
      if (jumpFunction && event.shiftKey) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      // Ctrl+F5: Windows NDP cursor solo play. Shift+F5: cursor play.
      // F3/Escape: stop. F5: compile and play from J0.
      const mode = jumpFunction ? `${event.ctrlKey ? "jump-solo" : "jump"}:${jumpFunction}` : (isF3 || isEscape) ? 'stop'
        : event.ctrlKey ? 'solo' : event.shiftKey ? 'cursor' : 'compile';
      dotNetRef.invokeMethodAsync('HandlePlaybackShortcut', mode).catch(console.error);
    };
    window.addEventListener('keydown', playbackShortcutHandler, true);
  }
  function unbindPlaybackShortcuts() {
    if (playbackShortcutHandler) window.removeEventListener('keydown', playbackShortcutHandler, true);
    playbackShortcutHandler = null;
  }
  window.ndpEditor = {
    init, clearTracking, bindPlaybackShortcuts, unbindPlaybackShortcuts, openCaretHelp, debugCaretHelp,
    getWordWrap() {
      try {
        const value = localStorage.getItem('ndp-online:word-wrap:v1');
        return value === null ? true : value === 'true';
      } catch (_) { return true; }
    },
    setWordWrap(enabled) {
      try { localStorage.setItem('ndp-online:word-wrap:v1', enabled ? 'true' : 'false'); } catch (_) {}
      requestRepaint();
    },
    loadSharedMml(content) {
      init();
      const area = document.getElementById('ndp-editor');
      if (!area) return;
      restoringShared = true;
      try {
        area.value = String(content);
        area.scrollTop = area.scrollLeft = 0;
        area.setSelectionRange(0, 0);
        // Propagate to Blazor without replacing the user's old local draft.
        area.dispatchEvent(new Event('input', { bubbles: true }));
      } finally { restoringShared = false; }
      render();
    },
    loadLocalMml(content) {
      init();
      const area = document.getElementById('ndp-editor');
      if (!area) return;
      area.value = String(content);
      area.scrollTop = area.scrollLeft = 0;
      area.setSelectionRange(0, 0);
      area.dispatchEvent(new Event('input', { bubbles: true }));
      render();
    },
    getCaretOffset() {return document.getElementById('ndp-editor')?.selectionStart ?? 0;},
    setTracking(tracks, loop, fps, realTimeMap, duration) {
      tracking={tracks,loop,fps,realTimeMap,duration};playedLines.clear();lastPositions=[-1,-1,-1,-1];scrollSuspended=false;
      latestTime=0;
      playbackRawTime=0;playbackTimeOffset=0;playbackTimelineReady=false;playbackHasAdvanced=false;suppressLoopDetectionCount=0;
      refreshPosition(0);
    },
    resetPlaybackTimeline, seekFromInput, nudgePlayback,
    setTrackingOptions(show, scroll) { enabled=!!show;autoScroll=!!scroll; if(!enabled){activeLines=new Set();activeNotes=new Map();playedLines.clear();requestRepaint();} else refreshPosition(latestTime);},
    updatePlaybackPosition: refreshPosition,
    refresh() {init();render();}
  };
})();
