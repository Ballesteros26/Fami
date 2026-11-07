/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module seq.trackmap;
import main;
import com.fb;
import com.session;
import ui.ui;
import ui.input;
import derelict.sdl2.sdl;
import seq.sequencer;
import seq.tracktable;
import std.string : format;
import ct.base;
import std.array;
import ui.sequencecolors : SequenceColorLookup, buildSequenceColorLookupFromSong,
	setSequenceBarBackground, setSequenceDarkTintBarBackground;

class TrackmapVoice : TrackVoice {
	this(VoiceInitParams v) {		
		super(v);
	}

	override void update() {
		RowData wseq, cseq;
		int h = area.y + area.h + 1;
		int y,i;
		int trkofs = pos.trkOffset;
		int lasttrk = tracks.trackLength;
 		int counter;
		int scry = area.y + 1;
		SequenceColorLookup sequenceColors = buildSequenceColorLookupFromSong(song);

		void printEmpty() {
			screen.cprint(area.x - 1, scry, 1, 0, 
						  std.array.replicate(" ", 16));
		}
		
		void printTrack() {
			if(wseq.seq is null) return;
			int fpCounter = fplayPos.rowCounter;
			int delta = fpCounter - counter; 
			int fgcol = (delta >= 0 && delta < wseq.seq.rows) ? 13 : 5;
			int trk = wseq.trk.smashedValue;
			int rows = wseq.seq.rows;
			int c = counter;
			if(scry == area.y + 1 + anchor) fgcol = 1;
			if(wseq.trk.trans >= 0xf0) {
				rows = 0;
				c = 0;
			}
			screen.fprint(area.x-1, scry, 
					   format(" `01%s `0%x%02X %04X  ", 
							  formatTrackValue(trk), fgcol,
							  rows, c));
			if(wseq.trk.smashedValue < 0xf000)
				setSequenceBarBackground(screen, area.x, scry, 13,
					sequenceColors, wseq.trk.number);
			if(trkofs == pos.mark) {
				for(int i = 0; i < 13; i++) {
					int xpos = area.x + i;
					if(screen.getbg(xpos, scry) == 0)
						setSequenceBarBackground(screen, xpos, scry, 1,
							sequenceColors, wseq.trk.number, playbackBarColor);
				}
			}
			if(trkofs == tracks.wrapOffset) {
				for(int i = 0; i < 15; i++) {
					int xpos = area.x + i - 1;
					if(screen.getbg(xpos, scry) == 0)
						setSequenceDarkTintBarBackground(screen, xpos, scry, 1,
							sequenceColors, wseq.trk.number, wrapBarColor);
				}
			}
		}
		trkofs -= seq.sequencer.anchor;
		counter = getRowcounter(trkofs);

		if(trkofs >= 0)
			wseq = getRowData(trkofs);
		y = area.y + 1;

		while(scry <= area.y + area.height) {
			if(trkofs < 0) {
				printEmpty();
				scry++;
			}
			else if(trkofs >= lasttrk+1) {
				printEmpty();
				scry++; trkofs++;
				continue;
			}
			else {
				printTrack(); 
				if(wseq.seq !is null)
					counter += wseq.seq.rows;
				scry++;
			}
			trkofs++;
			if(trkofs >= 0 && trkofs <= lasttrk) {
				wseq = getRowData(trkofs, 0);
			}
		}
	}
}

class TrackmapTable : BaseTrackTable {
	this(Rectangle a, PosDataTable pi) {
		int x = 5 + com.fb.border + a.x;
		for(int v=0;v<3;v++) {
			Rectangle na = Rectangle(x, a.y, a.height, 13 + com.fb.border);
			x += 13 + com.fb.border;
			voices[v] = new TrackmapVoice(VoiceInitParams(song.tracks[v],
														  na, pi.pos[v], this));
		}
		super(a, pi); 
	}

	override void activate() {
		super.activate();
		// FIX: scroll the screen to center, don't just set the offset vars
		centralize();
	}

	bool clickTargetAtLocalPoint(int x, int y, out int voice,
			out int trackIndex) {
		voice = voiceAtLocalX(x);
		trackIndex = -1;
		if(voice < 0)
			return false;

		Voice v = voices[voice];
		if(v is null)
			return false;

		int row = y - 1;
		trackIndex = v.pos.trkOffset + row - seq.sequencer.anchor;
		return trackIndex >= 0;
	}

	private bool isTrackmapStructuralEditKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(resolveTrackEntryStructuralKeyboardAction(key, actionId))
			return true;
		return isTrackEntryInsertShortcut(key) ||
			isTrackEntryInsertCopyShortcut(key) ||
			isTrackEntryDeleteShortcut(key);
	}

	private bool normalizeTrackmapStructuralEditCursor() {
		if(activeVoiceNum < 0 || activeVoiceNum >= cast(int)voices.length)
			return false;

		auto v = cast(TrackVoice)voices[activeVoiceNum];
		if(v is null || v.trackinput is null)
			return false;

		int trackIndex = v.pos.trkOffset;
		if(trackIndex < 0 || trackIndex >= v.tracks.trackLength)
			return false;

		Track track = v.tracks[trackIndex];
		if(track.trans >= 0xf0)
			return false;

		return selectTrackEntryAt(activeVoiceNum, trackIndex);
	}

	private bool handleTrackmapHomeEndKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveTrackEntryNavigationKeyboardAction(key, actionId))
			return false;
		switch(actionId) {
		case KeyboardActionId.trackEntryNavigateStart:
			selectTrackmapBoundary(false);
			return true;
		case KeyboardActionId.trackEntryNavigateEnd:
			selectTrackmapBoundary(true);
			return true;
		default:
			return false;
		}
	}

	private bool selectTrackmapBoundary(bool end) {
		if(activeVoiceNum < 0 || activeVoiceNum >= cast(int)voices.length)
			return false;

		auto v = cast(TrackVoice)voices[activeVoiceNum];
		if(v is null || v.trackinput is null)
			return false;

		int targetTrackIndex = -1;
		if(end) {
			for(int i = v.tracks.trackLength - 1; i >= 0; i--) {
				if(v.tracks[i].trans < 0xf0) {
					targetTrackIndex = i;
					break;
				}
			}
		}
		else {
			for(int i = 0; i < v.tracks.trackLength; i++) {
				if(v.tracks[i].trans < 0xf0) {
					targetTrackIndex = i;
					break;
				}
			}
		}

		if(targetTrackIndex < 0)
			return false;
		return selectTrackEntryAt(activeVoiceNum, targetTrackIndex);
	}

	private bool isValidTrackmapEntry(TrackVoice v, int trackIndex) {
		return v !is null &&
			trackIndex >= 0 &&
			trackIndex < v.tracks.trackLength &&
			v.tracks[trackIndex].trans < 0xf0;
	}

	private int firstValidTrackmapEntry(TrackVoice v) {
		if(v is null)
			return -1;
		for(int i = 0; i < v.tracks.trackLength; i++) {
			if(isValidTrackmapEntry(v, i))
				return i;
		}
		return -1;
	}

	private int lastValidTrackmapEntry(TrackVoice v) {
		if(v is null)
			return -1;
		for(int i = v.tracks.trackLength - 1; i >= 0; i--) {
			if(isValidTrackmapEntry(v, i))
				return i;
		}
		return -1;
	}

	private int trackmapPageStep() {
		int pageStep = seq.sequencer.PAGESTEP * song.highlight;
		return pageStep > 0 ? pageStep : 1;
	}

	private int nearestTrackmapEntryAtPageTarget(TrackVoice v,
			int targetTrackIndex, int direction) {
		if(direction < 0) {
			for(int i = targetTrackIndex; i >= 0; i--) {
				if(isValidTrackmapEntry(v, i))
					return i;
			}
			return firstValidTrackmapEntry(v);
		}

		for(int i = targetTrackIndex; i < v.tracks.trackLength; i++) {
			if(isValidTrackmapEntry(v, i))
				return i;
		}
		return lastValidTrackmapEntry(v);
	}

	private bool selectTrackmapPage(int direction) {
		if(direction != -1 && direction != 1)
			return false;
		if(activeVoiceNum < 0 || activeVoiceNum >= cast(int)voices.length)
			return false;

		auto v = cast(TrackVoice)voices[activeVoiceNum];
		if(v is null || v.trackinput is null)
			return false;

		int first = firstValidTrackmapEntry(v);
		int last = lastValidTrackmapEntry(v);
		if(first < 0 || last < 0)
			return false;

		int current = v.pos.trkOffset;
		if(!isValidTrackmapEntry(v, current))
			current = direction < 0 ? last : first;

		int target = current + direction * trackmapPageStep();
		if(target <= first)
			target = first;
		else if(target >= last)
			target = last;
		else
			target = nearestTrackmapEntryAtPageTarget(v, target, direction);

		if(target < 0)
			return false;
		return selectTrackEntryAt(activeVoiceNum, target);
	}

	private bool handleTrackmapPageKey(Keyinfo key) {
		if(key.mods != 0)
			return false;

		switch(key.raw) {
		case SDLK_PAGEUP:
			selectTrackmapPage(-1);
			return true;
		case SDLK_PAGEDOWN:
			selectTrackmapPage(1);
			return true;
		default:
			return false;
		}
	}

	private void resetTrackmapVoiceToTop(int voice, out int firstValidEntry) {
		firstValidEntry = -1;
		if(voice < 0 || voice >= cast(int)voices.length)
			return;

		auto v = cast(TrackVoice)voices[voice];
		if(v is null || v.trackinput is null)
			return;

		firstValidEntry = firstValidTrackmapEntry(v);
		int targetTrackIndex = firstValidEntry >= 0 ? firstValidEntry : 0;
		if(v.tracks.trackLength <= 0)
			return;

		v.pos.trkOffset = targetTrackIndex;
		v.pos.seqOffset = 0;
		v.pos.rowCounter = v.getRowcounter(targetTrackIndex);
		v.refreshPointer(0);
		v.trackinput.refresh(v.activeRow);
	}

		override int keypress(Keyinfo key) {
			if(handleTrackmapPageKey(key))
				return OK;
			if(handleTrackmapHomeEndKey(key))
				return OK;
			if(isTrackmapStructuralEditKey(key) &&
					!normalizeTrackmapStructuralEditCursor())
				return OK;
			return super.keypress(key);
		}

		
	// centerTo() & jump() (?) do not work with this!
	override void step(int st) { step(st,0); }
	override void step(int st, int extra) {
		int steps, rows;
		RowData s;
		activeVoice.trackFlush(posTable.pointerOffset);
		if(st > 0) {
			if(activeVoice.atEnd()) return;
			rows = activeVoice.activeRow.seq.rows;
			foreach(v; voices) {
				v.scroll(rows, true);
			}
		}
		else if(st < 0) {
			int t = activeVoice.pos.trkOffset-1;
			if(t < 0) t = activeVoice.tracks.trackLength-1;
			
			s = activeVoice.getRowData(t,0);
			rows = s.seq.rows;
			foreach(v; voices) {
				v.scroll(-rows);
			}
		}
		super.refresh();
	}

	override void toSeqStart() {
		posTable.pointerOffset = 0;

		int preferredVoice = activeVoiceNum;
		if(preferredVoice < 0 || preferredVoice >= cast(int)voices.length)
			preferredVoice = 0;

		int selectedVoice = -1;
		int selectedTrackIndex = -1;
		foreach(int voice, v; voices) {
			int firstValidEntry;
			resetTrackmapVoiceToTop(voice, firstValidEntry);
			if(firstValidEntry < 0)
				continue;
			if(voice == preferredVoice || selectedVoice < 0) {
				selectedVoice = voice;
				selectedTrackIndex = firstValidEntry;
			}
		}

		if(selectedVoice >= 0 &&
				selectTrackEntryAt(selectedVoice, selectedTrackIndex))
			return;

		activeVoiceNum = preferredVoice;
		activeVoice = voices[activeVoiceNum];
		if(activeVoice !is null && activeVoice.activeInput !is null)
			input = activeVoice.activeInput;
		refresh();
	}
}
