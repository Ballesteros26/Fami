/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module seq.trackoverview;

import ct.base;

struct TrackOverviewBlock {
	int voice;
	int trackIndex;
	int sequenceNumber;
	ushort trackValue;
	int rowLength;
	int startRow;
	int endRow;
}

struct TrackOverviewLane {
	int voice;
	TrackOverviewBlock[] blocks;
	int totalRows;
	bool hitEndMarker;
	bool hasValidLoop;
	int wrapTrackIndex = -1;
	int wrapStartRow;
	int loopEndRow;
	int loopLengthRows;
}

struct TrackOverviewPosition {
	bool valid;
	int voice;
	int globalRow;
	int localRow;
	int trackIndex = -1;
	int blockIndex = -1;
	int sequenceNumber = -1;
	ushort trackValue;
	int sequenceRowOffset = -1;
	bool repeatedLoopPass;
}

struct TrackOverviewOccurrence {
	bool valid;
	int loopPassOrdinal;
}

struct TrackOverviewCursorIdentity {
	bool valid;
	int voice = -1;
	int trackIndex = -1;
	int sequenceRowOffset = -1;
	TrackOverviewOccurrence occurrence;
}

TrackOverviewLane[] buildTrackOverview(Song sng) {
	return buildTrackOverview(sng.tracks, sng.seqs);
}

TrackOverviewLane[] buildTrackOverview(Tracklist[] tracks, Sequence[] sequences) {
	TrackOverviewLane[] lanes;
	int voiceCount = tracks.length < 3 ? cast(int)tracks.length : 3;
	lanes.length = voiceCount;

	foreach(voice; 0 .. voiceCount) {
		lanes[voice] = buildTrackOverviewLane(cast(int)voice, tracks[voice], sequences);
	}
	return lanes;
}

TrackOverviewLane buildTrackOverviewLane(int voice, Tracklist tracks, Sequence[] sequences) {
	TrackOverviewLane lane;
	lane.voice = voice;

	int startRow;
	foreach(trackIndex; 0 .. tracks.length) {
		Track track = tracks[trackIndex];
		if(track.trans >= 0xf0) {
			lane.hitEndMarker = true;
			break;
		}

		int rowLength = sequenceRowLength(track, sequences);
		TrackOverviewBlock block = TrackOverviewBlock(
			voice,
			cast(int)trackIndex,
			track.number,
			track.smashedValue,
			rowLength,
			startRow,
			startRow + rowLength);
		lane.blocks ~= block;
		startRow = block.endRow;
	}

	lane.totalRows = startRow;
	lane.loopEndRow = lane.totalRows;
	applyLoopMetadata(lane, tracks);
	return lane;
}

TrackOverviewPosition resolveTrackOverviewPosition(
		const TrackOverviewLane lane, int globalRow) {
	TrackOverviewPosition position;
	position.voice = lane.voice;
	position.globalRow = globalRow;

	if(globalRow < 0)
		return position;

	int localRow = globalRow;
	bool repeatedLoopPass;
	if(globalRow >= lane.loopEndRow) {
		if(!lane.hasValidLoop)
			return position;
		localRow = lane.wrapStartRow +
			((globalRow - lane.loopEndRow) % lane.loopLengthRows);
		repeatedLoopPass = true;
	}

	int blockIndex = findBlockIndex(lane.blocks, localRow);
	if(blockIndex < 0)
		return position;

	TrackOverviewBlock block = lane.blocks[blockIndex];
	position.valid = true;
	position.localRow = localRow;
	position.trackIndex = block.trackIndex;
	position.blockIndex = blockIndex;
	position.sequenceNumber = block.sequenceNumber;
	position.trackValue = block.trackValue;
	position.sequenceRowOffset = localRow - block.startRow;
	position.repeatedLoopPass = repeatedLoopPass;
	return position;
}

TrackOverviewPosition[] resolveTrackOverviewPositions(
		const(TrackOverviewLane)[] lanes, int globalRow) {
	TrackOverviewPosition[] positions;
	positions.length = lanes.length;
	foreach(idx, lane; lanes) {
		positions[idx] = resolveTrackOverviewPosition(lane, globalRow);
	}
	return positions;
}

TrackOverviewOccurrence trackOverviewOccurrenceAtGlobalRow(
		const TrackOverviewLane lane, int globalRow) {
	TrackOverviewOccurrence occurrence;
	TrackOverviewPosition position = resolveTrackOverviewPosition(lane, globalRow);
	if(!position.valid)
		return occurrence;

	occurrence.valid = true;
	if(position.repeatedLoopPass) {
		if(!lane.hasValidLoop || lane.loopLengthRows <= 0)
			return TrackOverviewOccurrence.init;
		occurrence.loopPassOrdinal = 1 +
			(globalRow - lane.loopEndRow) / lane.loopLengthRows;
	}
	return occurrence;
}

bool trackOverviewGlobalRowForOccurrence(const TrackOverviewLane lane,
		int trackIndex, int sequenceRowOffset,
		const TrackOverviewOccurrence occurrence, out int globalRow) {
	globalRow = -1;
	if(!occurrence.valid || occurrence.loopPassOrdinal < 0 ||
			trackIndex < 0 || sequenceRowOffset < 0)
		return false;

	TrackOverviewBlock block;
	bool foundBlock;
	foreach(candidate; lane.blocks) {
		if(candidate.trackIndex == trackIndex) {
			block = candidate;
			foundBlock = true;
			break;
		}
	}
	if(!foundBlock || block.rowLength <= 0 ||
			sequenceRowOffset >= block.rowLength)
		return false;

	int localRow = block.startRow + sequenceRowOffset;
	long mappedRow = localRow;
	if(occurrence.loopPassOrdinal > 0) {
		if(!lane.hasValidLoop || lane.loopLengthRows <= 0 ||
				localRow < lane.wrapStartRow || localRow >= lane.loopEndRow)
			return false;
		mappedRow += cast(long)occurrence.loopPassOrdinal * lane.loopLengthRows;
	}
	if(mappedRow < 0 || mappedRow > int.max)
		return false;

	globalRow = cast(int)mappedRow;
	TrackOverviewPosition resolved = resolveTrackOverviewPosition(lane, globalRow);
	if(!resolved.valid || resolved.trackIndex != trackIndex ||
			resolved.sequenceRowOffset != sequenceRowOffset ||
			resolved.repeatedLoopPass != (occurrence.loopPassOrdinal > 0)) {
		globalRow = -1;
		return false;
	}
	return true;
}

TrackOverviewCursorIdentity trackOverviewCursorIdentityAtGlobalRow(
		const(TrackOverviewLane)[] lanes, int globalRow, int voice,
		int trackIndex, int sequenceRowOffset) {
	TrackOverviewCursorIdentity identity;
	if(globalRow < 0 || voice < 0 || voice >= cast(int)lanes.length ||
			trackIndex < 0 || sequenceRowOffset < 0)
		return identity;

	TrackOverviewPosition position =
		resolveTrackOverviewPosition(lanes[voice], globalRow);
	if(!position.valid || position.voice != voice ||
			position.trackIndex != trackIndex ||
			position.sequenceRowOffset != sequenceRowOffset)
		return identity;

	TrackOverviewOccurrence occurrence =
		trackOverviewOccurrenceAtGlobalRow(lanes[voice], globalRow);
	if(!occurrence.valid)
		return identity;

	identity.valid = true;
	identity.voice = voice;
	identity.trackIndex = trackIndex;
	identity.sequenceRowOffset = sequenceRowOffset;
	identity.occurrence = occurrence;
	return identity;
}

bool trackOverviewGlobalRowForCursorIdentity(
		const(TrackOverviewLane)[] lanes,
		const TrackOverviewCursorIdentity identity, out int globalRow) {
	globalRow = -1;
	if(!identity.valid || identity.voice < 0 ||
			identity.voice >= cast(int)lanes.length)
		return false;

	if(!trackOverviewGlobalRowForOccurrence(lanes[identity.voice],
			identity.trackIndex, identity.sequenceRowOffset,
			identity.occurrence, globalRow))
		return false;

	TrackOverviewPosition position =
		resolveTrackOverviewPosition(lanes[identity.voice], globalRow);
	if(!position.valid || position.voice != identity.voice ||
			position.trackIndex != identity.trackIndex ||
			position.sequenceRowOffset != identity.sequenceRowOffset) {
		globalRow = -1;
		return false;
	}
	return true;
}

bool trackOverviewResolutionSelfCheck() {
	enum CHECK_ROW = 320;

	TrackOverviewLane[] lanes = trackOverviewSelfCheckLanes();
	TrackOverviewPosition[] positions = resolveTrackOverviewPositions(lanes,
		CHECK_ROW);
	if(positions.length != 3)
		return false;

	if(!trackOverviewSelfCheckPosition(positions[0], 0, CHECK_ROW, 10, 10,
			6, 0, false))
		return false;
	if(!trackOverviewSelfCheckPosition(positions[1], 1, 0, 0, 0, 1, 0, true))
		return false;
	if(!trackOverviewSelfCheckPosition(positions[2], 2, CHECK_ROW, 5, 5,
			3, 0, false))
		return false;

	TrackOverviewLane noLoopLane = trackOverviewSelfCheckLane(0,
		[ trackOverviewSelfCheckBlock(0, 0, 1, 0xa001, 0, 64) ], false, -1);
	if(resolveTrackOverviewPosition(noLoopLane, CHECK_ROW).valid)
		return false;
	if(!trackOverviewOccurrenceSelfCheck())
		return false;

	return true;
}

private bool trackOverviewOccurrenceSelfCheck() {
	TrackOverviewLane oldLane = trackOverviewSelfCheckLane(0, [
		trackOverviewSelfCheckBlock(0, 0, 7, 0xa007, 0, 4),
		trackOverviewSelfCheckBlock(0, 1, 7, 0xa007, 4, 4)
	], true, 0);
	TrackOverviewLane newLane = trackOverviewSelfCheckLane(0, [
		trackOverviewSelfCheckBlock(0, 0, 7, 0xa007, 0, 4),
		trackOverviewSelfCheckBlock(0, 1, 7, 0xa007, 4, 5)
	], true, 0);

	TrackOverviewOccurrence base =
		trackOverviewOccurrenceAtGlobalRow(oldLane, 6);
	TrackOverviewOccurrence firstRepeat =
		trackOverviewOccurrenceAtGlobalRow(oldLane, 14);
	TrackOverviewOccurrence secondRepeat =
		trackOverviewOccurrenceAtGlobalRow(oldLane, 22);
	if(!base.valid || base.loopPassOrdinal != 0 ||
			!firstRepeat.valid || firstRepeat.loopPassOrdinal != 1 ||
			!secondRepeat.valid || secondRepeat.loopPassOrdinal != 2)
		return false;

	int globalRow;
	if(!trackOverviewGlobalRowForOccurrence(newLane, 1, 2,
			secondRepeat, globalRow) || globalRow != 24)
		return false;
	TrackOverviewPosition remapped = resolveTrackOverviewPosition(newLane,
		globalRow);
	if(!remapped.valid || remapped.trackIndex != 1 ||
			remapped.sequenceNumber != 7 || remapped.sequenceRowOffset != 2)
		return false;

	if(!trackOverviewGlobalRowForOccurrence(newLane, 0, 2, base,
			globalRow) || globalRow != 2)
		return false;

	TrackOverviewLane[] oldLanes = [oldLane];
	TrackOverviewLane[] newLanes = [newLane];
	TrackOverviewCursorIdentity invalidIdentity;
	if(trackOverviewGlobalRowForCursorIdentity(newLanes, invalidIdentity,
			globalRow))
		return false;

	TrackOverviewCursorIdentity baseIdentity =
		trackOverviewCursorIdentityAtGlobalRow(oldLanes, 6, 0, 1, 2);
	if(!baseIdentity.valid || baseIdentity.occurrence.loopPassOrdinal != 0)
		return false;

	TrackOverviewCursorIdentity secondIdentity =
		trackOverviewCursorIdentityAtGlobalRow(oldLanes, 22, 0, 1, 2);
	TrackOverviewCursorIdentity copiedIdentity = secondIdentity;
	if(!copiedIdentity.valid || copiedIdentity.trackIndex != 1 ||
			copiedIdentity.occurrence.loopPassOrdinal != 2 ||
			!trackOverviewGlobalRowForCursorIdentity(newLanes,
				copiedIdentity, globalRow) || globalRow != 24)
		return false;

	if(trackOverviewCursorIdentityAtGlobalRow(oldLanes, 2, 0, 1, 2).valid)
		return false;
	return true;
}

private void applyLoopMetadata(ref TrackOverviewLane lane, Tracklist tracks) {
	if(!lane.hitEndMarker)
		return;

	int wrapTrackIndex = tracks.wrapOffset;
	lane.wrapTrackIndex = wrapTrackIndex;
	if(wrapTrackIndex < 0 || wrapTrackIndex >= cast(int)lane.blocks.length)
		return;

	lane.wrapStartRow = lane.blocks[wrapTrackIndex].startRow;
	lane.loopLengthRows = lane.loopEndRow - lane.wrapStartRow;
	lane.hasValidLoop = lane.loopLengthRows > 0;
}

private int findBlockIndex(const(TrackOverviewBlock)[] blocks, int localRow) {
	foreach(idx, block; blocks) {
		if(block.rowLength <= 0)
			continue;
		if(localRow >= block.startRow && localRow < block.endRow)
			return cast(int)idx;
	}
	return -1;
}

private int sequenceRowLength(Track track, Sequence[] sequences) {
	int sequenceNumber = track.number;
	if(sequenceNumber < 0 || sequenceNumber >= sequences.length)
		return 0;
	Sequence sequence = sequences[sequenceNumber];
	if(sequence is null)
		return 0;
	return sequence.rows;
}

private TrackOverviewLane[] trackOverviewSelfCheckLanes() {
	TrackOverviewLane[] lanes;
	lanes.length = 3;

	TrackOverviewBlock[] voice0;
	foreach(trackIndex; 0 .. 11) {
		int sequenceNumber = trackIndex == 10 ? 6 : cast(int)trackIndex;
		voice0 ~= trackOverviewSelfCheckBlock(0, cast(int)trackIndex,
			sequenceNumber, 0xa000 | sequenceNumber,
			cast(int)trackIndex * 32, 32);
	}
	lanes[0] = trackOverviewSelfCheckLane(0, voice0, false, -1);

	lanes[1] = trackOverviewSelfCheckLane(1,
		[ trackOverviewSelfCheckBlock(1, 0, 1, 0xa001, 0, 64) ], true, 0);

	TrackOverviewBlock[] voice2;
	foreach(trackIndex; 0 .. 6) {
		int sequenceNumber = trackIndex == 5 ? 3 : cast(int)trackIndex;
		voice2 ~= trackOverviewSelfCheckBlock(2, cast(int)trackIndex,
			sequenceNumber, 0xa000 | sequenceNumber,
			cast(int)trackIndex * 64, 64);
	}
	lanes[2] = trackOverviewSelfCheckLane(2, voice2, false, -1);

	return lanes;
}

private TrackOverviewLane trackOverviewSelfCheckLane(int voice,
		TrackOverviewBlock[] blocks, bool looped, int wrapBlockIndex) {
	TrackOverviewLane lane;
	lane.voice = voice;
	lane.blocks = blocks;
	if(blocks.length > 0)
		lane.totalRows = blocks[$ - 1].endRow;
	lane.loopEndRow = lane.totalRows;
	lane.hitEndMarker = looped;
	lane.wrapTrackIndex = wrapBlockIndex;

	if(looped && wrapBlockIndex >= 0 &&
			wrapBlockIndex < cast(int)blocks.length) {
		lane.wrapStartRow = blocks[wrapBlockIndex].startRow;
		lane.loopLengthRows = lane.loopEndRow - lane.wrapStartRow;
		lane.hasValidLoop = lane.loopLengthRows > 0;
	}

	return lane;
}

private TrackOverviewBlock trackOverviewSelfCheckBlock(int voice,
		int trackIndex, int sequenceNumber, int trackValue, int startRow,
		int rowLength) {
	return TrackOverviewBlock(voice, trackIndex, sequenceNumber,
		cast(ushort)trackValue, rowLength, startRow, startRow + rowLength);
}

private bool trackOverviewSelfCheckPosition(
		const TrackOverviewPosition position, int voice, int localRow,
		int trackIndex, int blockIndex, int sequenceNumber,
		int sequenceRowOffset, bool repeatedLoopPass) {
	return position.valid &&
		position.voice == voice &&
		position.localRow == localRow &&
		position.trackIndex == trackIndex &&
		position.blockIndex == blockIndex &&
		position.sequenceNumber == sequenceNumber &&
		position.sequenceRowOffset == sequenceRowOffset &&
		position.repeatedLoopPass == repeatedLoopPass;
}
