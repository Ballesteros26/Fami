/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module seq.sequencer;
import main;
import com.fb;
import ui.ui, ui.help;
import ct.base;
import com.session;
import com.util;
import ui.input;
import ui.dialogs;
import seq.fplay;
import seq.trackoverview : TrackOverviewBlock, TrackOverviewLane,
	TrackOverviewCursorIdentity, TrackOverviewOccurrence,
	TrackOverviewPosition, buildTrackOverview, resolveTrackOverviewPositions,
	trackOverviewCursorIdentityAtGlobalRow,
	trackOverviewGlobalRowForCursorIdentity,
	trackOverviewGlobalRowForOccurrence, trackOverviewOccurrenceAtGlobalRow;
import seq.tracktable;
import seq.seqtable;
import seq.trackmap;
import derelict.sdl2.sdl;
import std.string;
import std.stdio;
import audio.audio, audio.player;
import audio.seekmanager : timelineSeekManager;

enum PAGESTEP = 2;
enum Jump { toBeginning = 0, toMark = -1, toEnd = -2, toWrapMark = -3 };
enum int SEQUENCE_ROW_DRAG_AUTOSCROLL_INTERVAL_TICKS = 4;
enum int SEQUENCE_ROW_DRAG_AUTOSCROLL_MARGIN_ROWS = 4;
enum int SUBTUNE_SELECTOR_VALUE_X_OFFSET = 2;
enum int SUBTUNE_SELECTOR_VALUE_WIDTH = 2;

struct SubtuneSelectionDecision {
	bool valid;
	bool changed;
	int target;
}

SubtuneSelectionDecision subtuneSelectionDecision(int current,
		int target) pure nothrow {
	if(target < 0 || target >= SUBTUNE_MAX)
		return SubtuneSelectionDecision(false, false, current);
	return SubtuneSelectionDecision(true, target != current, target);
}

int wrappedSubtuneTarget(int current, int delta) pure nothrow {
	int target = (current + delta) % SUBTUNE_MAX;
	if(target < 0)
		target += SUBTUNE_MAX;
	return target;
}

bool subtuneSelectorValueCellAt(int areaX, int areaY, int x,
		int y) pure nothrow {
	return y == areaY && x >= areaX + SUBTUNE_SELECTOR_VALUE_X_OFFSET &&
		x < areaX + SUBTUNE_SELECTOR_VALUE_X_OFFSET +
			SUBTUNE_SELECTOR_VALUE_WIDTH;
}

enum SequenceRowDragAutoScrollDirection {
	none,
	up,
	down
}

enum SequenceOriginDestination {
	none,
	instrument,
	command,
	pulse,
	filter,
	chord
}

enum playbackBarColor = 6;
enum wrapBarColor = 4;

bool displaySequenceRowcounter = true;
int stepValue = 1;
int activeVoiceNum;
private int stepCounter;

int tableTop = 15, tableBot = -16;
enum anchor = 16;
Clip[] clip;

private {
	bool useRelativeNotes = true;
}

int sequenceMovementMarginForHeight(int height) {
	return height > 10 ? SEQUENCE_ROW_DRAG_AUTOSCROLL_MARGIN_ROWS : 1;
}

int sequenceTopAllowedVisibleRowForHeight(int height) {
	return sequenceMovementMarginForHeight(height);
}

int sequenceBottomAllowedVisibleRowForHeight(int height) {
	int bottom = height - 1 - sequenceMovementMarginForHeight(height);
	int top = sequenceTopAllowedVisibleRowForHeight(height);
	return bottom < top ? top : bottom;
}

SequenceRowDragAutoScrollDirection sequenceRowDragAutoScrollDirectionForRow(
		int visibleRow, int visibleRows) {
	if(visibleRow < 0 || visibleRow >= visibleRows)
		return SequenceRowDragAutoScrollDirection.none;
	if(visibleRow < sequenceTopAllowedVisibleRowForHeight(visibleRows))
		return SequenceRowDragAutoScrollDirection.up;
	if(visibleRow > sequenceBottomAllowedVisibleRowForHeight(visibleRows))
		return SequenceRowDragAutoScrollDirection.down;
	return SequenceRowDragAutoScrollDirection.none;
}

bool advanceSequenceRowDragAutoScrollCadence(ref int accumulator) {
	accumulator++;
	if(accumulator < SEQUENCE_ROW_DRAG_AUTOSCROLL_INTERVAL_TICKS)
		return false;
	accumulator = 0;
	return true;
}

struct RowData {
	Track trk; 
	alias trk track;
	// offset in tracklist, checked against endmark
	int trkOffset; 
	// offset in tracklist, not checked
	int trkOffset2;
	int seqOffset;
	Sequence seq; // full sequence, cursor is at seq[seqOffset]
	//Sequence clipped; // clipped sequence, from cursor downwards
	int clippedRows;
	Element element; // data entry under cursor
}

struct VoiceInitParams {
	Tracklist t;
	Rectangle a;
	PosData p;
	VoiceTable voiceTable;
}

class PosData {
	int pointerOffsetValue = anchor;
	int trkOffset = 0;
	int seqOffset;
	int mark; 
	int rowCounter;
	Tracklist tracks;

	@property int pointerOffset() {
		return pointerOffsetValue - anchor;
	}
	
	@property int pointerOffset(int i) {
		return pointerOffsetValue = i + anchor;
	}
	
	@property int rowOnCursor() {
		return seqOffset + pointerOffset;
	}
	
	int getRowCounter() {
		int counter;
		for(int i = 0; i <= trkOffset; i++) {
			Track t = tracks[i];
			counter += song.sequence(t).rows;
		}
		return counter + seqOffset;
	}
	
}

class PosDataTable {
	PosData[] pos;

	PosData opIndex(int idx) {
		return pos[idx];
	}

	this() {
		pos.length = 3;
		foreach(ref p; pos) p = new PosData;
	}
	
	@property int pointerOffset(int o) { 
		foreach(ref p; pos) { p.pointerOffset = o; }
		return 0;
	}
	
	@property int pointerOffset() {
		return pos[0].pointerOffset;
	}
	
	@property int normalPointerOffset() { 
		int r = tableTop + pos[0].pointerOffset;
		return r;
	}
			
	@property int rowCounter() { 
		return pos[0].rowCounter; 
	}
	
	@property int rowCounter(int o) { 
		foreach(ref p; pos) { p.rowCounter = o; }
		return 0;
	}

	PosDataTable dup() {
		auto pt = new PosDataTable();
		pt.copyFrom(this);
		return pt;
	}
	
	void copyFrom(PosDataTable pt) {
		for(int i = 0 ; i < 3; i++) {
			PosData p = pos[i];
			PosData t = pt[i];
			p.pointerOffset = t.pointerOffset;
			p.seqOffset = t.seqOffset;
			p.trkOffset = t.trkOffset;
			p.rowCounter = t.rowCounter;
			p.mark = t.mark;
		}
	}
}

void initializeSubtunePositionAtSongStart(PosDataTable position,
		int viewHeight) {
	if(position is null)
		return;
	int pointer = sequenceTopAllowedVisibleRowForHeight(viewHeight) - anchor;
	position.pointerOffset = pointer;
	foreach(pos; position.pos) {
		pos.trkOffset = 0;
		pos.seqOffset = -pointer;
		pos.rowCounter = -pointer;
		pos.mark = 0;
	}
}

// ------------------------------------------------------------------------
// ------------------------------------------------------------------------

abstract class Voice : Window {
	Tracklist tracks;
	PosData pos;
	RowData activeRow;
	Input input;
	alias input activeInput;
	VoiceTable parent;
	
	this(ref VoiceInitParams v) {
		super(v.a);
		tracks = v.t; pos = v.p;
		parent = v.voiceTable;
	}

public:

	bool atBeg() { 
		return pos.trkOffset <= 0
			&& (pos.seqOffset + pos.pointerOffset) <= 0;
	}

	bool atEnd() {
		RowData s = getRowData(pos.trkOffset, 
									   pos.seqOffset + pos.pointerOffset);
		return (s.trk.trans >= 0xf0);
	}
	
	bool pastEnd() { return pastEnd(0); }
	
	bool pastEnd(int y) {
		RowData s = getRowData(pos.trkOffset,
							   pos.seqOffset + y);
		int t = s.trkOffset2 - 1;
		if(t < 0) return false;
		Track trk = tracks[t];
		return (trk.trans >= 0xf0);
	}

	void trackFlush(int y) { return; }

	override void refresh() { refreshPointer(0); }
		
		RowData getRowData(int trkofs, int seqofs) {
			static RowData s;
			int trkofs2 = trkofs;
			Sequence seq;
			int lasttrk = tracks.trackLength;
			Sequence getSeq(Track t) {
				if(t.trans >= 0xf0) return song.seqs[0];
				else return song.seqs[t.number];
		}
		int numRowsInSeq() {
				if(tracks[trkofs2].trans >= 0xf0)
					return 1;
				return getSeq(tracks[trkofs2]).rows;
				}

				if(trkofs > lasttrk) trkofs = lasttrk;
				s.trk = tracks[trkofs];

			seq = getSeq(s.trk);

		while (seqofs < 0)  {
			seqofs += numRowsInSeq();
			if(--trkofs < 0) {
				trkofs = 0;
				seqofs = 0;
				break;
			}
			--trkofs2;
			s.trk = tracks[trkofs];
			seq = song.seqs[s.trk.number];
		} 
		assert(seqofs >= 0);

			while(seqofs >= numRowsInSeq()) {
				seqofs -= numRowsInSeq();
				if(trkofs < lasttrk)
					trkofs++;
				trkofs2++;
				s.trk = tracks[trkofs2];
				seq = getSeq(s.trk);
			}
		s.seqOffset = seqofs;
		s.clippedRows = seq.rows - seqofs;
		s.trkOffset = trkofs;
		s.trkOffset2 = trkofs2;
		s.element = seq.data[seqofs];
		if(useRelativeNotes) {
			int t = trkofs;
			while(t >= 0 && tracks[t].trans == 0x80) t--;
			if(t >= 0)
				s.element.transpose = tracks[t].trans - 0xa0;
		}
		s.seq = seq;
		return s;
	}
	
	RowData getRowData(int tofs) {
		return getRowData(tofs, 0);
	}

	void scroll(int steps) {
		scroll(steps, true);
	}

 	void scroll(int steps, bool canWrap) {
		int oldRowcounter;
		RowData s = getRowData(pos.trkOffset);
		assert(s.seq.rows == s.clippedRows);
		with(pos) {
			seqOffset = seqOffset + steps;
			oldRowcounter = rowCounter;
			rowCounter += steps;
			while(seqOffset + pointerOffset < 0) {
				if(--trkOffset < 0) {
					if(canWrap) {
						trkOffset = tracks.trackLength - 1;
						rowCounter = getRowCounter();
					}
					else trkOffset = 0;
				} 
				s = getRowData(trkOffset);
				seqOffset += s.clippedRows;
				steps += s.clippedRows;
			}
			while(seqOffset + pointerOffset >= s.clippedRows) {
				seqOffset -= s.clippedRows;
				steps -= s.clippedRows;
				if(++trkOffset >= tracks.trackLength) {
					if(canWrap) {
						trkOffset = 0;
						rowCounter = seqOffset;
					}
					else { 
						trkOffset = tracks.trackLength - 1; 
						rowCounter = oldRowcounter;
					}
				}
				s = getRowData(trkOffset);
			}
		}
	}

	// TODO: move elsewhere...
	int getRowcounter(int trkofs) {
		int counter = 0;
		for(int i = 0; i < trkofs; i++) {
			Track t = tracks[i];
			counter += song.sequence(t).rows;
		}
		return counter;
	}


protected:
	
	override void update();
	
	void refreshPointer() {
		refreshPointer(pos.pointerOffset);
	}
	
	void refreshPointer(int y);

	void jump(int jumpto) {
		if(jumpto == Jump.toMark) jumpto = pos.mark;
		else if(jumpto == Jump.toWrapMark) jumpto = tracks.wrapOffset;
		assert(jumpto >= 0);
		pos.trkOffset = jumpto;
		pos.seqOffset = 0;
		pos.rowCounter = getRowcounter(jumpto);
	}    

	void setMark() {
		setMark(1);
	}
	
	// when m == 1, sets mark to current trkOffsets
	// when m == 0, zeroes it out
	void setMark(int m) {
		pos.mark = m ? activeRow.trkOffset : 0;
	}
	alias setMark setPositionMark;

	void setWrapMark() {
		tracks.wrapOffset = cast(ushort) (activeRow.trkOffset);
	}

	string formatTrackValue(int trknum) {
		if(trknum >= 0xf000)
			return "LOOP";
		return format("%04X", trknum);
	}
}

abstract class VoiceTable : Window {
	Voice[3] voices;
	Voice active;
	alias active activeVoice;
	PosDataTable posTable;
	
	this(Rectangle a, PosDataTable pi) {
		super(a);
		posTable = pi;
		activeVoice = voices[0];
	}

	override void activate() {
		activeVoice = voices[activeVoiceNum];
		input = activeVoice.activeInput;
		refresh();
	}

	override void deactivate() {
		activeVoice.trackFlush(posTable.pointerOffset);
	}

	override void refresh() {
		foreach(v; voices) {
			v.refresh(); 
		}
	}

	void centralize() {
		jump(activeVoice.activeRow.trkOffset,true);
	}

	private bool handleSequencerConfigAction(KeyboardActionId actionId) {
		switch(actionId) {
		case KeyboardActionId.sequencerHighlightIncrease:
			if(song.highlight < 16)
				song.highlight++;
			return true;
		case KeyboardActionId.sequencerHighlightDecrease:
			if(song.highlight > 1)
				song.highlight--;
			return true;
		case KeyboardActionId.sequencerRowCountersToggle:
			displaySequenceRowcounter ^= 1;
			return true;
		case KeyboardActionId.sequencerRelativeNotesToggle:
			useRelativeNotes ^= 1;
			UI.statusline.displayOperationFeedback(format("Relative notes %s.",
				useRelativeNotes ?  "enabled" : "disabled"));
			return true;
		case KeyboardActionId.sequencerHighlightOffsetSet:
			song.highlightOffset = posTable.rowCounter + posTable.pointerOffset;
			refresh();
			UI.statusline.displayOperationFeedback("Highlight offset set.");
			return true;
		case KeyboardActionId.sequencerPlaybackMarkSet:
			setPositionMark();
			refresh();
			return true;
		case KeyboardActionId.sequencerPlaybackMarkJump:
			jump(Jump.toMark, true);
			return true;
		case KeyboardActionId.sequencerPlaybackMarkCenter:
			centralize();
			return true;
		default:
			return false;
		}
	}

	override int keypress(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveSequencerKeyboardAction(key, actionId))
			return OK;
		if(handleSequencerConfigAction(actionId))
			return OK;

		switch(actionId) {
		case KeyboardActionId.sequencerViewNavigateSongStart:
			jump(Jump.toBeginning, true);
			break;
		case KeyboardActionId.sequencerViewNavigateSongEnd:
			jump(Jump.toEnd, true);
			break;
		case KeyboardActionId.sequencerViewNavigateLargePageUp:
			step(-PAGESTEP * 2 * song.highlight);
			step(-PAGESTEP * song.highlight);
			break;
		case KeyboardActionId.sequencerViewNavigateLargePageDown:
			step(PAGESTEP * 2 * song.highlight);
			step(PAGESTEP * song.highlight);
			break;
		case KeyboardActionId.trackEntryLoopSetAllVoices:
			setWrapMark();
			break;
		case KeyboardActionId.sequencerViewNavigateDown:
			step(1);
			break;
		case KeyboardActionId.sequencerViewNavigateUp:
			step(-1);
			break;
		case KeyboardActionId.sequencerViewNavigatePageUp:
			step(-PAGESTEP * song.highlight);
			break;
		case KeyboardActionId.sequencerViewNavigatePageDown:
			step(PAGESTEP * song.highlight);
			break;
		case KeyboardActionId.sequencerViewScrollDown:
			scroll(1);
			step(-1);
			break;
		case KeyboardActionId.sequencerViewScrollUp:
			scroll(-1);
			step(1);
			break;
		case KeyboardActionId.sequencerNavigateVoicePrevious:
			foreach(v; voices)
				v.input.nibble = 0;
			stepVoice(-1);
			break;
		case KeyboardActionId.sequencerNavigateVoiceNext:
			foreach(v; voices)
				v.input.nibble = 0;
			stepVoice();
			break;
		default:
			break;
		}
		return OK;
	}

	void stepVoice() { stepVoice(1); }
	
	void stepVoice(int i) {
		// safety check - if we're past endmark on all voices,
		// exit the method -- can happen if all tracklists
		// contain only FF00
		bool pastAll = true;
		foreach(voice; voices) {
			if(!voice.pastEnd(posTable.pointerOffset))
				pastAll = false;
		}
		if(pastAll) return;
		int nv = umod(activeVoiceNum + i, 0, 2);
		while(voices[nv].pastEnd(posTable.pointerOffset)) {
			nv = umod(nv + i, 0, 2);
		}
		activateVoice(nv);
	}

	void scroll(int st) {
		foreach(v; voices) { v.scroll(st); }
	}

	void activateVoice(int voice) {
		deactivate();
		activeVoiceNum = voice;
		activate();
		voices[voice].refreshPointer();
		step(0);
	}

	protected int voiceAtLocalX(int x) {
		foreach(i, voice; voices) {
			if(voice is null)
				continue;
			int left = voice.area.x - area.x;
			if(x >= left && x < left + voice.area.width)
				return cast(int)i;
		}
		return -1;
	}

	protected bool activateVoiceAtLocalX(int x) {
		int voice = voiceAtLocalX(x);
		if(voice < 0)
			return false;
		if(voice != activeVoiceNum)
			activateVoice(voice);
		return true;
	}

	void jumpToVoice(int voice) {
		deactivate();
		activeVoiceNum = voice;
		activate();
		// making sure cursor is not past endmark
		step(0);
	}
	
	override void update() {
		input = activeVoice.activeInput; 
		foreach(v; voices) { 
			v.refreshPointer(posTable.pointerOffset);
			v.update(); 
			
		}
		// statusline
		screen.cprint(area.x + 1, area.y, 1, 0, format("#%02X",song.subtune));
		for(int i = 0, x = area.x + 5 + com.fb.border; i < 3; i++) {
			Voice v = voices[i];
			RowData c = v.activeRow;
			screen.cprint(x, area.y, 1, 0,
				format("+%03X %02X %s", c.trkOffset, c.trk.number,
					   audio.player.muted[i] ? "Off" : "   ") );
			x += 13 + com.fb.border;
		}
		// row counter
		int r = activeVoice.pos.rowCounter - anchor;
		for(int y = 0; y < area.height; y++) {
			string s = "    ";
			if(r >= 0) s = format("%+4X", r);
			r++;
			screen.cprint(area.x, area.y + y + 1, 12, 0, s);
		}

	}
	
	void setPositionMark() {
		foreach(v; voices) {
			v.setPositionMark();
		}
	}

	void setWrapMark() {
		foreach(v; voices) {
			v.setWrapMark();
		}
	}

	void jump(int to, bool doCtr) {
		switch(to) {
		case Jump.toBeginning:
			posTable.pointerOffset = 0;
			foreach(v; voices) {
				v.jump(Jump.toBeginning);
			}
			if(doCtr) centerTo(0);
			break;
		case Jump.toMark:
			posTable.pointerOffset = 0;
			foreach(v; voices) {
				v.jump(Jump.toBeginning);
				v.jump(v.pos.mark);
			}
			if(doCtr) centerTo(0);
			break;
		case Jump.toWrapMark:
			posTable.pointerOffset = 0;
			foreach(v; voices) {
				v.jump(Jump.toBeginning);
				v.jump(v.tracks.wrapOffset);
			}
			if(doCtr) centerTo(0);
			break;
		case Jump.toEnd:
			centralize();
			toSeqStart();

			foreach(v; voices) {
				v.jump(Jump.toBeginning);
			}

			int e = activeVoice.tracks.trackLength - 1;
			
			for(int i = 0; i < e; i++) {
				activeVoice.refreshPointer(posTable.pointerOffset);
				RowData s = activeVoice.getRowData(i);
				step(s.seq.rows);
			}
			activeVoice.refreshPointer(posTable.pointerOffset);
			toSeqEnd();
			break;
		default:
			if(to < 0) {
				to = activeVoice.pos.mark;
			}
			foreach(v; voices) {
				v.jump(Jump.toBeginning);
			}
			Voice v = activeVoice;
			posTable.pointerOffset = 0;
			for(int i = 0; i < to; i++) {
				activeVoice.refreshPointer(0);
				int trk = v.tracks[i].number;
				Sequence s = song.seqs[trk];
				step(s.rows);
			}
			if(doCtr) centerTo(0);
			break;
		}
		refresh();
	}

	void toSeqStart() {
		int st = -activeVoice.activeRow.seqOffset;
		this.step(st,0);
	}

	void toSeqEnd() {
		int rows = activeVoice.activeRow.seq.rows;
		int seqend = rows -
			activeVoice.activeRow.seqOffset - 1;
		step(seqend);
	}

	void toScreenTop() {
		step(-posTable.normalPointerOffset);
	}
	
	void toScreenBot() {
		int scrend = tableTop - posTable.pointerOffset - 1;
		step(scrend);
	}

	void centerTo(int center) {
		assert(center < tableTop && center >= tableBot);
		int steps = center - posTable.pointerOffset;
		foreach(v; voices) {
			v.scroll(-steps);
		}
		posTable.pointerOffset = center;
		step(0,1,1);
	}

	void step(int s) { step(s, 0); }
	void step(int s, int e) {
		step(s, e, area.height);
	}

	void step(int st, int extra, int height) {
		bool wrapOk = true;
		bool atBeg = activeVoice.atBeg();
		if(st < 0 && atBeg && stepCounter > 0) {
			st = 0;
			wrapOk = false;
		}
	
		posTable.pointerOffset = 
			posTable.pointerOffset + st;

		bool atEnd = activeVoice.atEnd();

		if(atEnd && stepCounter > 1) {
			posTable.pointerOffset = 
				posTable.pointerOffset - st;
			st = 0;
			wrapOk = false;
		}
		int r;
		if(posTable.pointerOffset >= tableTop) {
			r = -(height/2-posTable.pointerOffset-1);
			posTable.pointerOffset = tableTop - 1;
		}
		else if(posTable.pointerOffset < tableBot) {
			r = (posTable.pointerOffset+height/2);
			posTable.pointerOffset = tableBot;

		}

 		stepCounter++;

		int d = r > 0 ? 1 : - 1;
		if(r == 0) d = 0;
		int i;

		doStep(wrapOk,r);

		if(d <= 0) return;
		assert(extra >= 0);
		posTable.pointerOffset = 
			posTable.pointerOffset - extra;

		doStep(true,extra);
	}

	protected void doStep(bool wrapOk, int r) {
		foreach(v; voices) {
			bool wrap = wrapOk;
			v.scroll(r,wrap);
		}
	}

	// for seq copy/insert/etc 
	RowData getRowData() {
		return activeVoice.activeRow;
	}

	Sequence getActiveSequence() {
		return activeVoice.activeRow.seq;
	}

	// helper for trackcopy/paste
	Tracklist getTracklist(Voice v) {
		return v.tracks[v.activeRow.trkOffset .. v.tracks.length];
	}
}

// -------------------------------------------------------------------

private final class SequenceDialogHistoryRecord : UndoOwnerPayload {
	Sequence sequence;
	ubyte[] sequenceBytes;
	PosDataTable posTable;
	int subtuneNum;
	TrackOverviewCursorIdentity cursorIdentity;

	this(Sequence sequence, ubyte[] sequenceBytes,
			PosDataTable posTable, int subtuneNum,
			TrackOverviewCursorIdentity cursorIdentity) {
		this.sequence = sequence;
		this.sequenceBytes = sequenceBytes;
		this.posTable = posTable;
		this.subtuneNum = subtuneNum;
		this.cursorIdentity = cursorIdentity;
	}
}

private struct F6OriginMarker {
	bool valid;
	int subtune = -1;
	TrackOverviewCursorIdentity cursorIdentity;
	Sequence sequence;
	int sequenceRows;
	ushort trackValue;
	int inputColumn;
	int inputDisplayOffset;
	int visibleRow;
	SequenceOriginDestination destination;
}

final class Sequencer : Window, Undoable {
	private {
		VoiceTable[] voiceTables;
		TrackmapTable trackmapTable;
		SequenceTable sequenceTable;
		TrackTable trackTable;
		QueryDialog queryCopy, queryAppend;
		PosDataTable[] postables;
		PosDataTable enterTogglePos;
		ushort enterToggleTrackValue;
		int enterToggleTrackOffset;
		int enterToggleVoice;
		int enterToggleSubtune;
		bool enterToggleRestoreValid = false;
		bool overviewGlobalRowValid = false;
		int overviewGlobalRow;
		bool f5PlaybackAnchorValid = false;
		int f5PlaybackAnchorSubtune = -1;
		int f5PlaybackAnchorGlobalRow = -1;
		int f5PlaybackAnchorVoice = -1;
		int[3] f5PlaybackAnchorTrackIndex;
		ushort[3] f5PlaybackAnchorTrackValue;
		int[3] f5PlaybackAnchorSequenceRowOffset;
		PosDataTable f5PlaybackAnchorPos;
		TrackEntryClipboard trackEntryClipboard;
		F6OriginMarker f6OriginMarker;
		SequenceRowDragAutoScrollDirection sequenceRowDragAutoScrollDirection =
			SequenceRowDragAutoScrollDirection.none;
		int sequenceRowDragAutoScrollTicks;
		InputBoundedHexByte subtuneInput;
		bool subtuneEditorFocused;
	}
	VoiceTable activeView;
	//private Clip[] clip;
	enum int TRACK_HEADER_LOCAL_X_END = 3;
	enum int PATTERN_CELL_LOCAL_X = 4;
	enum int PATTERN_CELL_LOCAL_X_END = 12;
	enum int VOICE_SEPARATOR_LOCAL_X = 13;
	
	this(Rectangle a) {
		int h = screen.height - 10;
		super(a,ui.help.HELPSEQUENCER);
		trackmapTable = new TrackmapTable(a, seqPos);
		sequenceTable = new SequenceTable(a, seqPos);
		trackTable = new TrackTable(a, seqPos);
		voiceTables = [cast(VoiceTable)trackmapTable, sequenceTable, trackTable];
		activeView = sequenceTable;
		activeView.activate();
		activateVoice(0);
		subtuneInput = new InputBoundedHexByte(
			() => song.subtune,
			(int value) => setSubtune(value),
			0, SUBTUNE_MAX - 1,
			"Subtune high digit must be 0 or 1. Use 00-1F.");
		
		queryAppend = new QueryDialog("Insert this sequence to cursor pos: $",
								  &insertCallback, 0x80);
								  
		queryCopy = new QueryDialog("Copy this sequence to cursor seq: $",
								&copyCallback, 0x80);
		
		// top & bottom
		tableBot = -area.height / 2;
		tableTop = area.height / 2;
		sequenceTable.placeSongStartAtTopBoundary();

		postables.length = 32;
			foreach(ref p; postables) {
				p = new PosDataTable;
				initializeSubtunePositionAtSongStart(p, area.height);
			}
			
		}

		private void openSequenceAppendDialog() {
			queryAppend = new QueryDialog("Insert this sequence to cursor pos: $",
									  &insertCallback, 0x80);
			mainui.activateDialog(queryAppend);
		}

		private void openSequenceCopyDialog() {
			queryCopy = new QueryDialog("Copy this sequence to cursor seq: $",
									&copyCallback, 0x80);
			mainui.activateDialog(queryCopy);
		}

		override ContextHelp contextHelp() {
		if(activeView == sequenceTable)
			return ui.help.HELPSEQUENCECOLUMNS;
		if(activeView == trackTable)
			return ui.help.HELPTRACKTABLE;
		if(activeView == trackmapTable)
			return ui.help.HELPTRACKMAP;
		return help;
	}

	void activateVoice(int n) {
		if(activeView == sequenceTable)
			clearSequenceNavigationEntryProgress();
		activeView.jumpToVoice(n);
		input = activeView.input;
	}
	
	void reset() { reset(true); }
	
	void reset(bool tostart) {
		overviewGlobalRowValid = false;
		clearF6OriginMarker();
		clearF5PlaybackAnchor();
		clearSequenceNavigationEntryProgress();
		activeView.deactivate();
		if(tostart) {
			enterToggleRestoreValid = false;
			enterTogglePos = null;

			foreach(b; voiceTables) {
				b.toSeqStart();
			}
			sequenceTable.jump(Jump.toBeginning,true);

			foreach(ref p; postables) {
				p = new PosDataTable;
				initializeSubtunePositionAtSongStart(p, area.height);
			}

			trackTable.clearClickedTrackEntry();
			trackmapTable.clearClickedTrackEntry();
		}
		activeView = sequenceTable;
		activeView.activate();
	}

	void placeSequenceSongStartAtTopBoundary() {
		sequenceTable.placeSongStartAtTopBoundary();
		if(activeView == sequenceTable)
			input = activeView.input;
	}

	private void rememberEnterTogglePosition() {
		enterTogglePos = activeView.posTable.dup();
		enterToggleVoice = activeVoiceNum;
		enterToggleSubtune = song.subtune;
		Voice voice = activeView.voices[enterToggleVoice];
		voice.refreshPointer(activeView.posTable.pointerOffset);
		enterToggleTrackOffset = voice.activeRow.trkOffset;
		enterToggleTrackValue = voice.activeRow.track.smashedValue;
		enterToggleRestoreValid = true;
	}

		private bool canRestoreEnterTogglePosition() {
			if(!enterToggleRestoreValid || enterToggleSubtune != song.subtune)
				return false;
			if(activeVoiceNum != enterToggleVoice)
				return false;

		activeView.activeVoice.trackFlush(activeView.posTable.pointerOffset);
		Voice voice = activeView.voices[enterToggleVoice];
		voice.refreshPointer(activeView.posTable.pointerOffset);
			return voice.activeRow.trkOffset == enterToggleTrackOffset &&
				voice.activeRow.track.smashedValue == enterToggleTrackValue;
		}

		private bool captureTrackTableActivationTarget(out int voiceNum,
				out int trackIndex, out ushort trackValue,
				out int globalRow,
				out TrackOverviewPosition[] positions) {
			voiceNum = activeVoiceNum;
			trackIndex = -1;
			trackValue = 0;
			globalRow = -1;
			positions = null;
			if(activeView != sequenceTable)
				return false;
			if(voiceNum < 0 || voiceNum >= activeView.voices.length)
				return false;

			auto overview = buildTrackOverview(song);
			RowData row;
			if(!overviewGlobalRowFromActiveRow(overview, globalRow, row))
				return false;

			positions = resolveTrackOverviewPositions(overview, globalRow);
			if(voiceNum >= cast(int)positions.length ||
					!positions[voiceNum].valid)
				return false;

			trackIndex = row.trkOffset;
			trackValue = row.track.smashedValue;
			return true;
		}

		private bool resolveTrackTableEditorActivationTarget(
				int playbackAnchorGlobalRow,
				const TrackOverviewPosition[] playbackAnchorPositions,
				int voice, int trackIndex, ushort trackValue,
				out int f5EditorGlobalRow,
				out TrackOverviewPosition[] f5EditorPositions) {
			f5EditorGlobalRow = -1;
			f5EditorPositions = null;
			if(playbackAnchorGlobalRow < 0 || voice < 0 || voice >= 3 ||
					playbackAnchorPositions.length < 3 ||
					!playbackAnchorPositions[voice].valid ||
					playbackAnchorPositions[voice].sequenceRowOffset < 0)
				return false;

			f5EditorGlobalRow = playbackAnchorGlobalRow -
				playbackAnchorPositions[voice].sequenceRowOffset;
			if(f5EditorGlobalRow < 0)
				return false;

			auto overview = buildTrackOverview(song);
			f5EditorPositions = resolveTrackOverviewPositions(overview,
				f5EditorGlobalRow);
			if(f5EditorPositions.length < 3)
				return false;
			foreach(position; f5EditorPositions) {
				if(!position.valid || position.trackIndex < 0 ||
						position.sequenceRowOffset < 0 ||
						position.globalRow != f5EditorGlobalRow)
					return false;
			}

			TrackOverviewPosition activePosition = f5EditorPositions[voice];
			return activePosition.trackIndex == trackIndex &&
				activePosition.trackValue == trackValue &&
				activePosition.sequenceRowOffset == 0;
		}

		private void clearF5PlaybackAnchor() {
			f5PlaybackAnchorValid = false;
			f5PlaybackAnchorSubtune = -1;
			f5PlaybackAnchorGlobalRow = -1;
			f5PlaybackAnchorVoice = -1;
			f5PlaybackAnchorPos = null;
		}

		private bool storeF5PlaybackAnchor(int globalRow,
				const TrackOverviewPosition[] positions, int voice) {
			if(globalRow < 0 || voice < 0 || voice >= 3 ||
					positions.length < 3 || activeView != trackTable) {
				clearF5PlaybackAnchor();
				return false;
			}

			PosDataTable playbackPos = activeView.posTable.dup();
			foreach(i; 0 .. 3) {
				if(!positions[i].valid ||
						positions[i].trackIndex < 0 ||
						positions[i].sequenceRowOffset < 0) {
					clearF5PlaybackAnchor();
					return false;
				}

				f5PlaybackAnchorTrackIndex[i] = positions[i].trackIndex;
				f5PlaybackAnchorTrackValue[i] = positions[i].trackValue;
				f5PlaybackAnchorSequenceRowOffset[i] =
					positions[i].sequenceRowOffset;

				PosData pos = playbackPos.pos[i];
				pos.pointerOffset = 0;
				pos.trkOffset = positions[i].trackIndex;
				pos.seqOffset = positions[i].sequenceRowOffset;
				pos.rowCounter = positions[i].localRow;
			}

			f5PlaybackAnchorValid = true;
			f5PlaybackAnchorSubtune = song.subtune;
			f5PlaybackAnchorGlobalRow = globalRow;
			f5PlaybackAnchorVoice = voice;
			f5PlaybackAnchorPos = playbackPos;
			return true;
		}

		private bool f5PlaybackAnchorMatchesEditor() {
			if(!f5PlaybackAnchorValid || activeView != trackTable ||
					f5PlaybackAnchorSubtune != song.subtune ||
					f5PlaybackAnchorPos is null ||
					f5PlaybackAnchorVoice < 0 ||
					f5PlaybackAnchorVoice >= 3 ||
					f5PlaybackAnchorVoice >= cast(int)activeView.voices.length)
				return false;

			Voice voice = activeView.voices[f5PlaybackAnchorVoice];
			if(voice is null)
				return false;

			RowData row = voice.getRowData(voice.pos.trkOffset,
				voice.pos.seqOffset + activeView.posTable.pointerOffset);
			return row.trkOffset ==
					f5PlaybackAnchorTrackIndex[f5PlaybackAnchorVoice] &&
				row.seqOffset == 0 &&
				row.track.smashedValue ==
					f5PlaybackAnchorTrackValue[f5PlaybackAnchorVoice];
		}

		private void activateTrackTable() {
			if(activeView == sequenceTable) {
				resetSequenceRowDragAutoScroll();
				clearSequenceNavigationEntryProgress();
			}
			int targetVoice, targetTrackIndex;
			ushort targetTrackValue;
			int playbackAnchorGlobalRow;
			TrackOverviewPosition[] playbackAnchorPositions;
			bool hasPlaybackAnchorSource = captureTrackTableActivationTarget(
				targetVoice, targetTrackIndex, targetTrackValue,
				playbackAnchorGlobalRow, playbackAnchorPositions);

			int f5EditorGlobalRow;
			TrackOverviewPosition[] f5EditorPositions;
			bool hasF5EditorTarget = hasPlaybackAnchorSource &&
				resolveTrackTableEditorActivationTarget(
					playbackAnchorGlobalRow, playbackAnchorPositions,
					targetVoice, targetTrackIndex, targetTrackValue,
					f5EditorGlobalRow, f5EditorPositions);

			auto previousView = activeView;
			previousView.deactivate();
			if(hasF5EditorTarget) {
				activeView = trackTable;
				activeView.activate();
				if(moveEditorCursorToOverviewPositionsSafeForActiveView(
						f5EditorPositions, targetVoice)) {
					storeF5PlaybackAnchor(playbackAnchorGlobalRow,
						playbackAnchorPositions, targetVoice);
					return;
				}
				activeView.deactivate();
			}
			clearF5PlaybackAnchor();
			activeView = previousView;
			activeView.toSeqStart();
			activeView = trackTable;
			activeView.activate();
		}

	private void activateSequenceTable(PosDataTable restorePos = null) {
		if(activeView == sequenceTable) {
			resetSequenceRowDragAutoScroll();
			clearSequenceNavigationEntryProgress();
		}
		clearF5PlaybackAnchor();
		activeView.deactivate();
		if(restorePos !is null)
			activeView.posTable.copyFrom(restorePos);
		activeView = sequenceTable;
		activeView.activate();
		// Making sure cursor is not past endmark.
		activeView.step(0);
	}

		void resetMark() {
			foreach(v; activeView.voices) {
				v.setPositionMark(0);
			}
		}

		void setPlaybackMarkAtCurrentEditorPosition() {
			activeView.setPositionMark();
			activeView.refresh();
			input = activeView.input;
		}

		void setActiveVoicePlaybackMarkAtCurrentEditorPosition() {
			Voice voice = activeView.activeVoice;
			voice.setPositionMark();
			activeView.refresh();
			input = activeView.input;
		}

		Voice[] getVoices() {
			return activeView.voices;
	}

	bool cursorPlaybackPosition(out int[3] trackIndexes,
			out int[3] sequenceRowOffsets, out PosDataTable playbackPos) {
		playbackPos = null;

		if(f5PlaybackAnchorMatchesEditor()) {
			foreach(i; 0 .. 3) {
				trackIndexes[i] = f5PlaybackAnchorTrackIndex[i];
				sequenceRowOffsets[i] =
					f5PlaybackAnchorSequenceRowOffset[i];
			}
			playbackPos = f5PlaybackAnchorPos;
			return true;
		}

		if(activeView is null || activeView.voices.length < 3)
			return false;

		foreach(i; 0 .. 3) {
			Voice voice = activeView.voices[i];
			if(voice is null)
				return false;
			RowData row = voice.activeRow;
			if(row.trkOffset < 0 || row.seqOffset < 0 ||
					row.track.trans >= 0xf0)
				return false;
			trackIndexes[i] = row.trkOffset;
			sequenceRowOffsets[i] = row.seqOffset;
		}

		playbackPos = activeView.posTable.dup();
		return true;
	}

	int activeEditorVoice() {
		return activeVoiceNum;
	}

	RowData activeEditorRow() {
		return activeView.getRowData();
	}

	bool editorRowForVoice(int voice, out RowData row) {
		row = RowData.init;
		if(voice < 0 || voice >= cast(int)activeView.voices.length)
			return false;

		Voice v = activeView.voices[voice];
		if(v is null)
			return false;

		row = v.getRowData(v.pos.trkOffset,
			v.pos.seqOffset + activeView.posTable.pointerOffset);
		return true;
	}

	void flushPendingInput() {
		activeView.activeVoice.trackFlush(activeView.posTable.pointerOffset);
	}

	bool insertTrackEntryAt(int voice, int trackIndex,
			ushort expectedTrackValue, out ushort insertedTrackValue) {
		flushPendingInput();
		return trackTable.insertTrackEntryAt(voice, trackIndex,
			expectedTrackValue, insertedTrackValue);
	}

	bool insertNextUnusedExpandedSequenceTrackEntryAfter(int voice,
			int anchorTrackIndex, ushort expectedTrackValue,
			out int insertedTrackIndex, out ushort insertedTrackValue,
			out int insertedSequenceNumber) {
		flushPendingInput();
		return trackTable.insertNextUnusedExpandedSequenceTrackEntryAfter(
			voice, anchorTrackIndex, expectedTrackValue, insertedTrackIndex,
			insertedTrackValue, insertedSequenceNumber);
	}

	bool setTrackEntryToNextUnusedSequenceAt(int voice, int trackIndex,
			ushort expectedTrackValue, out ushort updatedTrackValue,
			out int updatedSequenceNumber) {
		flushPendingInput();
		return trackTable.setTrackEntryToNextUnusedSequenceAt(
			voice, trackIndex, expectedTrackValue, updatedTrackValue,
			updatedSequenceNumber);
	}

	bool insertCopyOfTrackEntryAt(int voice, int trackIndex,
			ushort expectedTrackValue, out ushort copiedTrackValue) {
		flushPendingInput();
		return trackTable.insertCopyOfTrackEntryAt(voice, trackIndex,
			expectedTrackValue, copiedTrackValue);
	}

	bool deleteTrackEntryAt(int voice, int trackIndex,
			ushort expectedTrackValue) {
		flushPendingInput();
		return trackTable.deleteTrackEntryAt(voice, trackIndex,
			expectedTrackValue);
	}

	bool deleteTrackEntryRangeAt(int voice, int startTrackIndex,
			int endTrackIndex, const(ushort)[] expectedTrackValues) {
		flushPendingInput();
		return trackTable.deleteTrackEntryRangeAt(voice, startTrackIndex,
			endTrackIndex, expectedTrackValues);
	}

	bool pasteTrackEntryClipboardAfter(int voice, int anchorTrackIndex,
			ushort expectedTrackValue, out int firstInsertedTrackIndex,
			out int lastInsertedTrackIndex, out int insertedCount) {
		firstInsertedTrackIndex = -1;
		lastInsertedTrackIndex = -1;
		insertedCount = 0;
		if(!trackEntryClipboard.hasEntries)
			return false;

		flushPendingInput();
		return trackTable.pasteTrackEntriesAfter(voice, anchorTrackIndex,
			expectedTrackValue, trackEntryClipboard.entries,
			firstInsertedTrackIndex, lastInsertedTrackIndex, insertedCount);
	}

	bool insertTrackEntriesAt(int voice, int insertionTrackIndex,
			const(Clip)[] entries,
			out int firstInsertedTrackIndex, out int lastInsertedTrackIndex,
			out int insertedCount) {
		flushPendingInput();
		return trackTable.insertTrackEntriesAt(voice, insertionTrackIndex,
			entries, firstInsertedTrackIndex, lastInsertedTrackIndex,
			insertedCount);
	}

	bool moveTrackEntryWithinVoice(int voice, int sourceTrackIndex,
			int insertionTrackIndex, ushort expectedTrackValue,
			out int movedTrackIndex, out ushort movedTrackValue) {
		flushPendingInput();
		return trackTable.moveTrackEntryWithinVoice(voice, sourceTrackIndex,
			insertionTrackIndex, expectedTrackValue, movedTrackIndex,
			movedTrackValue);
	}

	bool moveTrackEntryRangeWithinVoice(int voice, int sourceStartTrackIndex,
			int sourceEndTrackIndex, int insertionTrackIndex,
			const(ushort)[] expectedTrackValues,
			out int movedStartTrackIndex, out int movedEndTrackIndex) {
		flushPendingInput();
		return trackTable.moveTrackEntryRangeWithinVoice(voice,
			sourceStartTrackIndex, sourceEndTrackIndex, insertionTrackIndex,
			expectedTrackValues, movedStartTrackIndex, movedEndTrackIndex);
	}

	bool moveTrackEntryRangeToVoice(int sourceVoice,
			int sourceStartTrackIndex, int sourceEndTrackIndex,
			int targetVoice, int insertionTrackIndex,
			const(ushort)[] expectedTrackValues,
			out int movedStartTrackIndex, out int movedEndTrackIndex) {
		flushPendingInput();
		return trackTable.moveTrackEntryRangeToVoice(sourceVoice,
			sourceStartTrackIndex, sourceEndTrackIndex, targetVoice,
			insertionTrackIndex, expectedTrackValues, movedStartTrackIndex,
			movedEndTrackIndex);
	}

	bool moveTrackEntryToVoice(int sourceVoice, int sourceTrackIndex,
			int targetVoice, int insertionTrackIndex,
			ushort expectedTrackValue, out int movedTrackIndex,
			out ushort movedTrackValue) {
		flushPendingInput();
		return trackTable.moveTrackEntryToVoice(sourceVoice, sourceTrackIndex,
			targetVoice, insertionTrackIndex, expectedTrackValue,
			movedTrackIndex, movedTrackValue);
	}

	bool setLoopTargetForVoiceAtTrackIndex(int voice, int targetTrackIndex,
			ushort expectedTrackValue) {
		flushPendingInput();
		bool changed = trackTable.setLoopTargetForVoiceAtTrackIndex(voice,
			targetTrackIndex, expectedTrackValue);
		if(changed) {
			activeView.refresh();
			input = activeView.input;
		}
		return changed;
	}

	bool setLoopTargetsForVoiceTrackIndices(int[3] targetTrackIndex,
			ushort[3] expectedTrackValue) {
		flushPendingInput();
		bool changed = trackTable.setLoopTargetsForVoiceTrackIndices(
			targetTrackIndex, expectedTrackValue);
		if(changed) {
			activeView.refresh();
			input = activeView.input;
		}
		return changed;
	}

	bool setLoopTargetForActiveTrackEntry() {
		flushPendingInput();

		int voice = activeEditorVoice();
		RowData row;
		if(!editorRowForVoice(voice, row))
			return false;
		if(row.trkOffset < 0 || row.track.trans >= 0xf0)
			return false;

		bool changed = trackTable.setLoopTargetForVoiceAtTrackIndex(voice,
			row.trkOffset, row.track.smashedValue);
		if(changed) {
			activeView.refresh();
			input = activeView.input;
		}
		return changed;
	}

	bool moveEditorCursorToOverviewPosition(
			const TrackOverviewPosition position) {
		if(!position.valid || position.voice < 0 || position.voice >= 3 ||
				position.trackIndex < 0 || position.sequenceRowOffset < 0)
			return false;

		activeView.activeVoice.trackFlush(activeView.posTable.pointerOffset);
		activeView.activateVoice(position.voice);
		activeView.jump(position.trackIndex, false);
		activeView.step(position.sequenceRowOffset);
		activeView.centerTo(0);
		input = activeView.input;
		rememberOverviewGlobalRow(position.globalRow);
		return true;
	}

	bool moveEditorCursorToOverviewPositions(
			const TrackOverviewPosition[] positions, int activeVoice) {
		if(activeVoice < 0 || activeVoice >= 3 ||
				positions.length < 3 || !positions[activeVoice].valid)
			return false;
		foreach(voice; 0 .. 3) {
			if(!positions[voice].valid ||
					positions[voice].trackIndex < 0 ||
					positions[voice].sequenceRowOffset < 0)
				return false;
		}

		activeView.activeVoice.trackFlush(activeView.posTable.pointerOffset);
		activeView.posTable.pointerOffset = 0;
		foreach(voice; 0 .. 3) {
			PosData pos = activeView.posTable.pos[voice];
			pos.trkOffset = positions[voice].trackIndex;
			pos.seqOffset = positions[voice].sequenceRowOffset;
			pos.rowCounter = positions[voice].localRow;
		}
		activeView.activateVoice(activeVoice);
		input = activeView.input;
		return true;
	}

	bool moveEditorCursorToOverviewPositionsSafeForActiveView(
			const TrackOverviewPosition[] positions, int activeVoice) {
		bool moved;
		if(activeView == trackmapTable)
			moved = moveTrackmapCursorToOverviewPositions(positions,
				activeVoice);
		else
			moved = moveEditorCursorToOverviewPositions(positions,
				activeVoice);
		if(moved && activeVoice >= 0 &&
				activeVoice < cast(int)positions.length &&
				positions[activeVoice].valid)
			rememberOverviewGlobalRow(positions[activeVoice].globalRow);
		return moved;
	}

	bool moveTrackmapClickToOverviewResolvedPosition(int clickedVoice,
			int clickedTrackIndex) {
		if(activeView != trackmapTable || clickedVoice < 0 ||
				clickedVoice >= 3 || clickedTrackIndex < 0)
			return false;

		auto overview = buildTrackOverview(song);
		if(clickedVoice >= cast(int)overview.length)
			return false;

		TrackOverviewBlock clickedBlock;
		bool foundBlock;
		foreach(block; overview[clickedVoice].blocks) {
			if(block.trackIndex == clickedTrackIndex) {
				clickedBlock = block;
				foundBlock = true;
				break;
			}
		}
		if(!foundBlock)
			return false;

		auto positions = resolveTrackOverviewPositions(overview,
			clickedBlock.startRow);
		if(!moveEditorCursorToOverviewPositionsSafeForActiveView(positions,
				clickedVoice))
			return false;

		return trackmapTable.rememberTrackEntryClickAt(clickedVoice,
			clickedTrackIndex);
	}

	bool editorOverviewGlobalRow(const(TrackOverviewLane)[] overview,
			out int globalRow) {
		RowData row;
		return overviewGlobalRowFromActiveRow(overview, globalRow, row);
	}

	void clearF6OriginMarker() {
		f6OriginMarker = F6OriginMarker.init;
	}

	void retainF6OriginMarkerForDestination(
			SequenceOriginDestination destination) {
		if(f6OriginMarker.valid &&
				f6OriginMarker.destination != destination)
			clearF6OriginMarker();
	}

	private bool captureF6OriginMarker(
			SequenceOriginDestination destination,
			out F6OriginMarker marker) {
		marker = F6OriginMarker.init;
		if(destination == SequenceOriginDestination.none ||
				activeView != sequenceTable)
			return false;

		auto sequenceInput = cast(InputSeq)sequenceTable.input;
		if(sequenceInput is null)
			return false;

		auto overview = buildTrackOverview(song);
		int globalRow;
		RowData row;
		if(!overviewGlobalRowFromActiveRow(overview, globalRow, row) ||
				row.seq is null || row.seqOffset < 0 ||
				row.seqOffset >= row.seq.rows)
			return false;

		TrackOverviewCursorIdentity identity =
			trackOverviewCursorIdentityAtGlobalRow(overview, globalRow,
				activeVoiceNum, row.trkOffset, row.seqOffset);
		if(!identity.valid)
			return false;

		int displayOffset = sequenceInput.cursor.x - sequenceInput.pointerX;
		if(displayOffset < 0 || displayOffset > 8)
			return false;

		marker.subtune = song.subtune;
		marker.cursorIdentity = identity;
		marker.sequence = row.seq;
		marker.sequenceRows = row.seq.rows;
		marker.trackValue = row.track.smashedValue;
		marker.inputColumn = sequenceInput.currentNavigationColumn;
		marker.inputDisplayOffset = displayOffset;
		marker.visibleRow = activeView.posTable.normalPointerOffset;
		marker.destination = destination;
		marker.valid = true;
		return true;
	}

	private bool resolveF6OriginMarker(
			SequenceOriginDestination destination,
			out TrackOverviewLane[] overview, out int globalRow) {
		overview = null;
		globalRow = -1;
		if(!f6OriginMarker.valid ||
				f6OriginMarker.destination != destination ||
				f6OriginMarker.subtune != song.subtune ||
				!f6OriginMarker.cursorIdentity.valid ||
				f6OriginMarker.sequence is null ||
				f6OriginMarker.sequenceRows <= 0 ||
				f6OriginMarker.inputColumn < InputSeq.noteColumn ||
				f6OriginMarker.inputColumn > InputSeq.commandColumn ||
				f6OriginMarker.inputDisplayOffset < 0 ||
				f6OriginMarker.inputDisplayOffset > 8)
			return false;

		int voice = f6OriginMarker.cursorIdentity.voice;
		int trackIndex = f6OriginMarker.cursorIdentity.trackIndex;
		int sequenceRow = f6OriginMarker.cursorIdentity.sequenceRowOffset;
		if(voice < 0 || voice >= cast(int)song.tracks.length ||
				trackIndex < 0 || trackIndex >= song.tracks[voice].length ||
				sequenceRow < 0 ||
				sequenceRow >= f6OriginMarker.sequenceRows)
			return false;

		Track sourceTrack = song.tracks[voice][trackIndex];
		if(sourceTrack.trans >= 0xf0 ||
				sourceTrack.smashedValue != f6OriginMarker.trackValue ||
				sourceTrack.number >= song.seqs.length)
			return false;
		Sequence sourceSequence = song.seqs[sourceTrack.number];
		if(sourceSequence is null ||
				sourceSequence !is f6OriginMarker.sequence ||
				sourceSequence.rows != f6OriginMarker.sequenceRows)
			return false;

		overview = buildTrackOverview(song);
		if(!trackOverviewGlobalRowForCursorIdentity(overview,
				f6OriginMarker.cursorIdentity, globalRow))
			return false;

		TrackOverviewPosition[] positions =
			resolveTrackOverviewPositions(overview, globalRow);
		if(voice >= cast(int)positions.length)
			return false;
		TrackOverviewPosition sourcePosition = positions[voice];
		return sourcePosition.valid && sourcePosition.voice == voice &&
			sourcePosition.trackIndex == trackIndex &&
			sourcePosition.sequenceNumber == sourceTrack.number &&
			sourcePosition.trackValue == f6OriginMarker.trackValue &&
			sourcePosition.sequenceRowOffset == sequenceRow;
	}

	bool tryReturnToF6Origin(SequenceOriginDestination destination) {
		if(!f6OriginMarker.valid ||
				f6OriginMarker.destination != destination)
			return false;

		TrackOverviewLane[] overview;
		int globalRow;
		if(activeView != sequenceTable ||
				!resolveF6OriginMarker(destination, overview, globalRow)) {
			clearF6OriginMarker();
			return false;
		}

		F6OriginMarker marker = f6OriginMarker;
		if(!moveSequenceTableToOverviewGlobalRow(overview, globalRow,
				marker.visibleRow, marker.cursorIdentity.voice)) {
			clearF6OriginMarker();
			return false;
		}

		auto voice = cast(SeqVoice)
			sequenceTable.voices[marker.cursorIdentity.voice];
		if(voice is null || voice.seqinput is null) {
			clearF6OriginMarker();
			return false;
		}
		voice.seqinput.clickAtDisplayOffset(marker.inputDisplayOffset);
		input = voice.seqinput;
		activeView.refresh();
		clearF6OriginMarker();
		return true;
	}

	private void rememberOverviewGlobalRow(int globalRow) {
		overviewGlobalRow = globalRow;
		overviewGlobalRowValid = globalRow >= 0;
	}

	private bool activeOverviewRow(out RowData row) {
		row = RowData.init;
		if(activeVoiceNum < 0 || activeVoiceNum >= 3)
			return false;
		if(activeView is null ||
				activeVoiceNum >= cast(int)activeView.voices.length)
			return false;

		Voice voice = activeView.voices[activeVoiceNum];
		if(voice is null)
			return false;

		activeView.activeVoice.trackFlush(activeView.posTable.pointerOffset);
		voice.refreshPointer(activeView.posTable.pointerOffset);
		row = voice.activeRow;
		return row.trkOffset >= 0 && row.seqOffset >= 0 &&
			row.track.trans < 0xf0 && row.seq !is null;
	}

	private bool cachedOverviewGlobalRowMatches(
			const(TrackOverviewLane)[] overview, RowData row) {
		if(!overviewGlobalRowValid || overviewGlobalRow < 0)
			return false;

		TrackOverviewPosition[] positions =
			resolveTrackOverviewPositions(overview, overviewGlobalRow);
		if(activeVoiceNum < 0 ||
				activeVoiceNum >= cast(int)positions.length)
			return false;
		if(activeVoiceNum >= cast(int)activeView.voices.length ||
				activeView.voices[activeVoiceNum] is null)
			return false;

		TrackOverviewPosition position = positions[activeVoiceNum];
		int cursorLocalRow =
			activeView.voices[activeVoiceNum].pos.rowCounter +
			activeView.posTable.pointerOffset;
		return position.valid &&
			position.trackIndex == row.trkOffset &&
			position.sequenceRowOffset == row.seqOffset &&
			position.localRow == cursorLocalRow;
	}

	private bool overviewGlobalRowFromActiveRow(
			const(TrackOverviewLane)[] overview, out int globalRow,
			out RowData row) {
		globalRow = -1;
		if(!activeOverviewRow(row))
			return false;

		if(cachedOverviewGlobalRowMatches(overview, row)) {
			globalRow = overviewGlobalRow;
			return true;
		}

		if(activeVoiceNum < 0 ||
				activeVoiceNum >= cast(int)overview.length)
			return false;

		foreach(block; overview[activeVoiceNum].blocks) {
			if(block.trackIndex != row.trkOffset)
				continue;
			if(row.seqOffset < 0 || row.seqOffset >= block.rowLength)
				continue;
			globalRow = block.startRow + row.seqOffset;
			return true;
		}
		return false;
	}

	private int trackOverviewLastGlobalRow(
			const(TrackOverviewLane)[] overview) {
		int maxRows;
		foreach(lane; overview) {
			if(lane.totalRows > maxRows)
				maxRows = lane.totalRows;
		}
		return maxRows > 0 ? maxRows - 1 : -1;
	}

	private int sequenceMovementMargin() {
		return sequenceMovementMarginForHeight(activeView.area.height);
	}

	private int sequenceTopAllowedVisibleRow() {
		return sequenceTopAllowedVisibleRowForHeight(activeView.area.height);
	}

	private int sequenceBottomAllowedVisibleRow() {
		return sequenceBottomAllowedVisibleRowForHeight(activeView.area.height);
	}

	private int clampSequenceVisibleRowToMovementWindow(int visibleRow) {
		int top = sequenceTopAllowedVisibleRow();
		int bottom = sequenceBottomAllowedVisibleRow();
		if(visibleRow < top)
			return top;
		if(visibleRow > bottom)
			return bottom;
		return visibleRow;
	}

	private void resetSequenceRowDragAutoScroll() {
		sequenceRowDragAutoScrollDirection =
			SequenceRowDragAutoScrollDirection.none;
		sequenceRowDragAutoScrollTicks = 0;
	}

	private void setSequenceRowDragAutoScrollDirection(
			SequenceRowDragAutoScrollDirection direction) {
		if(sequenceRowDragAutoScrollDirection != direction)
			sequenceRowDragAutoScrollTicks = 0;
		sequenceRowDragAutoScrollDirection = direction;
		if(direction == SequenceRowDragAutoScrollDirection.none)
			sequenceRowDragAutoScrollTicks = 0;
	}

	private bool moveSequenceTableToOverviewGlobalRow(
			const(TrackOverviewLane)[] overview, int globalRow,
			int desiredVisibleRow, int targetActiveVoice = -1) {
		if(activeView != sequenceTable || globalRow < 0)
			return false;
		int destinationVoice = targetActiveVoice >= 0 ?
			targetActiveVoice : activeVoiceNum;
		if(destinationVoice < 0 || destinationVoice >= 3)
			return false;

		TrackOverviewPosition[] positions =
			resolveTrackOverviewPositions(overview, globalRow);
		if(destinationVoice >= cast(int)positions.length ||
				!positions[destinationVoice].valid)
			return false;
		foreach(voice; 0 .. 3) {
			if(voice >= cast(int)positions.length ||
					!positions[voice].valid ||
					positions[voice].trackIndex < 0 ||
					positions[voice].sequenceRowOffset < 0)
				return false;
		}

		auto originalPos = activeView.posTable.dup();
		auto originalVoice = activeView.activeVoice;
		int originalVoiceNum = activeVoiceNum;

		desiredVisibleRow =
			clampSequenceVisibleRowToMovementWindow(desiredVisibleRow);
		int desiredPointer = desiredVisibleRow - anchor;

		if(activeView.activeVoice !is null)
			activeView.activeVoice.trackFlush(activeView.posTable.pointerOffset);
		activeView.posTable.pointerOffset = desiredPointer;
		foreach(voice; 0 .. 3) {
			if(activeView.voices[voice] is null) {
				activeView.posTable.copyFrom(originalPos);
				activeView.activeVoice = originalVoice;
				activeVoiceNum = originalVoiceNum;
				if(activeView.activeVoice !is null)
					input = activeView.activeVoice.activeInput;
				return false;
			}

			PosData pos = activeView.posTable.pos[voice];
			pos.trkOffset = positions[voice].trackIndex;
			pos.seqOffset = positions[voice].sequenceRowOffset -
				desiredPointer;
			pos.rowCounter = positions[voice].localRow - desiredPointer;
			activeView.voices[voice].refreshPointer(
				activeView.posTable.pointerOffset);
		}

		activeVoiceNum = destinationVoice;
		activeView.activeVoice = activeView.voices[destinationVoice];
		input = activeView.activeVoice.activeInput;

		bool ok = activeVoiceNum == destinationVoice &&
			activeView.posTable.pointerOffset + anchor == desiredVisibleRow;
		foreach(voice; 0 .. 3) {
			RowData row = activeView.voices[voice].activeRow;
			ok = ok &&
				row.trkOffset == positions[voice].trackIndex &&
				row.seqOffset == positions[voice].sequenceRowOffset &&
				row.track.smashedValue == positions[voice].trackValue;
		}
		if(ok) {
			rememberOverviewGlobalRow(globalRow);
			return true;
		}

		activeView.posTable.copyFrom(originalPos);
		activeView.activeVoice = originalVoice;
		activeVoiceNum = originalVoiceNum;
		if(activeView.activeVoice !is null)
			input = activeView.activeVoice.activeInput;
		activeView.refresh();
		return false;
	}

	private bool moveSequenceTableByOverviewRows(int rowDelta) {
		if(activeView != sequenceTable)
			return false;
		auto overview = buildTrackOverview(song);
		int lastRow = trackOverviewLastGlobalRow(overview);
		if(lastRow < 0)
			return false;
		int currentGlobalRow;
		RowData row;
		if(!overviewGlobalRowFromActiveRow(overview,
				currentGlobalRow, row))
			return false;

		int targetGlobalRow = currentGlobalRow + rowDelta;
		if(targetGlobalRow < 0)
			targetGlobalRow = 0;
		if(targetGlobalRow > lastRow)
			targetGlobalRow = lastRow;

		int desiredVisibleRow =
			clampSequenceVisibleRowToMovementWindow(
				activeView.posTable.normalPointerOffset + rowDelta);
		return moveSequenceTableToOverviewGlobalRow(overview,
			targetGlobalRow, desiredVisibleRow);
	}

	private int sequenceOverviewPageRows() {
		int pageRows = PAGESTEP * song.highlight;
		return pageRows < 1 ? 1 : pageRows;
	}

	private bool resolveActiveSequenceOverviewBlockBounds(
			const TrackOverviewLane[] overview, int currentGlobalRow,
			out int firstGlobalRow, out int lastGlobalRow) {
		firstGlobalRow = -1;
		lastGlobalRow = -1;
		if(activeVoiceNum < 0 || activeVoiceNum >= 3 ||
				activeVoiceNum >= cast(int)overview.length)
			return false;

		TrackOverviewPosition[] positions =
			resolveTrackOverviewPositions(overview, currentGlobalRow);
		if(activeVoiceNum >= cast(int)positions.length ||
				!positions[activeVoiceNum].valid)
			return false;

		TrackOverviewPosition position = positions[activeVoiceNum];
		const lane = overview[activeVoiceNum];
		if(position.blockIndex < 0 ||
				position.blockIndex >= cast(int)lane.blocks.length)
			return false;

		TrackOverviewBlock block = lane.blocks[position.blockIndex];
		int loopPassOffset = currentGlobalRow - position.localRow;
		firstGlobalRow = loopPassOffset + block.startRow;
		lastGlobalRow = loopPassOffset + block.endRow - 1;

		int overviewLastRow = trackOverviewLastGlobalRow(overview);
		if(firstGlobalRow < 0)
			firstGlobalRow = 0;
		if(lastGlobalRow > overviewLastRow)
			lastGlobalRow = overviewLastRow;
		return firstGlobalRow <= lastGlobalRow;
	}

	private bool moveSequenceRowSelectionToOverviewGlobalRow(
			const(TrackOverviewLane)[] overview, int currentGlobalRow,
			RowData currentRow, int targetGlobalRow, int desiredVisibleRow,
			int fixedRowOverride = -1) {
		TrackOverviewPosition[] targetPositions =
			resolveTrackOverviewPositions(overview, targetGlobalRow);
		if(activeVoiceNum < 0 ||
				activeVoiceNum >= cast(int)targetPositions.length)
			return false;
		TrackOverviewPosition target = targetPositions[activeVoiceNum];
		if(!target.valid || target.trackIndex != currentRow.trkOffset ||
				target.sequenceRowOffset != currentRow.seqOffset +
					(targetGlobalRow - currentGlobalRow))
			return false;

		SequenceRowSelectionSnapshot snapshot;
		if(!sequenceTable.captureSequenceRowSelectionSnapshot(snapshot) ||
				snapshot.voice != activeVoiceNum ||
				snapshot.trackIndex != currentRow.trkOffset ||
				snapshot.sequence !is currentRow.seq ||
				snapshot.activeRow != currentRow.seqOffset)
			return false;

		if(!moveSequenceTableToOverviewGlobalRow(overview,
				targetGlobalRow, desiredVisibleRow))
			return false;
		return sequenceTable.commitSequenceRowSelectionAfterMove(snapshot,
			fixedRowOverride);
	}

	private bool handleSequenceRowSelectionOverviewMove(
			KeyboardActionId actionId) {
		if(activeView != sequenceTable)
			return true;

		auto overview = buildTrackOverview(song);
		int currentGlobalRow;
		RowData currentRow;
		if(!overviewGlobalRowFromActiveRow(overview,
				currentGlobalRow, currentRow))
			return true;

		int firstGlobalRow;
		int lastGlobalRow;
		if(!resolveActiveSequenceOverviewBlockBounds(overview,
				currentGlobalRow, firstGlobalRow, lastGlobalRow))
			return true;

		bool selectAll = actionId == KeyboardActionId.sequenceRowSelectPattern;
		int targetGlobalRow;
		int desiredVisibleRow;
		switch(actionId) {
		case KeyboardActionId.sequenceRowSelectionExtendUp:
			targetGlobalRow = currentGlobalRow - 1;
			break;
		case KeyboardActionId.sequenceRowSelectionExtendDown:
			targetGlobalRow = currentGlobalRow + 1;
			break;
		case KeyboardActionId.sequenceRowSelectionExtendPageUp:
			targetGlobalRow = currentGlobalRow - sequenceOverviewPageRows();
			break;
		case KeyboardActionId.sequenceRowSelectionExtendPageDown:
			targetGlobalRow = currentGlobalRow + sequenceOverviewPageRows();
			break;
		case KeyboardActionId.sequenceRowSelectionExtendHome:
			targetGlobalRow = firstGlobalRow;
			break;
		case KeyboardActionId.sequenceRowSelectionExtendEnd:
			targetGlobalRow = lastGlobalRow;
			break;
		case KeyboardActionId.sequenceRowSelectPattern:
			targetGlobalRow = lastGlobalRow;
			break;
		default:
			return false;
		}

		if(targetGlobalRow < firstGlobalRow)
			targetGlobalRow = firstGlobalRow;
		if(targetGlobalRow > lastGlobalRow)
			targetGlobalRow = lastGlobalRow;
		if(targetGlobalRow == currentGlobalRow && !selectAll)
			return true;

		if(actionId == KeyboardActionId.sequenceRowSelectionExtendHome)
			desiredVisibleRow = sequenceTopAllowedVisibleRow();
		else if(actionId == KeyboardActionId.sequenceRowSelectionExtendEnd ||
				selectAll)
			desiredVisibleRow = sequenceBottomAllowedVisibleRow();
		else
			desiredVisibleRow = clampSequenceVisibleRowToMovementWindow(
				activeView.posTable.normalPointerOffset +
					(targetGlobalRow - currentGlobalRow));
		moveSequenceRowSelectionToOverviewGlobalRow(overview,
			currentGlobalRow, currentRow, targetGlobalRow, desiredVisibleRow,
			selectAll ? 0 : -1);
		return true;
	}

	private bool resolveVoiceLaneGlobalRow(int clickedVoice,
			int clickedVisibleRow, out TrackOverviewLane[] overview,
			out int targetGlobalRow, out bool targetInsideSong) {
		overview = buildTrackOverview(song);
		targetGlobalRow = -1;
		targetInsideSong = false;
		if(clickedVoice < 0 || clickedVoice >= 3 ||
				clickedVisibleRow < 0 ||
				clickedVisibleRow >= activeView.area.height)
			return false;

		int currentGlobalRow;
		RowData row;
		if(!overviewGlobalRowFromActiveRow(overview, currentGlobalRow, row))
			return false;

		targetGlobalRow = currentGlobalRow +
			(clickedVisibleRow - activeView.posTable.normalPointerOffset);
		int lastRow = trackOverviewLastGlobalRow(overview);
		if(lastRow < 0)
			return false;
		targetInsideSong = targetGlobalRow >= 0 && targetGlobalRow <= lastRow;
		if(targetGlobalRow < 0)
			targetGlobalRow = 0;
		if(targetGlobalRow > lastRow)
			targetGlobalRow = lastRow;

		TrackOverviewPosition[] positions =
			resolveTrackOverviewPositions(overview, targetGlobalRow);
		return clickedVoice < cast(int)positions.length &&
			positions[clickedVoice].valid;
	}

	private bool resolveTrackHeaderGlobalRow(int clickedVoice,
			int clickedVisibleRow, out TrackOverviewLane[] overview,
			out int targetGlobalRow) {
		overview = buildTrackOverview(song);
		targetGlobalRow = -1;
		if(clickedVoice < 0 || clickedVoice >= 3 ||
				clickedVisibleRow < 0 ||
				clickedVisibleRow >= activeView.area.height)
			return false;

		int currentGlobalRow;
		RowData row;
		if(!overviewGlobalRowFromActiveRow(overview, currentGlobalRow, row))
			return false;

		int cursorScreenRow = activeView.posTable.pointerOffset + anchor;
		targetGlobalRow = currentGlobalRow +
			(clickedVisibleRow - cursorScreenRow);
		int lastRow = trackOverviewLastGlobalRow(overview);
		if(lastRow < 0)
			return false;
		if(targetGlobalRow < 0)
			targetGlobalRow = 0;
		if(targetGlobalRow > lastRow)
			targetGlobalRow = lastRow;

		TrackOverviewPosition[] positions =
			resolveTrackOverviewPositions(overview, targetGlobalRow);
		return clickedVoice < cast(int)positions.length &&
			positions[clickedVoice].valid;
	}

	private bool routePatternClickToSequenceTable(int clickedVoice,
			int clickedVisibleRow, int localX, int localY, int button) {
		if(activeView != sequenceTable && activeView != trackTable)
			return false;
		bool startedInSequenceTable = activeView == sequenceTable;
		if(startedInSequenceTable && button == 1)
			sequenceTable.cancelSequenceRowDrag();

		TrackOverviewLane[] overview;
		int targetGlobalRow;
		bool targetInsideSong;
		if(!resolveVoiceLaneGlobalRow(clickedVoice, clickedVisibleRow,
				overview, targetGlobalRow, targetInsideSong))
			return false;

		bool shiftClick = button == 1 &&
			(SDL_GetModState() & KMOD_SHIFT) != 0;
		SequenceRowSelectionSnapshot selectionSnapshot;
		bool hasSelectionSnapshot = shiftClick &&
			activeView == sequenceTable &&
			sequenceTable.captureSequenceRowSelectionSnapshot(
				selectionSnapshot);

		if(activeView != sequenceTable)
			activateSequenceTable();
		activateVoice(clickedVoice);
		if(!moveSequenceTableToOverviewGlobalRow(overview,
				targetGlobalRow, clickedVisibleRow))
			return false;

		sequenceTable.useCurrentRowForNextMouseClick();
		sequenceTable.clickedAt(localX, localY, button);
		if(shiftClick) {
			if(hasSelectionSnapshot)
				sequenceTable.commitSequenceRowSelectionAfterClick(
					selectionSnapshot);
			else
				sequenceTable.clearSequenceRowSelection();
		}
		else if(button == 1 && startedInSequenceTable && targetInsideSong)
			sequenceTable.beginSequenceRowDragCandidate();
		return true;
	}

	private bool moveTrackTableHeaderClickToOverviewGlobalRow(int x, int y) {
		if(activeView != sequenceTable && activeView != trackTable)
			return false;

		int clickedVoice;
		int clickedTrackIndex;
		ushort clickedTrackValue;
		int clickedVisibleRow;
		if(!trackTable.resolveRenderedTrackHeaderClick(x, y,
				clickedVoice, clickedTrackIndex, clickedTrackValue,
				clickedVisibleRow))
			return false;

		TrackOverviewLane[] overview;
		int targetGlobalRow;
		if(!resolveTrackHeaderGlobalRow(clickedVoice, clickedVisibleRow,
				overview, targetGlobalRow))
			return false;

		TrackOverviewPosition[] positions =
			resolveTrackOverviewPositions(overview, targetGlobalRow);
		if(clickedVoice >= cast(int)positions.length ||
				!positions[clickedVoice].valid ||
				positions[clickedVoice].trackIndex != clickedTrackIndex ||
				positions[clickedVoice].trackValue != clickedTrackValue ||
				positions[clickedVoice].sequenceRowOffset != 0)
			return false;

		VoiceTable previousView = activeView;
		PosDataTable previousPos = activeView.posTable.dup();
		int previousVoice = activeVoiceNum;
		bool switchedView = activeView != trackTable;
		if(switchedView) {
			activeView.deactivate();
			activeView = trackTable;
			activeView.activate();
		}

		if(!moveEditorCursorToOverviewPositionsSafeForActiveView(positions,
				clickedVoice)) {
			if(switchedView) {
				activeView.deactivate();
				activeView.posTable.copyFrom(previousPos);
				activeVoiceNum = previousVoice;
				activeView = previousView;
				activeView.activate();
				input = activeView.input;
			}
			return false;
		}

		trackTable.rememberTrackEntryClickAt(clickedVoice,
			clickedTrackIndex);
		storeF5PlaybackAnchor(targetGlobalRow, positions, clickedVoice);
		return true;
	}

	private bool moveSequenceTableToActiveOverviewBlockEdge(bool toEnd) {
		if(activeView != sequenceTable)
			return false;
		if(activeVoiceNum < 0 || activeVoiceNum >= 3)
			return false;

		auto overview = buildTrackOverview(song);
		if(trackOverviewLastGlobalRow(overview) < 0 ||
				activeVoiceNum >= cast(int)overview.length)
			return false;

		int currentGlobalRow;
		RowData row;
		if(!overviewGlobalRowFromActiveRow(overview,
				currentGlobalRow, row))
			return false;

		int firstGlobalRow;
		int lastGlobalRow;
		if(!resolveActiveSequenceOverviewBlockBounds(overview,
				currentGlobalRow, firstGlobalRow, lastGlobalRow))
			return false;
		int targetGlobalRow = toEnd ? lastGlobalRow : firstGlobalRow;

		int desiredVisibleRow = toEnd ?
			sequenceBottomAllowedVisibleRow() :
			sequenceTopAllowedVisibleRow();
		return moveSequenceTableToOverviewGlobalRow(overview,
			targetGlobalRow, desiredVisibleRow);
	}

	private bool handleSequenceOverviewHomeEndNavigation(Keyinfo key) {
		if(activeView != sequenceTable)
			return false;

		KeyboardActionId actionId;
		if(!resolveSequencerKeyboardAction(key, actionId))
			return false;
		bool toEnd;
		switch(actionId) {
		case KeyboardActionId.sequencerOverviewNavigateHome:
			toEnd = false;
			break;
		case KeyboardActionId.sequencerOverviewNavigateEnd:
			toEnd = true;
			break;
		default:
			return false;
		}
		sequenceTable.clearSequenceRowSelection();
		moveSequenceTableToActiveOverviewBlockEdge(toEnd);
		return true;
	}

	private bool handleTrackEditorOverviewHomeEndNavigation(Keyinfo key) {
		if(activeView != trackTable && activeView != trackmapTable)
			return false;

		KeyboardActionId actionId;
		if(!resolveTrackEntryNavigationKeyboardAction(key, actionId))
			return false;

		bool toEnd;
		switch(actionId) {
		case KeyboardActionId.trackEntryNavigateStart:
			toEnd = false;
			break;
		case KeyboardActionId.trackEntryNavigateEnd:
			toEnd = true;
			break;
		default:
			return false;
		}

		auto overview = buildTrackOverview(song);
		if(activeVoiceNum < 0 ||
				activeVoiceNum >= cast(int)overview.length)
			return true;

		const lane = overview[activeVoiceNum];
		if(lane.blocks.length == 0)
			return true;

		TrackOverviewBlock targetBlock = toEnd ?
			lane.blocks[$ - 1] : lane.blocks[0];
		TrackOverviewPosition[] positions =
			resolveTrackOverviewPositions(overview, targetBlock.startRow);
		moveEditorCursorToOverviewPositionsSafeForActiveView(positions,
			activeVoiceNum);
		return true;
	}

	private bool overviewBlockForTrackIndex(const TrackOverviewLane lane,
			int trackIndex, out TrackOverviewBlock block) {
		block = TrackOverviewBlock.init;
		foreach(candidate; lane.blocks) {
			if(candidate.trackIndex == trackIndex) {
				block = candidate;
				return true;
			}
		}
		return false;
	}

	private int nearestPhysicalBlockGlobalRow(
			const TrackOverviewLane lane, TrackOverviewBlock block,
			int currentGlobalRow, int direction) {
		int targetGlobalRow = block.startRow;
		if(!lane.hasValidLoop || lane.loopLengthRows <= 0 ||
				block.startRow < lane.wrapStartRow ||
				block.startRow >= lane.loopEndRow)
			return targetGlobalRow;

		if(direction > 0) {
			while(targetGlobalRow <= currentGlobalRow)
				targetGlobalRow += lane.loopLengthRows;
		}
		else {
			while(targetGlobalRow + lane.loopLengthRows < currentGlobalRow)
				targetGlobalRow += lane.loopLengthRows;
		}
		return targetGlobalRow;
	}

	private bool moveActiveTrackOrderByPhysicalEntry(int direction) {
		auto overview = buildTrackOverview(song);
		int currentGlobalRow;
		RowData row;
		if(!overviewGlobalRowFromActiveRow(overview,
				currentGlobalRow, row))
			return false;
		if(activeVoiceNum < 0 ||
				activeVoiceNum >= cast(int)overview.length)
			return false;
		if(activeVoiceNum >= cast(int)activeView.voices.length ||
				activeView.voices[activeVoiceNum] is null)
			return false;

		int targetTrackIndex = row.trkOffset + direction;
		Voice voice = activeView.voices[activeVoiceNum];
		if(targetTrackIndex < 0 ||
				targetTrackIndex >= voice.tracks.trackLength)
			return false;
		if(voice.tracks[targetTrackIndex].trans >= 0xf0)
			return false;

		TrackOverviewBlock targetBlock;
		if(!overviewBlockForTrackIndex(overview[activeVoiceNum],
				targetTrackIndex, targetBlock))
			return false;

		int targetGlobalRow = nearestPhysicalBlockGlobalRow(
			overview[activeVoiceNum], targetBlock, currentGlobalRow,
			direction);
		TrackOverviewPosition[] positions =
			resolveTrackOverviewPositions(overview, targetGlobalRow);
		if(activeVoiceNum >= cast(int)positions.length)
			return false;

		TrackOverviewPosition activePosition = positions[activeVoiceNum];
		if(!activePosition.valid ||
				activePosition.trackIndex != targetTrackIndex ||
				activePosition.sequenceRowOffset != 0)
			return false;

		return moveEditorCursorToOverviewPositionsSafeForActiveView(
			positions, activeVoiceNum);
	}

	private bool moveActiveTrackOrderByPhysicalPageEntries(int entryDelta) {
		if((activeView != trackTable && activeView != trackmapTable) ||
				entryDelta == 0)
			return false;

		auto overview = buildTrackOverview(song);
		int currentGlobalRow;
		RowData row;
		if(!overviewGlobalRowFromActiveRow(overview,
				currentGlobalRow, row))
			return false;
		if(activeVoiceNum < 0 ||
				activeVoiceNum >= cast(int)overview.length)
			return false;

		const lane = overview[activeVoiceNum];
		if(lane.blocks.length == 0)
			return false;

		TrackOverviewPosition[] currentPositions =
			resolveTrackOverviewPositions(overview, currentGlobalRow);
		if(activeVoiceNum >= cast(int)currentPositions.length)
			return false;
		TrackOverviewPosition currentPosition =
			currentPositions[activeVoiceNum];
		if(!currentPosition.valid || currentPosition.blockIndex < 0 ||
				currentPosition.blockIndex >= cast(int)lane.blocks.length)
			return false;

		int targetOrdinal = currentPosition.blockIndex + entryDelta;
		if(targetOrdinal < 0)
			targetOrdinal = 0;
		else if(targetOrdinal >= cast(int)lane.blocks.length)
			targetOrdinal = cast(int)lane.blocks.length - 1;
		if(targetOrdinal == currentPosition.blockIndex)
			return true;

		TrackOverviewBlock targetBlock = lane.blocks[targetOrdinal];
		int direction = entryDelta < 0 ? -1 : 1;
		int targetGlobalRow = nearestPhysicalBlockGlobalRow(
			lane, targetBlock, currentGlobalRow, direction);
		TrackOverviewPosition[] targetPositions =
			resolveTrackOverviewPositions(overview, targetGlobalRow);
		if(activeVoiceNum >= cast(int)targetPositions.length)
			return false;

		TrackOverviewPosition activePosition =
			targetPositions[activeVoiceNum];
		if(!activePosition.valid ||
				activePosition.trackIndex != targetBlock.trackIndex ||
				activePosition.sequenceRowOffset != 0)
			return false;

		return moveEditorCursorToOverviewPositionsSafeForActiveView(
			targetPositions, activeVoiceNum);
	}

	private bool loopAwareOverviewNavigationDelta(Keyinfo key,
			out int rowDelta, out KeyboardActionId actionId) {
		rowDelta = 0;
		if(!resolveSequencerKeyboardAction(key, actionId))
			return false;
		switch(actionId) {
		case KeyboardActionId.sequencerOverviewNavigateDown:
			rowDelta = 1;
			return true;
		case KeyboardActionId.sequencerOverviewNavigateUp:
			rowDelta = -1;
			return true;
		case KeyboardActionId.sequencerOverviewNavigatePageDown:
			rowDelta = sequenceOverviewPageRows();
			return true;
		case KeyboardActionId.sequencerOverviewNavigatePageUp:
			rowDelta = -sequenceOverviewPageRows();
			return true;
		default:
			return false;
		}
	}

	private bool handleLoopAwareOverviewNavigation(Keyinfo key) {
		int rowDelta;
		KeyboardActionId actionId;
		if(!loopAwareOverviewNavigationDelta(key, rowDelta, actionId))
			return false;
		if(activeView == sequenceTable) {
			sequenceTable.clearSequenceRowSelection();
			moveSequenceTableByOverviewRows(rowDelta);
			return true;
		}
		return false;
	}

	private bool handleTrackmapPhysicalOverviewNavigation(Keyinfo key) {
		int direction;
		KeyboardActionId actionId;
		if(!loopAwareOverviewNavigationDelta(key, direction, actionId))
			return false;
		if(actionId != KeyboardActionId.sequencerOverviewNavigateUp &&
				actionId != KeyboardActionId.sequencerOverviewNavigateDown)
			return false;
		if(activeView != trackmapTable)
			return false;
		moveActiveTrackOrderByPhysicalEntry(direction);
		return true;
	}

	private bool handleTrackmapPhysicalOverviewPageNavigation(Keyinfo key) {
		if(activeView != trackmapTable)
			return false;
		int navigationDelta;
		KeyboardActionId actionId;
		if(!loopAwareOverviewNavigationDelta(key, navigationDelta, actionId) ||
				(actionId != KeyboardActionId.sequencerOverviewNavigatePageUp &&
				 actionId != KeyboardActionId.sequencerOverviewNavigatePageDown))
			return false;

		int pageEntries = cast(int)song.highlight;
		if(pageEntries < 1)
			pageEntries = 1;
		int entryDelta = navigationDelta < 0 ? -pageEntries : pageEntries;
		moveActiveTrackOrderByPhysicalPageEntries(entryDelta);
		return true;
	}

	private bool handleTrackTablePhysicalOverviewNavigation(Keyinfo key) {
		int direction;
		KeyboardActionId actionId;
		if(!loopAwareOverviewNavigationDelta(key, direction, actionId))
			return false;
		if(actionId != KeyboardActionId.sequencerOverviewNavigateUp &&
				actionId != KeyboardActionId.sequencerOverviewNavigateDown)
			return false;
		if(activeView != trackTable)
			return false;
		moveActiveTrackOrderByPhysicalEntry(direction);
		return true;
	}

	private bool handleTrackTablePhysicalOverviewPageNavigation(Keyinfo key) {
		if(activeView != trackTable)
			return false;

		int navigationDelta;
		KeyboardActionId actionId;
		if(!loopAwareOverviewNavigationDelta(key, navigationDelta, actionId) ||
				(actionId != KeyboardActionId.sequencerOverviewNavigatePageUp &&
				 actionId != KeyboardActionId.sequencerOverviewNavigatePageDown))
			return false;
		int pageEntries = cast(int)song.highlight;
		if(pageEntries < 1)
			pageEntries = 1;
		int entryDelta = navigationDelta < 0 ? -pageEntries : pageEntries;

		moveActiveTrackOrderByPhysicalPageEntries(entryDelta);
		return true;
	}

	private bool moveTrackmapCursorToOverviewPositions(
			const TrackOverviewPosition[] positions, int activeVoice) {
		if(activeView != trackmapTable || activeVoice < 0 ||
				activeVoice >= 3 || positions.length < 3 ||
				!positions[activeVoice].valid)
			return false;
		foreach(voice; 0 .. 3) {
			if(!positions[voice].valid ||
					positions[voice].trackIndex < 0 ||
					positions[voice].sequenceRowOffset < 0)
				return false;
		}
		if(trackmapTable.activeVoice is null ||
				activeVoice >= cast(int)trackmapTable.voices.length ||
				trackmapTable.voices[activeVoice] is null)
			return false;

		// F7 overview-position moves use loop-aware time resolution, but apply
		// without TrackmapTable.activate() re-centering/re-jumping.
		trackmapTable.activeVoice.trackFlush(trackmapTable.posTable.pointerOffset);
		trackmapTable.posTable.pointerOffset = 0;
		foreach(voice; 0 .. 3) {
			PosData pos = trackmapTable.posTable.pos[voice];
			pos.trkOffset = positions[voice].trackIndex;
			pos.seqOffset = positions[voice].sequenceRowOffset;
			pos.rowCounter = positions[voice].localRow;
		}
		activeVoiceNum = activeVoice;
		trackmapTable.activeVoice = trackmapTable.voices[activeVoice];
		if(trackmapTable.activeVoice is null ||
				trackmapTable.activeVoice.activeInput is null)
			return false;
		trackmapTable.input = trackmapTable.activeVoice.activeInput;
		input = trackmapTable.input;
		trackmapTable.refresh();
		return true;
	}

	private bool resolveTrackmapActivationTarget(out int targetVoice,
			out TrackOverviewPosition[] targetPositions) {
		targetVoice = activeVoiceNum;
		targetPositions = null;
		if(targetVoice < 0 || targetVoice >= 3)
			return false;

		auto overview = buildTrackOverview(song);
		int currentGlobalRow;
		RowData row;
		if(!overviewGlobalRowFromActiveRow(overview, currentGlobalRow, row))
			return false;

		TrackOverviewPosition[] currentPositions =
			resolveTrackOverviewPositions(overview, currentGlobalRow);
		if(targetVoice >= cast(int)currentPositions.length)
			return false;
		TrackOverviewPosition currentPosition = currentPositions[targetVoice];
		if(!currentPosition.valid ||
				currentPosition.trackIndex != row.trkOffset ||
				currentPosition.sequenceRowOffset != row.seqOffset)
			return false;

		int targetGlobalRow = currentGlobalRow -
			currentPosition.sequenceRowOffset;
		if(targetGlobalRow < 0)
			return false;

		targetPositions = resolveTrackOverviewPositions(overview,
			targetGlobalRow);
		if(targetPositions.length < 3)
			return false;
		foreach(position; targetPositions) {
			if(!position.valid || position.trackIndex < 0 ||
					position.sequenceRowOffset < 0 ||
					position.globalRow != targetGlobalRow)
				return false;
		}

		TrackOverviewPosition activePosition = targetPositions[targetVoice];
		return activePosition.trackIndex == row.trkOffset &&
			activePosition.trackValue == row.track.smashedValue &&
			activePosition.sequenceRowOffset == 0;
	}

		bool moveEditorCursorToTrackBlockStart(int voice, int trackIndex) {
			if(voice < 0 || voice >= 3 || trackIndex < 0)
				return false;

			auto overview = buildTrackOverview(song);
			if(voice >= cast(int)overview.length)
				return false;

			TrackOverviewBlock targetBlock;
			bool foundBlock;
			foreach(block; overview[voice].blocks) {
				if(block.trackIndex != trackIndex)
					continue;
				targetBlock = block;
				foundBlock = true;
				break;
			}
			if(!foundBlock)
				return false;

			TrackOverviewPosition[] positions =
				resolveTrackOverviewPositions(overview, targetBlock.startRow);
			if(positions.length < 3)
				return false;
			foreach(position; positions) {
				if(!position.valid || position.trackIndex < 0 ||
						position.sequenceRowOffset < 0)
					return false;
			}
			TrackOverviewPosition targetPosition = positions[voice];
			if(targetPosition.trackIndex != trackIndex ||
					targetPosition.sequenceRowOffset != 0)
				return false;

			activeView.activeVoice.trackFlush(activeView.posTable.pointerOffset);
			enterToggleRestoreValid = false;
			overviewGlobalRowValid = false;
			if(activeView != sequenceTable)
				activateSequenceTable();

			activateVoice(voice);
			return moveSequenceTableToOverviewGlobalRow(overview,
				targetBlock.startRow, anchor);
		}

		private bool handleSequencerViewSwitchKey(Keyinfo key,
				bool forceTargetView = false) {
			KeyboardActionId actionId;
			if(!resolveSequencerKeyboardAction(key, actionId))
				return false;

			switch(actionId) {
			case KeyboardActionId.sequencerViewTrackTable:
			case KeyboardActionId.sequencerViewTrackTableWithTrackList:
				if(activeView != trackTable) {
					if(activeView == sequenceTable) {
						resetSequenceRowDragAutoScroll();
						rememberEnterTogglePosition();
					}
					activateTrackTable();
				}
				trackTable.displayTracklist =
					actionId == KeyboardActionId.sequencerViewTrackTableWithTrackList;
				return true;
			case KeyboardActionId.sequencerViewSequenceEditor:
				activateSequenceTable();
				return true;
			case KeyboardActionId.sequencerViewTrackMap:
				if(activeView == trackmapTable && !forceTargetView) {
					activeView.deactivate();
					activeView.toSeqStart();
					activeView = trackTable;
					activeView.activate();
					return true;
				}
				else if(activeView != trackmapTable) {
					if(activeView == sequenceTable) {
						resetSequenceRowDragAutoScroll();
						clearSequenceNavigationEntryProgress();
					}
					int targetVoice;
					TrackOverviewPosition[] targetPositions;
					bool hasTarget = resolveTrackmapActivationTarget(targetVoice,
						targetPositions);
					activeView.deactivate();
					activeView = trackmapTable;
					if(hasTarget &&
							moveEditorCursorToOverviewPositionsSafeForActiveView(
								targetPositions, targetVoice))
						return true;

					overviewGlobalRowValid = false;
					trackmapTable.toSeqStart();
					activeView.activate();
					auto overview = buildTrackOverview(song);
					int fallbackGlobalRow;
					RowData fallbackRow;
					if(overviewGlobalRowFromActiveRow(overview,
							fallbackGlobalRow, fallbackRow))
						rememberOverviewGlobalRow(fallbackGlobalRow);
					return true;
				}
				activeView.deactivate();
				activeView.activate();
				return true;
			case KeyboardActionId.sequencerViewToggleTrackSequence:
				if(activeView == sequenceTable)
					return handleSequenceReturnNavigation();
				if(activeView == trackTable) {
					PosDataTable restorePos = null;
					if(canRestoreEnterTogglePosition())
						restorePos = enterTogglePos;
					enterToggleRestoreValid = false;
					activateSequenceTable(restorePos);
					return true;
				}
				return false;
			default:
				return false;
			}
		}

		private bool handleSequenceReturnNavigation() {
			auto sequenceInput = cast(InputSeq)sequenceTable.input;
			if(sequenceInput is null)
				return true;

			switch(sequenceInput.currentNavigationColumn) {
			case InputSeq.noteColumn:
			case InputSeq.octaveColumn:
				rememberEnterTogglePosition();
				activateTrackTable();
				trackTable.displayTracklist = false;
				return true;
			case InputSeq.instrumentColumn:
				if(!sequenceInput.currentNavigationValueIsComplete())
					return true;
				int instrument;
				if(sequenceInput.currentInstrumentNavigationValue(instrument)) {
					F6OriginMarker marker;
					bool hasMarker = captureF6OriginMarker(
						SequenceOriginDestination.instrument, marker);
					if(mainui.activateInstrumentTable(instrument)) {
						if(hasMarker)
							f6OriginMarker = marker;
						else
							clearF6OriginMarker();
					}
				}
				return true;
			case InputSeq.commandColumn:
				if(!sequenceInput.currentNavigationValueIsComplete())
					return true;
				auto reference = decodeSequenceCommandReference(
					sequenceInput.currentCommandNavigationValue());
				SequenceOriginDestination destination =
					sequenceOriginDestination(reference.kind);
				if(destination != SequenceOriginDestination.none) {
					F6OriginMarker marker;
					bool hasMarker = captureF6OriginMarker(destination, marker);
					if(mainui.activateSequenceCommandReference(reference)) {
						if(hasMarker)
							f6OriginMarker = marker;
						else
							clearF6OriginMarker();
					}
				}
				return true;
			default:
				return true;
			}
		}

		private static SequenceOriginDestination sequenceOriginDestination(
				SequenceCommandReferenceKind kind) {
			final switch(kind) {
			case SequenceCommandReferenceKind.none:
				return SequenceOriginDestination.none;
			case SequenceCommandReferenceKind.command:
				return SequenceOriginDestination.command;
			case SequenceCommandReferenceKind.pulse:
				return SequenceOriginDestination.pulse;
			case SequenceCommandReferenceKind.filter:
				return SequenceOriginDestination.filter;
			case SequenceCommandReferenceKind.chord:
				return SequenceOriginDestination.chord;
			}
		}

		bool handleNonModalEditorViewSwitchKey(Keyinfo key) {
			return handleSequencerViewSwitchKey(key, true);
		}

		private bool isDirectSequenceRowCountAction(Keyinfo key) {
			KeyboardActionId actionId;
			if(resolveSequenceEditorCommandKeyboardAction(key, actionId))
				return actionId == KeyboardActionId.sequenceRowQuickExpand;
			if(resolveSequenceRowStructureKeyboardAction(key, actionId))
				return actionId == KeyboardActionId.sequenceRowInsertGrow ||
					actionId == KeyboardActionId.sequenceRowDeleteShrink;
			return resolveSequenceExpandShrinkKeyboardAction(key, actionId) &&
				(actionId == KeyboardActionId.sequenceRowExpandSequence ||
				 actionId == KeyboardActionId.sequenceRowShrinkSequence);
		}

		private int executeSequenceRowCountMutation(Sequence destination,
				int delegate(int) mutation) {
			if(activeView != sequenceTable || destination is null ||
					destination !is activeView.getActiveSequence())
				return OK;

			auto oldOverview = buildTrackOverview(song);
			int oldGlobalRow;
			RowData oldRow;
			bool hasOldGlobalRow = overviewGlobalRowFromActiveRow(oldOverview,
				oldGlobalRow, oldRow);
			int oldRows = destination.rows;
			TrackOverviewOccurrence occurrence;
			if(hasOldGlobalRow && activeVoiceNum >= 0 &&
					activeVoiceNum < cast(int)oldOverview.length)
				occurrence = trackOverviewOccurrenceAtGlobalRow(
					oldOverview[activeVoiceNum], oldGlobalRow);

			int result = mutation(oldRows);
			if(destination.rows == oldRows)
				return result;

			int desiredVisibleRow = activeView.posTable.normalPointerOffset;
			overviewGlobalRowValid = false;
			if(!occurrence.valid)
				return result;

			RowData newRow;
			if(!activeOverviewRow(newRow))
				return result;
			auto newOverview = buildTrackOverview(song);
			if(activeVoiceNum < 0 ||
					activeVoiceNum >= cast(int)newOverview.length)
				return result;

			int newGlobalRow;
			if(!trackOverviewGlobalRowForOccurrence(newOverview[activeVoiceNum],
					newRow.trkOffset, newRow.seqOffset, occurrence, newGlobalRow))
				return result;
			moveSequenceTableToOverviewGlobalRow(newOverview, newGlobalRow,
				desiredVisibleRow);
			return result;
		}

		private bool handleDirectSequenceRowCountAction(Keyinfo key,
				out int result) {
			result = OK;
			if(activeView != sequenceTable ||
					!isDirectSequenceRowCountAction(key))
				return false;

			int delegate(int) mutation = (int oldRows) {
				return activeView.keypress(key);
			};
			result = executeSequenceRowCountMutation(
				activeView.getActiveSequence(), mutation);
			return true;
		}

		bool handleFocusedStructuralKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(activeView == sequenceTable) {
				if(!resolveSequenceRowStructureKeyboardAction(key, actionId))
					return false;
			}
			else if(activeView == trackTable || activeView == trackmapTable) {
				if(!resolveTrackEntryStructuralKeyboardAction(key, actionId))
					return false;
			}
			else {
				return false;
			}

			keypress(key);
			return true;
		}

		override int keypress(Keyinfo key) {
			if(handleSubtuneEditorKey(key))
				return OK;

				KeyboardActionId loopActionId;
				if(resolveTrackEntryLoopSetActiveVoiceKeyboardAction(key,
						loopActionId)) {
					if(!audio.player.isPlaying || audio.player.keyjamEnabled)
						setLoopTargetForActiveTrackEntry();
				return OK;
			}

		if(handleSequenceRowClipboardShortcut(key))
			return OK;

		if(handleTrackmapPhysicalOverviewPageNavigation(key))
			return OK;

		if(handleTrackmapPhysicalOverviewNavigation(key))
			return OK;

		if(handleSequenceOverviewHomeEndNavigation(key))
			return OK;

		if(handleTrackEditorOverviewHomeEndNavigation(key))
			return OK;

		if(handleTrackTablePhysicalOverviewPageNavigation(key))
			return OK;

		if(handleLoopAwareOverviewNavigation(key))
			return OK;

			if(handleTrackTablePhysicalOverviewNavigation(key))
				return OK;

				if(handleSequencerViewSwitchKey(key))
					return OK;

		KeyboardActionId sequencerActionId;
		bool hasSequencerAction = resolveSequencerKeyboardAction(key,
			sequencerActionId);
		if(hasSequencerAction) {
			if(executeSubtuneAction(sequencerActionId))
				return OK;
			switch(sequencerActionId) {
			default:
				break;
			}
		}

		KeyboardActionId cursorStepActionId;
		int keypadStep;
		if(resolveSequencerCursorStepKeyboardAction(key, cursorStepActionId,
				keypadStep)) {
				stepValue = keypadStep;
			return OK;
		}
		int sequenceRowCountResult;
		if(handleDirectSequenceRowCountAction(key, sequenceRowCountResult))
			return sequenceRowCountResult;
		KeyboardActionId sequenceDialogActionId;
			if(resolveSequenceDialogKeyboardAction(key, sequenceDialogActionId)) {
				if(activeView != sequenceTable)
					return OK;
				switch(sequenceDialogActionId) {
				case KeyboardActionId.sequenceOpenAppendDialog:
					openSequenceAppendDialog();
					break;
				case KeyboardActionId.sequenceOpenCopyDialog:
					openSequenceCopyDialog();
					break;
			default:
				break;
			}
			return OK;
		}
		if(hasSequencerAction) {
			switch(sequencerActionId) {
			case KeyboardActionId.sequencerDebugSequenceDialog:
				mainui.activateDialog(
					new DebugDialog(activeView.activeVoice.activeRow.seq));
				return OK;
			default:
				break;
			}
		}
		return activeView.keypress(key);
	}

	override int keyrelease(Keyinfo key) {
		stepCounter = 0;
		// lazily skipping the "view" layer (so no keyrelease event ever gets there at the moment)
		activeView.activeVoice.keyrelease(key);
		return OK;
	}

	private static string subtuneQuickHelp() {
		return "Subtune: 00-1F. Up/Down changes selection.";
	}

	private void focusSubtuneEditor(int digit) {
		subtuneEditorFocused = true;
		subtuneInput.beginEdit();
		subtuneInput.setCursorDigit(digit);
		input = subtuneInput;
		if(UI.statusline !is null)
			UI.statusline.displayContextualSemantic(subtuneQuickHelp(),
				"sequencer:subtune");
	}

	private void cancelSubtuneEditor() {
		if(!subtuneEditorFocused)
			return;
		subtuneEditorFocused = false;
		input = activeView.input;
	}

	private bool executeSubtuneAction(KeyboardActionId actionId) {
		switch(actionId) {
		case KeyboardActionId.sequencerSubtuneNext:
			changeSubtune(1);
			return true;
		case KeyboardActionId.sequencerSubtunePrevious:
			changeSubtune(0);
			return true;
		default:
			return false;
		}
	}

	private bool handleSubtuneEditorKey(Keyinfo key) {
		if(!subtuneEditorFocused)
			return false;

		int result = subtuneInput.keypress(key);
		if(result == RETURN)
			cancelSubtuneEditor();
		else if(result == CANCEL)
			cancelSubtuneEditor();
		return true;
	}

	private bool voiceAreaOverlapsPointer(Voice v, int x, int y) {
		if(v.area.overlaps(x, y))
			return true;
		if(activeView != sequenceTable)
			return false;
		return x >= v.area.x && x < v.area.x + v.area.width &&
			y == v.area.y + v.area.height;
	}

	override void clickedAt(int x, int y, int button) {
		if(button == 1 && subtuneSelectorValueCellAt(area.x, area.y, x, y)) {
			focusSubtuneEditor(x -
				(area.x + SUBTUNE_SELECTOR_VALUE_X_OFFSET));
			return;
		}
		if(subtuneEditorFocused)
			cancelSubtuneEditor();
		foreach(idx, Voice v; activeView.voices) {
			if(!voiceAreaOverlapsPointer(v, x, y))
				continue;

			int localX = x - area.x;
			int localY = y - area.y;
			int voiceLocalX = x - v.area.x;
			int clickedVisibleRow = localY - 1;

			if(activeView == trackmapTable) {
				int clickedVoice, clickedTrackIndex;
				if(trackmapTable.clickTargetAtLocalPoint(localX, localY,
						clickedVoice, clickedTrackIndex))
					moveTrackmapClickToOverviewResolvedPosition(clickedVoice,
						clickedTrackIndex);
				return;
			}

			if(voiceLocalX >= 0 &&
					voiceLocalX <= TRACK_HEADER_LOCAL_X_END) {
				moveTrackTableHeaderClickToOverviewGlobalRow(localX, localY);
				return;
			}

			if(voiceLocalX >= PATTERN_CELL_LOCAL_X &&
					voiceLocalX <= PATTERN_CELL_LOCAL_X_END) {
				routePatternClickToSequenceTable(cast(int)idx,
					clickedVisibleRow, localX, localY, button);
				return;
			}

			if(voiceLocalX == VOICE_SEPARATOR_LOCAL_X)
				return;

			// All other in-lane cells are inert.
			return;
		}
	}

	private bool updateSequenceRowDragAt(int x, int y) {
		if(activeView != sequenceTable ||
				!sequenceTable.sequenceRowDragInProgress() ||
				!activeView.area.overlaps(x, y)) {
			resetSequenceRowDragAutoScroll();
			return false;
		}

		int visibleRow = y - area.y - 1;
		if(visibleRow < 0 || visibleRow >= activeView.area.height) {
			resetSequenceRowDragAutoScroll();
			return false;
		}

		auto autoScrollDirection = sequenceRowDragAutoScrollDirectionForRow(
			visibleRow, activeView.area.height);
		if(autoScrollDirection != SequenceRowDragAutoScrollDirection.none) {
			setSequenceRowDragAutoScrollDirection(autoScrollDirection);
			return false;
		}

		resetSequenceRowDragAutoScroll();

		TrackOverviewLane[] overview;
		int targetGlobalRow;
		bool targetInsideSong;
		if(!resolveVoiceLaneGlobalRow(activeVoiceNum, visibleRow,
				overview, targetGlobalRow, targetInsideSong) ||
				!targetInsideSong)
			return false;

		int currentGlobalRow;
		RowData currentRow;
		if(!overviewGlobalRowFromActiveRow(overview,
				currentGlobalRow, currentRow) ||
				targetGlobalRow == currentGlobalRow)
			return false;

		if(!moveSequenceRowSelectionToOverviewGlobalRow(overview,
				currentGlobalRow, currentRow, targetGlobalRow, visibleRow))
			return false;
		sequenceTable.activateSequenceRowDrag();
		return true;
	}

	override bool mouseMotionAt(int x, int y) {
		return updateSequenceRowDragAt(x, y);
	}

	bool advanceSequenceRowDragAutoScroll() {
		if(activeView != sequenceTable ||
				!sequenceTable.sequenceRowDragInProgress()) {
			resetSequenceRowDragAutoScroll();
			return false;
		}
		if(sequenceRowDragAutoScrollDirection ==
				SequenceRowDragAutoScrollDirection.none)
			return false;
		if(!advanceSequenceRowDragAutoScrollCadence(
				sequenceRowDragAutoScrollTicks))
			return false;

		auto overview = buildTrackOverview(song);
		int currentGlobalRow;
		RowData currentRow;
		if(!overviewGlobalRowFromActiveRow(overview,
				currentGlobalRow, currentRow))
			return false;

		int lastRow = trackOverviewLastGlobalRow(overview);
		if(lastRow < 0)
			return false;

		int rowDelta = sequenceRowDragAutoScrollDirection ==
			SequenceRowDragAutoScrollDirection.up ? -1 : 1;
		int targetGlobalRow = currentGlobalRow + rowDelta;
		if(targetGlobalRow < 0 || targetGlobalRow > lastRow)
			return false;

		int desiredVisibleRow = rowDelta < 0 ?
			sequenceTopAllowedVisibleRow() :
			sequenceBottomAllowedVisibleRow();
		if(!moveSequenceRowSelectionToOverviewGlobalRow(overview,
				currentGlobalRow, currentRow, targetGlobalRow,
				desiredVisibleRow))
			return false;
		sequenceTable.activateSequenceRowDrag();
		return true;
	}

	override bool mouseButtonUp(int button) {
		if(button != 1)
			return false;
		resetSequenceRowDragAutoScroll();
		return sequenceTable.finishSequenceRowDrag();
	}

protected:

	void changeSubtune(int direction) {
		int delta = direction > 0 ? 1 : -1;
		setSubtune(wrappedSubtuneTarget(song.subtune, delta));
	}

	bool setSubtune(int target) {
		auto decision = subtuneSelectionDecision(song.subtune, target);
		if(!decision.valid)
			return false;
		if(!decision.changed)
			return true;

		overviewGlobalRowValid = false;
		postables[song.subtune].copyFrom(activeView.posTable);
		
		refresh();
		mainui.stop();
		activeView.jump(0,false);
		resetMark();

		song.subtunes.activate(decision.target);
		song.subtune = decision.target;
		timelineSeekManager().resetSession("subtune_changed");

		activeView.posTable.copyFrom(postables[song.subtune]);
		activeView.activate();
		refresh();
		activeView.step(0);
		return true;
	}
	
	override void update() {
		activeView.update();
		if(subtuneEditorFocused) {
			subtuneInput.setCoord(area.x + SUBTUNE_SELECTOR_VALUE_X_OFFSET,
				area.y);
			subtuneInput.update();
			input = subtuneInput;
		}
		else
			input = activeView.input;
	}

public:
	bool handleSequenceRowClipboardShortcut(Keyinfo key) {
		if(activeView != sequenceTable)
			return false;
		KeyboardActionId actionId;
		if(!resolveSequenceRowClipboardKeyboardAction(key, actionId))
			return false;
		switch(actionId) {
		case KeyboardActionId.sequenceRowSelectionExtendUp:
		case KeyboardActionId.sequenceRowSelectionExtendDown:
		case KeyboardActionId.sequenceRowSelectionExtendPageUp:
		case KeyboardActionId.sequenceRowSelectionExtendPageDown:
		case KeyboardActionId.sequenceRowSelectionExtendHome:
		case KeyboardActionId.sequenceRowSelectionExtendEnd:
		case KeyboardActionId.sequenceRowSelectPattern:
			return handleSequenceRowSelectionOverviewMove(actionId);
		default:
			return sequenceTable.handleSequenceRowClipboardAction(actionId);
		}
	}

	bool consumeClickedTrackEntry(out int voice, out int trackIndex,
			out ushort trackValue) {
		auto table = cast(BaseTrackTable)activeView;
		if(table is null)
			return false;
		return table.consumeClickedTrackEntry(voice, trackIndex, trackValue);
	}

	void setTrackEntryClipboard(int subtune, int voice,
			int startTrackIndex, int endTrackIndex,
			const(Clip)[] entries) {
		trackEntryClipboard.set(subtune, voice, startTrackIndex,
			endTrackIndex, entries);
	}

	int trackEntryClipboardEntryCount() {
		return trackEntryClipboard.entryCount;
	}

	bool hasTrackEntryClipboard() {
		return trackEntryClipboard.hasEntries;
	}

	void clearDocumentStructuralClipboards() {
		trackEntryClipboard.clear();
		trackTable.clearDocumentClipboard();
		trackmapTable.clearDocumentClipboard();
		sequenceTable.clearDocumentClipboard();
	}

	void clearSongLocalInputMemory() {
		foreach(voice; sequenceTable.voices) {
			auto sequenceVoice = cast(SeqVoice)voice;
			assert(sequenceVoice !is null);
			sequenceVoice.seqinput.clearSongLocalInputMemory();
		}
	}

	private void clearSequenceNavigationEntryProgress() {
		foreach(voice; sequenceTable.voices) {
			auto sequenceVoice = cast(SeqVoice)voice;
			assert(sequenceVoice !is null);
			sequenceVoice.seqinput.clearNavigationEntryProgress();
		}
	}

	bool advanceSequenceRowCopyFeedback(int ticks) {
		return sequenceTable.advanceSequenceRowCopyFeedback(ticks);
	}

protected:
	override void activate() {}

	override void deactivate() {
		cancelSubtuneEditor();
		clearF6OriginMarker();
		clearSequenceNavigationEntryProgress();
		resetSequenceRowDragAutoScroll();
		activeView.deactivate();
	}

	override void refresh() {
	  foreach(b; voiceTables) {
	    b.refresh();
	  }
	}

	override final void undo(UndoValue entry) {
		auto record = cast(SequenceDialogHistoryRecord)entry.ownerPayload;
		if(record is null || record.sequence is null ||
				record.posTable is null || record.subtuneNum != song.subtune ||
				record.sequenceBytes.length != record.sequence.data.raw.length)
			return;

		int oldRows = record.sequence.rows;
		record.sequence.data.raw[] = record.sequenceBytes[];
		record.sequence.refresh();
		bool rowsChanged = record.sequence.rows != oldRows;
		activeView.posTable.copyFrom(record.posTable);
		refresh();
		if(!rowsChanged) {
			// Same-length history keeps the established cursor/end normalisation.
			activeView.step(0);
			return;
		}

		overviewGlobalRowValid = false;
		clearF5PlaybackAnchor();
		enterToggleRestoreValid = false;
		if(!record.cursorIdentity.valid)
			return;

		auto overview = buildTrackOverview(song);
		int globalRow;
		if(!trackOverviewGlobalRowForCursorIdentity(overview,
				record.cursorIdentity, globalRow))
			return;
		if(activeVoiceNum < 0 || activeVoiceNum >= 3 ||
				activeVoiceNum >= cast(int)activeView.voices.length ||
				activeView.voices[activeVoiceNum] is null)
			return;

		int restoredActiveVoiceNum = activeVoiceNum;
		bool moved;
		if(activeView == sequenceTable) {
			moved = moveSequenceTableToOverviewGlobalRow(overview, globalRow,
				record.posTable.normalPointerOffset);
		}
		else {
			auto positions = resolveTrackOverviewPositions(overview, globalRow);
			moved = moveEditorCursorToOverviewPositionsSafeForActiveView(
				positions, activeVoiceNum);
		}
		if(!moved) {
			activeView.posTable.copyFrom(record.posTable);
			activeVoiceNum = restoredActiveVoiceNum;
			activeView.activeVoice =
				activeView.voices[restoredActiveVoiceNum];
			input = activeView.activeVoice.activeInput;
			refresh();
			overviewGlobalRowValid = false;
		}
	}

	override final UndoValue createRedoState(UndoValue value) {
		UndoValue opposite;
		auto selected = cast(SequenceDialogHistoryRecord)value.ownerPayload;
		if(selected is null || selected.sequence is null)
			return opposite;
		opposite.ownerPayload = captureSequenceDialogHistorySide(
			selected.sequence);
		return opposite;
	}

private:
	SequenceDialogHistoryRecord captureSequenceDialogHistorySide(
			Sequence sequence) {
		if(sequence is null || activeView is null ||
				activeView.posTable is null)
			return null;

		TrackOverviewCursorIdentity cursorIdentity;
		auto overview = buildTrackOverview(song);
		int globalRow;
		RowData row;
		if(overviewGlobalRowFromActiveRow(overview, globalRow, row)) {
			cursorIdentity = trackOverviewCursorIdentityAtGlobalRow(overview,
				globalRow, activeVoiceNum, row.trkOffset, row.seqOffset);
		}

		return new SequenceDialogHistoryRecord(sequence,
			sequence.data.raw.dup, activeView.posTable.dup(), song.subtune,
			cursorIdentity);
	}

	void saveState() {
		UndoValue v;
		RowData s = activeView.getRowData();
		v.ownerPayload = captureSequenceDialogHistorySide(s.seq);
		if(v.ownerPayload is null)
			return;
		com.session.insertUndo(this, v);
	}

	void insertCallback(int param) {
		saveState();
		if(param >= MAX_SEQ_NUM) return;
		RowData s = activeView.getRowData();
		Sequence fr = song.seqs[param];
		Sequence to = s.seq;
		int delegate(int) mutation = (int oldRows) {
			to.insertFrom(fr, s.seqOffset);
			activeView.step(0);
			return OK;
		};
		executeSequenceRowCountMutation(to, mutation);
	}

	void copyCallback(int param) {
		saveState();
		if(param >= MAX_SEQ_NUM) return;
		RowData s = activeView.getRowData();
		Sequence fr = song.seqs[param];
		Sequence to = s.seq;
		int oldCursorRow = s.seqOffset;
		auto voice = cast(SeqVoice)activeView.activeVoice;
		int delegate(int) mutation = (int oldRows) {
			to.copyFrom(fr);
			if(to.rows < oldRows)
				voice.clampCursorAfterSequenceShorten(to, oldCursorRow);
			activeView.step(0);
			return OK;
		};
		executeSequenceRowCountMutation(to, mutation);
	}
}
