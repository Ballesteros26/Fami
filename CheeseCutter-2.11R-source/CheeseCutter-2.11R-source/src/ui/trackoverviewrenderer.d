/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.trackoverviewrenderer;

import com.fb : Video;
import seq.trackoverview : TrackOverviewBlock, TrackOverviewLane,
	TrackOverviewPosition;
import ui.sequencecolors : SequenceColorLookup,
	buildSequenceColorLookupFromOverview, sequenceArgbColor,
	sequenceTintArgbColor, SEQUENCE_COLOR_NOTE_PREVIEW_BRIGHTNESS;
import ui.trackoverviewlayout;
import ui.trackoverviewnotes : TrackOverviewNotePreviewBlock,
	TrackOverviewNotePreviewLane, TrackOverviewNotePreviews;
import ui.trackoverviewstate : TrackOverviewCurrentEditorBlock,
	TrackOverviewDropTarget,
	TrackOverviewSelectionState,
	TrackOverviewScrollbarThumb, TrackOverviewViewport,
	trackOverviewCurrentEditorBlockMatchesBlock,
	trackOverviewSelectionContainsBlock,
	trackOverviewSelectionMatchesBlock;

enum TRACK_OVERVIEW_BACKGROUND_COLOR = 0;
enum TRACK_OVERVIEW_TIMELINE_COLOR = 11;
enum TRACK_OVERVIEW_TIMELINE_EDGE_COLOR = 12;
enum TRACK_OVERVIEW_SCROLLBAR_COLOR = 11;
enum TRACK_OVERVIEW_SCROLLBAR_THUMB_COLOR = 15;
enum TRACK_OVERVIEW_SEPARATOR_COLOR = 0;
enum TRACK_OVERVIEW_GLOBAL_MARKER_COLOR = 1;
enum TRACK_OVERVIEW_GLOBAL_MARKER_EDGE_COLOR = 0;
enum TRACK_OVERVIEW_PLAY_FROM_MARKER_COLOR = 15;
enum TRACK_OVERVIEW_PLAY_FROM_MARKER_EDGE_COLOR = 0;
enum TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_COLOR = 15;
enum TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_EDGE_COLOR = 0;
enum TRACK_OVERVIEW_VOICE_MARKER_COLOR = 1;
enum TRACK_OVERVIEW_EDITOR_MARKER_COLOR = 12;
// Logical framebuffer pixels; SDL scales the whole framebuffer uniformly.
enum TRACK_OVERVIEW_GLOBAL_MARKER_CENTER_WIDTH = 1;
enum TRACK_OVERVIEW_GLOBAL_MARKER_OUTLINE_WIDTH = 1;
enum TRACK_OVERVIEW_GLOBAL_MARKER_TOTAL_WIDTH =
	TRACK_OVERVIEW_GLOBAL_MARKER_CENTER_WIDTH +
	2 * TRACK_OVERVIEW_GLOBAL_MARKER_OUTLINE_WIDTH;
enum TRACK_OVERVIEW_PLAY_FROM_MARKER_CENTER_WIDTH = 1;
enum TRACK_OVERVIEW_PLAY_FROM_MARKER_OUTLINE_WIDTH = 1;
enum TRACK_OVERVIEW_PLAY_FROM_MARKER_TRIANGLE_WIDTH = 9;
enum TRACK_OVERVIEW_PLAY_FROM_MARKER_TRIANGLE_HEIGHT = 5;
enum TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_CENTER_WIDTH = 1;
enum TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_OUTLINE_WIDTH = 1;
enum TRACK_OVERVIEW_PLAY_FROM_SPLIT_TRIANGLE_WIDTH = 7;
enum TRACK_OVERVIEW_PLAY_FROM_SPLIT_TRIANGLE_HEIGHT = 4;
enum TRACK_OVERVIEW_PLAY_FROM_SPLIT_TRIANGLE_Y_STEP = 6;
enum TRACK_OVERVIEW_NOTE_PREVIEW_VERTICAL_PADDING = 1;
enum TRACK_OVERVIEW_NOTE_PREVIEW_MARK_WIDTH = 1;
enum TRACK_OVERVIEW_NOTE_PREVIEW_MARK_HEIGHT = 2;
enum TRACK_OVERVIEW_SELECTION_HIGHLIGHT_COLOR = 1;
enum TRACK_OVERVIEW_SELECTION_HIGHLIGHT_THICKNESS = 1;
enum TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_COLOR = 15;
enum TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_THICKNESS = 1;
enum TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_INSET = 1;
enum TRACK_OVERVIEW_MUTED_LANE_BRIGHTNESS = 15;
enum TRACK_OVERVIEW_MUTED_NOTE_PREVIEW_BRIGHTNESS = 25;
enum TRACK_OVERVIEW_MUTED_VOICE_MARKER_COLOR = 12;
enum TRACK_OVERVIEW_LOOP_INDICATOR_COLOR = 12;
enum TRACK_OVERVIEW_MUTED_LOOP_INDICATOR_COLOR = 11;
enum TRACK_OVERVIEW_LOOP_START_TICK_COLOR = 1;
enum TRACK_OVERVIEW_LOOP_START_TICK_WIDTH = 1;
enum TRACK_OVERVIEW_LOOP_START_TICK_HEIGHT = 3;
enum TRACK_OVERVIEW_SPEED_MARKER_COLOR = 7;
enum TRACK_OVERVIEW_SPEED_MARKER_SIZE = 3;
enum TRACK_OVERVIEW_HIGHLIGHT_GUIDE_COLOR = 11;
enum TRACK_OVERVIEW_TIMELINE_HIGHLIGHT_GUIDE_COLOR = 12;
enum TRACK_OVERVIEW_PLUS_BACKGROUND_COLOR = 0;
enum TRACK_OVERVIEW_PLUS_COLOR = 1;
enum TRACK_OVERVIEW_DROP_TARGET_COLOR = 1;
enum TRACK_OVERVIEW_DROP_TARGET_EDGE_COLOR = 0;
enum TRACK_OVERVIEW_DROP_TARGET_CENTER_WIDTH = 3;
enum TRACK_OVERVIEW_DROP_TARGET_OUTLINE_WIDTH = 1;
enum TRACK_OVERVIEW_DUPLICATE_DROP_TARGET_UPWARD_EXTENSION = 2;
enum TRACK_OVERVIEW_DUPLICATE_PLUS_LANE_TOP_OVERHANG = 1;

struct TrackOverviewVoiceMarker {
	bool visible;
	TrackOverviewPosition position;
}

struct TrackOverviewMarkers {
	bool globalVisible;
	int globalRow;
	TrackOverviewVoiceMarker[TRACK_OVERVIEW_VOICE_LANES] voiceMarkers;
	bool editorGlobalVisible;
	int editorGlobalRow;
	TrackOverviewVoiceMarker editorVoiceMarker;
	bool playFromVisible;
	int playFromGlobalRow;
	TrackOverviewVoiceMarker[TRACK_OVERVIEW_VOICE_LANES] playFromVoiceMarkers;
}

struct TrackOverviewVisualState {
	bool[TRACK_OVERVIEW_VOICE_LANES] mutedVoices;
	bool showSelectedBlockPlus;
	bool showDuplicateDropIndicator;
}

void drawTrackOverview(Video target, const(TrackOverviewLane)[] lanes,
		const TrackOverviewNotePreviews notePreviews,
		const TrackOverviewSelectionState selection,
		const TrackOverviewCurrentEditorBlock currentEditorBlock, int x, int y,
		TrackOverviewViewport viewport, const TrackOverviewMarkers markers,
		const TrackOverviewDropTarget dropTarget, int fullX, int fullWidth,
		const TrackOverviewVisualState visualState, const(int)[] speedMarkerRows,
		int highlight,
		int highlightOffset) {
	if(target is null || viewport.visibleWidth <= 0)
		return;

	int visibleWidth = viewport.visibleWidth;
	int scrollX = viewport.scrollX;

	drawTrackOverviewBackground(target, fullX, y, fullWidth);
	target.fillRect(fullX, trackOverviewTimeRowY(y), fullWidth,
		trackOverviewTimeRowHeight(), TRACK_OVERVIEW_TIMELINE_COLOR);
	target.drawHLine(fullX,
		trackOverviewTimeRowY(y) + trackOverviewTimeRowHeight() - 1,
		fullWidth, TRACK_OVERVIEW_TIMELINE_EDGE_COLOR);

	drawTrackOverviewScrollbar(target, x, y, viewport, highlight, highlightOffset);
	drawTrackOverviewHighlightGuides(target, x, y, visibleWidth, scrollX,
		highlight, highlightOffset);

	SequenceColorLookup colors = buildSequenceColorLookupFromOverview(lanes);
	foreach(laneIndex, lane; lanes) {
		int voice = lane.voice;
		if(voice < 0 || voice >= TRACK_OVERVIEW_VOICE_LANES) {
			if(laneIndex >= TRACK_OVERVIEW_VOICE_LANES)
				continue;
			voice = cast(int)laneIndex;
		}

		int laneY = trackOverviewVoiceLaneY(y, voice);
		int blockY = trackOverviewVoiceBlockY(y, voice);
		bool muted = isMutedVoice(visualState, voice);
		drawTrackOverviewLoopIndicator(target, lane, x, laneY, visibleWidth,
			scrollX, muted);
		int noteLaneIndex = findNotePreviewLaneIndex(notePreviews, voice);
		foreach(blockIndex, block; lane.blocks) {
			if(!isDrawableBlock(block))
				continue;
			if(!isVisibleBlock(block, visibleWidth, scrollX))
				continue;

			uint color = sequenceArgbColor(colors, block.sequenceNumber);
			uint blockColor = muted ?
				sequenceTintArgbColor(color, TRACK_OVERVIEW_MUTED_LANE_BRIGHTNESS) :
				color;
			drawTrackOverviewBlock(target, block, x, blockY, visibleWidth, scrollX,
				blockColor);

			if(noteLaneIndex >= 0) {
				const noteLane = notePreviews.lanes[noteLaneIndex];
				int noteBlockIndex = findNotePreviewBlockIndex(noteLane,
					cast(int)blockIndex);
				if(noteBlockIndex >= 0) {
					uint noteColor = sequenceTintArgbColor(color, muted ?
						TRACK_OVERVIEW_MUTED_NOTE_PREVIEW_BRIGHTNESS :
						SEQUENCE_COLOR_NOTE_PREVIEW_BRIGHTNESS);
					drawTrackOverviewBlockNotes(target, block,
						noteLane.blocks[noteBlockIndex], noteLane, x, blockY,
						visibleWidth, scrollX, noteColor);
				}
			}
		}
	}

	drawTrackOverviewCurrentEditorBlock(target, lanes, currentEditorBlock, x, y,
		visibleWidth, scrollX);
	drawTrackOverviewSelection(target, lanes, selection, x, y, visibleWidth,
		scrollX);
	if(visualState.showSelectedBlockPlus)
		drawTrackOverviewSelectionPlus(target, lanes, selection, x, y,
			visibleWidth, scrollX);
	drawTrackOverviewDropTarget(target, dropTarget, x, y, visibleWidth,
		scrollX, visualState.showDuplicateDropIndicator);
	drawTrackOverviewMarkers(target, markers, x, y, visibleWidth, scrollX,
		visualState);
	drawTrackOverviewSpeedMarkers(target, speedMarkerRows, x, y, visibleWidth,
		scrollX);
}

private void drawTrackOverviewBackground(Video target, int x, int y, int width) {
	if(target is null || width <= 0)
		return;
	target.fillRect(x, y, width, trackOverviewTotalHeight(),
		TRACK_OVERVIEW_BACKGROUND_COLOR);
}

private void drawTrackOverviewScrollbar(Video target, int x, int y,
		const TrackOverviewViewport viewport, int highlight, int highlightOffset) {
	int scrollbarY = trackOverviewScrollbarY(y);
	int scrollbarHeight = trackOverviewScrollbarHeight();
	target.fillRect(x, scrollbarY, viewport.visibleWidth, scrollbarHeight,
		TRACK_OVERVIEW_SCROLLBAR_COLOR);
	drawTrackOverviewGuideBand(target, x, scrollbarY, scrollbarHeight,
		viewport.visibleWidth, viewport.scrollX, highlight, highlightOffset,
		TRACK_OVERVIEW_TIMELINE_HIGHLIGHT_GUIDE_COLOR, 2);

	TrackOverviewScrollbarThumb thumb = viewport.scrollbarThumb;
	if(thumb.width <= 0)
		return;

	target.fillRect(x + thumb.x, scrollbarY, thumb.width, scrollbarHeight,
		TRACK_OVERVIEW_SCROLLBAR_THUMB_COLOR);
}

private void drawTrackOverviewHighlightGuides(Video target, int x, int y,
		int visibleWidth, int scrollX, int highlight, int highlightOffset) {
	int timelineY = trackOverviewTimeRowY(y);
	int timelineHeight = trackOverviewTimeRowHeight();
	int lanesY = trackOverviewTimeRowBottomGapY(y);
	int lanesHeight = trackOverviewTimeRowBottomGapHeight() +
		TRACK_OVERVIEW_VOICE_AREA_HEIGHT;
	drawTrackOverviewGuideBand(target, x, timelineY, timelineHeight,
		visibleWidth, scrollX, highlight, highlightOffset,
		TRACK_OVERVIEW_TIMELINE_HIGHLIGHT_GUIDE_COLOR, 3);
	drawTrackOverviewGuideBand(target, x, lanesY, lanesHeight,
		visibleWidth, scrollX, highlight, highlightOffset,
		TRACK_OVERVIEW_HIGHLIGHT_GUIDE_COLOR, 4);
}

private void drawTrackOverviewGuideBand(Video target, int x, int y, int height,
		int visibleWidth, int scrollX, int highlight, int highlightOffset,
		int color, int step) {
	if(target is null || visibleWidth <= 0 || height <= 0 || highlight <= 0)
		return;

	int firstRow = trackOverviewLocalXToRow(0, scrollX);
	int lastRow = trackOverviewLocalXToRow(visibleWidth - 1, scrollX);
	if(lastRow < firstRow)
		return;

	int firstGuide = firstRow + positiveModulo(highlightOffset - firstRow,
		highlight);
	long previousX = long.min;
	foreach(row; firstGuide .. lastRow + 1) {
		if((row - firstGuide) % highlight)
			continue;
		long markerX = trackOverviewRowToLocalX(row, scrollX);
		if(markerX == previousX)
			continue;
		previousX = markerX;
		drawDitheredGuideLine(target, markerX, x, y, height, visibleWidth,
			color, step);
	}
}

private int positiveModulo(int value, int modulus) {
	int result = value % modulus;
	return result < 0 ? result + modulus : result;
}

private void drawDitheredGuideLine(Video target, long markerX, int x, int y,
		int height, int visibleWidth, int color, int step) {
	if(step <= 1) {
		drawMarkerLine(target, markerX, x, y, height, visibleWidth, color);
		return;
	}
	foreach(offset; 0 .. height) {
		if(offset % step)
			continue;
		drawMarkerLine(target, markerX, x, y + offset, 1, visibleWidth, color);
	}
}

private void drawTrackOverviewLoopIndicator(Video target,
		const TrackOverviewLane lane, int x, int laneY, int visibleWidth,
		int scrollX, bool muted) {
	if(!lane.hasValidLoop || lane.loopLengthRows <= 0 ||
			lane.loopEndRow <= lane.wrapStartRow)
		return;

	int indicatorHeight = trackOverviewVoiceLoopIndicatorHeight();
	int lineOffset = trackOverviewVoiceLoopIndicatorLineY();
	if(indicatorHeight <= 0 || lineOffset < 0 || lineOffset >= indicatorHeight)
		return;

	long loopX0 = trackOverviewRowToLocalX(lane.wrapStartRow, scrollX);
	long loopX1 = trackOverviewRowToLocalX(lane.loopEndRow, scrollX);
	int color = muted ? TRACK_OVERVIEW_MUTED_LOOP_INDICATOR_COLOR :
		TRACK_OVERVIEW_LOOP_INDICATOR_COLOR;
	drawPaletteBand(target, x, laneY + lineOffset, visibleWidth, loopX0, loopX1,
		1, color);
	int tickY = laneY + lineOffset - TRACK_OVERVIEW_LOOP_START_TICK_HEIGHT / 2;
	drawPaletteBand(target, x, tickY, visibleWidth, loopX0,
		loopX0 + TRACK_OVERVIEW_LOOP_START_TICK_WIDTH,
		TRACK_OVERVIEW_LOOP_START_TICK_HEIGHT,
		TRACK_OVERVIEW_LOOP_START_TICK_COLOR);
}

private void drawTrackOverviewMarkers(Video target,
		const TrackOverviewMarkers markers, int x, int y, int visibleWidth,
		int scrollX, const TrackOverviewVisualState visualState) {
	if(markers.playFromVisible && markers.playFromGlobalRow >= 0) {
		long markerX = trackOverviewRowToLocalX(markers.playFromGlobalRow,
			scrollX);
		drawPlayFromMarker(target, markerX, x, y, visibleWidth);
	}

	foreach(marker; markers.playFromVoiceMarkers) {
		if(!marker.visible || !marker.position.valid)
			continue;
		int voice = marker.position.voice;
		if(voice < 0 || voice >= TRACK_OVERVIEW_VOICE_LANES)
			continue;

		long markerX = trackOverviewRowToLocalX(marker.position.localRow, scrollX);
		drawPlayFromSplitTimelineMarker(target, markerX, x, y, visibleWidth,
			voice);
		drawPlayFromVoiceMarker(target, markerX, x,
			trackOverviewVoiceBlockY(y, voice),
			trackOverviewVoiceBlockHeight(), visibleWidth);
	}

	if(markers.editorGlobalVisible && markers.editorGlobalRow >= 0) {
		long markerX = trackOverviewRowToLocalX(markers.editorGlobalRow, scrollX);
		drawEditorGlobalMarker(target, markerX, x, y, visibleWidth);
	}

	if(markers.editorVoiceMarker.visible &&
			markers.editorVoiceMarker.position.valid) {
		int voice = markers.editorVoiceMarker.position.voice;
		if(voice >= 0 && voice < TRACK_OVERVIEW_VOICE_LANES) {
			long markerX = trackOverviewRowToLocalX(
				markers.editorVoiceMarker.position.localRow, scrollX);
			drawMarkerLine(target, markerX, x,
				trackOverviewVoiceBlockY(y, voice),
				trackOverviewVoiceBlockHeight(), visibleWidth,
				voiceMarkerColor(visualState, voice,
					TRACK_OVERVIEW_EDITOR_MARKER_COLOR));
		}
	}

	foreach(marker; markers.voiceMarkers) {
		if(!marker.visible || !marker.position.valid)
			continue;
		int voice = marker.position.voice;
		if(voice < 0 || voice >= TRACK_OVERVIEW_VOICE_LANES)
			continue;

		long markerX = trackOverviewRowToLocalX(marker.position.localRow, scrollX);
		drawMarkerLine(target, markerX, x,
			trackOverviewVoiceBlockY(y, voice),
			trackOverviewVoiceBlockHeight(), visibleWidth,
			voiceMarkerColor(visualState, voice,
				TRACK_OVERVIEW_VOICE_MARKER_COLOR));
	}

	if(markers.globalVisible && markers.globalRow >= 0) {
		long markerX = trackOverviewRowToLocalX(markers.globalRow, scrollX);
		drawGlobalMarker(target, markerX, x, y, visibleWidth);
	}
}

private void drawTrackOverviewSpeedMarkers(Video target,
		const(int)[] speedMarkerRows, int x, int y, int visibleWidth,
		int scrollX) {
	if(target is null || speedMarkerRows.length == 0 || visibleWidth <= 0)
		return;

	int timelineY = trackOverviewTimeRowY(y);
	int timelineHeight = trackOverviewTimeRowHeight();
	if(timelineHeight < TRACK_OVERVIEW_SPEED_MARKER_SIZE)
		return;

	int markerY = timelineY + timelineHeight -
		TRACK_OVERVIEW_SPEED_MARKER_SIZE - 2;
	foreach(row; speedMarkerRows) {
		if(row < 0)
			continue;
		long markerX = trackOverviewRowToLocalX(row, scrollX) -
			TRACK_OVERVIEW_SPEED_MARKER_SIZE / 2;
		drawMarkerBand(target, markerX, TRACK_OVERVIEW_SPEED_MARKER_SIZE,
			x, markerY, TRACK_OVERVIEW_SPEED_MARKER_SIZE, visibleWidth,
			TRACK_OVERVIEW_SPEED_MARKER_COLOR);
	}
}

private void drawPlayFromSplitTimelineMarker(Video target, long markerX, int x,
		int y, int visibleWidth, int voice) {
	int markerY = trackOverviewTimeRowY(y);
	int markerHeight = trackOverviewTimeRowHeight();
	if(markerHeight <= 0)
		return;

	drawMarkerLine(target, markerX, x, markerY, markerHeight, visibleWidth,
		TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_COLOR);
	int triangleY = playFromSplitTriangleY(markerY, markerHeight, voice);
	drawPlayFromMarkerTriangle(target, markerX, x, triangleY + 1, visibleWidth,
		TRACK_OVERVIEW_PLAY_FROM_SPLIT_TRIANGLE_WIDTH,
		TRACK_OVERVIEW_PLAY_FROM_SPLIT_TRIANGLE_HEIGHT,
		TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_EDGE_COLOR);
	drawPlayFromMarkerTriangle(target, markerX, x, triangleY, visibleWidth,
		TRACK_OVERVIEW_PLAY_FROM_SPLIT_TRIANGLE_WIDTH,
		TRACK_OVERVIEW_PLAY_FROM_SPLIT_TRIANGLE_HEIGHT,
		TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_COLOR);
}

private int playFromSplitTriangleY(int markerY, int markerHeight, int voice) {
	int maxOffset = markerHeight - TRACK_OVERVIEW_PLAY_FROM_SPLIT_TRIANGLE_HEIGHT;
	if(maxOffset < 0)
		maxOffset = 0;

	int offset = voice * TRACK_OVERVIEW_PLAY_FROM_SPLIT_TRIANGLE_Y_STEP;
	if(offset > maxOffset)
		offset = maxOffset;
	return markerY + offset;
}

private void drawPlayFromMarker(Video target, long markerX, int x, int y,
		int visibleWidth) {
	int markerY = trackOverviewTimeRowY(y);
	int markerHeight = trackOverviewTimeRowHeight();
	if(markerHeight <= 0)
		return;

	long centerX = markerX - TRACK_OVERVIEW_PLAY_FROM_MARKER_CENTER_WIDTH / 2;
	long leftOutlineX = centerX - TRACK_OVERVIEW_PLAY_FROM_MARKER_OUTLINE_WIDTH;
	long rightOutlineX = centerX + TRACK_OVERVIEW_PLAY_FROM_MARKER_CENTER_WIDTH;

	drawMarkerBand(target, leftOutlineX,
		TRACK_OVERVIEW_PLAY_FROM_MARKER_OUTLINE_WIDTH, x, markerY, markerHeight,
		visibleWidth, TRACK_OVERVIEW_PLAY_FROM_MARKER_EDGE_COLOR);
	drawMarkerBand(target, centerX,
		TRACK_OVERVIEW_PLAY_FROM_MARKER_CENTER_WIDTH, x, markerY, markerHeight,
		visibleWidth, TRACK_OVERVIEW_PLAY_FROM_MARKER_COLOR);
	drawMarkerBand(target, rightOutlineX,
		TRACK_OVERVIEW_PLAY_FROM_MARKER_OUTLINE_WIDTH, x, markerY, markerHeight,
		visibleWidth, TRACK_OVERVIEW_PLAY_FROM_MARKER_EDGE_COLOR);
	drawPlayFromMarkerTriangle(target, markerX, x, markerY, visibleWidth,
		TRACK_OVERVIEW_PLAY_FROM_MARKER_TRIANGLE_WIDTH,
		TRACK_OVERVIEW_PLAY_FROM_MARKER_TRIANGLE_HEIGHT,
		TRACK_OVERVIEW_PLAY_FROM_MARKER_EDGE_COLOR);
}

private void drawPlayFromVoiceMarker(Video target, long markerX, int x, int y,
		int height, int visibleWidth) {
	if(height <= 0)
		return;

	long centerX = markerX -
		TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_CENTER_WIDTH / 2;
	long leftOutlineX = centerX -
		TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_OUTLINE_WIDTH;
	long rightOutlineX = centerX +
		TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_CENTER_WIDTH;

	drawMarkerBand(target, leftOutlineX,
		TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_OUTLINE_WIDTH, x, y, height,
		visibleWidth, TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_EDGE_COLOR);
	drawMarkerBand(target, centerX,
		TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_CENTER_WIDTH, x, y, height,
		visibleWidth, TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_COLOR);
	drawMarkerBand(target, rightOutlineX,
		TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_OUTLINE_WIDTH, x, y, height,
		visibleWidth, TRACK_OVERVIEW_PLAY_FROM_VOICE_MARKER_EDGE_COLOR);
}

private void drawPlayFromMarkerTriangle(Video target, long markerX, int x, int y,
		int visibleWidth, int triangleWidth, int triangleHeight, int color) {
	foreach(row; 0 .. triangleHeight) {
		int width = triangleWidth - row * 2;
		if(width <= 0)
			break;
		long triangleX = markerX - width / 2;
		drawMarkerBand(target, triangleX, width, x, y + row, 1, visibleWidth,
			color);
	}
}

private void drawEditorGlobalMarker(Video target, long markerX, int x, int y,
		int visibleWidth) {
	int markerY = trackOverviewTimeRowY(y);
	int markerHeight = trackOverviewTimeRowHeight();
	if(markerHeight <= 0)
		return;

	drawMarkerLine(target, markerX, x, markerY, markerHeight, visibleWidth,
		TRACK_OVERVIEW_EDITOR_MARKER_COLOR);
}

private void drawGlobalMarker(Video target, long markerX, int x, int y,
		int visibleWidth) {
	int markerY = trackOverviewTimeRowY(y);
	int markerHeight = trackOverviewTimeRowHeight();
	if(markerHeight <= 0)
		return;

	long centerX = markerX - TRACK_OVERVIEW_GLOBAL_MARKER_CENTER_WIDTH / 2;
	long leftOutlineX = centerX - TRACK_OVERVIEW_GLOBAL_MARKER_OUTLINE_WIDTH;
	long rightOutlineX = centerX + TRACK_OVERVIEW_GLOBAL_MARKER_CENTER_WIDTH;

	drawMarkerBand(target, leftOutlineX,
		TRACK_OVERVIEW_GLOBAL_MARKER_OUTLINE_WIDTH, x, markerY, markerHeight,
		visibleWidth, TRACK_OVERVIEW_GLOBAL_MARKER_EDGE_COLOR);
	drawMarkerBand(target, centerX,
		TRACK_OVERVIEW_GLOBAL_MARKER_CENTER_WIDTH, x, markerY, markerHeight,
		visibleWidth, TRACK_OVERVIEW_GLOBAL_MARKER_COLOR);
	drawMarkerBand(target, rightOutlineX,
		TRACK_OVERVIEW_GLOBAL_MARKER_OUTLINE_WIDTH, x, markerY, markerHeight,
		visibleWidth, TRACK_OVERVIEW_GLOBAL_MARKER_EDGE_COLOR);
}

private void drawTrackOverviewBlock(Video target, const TrackOverviewBlock block,
		int x, int y, int visibleWidth, int scrollX, uint color) {
	if(!isDrawableBlock(block))
		return;

	long blockX0 = trackOverviewRowToLocalX(block.startRow, scrollX);
	long blockX1 = blockX0 + trackOverviewRowsToPixels(block.rowLength);

	if(blockX1 <= 0 || blockX0 >= visibleWidth)
		return;

	long drawX0 = blockX0;
	long drawX1 = blockX1;
	if(drawX0 < 0)
		drawX0 = 0;
	if(drawX1 > visibleWidth)
		drawX1 = visibleWidth;
	if(drawX0 >= drawX1)
		return;

	target.fillRectRaw(clampToInt(cast(long)x + drawX0), y,
		cast(int)(drawX1 - drawX0), trackOverviewVoiceBlockHeight(), color);

	long separatorX = blockX1 - 1;
	if(separatorX >= 0 && separatorX < visibleWidth) {
		target.drawVLine(clampToInt(cast(long)x + separatorX), y,
			trackOverviewVoiceBlockHeight(), TRACK_OVERVIEW_SEPARATOR_COLOR);
	}
}

private void drawTrackOverviewBlockNotes(Video target,
		const TrackOverviewBlock block,
		const TrackOverviewNotePreviewBlock noteBlock,
		const TrackOverviewNotePreviewLane noteLane, int x, int y,
		int visibleWidth, int scrollX, uint color) {
	if(!noteLane.hasPitchRange || noteBlock.notes.length == 0)
		return;

	foreach(note; noteBlock.notes) {
		if(note.rowOffset < 0 || note.rowOffset >= block.rowLength)
			continue;

		long markerX = trackOverviewRowToLocalX(
			block.startRow + note.rowOffset, scrollX);
		int markerY = trackOverviewNotePreviewY(noteLane, note.pitch, y);
		drawRawNotePreviewMark(target, markerX, x, markerY, visibleWidth,
			color);
	}
}

private void drawTrackOverviewSelection(Video target,
		const(TrackOverviewLane)[] lanes,
		const TrackOverviewSelectionState selection, int x, int y,
		int visibleWidth, int scrollX) {
	if(!selection.active || visibleWidth <= 0)
		return;

	foreach(laneIndex, lane; lanes) {
		int voice = lane.voice;
		if(voice < 0 || voice >= TRACK_OVERVIEW_VOICE_LANES) {
			if(laneIndex >= TRACK_OVERVIEW_VOICE_LANES)
				continue;
			voice = cast(int)laneIndex;
		}
		if(voice != selection.voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(!trackOverviewSelectionContainsBlock(selection,
					cast(int)blockIndex, block))
				continue;

			drawTrackOverviewSelectionOutline(target, block, x,
				trackOverviewVoiceBlockY(y, voice), visibleWidth, scrollX);
		}
		return;
	}
}

private void drawTrackOverviewCurrentEditorBlock(Video target,
		const(TrackOverviewLane)[] lanes,
		const TrackOverviewCurrentEditorBlock currentEditorBlock, int x, int y,
		int visibleWidth, int scrollX) {
	if(!currentEditorBlock.valid || visibleWidth <= 0)
		return;

	foreach(laneIndex, lane; lanes) {
		int voice = lane.voice;
		if(voice < 0 || voice >= TRACK_OVERVIEW_VOICE_LANES) {
			if(laneIndex >= TRACK_OVERVIEW_VOICE_LANES)
				continue;
			voice = cast(int)laneIndex;
		}
		if(voice != currentEditorBlock.voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(!trackOverviewCurrentEditorBlockMatchesBlock(
					currentEditorBlock, cast(int)blockIndex, block))
				continue;

			drawTrackOverviewCurrentEditorBlockOutline(target, block, x,
				trackOverviewVoiceBlockY(y, voice), visibleWidth, scrollX);
			return;
		}
		return;
	}
}

private void drawTrackOverviewCurrentEditorBlockOutline(Video target,
		const TrackOverviewBlock block, int x, int y, int visibleWidth,
		int scrollX) {
	if(!isDrawableBlock(block) ||
			TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_THICKNESS <= 0)
		return;

	long rawBlockX0 = trackOverviewRowToLocalX(block.startRow, scrollX);
	long rawBlockX1 = trackOverviewRowToLocalX(block.endRow, scrollX);
	long blockX0 = rawBlockX0 + TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_INSET;
	long blockX1 = rawBlockX1 - TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_INSET;
	if(blockX1 <= blockX0) {
		blockX0 = rawBlockX0;
		blockX1 = rawBlockX1;
	}
	int insetY = TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_INSET;
	int height = trackOverviewVoiceBlockHeight() -
		2 * TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_INSET;
	if(blockX1 <= blockX0 || height <= 0)
		return;
	if(blockX1 <= 0 || blockX0 >= visibleWidth)
		return;

	int thickness = TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_THICKNESS;
	int y0 = y + insetY;
	int y1 = y0 + height - thickness;
	drawHorizontalEditorBlockBand(target, x, y0, visibleWidth, blockX0,
		blockX1, thickness);
	drawHorizontalEditorBlockBand(target, x, y1, visibleWidth, blockX0,
		blockX1, thickness);
	drawVerticalEditorBlockBand(target, x, y0, visibleWidth, blockX0, height,
		thickness);
	drawVerticalEditorBlockBand(target, x, y0, visibleWidth,
		blockX1 - thickness, height, thickness);
}

private void drawTrackOverviewSelectionOutline(Video target,
		const TrackOverviewBlock block, int x, int y, int visibleWidth,
		int scrollX) {
	if(!isDrawableBlock(block) ||
			TRACK_OVERVIEW_SELECTION_HIGHLIGHT_THICKNESS <= 0)
		return;

	long blockX0 = trackOverviewRowToLocalX(block.startRow, scrollX);
	long blockX1 = blockX0 + trackOverviewRowsToPixels(block.rowLength);
	if(blockX1 <= 0 || blockX0 >= visibleWidth)
		return;

	int thickness = TRACK_OVERVIEW_SELECTION_HIGHLIGHT_THICKNESS;
	int height = trackOverviewVoiceBlockHeight();
	drawHorizontalSelectionBand(target, x, y, visibleWidth, blockX0, blockX1,
		thickness);
	drawHorizontalSelectionBand(target, x, y + height - thickness, visibleWidth,
		blockX0, blockX1, thickness);
	drawVerticalSelectionBand(target, x, y, visibleWidth, blockX0, height,
		thickness);
	drawVerticalSelectionBand(target, x, y, visibleWidth, blockX1 - thickness,
		height, thickness);
}

private void drawTrackOverviewSelectionPlus(Video target,
		const(TrackOverviewLane)[] lanes,
		const TrackOverviewSelectionState selection, int x, int y,
		int visibleWidth, int scrollX) {
	if(!selection.active || !selection.primary.valid || visibleWidth <= 0)
		return;

	foreach(laneIndex, lane; lanes) {
		int voice = lane.voice;
		if(voice < 0 || voice >= TRACK_OVERVIEW_VOICE_LANES) {
			if(laneIndex >= TRACK_OVERVIEW_VOICE_LANES)
				continue;
			voice = cast(int)laneIndex;
		}
		if(voice != selection.primary.voice)
			continue;

		foreach(blockIndex, block; lane.blocks) {
			if(!trackOverviewSelectionMatchesBlock(selection.primary,
					cast(int)blockIndex, block))
				continue;

			drawTrackOverviewPlus(target, block, x,
				trackOverviewVoiceBlockY(y, selection.primary.voice),
				visibleWidth, scrollX);
			return;
		}
		return;
	}
}

private void drawTrackOverviewPlus(Video target, const TrackOverviewBlock block,
		int x, int y, int visibleWidth, int scrollX) {
	if(!isDrawableBlock(block))
		return;

	long blockX0 = trackOverviewRowToLocalX(block.startRow, scrollX);
	long blockX1 = trackOverviewRowToLocalX(block.endRow, scrollX);
	auto rect = trackOverviewPlusRect(blockX0, blockX1, y);
	drawTrackOverviewPlusGlyph(target, x, visibleWidth, rect);
}

private void drawTrackOverviewPlusGlyph(Video target, int x, int visibleWidth,
		const TrackOverviewPixelRect rect) {
	if(rect.width < 3 || rect.height < 3)
		return;
	if(rect.x + rect.width <= 0 || rect.x >= visibleWidth)
		return;

	drawPaletteBand(target, x, rect.y, visibleWidth, rect.x,
		rect.x + rect.width, rect.height, TRACK_OVERVIEW_PLUS_BACKGROUND_COLOR);

	long horizontalX0 = rect.x + 2;
	long horizontalX1 = rect.x + rect.width - 2;
	if(horizontalX1 <= horizontalX0) {
		horizontalX0 = rect.x;
		horizontalX1 = rect.x + rect.width;
	}
	int centerY = rect.y + rect.height / 2;
	drawPaletteBand(target, x, centerY, visibleWidth, horizontalX0,
		horizontalX1, 1, TRACK_OVERVIEW_PLUS_COLOR);

	long centerX = rect.x + rect.width / 2;
	int verticalY = rect.y + 2;
	int verticalHeight = rect.height - 4;
	if(verticalHeight <= 0) {
		verticalY = rect.y;
		verticalHeight = rect.height;
	}
	drawPaletteBand(target, x, verticalY, visibleWidth, centerX, centerX + 1,
		verticalHeight, TRACK_OVERVIEW_PLUS_COLOR);
}

private void drawTrackOverviewDropTarget(Video target,
		const TrackOverviewDropTarget dropTarget, int x, int y,
		int visibleWidth, int scrollX, bool duplicateIndicator) {
	if(!dropTarget.valid ||
			dropTarget.voice < 0 ||
			dropTarget.voice >= TRACK_OVERVIEW_VOICE_LANES)
		return;

	long markerX = trackOverviewRowToLocalX(dropTarget.insertionRow, scrollX);
	long centerX = markerX - TRACK_OVERVIEW_DROP_TARGET_CENTER_WIDTH / 2;
	long leftOutlineX = centerX - TRACK_OVERVIEW_DROP_TARGET_OUTLINE_WIDTH;
	long rightOutlineX = centerX + TRACK_OVERVIEW_DROP_TARGET_CENTER_WIDTH;
	int blockY = trackOverviewVoiceBlockY(y, dropTarget.voice);
	int markerY = blockY;
	int height = trackOverviewVoiceBlockHeight();
	if(duplicateIndicator) {
		markerY -= TRACK_OVERVIEW_DUPLICATE_DROP_TARGET_UPWARD_EXTENSION;
		height += TRACK_OVERVIEW_DUPLICATE_DROP_TARGET_UPWARD_EXTENSION;
	}
	drawMarkerBand(target, leftOutlineX,
		TRACK_OVERVIEW_DROP_TARGET_OUTLINE_WIDTH, x, markerY, height,
		visibleWidth, TRACK_OVERVIEW_DROP_TARGET_EDGE_COLOR);
	drawMarkerBand(target, centerX,
		TRACK_OVERVIEW_DROP_TARGET_CENTER_WIDTH, x, markerY, height, visibleWidth,
		TRACK_OVERVIEW_DROP_TARGET_COLOR);
	drawMarkerBand(target, rightOutlineX,
		TRACK_OVERVIEW_DROP_TARGET_OUTLINE_WIDTH, x, markerY, height,
		visibleWidth, TRACK_OVERVIEW_DROP_TARGET_EDGE_COLOR);

	if(duplicateIndicator) {
		TrackOverviewPixelRect plusRect;
		plusRect.x = markerX - TRACK_OVERVIEW_PLUS_SIZE / 2;
		plusRect.y = trackOverviewVoiceLoopIndicatorY(y, dropTarget.voice) -
			TRACK_OVERVIEW_DUPLICATE_PLUS_LANE_TOP_OVERHANG;
		plusRect.width = TRACK_OVERVIEW_PLUS_SIZE;
		plusRect.height = TRACK_OVERVIEW_PLUS_SIZE;
		drawTrackOverviewPlusGlyph(target, x, visibleWidth, plusRect);
	}
}

private void drawHorizontalEditorBlockBand(Video target, int x, int y,
		int visibleWidth, long blockX0, long blockX1, int thickness) {
	drawPaletteBand(target, x, y, visibleWidth, blockX0, blockX1, thickness,
		TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_COLOR);
}

private void drawVerticalEditorBlockBand(Video target, int x, int y,
		int visibleWidth, long bandX, int height, int thickness) {
	drawPaletteBand(target, x, y, visibleWidth, bandX, bandX + thickness,
		height, TRACK_OVERVIEW_CURRENT_EDITOR_BLOCK_COLOR);
}

private void drawHorizontalSelectionBand(Video target, int x, int y,
		int visibleWidth, long blockX0, long blockX1, int thickness) {
	drawPaletteBand(target, x, y, visibleWidth, blockX0, blockX1, thickness,
		TRACK_OVERVIEW_SELECTION_HIGHLIGHT_COLOR);
}

private void drawVerticalSelectionBand(Video target, int x, int y,
		int visibleWidth, long bandX, int height, int thickness) {
	drawPaletteBand(target, x, y, visibleWidth, bandX, bandX + thickness,
		height, TRACK_OVERVIEW_SELECTION_HIGHLIGHT_COLOR);
}

private void drawPaletteBand(Video target, int x, int y, int visibleWidth,
		long bandX0, long bandX1, int height, int color) {
	if(height <= 0)
		return;

	long drawX0 = bandX0;
	long drawX1 = bandX1;
	if(drawX0 < 0)
		drawX0 = 0;
	if(drawX1 > visibleWidth)
		drawX1 = visibleWidth;
	if(drawX0 >= drawX1)
		return;

	target.fillRect(clampToInt(cast(long)x + drawX0), y,
		cast(int)(drawX1 - drawX0), height, color);
}

private int trackOverviewNotePreviewY(
		const TrackOverviewNotePreviewLane noteLane, int pitch, int blockY) {
	int laneHeight = trackOverviewVoiceBlockHeight();
	int padding = TRACK_OVERVIEW_NOTE_PREVIEW_VERTICAL_PADDING;
	int drawableHeight = laneHeight - 2 * padding;
	if(drawableHeight <= 0)
		return blockY;

	int markHeight = TRACK_OVERVIEW_NOTE_PREVIEW_MARK_HEIGHT;
	if(markHeight > drawableHeight)
		markHeight = drawableHeight;
	int usableHeight = drawableHeight - markHeight;
	if(usableHeight < 0)
		usableHeight = 0;

	if(noteLane.minPitch == noteLane.maxPitch)
		return blockY + (laneHeight - markHeight) / 2;

	int pitchSpan = noteLane.maxPitch - noteLane.minPitch;
	if(pitch < noteLane.minPitch)
		pitch = noteLane.minPitch;
	else if(pitch > noteLane.maxPitch)
		pitch = noteLane.maxPitch;

	int offsetFromTop = cast(int)(cast(long)(noteLane.maxPitch - pitch) *
		usableHeight / pitchSpan);
	return blockY + padding + offsetFromTop;
}

private void drawRawNotePreviewMark(Video target, long markerX, int x, int y,
		int visibleWidth, uint color) {
	if(TRACK_OVERVIEW_NOTE_PREVIEW_MARK_WIDTH <= 0 ||
			TRACK_OVERVIEW_NOTE_PREVIEW_MARK_HEIGHT <= 0 ||
			visibleWidth <= 0)
		return;

	long x0 = markerX;
	long x1 = markerX + TRACK_OVERVIEW_NOTE_PREVIEW_MARK_WIDTH;
	if(x1 <= 0 || x0 >= visibleWidth)
		return;
	if(x0 < 0)
		x0 = 0;
	if(x1 > visibleWidth)
		x1 = visibleWidth;
	if(x0 >= x1)
		return;

	target.fillRectRaw(clampToInt(cast(long)x + x0), y,
		cast(int)(x1 - x0), TRACK_OVERVIEW_NOTE_PREVIEW_MARK_HEIGHT, color);
}

private void drawMarkerLine(Video target, long markerX, int x, int y,
		int height, int visibleWidth, int color) {
	drawMarkerBand(target, markerX, 1, x, y, height, visibleWidth, color);
}

private void drawMarkerBand(Video target, long markerX, int markerWidth,
		int x, int y, int height, int visibleWidth, int color) {
	if(markerWidth <= 0 || height <= 0 || visibleWidth <= 0)
		return;

	long x0 = markerX;
	long x1 = markerX + markerWidth;
	if(x1 <= 0 || x0 >= visibleWidth)
		return;
	if(x0 < 0)
		x0 = 0;
	if(x1 > visibleWidth)
		x1 = visibleWidth;
	if(x0 >= x1)
		return;

	target.fillRect(clampToInt(cast(long)x + x0), y, cast(int)(x1 - x0),
		height, color);
}

private bool isDrawableBlock(const TrackOverviewBlock block) {
	return block.rowLength > 0;
}

private bool isVisibleBlock(const TrackOverviewBlock block, int visibleWidth,
		int scrollX) {
	long blockX0 = trackOverviewRowToLocalX(block.startRow, scrollX);
	long blockX1 = blockX0 + trackOverviewRowsToPixels(block.rowLength);
	return blockX1 > 0 && blockX0 < visibleWidth;
}

private bool isMutedVoice(const TrackOverviewVisualState visualState,
		int voice) {
	return voice >= 0 && voice < TRACK_OVERVIEW_VOICE_LANES &&
		visualState.mutedVoices[voice];
}

private int voiceMarkerColor(const TrackOverviewVisualState visualState,
		int voice, int color) {
	return isMutedVoice(visualState, voice) ?
		TRACK_OVERVIEW_MUTED_VOICE_MARKER_COLOR : color;
}

private int findNotePreviewLaneIndex(
		const TrackOverviewNotePreviews notePreviews, int voice) {
	foreach(index, lane; notePreviews.lanes) {
		if(lane.voice == voice)
			return cast(int)index;
	}
	return -1;
}

private int findNotePreviewBlockIndex(
		const TrackOverviewNotePreviewLane lane, int blockIndex) {
	foreach(index, block; lane.blocks) {
		if(block.blockIndex == blockIndex)
			return cast(int)index;
	}
	return -1;
}

private int clampToInt(long value) {
	if(value < int.min)
		return int.min;
	if(value > int.max)
		return int.max;
	return cast(int)value;
}
