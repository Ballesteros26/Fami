/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.trackoverviewnotes;

import ct.base : Element, Song;
import seq.trackoverview : TrackOverviewLane;
import std.array : Appender;

struct TrackOverviewNotePreviewEvent {
	int rowOffset;
	int pitch;
}

struct TrackOverviewNotePreviewBlock {
	int blockIndex = -1;
	int sequenceNumber = -1;
	TrackOverviewNotePreviewEvent[] notes;
}

struct TrackOverviewNotePreviewLane {
	int voice = -1;
	bool hasPitchRange;
	int minPitch;
	int maxPitch;
	TrackOverviewNotePreviewBlock[] blocks;
}

struct TrackOverviewNotePreviews {
	TrackOverviewNotePreviewLane[] lanes;
}

TrackOverviewNotePreviews buildTrackOverviewNotePreviews(Song sng,
		const(TrackOverviewLane)[] overview) {
	TrackOverviewNotePreviews previews;
	if(sng is null)
		return previews;

	previews.lanes.length = overview.length;
	foreach(laneIndex, lane; overview) {
		TrackOverviewNotePreviewLane previewLane;
		previewLane.voice = lane.voice;
		Appender!(TrackOverviewNotePreviewBlock[]) previewBlocks;
		previewBlocks.reserve(lane.blocks.length);

		foreach(blockIndex, block; lane.blocks) {
			TrackOverviewNotePreviewBlock previewBlock;
			previewBlock.blockIndex = cast(int)blockIndex;
			previewBlock.sequenceNumber = block.sequenceNumber;

			if(block.rowLength > 0 && block.sequenceNumber >= 0 &&
					block.sequenceNumber < cast(int)sng.seqs.length) {
				auto sequence = sng.seqs[block.sequenceNumber];
				if(sequence !is null) {
					int rows = block.rowLength < sequence.rows ?
						block.rowLength : sequence.rows;
					Appender!(TrackOverviewNotePreviewEvent[]) previewNotes;
					previewNotes.reserve(rows);
					foreach(rowOffset; 0 .. rows) {
						Element element = sequence.data[rowOffset];
						int pitch = element.note.value;
						if(!isTrackOverviewPreviewNote(pitch))
							continue;

						previewNotes.put(TrackOverviewNotePreviewEvent(rowOffset,
							pitch));
						extendPitchRange(previewLane, pitch);
					}
					previewBlock.notes = previewNotes.data;
				}
			}

			if(previewBlock.notes.length > 0)
				previewBlocks.put(previewBlock);
		}

		previewLane.blocks = previewBlocks.data;
		previews.lanes[laneIndex] = previewLane;
	}

	return previews;
}

bool isTrackOverviewPreviewNote(int noteValue) {
	return noteValue >= 3 && noteValue <= 0x5e;
}

private void extendPitchRange(ref TrackOverviewNotePreviewLane lane,
		int pitch) {
	if(!lane.hasPitchRange) {
		lane.hasPitchRange = true;
		lane.minPitch = pitch;
		lane.maxPitch = pitch;
		return;
	}

	if(pitch < lane.minPitch)
		lane.minPitch = pitch;
	if(pitch > lane.maxPitch)
		lane.maxPitch = pitch;
}
