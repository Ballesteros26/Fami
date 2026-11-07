/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module seq.seqtable;
import main;
import ui.ui;
import com.fb;
import com.util;
import seq.sequencer;
import com.session;
import ct.base;
import ui.input;
import derelict.sdl2.sdl;
import std.string;
import audio.player;
import audio.seekmanager : timelineSeekManager;
import ui.sequencecolors : SequenceColorLookup, buildSequenceColorLookupFromSong,
	sequenceArgbColor, sequenceRowNumberColors, setSequenceBarBackground,
	setSequenceDarkTintBarBackground, SEQUENCE_ROW_NUMBER_CELL_COUNT;

private enum SEQUENCE_ROW_SELECTION_FG = 1;
private enum SEQUENCE_ROW_SELECTION_BG = 6;
private enum SEQUENCE_ROW_COPY_FEEDBACK_TICKS = 4;

private struct SequenceRowSelection {
	bool active;
	int subtuneNum;
	int voice;
	int trackIndex;
	int fixedRow;
	int copyFeedbackTicks;
	Sequence sequence;

	void clear() {
		active = false;
		copyFeedbackTicks = 0;
		sequence = null;
	}
}

package struct SequenceRowSelectionSnapshot {
	bool selectionActive;
	int subtuneNum;
	int voice;
	int trackIndex;
	int fixedRow;
	int activeRow;
	Sequence sequence;
}

private struct SequenceRowClipboard {
	int rowCount;
	ubyte[] rawRows;
	Sequence sourceSequence;
	int sourceSubtuneNum;
	int sourceVoice;
	int sourceTrackIndex;

	@property bool hasRows() const {
		return rowCount > 0 && rawRows.length == rowCount * 4;
	}

	void clear() {
		rowCount = 0;
		rawRows = null;
		sourceSequence = null;
		sourceSubtuneNum = -1;
		sourceVoice = -1;
		sourceTrackIndex = -1;
	}

	void set(Sequence sequence, int subtuneNum, int voice,
			int trackIndex, int startRow, int endRow) {
		rowCount = endRow - startRow + 1;
		sourceSequence = sequence;
		sourceSubtuneNum = subtuneNum;
		sourceVoice = voice;
		sourceTrackIndex = trackIndex;
		rawRows = sequence.data.raw[startRow * 4 .. (endRow + 1) * 4].dup;
	}
}

class SeqVoice : Voice, Undoable {
	InputSeq seqinput;

	private void shiftRowsUp() {
		saveState();
		activeRow.seq.remove(activeRow.seqOffset);
	}

	private void insertBlankSameLength() {
		saveState();
		activeRow.seq.insert(activeRow.seqOffset);
	}

	private void shrinkPattern() {
		Sequence seq = activeRow.seq;
		int oldCursorRow = activeRow.seqOffset;
		saveState();
		seq.shrink(oldCursorRow, 1, true);
		clampCursorAfterSequenceShorten(seq, oldCursorRow);
	}

	private void growPattern() {
		saveState();
		activeRow.seq.expand(activeRow.seqOffset, 1);
	}

	private void expandSequenceAtEnd() {
		Sequence seq = activeRow.seq;
		if(seq is null || seq.rows >= MAX_SEQ_ROWS)
			return;
		saveState();
		seq.expand(0, 1, false);
	}

	private void shrinkSequenceAtEnd() {
		Sequence seq = activeRow.seq;
		int oldCursorRow = activeRow.seqOffset;
		if(seq is null || seq.rows <= 1 || oldCursorRow >= seq.rows - 1)
			return;
		saveState();
		seq.shrink(0, 1, false);
		clampCursorAfterSequenceShorten(seq, oldCursorRow);
	}

	package void clampCursorAfterSequenceShorten(Sequence seq,
			int oldCursorRow) {
		if(seq is null || seq.rows <= 0)
			return;

		int targetRow = oldCursorRow;
		if(targetRow >= seq.rows)
			targetRow = seq.rows - 1;
		if(targetRow < 0)
			targetRow = 0;

		int delta = targetRow - oldCursorRow;
		if(delta != 0) {
			auto table = cast(VoiceTable)parent;
			if(table !is null && table.activeVoice is this)
				table.step(delta);
		}
		refreshPointer(pos.pointerOffset);
	}

	this(VoiceInitParams v) {
		super(v);
		activeRow = getRowData(0, 0);
		seqinput = new InputSeq();
		(cast(InputSeq)seqinput).setElement(activeRow.element);
		seqinput.setCoord(area.x + 4, 0);
		(cast(InputSeq)seqinput).setPointer(area.x + 4, 0);
		activeInput = seqinput;
	}

	override int keyrelease(Keyinfo key) {
		return seqinput.keyrelease(key);
	}

	override int keypress(Keyinfo key) {
		KeyboardActionId actionId;
		if(resolveSequenceEditorCommandKeyboardAction(key, actionId) &&
				actionId == KeyboardActionId.sequenceRowQuickExpand) {
			saveState();
			expandSequenceAtRowToNextHighlightBoundary(activeRow.seq,
				activeRow.seqOffset, song.highlight);
			return OK;
		}

		if(handleSequenceTransposeKey(key))
			return OK;

		if(handleSequenceRowStructureKey(key))
			return OK;

		if(handleSequenceExpandShrinkKey(key))
			return OK;

		version(OSX) {
			if(key.mods & KMOD_SHIFT) {
				return seqinput.keypress(key);
			}
				else if(key.mods & KMOD_CTRL) {
					return seqinput.keypress(key);
			}
			else switch(key.raw)
				 {
					 case SDLK_LEFT:
						 return seqinput.step(-1);
					 case SDLK_RIGHT:
						 return seqinput.step(1);
					 default:
						 return seqinput.keypress(key);
				 }
		}
		else {
				if(key.mods & KMOD_SHIFT) {
					return seqinput.keypress(key);
				}
					else if(key.mods & KMOD_CTRL) {
						return seqinput.keypress(key);
				}
			else switch(key.raw)
				 {
					 case SDLK_LEFT:
						 return seqinput.step(-1);
					 case SDLK_RIGHT:
						 return seqinput.step(1);
					 default:
						 return seqinput.keypress(key);
				 }
		}
		return OK;
	}

	private bool handleSequenceExpandShrinkKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveSequenceExpandShrinkKeyboardAction(key, actionId))
			return false;

		switch(actionId) {
		case KeyboardActionId.sequenceRowExpandSequence:
			expandSequenceAtEnd();
			return true;
		case KeyboardActionId.sequenceRowShrinkSequence:
			shrinkSequenceAtEnd();
			return true;
		default:
			return false;
		}
	}

	private bool handleSequenceRowStructureKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveSequenceRowStructureKeyboardAction(key, actionId))
			return false;

		switch(actionId) {
		case KeyboardActionId.sequenceRowDeleteSameLength:
		case KeyboardActionId.sequenceRowDeleteShrink:
			auto table = cast(SequenceTable)parent;
			if(table !is null && table.clearSelectedSequenceRows())
				return true;
			if(actionId == KeyboardActionId.sequenceRowDeleteSameLength)
				shiftRowsUp();
			else
				shrinkPattern();
			return true;
		case KeyboardActionId.sequenceRowInsertSameLength:
			insertBlankSameLength();
			return true;
		case KeyboardActionId.sequenceRowInsertGrow:
			growPattern();
			return true;
		default:
			return false;
		}
	}

	private bool handleSequenceTransposeKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveSequenceTransposeKeyboardAction(key, actionId))
			return false;

		int delta;
		switch(actionId) {
		case KeyboardActionId.sequenceTransposeSemitoneUp:
			delta = 1;
			break;
		case KeyboardActionId.sequenceTransposeSemitoneDown:
			delta = -1;
			break;
		case KeyboardActionId.sequenceTransposeOctaveUp:
			delta = 12;
			break;
		case KeyboardActionId.sequenceTransposeOctaveDown:
			delta = -12;
			break;
		default:
			return false;
		}

		saveState();
		activeRow.seq.transpose(activeRow.seqOffset, delta);
		return true;
	}

	override void refreshPointer(int y) {
		assert(seqinput !is null);
		assert(pos !is null);
		activeRow = getRowData(pos.trkOffset, pos.seqOffset + y);
		activeInput.setCoord(0, 1 + area.y + y + anchor);
		(cast(InputSeq)seqinput).setElement(activeRow.element);
	}

	override void update() {
		RowData wseq;
		int scry = area.y + area.height;
		int trkofs = pos.trkOffset, seqofs = pos.seqOffset - anchor;
		int lasttrk = tracks.trackLength;
		int hcount = pos.rowCounter - anchor + area.height - 1;
		int row = area.height;
		Sequence seq;
		SequenceColorLookup sequenceColors = buildSequenceColorLookupFromSong(song);

		seqofs += area.height;// - pos.delta;
		wseq = getRowData(trkofs, seqofs);
		trkofs = wseq.trkOffset2;
		seqofs = wseq.seqOffset;
		seq = new Sequence(wseq.seq.data.raw[0 .. $], seqofs);
		void printEmpty() {
			import std.array;

			screen.cprint(area.x - 1, scry, 1, 0,
						  replicate(" ", 16));
		}

		void printTrack() {
			screen.cprint(area.x - 1, scry, 1, 0,
						  " " ~ formatTrackValue(wseq.track.smashedValue));
			if(wseq.track.smashedValue < 0xf000)
				setSequenceBarBackground(screen, area.x, scry, 13,
					sequenceColors, wseq.track.number);
			if(trkofs == pos.mark) {
				for(int i = 0; i < 13; i++) {
					int xpos = area.x + i;
					if(screen.getbg(xpos, scry) == 0)
						setSequenceBarBackground(screen, xpos, scry, 1,
							sequenceColors, wseq.track.number, playbackBarColor);
				}
			}
			if(trkofs == tracks.wrapOffset) {
				for(int i = 0; i < 15; i++) {
					int xpos = area.x + i - 1;
					if(screen.getbg(xpos, scry) == 0)
						setSequenceDarkTintBarBackground(screen, xpos, scry, 1,
							sequenceColors, wseq.track.number, wrapBarColor);
				}
			}
		}

		void highlightSelectedRow(RowData rowData, int seqRow) {
			auto sequenceTable = cast(SequenceTable)parent;
				if(sequenceTable is null ||
						!sequenceTable.isSequenceRowSelected(this, rowData, seqRow))
					return;
				for(int x = area.x - 1; x < area.x + area.width; x++)
					screen.setColor(x, scry,
						sequenceTable.sequenceRowSelectionForeground(),
						sequenceTable.sequenceRowSelectionBackground());
			}

		void colorSequenceRowNumber(bool accentRow) {
			auto colors = sequenceRowNumberColors(
				sequenceArgbColor(sequenceColors, wseq.track.number), accentRow);
			for(int x = area.x;
					x < area.x + SEQUENCE_ROW_NUMBER_CELL_COUNT; x++)
				screen.setColorsRaw(x, scry, colors.foregroundArgb,
					colors.backgroundArgb);
		}

		int rows = seq.rows;
		while(scry >= area.y + 1) {
			if(trkofs < 0) {
				printEmpty();
				scry--; row--;
			}
			else if(trkofs >= lasttrk+1) {
				printEmpty();
				if(trkofs == lasttrk+1) {
					wseq = getRowData(trkofs, 0);
					printTrack();
				}
				hcount--; scry--; trkofs--;
				if(trkofs >= 0) rows = 0;
				continue;
			}
			else {
				for(int i = rows - 1; i >= 0;
					i--, scry--, hcount--, row--) {
					printEmpty();
					if(scry < area.y + 1) break;
					Element d = seq.data[i];
					screen.fprint(area.x + 4, scry, d.toString(wseq.element.transpose));
					if(i == 0) printTrack();
					else {
						if(.seq.sequencer.displaySequenceRowcounter == true) {
							bool accentRow = (hcount - song.highlightOffset) %
								song.highlight == 0;
							int c = accentRow ? 12 : 11;
							screen.cprint(area.x, scry, c, 0, format(" %02X ", i));
							colorSequenceRowNumber(accentRow);
						}
						else screen.cprint(area.x, scry, 0, 0, "    ");
					}
					highlightSelectedRow(wseq, i);
				}
			}
			trkofs--;
			if(trkofs >= 0) {
				wseq = getRowData(trkofs, 0);
				seq = wseq.seq;
				rows = seq.rows;
			}
		}

	}

protected:

	override final void undo(UndoValue entry) {
		auto data = entry.array.target;
		auto target = entry.array.source;
		target[] = data;
		assert(parent !is null);
		entry.seq.refresh();
		parent.step(0);
	}

	void saveState() {
		UndoValue v;
		import std.typecons;
		v.array = UndoValue.Array(activeRow.seq.data.raw.dup,
								  activeRow.seq.data.raw);
		v.seq = activeRow.seq;
		com.session.insertUndo(this, v);
	}

	override final UndoValue createRedoState(UndoValue value) {
		value.array.target = value.array.source.dup;
		return value;
	}
}

class SequenceTable : VoiceTable {
	private enum SequenceRowDragState {
		None,
		Candidate,
		Active
	}

	private SequenceRowSelection rowSelection;
	private SequenceRowClipboard rowClipboard;
	private bool skipNextMouseClickRowPlacement;
	private SequenceRowDragState rowDragState;

	this(Rectangle a, PosDataTable pi) {
		int x = 5 + com.fb.border + a.x;
		for(int v=0;v<3;v++) {
			Rectangle na = Rectangle(x, a.y, a.height, 13 + com.fb.border);
			x += 13 + com.fb.border;
			voices[v] = new SeqVoice(VoiceInitParams(song.tracks[v],
													 na, pi[v], this));
		}
		super(a, pi);
	}

	override void activate() {
		super.activate();
		// works as scroll(1) would but does not store variables
		foreach(Voice v; voices) {
			with(v.pos) {
				if(trkOffset >= v.tracks.trackLength) {
					trkOffset = 0;
					rowCounter = -pointerOffset;
				}
			}

		}

	}

	override void deactivate() {
		cancelSequenceRowDrag();
		clearSequenceRowSelection();
		super.deactivate();
	}

	final void clearDocumentClipboard() {
		rowClipboard.clear();
	}

	package bool clearSequenceRowSelection() {
		bool wasActive = rowSelection.active;
		rowSelection.clear();
		return wasActive;
	}

	package bool beginSequenceRowDragCandidate() {
		cancelSequenceRowDrag();
		RowData row;
		int voiceNum;
		if(rowSelection.active ||
				!currentRowSelectionContext(row, voiceNum))
			return false;
		rowDragState = SequenceRowDragState.Candidate;
		return true;
	}

	package bool sequenceRowDragInProgress() {
		return rowDragState != SequenceRowDragState.None;
	}

	package void activateSequenceRowDrag() {
		if(rowDragState == SequenceRowDragState.Candidate)
			rowDragState = SequenceRowDragState.Active;
	}

	package bool finishSequenceRowDrag() {
		bool wasInProgress = sequenceRowDragInProgress();
		cancelSequenceRowDrag();
		return wasInProgress;
	}

	package void cancelSequenceRowDrag() {
		rowDragState = SequenceRowDragState.None;
	}

	void useCurrentRowForNextMouseClick() {
		skipNextMouseClickRowPlacement = true;
	}

	private void refreshActiveSequenceRow() {
		auto v = cast(SeqVoice)activeVoice;
		if(v !is null)
			v.refreshPointer(posTable.pointerOffset);
	}

	private bool activeSequenceInputIsNoteColumn() {
		auto v = cast(SeqVoice)activeVoice;
		if(v is null || v.seqinput is null)
			return false;
		auto input = cast(InputSeq)v.seqinput;
		return input.activeColumn == 0;
	}

	private void moveActiveSequenceRowBounded(int delta) {
		refreshActiveSequenceRow();
		RowData row = activeVoice.activeRow;
		if(row.seq is null || row.seq.rows <= 0)
			return;

		int targetRow = row.seqOffset + delta;
		if(targetRow < 0)
			targetRow = 0;
		if(targetRow >= row.seq.rows)
			targetRow = row.seq.rows - 1;

		int boundedDelta = targetRow - row.seqOffset;
		if(boundedDelta == 0) {
			refreshActiveSequenceRow();
			return;
		}

		int editLine = posTable.pointerOffset;
		foreach(v; voices)
			v.scroll(boundedDelta, false);
		posTable.pointerOffset = editLine;
		refreshActiveSequenceRow();
	}

	private void advanceAfterNoteInputBounded() {
		moveActiveSequenceRowBounded(stepValue);
	}

	private int sequenceMovementMargin() {
		return area.height > 10 ? 4 : 1;
	}

	private int sequenceTopAllowedVisibleRow() {
		return sequenceMovementMargin();
	}

	private int sequenceBottomAllowedVisibleRow() {
		int bottom = area.height - 1 - sequenceMovementMargin();
		int top = sequenceTopAllowedVisibleRow();
		return bottom < top ? top : bottom;
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

		private bool placeActiveSequenceCursorOnResolvedRow(
				RowData target, int desiredVisibleRow) {
			int originalVoiceNum = activeVoiceNum;
			if(originalVoiceNum < 0 || originalVoiceNum >= voices.length)
				return false;

			auto voice = cast(SeqVoice)activeVoice;
			if(voice is null || target.seq is null ||
					target.track.trans >= 0xf0)
				return false;
			if(target.seqOffset < 0 || target.seqOffset >= target.seq.rows)
				return false;

			desiredVisibleRow =
				clampSequenceVisibleRowToMovementWindow(desiredVisibleRow);
			int desiredPointer = desiredVisibleRow - anchor;
			int targetRowCounter =
				voice.getRowcounter(target.trkOffset) + target.seqOffset;
			int trackIndex = target.trkOffset;
			Sequence sequence = target.seq;
			int targetSeqOffset = target.seqOffset;
			auto originalPos = posTable.dup();

			posTable.pointerOffset = desiredPointer;
			for(int i = 0; i < voices.length; i++) {
				auto sequenceVoice = cast(SeqVoice)voices[i];
				if(sequenceVoice is null) {
					posTable.copyFrom(originalPos);
					refreshActiveSequenceRow();
					return false;
				}
				RowData cursorRow;
				if(!sequenceRowAtAbsoluteCounter(sequenceVoice,
						targetRowCounter, cursorRow)) {
					posTable.copyFrom(originalPos);
					refreshActiveSequenceRow();
					return false;
				}
				auto pos = sequenceVoice.pos;
				pos.trkOffset = cursorRow.trkOffset;
				pos.seqOffset = cursorRow.seqOffset - desiredPointer;
				pos.rowCounter = targetRowCounter - desiredPointer;
			}
			refreshActiveSequenceRow();

			if(activeVoiceNum == originalVoiceNum) {
				voice = cast(SeqVoice)activeVoice;
				if(voice !is null) {
					RowData row = voice.activeRow;
					if(row.trkOffset == trackIndex &&
							row.seq is sequence &&
							row.seqOffset == targetSeqOffset)
						return true;
				}
			}

			posTable.copyFrom(originalPos);
			refreshActiveSequenceRow();
			return false;
		}

		private bool sequenceRowAtAbsoluteCounter(SeqVoice voice,
				int absoluteRow, out RowData row) {
			row = RowData.init;
			if(voice is null || absoluteRow < 0)
				return false;
			for(int trackIndex = 0; trackIndex < voice.tracks.trackLength;
					trackIndex++) {
				Track track = voice.tracks[trackIndex];
				if(track.trans >= 0xf0)
					return false;
				Sequence sequence = song.sequence(track);
				if(sequence is null || sequence.rows <= 0)
					return false;
				if(absoluteRow < sequence.rows) {
					row = voice.getRowData(trackIndex, absoluteRow);
					return row.seq !is null &&
						row.track.trans < 0xf0 &&
						row.trkOffset == trackIndex &&
						row.seqOffset == absoluteRow;
				}
				absoluteRow -= sequence.rows;
			}
			return false;
		}

		private int sequenceTotalRows(SeqVoice voice) {
			if(voice is null)
				return 0;
			int rows;
			for(int trackIndex = 0; trackIndex < voice.tracks.trackLength;
					trackIndex++) {
				Track track = voice.tracks[trackIndex];
				if(track.trans >= 0xf0)
					break;
				Sequence sequence = song.sequence(track);
				if(sequence is null || sequence.rows <= 0)
					break;
				rows += sequence.rows;
			}
			return rows;
		}

		private bool placeActiveSequenceCursorAtAbsoluteRow(
				int absoluteRow, int desiredVisibleRow) {
			auto voice = cast(SeqVoice)activeVoice;
			if(voice is null)
				return false;
			int totalRows = sequenceTotalRows(voice);
			if(totalRows <= 0)
				return false;
			if(absoluteRow < 0)
				absoluteRow = 0;
			if(absoluteRow >= totalRows)
				absoluteRow = totalRows - 1;

			RowData target;
			if(!sequenceRowAtAbsoluteCounter(voice, absoluteRow, target))
				return false;
			return placeActiveSequenceCursorOnResolvedRow(target,
				desiredVisibleRow);
		}

			private int activeSequenceAbsoluteRow() {
				auto voice = cast(SeqVoice)activeVoice;
				if(voice is null)
					return 0;
				refreshActiveSequenceRow();
			RowData row = voice.activeRow;
			if(row.seq is null)
				return 0;
				return voice.getRowcounter(row.trkOffset) + row.seqOffset;
			}

			private int sequenceCursorVisibleRow() {
				return posTable.pointerOffset + anchor;
			}

			private int sequenceViewportStartAbsoluteRow() {
				return activeSequenceAbsoluteRow() - sequenceCursorVisibleRow();
			}

			private bool placeCursorAtAbsoluteSongRow(int absoluteRow,
					int preferredVisibleRow) {
				return placeActiveSequenceCursorAtAbsoluteRow(absoluteRow,
					preferredVisibleRow);
			}

			private bool moveCursorByRows(int delta) {
				if(delta == 0)
					return true;
				int currentRow = activeSequenceAbsoluteRow();
				int viewportStart = sequenceViewportStartAbsoluteRow();
				int targetRow = currentRow + delta;
				int preferredVisibleRow = targetRow - viewportStart;
				return placeCursorAtAbsoluteSongRow(targetRow,
					preferredVisibleRow);
			}

		void placeSongStartAtTopBoundary() {
			int desiredPointer = sequenceTopAllowedVisibleRow() - anchor;
			posTable.pointerOffset = desiredPointer;
			foreach(v; voices)
				v.scroll(-desiredPointer, false);
			refreshActiveSequenceRow();
		}

	private bool placeActiveSequenceCursorAtVisibleRowClamped(
			int clickedVisibleRow) {
		auto voice = cast(SeqVoice)activeVoice;
		if(voice is null)
			return false;

		if(clickedVisibleRow < 0 || clickedVisibleRow >= area.height)
			return false;

		int clickedPointer = clickedVisibleRow - tableTop;
		RowData target = voice.getRowData(voice.pos.trkOffset,
			voice.pos.seqOffset + clickedPointer);
		if(target.seq is null || target.track.trans >= 0xf0)
			return false;
		if(target.seqOffset < 0 || target.seqOffset >= target.seq.rows)
			return false;

		return placeActiveSequenceCursorOnResolvedRow(target,
			clickedVisibleRow);
	}

	private void startSequenceRowCopyFeedback() {
		if(rowSelection.active)
			rowSelection.copyFeedbackTicks =
				SEQUENCE_ROW_COPY_FEEDBACK_TICKS;
	}

	private bool sequenceRowSelectionVisible() {
		if(rowSelection.copyFeedbackTicks <= 0)
			return true;
		return (rowSelection.copyFeedbackTicks % 2) != 0;
	}

	private int sequenceRowSelectionForeground() {
		return SEQUENCE_ROW_SELECTION_FG;
	}

	private int sequenceRowSelectionBackground() {
		return SEQUENCE_ROW_SELECTION_BG;
	}

	private bool currentRowSelectionContext(out RowData row,
			out int voiceNum) {
		voiceNum = activeVoiceNum;
		if(voiceNum < 0 || voiceNum >= voices.length)
			return false;
		auto v = cast(SeqVoice)voices[voiceNum];
		if(v is null)
			return false;
		row = v.activeRow;
		if(row.seq is null)
			return false;
		if(row.track.trans >= 0xf0)
			return false;
		if(row.seqOffset < 0 || row.seqOffset >= row.seq.rows)
			return false;
		return true;
	}

	private bool storeSequenceRowFixedEdge(RowData row, int voiceNum,
			int fixedRow) {
		if(row.seq is null || fixedRow < 0 || fixedRow >= row.seq.rows)
			return false;

		rowSelection.active = true;
		rowSelection.subtuneNum = song.subtune;
		rowSelection.voice = voiceNum;
		rowSelection.trackIndex = row.trkOffset;
		rowSelection.fixedRow = fixedRow;
		rowSelection.sequence = row.seq;
		rowSelection.copyFeedbackTicks = 0;
		return true;
	}

	private bool selectionMatchesCurrentContext(out RowData row,
			out int voiceNum) {
		if(!rowSelection.active)
			return false;
		if(!currentRowSelectionContext(row, voiceNum)) {
			clearSequenceRowSelection();
			return false;
		}
		if(rowSelection.subtuneNum != song.subtune ||
				rowSelection.voice != voiceNum ||
				rowSelection.trackIndex != row.trkOffset ||
				rowSelection.sequence !is row.seq) {
			clearSequenceRowSelection();
			return false;
		}
		if(rowSelection.fixedRow < 0 ||
				rowSelection.fixedRow >= row.seq.rows) {
			clearSequenceRowSelection();
			return false;
		}
		return true;
	}

	package bool captureSequenceRowSelectionSnapshot(
			out SequenceRowSelectionSnapshot snapshot) {
		refreshActiveSequenceRow();
		RowData row;
		int voiceNum;
		if(!currentRowSelectionContext(row, voiceNum))
			return false;

		if(rowSelection.active &&
				!selectionMatchesCurrentContext(row, voiceNum)) {
			if(!currentRowSelectionContext(row, voiceNum))
				return false;
		}

		snapshot.selectionActive = rowSelection.active;
		snapshot.subtuneNum = song.subtune;
		snapshot.voice = voiceNum;
		snapshot.trackIndex = row.trkOffset;
		snapshot.fixedRow = rowSelection.active ?
			rowSelection.fixedRow : row.seqOffset;
		snapshot.activeRow = row.seqOffset;
		snapshot.sequence = row.seq;
		return true;
	}

	private bool snapshotMatchesCurrentContext(
			SequenceRowSelectionSnapshot snapshot, RowData row,
			int voiceNum) {
		return snapshot.subtuneNum == song.subtune &&
			snapshot.voice == voiceNum &&
			snapshot.trackIndex == row.trkOffset &&
			snapshot.sequence !is null &&
			snapshot.sequence is row.seq &&
			snapshot.fixedRow >= 0 &&
			snapshot.fixedRow < row.seq.rows &&
			snapshot.activeRow >= 0 &&
			snapshot.activeRow < row.seq.rows;
	}

	package bool commitSequenceRowSelectionAfterMove(
			SequenceRowSelectionSnapshot snapshot,
			int fixedRowOverride = -1) {
		refreshActiveSequenceRow();
		RowData row;
		int voiceNum;
		if(!currentRowSelectionContext(row, voiceNum) ||
				!snapshotMatchesCurrentContext(snapshot, row, voiceNum)) {
			clearSequenceRowSelection();
			return false;
		}

		int fixedRow = fixedRowOverride >= 0 ? fixedRowOverride :
			(snapshot.selectionActive ? snapshot.fixedRow : snapshot.activeRow);
		return storeSequenceRowFixedEdge(row, voiceNum, fixedRow);
	}

	package bool commitSequenceRowSelectionAfterClick(
			SequenceRowSelectionSnapshot snapshot) {
		refreshActiveSequenceRow();
		RowData row;
		int voiceNum;
		if(!currentRowSelectionContext(row, voiceNum) ||
				!snapshotMatchesCurrentContext(snapshot, row, voiceNum)) {
			clearSequenceRowSelection();
			return false;
		}

		int fixedRow = snapshot.activeRow;
		if(snapshot.selectionActive) {
			int lo = snapshot.fixedRow < snapshot.activeRow ?
				snapshot.fixedRow : snapshot.activeRow;
			int hi = snapshot.fixedRow > snapshot.activeRow ?
				snapshot.fixedRow : snapshot.activeRow;
			int clickedRow = row.seqOffset;

			if(clickedRow < lo)
				fixedRow = hi;
			else if(clickedRow > hi)
				fixedRow = lo;
			else {
				int distanceToLo = clickedRow - lo;
				int distanceToHi = hi - clickedRow;
				if(distanceToLo < distanceToHi)
					fixedRow = hi;
				else if(distanceToHi < distanceToLo)
					fixedRow = lo;
				else
					fixedRow = snapshot.fixedRow;
			}
		}

		return storeSequenceRowFixedEdge(row, voiceNum, fixedRow);
	}

	package bool currentSequenceRowSelectionRange(out RowData row,
			out int voiceNum, out int startRow, out int endRow) {
		if(!selectionMatchesCurrentContext(row, voiceNum))
			return false;

		startRow = rowSelection.fixedRow;
		endRow = row.seqOffset;
		if(startRow > endRow) {
			int tmp = startRow;
			startRow = endRow;
			endRow = tmp;
		}
		if(startRow < 0 || endRow >= row.seq.rows || startRow > endRow)
			return false;
		return true;
	}

	package bool clearSelectedSequenceRows() {
		refreshActiveSequenceRow();
		RowData row;
		int voiceNum, startRow, endRow;
		if(!currentSequenceRowSelectionRange(row, voiceNum,
				startRow, endRow))
			return false;

		auto voice = cast(SeqVoice)activeVoice;
		if(voice is null)
			return false;

		voice.saveState();
		foreach(rowIndex; startRow .. endRow + 1)
			row.seq.data[rowIndex].clear();
		step(0);
		return true;
	}

	private void copySelectedSequenceRows() {
		refreshActiveSequenceRow();
		RowData row;
		int voiceNum, startRow, endRow;
		if(!currentSequenceRowSelectionRange(row, voiceNum,
				startRow, endRow)) {
			if(UI.statusline !is null)
				UI.statusline.displayOperationFeedback(
					"No sequence rows selected.");
			return;
		}

		rowClipboard.set(row.seq, song.subtune, voiceNum,
			row.trkOffset, startRow, endRow);
		startSequenceRowCopyFeedback();
		if(UI.statusline !is null)
			UI.statusline.displayOperationFeedback(format(
				"Sequence selection copied: %d.", rowClipboard.rowCount));
	}

	private void pasteSequenceRows() {
		if(!rowClipboard.hasRows) {
			if(UI.statusline !is null)
				UI.statusline.displayOperationFeedback(
					"No sequence rows copied.");
			return;
		}

		refreshActiveSequenceRow();
		RowData row;
		int voiceNum, pasteStartRow, selectionEndRow;
		if(!currentSequenceRowSelectionRange(row, voiceNum,
				pasteStartRow, selectionEndRow)) {
			if(!currentRowSelectionContext(row, voiceNum))
				return;
			pasteStartRow = row.seqOffset;
		}

		int rowsThatFit = row.seq.rows - pasteStartRow;
		int rowsToPaste = rowClipboard.rowCount < rowsThatFit ?
			rowClipboard.rowCount : rowsThatFit;
		if(rowsToPaste <= 0) {
			if(UI.statusline !is null)
				UI.statusline.displayOperationFeedback(
					"No rows pasted.");
			return;
		}
		int endRow = pasteStartRow + rowsToPaste;

		auto voice = cast(SeqVoice)activeVoice;
		if(voice is null)
			return;

		voice.saveState();
		row.seq.data.raw[pasteStartRow * 4 .. endRow * 4] =
			rowClipboard.rawRows[0 .. rowsToPaste * 4];
		step(0);
		if(UI.statusline !is null)
			UI.statusline.displayOperationFeedback(format(
				"Sequence selection pasted: %d.", rowsToPaste));
	}

	bool handleSequenceRowClipboardAction(KeyboardActionId actionId) {
		switch(actionId) {
		case KeyboardActionId.sequenceRowSelectionClear:
			if(!rowSelection.active)
				return false;
			clearSequenceRowSelection();
			return true;
		case KeyboardActionId.sequenceRowCopy:
			copySelectedSequenceRows();
			return true;
		case KeyboardActionId.sequenceRowPaste:
			pasteSequenceRows();
			return true;
		default:
			return false;
		}
	}

		bool handleSequenceRowClipboardShortcut(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveSequenceRowClipboardKeyboardAction(key, actionId))
				return false;
			return handleSequenceRowClipboardAction(actionId);
		}

		bool handleSequencePlayRowShortcut(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveSequencePlayRowKeyboardAction(key, actionId))
				return false;
			audio.player.playRow(voices);
			step(1);
			return true;
		}

	bool advanceSequenceRowCopyFeedback(int ticks) {
		if(rowSelection.copyFeedbackTicks <= 0)
			return false;
		// UI timer calls continue while stopped even when audio ticks are zero.
		rowSelection.copyFeedbackTicks--;
		return true;
	}

	bool isSequenceRowSelected(SeqVoice voice, RowData row, int rowIndex) {
		if(!rowSelection.active || voice !is activeVoice)
			return false;
		RowData current;
		int voiceNum;
		if(!selectionMatchesCurrentContext(current, voiceNum))
			return false;
		if(!sequenceRowSelectionVisible())
			return false;
		if(row.seq !is rowSelection.sequence ||
				row.trkOffset != rowSelection.trackIndex)
			return false;
		if(rowIndex < 0 || rowIndex >= row.seq.rows)
			return false;

		int lo = rowSelection.fixedRow;
		int hi = current.seqOffset;
		if(lo > hi) {
			int tmp = lo;
			lo = hi;
			hi = tmp;
		}
		return rowIndex >= lo && rowIndex <= hi;
	}

	override void update() {
		super.update();
		if(!audio.player.isPlaying || audio.player.keyjamEnabled) return;
		// trackbar
		for(int i = 0 ; i < 3; i++) {
			PosData fp = fplayPos[i];
			PosData vp = posTable[i];
			int tp = fp.rowCounter - vp.rowCounter + anchor;
			if(tp >= 0 && tp < area.height) {
				for(int x = voices[i].area.x;
					x < voices[i].area.x + voices[i].area.width; x++) {
					screen.setColor(x, 1 + area.y + tp, 1,0);
				}
			}
		}

	}

	override void stepVoice(int i) {
		int n = activeVoiceNum + i;
		n = umod(n, 0, 2);
		if(!voices[n].atEnd())
			super.stepVoice(i);

		SeqVoice v = cast(SeqVoice)voices[n];
		(cast(InputSeq)v.seqinput).columnReset(0);
		RowData row;
		int voiceNum;
		if(rowSelection.active &&
				!selectionMatchesCurrentContext(row, voiceNum))
			clearSequenceRowSelection();
	}

	// Sequencer owns Shift-click selection; this method owns cursor and column.
	override void clickedAt(int x, int y, int button) {
		bool shiftClick = button == 1 &&
			(SDL_GetModState() & KMOD_SHIFT) != 0;
		activateVoiceAtLocalX(x);
		y -= 1;
		if(skipNextMouseClickRowPlacement)
			skipNextMouseClickRowPlacement = false;
		else
			placeActiveSequenceCursorAtVisibleRowClamped(y);
		selectPatternColumnAtLocalX(x);
		if(button == 1 && !shiftClick)
			clearSequenceRowSelection();
		else if(button != 1) {
			RowData row;
			int voiceNum;
			if(rowSelection.active &&
				!selectionMatchesCurrentContext(row, voiceNum))
				clearSequenceRowSelection();
		}
	}

	void selectPatternColumnAtLocalX(int x) {
		auto voice = cast(SeqVoice)activeVoice;
		if(voice !is null && voice.seqinput !is null) {
			voice.refreshPointer(posTable.pointerOffset);
			input = voice.seqinput;
			int patternX = x - (voice.area.x - area.x + 4);
			voice.seqinput.clickAtDisplayOffset(patternX);
		}
	}

	private bool sequenceEditKey(Keyinfo key) {
		if(key.mods & (KMOD_CTRL | KMOD_ALT | KMOD_GUI))
			return false;
		switch(key.raw) {
		case SDLK_BACKSPACE, SDLK_DELETE, SDLK_INSERT:
			return true;
		default:
			return false;
		}
	}

	private bool plainSequenceRowMovementKey(Keyinfo key) {
		return (key.raw == SDLK_UP || key.raw == SDLK_DOWN) &&
			(key.mods & (KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI)) == 0;
	}

		private void homeInPattern() {
			auto voice = cast(SeqVoice)activeVoice;
			if(voice is null)
				return;
			refreshActiveSequenceRow();
			RowData row = voice.activeRow;
			if(row.seq is null)
				return;
			int absoluteRow = voice.getRowcounter(row.trkOffset);
			placeActiveSequenceCursorAtAbsoluteRow(absoluteRow,
				sequenceTopAllowedVisibleRow());
		}

		private void endInPattern() {
			auto voice = cast(SeqVoice)activeVoice;
			if(voice is null)
				return;
			refreshActiveSequenceRow();
			RowData row = voice.activeRow;
			if(row.seq is null || row.seq.rows <= 0)
				return;
			int absoluteRow = voice.getRowcounter(row.trkOffset) +
				row.seq.rows - 1;
			placeActiveSequenceCursorAtAbsoluteRow(absoluteRow,
				sequenceBottomAllowedVisibleRow());
		}

		private bool pageInSong(int direction) {
			if(direction != -1 && direction != 1)
				return false;
			int pageRows = seq.sequencer.PAGESTEP * song.highlight;
			if(pageRows <= 0)
				pageRows = 1;
			int visibleRow = posTable.normalPointerOffset;
			int desiredVisibleRow =
				clampSequenceVisibleRowToMovementWindow(
					visibleRow + direction * pageRows);
			return placeActiveSequenceCursorAtAbsoluteRow(
				activeSequenceAbsoluteRow() + direction * pageRows,
				desiredVisibleRow);
		}

	override int keypress(Keyinfo key) {
		if(handleSequenceRowClipboardShortcut(key))
			return OK;
		if(handleSequencePlayRowShortcut(key))
			return OK;
				if(plainSequenceRowMovementKey(key)) {
						if(rowSelection.active)
							clearSequenceRowSelection();
						moveCursorByRows(key.raw == SDLK_UP ? -1 : 1);
						return OK;
					}
			if(!key.mods &&
					(key.raw == SDLK_PAGEUP || key.raw == SDLK_PAGEDOWN)) {
				if(rowSelection.active)
					clearSequenceRowSelection();
				pageInSong(key.raw == SDLK_PAGEUP ? -1 : 1);
				return OK;
			}

		version(OSX) {
			if(sequenceEditKey(key))
				return activeVoice.keypress(key);

			if(!key.mods) {
				switch(key.raw) {
				case SDLK_HOME:
					homeInPattern();
					return OK;
				case SDLK_END:
					endInPattern();
					return OK;
				default:
					break;
				}
			}
		}

		// globals
		super.keypress(key);
		if(!key.mods) {
			switch(key.raw)
			{
				case SDLK_HOME:
					version(OSX) {
						break;
					}
					else {
					SeqVoice v = cast(SeqVoice)activeVoice;
					InputSeq i = cast(InputSeq)v.seqinput;
					if(i.activeColumn > 0) {
						(cast(InputSeq)v.seqinput).columnReset(0);
						break;
					}
						homeInPattern();
						break;
					}
					break;
				case SDLK_END:
				version(OSX) {
					break;
				}
				else {
					SeqVoice v = cast(SeqVoice)activeVoice;
					InputSeq i = cast(InputSeq)v.seqinput;
					if(i.activeColumn < i.columns) {
						(cast(InputSeq)v.seqinput).columnReset(i.columns,0);
						break;
					}
						endInPattern();
						break;
					}
				break;
			default:
				break;
			}

		}
		else {
			KeyboardActionId splitActionId;
			if(resolveSequenceSplitKeyboardAction(key, splitActionId)) {
				RowData r = activeVoice.activeRow;
				// bad coding because all the rowcountergetters are flawed one way or another
				int rowcount = activeVoice.getRowcounter(r.trkOffset) + r.seqOffset;
				song.splitSequence(r.track.number, r.seqOffset);
				timelineSeekManager().invalidate("split_sequence");
				jump(Jump.toBeginning,false);
				step(rowcount);
				centerTo(0);
			}
		}
		int r;
		bool noteInputWrap = activeSequenceInputIsNoteColumn();
		if((r = activeVoice.keypress(key)) != OK) {
			switch(r) {
			case WRAPL:
				stepVoice(-1);
				break;
			case WRAPR:
				stepVoice(1);
				break;
			case WRAP:
				if(noteInputWrap)
					advanceAfterNoteInputBounded();
				else
					step(stepValue);
				break;
			default:
				step(stepValue);
				break;
			}
		}
		RowData row;
		int voiceNum;
		if(rowSelection.active &&
				!selectionMatchesCurrentContext(row, voiceNum))
			clearSequenceRowSelection();
		return OK;
	}
}
