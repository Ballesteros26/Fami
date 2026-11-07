/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module seq.tracktable;
import seq.sequencer;
import seq.seqtable;
import com.fb;
import com.session;
import com.util;
import ui.ui;
import ui.dialogs;
import ui.input;
import derelict.sdl2.sdl;
import ct.base;
import ui.sequencecolors : SequenceColorLookup, buildSequenceColorLookupFromSong,
	setSequenceBarBackground, setSequenceDarkTintBarBackground;
import seq.trackoverview : TrackOverviewPosition;
import std.string : format;

class TrackVoice : SeqVoice {
	InputTrack trackinput;
	bool displayTracklist = false;
	this(VoiceInitParams v) {		
		super(v);
		activeRow = getRowData(0, 0);
		trackinput = new InputTrack(activeRow, &(cast(BaseTrackTable)v.voiceTable).trackValueChanged);
		trackinput.setCoord(area.x,0);
		activeInput = trackinput;
	}

	override void trackFlush(int y) {
		if(trackinput is null)
			return;
		trackinput.flush();
		refreshPointer(y);
	}

	override int keypress(Keyinfo key) {
		return trackinput.keypress(key);
	}

	override void deactivate() {
		super.deactivate();
		with(pos) {
			if(trkOffset >= tracks.trackLength) {
				trkOffset = 0; rowCounter = seqOffset;
			}
		}
	}

	override void update() {
		super.update();
		RowData wseq, cseq;
		int h = area.y + area.h + 1;
		int y,i;
		int trkofs = pos.trkOffset;
		int rows = 0;
		int lasttrk = tracks.trackLength;
 		int counter;
		int scry = area.y + 1; 
		SequenceColorLookup sequenceColors = buildSequenceColorLookupFromSong(song);

		void printTrack() {
			if(!displayTracklist) return;
			if(wseq.seq is null) return;

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

		trkofs -= pos.pointerOffset + seq.sequencer.anchor;
		counter = getRowcounter(trkofs);

		if(trkofs >= 0)
			wseq = getRowData(trkofs);
		y = area.y + 1;

		while(scry <= area.y + area.height) {
			if(trkofs < 0) {
				scry++;
			}
			else if(trkofs >= lasttrk+1) {
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

	protected:

				void refreshTrack(int po) {
					refreshPointer(po);
					trackinput.refresh(activeRow);
				refreshPointer(po);
			}

	void trackInsert(bool doInsert) {
		Track trk = activeRow.track; 
		trackinput.flush();
		{
			if(!doInsert) {
				tracks.expand();
			}
				else {
					tracks.insertAt(activeRow.trkOffset);
					if(pos.trkOffset <= pos.mark)
						pos.mark++;
					}
				}
				trackinput.init(activeRow);
			}

				void trackInsertCopy() {
					trackinput.flush();
				{
					tracks.insertCopyAt(activeRow.trkOffset);
						if(pos.trkOffset <= pos.mark)
							pos.mark++;
					}
					trackinput.init(activeRow);
				}
	
	void trackDelete(bool doDelete) {
		trackinput.flush();
		int trackLength = tracks.trackLength;
		int deletedTrackIndex = doDelete ?
			activeRow.trkOffset : trackLength - 1;
		{
			if(!doDelete) {
				
				if(trackLength == 1) {
					tracks[0].setValue(0xa0, 0);
				}
				tracks.shrink();
			}
			else {
				if(trackLength == 1) {
					tracks[0].setValue(0xa0, 00);
				}
				else {
					tracks.deleteAt(deletedTrackIndex);
				}
			}
		}

		if(trackLength > 1 && pos.mark > deletedTrackIndex)
			pos.mark--;
		else if(trackLength > 1 && pos.mark >= deletedTrackIndex)
			pos.mark = deletedTrackIndex;
		if(pos.mark < 0) pos.mark = 0;
		if(pos.mark >= tracks.trackLength) {
			pos.mark = tracks.trackLength - 1;
		}

		// A deleted last entry moves this index onto the new LOOP slot.
		pos.trkOffset = deletedTrackIndex;
		if(pos.trkOffset >= tracks.trackLength)
			pos.trkOffset = tracks.trackLength - 1;
		if(pos.trkOffset < 0)
			pos.trkOffset = 0;
		pos.seqOffset = 0;
		pos.rowCounter = getRowcounter(pos.trkOffset);
		trackinput.init(activeRow);
		refreshTrack(0);
	}

	bool trackMoveWithin(int sourceTrackIndex, int insertionTrackIndex,
			out int movedTrackIndex) {
		movedTrackIndex = -1;
		trackinput.flush();
		int movedMark = movedTrackEntryIndex(pos.mark, sourceTrackIndex,
			insertionTrackIndex);
		if(!tracks.moveEntryWithin(sourceTrackIndex, insertionTrackIndex))
			return false;

		movedTrackIndex = sourceTrackIndex < insertionTrackIndex ?
			insertionTrackIndex - 1 : insertionTrackIndex;
		pos.mark = movedMark;
		if(pos.mark < 0) pos.mark = 0;
		if(pos.mark >= tracks.trackLength) {
			pos.mark = tracks.trackLength - 1;
		}
		pos.trkOffset = movedTrackIndex;
		pos.seqOffset = 0;
		pos.rowCounter = getRowcounter(movedTrackIndex);
		refreshTrack(0);
		return true;
	}

	bool trackMoveRangeWithin(int sourceStartTrackIndex,
			int sourceEndTrackIndex, int insertionTrackIndex,
			out int movedStartTrackIndex, out int movedEndTrackIndex) {
		movedStartTrackIndex = -1;
		movedEndTrackIndex = -1;
		trackinput.flush();

		int count = sourceEndTrackIndex - sourceStartTrackIndex + 1;
		int movedMark = movedTrackEntryRangeIndex(pos.mark,
			sourceStartTrackIndex, count, insertionTrackIndex);
		if(!tracks.moveEntriesWithin(sourceStartTrackIndex,
				sourceEndTrackIndex, insertionTrackIndex))
			return false;

		movedStartTrackIndex = sourceStartTrackIndex < insertionTrackIndex ?
			insertionTrackIndex - count : insertionTrackIndex;
		movedEndTrackIndex = movedStartTrackIndex + count - 1;
		pos.mark = movedMark;
		if(pos.mark < 0) pos.mark = 0;
		if(pos.mark >= tracks.trackLength) {
			pos.mark = tracks.trackLength - 1;
		}
		pos.trkOffset = movedStartTrackIndex;
		pos.seqOffset = 0;
		pos.rowCounter = getRowcounter(movedStartTrackIndex);
		refreshTrack(0);
		return true;
	}

	bool trackDeleteEntriesAt(int sourceStartTrackIndex,
			int sourceEndTrackIndex) {
		if(sourceEndTrackIndex < sourceStartTrackIndex)
			return false;

		trackinput.flush();
		int trackLength = tracks.trackLength;
		if(sourceStartTrackIndex < 0 ||
				sourceEndTrackIndex >= trackLength)
			return false;

		int count = sourceEndTrackIndex - sourceStartTrackIndex + 1;
		if(count <= 0 || count >= trackLength)
			return false;

		foreach(_; 0 .. count) {
			tracks.deleteAt(sourceStartTrackIndex);
		}
		if(tracks.trackLength != trackLength - count)
			return false;

		if(pos.mark > sourceEndTrackIndex)
			pos.mark -= count;
		else if(pos.mark >= sourceStartTrackIndex)
			pos.mark = sourceStartTrackIndex;
		if(pos.mark < 0) pos.mark = 0;
		if(pos.mark >= tracks.trackLength) {
			pos.mark = tracks.trackLength - 1;
		}

		pos.trkOffset = sourceStartTrackIndex;
		if(pos.trkOffset >= tracks.trackLength)
			pos.trkOffset = tracks.trackLength - 1;
		pos.seqOffset = 0;
		pos.rowCounter = getRowcounter(pos.trkOffset);
		trackinput.init(activeRow);
		refreshTrack(0);
		return true;
	}

	bool trackInsertEntriesAt(int insertionTrackIndex,
			const(Clip)[] entries) {
		if(entries.length == 0)
			return false;

		trackinput.flush();
		int trackLength = tracks.trackLength;
		if(insertionTrackIndex < 0 || insertionTrackIndex > trackLength)
			return false;
		if(cast(long)trackLength + entries.length > tracks.length - 1)
			return false;

		foreach(idx, entry; entries) {
			int targetIndex = insertionTrackIndex + cast(int)idx;
			tracks.insertAt(targetIndex);
			tracks[targetIndex].setValue(entry.trans, entry.no);
		}

		if(insertionTrackIndex <= pos.mark)
			pos.mark += cast(int)entries.length;
		if(pos.mark < 0) pos.mark = 0;
		if(pos.mark >= tracks.trackLength) {
			pos.mark = tracks.trackLength - 1;
		}

		pos.trkOffset = insertionTrackIndex + cast(int)entries.length - 1;
		pos.seqOffset = 0;
		pos.rowCounter = getRowcounter(pos.trkOffset);
		refreshTrack(0);
		return true;
	}

	void trackTrans(int d) {
		trackinput.flush();
		{
			tracks.transposeAt(activeRow.trkOffset, tracks.length, d);
		}
		trackinput.init(activeRow);
	}
}

abstract class BaseTrackTable : VoiceTable, Undoable {
	QueryDialog queryClip;

	protected Clip[] clip;
	private struct ClickedTrackEntry {
		bool valid;
		int voice;
		int trackIndex;
		ushort trackValue;
	}
	private ClickedTrackEntry clickedTrackEntry;
    
	this(Rectangle a, PosDataTable pi) {
		super(a, pi);
		queryClip = new QueryDialog("Copy number of tracks to clipboard: $",
									&clipCallback, 0x80);
		
	}

	final void clearDocumentClipboard() {
		clip = null;
	}

	void trackValueChanged() {
		saveState(false);
	}

	private InputTrack currentTrackInput() {
		auto trackInput = cast(InputTrack)input;
		if(trackInput !is null)
			return trackInput;

		auto v = cast(TrackVoice)activeVoice;
		if(v is null || v.trackinput is null)
			return null;

		input = v.trackinput;
		return v.trackinput;
	}

	private TrackVoice prepareCurrentTrackEdit() {
		auto v = cast(TrackVoice)activeVoice;
		if(v is null || v.trackinput is null)
			return null;

		input = v.trackinput;
		v.trackFlush(posTable.pointerOffset);
		v.trackinput.refresh(v.activeRow);
		input = v.trackinput;
		return v;
	}

	package void clearClickedTrackEntry() {
		clickedTrackEntry = ClickedTrackEntry();
	}

	private int trackMovementMargin() {
		return area.height > 10 ? 4 : 1;
	}

	private int trackTopAllowedVisibleRow() {
		return trackMovementMargin();
	}

	private int trackBottomAllowedVisibleRow() {
		int bottom = area.height - 1 - trackMovementMargin();
		int top = trackTopAllowedVisibleRow();
		return bottom < top ? top : bottom;
	}

	private int clampTrackVisibleRowToMovementWindow(int visibleRow) {
		int top = trackTopAllowedVisibleRow();
		int bottom = trackBottomAllowedVisibleRow();
		if(visibleRow < top)
			return top;
		if(visibleRow > bottom)
			return bottom;
		return visibleRow;
	}

	int defaultActivationVisibleRow() {
		return clampTrackVisibleRowToMovementWindow(anchor);
	}

	private bool currentTrackCursorRow(out RowData row) {
		row = RowData.init;
		auto v = cast(TrackVoice)activeVoice;
		if(v is null || v.trackinput is null)
			return false;
		v.refreshTrack(posTable.pointerOffset);
		input = v.trackinput;
		row = v.activeRow;
		if(row.seq is null || row.track.trans >= 0xf0)
			return false;
		if(row.seqOffset < 0 || row.seqOffset >= row.seq.rows)
			return false;
		return true;
	}

	protected bool placeTrackCursorOnResolvedRowClamped(RowData target,
			int desiredVisibleRow) {
		int originalVoiceNum = activeVoiceNum;
		if(originalVoiceNum < 0 || originalVoiceNum >= voices.length)
			return false;

		auto v = cast(TrackVoice)activeVoice;
		if(v is null || v.trackinput is null)
			return false;
		if(target.seq is null || target.track.trans >= 0xf0)
			return false;
		if(target.seqOffset < 0 || target.seqOffset >= target.seq.rows)
			return false;

		desiredVisibleRow =
			clampTrackVisibleRowToMovementWindow(desiredVisibleRow);
		int desiredPointer = desiredVisibleRow - anchor;
		int targetRowCounter =
			v.getRowcounter(target.trkOffset) + target.seqOffset;
		int delta = targetRowCounter - desiredPointer - v.pos.rowCounter;
		int trackIndex = target.trkOffset;
		Sequence sequence = target.seq;
		int targetSeqOffset = target.seqOffset;
		auto originalPos = posTable.dup();

		posTable.pointerOffset = desiredPointer;
		if(delta != 0) {
			foreach(voice; voices)
				voice.scroll(delta, false);
		}
		refresh();

		if(activeVoiceNum == originalVoiceNum) {
			v = cast(TrackVoice)activeVoice;
			if(v !is null && v.trackinput !is null) {
				RowData row = v.activeRow;
				if(row.trkOffset == trackIndex &&
						row.seq is sequence &&
						row.seqOffset == targetSeqOffset) {
					input = v.trackinput;
					return true;
				}
			}
		}

		posTable.copyFrom(originalPos);
		refresh();
		return false;
	}

	void normalizeTrackCursorIntoMovementWindow() {
		RowData row;
		if(!currentTrackCursorRow(row))
			return;
		placeTrackCursorOnResolvedRowClamped(row,
			posTable.normalPointerOffset);
	}

	bool activateAtTrackEntryClamped(int voice, int trackIndex,
			ushort expectedTrackValue, int desiredVisibleRow) {
		if(voice < 0 || voice >= voices.length)
			return false;
		auto v = cast(TrackVoice)voices[voice];
		if(v is null || v.trackinput is null)
			return false;
		if(trackIndex < 0 || trackIndex >= v.tracks.trackLength)
			return false;

		RowData target = v.getRowData(trackIndex, 0);
		if(target.seq is null || target.track.trans >= 0xf0)
			return false;
		if(target.track.smashedValue != expectedTrackValue)
			return false;

		auto originalPos = posTable.dup();
		int originalVoiceNum = activeVoiceNum;
		auto originalVoice = activeVoice;

		desiredVisibleRow =
			clampTrackVisibleRowToMovementWindow(desiredVisibleRow);
		int desiredPointer = desiredVisibleRow - anchor;

		if(activeVoice !is null)
			activeVoice.trackFlush(posTable.pointerOffset);
		activeVoiceNum = voice;
		activeVoice = v;
		input = v.trackinput;
		posTable.pointerOffset = desiredPointer;
		v.pos.trkOffset = trackIndex;
		v.pos.seqOffset = -desiredPointer;
		v.pos.rowCounter = v.getRowcounter(trackIndex) - desiredPointer;
		v.refreshTrack(posTable.pointerOffset);
		input = v.trackinput;
		refresh();
		v.refreshTrack(posTable.pointerOffset);
		input = v.trackinput;

		RowData row = v.activeRow;
		bool voiceOk = activeVoiceNum == voice;
		bool trackOk = row.trkOffset == trackIndex;
		bool valueOk = row.track.smashedValue == expectedTrackValue;
		bool visibleOk = posTable.pointerOffset + anchor == desiredVisibleRow;
		if(voiceOk && trackOk && valueOk && visibleOk) {
			return true;
		}

		posTable.copyFrom(originalPos);
		activeVoiceNum = originalVoiceNum;
		activeVoice = originalVoice;
		if(activeVoice !is null)
			input = activeVoice.activeInput;
		refresh();
		return false;
	}

	bool activateAtOverviewPositionsClamped(
			const TrackOverviewPosition[] positions, int voice,
			int desiredVisibleRow) {
		if(voice < 0 || voice >= voices.length ||
				positions.length < voices.length)
			return false;
		foreach(i; 0 .. voices.length) {
			auto v = cast(TrackVoice)voices[i];
			if(v is null || v.trackinput is null)
				return false;
			if(!positions[i].valid ||
					positions[i].trackIndex < 0 ||
					positions[i].sequenceRowOffset < 0 ||
					positions[i].trackIndex >= v.tracks.trackLength)
				return false;
			Track targetTrack = v.tracks[positions[i].trackIndex];
			if(targetTrack.trans >= 0xf0 ||
					targetTrack.smashedValue != positions[i].trackValue)
				return false;
		}

		auto originalPos = posTable.dup();
		int originalVoiceNum = activeVoiceNum;
		auto originalVoice = activeVoice;

		desiredVisibleRow =
			clampTrackVisibleRowToMovementWindow(desiredVisibleRow);
		int desiredPointer = desiredVisibleRow - anchor;

		if(activeVoice !is null)
			activeVoice.trackFlush(posTable.pointerOffset);
		posTable.pointerOffset = desiredPointer;
		foreach(i; 0 .. voices.length) {
			auto v = cast(TrackVoice)voices[i];
			PosData pos = posTable.pos[i];
			pos.trkOffset = positions[i].trackIndex;
			pos.seqOffset = -desiredPointer;
			pos.rowCounter =
				v.getRowcounter(positions[i].trackIndex) - desiredPointer;
			v.refreshTrack(posTable.pointerOffset);
		}

		activeVoiceNum = voice;
		activeVoice = voices[voice];
		input = activeVoice.activeInput;
		refresh();
		input = activeVoice.activeInput;

		bool ok = activeVoiceNum == voice &&
			posTable.pointerOffset + anchor == desiredVisibleRow;
		foreach(i; 0 .. voices.length) {
			auto v = cast(TrackVoice)voices[i];
			RowData row = v.activeRow;
			ok = ok &&
				row.trkOffset == positions[i].trackIndex &&
				row.seqOffset == 0 &&
				row.track.smashedValue == positions[i].trackValue;
		}
		if(ok)
			return true;

		posTable.copyFrom(originalPos);
		activeVoiceNum = originalVoiceNum;
		activeVoice = originalVoice;
		if(activeVoice !is null)
			input = activeVoice.activeInput;
		refresh();
		return false;
	}

	private void setClickedTrackEntry(int voice, int trackIndex,
			ushort trackValue) {
		clickedTrackEntry.valid = true;
		clickedTrackEntry.voice = voice;
		clickedTrackEntry.trackIndex = trackIndex;
		clickedTrackEntry.trackValue = trackValue;
	}

	bool consumeClickedTrackEntry(out int voice, out int trackIndex,
			out ushort trackValue) {
		if(!clickedTrackEntry.valid)
			return false;
		voice = clickedTrackEntry.voice;
		trackIndex = clickedTrackEntry.trackIndex;
		trackValue = clickedTrackEntry.trackValue;
		clearClickedTrackEntry();
		return true;
	}

	bool rememberCurrentTrackEntryClick() {
		return rememberClickedActiveTrackEntry();
	}

	bool rememberTrackEntryClickAt(int voice, int trackIndex) {
		clearClickedTrackEntry();
		if(voice < 0 || voice >= cast(int)voices.length || trackIndex < 0)
			return false;

		auto v = cast(TrackVoice)voices[voice];
		if(v is null || v.trackinput is null)
			return false;

		Tracklist tracks = v.tracks;
		if(trackIndex >= tracks.trackLength)
			return false;

		Track track = tracks[trackIndex];
		if(track.trans >= 0xf0)
			return false;

		setClickedTrackEntry(voice, trackIndex, track.smashedValue);
		return true;
	}

	protected bool selectTrackEntryAt(int voice, int trackIndex) {
		clearClickedTrackEntry();
		if(voice < 0 || voice >= cast(int)voices.length)
			return false;

		auto v = cast(TrackVoice)voices[voice];
		if(v is null || v.trackinput is null || trackIndex < 0)
			return false;

		Tracklist tracks = v.tracks;
		if(trackIndex >= tracks.trackLength)
			return false;

		Track track = tracks[trackIndex];
		if(track.trans >= 0xf0)
			return false;

		activeVoice.trackFlush(posTable.pointerOffset);
		activeVoiceNum = voice;
		activeVoice = v;
		input = v.trackinput;
		v.pos.trkOffset = trackIndex;
		v.pos.seqOffset = 0;
		v.pos.rowCounter = v.getRowcounter(trackIndex);
		v.refreshTrack(0);
		input = v.trackinput;
		refresh();

		setClickedTrackEntry(voice, trackIndex, track.smashedValue);
		return true;
	}

	protected bool rememberClickedActiveTrackEntry() {
		clearClickedTrackEntry();
		auto v = cast(TrackVoice)activeVoice;
		if(v is null || v.trackinput is null)
			return false;
		v.refreshTrack(posTable.pointerOffset);
		input = v.trackinput;

		RowData row = v.activeRow;
		if(row.trkOffset < 0 || row.track.trans >= 0xf0)
			return false;

		setClickedTrackEntry(activeVoiceNum, row.trkOffset,
			row.track.smashedValue);
		return true;
	}

			void insertCopyOfCurrentTrackEntry() {
				auto v = prepareCurrentTrackEdit();
				if(v is null)
					return;
				RowData row = v.activeRow;
				if(row.trkOffset < 0 || row.trkOffset >= v.tracks.trackLength ||
						row.track.trans >= 0xf0)
					return;
				if(currentTrackInput() is null)
					return;
				auto undoState = createState(false);
				com.session.insertUndo(this, undoState);
				v.trackInsertCopy();
				refresh();
			}

		void insertCurrentTrackEntry() {
			auto v = prepareCurrentTrackEdit();
			if(v is null)
				return;
			RowData row = v.activeRow;
			if(row.trkOffset < 0 || row.trkOffset >= v.tracks.trackLength)
				return;
			if(!saveState(false))
				return;
			v.trackInsert(true);
			refresh();
	}

	private TrackVoice prepareTrackEntryEditAt(int voice, int trackIndex,
			ushort expectedTrackValue) {
		if(voice < 0 || voice >= cast(int)voices.length)
			return null;

		auto v = cast(TrackVoice)voices[voice];
		if(v is null || trackIndex < 0)
			return null;

		Tracklist tracks = v.tracks;
		int trackLength = tracks.trackLength;
		if(trackIndex >= trackLength)
			return null;

		Track original = tracks[trackIndex];
		if(original.trans >= 0xf0 ||
				original.smashedValue != expectedTrackValue)
			return null;

		activeVoice = v;
		input = v.trackinput;
		v.pos.trkOffset = trackIndex;
		v.pos.seqOffset = 0;
		v.pos.rowCounter = v.getRowcounter(trackIndex);
		v.refreshTrack(0);
		input = v.trackinput;
		return v;
	}

	private TrackVoice trackEntryAt(int voice, int trackIndex,
			ushort expectedTrackValue) {
		if(voice < 0 || voice >= cast(int)voices.length)
			return null;

		auto v = cast(TrackVoice)voices[voice];
		if(v is null || trackIndex < 0)
			return null;

		Tracklist tracks = v.tracks;
		int trackLength = tracks.trackLength;
		if(trackIndex >= trackLength)
			return null;

		Track original = tracks[trackIndex];
		if(original.trans >= 0xf0 ||
				original.smashedValue != expectedTrackValue)
			return null;

		return v;
	}

	bool insertTrackEntryAt(int voice, int trackIndex,
			ushort expectedTrackValue, out ushort insertedTrackValue) {
		auto v = prepareTrackEntryEditAt(voice, trackIndex,
			expectedTrackValue);
		if(v is null || !saveState(false))
			return false;

		v.trackInsert(true);
		insertedTrackValue = v.tracks[trackIndex].smashedValue;
		refresh();
		return true;
	}

	bool insertNextUnusedExpandedSequenceTrackEntryAfter(int voice,
			int anchorTrackIndex, ushort expectedTrackValue,
			out int insertedTrackIndex, out ushort insertedTrackValue,
			out int insertedSequenceNumber) {
		insertedTrackIndex = -1;
		insertedTrackValue = 0;
		insertedSequenceNumber = -1;

		auto v = prepareTrackEntryEditAt(voice, anchorTrackIndex,
			expectedTrackValue);
		if(v is null)
			return false;

		Tracklist tracks = v.tracks;
		Track anchor = tracks[anchorTrackIndex];
		int insertIndex = anchorTrackIndex + 1;
		if(insertIndex > tracks.length - 2)
			return false;

		int freeSequence = song.getFreeSequence(cast(int)anchor.number + 1);
		if(freeSequence <= 0)
			return false;
		if(freeSequence >= cast(int)song.seqs.length)
			return false;

		Sequence sequence = song.seqs[freeSequence];
		if(sequence is null)
			return false;

		UndoValue undoState = createState(false, sequence);

		v.pos.trkOffset = insertIndex;
		v.pos.seqOffset = 0;
		v.pos.rowCounter = v.getRowcounter(insertIndex);
		v.refreshTrack(0);
		input = v.trackinput;

		sequence.clear();
		if(!expandSequenceAtRowToNextHighlightBoundary(sequence, 0,
				song.highlight)) {
			restoreState(undoState);
			return false;
		}

		int previousTrackLength = tracks.trackLength;
		v.trackInsert(true);
		if(tracks.trackLength <= previousTrackLength ||
				insertIndex >= tracks.trackLength) {
			restoreState(undoState);
			return false;
		}

		v.tracks[insertIndex].number = cast(ubyte)freeSequence;
		v.refreshTrack(0);

		com.session.insertUndo(this, undoState);

		insertedTrackIndex = insertIndex;
		insertedSequenceNumber = freeSequence;
		insertedTrackValue = v.tracks[insertIndex].smashedValue;
		refresh();
		return true;
	}

	bool setTrackEntryToNextUnusedSequenceAt(int voice, int trackIndex,
			ushort expectedTrackValue, out ushort updatedTrackValue,
			out int updatedSequenceNumber) {
		updatedTrackValue = 0;
		updatedSequenceNumber = -1;

		auto v = prepareTrackEntryEditAt(voice, trackIndex,
			expectedTrackValue);
		if(v is null)
			return false;

		Tracklist tracks = v.tracks;
		Track track = tracks[trackIndex];
		int freeSequence = song.getFreeSequence(cast(int)track.number + 1);
		if(freeSequence <= 0 ||
				freeSequence >= cast(int)song.seqs.length)
			return false;
		if(!saveState(false))
			return false;

		tracks[trackIndex].setValue(track.trans, freeSequence);
		updatedTrackValue = tracks[trackIndex].smashedValue;
		updatedSequenceNumber = freeSequence;
		v.refreshTrack(0);
		refresh();
		return true;
	}

	bool insertCopyOfTrackEntryAt(int voice, int trackIndex,
			ushort expectedTrackValue, out ushort copiedTrackValue) {
		auto v = prepareTrackEntryEditAt(voice, trackIndex,
			expectedTrackValue);
		if(v is null || !saveState(false))
			return false;

		v.trackInsertCopy();
		copiedTrackValue = v.tracks[trackIndex].smashedValue;
		refresh();
		return true;
	}

	bool deleteTrackEntryAt(int voice, int trackIndex,
			ushort expectedTrackValue) {
		auto v = prepareTrackEntryEditAt(voice, trackIndex,
			expectedTrackValue);
		if(v is null || !saveState(false))
			return false;

		v.trackDelete(true);
		refresh();
		return true;
	}

	bool deleteTrackEntryRangeAt(int voice, int startTrackIndex,
			int endTrackIndex, const(ushort)[] expectedTrackValues) {
		if(endTrackIndex < startTrackIndex)
			return false;

		int count = endTrackIndex - startTrackIndex + 1;
		if(count <= 0 || expectedTrackValues.length != cast(size_t)count)
			return false;
		if(count == 1) {
			return deleteTrackEntryAt(voice, startTrackIndex,
				expectedTrackValues[0]);
		}

		auto v = prepareTrackEntryEditAt(voice, startTrackIndex,
			expectedTrackValues[0]);
		if(v is null)
			return false;

		Tracklist tracks = v.tracks;
		int trackLength = tracks.trackLength;
		if(endTrackIndex >= trackLength || count >= trackLength)
			return false;

		foreach(idx, expectedTrackValue; expectedTrackValues) {
			int trackIndex = startTrackIndex + cast(int)idx;
			Track track = tracks[trackIndex];
			if(track.trans >= 0xf0 ||
					track.smashedValue != expectedTrackValue)
				return false;
		}

		if(!saveState(false))
			return false;
		if(!v.trackDeleteEntriesAt(startTrackIndex, endTrackIndex))
			return false;

		refresh();
		return true;
	}

	bool moveTrackEntryWithinVoice(int voice, int sourceTrackIndex,
			int insertionTrackIndex, ushort expectedTrackValue,
			out int movedTrackIndex, out ushort movedTrackValue) {
		movedTrackIndex = -1;
		movedTrackValue = 0;

		auto v = prepareTrackEntryEditAt(voice, sourceTrackIndex,
			expectedTrackValue);
		if(v is null)
			return false;

		Tracklist tracks = v.tracks;
		int trackLength = tracks.trackLength;
		if(insertionTrackIndex < 0 || insertionTrackIndex > trackLength)
			return false;
		if(insertionTrackIndex == sourceTrackIndex ||
				insertionTrackIndex == sourceTrackIndex + 1)
			return false;

		ushort sourceTrackValue = tracks[sourceTrackIndex].smashedValue;
		if(!saveState(false))
			return false;
		if(!v.trackMoveWithin(sourceTrackIndex, insertionTrackIndex,
				movedTrackIndex))
			return false;

		movedTrackValue = sourceTrackValue;
		refresh();
		return true;
	}

	bool moveTrackEntryRangeWithinVoice(int voice, int sourceStartTrackIndex,
			int sourceEndTrackIndex, int insertionTrackIndex,
			const(ushort)[] expectedTrackValues,
			out int movedStartTrackIndex, out int movedEndTrackIndex) {
		movedStartTrackIndex = -1;
		movedEndTrackIndex = -1;

		if(sourceEndTrackIndex < sourceStartTrackIndex)
			return false;

		int count = sourceEndTrackIndex - sourceStartTrackIndex + 1;
		if(count <= 1 || expectedTrackValues.length != cast(size_t)count)
			return false;

		auto v = prepareTrackEntryEditAt(voice, sourceStartTrackIndex,
			expectedTrackValues[0]);
		if(v is null)
			return false;

		Tracklist tracks = v.tracks;
		int trackLength = tracks.trackLength;
		if(sourceEndTrackIndex >= trackLength)
			return false;
		if(insertionTrackIndex < 0 || insertionTrackIndex > trackLength)
			return false;
		if(insertionTrackIndex >= sourceStartTrackIndex &&
				insertionTrackIndex <= sourceEndTrackIndex + 1)
			return false;

		foreach(idx, expectedTrackValue; expectedTrackValues) {
			int trackIndex = sourceStartTrackIndex + cast(int)idx;
			Track track = tracks[trackIndex];
			if(track.trans >= 0xf0 ||
					track.smashedValue != expectedTrackValue)
				return false;
		}

		if(!saveState(false))
			return false;
		if(!v.trackMoveRangeWithin(sourceStartTrackIndex,
				sourceEndTrackIndex, insertionTrackIndex,
				movedStartTrackIndex, movedEndTrackIndex))
			return false;

		refresh();
		return true;
	}

	bool moveTrackEntryToVoice(int sourceVoice, int sourceTrackIndex,
			int targetVoice, int insertionTrackIndex,
			ushort expectedTrackValue, out int movedTrackIndex,
			out ushort movedTrackValue) {
		movedTrackIndex = -1;
		movedTrackValue = 0;

		if(sourceVoice == targetVoice) {
			return moveTrackEntryWithinVoice(sourceVoice, sourceTrackIndex,
				insertionTrackIndex, expectedTrackValue, movedTrackIndex,
				movedTrackValue);
		}

		auto source = prepareTrackEntryEditAt(sourceVoice, sourceTrackIndex,
			expectedTrackValue);
		if(source is null)
			return false;
		if(targetVoice < 0 || targetVoice >= cast(int)voices.length)
			return false;

		auto target = cast(TrackVoice)voices[targetVoice];
		if(target is null)
			return false;

		Tracklist sourceTracks = source.tracks;
		Tracklist targetTracks = target.tracks;
		int sourceLength = sourceTracks.trackLength;
		int targetLength = targetTracks.trackLength;
		if(sourceLength <= 1)
			return false;
		if(insertionTrackIndex < 0 || insertionTrackIndex > targetLength)
			return false;
		if(cast(long)targetLength + 1 > targetTracks.length - 1)
			return false;

		ushort sourceTrackValue = sourceTracks[sourceTrackIndex].smashedValue;
		Clip movedEntry;
		movedEntry.trans = sourceTracks[sourceTrackIndex].trans;
		movedEntry.no = sourceTracks[sourceTrackIndex].number;

		UndoValue undoState = createState(true);

		source.trackDelete(true);
		if(sourceTracks.trackLength != sourceLength - 1) {
			restoreState(undoState);
			return false;
		}

		if(!target.trackInsertEntriesAt(insertionTrackIndex, [movedEntry])) {
			restoreState(undoState);
			return false;
		}

		activeVoice = target;
		input = target.trackinput;
		com.session.insertUndo(this, undoState);

		movedTrackIndex = insertionTrackIndex;
		movedTrackValue = sourceTrackValue;
		refresh();
		return true;
	}

	bool moveTrackEntryRangeToVoice(int sourceVoice,
			int sourceStartTrackIndex, int sourceEndTrackIndex,
			int targetVoice, int insertionTrackIndex,
			const(ushort)[] expectedTrackValues,
			out int movedStartTrackIndex, out int movedEndTrackIndex) {
		movedStartTrackIndex = -1;
		movedEndTrackIndex = -1;

		if(sourceVoice == targetVoice) {
			return moveTrackEntryRangeWithinVoice(sourceVoice,
				sourceStartTrackIndex, sourceEndTrackIndex,
				insertionTrackIndex, expectedTrackValues,
				movedStartTrackIndex, movedEndTrackIndex);
		}
		if(sourceEndTrackIndex < sourceStartTrackIndex)
			return false;

		int count = sourceEndTrackIndex - sourceStartTrackIndex + 1;
		if(count <= 1 || expectedTrackValues.length != cast(size_t)count)
			return false;

		auto source = prepareTrackEntryEditAt(sourceVoice,
			sourceStartTrackIndex, expectedTrackValues[0]);
		if(source is null)
			return false;
		if(targetVoice < 0 || targetVoice >= cast(int)voices.length)
			return false;

		auto target = cast(TrackVoice)voices[targetVoice];
		if(target is null)
			return false;

		Tracklist sourceTracks = source.tracks;
		Tracklist targetTracks = target.tracks;
		int sourceLength = sourceTracks.trackLength;
		int targetLength = targetTracks.trackLength;
		if(sourceEndTrackIndex >= sourceLength)
			return false;
		if(sourceLength <= count)
			return false;
		if(insertionTrackIndex < 0 || insertionTrackIndex > targetLength)
			return false;
		if(cast(long)targetLength + count > targetTracks.length - 1)
			return false;

		Clip[] movedEntries;
		movedEntries.length = count;
		foreach(idx, expectedTrackValue; expectedTrackValues) {
			int trackIndex = sourceStartTrackIndex + cast(int)idx;
			Track track = sourceTracks[trackIndex];
			if(track.trans >= 0xf0 ||
					track.smashedValue != expectedTrackValue)
				return false;
			movedEntries[idx].trans = track.trans;
			movedEntries[idx].no = track.number;
		}

		UndoValue undoState = createState(true);

		if(!source.trackDeleteEntriesAt(sourceStartTrackIndex,
				sourceEndTrackIndex)) {
			restoreState(undoState);
			return false;
		}
		if(sourceTracks.trackLength != sourceLength - count) {
			restoreState(undoState);
			return false;
		}

		if(!target.trackInsertEntriesAt(insertionTrackIndex,
				movedEntries)) {
			restoreState(undoState);
			return false;
		}

		activeVoice = target;
		input = target.trackinput;
		com.session.insertUndo(this, undoState);

		movedStartTrackIndex = insertionTrackIndex;
		movedEndTrackIndex = insertionTrackIndex + count - 1;
		refresh();
		return true;
	}

	bool pasteTrackEntriesAfter(int voice, int anchorTrackIndex,
			ushort expectedTrackValue, const(Clip)[] entries,
			out int firstInsertedTrackIndex, out int lastInsertedTrackIndex,
			out int insertedCount) {
		firstInsertedTrackIndex = -1;
		lastInsertedTrackIndex = -1;
		insertedCount = 0;

		if(entries.length == 0)
			return false;

		auto v = prepareTrackEntryEditAt(voice, anchorTrackIndex,
			expectedTrackValue);
		if(v is null)
			return false;

		Tracklist tracks = v.tracks;
		int insertionTrackIndex = anchorTrackIndex + 1;
		if(insertionTrackIndex < 0 ||
				insertionTrackIndex > tracks.trackLength)
			return false;
		if(cast(long)tracks.trackLength + entries.length >
				tracks.length - 1)
			return false;

		if(!saveState(false))
			return false;
		if(!v.trackInsertEntriesAt(insertionTrackIndex, entries))
			return false;

		firstInsertedTrackIndex = insertionTrackIndex;
		insertedCount = cast(int)entries.length;
		lastInsertedTrackIndex = firstInsertedTrackIndex + insertedCount - 1;
		refresh();
		return true;
	}

	bool insertTrackEntriesAt(int voice, int insertionTrackIndex,
			const(Clip)[] entries,
			out int firstInsertedTrackIndex, out int lastInsertedTrackIndex,
			out int insertedCount) {
		firstInsertedTrackIndex = -1;
		lastInsertedTrackIndex = -1;
		insertedCount = 0;

		if(entries.length == 0 || voice < 0 ||
				voice >= cast(int)voices.length)
			return false;

		auto v = cast(TrackVoice)voices[voice];
		if(v is null || v.trackinput is null)
			return false;

		Tracklist tracks = v.tracks;
		if(insertionTrackIndex < 0 ||
				insertionTrackIndex > tracks.trackLength)
			return false;
		if(cast(long)tracks.trackLength + entries.length >
				tracks.length - 1)
			return false;

		activeVoiceNum = voice;
		activeVoice = v;
		input = v.trackinput;

		if(!saveState(false))
			return false;
		if(!v.trackInsertEntriesAt(insertionTrackIndex, entries))
			return false;

		firstInsertedTrackIndex = insertionTrackIndex;
		insertedCount = cast(int)entries.length;
		lastInsertedTrackIndex = firstInsertedTrackIndex +
			insertedCount - 1;
		refresh();
		return true;
	}

	bool setLoopTargetForVoiceAtTrackIndex(int voice, int targetTrackIndex,
			ushort expectedTrackValue) {
		auto v = trackEntryAt(voice, targetTrackIndex, expectedTrackValue);
		if(v is null)
			return false;

		if(v.tracks.wrapOffset == targetTrackIndex)
			return true;

		if(!saveState(true))
			return false;

		v.tracks.wrapOffset = cast(ushort)targetTrackIndex;
		refresh();
		return true;
	}

	bool setLoopTargetsForVoiceTrackIndices(int[3] targetTrackIndex,
			ushort[3] expectedTrackValue) {
		TrackVoice[3] targetVoices;
		bool changed;
		foreach(i; 0 .. targetVoices.length) {
			auto v = trackEntryAt(cast(int)i, targetTrackIndex[i],
				expectedTrackValue[i]);
			if(v is null)
				return false;
			targetVoices[i] = v;
			if(v.tracks.wrapOffset != targetTrackIndex[i])
				changed = true;
		}

		if(!changed)
			return true;
		if(!saveState(true))
			return false;

		foreach(i, v; targetVoices) {
			v.tracks.wrapOffset = cast(ushort)targetTrackIndex[i];
		}
		refresh();
		return true;
	}

		void deleteCurrentTrackEntry() {
			auto v = prepareCurrentTrackEdit();
			if(v is null)
				return;
			RowData row = v.activeRow;
			if(row.trkOffset < 0 || row.trkOffset >= v.tracks.trackLength ||
					row.track.trans >= 0xf0)
				return;
			if(!saveState(false))
				return;
			v.trackDelete(true);
			if(v.pos.trkOffset >= v.tracks.trackLength-1)
				jump(Jump.toEnd,true);
			else
				refresh();
		}

		private final void setCurrentLoopTarget() {
			auto activeTrackVoice = prepareCurrentTrackEdit();
			if(activeTrackVoice is null)
				return;

			int[3] targetTrackIndex;
			foreach(i, voice; voices) {
				auto v = cast(TrackVoice)voice;
				if(v is null)
					return;
				v.refreshTrack(posTable.pointerOffset);
				int trackLength = v.tracks.trackLength;
				if(v.activeRow.trkOffset < 0 ||
						v.activeRow.trkOffset >= trackLength)
					return;
				targetTrackIndex[i] = v.activeRow.trkOffset;
			}

			if(!saveState(true))
				return;

			foreach(i, voice; voices) {
				auto v = cast(TrackVoice)voice;
				v.tracks.wrapOffset = cast(ushort)targetTrackIndex[i];
			}
			refresh();
		}

	private bool handleTrackEntryStructuralKey(Keyinfo key) {
		KeyboardActionId actionId;
		bool resolved = resolveTrackEntryStructuralKeyboardAction(key, actionId);
		bool matched = resolved;

		if(!resolved) {
			if(isTrackEntryInsertShortcut(key)) {
				actionId = KeyboardActionId.trackEntryInsert;
				matched = true;
			}
			else if(isTrackEntryInsertCopyShortcut(key)) {
				actionId = KeyboardActionId.trackEntryInsertCopy;
				matched = true;
			}
			else if(isTrackEntryDeleteShortcut(key)) {
				actionId = KeyboardActionId.trackEntryDelete;
				matched = true;
			}
		}

		if(!matched)
			return false;
		return handleTrackEntryStructuralAction(actionId);
	}

	private bool handleTrackEntryClipboardKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveTrackEntryClipboardKeyboardAction(key, actionId))
			return false;
		return handleTrackEntryClipboardAction(actionId);
	}

		private bool handleTrackEntryLoopKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveTrackEntryLoopSetAllVoicesKeyboardAction(key, actionId))
				return false;
			setCurrentLoopTarget();
			return true;
		}

	private bool handleTrackEntryTransposeKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveTrackEntryTransposeKeyboardAction(key, actionId))
			return false;
		return handleTrackEntryTransposeAction(actionId);
	}

	private bool handleTrackEntrySwapKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveTrackEntrySwapKeyboardAction(key, actionId))
			return false;
		return handleTrackEntrySwapAction(actionId);
	}

	private bool handleTrackEntryNavigationKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveTrackEntryNavigationKeyboardAction(key, actionId))
			return false;
		return handleTrackEntryNavigationAction(actionId);
	}

	private bool handleTrackEntryStructuralAction(KeyboardActionId actionId) {
		switch(actionId) {
		case KeyboardActionId.trackEntryInsert:
			version(OSX) {
				insertCurrentTrackEntry();
			}
			else {
				saveState(false);
				auto v = cast(TrackVoice)activeVoice;
				v.trackInsert(true);
			}
			return true;
		case KeyboardActionId.trackEntryInsertCopy:
			insertCopyOfCurrentTrackEntry();
			return true;
		case KeyboardActionId.trackEntryDelete:
			deleteCurrentTrackEntry();
			return true;
		case KeyboardActionId.trackEntryInsertToEnd:
			saveState(false);
			(cast(TrackVoice)activeVoice).trackInsert(false);
			jump(Jump.toEnd, true);
			return true;
		case KeyboardActionId.trackEntryDeleteToEnd:
			saveState(true);
			(cast(TrackVoice)activeVoice).trackDelete(false);
			jump(Jump.toEnd, true);
			return true;
		case KeyboardActionId.trackEntryInsertAllVoices:
			saveState(true);
			for(int i = 0; i < voices.length; i++) {
				auto v = cast(TrackVoice)voices[i];
				v.trackInsert(true);
			}
			return true;
		case KeyboardActionId.trackEntryDeleteAllVoices:
			saveState(true);
			for(int i = 0; i < voices.length; i++) {
				auto v = cast(TrackVoice)voices[i];
				v.trackDelete(true);
			}
			return true;
		default:
			return false;
		}
	}

	private bool handleTrackEntryClipboardAction(KeyboardActionId actionId) {
		switch(actionId) {
		case KeyboardActionId.trackEntryCopyPrompt:
			mainui.activateDialog(queryClip);
			return true;
		case KeyboardActionId.trackEntryPastePrompt:
			mainui.activateDialog(new ConfirmationDialog("Paste tracks; insert or overwrite? (i/o) ",
														 &pasteCallback,
														 "oi", 1));
			return true;
		case KeyboardActionId.trackEntryPasteInsert:
			pasteTracks(clip, true);
			return true;
		case KeyboardActionId.trackEntryPasteOverwrite:
			pasteTracks(clip, false);
			return true;
		default:
			return false;
		}
	}

	private bool handleTrackEntryTransposeAction(KeyboardActionId actionId) {
		switch(actionId) {
		case KeyboardActionId.trackEntryTransposeUpFromCursor:
			saveState(true);
			(cast(TrackVoice)activeVoice).trackTrans(1);
			return true;
		case KeyboardActionId.trackEntryTransposeDownFromCursor:
			saveState(true);
			(cast(TrackVoice)activeVoice).trackTrans(-1);
			return true;
		default:
			return false;
		}
	}

	private bool handleTrackEntrySwapAction(KeyboardActionId actionId) {
		switch(actionId) {
		case KeyboardActionId.trackEntrySwapWithVoice1:
			trackSwap(0);
			return true;
		case KeyboardActionId.trackEntrySwapWithVoice2:
			trackSwap(1);
			return true;
		case KeyboardActionId.trackEntrySwapWithVoice3:
			trackSwap(2);
			return true;
		default:
			return false;
		}
	}

	private bool moveTrackCursorToBoundary(bool end) {
		auto v = cast(TrackVoice)activeVoice;
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

		Track targetTrack = v.tracks[targetTrackIndex];
		int visibleRow = end ?
			trackBottomAllowedVisibleRow() :
			trackTopAllowedVisibleRow();
		return activateAtTrackEntryClamped(activeVoiceNum,
			targetTrackIndex, targetTrack.smashedValue, visibleRow);
	}

	private bool handleTrackEntryNavigationAction(KeyboardActionId actionId) {
		switch(actionId) {
		case KeyboardActionId.trackEntryNavigateStart:
			moveTrackCursorToBoundary(false);
			return true;
		case KeyboardActionId.trackEntryNavigateEnd:
			moveTrackCursorToBoundary(true);
			return true;
		default:
			return false;
		}
	}
		
	override int keypress(Keyinfo key) {
		if(handleTrackEntryLoopKey(key))
			return OK;

		if(handleTrackEntryStructuralKey(key))
			return OK;

		if(handleTrackEntryClipboardKey(key))
			return OK;

		handleTrackEntryTransposeKey(key);

		if(handleTrackEntryNavigationKey(key))
			return OK;

		handleTrackEntrySwapKey(key);
		
		super.keypress(key);
	
		switch(activeVoice.keypress(key))
		{
		case WRAPL:
			stepVoice(-1);
			break;
		case WRAPR:
			stepVoice(1);
			break;
		default:
			break;
		}

		return OK;
	}

	override void toSeqEnd() {
		return;
	}

	override void toSeqStart() {
		return;
	}

	override void refresh() {
		foreach(v; voices) {
			(cast(TrackVoice)v).refreshTrack(posTable.pointerOffset);
			v.refresh();
		}
	}
	
	override void jump(int jumpto, bool center) { 
	  activeVoice.trackFlush(posTable.pointerOffset); 
	  super.jump(jumpto,center); 
	}

	override void activate() {
		super.activate();
	}	

	override void deactivate() {
		super.deactivate();
		activeVoice.deactivate();
	}

	/* custom voicestepper: voice resync needed because
	 * tracks may not be aligned */
	override void stepVoice(int i) {
		int nib = 3 ^ 3 - activeVoice.activeInput.nibble;
		super.stepVoice(i);
		super.step(-activeVoice.activeRow.seqOffset,0);
		activeVoice.activeInput.nibble = nib;
	}

	override void step(int st, int extra, int height) {
		activeVoice.trackFlush(posTable.pointerOffset);
		doStep(true, st);
	}

	protected void trackSwap(int withVoice) {
		saveState(true);
		Tracklist from = getTracklist(activeVoice);
		Tracklist to = getTracklist(voices[withVoice]);
		// Track data is swapped verbatim; transferred LOOP targets are not rebased.
		// Deferred: define whether LOOP targets should follow the swapped track data.
		for(int i = 0; i < from.length; i++) {
			if(i >= to.length) break;
			int temptrans, tempno;
			temptrans = to[i].trans;
			tempno = to[i].number;
			to[i].setValue(from[i].trans, from[i].number);
			from[i].setValue(temptrans, tempno);
		}
		refresh();
	}

	void clipCallback(int num) {
		const int trackLength = activeVoice.tracks.trackLength;
		int curTrkOffset = activeVoice.activeRow.trkOffset;
		Tracklist tl = getTracklist(activeVoice)[0..num];
		int length = tl.length;
		
		if(curTrkOffset + num >= trackLength)
			length = trackLength - curTrkOffset;
		assert(length >= 0);
		clip.length = length;
		for(int i = 0; i < length; i++) {
			clip[i].trans = tl[i].trans;
			clip[i].no = tl[i].number;
		}
	}

	void pasteCallback(int value) {
		pasteTracks(clip, value > 0);
	}
	
	private void pasteTracks(Clip[] clip, bool doInsert) {
		saveState(false);
		if(doInsert) {
			for(int i = 0; i < clip.length; i++) {
				auto v = cast(TrackVoice)activeVoice;
				v.trackInsert(true);
			}
		}
		Tracklist vtr = getTracklist(activeVoice)[0..clip.length];
		// FIX: ADD .dup operator to Tracklist
		for(int i = 0; i < clip.length; i++) {
			vtr[i].setValue(clip[i].trans,clip[i].no);
		}
		// reinitialize trackinput for voices
		refresh();
		// make sure cursor not past track end
		step(0,0,0);

		clip.length = 0;
	}

		protected bool saveState(bool allVoices) {
			if(currentTrackInput() is null)
				return false;
			auto undoState = createState(allVoices);
			com.session.insertUndo(this, undoState);
			return true;
		}

	private UndoValue createState(bool allVoices,
			Sequence sequenceSnapshot = null) {
			import std.typecons;
			UndoValue v;
			auto trackInput = currentTrackInput();

			assert(trackInput !is null);
			v.trackValue = trackInput.trk.dup;
			v.track = trackInput.trk;

			if(allVoices) {
				v.trackLists.length = voices.length;
				for(int i = 0; i < voices.length; i++) {
					auto tl = voices[i].tracks;
					v.trackLists[i].store = tl.deepcopy;
					v.trackLists[i].source = tl;
				}
			}
			else {
				auto tl = getTracklist(activeVoice);
				v.trackLists.length = 1;
				v.trackLists[0].store = tl.deepcopy;
				v.trackLists[0].source = tl;
			}
			if(sequenceSnapshot !is null) {
				v.array = UndoValue.Array(sequenceSnapshot.data.raw.dup,
					sequenceSnapshot.data.raw);
				v.seq = sequenceSnapshot;
			}
			v.posTable = posTable.dup();
			v.subtuneNum = song.subtune;
			v.allVoices = allVoices;
			return v;
		}

	private void restoreState(UndoValue v) {
		if(v.subtuneNum != song.subtune)
			return;
		
		foreach(t; v.trackLists) {
			t.source.overwriteFrom(t.store);
		}

		v.track = v.trackValue;

		if(v.seq !is null) {
			auto data = v.array.target;
			auto target = v.array.source;
			target[] = data;
			v.seq.refresh();
		}

		posTable.copyFrom(v.posTable);
		refresh();
		// make sure cursor not past track end
		step(0,0,0);
	}

	override protected final void undo(UndoValue v) {
		restoreState(v);
	}

	override protected UndoValue createRedoState(UndoValue value) {
		return createState(value.allVoices, value.seq);
	}
}


class TrackTable : BaseTrackTable {
	this(Rectangle a, PosDataTable pi) {
		int x = 5 + com.fb.border + a.x;
		for(int v=0;v<3;v++) {
			Rectangle na = Rectangle(x, a.y, a.height, 13 + com.fb.border);
			x += 13 + com.fb.border;

			voices[v] = new TrackVoice(VoiceInitParams(song.tracks[v],
													   na, pi.pos[v], this));
		}
		super(a, pi);
	}

	bool resolveRenderedTrackHeaderClick(int x, int y, out int voice,
			out int trackIndex, out ushort trackValue, out int visibleRow) {
		voice = -1;
		trackIndex = -1;
		trackValue = 0;
		visibleRow = y - 1;
		if(visibleRow < 0 || visibleRow >= area.height)
			return false;

		voice = voiceAtLocalX(x);
		if(voice < 0 || voice >= cast(int)voices.length)
			return false;
		auto v = cast(TrackVoice)voices[voice];
		if(v is null || v.trackinput is null)
			return false;

		int rowFromCursor = visibleRow - anchor;
		int localRow = v.getRowcounter(v.pos.trkOffset) +
			v.pos.seqOffset + rowFromCursor;
		int trackRows = v.getRowcounter(v.tracks.trackLength);
		if(localRow < 0 || localRow >= trackRows)
			return false;

		RowData row = v.getRowData(0, localRow);
		if(row.seq is null)
			return false;
		if(row.track.trans >= 0xf0)
			return false;
		if(row.seqOffset != 0)
			return false;
		if(row.trkOffset < 0 || row.trkOffset >= v.tracks.trackLength)
			return false;
		if(v.getRowcounter(row.trkOffset) != localRow)
			return false;

		trackIndex = row.trkOffset;
		trackValue = row.track.smashedValue;
		return true;
	}

	override void activate() {
		super.activate();
		normalizeTrackCursorIntoMovementWindow();
	}

	override void refresh() {
		foreach(v; voices) {
			(cast(TrackVoice)v).refreshTrack(posTable.pointerOffset);
			v.refresh();
		}
	}

	override protected void doStep(bool wrapOk, int r) {
		foreach(v; voices) {
			bool wrap = wrapOk;
			v.scroll(r,wrap);
		}
	}

	private bool moveTrackCursorByTrackEntries(int direction) {
		if(direction != -1 && direction != 1)
			return false;
		if(activeVoice is null)
			return false;
		activeVoice.trackFlush(posTable.pointerOffset);

		RowData row;
		if(!currentTrackCursorRow(row))
			return false;

		auto v = cast(TrackVoice)activeVoice;
		if(v is null || v.trackinput is null)
			return false;

		int targetTrackIndex = row.trkOffset + direction;
		if(targetTrackIndex < 0)
			targetTrackIndex = v.tracks.trackLength - 1;
		if(targetTrackIndex < 0 || targetTrackIndex >= v.tracks.trackLength)
			return false;

		Track targetTrack = v.tracks[targetTrackIndex];
		if(targetTrack.trans >= 0xf0)
			return false;

		return activateAtTrackEntryClamped(activeVoiceNum,
			targetTrackIndex, targetTrack.smashedValue,
			posTable.normalPointerOffset);
	}

	override int keypress(Keyinfo key) {
		if(key.mods & KMOD_CTRL) {
			switch(key.raw)
			{
			default:
				break;
			}
		}
		switch(key.raw)
		{
		case SDLK_DOWN, SDLK_PAGEDOWN:
			moveTrackCursorByTrackEntries(1);
			return OK;
		case SDLK_UP, SDLK_PAGEUP:
			moveTrackCursorByTrackEntries(-1);
			return OK;
		default:
			return super.keypress(key);
		}
	}

	@property void displayTracklist(bool toggleOrDisable) {
		foreach(voice; voices) {
			TrackVoice tv = cast(TrackVoice)voice;
			if(!toggleOrDisable)
				tv.displayTracklist = false;
			else tv.displayTracklist ^= 1;
		}
	}
}
