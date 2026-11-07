/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.trackoverviewstate;

import com.util : Clip;
import seq.trackoverview : TrackOverviewBlock, TrackOverviewLane,
	TrackOverviewPosition, resolveTrackOverviewPosition,
	resolveTrackOverviewPositions, trackOverviewResolutionSelfCheck;
import ui.trackoverviewlayout : TRACK_OVERVIEW_VOICE_LANES,
	trackOverviewClampedContentLocalX,
	trackOverviewContentAreaWidth, trackOverviewContentX,
	trackOverviewLocalXToRow, trackOverviewPlusRect,
	trackOverviewRowToLocalX, trackOverviewRowsToPixels,
	TRACK_OVERVIEW_ROW_WIDTH,
	trackOverviewScrollbarHeight, trackOverviewScrollbarY,
	trackOverviewTimelineXToRow,
	trackOverviewTimeRowHeight, trackOverviewTimeRowY,
	trackOverviewTotalHeight, trackOverviewVoiceLaneHeight,
	trackOverviewVoiceLaneY, trackOverviewVoiceLoopIndicatorHeight,
	trackOverviewVoiceLoopIndicatorY, trackOverviewVoiceBlockHeight,
	trackOverviewVoiceBlockY;

struct TrackOverviewScrollState {
	int scrollX;
	bool manualScrollActive;
	int manualScrollEditorRow = -1;
	bool scrollbarDragActive;
	int scrollbarDragThumbOffsetX;
	bool timelineScrubActive;
	bool timelineScrubForceNextSeek;
	bool timelineScrubHasLastTarget;
	bool[TRACK_OVERVIEW_VOICE_LANES] timelineScrubLastValid;
	int[TRACK_OVERVIEW_VOICE_LANES] timelineScrubLastTrackIndexes;
	int[TRACK_OVERVIEW_VOICE_LANES] timelineScrubLastSequenceRowOffsets;
	ushort[TRACK_OVERVIEW_VOICE_LANES] timelineScrubLastTrackValues;
}

enum TRACK_OVERVIEW_FOLLOW_LEFT_MARGIN = 80;
enum TRACK_OVERVIEW_FOLLOW_RIGHT_MARGIN = 200;
enum TRACK_OVERVIEW_KEY_SCROLL_STEP = 64 * TRACK_OVERVIEW_ROW_WIDTH;
enum TRACK_OVERVIEW_WHEEL_SCROLL_STEP = 16 * TRACK_OVERVIEW_ROW_WIDTH;
enum TRACK_OVERVIEW_DRAG_START_THRESHOLD_PIXELS = 4;
enum TRACK_OVERVIEW_DRAG_EDGE_SCROLL_ZONE_PIXELS = 48;
enum TRACK_OVERVIEW_DRAG_EDGE_SCROLL_STEP_PIXELS = 16;

struct TrackOverviewScrollbarThumb {
	int x;
	int width;
	bool enabled;
}

struct TrackOverviewViewport {
	int visibleWidth;
	int contentWidth;
	int maxScrollX;
	int scrollX;
	TrackOverviewScrollbarThumb scrollbarThumb;
}

enum TrackOverviewHitRegion {
	Outside,
	TimeRow,
	VoiceLoopLane,
	VoiceLane,
	Plus,
	Scrollbar
}

struct TrackOverviewHitTest {
	TrackOverviewHitRegion region;
	int x = -1;
	int y = -1;
	int localX = -1;
	int row = -1;
	int voice = -1;
	int blockIndex = -1;
	int trackIndex = -1;
	int sequenceNumber = -1;
	ushort trackValue;
}

struct TrackOverviewEditorCursor {
	bool valid;
	int voice = -1;
	int globalRow = -1;
	TrackOverviewPosition position;
}

struct TrackOverviewPlaybackState {
	bool active;
}

struct TrackOverviewPlaybackCursor {
	bool valid;
	bool globalVisible;
	int globalRow = -1;
	TrackOverviewPosition[TRACK_OVERVIEW_VOICE_LANES] voicePositions;
}

struct TrackOverviewBlockSelection {
	bool valid;
	int voice = -1;
	int blockIndex = -1;
	int trackIndex = -1;
	int sequenceNumber = -1;
	ushort trackValue;
}

struct TrackOverviewSelectionState {
	bool active;
	int subtune = -1;
	TrackOverviewBlockSelection primary;
	TrackOverviewBlockSelection anchor;
	int voice = -1;
	int rangeStartTrackIndex = -1;
	int rangeEndTrackIndex = -1;
	TrackOverviewBlockSelection[] selectedBlocks;
}

struct TrackOverviewDropTarget {
	bool valid;
	int voice = -1;
	int insertionTrackIndex = -1;
	int insertionRow = -1;
}

struct TrackOverviewBlockDragState {
	bool candidateActive;
	bool active;
	TrackOverviewBlockSelection source;
	bool rangeActive;
	int rangeStartTrackIndex = -1;
	int rangeEndTrackIndex = -1;
	int rangeAnchorTrackIndex = -1;
	int rangePrimaryTrackIndex = -1;
	ushort[] rangeTrackValues;
	TrackOverviewDropTarget dropTarget;
	int mouseDownX = -1;
	int mouseDownY = -1;
	int lastMouseX = -1;
	int lastMouseY = -1;
}

struct TrackOverviewCurrentEditorBlock {
	bool valid;
	int voice = -1;
	int blockIndex = -1;
	int trackIndex = -1;
	int sequenceNumber = -1;
	ushort trackValue;
	int globalRow = -1;
}

enum TrackOverviewFocusKind {
	Editor,
	Timeline,
	Block
}

struct TrackOverviewFocusState {
	TrackOverviewFocusKind kind = TrackOverviewFocusKind.Editor;
	int voice = -1;
	int blockIndex = -1;
	int trackIndex = -1;
	int sequenceNumber = -1;
	ushort trackValue;
}

int trackOverviewContentWidth(const(TrackOverviewLane)[] lanes) {
	int maxRows;
	foreach(lane; lanes) {
		if(lane.totalRows > maxRows)
			maxRows = lane.totalRows;
	}

	long width = trackOverviewRowsToPixels(maxRows);
	if(width > int.max)
		return int.max;
	return cast(int)width;
}

int trackOverviewLastTimelineRow(const(TrackOverviewLane)[] lanes) {
	int maxRows;
	foreach(lane; lanes) {
		if(lane.totalRows > maxRows)
			maxRows = lane.totalRows;
	}
	return maxRows > 0 ? maxRows - 1 : -1;
}

TrackOverviewPosition trackOverviewTimelinePositionAtRow(
		const(TrackOverviewLane)[] lanes, int activeVoice, int globalRow) {
	TrackOverviewPosition position;
	if(globalRow < 0 || activeVoice < 0 ||
			activeVoice >= cast(int)lanes.length)
		return position;

	return resolveTrackOverviewPosition(lanes[activeVoice], globalRow);
}

TrackOverviewPosition[] trackOverviewTimelinePositionsAtRow(
		const(TrackOverviewLane)[] lanes, int globalRow) {
	if(globalRow < 0)
		return null;
	return resolveTrackOverviewPositions(lanes, globalRow);
}

bool trackOverviewTimelinePositionsAllValid(
		const TrackOverviewPosition[] positions) {
	if(positions.length < TRACK_OVERVIEW_VOICE_LANES)
		return false;

	foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
		if(!positions[voice].valid)
			return false;
	}
	return true;
}

TrackOverviewPosition trackOverviewTimelineBestPosition(
		const TrackOverviewPosition[] positions, int preferredVoice) {
	TrackOverviewPosition position;
	if(preferredVoice >= 0 && preferredVoice < cast(int)positions.length &&
			positions[preferredVoice].valid)
		return positions[preferredVoice];

	foreach(candidate; positions) {
		if(candidate.valid)
			return candidate;
	}
	return position;
}

int trackOverviewMaxScrollX(int contentWidth, int visibleWidth) {
	if(contentWidth <= 0 || visibleWidth <= 0 || contentWidth <= visibleWidth)
		return 0;
	return contentWidth - visibleWidth;
}

int clampTrackOverviewScrollX(int scrollX, int contentWidth, int visibleWidth) {
	int maxScrollX = trackOverviewMaxScrollX(contentWidth, visibleWidth);
	if(scrollX < 0)
		return 0;
	if(scrollX > maxScrollX)
		return maxScrollX;
	return scrollX;
}

int trackOverviewFollowEditorCursorScrollX(int scrollX, int contentWidth,
		int visibleWidth, const TrackOverviewEditorCursor cursor) {
	scrollX = clampTrackOverviewScrollX(scrollX, contentWidth, visibleWidth);
	if(!cursor.valid || cursor.globalRow < 0 || visibleWidth <= 0)
		return scrollX;

	return trackOverviewFollowRowScrollX(scrollX, contentWidth, visibleWidth,
		cursor.globalRow);
}

int trackOverviewFollowPlaybackCursorScrollX(int scrollX, int contentWidth,
		int visibleWidth, const TrackOverviewPlaybackCursor cursor) {
	scrollX = clampTrackOverviewScrollX(scrollX, contentWidth, visibleWidth);
	if(!cursor.globalVisible || cursor.globalRow < 0 || visibleWidth <= 0)
		return scrollX;

	return trackOverviewFollowRowScrollX(scrollX, contentWidth, visibleWidth,
		cursor.globalRow);
}

int trackOverviewCenterPlaybackCursorScrollX(int scrollX, int contentWidth,
		int visibleWidth, const TrackOverviewPlaybackCursor cursor) {
	scrollX = clampTrackOverviewScrollX(scrollX, contentWidth, visibleWidth);
	if(!cursor.globalVisible || cursor.globalRow < 0 || visibleWidth <= 0)
		return scrollX;

	long markerX = trackOverviewRowsToPixels(cursor.globalRow);
	long nextScrollX = markerX - visibleWidth / 2;
	return clampTrackOverviewScrollX(clampLongToInt(nextScrollX), contentWidth,
		visibleWidth);
}

int trackOverviewFollowRowScrollX(int scrollX, int contentWidth,
		int visibleWidth, int row) {
	scrollX = clampTrackOverviewScrollX(scrollX, contentWidth, visibleWidth);
	if(row < 0 || visibleWidth <= 0)
		return scrollX;

	long markerX = trackOverviewRowsToPixels(row);
	long visibleStart = scrollX;
	int leftMargin = trackOverviewFollowLeftMargin(visibleWidth);
	int rightMargin = trackOverviewFollowRightMargin(visibleWidth);
	long followStart = visibleStart + leftMargin;
	long followEnd = visibleStart + visibleWidth - rightMargin;
	long nextScrollX = scrollX;

	if(markerX < followStart)
		nextScrollX = markerX - leftMargin;
	else if(markerX >= followEnd)
		nextScrollX = markerX - visibleWidth + rightMargin + 1;

	return clampTrackOverviewScrollX(clampLongToInt(nextScrollX), contentWidth,
		visibleWidth);
}

TrackOverviewScrollbarThumb trackOverviewScrollbarThumb(
		int visibleWidth, int contentWidth, int scrollX) {
	TrackOverviewScrollbarThumb thumb;
	if(visibleWidth <= 0)
		return thumb;

	int maxScrollX = trackOverviewMaxScrollX(contentWidth, visibleWidth);
	scrollX = clampTrackOverviewScrollX(scrollX, contentWidth, visibleWidth);
	if(maxScrollX == 0) {
		thumb.width = visibleWidth;
		return thumb;
	}

	long thumbWidth = cast(long)visibleWidth * visibleWidth / contentWidth;
	if(thumbWidth < 1)
		thumbWidth = 1;
	else if(thumbWidth > visibleWidth)
		thumbWidth = visibleWidth;

	int travelWidth = visibleWidth - cast(int)thumbWidth;
	long thumbX = cast(long)scrollX * travelWidth / maxScrollX;
	thumb.x = cast(int)thumbX;
	thumb.width = cast(int)thumbWidth;
	thumb.enabled = true;
	return thumb;
}

TrackOverviewViewport trackOverviewViewport(
		const(TrackOverviewLane)[] lanes, int visibleWidth, int scrollX) {
	TrackOverviewViewport viewport;
	viewport.visibleWidth = visibleWidth > 0 ? visibleWidth : 0;
	viewport.contentWidth = trackOverviewContentWidth(lanes);
	viewport.maxScrollX = trackOverviewMaxScrollX(viewport.contentWidth,
		viewport.visibleWidth);
	viewport.scrollX = clampTrackOverviewScrollX(scrollX, viewport.contentWidth,
		viewport.visibleWidth);
	viewport.scrollbarThumb = trackOverviewScrollbarThumb(viewport.visibleWidth,
		viewport.contentWidth, viewport.scrollX);
	return viewport;
}

bool trackOverviewScrollByPixels(ref TrackOverviewScrollState state,
		const(TrackOverviewLane)[] lanes, int visibleWidth, int deltaX,
		int editorRow) {
	TrackOverviewViewport viewport = trackOverviewViewport(lanes, visibleWidth,
		state.scrollX);
	int oldScrollX = viewport.scrollX;
	int nextScrollX = clampTrackOverviewScrollX(
		clampLongToInt(cast(long)oldScrollX + deltaX),
		viewport.contentWidth, viewport.visibleWidth);
	state.scrollX = nextScrollX;

	if(nextScrollX == oldScrollX)
		return false;

	state.manualScrollActive = true;
	state.manualScrollEditorRow = editorRow;
	return true;
}

void clearTrackOverviewManualScroll(ref TrackOverviewScrollState state) {
	state.manualScrollActive = false;
	state.manualScrollEditorRow = -1;
}

void stopTrackOverviewScrollbarDrag(ref TrackOverviewScrollState state) {
	state.scrollbarDragActive = false;
	state.scrollbarDragThumbOffsetX = 0;
}

void stopTrackOverviewTimelineScrub(ref TrackOverviewScrollState state) {
	state.timelineScrubActive = false;
	state.timelineScrubForceNextSeek = false;
	clearTrackOverviewTimelineScrubTarget(state);
}

private void clearTrackOverviewTimelineScrubTarget(
		ref TrackOverviewScrollState state) {
	state.timelineScrubHasLastTarget = false;
	foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
		state.timelineScrubLastValid[voice] = false;
		state.timelineScrubLastTrackIndexes[voice] = -1;
		state.timelineScrubLastSequenceRowOffsets[voice] = -1;
		state.timelineScrubLastTrackValues[voice] = 0;
	}
}

void stopTrackOverviewPointerDrag(ref TrackOverviewScrollState state) {
	stopTrackOverviewScrollbarDrag(state);
	stopTrackOverviewTimelineScrub(state);
}

void syncTrackOverviewManualScroll(ref TrackOverviewScrollState state,
		const TrackOverviewEditorCursor cursor) {
	if(!state.manualScrollActive)
		return;
	if(!cursor.valid) {
		clearTrackOverviewManualScroll(state);
		return;
	}
	if(state.manualScrollEditorRow >= 0 &&
			cursor.globalRow != state.manualScrollEditorRow)
		clearTrackOverviewManualScroll(state);
}

bool startTrackOverviewScrollbarDrag(ref TrackOverviewScrollState state,
		const TrackOverviewViewport viewport, int localX, int editorRow) {
	if(!viewport.scrollbarThumb.enabled)
		return false;
	if(!trackOverviewLocalXInThumb(localX, viewport.scrollbarThumb))
		return false;

	stopTrackOverviewTimelineScrub(state);
	state.scrollbarDragActive = true;
	state.scrollbarDragThumbOffsetX = localX - viewport.scrollbarThumb.x;
	state.manualScrollActive = true;
	state.manualScrollEditorRow = editorRow;
	return true;
}

void startTrackOverviewTimelineScrub(ref TrackOverviewScrollState state) {
	stopTrackOverviewScrollbarDrag(state);
	state.timelineScrubActive = true;
	state.timelineScrubForceNextSeek = true;
	clearTrackOverviewTimelineScrubTarget(state);
}

bool rememberTrackOverviewTimelineScrubTargets(
		ref TrackOverviewScrollState state,
		const TrackOverviewPosition[] positions) {
	if(!state.timelineScrubActive || positions.length == 0)
		return false;

	bool same = state.timelineScrubHasLastTarget;
	foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
		bool valid = voice < positions.length && positions[voice].valid;
		if(state.timelineScrubLastValid[voice] != valid) {
			same = false;
			continue;
		}
		if(!valid)
			continue;
		if(state.timelineScrubLastTrackIndexes[voice] !=
				positions[voice].trackIndex ||
				state.timelineScrubLastSequenceRowOffsets[voice] !=
				positions[voice].sequenceRowOffset ||
				state.timelineScrubLastTrackValues[voice] !=
				positions[voice].trackValue)
			same = false;
	}
	if(same)
		return false;

	state.timelineScrubHasLastTarget = true;
	foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
		bool valid = voice < positions.length && positions[voice].valid;
		state.timelineScrubLastValid[voice] = valid;
		if(valid) {
			state.timelineScrubLastTrackIndexes[voice] =
				positions[voice].trackIndex;
			state.timelineScrubLastSequenceRowOffsets[voice] =
				positions[voice].sequenceRowOffset;
			state.timelineScrubLastTrackValues[voice] =
				positions[voice].trackValue;
		}
		else {
			state.timelineScrubLastTrackIndexes[voice] = -1;
			state.timelineScrubLastSequenceRowOffsets[voice] = -1;
			state.timelineScrubLastTrackValues[voice] = 0;
		}
	}
	return true;
}

bool trackOverviewTimelineSelfCheck() {
	return trackOverviewResolutionSelfCheck() &&
		trackOverviewTimelineScrubTargetSelfCheck();
}

debug void runTrackOverviewSelfChecks() {
	assert(trackOverviewResolutionSelfCheck());
	assert(trackOverviewTimelineSelfCheck());
}

private bool trackOverviewTimelineScrubTargetSelfCheck() {
	TrackOverviewScrollState state;
	TrackOverviewPosition[TRACK_OVERVIEW_VOICE_LANES] positions;

	foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
		positions[voice] = trackOverviewScrubSelfCheckPosition(
			cast(int)voice, cast(int)voice, cast(int)voice + 1,
			cast(int)voice * 8, 0xa000 | (cast(int)voice + 1));
	}

	startTrackOverviewTimelineScrub(state);
	if(!rememberTrackOverviewTimelineScrubTargets(state, positions[]))
		return false;
	if(rememberTrackOverviewTimelineScrubTargets(state, positions[]))
		return false;

	positions[0].valid = false;
	TrackOverviewPosition fallback =
		trackOverviewTimelineBestPosition(positions[], 0);
	if(!fallback.valid || fallback.voice != 1)
		return false;

	positions[0].valid = true;
	positions[2].sequenceRowOffset++;
	if(!rememberTrackOverviewTimelineScrubTargets(state, positions[]))
		return false;

	return true;
}

bool dragTrackOverviewScrollbar(ref TrackOverviewScrollState state,
		const TrackOverviewViewport viewport, int localX, int editorRow) {
	if(!state.scrollbarDragActive)
		return false;
	if(viewport.visibleWidth <= 0 || viewport.maxScrollX <= 0) {
		stopTrackOverviewScrollbarDrag(state);
		return false;
	}

	int travelWidth = viewport.visibleWidth - viewport.scrollbarThumb.width;
	if(travelWidth <= 0) {
		state.scrollX = 0;
		stopTrackOverviewScrollbarDrag(state);
		return false;
	}

	int thumbX = localX - state.scrollbarDragThumbOffsetX;
	if(thumbX < 0)
		thumbX = 0;
	else if(thumbX > travelWidth)
		thumbX = travelWidth;

	long scrollX = cast(long)thumbX * viewport.maxScrollX / travelWidth;
	int nextScrollX = clampTrackOverviewScrollX(clampLongToInt(scrollX),
		viewport.contentWidth, viewport.visibleWidth);
	bool changed = nextScrollX != state.scrollX;
	state.scrollX = nextScrollX;
	state.manualScrollActive = true;
	state.manualScrollEditorRow = editorRow;
	return changed;
}

void clearTrackOverviewBlockSelection(
		ref TrackOverviewBlockSelection selection) {
	selection = TrackOverviewBlockSelection();
}

void clearTrackOverviewSelectionState(
		ref TrackOverviewSelectionState selection) {
	selection = TrackOverviewSelectionState();
}

void setTrackOverviewSingleSelectionState(
		ref TrackOverviewSelectionState state, int subtune,
		const TrackOverviewBlockSelection selection) {
	clearTrackOverviewSelectionState(state);
	if(!selection.valid)
		return;

	state.active = true;
	state.subtune = subtune;
	state.primary = selection;
	state.anchor = selection;
	state.voice = selection.voice;
	state.rangeStartTrackIndex = selection.trackIndex;
	state.rangeEndTrackIndex = selection.trackIndex;
	state.selectedBlocks.length = 1;
	state.selectedBlocks[0] = selection;
}

bool validateTrackOverviewSelectionState(
		ref TrackOverviewSelectionState state, int subtune,
		const TrackOverviewBlockSelection singleSelection,
		const(TrackOverviewLane)[] lanes) {
	if(subtune < 0 || !singleSelection.valid) {
		clearTrackOverviewSelectionState(state);
		return false;
	}

	if(!trackOverviewSelectionExists(singleSelection, lanes)) {
		clearTrackOverviewSelectionState(state);
		return false;
	}

	if(!state.active || state.subtune != subtune ||
			!trackOverviewBlockSelectionsMatch(state.primary,
				singleSelection)) {
		setTrackOverviewSingleSelectionState(state, subtune,
			singleSelection);
		return state.active;
	}

	if(!trackOverviewSelectionRangeIsValid(state, lanes)) {
		setTrackOverviewSingleSelectionState(state, subtune,
			singleSelection);
	}
	return state.active;
}

bool trackOverviewSelectionHasSelection(
		const TrackOverviewSelectionState state) {
	return state.active && state.primary.valid && state.selectedBlocks.length > 0;
}

int trackOverviewSelectionPrimaryVoice(
		const TrackOverviewSelectionState state) {
	return trackOverviewSelectionHasSelection(state) ? state.primary.voice : -1;
}

int trackOverviewSelectionPrimaryTrackIndex(
		const TrackOverviewSelectionState state) {
	return trackOverviewSelectionHasSelection(state) ?
		state.primary.trackIndex : -1;
}

int trackOverviewSelectionRangeStartTrackIndex(
		const TrackOverviewSelectionState state) {
	return trackOverviewSelectionHasSelection(state) ?
		state.rangeStartTrackIndex : -1;
}

int trackOverviewSelectionRangeEndTrackIndex(
		const TrackOverviewSelectionState state) {
	return trackOverviewSelectionHasSelection(state) ?
		state.rangeEndTrackIndex : -1;
}

int trackOverviewSelectionSelectedCount(
		const TrackOverviewSelectionState state) {
	return trackOverviewSelectionHasSelection(state) ?
		cast(int)state.selectedBlocks.length : 0;
}

bool trackOverviewSelectionContainsBlock(
		const TrackOverviewSelectionState state, int blockIndex,
		const TrackOverviewBlock block) {
	if(!trackOverviewSelectionHasSelection(state))
		return false;

	foreach(selection; state.selectedBlocks) {
		if(trackOverviewSelectionMatchesBlock(selection, blockIndex, block))
			return true;
	}
	return false;
}

private bool trackOverviewSelectionContainsSelection(
		const TrackOverviewSelectionState state,
		const TrackOverviewBlockSelection selection) {
	if(!trackOverviewSelectionHasSelection(state))
		return false;

	foreach(selected; state.selectedBlocks) {
		if(trackOverviewBlockSelectionsMatch(selected, selection))
			return true;
	}
	return false;
}

bool trackOverviewSelectionIsSameVoiceContiguous(
		const TrackOverviewSelectionState state) {
	if(!trackOverviewSelectionHasSelection(state))
		return false;

	int voice = state.selectedBlocks[0].voice;
	int minTrackIndex = state.selectedBlocks[0].trackIndex;
	int maxTrackIndex = minTrackIndex;
	foreach(idx, selection; state.selectedBlocks) {
		if(!selection.valid || selection.voice != voice)
			return false;
		if(selection.trackIndex < minTrackIndex)
			minTrackIndex = selection.trackIndex;
		if(selection.trackIndex > maxTrackIndex)
			maxTrackIndex = selection.trackIndex;

		foreach(previous; state.selectedBlocks[0 .. idx]) {
			if(previous.trackIndex == selection.trackIndex)
				return false;
		}
	}

	return maxTrackIndex - minTrackIndex + 1 ==
		cast(int)state.selectedBlocks.length;
}

bool collectTrackOverviewSelectedTrackEntries(
		ref TrackOverviewSelectionState state,
		const TrackOverviewBlockSelection singleSelection, int subtune,
		const(TrackOverviewLane)[] lanes, out Clip[] entries, out int voice,
		out int startTrackIndex, out int endTrackIndex) {
	entries = null;
	voice = -1;
	startTrackIndex = -1;
	endTrackIndex = -1;

	if(subtune < 0 || !singleSelection.valid ||
			!trackOverviewSelectionExists(singleSelection, lanes)) {
		clearTrackOverviewSelectionState(state);
		return false;
	}

	if(!state.active) {
		setTrackOverviewSingleSelectionState(state, subtune, singleSelection);
	}
	else if(state.subtune != subtune ||
			!trackOverviewBlockSelectionsMatch(state.primary,
				singleSelection)) {
		clearTrackOverviewSelectionState(state);
		return false;
	}

	if(!trackOverviewSelectionRangeIsValid(state, lanes)) {
		clearTrackOverviewSelectionState(state);
		return false;
	}

	foreach(selection; state.selectedBlocks) {
		Clip entry;
		entry.trans = selection.trackValue >> 8;
		entry.no = selection.trackValue & 0xff;
		entries ~= entry;
	}
	if(entries.length == 0) {
		clearTrackOverviewSelectionState(state);
		return false;
	}

	voice = state.voice;
	startTrackIndex = state.rangeStartTrackIndex;
	endTrackIndex = state.rangeEndTrackIndex;
	return true;
}

bool selectTrackOverviewRangeFromHit(
		ref TrackOverviewSelectionState state,
		ref TrackOverviewBlockSelection singleSelection, int subtune,
		const(TrackOverviewLane)[] lanes, const TrackOverviewHitTest hit) {
	TrackOverviewBlockSelection clickedSelection;
	if(!trackOverviewBlockSelectionFromHit(clickedSelection, hit)) {
		clearTrackOverviewBlockSelection(singleSelection);
		clearTrackOverviewSelectionState(state);
		return false;
	}

	if(!state.active || !state.anchor.valid ||
			state.subtune != subtune ||
			state.anchor.voice != clickedSelection.voice ||
			!trackOverviewSelectionExists(state.anchor, lanes)) {
		singleSelection = clickedSelection;
		setTrackOverviewSingleSelectionState(state, subtune,
			clickedSelection);
		return true;
	}

	if(!setTrackOverviewRangeSelectionState(state, subtune, lanes,
			state.anchor, clickedSelection)) {
		singleSelection = clickedSelection;
		setTrackOverviewSingleSelectionState(state, subtune,
			clickedSelection);
		return true;
	}

	singleSelection = state.primary;
	return true;
}

bool selectTrackOverviewRangeByTrackIndex(
		ref TrackOverviewSelectionState state,
		ref TrackOverviewBlockSelection singleSelection, int subtune,
		const(TrackOverviewLane)[] lanes, int voice, int startTrackIndex,
		int endTrackIndex) {
	return selectTrackOverviewRangeByTrackIndexWithPrimary(state,
		singleSelection, subtune, lanes, voice, startTrackIndex,
		endTrackIndex, startTrackIndex, endTrackIndex);
}

bool selectTrackOverviewRangeByTrackIndexWithPrimary(
		ref TrackOverviewSelectionState state,
		ref TrackOverviewBlockSelection singleSelection, int subtune,
		const(TrackOverviewLane)[] lanes, int voice, int startTrackIndex,
		int endTrackIndex, int anchorTrackIndex, int primaryTrackIndex) {
	if(subtune < 0 || voice < 0 || startTrackIndex < 0 ||
			endTrackIndex < startTrackIndex) {
		clearTrackOverviewBlockSelection(singleSelection);
		clearTrackOverviewSelectionState(state);
		return false;
	}

	foreach(lane; lanes) {
		if(lane.voice != voice)
			continue;

		TrackOverviewBlockSelection anchor;
		TrackOverviewBlockSelection primary;
		TrackOverviewBlockSelection[] selectedBlocks;
		if(anchorTrackIndex < startTrackIndex ||
				anchorTrackIndex > endTrackIndex)
			anchorTrackIndex = startTrackIndex;
		if(primaryTrackIndex < startTrackIndex ||
				primaryTrackIndex > endTrackIndex)
			primaryTrackIndex = endTrackIndex;

		foreach(blockIndex, block; lane.blocks) {
			if(!isSelectableTrackOverviewBlock(block))
				continue;
			if(block.trackIndex >= startTrackIndex &&
					block.trackIndex <= endTrackIndex) {
				TrackOverviewBlockSelection selection;
				setTrackOverviewBlockSelection(selection,
					cast(int)blockIndex, block);
				selectedBlocks ~= selection;
				if(block.trackIndex == anchorTrackIndex)
					anchor = selection;
				if(block.trackIndex == primaryTrackIndex)
					primary = selection;
			}
		}

		if(selectedBlocks.length !=
				cast(size_t)(endTrackIndex - startTrackIndex + 1) ||
				!anchor.valid || !primary.valid) {
			clearTrackOverviewBlockSelection(singleSelection);
			clearTrackOverviewSelectionState(state);
			return false;
		}

		state.active = true;
		state.subtune = subtune;
		state.primary = primary;
		state.anchor = anchor;
		state.voice = voice;
		state.rangeStartTrackIndex = startTrackIndex;
		state.rangeEndTrackIndex = endTrackIndex;
		state.selectedBlocks = selectedBlocks;
		singleSelection = state.primary;
		return true;
	}

	clearTrackOverviewBlockSelection(singleSelection);
	clearTrackOverviewSelectionState(state);
	return false;
}

bool selectTrackOverviewHitBlockPreservingRange(
		ref TrackOverviewSelectionState state,
		ref TrackOverviewBlockSelection singleSelection, int subtune,
		const(TrackOverviewLane)[] lanes, const TrackOverviewHitTest hit) {
	TrackOverviewBlockSelection clickedSelection;
	if(!trackOverviewBlockSelectionFromHit(clickedSelection, hit)) {
		clearTrackOverviewBlockSelection(singleSelection);
		clearTrackOverviewSelectionState(state);
		return false;
	}

	if(state.active && state.subtune == subtune &&
			trackOverviewSelectionRangeIsValid(state, lanes) &&
			trackOverviewSelectionContainsSelection(state, clickedSelection)) {
		state.primary = clickedSelection;
		singleSelection = clickedSelection;
		return true;
	}

	singleSelection = clickedSelection;
	setTrackOverviewSingleSelectionState(state, subtune, clickedSelection);
	return true;
}

void clearTrackOverviewBlockDrag(ref TrackOverviewBlockDragState drag) {
	drag = TrackOverviewBlockDragState();
}

void startTrackOverviewBlockDragCandidate(
		ref TrackOverviewBlockDragState drag,
		TrackOverviewBlockSelection selection,
		const TrackOverviewSelectionState selectionState, int mouseDownX,
		int mouseDownY) {
	clearTrackOverviewBlockDrag(drag);
	if(!selection.valid)
		return;

	drag.candidateActive = true;
	drag.source = selection;
	drag.mouseDownX = mouseDownX;
	drag.mouseDownY = mouseDownY;
	drag.lastMouseX = mouseDownX;
	drag.lastMouseY = mouseDownY;

	if(!trackOverviewSelectionHasSelection(selectionState) ||
			!trackOverviewSelectionIsSameVoiceContiguous(selectionState) ||
			trackOverviewSelectionSelectedCount(selectionState) <= 1 ||
			!trackOverviewSelectionContainsSelection(selectionState,
				selection))
		return;

	drag.rangeActive = true;
	drag.rangeStartTrackIndex = selectionState.rangeStartTrackIndex;
	drag.rangeEndTrackIndex = selectionState.rangeEndTrackIndex;
	drag.rangeAnchorTrackIndex = selectionState.anchor.trackIndex;
	drag.rangePrimaryTrackIndex = selectionState.primary.trackIndex;
	foreach(selected; selectionState.selectedBlocks) {
		drag.rangeTrackValues ~= selected.trackValue;
	}
}

bool updateTrackOverviewBlockDrag(ref TrackOverviewBlockDragState drag,
		int x, int y) {
	if(!drag.candidateActive || !drag.source.valid)
		return false;
	drag.lastMouseX = x;
	drag.lastMouseY = y;
	if(drag.active)
		return true;

	long dx = cast(long)x - drag.mouseDownX;
	long dy = cast(long)y - drag.mouseDownY;
	long threshold = TRACK_OVERVIEW_DRAG_START_THRESHOLD_PIXELS;
	if(dx * dx + dy * dy < threshold * threshold)
		return false;

	drag.active = true;
	return true;
}

int trackOverviewDragEdgeScrollDelta(
		const TrackOverviewBlockDragState drag, int fullWidth) {
	if(!drag.active || fullWidth <= 0)
		return 0;
	if(drag.lastMouseY < 0 || drag.lastMouseY >= trackOverviewTotalHeight())
		return 0;

	if(drag.lastMouseX < TRACK_OVERVIEW_DRAG_EDGE_SCROLL_ZONE_PIXELS)
		return -TRACK_OVERVIEW_DRAG_EDGE_SCROLL_STEP_PIXELS;
	if(drag.lastMouseX >= fullWidth -
			TRACK_OVERVIEW_DRAG_EDGE_SCROLL_ZONE_PIXELS)
		return TRACK_OVERVIEW_DRAG_EDGE_SCROLL_STEP_PIXELS;
	return 0;
}

bool updateTrackOverviewBlockDropTarget(ref TrackOverviewBlockDragState drag,
		const(TrackOverviewLane)[] lanes, int x, int y, int originX,
		int originY, int fullWidth, int scrollX, bool duplicateMode) {
	TrackOverviewDropTarget oldTarget = drag.dropTarget;
	drag.dropTarget = TrackOverviewDropTarget();
	if(!drag.active || !drag.source.valid)
		return oldTarget.valid;

	TrackOverviewHitTest hit = trackOverviewHitTest(lanes, x, y, originX,
		originY, fullWidth, scrollX);
	if(hit.region != TrackOverviewHitRegion.VoiceLane || hit.voice < 0)
		return oldTarget.valid;

	foreach(lane; lanes) {
		if(lane.voice != hit.voice)
			continue;

		if(hit.voice != drag.source.voice) {
			if(hit.blockIndex < 0 ||
					hit.blockIndex >= cast(int)lane.blocks.length ||
					!isSelectableTrackOverviewBlock(lane.blocks[hit.blockIndex]))
				return oldTarget.valid;
		}

		TrackOverviewDropTarget target = trackOverviewDropTargetForHit(
			drag.source, lane, hit, scrollX);
		if(!duplicateMode &&
				trackOverviewDropTargetIsOriginalPosition(drag, target))
			return oldTarget.valid;

		drag.dropTarget = target;
		return !trackOverviewDropTargetsMatch(oldTarget, drag.dropTarget);
	}

	return oldTarget.valid;
}

TrackOverviewCurrentEditorBlock trackOverviewCurrentEditorBlock(
		const TrackOverviewEditorCursor cursor) {
	TrackOverviewCurrentEditorBlock current;
	if(!cursor.valid || !cursor.position.valid)
		return current;

	current.valid = true;
	current.voice = cursor.position.voice;
	current.blockIndex = cursor.position.blockIndex;
	current.trackIndex = cursor.position.trackIndex;
	current.sequenceNumber = cursor.position.sequenceNumber;
	current.trackValue = cursor.position.trackValue;
	current.globalRow = cursor.globalRow;
	return current;
}

void setTrackOverviewEditorFocus(ref TrackOverviewFocusState focus) {
	focus = TrackOverviewFocusState();
}

void setTrackOverviewTimelineFocus(ref TrackOverviewFocusState focus) {
	focus = TrackOverviewFocusState();
	focus.kind = TrackOverviewFocusKind.Timeline;
}

void setTrackOverviewBlockFocus(ref TrackOverviewFocusState focus,
		const TrackOverviewBlockSelection selection) {
	if(!selection.valid) {
		setTrackOverviewEditorFocus(focus);
		return;
	}

	focus.kind = TrackOverviewFocusKind.Block;
	focus.voice = selection.voice;
	focus.blockIndex = selection.blockIndex;
	focus.trackIndex = selection.trackIndex;
	focus.sequenceNumber = selection.sequenceNumber;
	focus.trackValue = selection.trackValue;
}

void validateTrackOverviewFocus(ref TrackOverviewFocusState focus,
		const TrackOverviewBlockSelection selection) {
	if(focus.kind != TrackOverviewFocusKind.Block)
		return;
	if(!trackOverviewFocusMatchesSelection(focus, selection))
		setTrackOverviewEditorFocus(focus);
}

bool selectTrackOverviewHitBlock(ref TrackOverviewBlockSelection selection,
		const TrackOverviewHitTest hit) {
	if(!trackOverviewBlockSelectionFromHit(selection, hit)) {
		clearTrackOverviewBlockSelection(selection);
		return false;
	}

	return true;
}

bool selectAdjacentTrackOverviewBlock(ref TrackOverviewBlockSelection selection,
		const(TrackOverviewLane)[] lanes, int direction) {
	if(!selection.valid || direction == 0) {
		clearTrackOverviewBlockSelection(selection);
		return false;
	}

	foreach(lane; lanes) {
		if(lane.voice != selection.voice)
			continue;

		int currentBlockIndex = -1;
		foreach(blockIndex, block; lane.blocks) {
			if(isSelectableTrackOverviewBlock(block) &&
					trackOverviewSelectionMatchesBlock(selection,
						cast(int)blockIndex, block)) {
				currentBlockIndex = cast(int)blockIndex;
				break;
			}
		}

		if(currentBlockIndex < 0) {
			clearTrackOverviewBlockSelection(selection);
			return false;
		}

		int nextBlockIndex = currentBlockIndex;
		int step = direction < 0 ? -1 : 1;
		for(int idx = currentBlockIndex + step;
				idx >= 0 && idx < cast(int)lane.blocks.length;
				idx += step) {
			if(!isSelectableTrackOverviewBlock(lane.blocks[idx]))
				continue;
			nextBlockIndex = idx;
			break;
		}

		setTrackOverviewBlockSelection(selection, nextBlockIndex,
			lane.blocks[nextBlockIndex]);
		return true;
	}

	clearTrackOverviewBlockSelection(selection);
	return false;
}

bool selectTrackOverviewBlockAtTrackIndex(
		ref TrackOverviewBlockSelection selection,
		const(TrackOverviewLane)[] lanes, int voice, int trackIndex,
		ushort trackValue) {
	if(voice < 0 || trackIndex < 0) {
		clearTrackOverviewBlockSelection(selection);
		return false;
	}

	foreach(lane; lanes) {
		if(lane.voice != voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(!isSelectableTrackOverviewBlock(block))
				continue;
			if(block.trackIndex == trackIndex &&
					block.trackValue == trackValue) {
				setTrackOverviewBlockSelection(selection,
					cast(int)blockIndex, block);
				return true;
			}
		}

		clearTrackOverviewBlockSelection(selection);
		return false;
	}

	clearTrackOverviewBlockSelection(selection);
	return false;
}

bool selectTrackOverviewBlockNearTrackIndex(
		ref TrackOverviewBlockSelection selection,
		const(TrackOverviewLane)[] lanes, int voice, int trackIndex) {
	if(voice < 0 || trackIndex < 0) {
		clearTrackOverviewBlockSelection(selection);
		return false;
	}

	foreach(lane; lanes) {
		if(lane.voice != voice)
			continue;

		int previousBlockIndex = -1;
		foreach(blockIndex, block; lane.blocks) {
			if(!isSelectableTrackOverviewBlock(block))
				continue;
			if(block.trackIndex == trackIndex) {
				setTrackOverviewBlockSelection(selection,
					cast(int)blockIndex, block);
				return true;
			}
			if(block.trackIndex < trackIndex)
				previousBlockIndex = cast(int)blockIndex;
		}

		if(previousBlockIndex >= 0) {
			setTrackOverviewBlockSelection(selection, previousBlockIndex,
				lane.blocks[previousBlockIndex]);
			return true;
		}

		clearTrackOverviewBlockSelection(selection);
		return false;
	}

	clearTrackOverviewBlockSelection(selection);
	return false;
}

bool revealTrackOverviewBlockSelection(ref TrackOverviewScrollState state,
		const TrackOverviewBlockSelection selection,
		const(TrackOverviewLane)[] lanes, int visibleWidth) {
	if(!selection.valid || visibleWidth <= 0)
		return false;

	foreach(lane; lanes) {
		if(lane.voice != selection.voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(!isSelectableTrackOverviewBlock(block) ||
					!trackOverviewSelectionMatchesBlock(selection,
						cast(int)blockIndex, block))
				continue;

			int oldScrollX = state.scrollX;
			int contentWidth = trackOverviewContentWidth(lanes);
			state.scrollX = trackOverviewFollowRowScrollX(state.scrollX,
				contentWidth, visibleWidth, block.startRow);
			state.manualScrollActive = true;
			state.manualScrollEditorRow = block.startRow;
			return state.scrollX != oldScrollX;
		}
		return false;
	}

	return false;
}

bool validateTrackOverviewBlockSelection(
		ref TrackOverviewBlockSelection selection,
		const(TrackOverviewLane)[] lanes) {
	if(!selection.valid)
		return false;

	foreach(lane; lanes) {
		if(lane.voice != selection.voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(trackOverviewSelectionMatchesBlock(selection,
					cast(int)blockIndex, block))
				return true;
		}

		clearTrackOverviewBlockSelection(selection);
		return false;
	}

	clearTrackOverviewBlockSelection(selection);
	return false;
}

bool trackOverviewSelectionMatchesBlock(
		const TrackOverviewBlockSelection selection, int blockIndex,
		const TrackOverviewBlock block) {
	return selection.valid &&
		selection.voice == block.voice &&
		selection.blockIndex == blockIndex &&
		selection.trackIndex == block.trackIndex &&
		selection.sequenceNumber == block.sequenceNumber &&
		selection.trackValue == block.trackValue;
}

private bool trackOverviewSelectionExists(
		const TrackOverviewBlockSelection selection,
		const(TrackOverviewLane)[] lanes) {
	if(!selection.valid)
		return false;

	foreach(lane; lanes) {
		if(lane.voice != selection.voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(trackOverviewSelectionMatchesBlock(selection,
					cast(int)blockIndex, block))
				return true;
		}
		return false;
	}
	return false;
}

bool trackOverviewCurrentEditorBlockMatchesBlock(
		const TrackOverviewCurrentEditorBlock current, int blockIndex,
		const TrackOverviewBlock block) {
	return current.valid &&
		current.voice == block.voice &&
		current.blockIndex == blockIndex &&
		current.trackIndex == block.trackIndex &&
		current.sequenceNumber == block.sequenceNumber &&
		current.trackValue == block.trackValue;
}

private bool trackOverviewBlockSelectionsMatch(
		const TrackOverviewBlockSelection a,
		const TrackOverviewBlockSelection b) {
	return a.valid == b.valid &&
		a.voice == b.voice &&
		a.blockIndex == b.blockIndex &&
		a.trackIndex == b.trackIndex &&
		a.sequenceNumber == b.sequenceNumber &&
		a.trackValue == b.trackValue;
}

private bool trackOverviewBlockSelectionFromHit(
		out TrackOverviewBlockSelection selection,
		const TrackOverviewHitTest hit) {
	selection = TrackOverviewBlockSelection();
	if(hit.region != TrackOverviewHitRegion.VoiceLane ||
			hit.voice < 0 || hit.blockIndex < 0)
		return false;

	selection.valid = true;
	selection.voice = hit.voice;
	selection.blockIndex = hit.blockIndex;
	selection.trackIndex = hit.trackIndex;
	selection.sequenceNumber = hit.sequenceNumber;
	selection.trackValue = hit.trackValue;
	return true;
}

private bool setTrackOverviewRangeSelectionState(
		ref TrackOverviewSelectionState state, int subtune,
		const(TrackOverviewLane)[] lanes,
		const TrackOverviewBlockSelection anchor,
		const TrackOverviewBlockSelection primary) {
	if(subtune < 0 || !anchor.valid || !primary.valid ||
			anchor.voice != primary.voice)
		return false;

	foreach(lane; lanes) {
		if(lane.voice != anchor.voice)
			continue;

		int anchorBlockIndex = trackOverviewMatchingBlockIndex(lane, anchor);
		int primaryBlockIndex = trackOverviewMatchingBlockIndex(lane, primary);
		if(anchorBlockIndex < 0 || primaryBlockIndex < 0)
			return false;

		int startBlockIndex = anchorBlockIndex < primaryBlockIndex ?
			anchorBlockIndex : primaryBlockIndex;
		int endBlockIndex = anchorBlockIndex > primaryBlockIndex ?
			anchorBlockIndex : primaryBlockIndex;

		TrackOverviewBlockSelection[] selectedBlocks;
		foreach(blockIndex; startBlockIndex .. endBlockIndex + 1) {
			TrackOverviewBlock block = lane.blocks[blockIndex];
			if(!isSelectableTrackOverviewBlock(block))
				continue;

			TrackOverviewBlockSelection selection;
			setTrackOverviewBlockSelection(selection, blockIndex, block);
			selectedBlocks ~= selection;
		}
		if(selectedBlocks.length == 0)
			return false;

		state.active = true;
		state.subtune = subtune;
		state.primary = primary;
		state.anchor = anchor;
		state.voice = anchor.voice;
		state.rangeStartTrackIndex = selectedBlocks[0].trackIndex;
		state.rangeEndTrackIndex =
			selectedBlocks[$ - 1].trackIndex;
		state.selectedBlocks = selectedBlocks;
		return true;
	}

	return false;
}

private bool trackOverviewSelectionRangeIsValid(
		const TrackOverviewSelectionState state,
		const(TrackOverviewLane)[] lanes) {
	if(!trackOverviewSelectionHasSelection(state) ||
			!state.anchor.valid ||
			!state.primary.valid)
		return false;
	if(!trackOverviewSelectionIsSameVoiceContiguous(state))
		return false;
	if(!trackOverviewSelectionExists(state.anchor, lanes) ||
			!trackOverviewSelectionExists(state.primary, lanes))
		return false;

	foreach(selection; state.selectedBlocks) {
		if(!trackOverviewSelectionExists(selection, lanes))
			return false;
	}
	return true;
}

private int trackOverviewMatchingBlockIndex(const TrackOverviewLane lane,
		const TrackOverviewBlockSelection selection) {
	foreach(blockIndex, block; lane.blocks) {
		if(trackOverviewSelectionMatchesBlock(selection,
				cast(int)blockIndex, block))
			return cast(int)blockIndex;
	}
	return -1;
}

private bool trackOverviewFocusMatchesSelection(
		const TrackOverviewFocusState focus,
		const TrackOverviewBlockSelection selection) {
	return selection.valid &&
		focus.voice == selection.voice &&
		focus.blockIndex == selection.blockIndex &&
		focus.trackIndex == selection.trackIndex &&
		focus.sequenceNumber == selection.sequenceNumber &&
		focus.trackValue == selection.trackValue;
}

private void setTrackOverviewBlockSelection(
		ref TrackOverviewBlockSelection selection, int blockIndex,
		const TrackOverviewBlock block) {
	selection.valid = true;
	selection.voice = block.voice;
	selection.blockIndex = blockIndex;
	selection.trackIndex = block.trackIndex;
	selection.sequenceNumber = block.sequenceNumber;
	selection.trackValue = block.trackValue;
}

private bool isSelectableTrackOverviewBlock(const TrackOverviewBlock block) {
	return block.rowLength > 0;
}

private TrackOverviewDropTarget trackOverviewDropTargetForHit(
		const TrackOverviewBlockSelection source,
		const TrackOverviewLane lane, const TrackOverviewHitTest hit,
		int scrollX) {
	if(hit.localX < 0)
		return TrackOverviewDropTarget();

	long pointerPixelX = cast(long)hit.localX + scrollX;
	if(hit.blockIndex >= 0 && hit.blockIndex < cast(int)lane.blocks.length) {
		TrackOverviewBlock block = lane.blocks[hit.blockIndex];
		if(isSelectableTrackOverviewBlock(block)) {
			long blockX0 = trackOverviewRowsToPixels(block.startRow);
			long blockX1 = trackOverviewRowsToPixels(block.endRow);
			long midpoint = blockX0 + (blockX1 - blockX0) / 2;
			if(pointerPixelX < midpoint)
				return trackOverviewDropTarget(lane.voice, block.trackIndex,
					block.startRow);
			return trackOverviewDropTarget(lane.voice, block.trackIndex + 1,
				block.endRow);
		}
	}

	return nearestTrackOverviewDropTarget(lane.voice, lane, pointerPixelX);
}

private TrackOverviewDropTarget nearestTrackOverviewDropTarget(int voice,
		const TrackOverviewLane lane, long pointerPixelX) {
	TrackOverviewDropTarget bestTarget;
	bool found;
	long bestDistance;

	foreach(block; lane.blocks) {
		if(!isSelectableTrackOverviewBlock(block))
			continue;

		considerTrackOverviewDropBoundary(bestTarget, found, bestDistance,
			voice, block.trackIndex, block.startRow, pointerPixelX);
		considerTrackOverviewDropBoundary(bestTarget, found, bestDistance,
			voice, block.trackIndex + 1, block.endRow, pointerPixelX);
	}

	return found ? bestTarget : TrackOverviewDropTarget();
}

private void considerTrackOverviewDropBoundary(
		ref TrackOverviewDropTarget bestTarget, ref bool found,
		ref long bestDistance, int voice, int insertionTrackIndex,
		int insertionRow, long pointerPixelX) {
	long boundaryX = trackOverviewRowsToPixels(insertionRow);
	long distance = boundaryX - pointerPixelX;
	if(distance < 0)
		distance = -distance;

	if(found && distance >= bestDistance)
		return;

	bestTarget = trackOverviewDropTarget(voice, insertionTrackIndex,
		insertionRow);
	bestDistance = distance;
	found = true;
}

private TrackOverviewDropTarget trackOverviewDropTarget(int voice,
		int insertionTrackIndex, int insertionRow) {
	TrackOverviewDropTarget target;
	target.valid = insertionTrackIndex >= 0 && insertionRow >= 0;
	target.voice = voice;
	target.insertionTrackIndex = insertionTrackIndex;
	target.insertionRow = insertionRow;
	return target;
}

private bool trackOverviewDropTargetIsOriginalPosition(
		const TrackOverviewBlockDragState drag,
		const TrackOverviewDropTarget target) {
	if(!target.valid || !drag.source.valid || target.voice != drag.source.voice)
		return false;
	if(drag.rangeActive) {
		return target.insertionTrackIndex >= drag.rangeStartTrackIndex &&
			target.insertionTrackIndex <= drag.rangeEndTrackIndex + 1;
	}
	return target.insertionTrackIndex == drag.source.trackIndex ||
		target.insertionTrackIndex == drag.source.trackIndex + 1;
}

private bool trackOverviewDropTargetsMatch(
		const TrackOverviewDropTarget a, const TrackOverviewDropTarget b) {
	return a.valid == b.valid &&
		a.voice == b.voice &&
		a.insertionTrackIndex == b.insertionTrackIndex &&
		a.insertionRow == b.insertionRow;
}

TrackOverviewHitTest trackOverviewPlusHitTest(
		const(TrackOverviewLane)[] lanes,
		const TrackOverviewBlockSelection selection, int x, int y, int originX,
		int originY, int fullWidth, int scrollX) {
	TrackOverviewHitTest hit;
	hit.x = x;
	hit.y = y;
	if(!selection.valid)
		return hit;

	int relativeY = y - originY;
	if(relativeY < 0 || relativeY >= trackOverviewTotalHeight())
		return hit;

	int contentX = trackOverviewContentX(originX);
	int contentWidth = trackOverviewContentAreaWidth(fullWidth);
	if(contentWidth <= 0 || x < contentX || x >= contentX + contentWidth)
		return hit;

	long localX = cast(long)x - contentX;
	foreach(lane; lanes) {
		if(lane.voice != selection.voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(!trackOverviewSelectionMatchesBlock(selection,
					cast(int)blockIndex, block) ||
					!isSelectableTrackOverviewBlock(block))
				continue;

			long blockX0 = trackOverviewRowToLocalX(block.startRow, scrollX);
			long blockX1 = trackOverviewRowToLocalX(block.endRow, scrollX);
			auto rect = trackOverviewPlusRect(blockX0, blockX1,
				trackOverviewVoiceBlockY(0, selection.voice));
			if(!trackOverviewContainsPlusPoint(rect, localX, relativeY))
				return hit;

			hit.region = TrackOverviewHitRegion.Plus;
			hit.localX = cast(int)localX;
			hit.row = trackOverviewLocalXToRow(hit.localX, scrollX);
			hit.voice = selection.voice;
			hit.blockIndex = cast(int)blockIndex;
			hit.trackIndex = block.trackIndex;
			hit.sequenceNumber = block.sequenceNumber;
			hit.trackValue = block.trackValue;
			return hit;
		}
		return hit;
	}

	return hit;
}

TrackOverviewHitTest trackOverviewHitTest(
		const(TrackOverviewLane)[] lanes, int x, int y, int originX,
		int originY, int fullWidth, int scrollX) {
	TrackOverviewHitTest hit;
	hit.x = x;
	hit.y = y;

	int relativeY = y - originY;
	if(relativeY < 0 || relativeY >= trackOverviewTotalHeight())
		return hit;

	int contentX = trackOverviewContentX(originX);
	int contentWidth = trackOverviewContentAreaWidth(fullWidth);

	if(trackOverviewContainsY(relativeY, trackOverviewTimeRowY(0),
			trackOverviewTimeRowHeight())) {
		if(contentWidth <= 0 || fullWidth <= 0 ||
				x < originX || x >= originX + fullWidth)
			return hit;

		int overviewContentWidth = trackOverviewContentWidth(lanes);
		int row = trackOverviewTimelineXToRow(x, originX, fullWidth, scrollX,
			overviewContentWidth);
		if(row < 0)
			return hit;

		hit.localX = trackOverviewClampedContentLocalX(x, originX, fullWidth);
		hit.region = TrackOverviewHitRegion.TimeRow;
		hit.row = row;
		return hit;
	}

	if(contentWidth <= 0 || x < contentX || x >= contentX + contentWidth)
		return hit;

	hit.localX = x - contentX;

	foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
		if(!trackOverviewContainsY(relativeY,
				trackOverviewVoiceLaneY(0, cast(int)voice),
				trackOverviewVoiceLaneHeight()))
			continue;

		hit.voice = cast(int)voice;
		hit.row = trackOverviewLocalXToRow(hit.localX, scrollX);
		if(trackOverviewContainsY(relativeY,
				trackOverviewVoiceLoopIndicatorY(0, cast(int)voice),
				trackOverviewVoiceLoopIndicatorHeight())) {
			hit.region = TrackOverviewHitRegion.VoiceLoopLane;
			trackOverviewFindHitBlockAtLocalX(lanes, hit, scrollX);
			return hit;
		}

		if(!trackOverviewContainsY(relativeY,
				trackOverviewVoiceBlockY(0, cast(int)voice),
				trackOverviewVoiceBlockHeight()))
			return hit;

		hit.region = TrackOverviewHitRegion.VoiceLane;
		trackOverviewFindHitBlock(lanes, hit);
		return hit;
	}

	if(trackOverviewContainsY(relativeY, trackOverviewScrollbarY(0),
			trackOverviewScrollbarHeight())) {
		hit.region = TrackOverviewHitRegion.Scrollbar;
		return hit;
	}

	return hit;
}

bool trackOverviewLocalXInThumb(int localX,
		const TrackOverviewScrollbarThumb thumb) {
	return localX >= thumb.x && localX < thumb.x + thumb.width;
}

private bool trackOverviewContainsPlusPoint(T)(T rect, long x, int y) {
	return rect.width > 0 && rect.height > 0 &&
		x >= rect.x && x < rect.x + rect.width &&
		y >= rect.y && y < rect.y + rect.height;
}

TrackOverviewEditorCursor trackOverviewEditorCursor(
		const(TrackOverviewLane)[] lanes, int activeVoice, int trackIndex,
		int sequenceRowOffset) {
	TrackOverviewEditorCursor cursor;
	cursor.voice = activeVoice;

	TrackOverviewPosition position = trackOverviewPositionAtTrackRow(lanes,
		activeVoice, trackIndex, sequenceRowOffset);
	if(!position.valid)
		return cursor;

	cursor.valid = true;
	cursor.globalRow = position.localRow;
	cursor.position = position;
	return cursor;
}

TrackOverviewPosition trackOverviewPositionAtTrackRow(
		const(TrackOverviewLane)[] lanes, int activeVoice, int trackIndex,
		int sequenceRowOffset) {
	TrackOverviewPosition position;
	position.voice = activeVoice;

	if(activeVoice < 0 || trackIndex < 0 || sequenceRowOffset < 0)
		return position;

	foreach(lane; lanes) {
		if(lane.voice != activeVoice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(block.trackIndex != trackIndex)
				continue;
			if(block.rowLength <= 0 || sequenceRowOffset >= block.rowLength)
				return position;

			int localRow = block.startRow + sequenceRowOffset;
			position.valid = true;
			position.voice = activeVoice;
			position.globalRow = localRow;
			position.localRow = localRow;
			position.trackIndex = block.trackIndex;
			position.blockIndex = cast(int)blockIndex;
			position.sequenceNumber = block.sequenceNumber;
			position.trackValue = block.trackValue;
			position.sequenceRowOffset = sequenceRowOffset;
			return position;
		}
	}

	return position;
}

void startTrackOverviewPlaybackState(ref TrackOverviewPlaybackState state) {
	state.active = true;
}

void stopTrackOverviewPlaybackState(ref TrackOverviewPlaybackState state) {
	state.active = false;
}

void advanceTrackOverviewPlaybackState(ref TrackOverviewPlaybackState state,
		int rows) {
	// Playback display position is resolved from live fplayPos in
	// trackOverviewPlaybackCursor(), so loop/wrap jumps cannot leave a stale
	// accumulated overview row behind.
}

TrackOverviewPlaybackCursor trackOverviewPlaybackCursor(
		const(TrackOverviewLane)[] lanes,
		const TrackOverviewPlaybackState state,
		const int[TRACK_OVERVIEW_VOICE_LANES] trackIndexes,
		const int[TRACK_OVERVIEW_VOICE_LANES] sequenceRowOffsets) {
	TrackOverviewPlaybackCursor cursor;

	if(!state.active)
		return cursor;

	TrackOverviewPosition globalPosition = trackOverviewPositionAtTrackRow(lanes,
		0, trackIndexes[0], sequenceRowOffsets[0]);
	if(globalPosition.valid) {
		cursor.globalVisible = true;
		cursor.globalRow = globalPosition.localRow;
		cursor.valid = true;
	}

	foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
		TrackOverviewPosition position = trackOverviewPositionAtTrackRow(lanes,
			cast(int)voice, trackIndexes[voice], sequenceRowOffsets[voice]);
		cursor.voicePositions[voice] = position;
		if(position.valid)
			cursor.valid = true;
	}

	return cursor;
}

private bool trackOverviewContainsY(int y, int regionY, int height) {
	return height > 0 && y >= regionY && y < regionY + height;
}

private int trackOverviewFollowLeftMargin(int visibleWidth) {
	return trackOverviewConstrainedFollowMargin(
		TRACK_OVERVIEW_FOLLOW_LEFT_MARGIN, visibleWidth);
}

private int trackOverviewFollowRightMargin(int visibleWidth) {
	return trackOverviewConstrainedFollowMargin(
		TRACK_OVERVIEW_FOLLOW_RIGHT_MARGIN, visibleWidth);
}

private int trackOverviewConstrainedFollowMargin(int margin, int visibleWidth) {
	if(margin <= 0 || visibleWidth <= 2)
		return 0;
	int maxMargin = visibleWidth / 3;
	return margin < maxMargin ? margin : maxMargin;
}

private void trackOverviewFindHitBlock(const(TrackOverviewLane)[] lanes,
		ref TrackOverviewHitTest hit) {
	if(hit.voice < 0 || hit.row < 0)
		return;

	foreach(lane; lanes) {
		if(lane.voice != hit.voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(hit.row < block.startRow || hit.row >= block.endRow)
				continue;

			hit.blockIndex = cast(int)blockIndex;
			hit.trackIndex = block.trackIndex;
			hit.sequenceNumber = block.sequenceNumber;
			hit.trackValue = block.trackValue;
			return;
		}
		return;
	}
}

private void trackOverviewFindHitBlockAtLocalX(
		const(TrackOverviewLane)[] lanes, ref TrackOverviewHitTest hit,
		int scrollX) {
	if(hit.voice < 0 || hit.localX < 0)
		return;

	long pointerPixelX = cast(long)hit.localX + scrollX;
	foreach(lane; lanes) {
		if(lane.voice != hit.voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(!isSelectableTrackOverviewBlock(block))
				continue;

			long blockX0 = trackOverviewRowsToPixels(block.startRow);
			long blockX1 = trackOverviewRowsToPixels(block.endRow);
			if(pointerPixelX < blockX0 || pointerPixelX >= blockX1)
				continue;

			hit.blockIndex = cast(int)blockIndex;
			hit.trackIndex = block.trackIndex;
			hit.sequenceNumber = block.sequenceNumber;
			hit.trackValue = block.trackValue;
			return;
		}
		return;
	}
}

private int clampLongToInt(long value) {
	if(value < int.min)
		return int.min;
	if(value > int.max)
		return int.max;
	return cast(int)value;
}

private TrackOverviewPosition trackOverviewScrubSelfCheckPosition(int voice,
		int trackIndex, int sequenceNumber, int sequenceRowOffset,
		int trackValue) {
	TrackOverviewPosition position;
	position.valid = true;
	position.voice = voice;
	position.trackIndex = trackIndex;
	position.blockIndex = trackIndex;
	position.sequenceNumber = sequenceNumber;
	position.sequenceRowOffset = sequenceRowOffset;
	position.trackValue = cast(ushort)trackValue;
	return position;
}
