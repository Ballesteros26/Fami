/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.trackoverviewlayout;

enum TrackOverviewRegion {
	TimeRow,
	Voice1,
	Voice2,
	Voice3,
	Scrollbar
}

struct TrackOverviewPixelRect {
	long x;
	int y;
	int width;
	int height;
}

struct RightVisualPaneRect {
	int voice;
	int x;
	int y;
	int width;
	int height;
}

struct RightVisualPanelMouseHit {
	bool handled;
	int voice = -1;
}

enum TRACK_OVERVIEW_MARKER_LANE_HEIGHT = 22;
enum TRACK_OVERVIEW_TIME_ROW_BOTTOM_GAP_HEIGHT = 2;
enum TRACK_OVERVIEW_LOOP_INDICATOR_HEIGHT = 7;
enum TRACK_OVERVIEW_LOOP_INDICATOR_LINE_Y = 3;
enum TRACK_OVERVIEW_VOICE_BLOCK_HEIGHT = 18;
enum TRACK_OVERVIEW_VOICE_LANE_HEIGHT =
	TRACK_OVERVIEW_LOOP_INDICATOR_HEIGHT +
	TRACK_OVERVIEW_VOICE_BLOCK_HEIGHT;
enum TRACK_OVERVIEW_VOICE_LANE_SPACING = 1;
enum TRACK_OVERVIEW_VOICE_LANES = 3;
enum TRACK_OVERVIEW_SCROLLBAR_TOP_GAP_HEIGHT = 4;
enum TRACK_OVERVIEW_SCROLLBAR_HEIGHT = 6;
enum TRACK_OVERVIEW_BOTTOM_GAP_HEIGHT = 4;
enum TRACK_OVERVIEW_SIDE_PADDING = 15;
enum TRACK_OVERVIEW_ROW_WIDTH = 2;
enum TRACK_OVERVIEW_PLUS_SIZE = 9;
enum TRACK_OVERVIEW_PLUS_RIGHT_INSET = 2;
enum RIGHT_VISUAL_PANEL_X = 55;
enum RIGHT_VISUAL_PANEL_ROWS = 3;
enum RIGHT_VISUAL_PANE_COUNT = 3;

enum TRACK_OVERVIEW_VOICE_AREA_HEIGHT =
	TRACK_OVERVIEW_VOICE_LANES * TRACK_OVERVIEW_VOICE_LANE_HEIGHT +
	(TRACK_OVERVIEW_VOICE_LANES - 1) * TRACK_OVERVIEW_VOICE_LANE_SPACING;

enum TRACK_OVERVIEW_HEIGHT =
	TRACK_OVERVIEW_MARKER_LANE_HEIGHT +
	TRACK_OVERVIEW_TIME_ROW_BOTTOM_GAP_HEIGHT +
	TRACK_OVERVIEW_VOICE_AREA_HEIGHT +
	TRACK_OVERVIEW_SCROLLBAR_TOP_GAP_HEIGHT +
	TRACK_OVERVIEW_SCROLLBAR_HEIGHT +
	TRACK_OVERVIEW_BOTTOM_GAP_HEIGHT;

enum TRACK_OVERVIEW_GUI_START_Y = TRACK_OVERVIEW_HEIGHT;

int trackOverviewRegionY(TrackOverviewRegion region) {
	final switch(region) {
	case TrackOverviewRegion.TimeRow:
		return 0;
	case TrackOverviewRegion.Voice1:
		return TRACK_OVERVIEW_MARKER_LANE_HEIGHT +
			TRACK_OVERVIEW_TIME_ROW_BOTTOM_GAP_HEIGHT;
	case TrackOverviewRegion.Voice2:
		return TRACK_OVERVIEW_MARKER_LANE_HEIGHT +
			TRACK_OVERVIEW_TIME_ROW_BOTTOM_GAP_HEIGHT +
			TRACK_OVERVIEW_VOICE_LANE_HEIGHT +
			TRACK_OVERVIEW_VOICE_LANE_SPACING;
	case TrackOverviewRegion.Voice3:
		return TRACK_OVERVIEW_MARKER_LANE_HEIGHT +
			TRACK_OVERVIEW_TIME_ROW_BOTTOM_GAP_HEIGHT +
			2 * (TRACK_OVERVIEW_VOICE_LANE_HEIGHT +
				TRACK_OVERVIEW_VOICE_LANE_SPACING);
	case TrackOverviewRegion.Scrollbar:
		return TRACK_OVERVIEW_MARKER_LANE_HEIGHT +
			TRACK_OVERVIEW_TIME_ROW_BOTTOM_GAP_HEIGHT +
			TRACK_OVERVIEW_VOICE_AREA_HEIGHT +
			TRACK_OVERVIEW_SCROLLBAR_TOP_GAP_HEIGHT;
	}
}

int trackOverviewRegionY(int originY, TrackOverviewRegion region) {
	return originY + trackOverviewRegionY(region);
}

int trackOverviewRegionHeight(TrackOverviewRegion region) {
	final switch(region) {
	case TrackOverviewRegion.TimeRow:
		return TRACK_OVERVIEW_MARKER_LANE_HEIGHT;
	case TrackOverviewRegion.Voice1:
	case TrackOverviewRegion.Voice2:
	case TrackOverviewRegion.Voice3:
		return TRACK_OVERVIEW_VOICE_LANE_HEIGHT;
	case TrackOverviewRegion.Scrollbar:
		return TRACK_OVERVIEW_SCROLLBAR_HEIGHT;
	}
}

int trackOverviewTimeRowY(int originY = 0) {
	return trackOverviewRegionY(originY, TrackOverviewRegion.TimeRow);
}

int trackOverviewTimeRowHeight() {
	return trackOverviewRegionHeight(TrackOverviewRegion.TimeRow);
}

int trackOverviewTimeRowBottomGapY(int originY = 0) {
	return originY + TRACK_OVERVIEW_MARKER_LANE_HEIGHT;
}

int trackOverviewTimeRowBottomGapHeight() {
	return TRACK_OVERVIEW_TIME_ROW_BOTTOM_GAP_HEIGHT;
}

int trackOverviewVoiceLaneY(int originY, int voice) {
	return originY + TRACK_OVERVIEW_MARKER_LANE_HEIGHT +
		TRACK_OVERVIEW_TIME_ROW_BOTTOM_GAP_HEIGHT +
		voice * (TRACK_OVERVIEW_VOICE_LANE_HEIGHT +
			TRACK_OVERVIEW_VOICE_LANE_SPACING);
}

int trackOverviewVoiceLaneHeight() {
	return TRACK_OVERVIEW_VOICE_LANE_HEIGHT;
}

int trackOverviewVoiceLoopIndicatorY(int originY, int voice) {
	return trackOverviewVoiceLaneY(originY, voice);
}

int trackOverviewVoiceLoopIndicatorHeight() {
	return TRACK_OVERVIEW_LOOP_INDICATOR_HEIGHT;
}

int trackOverviewVoiceLoopIndicatorLineY() {
	return TRACK_OVERVIEW_LOOP_INDICATOR_LINE_Y;
}

int trackOverviewVoiceBlockY(int originY, int voice) {
	return trackOverviewVoiceLaneY(originY, voice) +
		TRACK_OVERVIEW_LOOP_INDICATOR_HEIGHT;
}

int trackOverviewVoiceBlockHeight() {
	return TRACK_OVERVIEW_VOICE_BLOCK_HEIGHT;
}

int trackOverviewScrollbarY(int originY = 0) {
	return trackOverviewRegionY(originY, TrackOverviewRegion.Scrollbar);
}

int trackOverviewScrollbarHeight() {
	return trackOverviewRegionHeight(TrackOverviewRegion.Scrollbar);
}

int trackOverviewLeftPadding() pure nothrow @safe {
	return TRACK_OVERVIEW_SIDE_PADDING;
}

int trackOverviewRightPadding() pure nothrow @safe {
	return TRACK_OVERVIEW_SIDE_PADDING;
}

int trackOverviewContentX(int originX = 0) {
	return originX + trackOverviewLeftPadding();
}

int trackOverviewContentAreaWidth(int fullWidth) {
	int width = fullWidth - trackOverviewLeftPadding() -
		trackOverviewRightPadding();
	return width > 0 ? width : 0;
}

int trackOverviewClampedContentLocalX(int x, int originX, int fullWidth) {
	int contentWidth = trackOverviewContentAreaWidth(fullWidth);
	if(contentWidth <= 0)
		return -1;

	long localX = cast(long)x - trackOverviewContentX(originX);
	if(localX < 0)
		return 0;
	if(localX >= contentWidth)
		return contentWidth - 1;
	return trackOverviewClampLongToInt(localX);
}

long trackOverviewRowsToPixels(int rows) {
	return cast(long)rows * TRACK_OVERVIEW_ROW_WIDTH;
}

long trackOverviewRowToLocalX(int row, int scrollX) {
	return trackOverviewRowsToPixels(row) - scrollX;
}

int trackOverviewLocalXToRow(int localX, int scrollX) {
	long pixelX = cast(long)localX + scrollX;
	if(pixelX < 0)
		return -1;
	return trackOverviewClampLongToInt(pixelX / TRACK_OVERVIEW_ROW_WIDTH);
}

int trackOverviewTimelineXToRow(int x, int originX, int fullWidth,
		int scrollX, int contentWidth) {
	int localX = trackOverviewClampedContentLocalX(x, originX, fullWidth);
	if(localX < 0 || contentWidth <= 0)
		return -1;

	long pixelX = cast(long)localX + scrollX;
	if(pixelX < 0)
		pixelX = 0;

	long maxPixelX = cast(long)contentWidth - 1;
	if(pixelX > maxPixelX)
		pixelX = maxPixelX;

	return trackOverviewClampLongToInt(pixelX / TRACK_OVERVIEW_ROW_WIDTH);
}

TrackOverviewPixelRect trackOverviewPlusRect(long blockX0, long blockX1,
		int blockY) {
	TrackOverviewPixelRect rect;
	long blockWidth = blockX1 - blockX0;
	if(blockWidth <= 0)
		return rect;

	int width = TRACK_OVERVIEW_PLUS_SIZE;
	if(blockWidth < width)
		width = trackOverviewClampLongToInt(blockWidth);
	int height = TRACK_OVERVIEW_PLUS_SIZE;
	if(height > trackOverviewVoiceBlockHeight())
		height = trackOverviewVoiceBlockHeight();

	long rectX = blockX1 - TRACK_OVERVIEW_PLUS_RIGHT_INSET - width;
	if(rectX < blockX0)
		rectX = blockX0;

	rect.x = rectX;
	rect.y = blockY + (trackOverviewVoiceBlockHeight() - height) / 2;
	rect.width = width;
	rect.height = height;
	return rect;
}

int trackOverviewTotalHeight() {
	return TRACK_OVERVIEW_HEIGHT;
}

int trackOverviewGuiStartY() pure nothrow @safe {
	return TRACK_OVERVIEW_GUI_START_Y;
}

RightVisualPaneRect rightVisualPaneRect(int voice, int screenWidth,
		int fontWidth, int fontHeight) pure nothrow @safe {
	RightVisualPaneRect pane;
	if(voice < 0 || voice >= RIGHT_VISUAL_PANE_COUNT ||
			screenWidth <= RIGHT_VISUAL_PANEL_X || fontWidth <= 0 ||
			fontHeight <= 0)
		return pane;

	int panelX = RIGHT_VISUAL_PANEL_X * fontWidth +
		trackOverviewLeftPadding();
	int fullPanelWidth = (screenWidth - RIGHT_VISUAL_PANEL_X) * fontWidth;
	int panelWidth = fullPanelWidth - trackOverviewLeftPadding() -
		trackOverviewRightPadding();
	if(panelWidth <= 0)
		return pane;

	int paneWidth = panelWidth / RIGHT_VISUAL_PANE_COUNT;
	int x = panelX + voice * paneWidth;
	int width = voice == RIGHT_VISUAL_PANE_COUNT - 1 ?
		panelX + panelWidth - x : paneWidth;
	return RightVisualPaneRect(voice, x, trackOverviewGuiStartY(), width,
		RIGHT_VISUAL_PANEL_ROWS * fontHeight);
}

RightVisualPanelMouseHit rightVisualPanelMouseHit(int x, int y,
		bool leftButton, bool oscillatorVisible, bool blockedByModal,
		int screenWidth, int fontWidth, int fontHeight)
		pure nothrow @safe {
	RightVisualPanelMouseHit hit;
	if(!leftButton || !oscillatorVisible || blockedByModal)
		return hit;

	foreach(voice; 0 .. RIGHT_VISUAL_PANE_COUNT) {
		auto pane = rightVisualPaneRect(voice, screenWidth, fontWidth,
			fontHeight);
		if(x >= pane.x && x < pane.x + pane.width &&
				y >= pane.y && y < pane.y + pane.height)
			return RightVisualPanelMouseHit(true, voice);
	}
	return hit;
}

private int trackOverviewClampLongToInt(long value) {
	if(value < int.min)
		return int.min;
	if(value > int.max)
		return int.max;
	return cast(int)value;
}
