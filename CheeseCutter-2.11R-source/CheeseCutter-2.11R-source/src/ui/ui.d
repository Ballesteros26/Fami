/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.ui;
import core.exception : RangeError;
import derelict.sdl2.sdl;
import std.conv;
import std.path : baseName, dirName;
import main;
import ct.base;
import ct.exporter;
import com.session;
import ct.purge;
	import ui.help;
	import ui.bottomcontrols : BottomControlInteraction, BottomControlRole,
		bottomControlInteractionAtCell, bottomControlLayout,
		bottomControlThemeIndex;
	import ui.input;
import audio.player;
import audio.seekmanager : TimelineSeekInputKind, TimelineSeekOptions,
	TimelineSeekResult, TimelineSeekStatus, TimelineSeekTarget,
	timelineSeekManager;
import ui.tables;
import ui.dialogs;
import seq.fplay;
import seq.trackoverview : TrackOverviewLane, TrackOverviewPosition,
	buildTrackOverview;
import com.fb;
import com.util;
import seq.sequencer;
import ui.trackoverviewlayout : trackOverviewContentAreaWidth,
	trackOverviewContentX, trackOverviewTimelineXToRow,
	trackOverviewGuiStartY, trackOverviewTotalHeight,
	trackOverviewLeftPadding, trackOverviewRightPadding,
	rightVisualPaneRect, rightVisualPanelMouseHit,
	RightVisualPaneRect, RightVisualPanelMouseHit, RIGHT_VISUAL_PANEL_ROWS,
	RIGHT_VISUAL_PANEL_X, RIGHT_VISUAL_PANE_COUNT,
	TRACK_OVERVIEW_VOICE_LANES;
import ui.trackoverviewnotes : buildTrackOverviewNotePreviews;
import ui.trackoverviewrenderer : drawTrackOverview, TrackOverviewMarkers,
	TrackOverviewVisualState;
import ui.trackoverviewstate : TrackOverviewEditorCursor, TrackOverviewHitRegion,
	TrackOverviewHitTest,
	TrackOverviewBlockDragState,
	TrackOverviewBlockSelection,
	TrackOverviewCurrentEditorBlock,
	TrackOverviewFocusKind, TrackOverviewFocusState,
	TrackOverviewPlaybackCursor, TrackOverviewPlaybackState,
	TrackOverviewScrollState, TrackOverviewSelectionState,
	advanceTrackOverviewPlaybackState,
	clearTrackOverviewBlockDrag,
	clearTrackOverviewBlockSelection,
	clearTrackOverviewManualScroll,
	clearTrackOverviewSelectionState,
	collectTrackOverviewSelectedTrackEntries,
	dragTrackOverviewScrollbar,
	rememberTrackOverviewTimelineScrubTargets,
	revealTrackOverviewBlockSelection,
	selectAdjacentTrackOverviewBlock,
	selectTrackOverviewBlockAtTrackIndex,
	selectTrackOverviewBlockNearTrackIndex,
	selectTrackOverviewRangeByTrackIndex,
	selectTrackOverviewRangeByTrackIndexWithPrimary,
	selectTrackOverviewHitBlockPreservingRange,
	selectTrackOverviewRangeFromHit,
	setTrackOverviewBlockFocus,
	setTrackOverviewEditorFocus,
	setTrackOverviewTimelineFocus,
	startTrackOverviewBlockDragCandidate,
	startTrackOverviewPlaybackState, stopTrackOverviewPlaybackState,
	startTrackOverviewScrollbarDrag, stopTrackOverviewScrollbarDrag,
	startTrackOverviewTimelineScrub, stopTrackOverviewPointerDrag,
	stopTrackOverviewTimelineScrub,
	syncTrackOverviewManualScroll,
	trackOverviewDragEdgeScrollDelta,
	TRACK_OVERVIEW_KEY_SCROLL_STEP,
	TRACK_OVERVIEW_WHEEL_SCROLL_STEP,
	trackOverviewContentWidth, trackOverviewEditorCursor,
	trackOverviewCurrentEditorBlock,
	trackOverviewCenterPlaybackCursorScrollX,
	trackOverviewFollowEditorCursorScrollX,
	trackOverviewFollowPlaybackCursorScrollX, trackOverviewPlaybackCursor,
	trackOverviewHitTest, trackOverviewPlusHitTest,
	trackOverviewLastTimelineRow,
	trackOverviewPositionAtTrackRow,
	trackOverviewTimelineBestPosition,
	trackOverviewTimelinePositionsAllValid,
	trackOverviewTimelinePositionsAtRow,
	trackOverviewScrollByPixels,
	trackOverviewSelectionSelectedCount,
	updateTrackOverviewBlockDrag,
	updateTrackOverviewBlockDropTarget,
	validateTrackOverviewFocus,
	validateTrackOverviewBlockSelection,
	validateTrackOverviewSelectionState,
	trackOverviewViewport;
import std.string;
import std.file;
import std.stdio;
import audio.audio, audio.timer, audio.callback;

enum PAGESTEP = 16;
enum CONFIRM_TIMEOUT = 3000; // 60 seconds * 50 UI timer events per second
enum HELP_TEXT_TOGGLE_STATUS_TICKS = 35;
enum FAILURE_TIMEOUT = 250; // 5 seconds * 50 UI timer events per second
enum UPDATE_RATE = 2; // 50 / n times per second

private enum DocumentReplacementScope {
	fullSongReplacement,
	sequencesOnlyReplacement
}

private int tickcounter1, tickcounter3 = -1;
private int escapecounter;

struct Rectangle {
	int x, y;
	int height, width;
	alias height h;
	alias width w;
	
	string toString() {
		return format("%d %d %d %d",x, y, h, w);
	}
	
	bool overlaps(int cx, int cy) {
		return cx >= x && cx < x + width && cy >= y && cy < y + height;
	}
	
	Rectangle relativeTo(int scrx, int scry) {
		return Rectangle(scrx - x, scry - y);
	}
}

enum TrackOverviewQuickHelpKind {
	noBlock,
	activeBlock,
	selectedRange,
	timeline
}

struct TrackOverviewQuickHelpAction {
	KeyboardActionId actionId;
	string actionPhrase;
}

TrackOverviewQuickHelpKind trackOverviewQuickHelpKind(
		TrackOverviewFocusKind focusKind,
		const TrackOverviewSelectionState selectionState) {
	final switch(focusKind) {
	case TrackOverviewFocusKind.Block:
		int selectedCount =
			trackOverviewSelectionSelectedCount(selectionState);
		if(selectedCount == 1)
			return TrackOverviewQuickHelpKind.activeBlock;
		if(selectedCount > 1)
			return TrackOverviewQuickHelpKind.selectedRange;
		return TrackOverviewQuickHelpKind.noBlock;
	case TrackOverviewFocusKind.Timeline:
		return TrackOverviewQuickHelpKind.timeline;
	case TrackOverviewFocusKind.Editor:
		return TrackOverviewQuickHelpKind.noBlock;
	}
}

TrackOverviewQuickHelpAction[] trackOverviewQuickHelpActions(
		TrackOverviewQuickHelpKind kind) {
	final switch(kind) {
	case TrackOverviewQuickHelpKind.activeBlock:
		return [
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewInsertCopyEntry,
				"duplicate"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewLoopActiveVoice,
				"voice LOOP"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewLoopAllVoices,
				"all LOOP"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.sequencerPlaybackMarkSetActiveVoice,
				"voice mark"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.sequencerPlaybackMarkSet,
				"all marks")
		];
	case TrackOverviewQuickHelpKind.selectedRange:
		return [
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewCopyEntries,
				"copy"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewDeleteSelection,
				"remove")
		];
	case TrackOverviewQuickHelpKind.timeline:
		return [
			TrackOverviewQuickHelpAction(
				KeyboardActionId.playbackPlayFromMark,
				"play mark"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.playbackPlayFromStart,
				"play start"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.playbackPlayFromCursor,
				"play cursor"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.playbackStop,
				"stop"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewTimelineStepLeft,
				"previous"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewTimelineStepRight,
				"next"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewTimelinePageUp,
				"page up"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewTimelinePageDown,
				"page down"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewTimelineHome,
				"start"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewTimelineEnd,
				"end")
		];
	case TrackOverviewQuickHelpKind.noBlock:
		return [];
	}
}

private TrackOverviewQuickHelpAction[][] trackOverviewQuickHelpActionLines(
		TrackOverviewQuickHelpKind kind) {
	final switch(kind) {
	case TrackOverviewQuickHelpKind.activeBlock:
		return [
			[
				TrackOverviewQuickHelpAction(
					KeyboardActionId.trackOverviewInsertCopyEntry,
					"duplicate"),
				TrackOverviewQuickHelpAction(
					KeyboardActionId.trackOverviewLoopAllVoices,
					"all LOOP")
			],
			[
				TrackOverviewQuickHelpAction(
					KeyboardActionId.trackOverviewLoopActiveVoice,
					"voice LOOP")
			],
			[
				TrackOverviewQuickHelpAction(
					KeyboardActionId.sequencerPlaybackMarkSetActiveVoice,
					"voice mark"),
				TrackOverviewQuickHelpAction(
					KeyboardActionId.sequencerPlaybackMarkSet,
					"all marks")
			]
		];
	case TrackOverviewQuickHelpKind.selectedRange:
		return [trackOverviewQuickHelpActions(kind)];
	case TrackOverviewQuickHelpKind.timeline:
		return [
			[
				TrackOverviewQuickHelpAction(
					KeyboardActionId.playbackPlayFromMark,
					"play mark"),
				TrackOverviewQuickHelpAction(
					KeyboardActionId.playbackPlayFromStart,
					"play start")
			],
			[
				TrackOverviewQuickHelpAction(
					KeyboardActionId.playbackPlayFromCursor,
					"play cursor"),
				TrackOverviewQuickHelpAction(
					KeyboardActionId.playbackStop,
					"stop")
			],
			[
				TrackOverviewQuickHelpAction(
					KeyboardActionId.trackOverviewTimelineStepLeft,
					"previous"),
				TrackOverviewQuickHelpAction(
					KeyboardActionId.trackOverviewTimelineStepRight,
					"next")
			]
		];
	case TrackOverviewQuickHelpKind.noBlock:
		return [];
	}
}

private string trackOverviewQuickHelpLine(
		TrackOverviewQuickHelpAction[] actions) {
	string message;
	foreach(action; actions) {
		string shortcut = keyboardActionPrimaryShortcutLabel(
			keyboardActionStableId(action.actionId));
		if(shortcut.length == 0)
			continue;
		if(message.length)
			message ~= "; ";
		message ~= shortcut ~ " " ~ action.actionPhrase;
	}
	if(message.length)
		message ~= ".";
	return message;
}

string trackOverviewQuickHelpMessage(TrackOverviewQuickHelpKind kind) {
	if(kind == TrackOverviewQuickHelpKind.noBlock)
		return "Click a block; click timeline to focus.";

	string message;
	foreach(line; trackOverviewQuickHelpActionLines(kind)) {
		string lineMessage = trackOverviewQuickHelpLine(line);
		if(lineMessage.length == 0)
			continue;
		if(message.length)
			message ~= "\n";
		message ~= lineMessage;
	}
	return message;
}

private string trackOverviewQuickHelpSemanticContext(
		TrackOverviewQuickHelpKind kind) {
	return "track_overview:" ~ to!string(cast(int)kind);
}

bool trackOverviewKeyboardContextIsActive(TrackOverviewFocusKind focusKind,
		bool activeWindowIsSequencer, bool dialogActive) {
	return !dialogActive && activeWindowIsSequencer &&
		focusKind != TrackOverviewFocusKind.Editor;
}

abstract class Window {
	Rectangle area;
	Input input;
	protected ContextHelp help;
	
	this(Rectangle a) {
		this(a, ui.help.HELPMAIN);
	}

	this(Rectangle a, ContextHelp ctx) {
		contextHelp = ctx;
		area = a;
	}

	abstract void update();
	int keypress(Keyinfo key) { return 0; }
	int keyrelease(Keyinfo key) { return 0; }
		void refresh() {}
		void deactivate() {
			if(input !is null)
				input.deactivate();
		}
		void activate() { refresh(); }
		void clickedAt(int scrx, int scry, int button) {}
		bool mouseMotionAt(int x, int y) { return false; }
		bool mouseButtonUp(int button) { return false; }
		bool advanceGeneratedTableRowDragAutoScroll() { return false; }
		bool allowsF6OriginReturn() { return false; }

protected:

	@property void contextHelp(ContextHelp h) { help = h; }
	@property ContextHelp contextHelp() { return help; }
	
	final void drawFrame() { drawFrame(area); }
	
	static void drawFrame(Rectangle a) {
		int x,y;
		for(y=a.y;y<a.y+a.height;y++) {
			screen.setChar(a.x-1,y,0);
			screen.setChar(a.x,y, 0x500|216);
			screen.setChar(a.x+a.width-1,y, 0x500|216);
			screen.setChar(a.x+a.width,y,0);
			screen.setColor(a.x+a.width+1,y+1,11,0);
		}
		for(x=a.x;x<a.x+a.width;x++) {
			screen.setChar(x,a.y, 0x0500|192);
			screen.setChar(x,a.y+a.height-1, 0x0500|192);
			screen.setColor(x+2,a.y+a.height, 11, 0);
		}

		screen.setChar(a.x,a.y,0x500 | 201);
		screen.setChar(a.x+a.width-1,a.y,0x500 | 215);
		screen.setChar(a.x,a.y+a.height-1,0x500 | 195);
		screen.setChar(a.x+a.width-1,a.y+a.height-1,0x500 | 212);
		screen.clearCells(a.x + 1, a.y + 1,
				a.width - 2, a.height - 2);
	}

	final void drawRuler(int y) {
		for(int x = area.x;x < area.x + area.width; x++) {
			screen.setChar(x, area.y + y, 0x0500|192);
	}
}

}

struct Hotspot {
	Rectangle area;
	void delegate(int) callback;
}

class WindowSwitcher : Window {
	Window[] windows;
	Window activeWindow;
	int activeWindowNum;
	
	this(Rectangle s, Window[] w) {
		super(s);
		windows = w;
		activeWindowNum = 0;
		activateWindow();
	}
	
	void activateWindow() {
		activateWindow(activeWindowNum);
	}
	
	void activateWindow(ulong n){
		activateWindow(cast(int)n);
	}
	
	void activateWindow(int n) {
		if(activeWindow !is null)
			activeWindow.deactivate();
		activeWindow = windows[n];
		activeWindow.activate();
		activeWindowNum = n;
		input = activeWindow.input;
		refresh();
	}

	override void update() {
		activeWindow.update();
	}

	override void activate() {
		activeWindow.activate();
	}

	override void deactivate() {
		activeWindow.deactivate();
	}

	override void refresh() {
		foreach(w; windows) w.refresh();
	}
	
	override int keypress(Keyinfo key) {
		KeyboardActionId actionId;
		if(resolveUiWindowSwitcherKeyboardAction(key, actionId)) {
			switch(actionId) {
			case KeyboardActionId.uiSubwindowPrevious:
				activeWindowNum--;
				break;
			case KeyboardActionId.uiSubwindowNext:
				activeWindowNum++;
				break;
			default:
				assert(0);
			}
			/+
			if(activeWindowNum < 0) activeWindowNum = cast(int)(windows.length - 1);
			if(activeWindowNum >= windows.length)
				activeWindowNum %= windows.length;
				+/
			activeWindowNum = umod(activeWindowNum, 0, cast(int)windows.length - 1);
			activateWindow();
			return OK;
		}
		return activeWindow.keypress(key);
	}

	override ContextHelp contextHelp() { 
		return activeWindow.contextHelp();
	}

	override void clickedAt(int scrx, int scry, int button) {
		//	activateAt(scrx - activeWindow.area.x, scry - activeWindow.area.y);
	}
}

private enum OSCILLOSCOPE_DISPLAY_GAIN_NUM = 1;
private enum OSCILLOSCOPE_DISPLAY_GAIN_DEN = 1;
private enum STATUSLINE_TEXT_X = 1;
private enum STATUSLINE_ROWS = 3;
private enum StatuslineInformationLifetime {
	timedOnly,
	contextDismissible
}
private enum STATUSLINE_TEXT_WIDTH = RIGHT_VISUAL_PANEL_X - STATUSLINE_TEXT_X;
private enum STATUSLINE_ALERT_ICON_X = 1;
private enum STATUSLINE_ALERT_ICON_Y = 0;
private enum STATUSLINE_FAILURE_TEXT_X = 3;
private enum STATUSLINE_FAILURE_TEXT_WIDTH =
	RIGHT_VISUAL_PANEL_X - STATUSLINE_FAILURE_TEXT_X;
private enum STATUSLINE_ALERT_COLOR = 1;
private enum STATUSLINE_ALERT_BACKGROUND = 0;
private enum STATUSLINE_JUMP_HINT = "[Enter to jump]";

private enum MAX_SONG_SPEED = 0x1f;
private enum INFOBAR_OCTAVE_LABEL_X_OFFSET = 19;
private enum INFOBAR_OCTAVE_VALUE_X_OFFSET = 24;
private enum INFOBAR_SPEED_LABEL_X_OFFSET = 27;
private enum INFOBAR_SPEED_VALUE_X_OFFSET = 32;
private enum INFOBAR_STEP_LABEL_X_OFFSET = 35;
private enum INFOBAR_STEP_VALUE_X_OFFSET = 39;
private enum INFOBAR_RATE_X_OFFSET = 3;
private enum INFOBAR_RATE_FIELD_WIDTH = 20;
private enum INFOBAR_RATE_MULTIPLIER_X_OFFSET = INFOBAR_RATE_X_OFFSET + 6;
private enum INFOBAR_RATE_MULTIPLIER_WIDTH = 2;
private enum INFOBAR_RATE_TIMING_X_OFFSET = INFOBAR_RATE_X_OFFSET + 9;
private enum INFOBAR_RATE_TIMING_WIDTH = 11;
private enum INFOBAR_SID_X_OFFSET = INFOBAR_RATE_X_OFFSET +
	INFOBAR_RATE_FIELD_WIDTH + 1;
private enum INFOBAR_SID_FIELD_WIDTH = 24;
private enum INFOBAR_SID_HOTSPOT_WIDTH = 10;
private enum INFOBAR_ICON_NORMAL_COLOR = 5;
private enum INFOBAR_ICON_KEYJAM_ENABLED_COLOR = 1;
private enum INFOBAR_ICON_KEYJAM_DISABLED_COLOR = 11;
private enum INFOBAR_ICON_BACKGROUND_COLOR = 0;
private enum INFOBAR_THEME_SELECTED_COLOR = 1;
private enum INFOBAR_THEME_UNSELECTED_COLOR = 11;

private void adjustSongMultiplier(int direction) {
	assert(direction == -1 || direction == 1);
	int oldMultiplier = song.multiplier;
	if(direction > 0)
		audio.player.incMultiplier();
	else
		audio.player.decMultiplier();
	if(song.multiplier != oldMultiplier)
		timelineSeekManager().invalidate("song_multispeed");
}

class InputBoundedHexByte : Input {
	alias ValueGetter = int delegate();
	alias ValueSetter = bool delegate(int);

	private {
		char[] digits;
		int originalValue;
		int digitCursor;
		ValueGetter valueGetter;
		ValueSetter valueSetter;
		int minimumValue;
		int maximumValue;
		string invalidHighDigitMessage;
	}

	this(ValueGetter getter, ValueSetter setter, int minimum, int maximum,
			string invalidMessage) {
		super(2);
		valueGetter = getter;
		valueSetter = setter;
		minimumValue = minimum;
		maximumValue = maximum;
		invalidHighDigitMessage = invalidMessage;
		refresh();
	}

	void beginEdit() {
		originalValue = valueGetter();
		setDigitsFromValue(originalValue);
	}

	override void refresh() {
		setDigitsFromValue(valueGetter());
	}

	override int setValue(int v) {
		int nextValue = clamp(v, minimumValue, maximumValue);
		valueSetter(nextValue);
		setDigitsFromValue(valueGetter());
		return OK;
	}

	override int keypress(Keyinfo key) {
		if(key.raw == SDLK_RETURN || key.raw == SDLK_KP_ENTER)
			return RETURN;
		if(key.raw == SDLK_ESCAPE) {
			setValue(originalValue);
			return CANCEL;
		}
		if(key.raw == SDLK_LEFT) {
			if(digitCursor > 0)
				digitCursor--;
			return OK;
		}
		if(key.raw == SDLK_RIGHT) {
			if(digitCursor < width - 1)
				digitCursor++;
			return OK;
		}
		if(key.raw == SDLK_UP) {
			stepValue(1);
			return OK;
		}
		if(key.raw == SDLK_DOWN) {
			stepValue(-1);
			return OK;
		}
		if(key.raw == SDLK_BACKSPACE || key.raw == SDLK_DELETE) {
			digits[digitCursor] = '0';
			if(digitCursor > 0)
				digitCursor--;
			applyDigits();
			return OK;
		}

		int value = hexDigitValue(key);
		if(value < 0)
			return OK;

		int candidate = currentDigitsValue();
		if(digitCursor == 0)
			candidate = (candidate & 0x0f) | (value << 4);
		else
			candidate = (candidate & 0xf0) | value;
		if(candidate < minimumValue || candidate > maximumValue) {
			if(UI.statusline !is null)
				UI.statusline.displayFailure(invalidHighDigitMessage);
			return OK;
		}

		digits[digitCursor] = hexDigitChar(value);
		if(digitCursor < width - 1)
			digitCursor++;
		applyDigits();
		return OK;
	}

	override void update() {
		screen.cprint(x, y, 1, -1,
			format("%02X", currentDigitsValue()));
		cursor.set(x + digitCursor, y);
	}

	void setCursorDigit(int digit) {
		digitCursor = clamp(digit, 0, width - 1);
	}

	@property int cursorDigit() const {
		return digitCursor;
	}

private:
	void setDigitsFromValue(int value) {
		digits = format("%02X",
			clamp(value, minimumValue, maximumValue)).dup;
		if(digits.length > width)
			digits = digits[$ - width .. $].dup;
		digitCursor = 0;
	}

	void stepValue(int delta) {
		int cursor = digitCursor;
		int next = currentDigitsValue() + delta;
		if(next < minimumValue)
			next = maximumValue;
		else if(next > maximumValue)
			next = minimumValue;
		setDigitsFromValue(next);
		digitCursor = cursor;
		applyDigits();
	}

	void applyDigits() {
		valueSetter(currentDigitsValue());
	}

	int currentDigitsValue() {
		return digits.length == 0 ? 0 : parseHexDigits(digits);
	}

	int parseHexDigits(const(char)[] value) {
		int result;
		foreach(ch; value)
			result = (result << 4) | hexDigitValue(ch);
		return result;
	}

	int hexDigitValue(Keyinfo key) {
		if(key.raw >= SDLK_KP_0 && key.raw <= SDLK_KP_9)
			return key.raw - SDLK_KP_0;
		if(key.unicode >= '0' && key.unicode <= '9')
			return key.unicode - '0';
		if(key.unicode >= 'a' && key.unicode <= 'f')
			return key.unicode - 'a' + 10;
		if(key.unicode >= 'A' && key.unicode <= 'F')
			return key.unicode - 'A' + 10;
		return -1;
	}

	int hexDigitValue(const(char) ch) {
		if(ch >= '0' && ch <= '9')
			return ch - '0';
		if(ch >= 'A' && ch <= 'F')
			return ch - 'A' + 10;
		if(ch >= 'a' && ch <= 'f')
			return ch - 'a' + 10;
		return 0;
	}

	char hexDigitChar(int value) {
		return cast(char)(value < 10 ? '0' + value : 'A' + value - 10);
	}
	}

private int currentSongSpeedForEditor() {
	return song.speed;
}

private bool setSongSpeedFromEditor(int value) {
	if(song.speed != value) {
		song.speed = value;
		timelineSeekManager().invalidate("song_speed");
	}
	return true;
}

class InputSongSpeed : InputBoundedHexByte {
	this() {
		super(() => currentSongSpeedForEditor(),
			(int value) => setSongSpeedFromEditor(value), 0,
			MAX_SONG_SPEED,
			"Tempo speed high digit must be 0 or 1. Use 00-1F.");
	}
}

	class InputBaseOctave : Input {
		private int originalOctave;

		this() {
			super(1);
			refresh();
		}

		void beginEdit() {
			originalOctave = state.octave;
			setValue(originalOctave);
		}

		override void refresh() {
			setValue(state.octave);
		}

		override int setValue(int v) {
			state.octave = clamp(v, 0, 6);
			return OK;
		}

		override int keypress(Keyinfo key) {
			if(key.raw == SDLK_RETURN || key.raw == SDLK_KP_ENTER)
				return RETURN;
			if(key.raw == SDLK_ESCAPE) {
				setValue(originalOctave);
				return CANCEL;
			}
			if(key.raw == SDLK_UP) {
				setValue(state.octave + 1);
				return OK;
			}
			if(key.raw == SDLK_DOWN) {
				setValue(state.octave - 1);
				return OK;
			}
			if(key.unicode >= '0' && key.unicode <= '6')
				setValue(key.unicode - '0');
			return OK;
		}

		override void update() {
			screen.cprint(x, y, 1, -1, format("%d", state.octave));
			cursor.set(x, y);
		}
	}

	class InputStepValue : Input {
		private int originalStep;

		this() {
			super(1);
			refresh();
		}

		void beginEdit() {
			originalStep = currentStep();
			setValue(originalStep);
		}

		override void refresh() {
			setValue(currentStep());
		}

		override int setValue(int v) {
			seq.sequencer.stepValue = clamp(v, 1, 9);
			return OK;
		}

		override int keypress(Keyinfo key) {
			if(key.raw == SDLK_RETURN || key.raw == SDLK_KP_ENTER)
				return RETURN;
			if(key.raw == SDLK_ESCAPE) {
				setValue(originalStep);
				return CANCEL;
			}
			KeyboardActionId actionId;
			if(resolveCursorStepInputKeyboardAction(key, actionId)) {
				switch(actionId) {
				case KeyboardActionId.sequencerCursorStepDecrease:
					stepValue(-1);
					break;
				case KeyboardActionId.sequencerCursorStepIncrease:
					stepValue(1);
					break;
				default:
					break;
				}
				return OK;
			}

			int value = stepDigitValue(key);
			if(value > 0)
				setValue(value);
			return OK;
		}

		override void update() {
			screen.cprint(x, y, 1, -1, format("%d", currentStep()));
			cursor.set(x, y);
		}

	private:
		int currentStep() {
			return clamp(seq.sequencer.stepValue, 1, 9);
		}

		void stepValue(int delta) {
			int next = currentStep() + delta;
			if(next < 1)
				next = 9;
			else if(next > 9)
				next = 1;
			setValue(next);
		}

		int stepDigitValue(Keyinfo key) {
			if(key.raw >= SDLK_KP_1 && key.raw <= SDLK_KP_9)
				return key.raw - SDLK_KP_1 + 1;
			if(key.unicode >= '1' && key.unicode <= '9')
				return key.unicode - '0';
			return 0;
		}
	}
	
	class Infobar : Window {
		private {
			const int x1, x2;
			enum TITLE_FIELD = 0;
			enum AUTHOR_FIELD = 1;
			enum RELEASE_FIELD = 2;
				enum OCTAVE_FIELD = 3;
				enum SPEED_FIELD = 4;
				enum STEP_FIELD = 5;
				int idx;
				int nextActivationField;
				int nextActivationSpeedDigit;
				bool speedChordJumpRequested;
			}
		InputString inputTitle, inputAuthor, inputReleased;
		InputBaseOctave inputOctave;
		InputSongSpeed inputSpeed;
		InputStepValue inputStep;
		
		this(Rectangle a) {
			super(a);
			x1 = area.x;
			x2 = x1 + (com.fb.mode > 0 ? 64 : 48);
		}

		private static string baseOctaveQuickHelp() {
			string decrease = keyboardActionPrimaryShortcutLabel(
				keyboardActionStableId(KeyboardActionId.uiBaseOctaveDecrease));
			string increase = keyboardActionPrimaryShortcutLabel(
				keyboardActionStableId(KeyboardActionId.uiBaseOctaveIncrease));
			return format("Base octave: 0-6.\n%s decrease; %s increase.",
				decrease, increase);
		}

		private static string songSpeedQuickHelp() {
			string decrease = keyboardActionPrimaryShortcutLabel(
				keyboardActionStableId(KeyboardActionId.songSpeedDecrease));
			string increase = keyboardActionPrimaryShortcutLabel(
				keyboardActionStableId(KeyboardActionId.songSpeedIncrease));
			return format("Tempo speed: $2-$1F steady.\n" ~
				"$0/$1 uses Chord row $00 shuffle timing.\n" ~
				"%s decrease; %s increase.", decrease, increase);
		}

		private static string cursorStepQuickHelp() {
			string setValue = keyboardActionPrimaryShortcutLabel(
				keyboardActionStableId(KeyboardActionId.sequencerCursorStepSet));
			string decrease = keyboardActionPrimaryShortcutLabel(
				keyboardActionStableId(KeyboardActionId.sequencerCursorStepDecrease));
			string increase = keyboardActionPrimaryShortcutLabel(
				keyboardActionStableId(KeyboardActionId.sequencerCursorStepIncrease));
			return format("Cursor step: 1-9.\n%s set value.\n" ~
				"%s decrease; %s increase.", setValue, decrease, increase);
		}

	override void update() {
		for(int x = 0; x < RIGHT_VISUAL_PANEL_X; x++)
			screen.cprint(x, area.y, 15, 0, " ");

		int c1 = audio.player.isPlaying ? 13 : 12;
		screen.fprint(x1,area.y,format("`05Time: `0%x%02d:%02d / $%02x",
									   c1,audio.timer.min, audio.timer.sec,
									   audio.callback.linesPerFrame & 255));
		
		screen.fprint(x1 + 19,area.y,
				   format("`05Oct: `0d%d  `b1S`05pd: `0d%02X `05St: `0d%d ",
						  state.octave, song.speed, seq.sequencer.stepValue));
		string timingText = audio.player.ntsc ? "60hz (NTSC)" : "50hz (PAL)";
		screen.fprint(x2 + INFOBAR_RATE_X_OFFSET, area.y + 1,
			format("`05Rate: `0d%02d*%-11s", song.multiplier, timingText));
		string sidText =
			audio.player.usefp ? audio.player.curfp.id :
			audio.player.sidtype ? "8580" : "6581";
		sidText ~= audio.player.badline ? "&0fb" : " ";
		screen.fprint(x2 + INFOBAR_SID_X_OFFSET, area.y + 1,
			format("`05SID: `0d%s",
				sidText.leftJustify(INFOBAR_SID_FIELD_WIDTH - 5)));
		screen.fprint(x1,area.y+1,format("`05Filename: `0d%s", state.filename.leftJustify(38)));
		//screen.fprint(x2,area.y,format("`05  `b1T`01itle: `0d%-32s", std.string.toString(cast(char *)song.title))); 
		string infoLabel = idx == AUTHOR_FIELD ? " `01Author:" :
			idx == RELEASE_FIELD ? "`01Release:" : "  `b1T`01itle:";
		screen.fprint(x2,area.y,
					  format("`05%s `0d%-32s", infoLabel, song.title));
			screen.fprint(x2,area.y+2,format("`05 Player: `0d%s", ztos(song.playerID)));
			submitBottomControlGlyphs();
		}

			private void submitBottomControlGlyphs() {
				auto layout = bottomControlLayout(screen.width, screen.height);
				if(!layout.valid)
					return;
				foreach(i; 0 .. layout.count) {
					auto placement = layout.placements[i];
					int color = bottomControlColor(placement.role);
					foreach(glyphIndex; 0 .. placement.glyphCount) {
						video.submitInfobarExtendedGlyph(
							placement.rect.x + glyphIndex,
							placement.rect.y,
							placement.glyphs[glyphIndex], color,
							INFOBAR_ICON_BACKGROUND_COLOR);
					}
				}
			}

			private int bottomControlColor(BottomControlRole role) {
				final switch(role) {
				case BottomControlRole.none:
					return INFOBAR_ICON_NORMAL_COLOR;
				case BottomControlRole.theme1:
				case BottomControlRole.theme2:
				case BottomControlRole.theme3:
				case BottomControlRole.theme4:
					return bottomControlThemeIndex(role) == currentInterfaceTheme() ?
						INFOBAR_THEME_SELECTED_COLOR : INFOBAR_THEME_UNSELECTED_COLOR;
				case BottomControlRole.keyjam:
					return state.keyjamStatus ? INFOBAR_ICON_KEYJAM_ENABLED_COLOR :
						INFOBAR_ICON_KEYJAM_DISABLED_COLOR;
				case BottomControlRole.fullscreen:
				case BottomControlRole.load:
				case BottomControlRole.save:
				case BottomControlRole.audio:
				case BottomControlRole.help:
					return INFOBAR_ICON_NORMAL_COLOR;
				}
			}

			bool clickedBottomControlAt(int x, int y, int button) {
				auto interaction = bottomControlInteractionAtCell(screen.width,
					screen.height, x, y, button, currentInterfaceTheme());
				if(!interaction.handled)
					return false;
				if(interaction.invokeAction)
					executeBottomControlAction(interaction);
				return true;
			}

			private void executeBottomControlAction(BottomControlInteraction interaction) {
				final switch(interaction.role) {
				case BottomControlRole.none:
					break;
				case BottomControlRole.fullscreen:
					mainui.executeUiGlobalAction(KeyboardActionId.uiToggleFullscreen);
					break;
				case BottomControlRole.theme1:
				case BottomControlRole.theme2:
				case BottomControlRole.theme3:
				case BottomControlRole.theme4:
					if(video.applyInterfaceTheme(interaction.themeIndex))
						submitBottomControlGlyphs();
					break;
				case BottomControlRole.load:
					mainui.openContextualLoadDialog();
					break;
				case BottomControlRole.save:
					mainui.openContextualSaveDialog();
					break;
				case BottomControlRole.keyjam:
					mainui.toggleKeyjamMode();
					submitBottomControlGlyphs();
					break;
				case BottomControlRole.audio:
					mainui.openAudioSettingsDialog();
					break;
				case BottomControlRole.help:
					mainui.openContextHelp();
					break;
				}
			}

		override void refresh() {
			inputTitle = new InputString(cast(string)(song.title), cast(int)(song.title.length));
			inputReleased = new InputString(cast(string)(song.release), cast(int)( song.release.length));
			inputAuthor = new InputString(cast(string)(song.author), cast(int)(song.author.length));
			if(inputOctave is null)
				inputOctave = new InputBaseOctave();
			if(inputSpeed is null)
				inputSpeed = new InputSongSpeed();
			if(inputStep is null)
				inputStep = new InputStepValue();
			if(idx == OCTAVE_FIELD) {
				inputOctave.beginEdit();
				input = inputOctave;
				input.setCoord(x1 + INFOBAR_OCTAVE_VALUE_X_OFFSET, area.y);
				if(UI.statusline !is null)
					UI.statusline.displayContextual(baseOctaveQuickHelp());
				return;
			}
			if(idx == SPEED_FIELD) {
				inputSpeed.beginEdit();
				inputSpeed.setCursorDigit(nextActivationSpeedDigit);
				input = inputSpeed;
				input.setCoord(x1 + INFOBAR_SPEED_VALUE_X_OFFSET, area.y);
				if(UI.statusline !is null)
					UI.statusline.displayContextual(songSpeedQuickHelp());
				return;
			}
			if(idx == STEP_FIELD) {
				inputStep.beginEdit();
				input = inputStep;
				input.setCoord(x1 + INFOBAR_STEP_VALUE_X_OFFSET, area.y);
				if(UI.statusline !is null)
					UI.statusline.displayContextual(cursorStepQuickHelp());
				return;
			}
		input = ([ inputTitle, inputAuthor, inputReleased ])[idx];
		input.setCoord(x2 + 9, area.y);
	}
	
	override void activate() {
		idx = nextActivationField;
		nextActivationField = TITLE_FIELD;
		refresh();
	}

		void activateSpeedOnNextOpen(int digit = 0) {
			nextActivationField = SPEED_FIELD;
			nextActivationSpeedDigit = clamp(digit, 0, 1);
		}

		void activateOctaveOnNextOpen() {
			nextActivationField = OCTAVE_FIELD;
		}

		void activateStepOnNextOpen() {
			nextActivationField = STEP_FIELD;
		}

	bool octaveEditActive() {
		return idx == OCTAVE_FIELD;
	}

	bool speedEditActive() {
		return idx == SPEED_FIELD;
	}

		bool stepEditActive() {
			return idx == STEP_FIELD;
		}

		bool inlineEditActive() {
			return octaveEditActive() || speedEditActive() || stepEditActive();
		}

		bool octaveEditContainsCell(int x, int y) {
			return octaveEditActive() && y == area.y &&
				x >= x1 + INFOBAR_OCTAVE_LABEL_X_OFFSET &&
				x < x1 + INFOBAR_OCTAVE_VALUE_X_OFFSET + 1;
		}

		bool speedEditContainsCell(int x, int y) {
			return speedEditActive() && y == area.y &&
				x >= x1 + INFOBAR_SPEED_LABEL_X_OFFSET &&
				x < x1 + INFOBAR_SPEED_VALUE_X_OFFSET + 2;
		}

		bool stepEditContainsCell(int x, int y) {
			return stepEditActive() && y == area.y &&
				x >= x1 + INFOBAR_STEP_LABEL_X_OFFSET &&
				x < x1 + INFOBAR_STEP_VALUE_X_OFFSET + 1;
		}

		void setSpeedCursorFromCell(int x) {
			if(!speedEditActive())
				return;
			int valueX = x1 + INFOBAR_SPEED_VALUE_X_OFFSET;
			inputSpeed.setCursorDigit(x >= valueX ? x - valueX : 0);
		}

		bool consumeSpeedChordJumpRequest() {
			bool requested = speedChordJumpRequested;
		speedChordJumpRequested = false;
		return requested;
	}

	override void deactivate() {
		outputStrings();
	}

	private void outputStrings() {
		song.title[0..32] = (cast(InputString)inputTitle).toString(true)[0..32];
		song.release[0..32] = (cast(InputString)inputReleased).toString(true)[0..32];
		song.author[0..32] = (cast(InputString)inputAuthor).toString(true)[0..32];
	}
	
	override int keypress(Keyinfo key) {
		int r = input.keypress(key);
		if(r == RETURN) {
			if(idx == SPEED_FIELD) {
				speedChordJumpRequested = song.speed <= 1;
				return RETURN;
			}
			if(idx == STEP_FIELD)
				return RETURN;
			idx++; 
			if(idx > RELEASE_FIELD) {
				idx = TITLE_FIELD;
				return RETURN;
			}
			outputStrings();
			refresh();
		}
		else if(r == CANCEL) {
			idx = TITLE_FIELD; update();
			return RETURN;
		}
		return OK;
	}
}

class Statusline : Window {
	int counter;
	string message;
	private int failureCounter;
	private string failureMessage;
	private string persistentContextualMessage;
	private bool persistentContextualAlert;
	private string contextualMessage;
	private string contextualOwner;
	private StatuslineInformationLifetime informationLifetime;
	private bool helpToggleConfirmationActive;
	private ulong interactionGeneration;
	private ulong transientGeneration;
	private ulong failureGeneration;
	private ulong persistentContextualGeneration;
	
	this(Rectangle a) {
		super(a);
	}

	void displayTimedOperationFeedback(string msg) {
		if(!state.displayHelp)
			return;
		helpToggleConfirmationActive = false;
		transientGeneration = interactionGeneration;
		message = msg;
		counter = CONFIRM_TIMEOUT;
		informationLifetime = StatuslineInformationLifetime.timedOnly;
		update();
	}

	void displayOperationFeedback(string msg) {
		if(!state.displayHelp)
			return;
		helpToggleConfirmationActive = false;
		transientGeneration = interactionGeneration;
		message = msg;
		counter = CONFIRM_TIMEOUT;
		informationLifetime =
			StatuslineInformationLifetime.contextDismissible;
		update();
	}

	void displayHelpTextToggleConfirmation(string msg) {
		clearTransientStatus();
		helpToggleConfirmationActive = true;
		transientGeneration = interactionGeneration;
		message = msg;
		counter = HELP_TEXT_TOGGLE_STATUS_TICKS;
		informationLifetime = StatuslineInformationLifetime.timedOnly;
		update();
	}

	void displayFailure(string msg) {
		if(!state.displayHelp)
			return;
		helpToggleConfirmationActive = false;
		counter = 0;
		informationLifetime = StatuslineInformationLifetime.timedOnly;
		failureMessage = msg;
		failureCounter = FAILURE_TIMEOUT;
		failureGeneration = interactionGeneration;
		showAlertGlyph();
		update();
	}

	void noteMeaningfulInteraction() {
		interactionGeneration++;
		if(interactionGeneration == 0) {
			interactionGeneration = 1;
			transientGeneration = 0;
			failureGeneration = 0;
			persistentContextualGeneration = 0;
		}
		clearIneligibleTransientStatus();
		update();
	}

	void displayContextual(string msg, string sourceFile = __FILE__,
			size_t sourceLine = __LINE__) {
		string owner = contextualOwnerId(sourceFile, sourceLine);
		displayContextualWithOwner(msg, owner);
	}

	void displayContextualSemantic(string msg, string semanticContext,
			string sourceFile = __FILE__, size_t sourceLine = __LINE__) {
		string owner = contextualOwnerId(sourceFile, sourceLine,
			semanticContext);
		displayContextualWithOwner(msg, owner);
	}

	private void displayContextualWithOwner(string msg, string owner) {
		contextualMessage = msg;
		contextualOwner = owner;
		clearIneligibleTransientStatus();
		if(persistentContextualVisible() || counterMessageVisible() ||
				failureMessageVisible())
			return;
		update();
	}

	void setPersistentContextualMessage(string msg) {
		persistentContextualMessage = msg;
		persistentContextualAlert = false;
		persistentContextualGeneration = interactionGeneration;
		update();
	}

	void setPersistentAlertMessage(string msg) {
		persistentContextualMessage = msg;
		persistentContextualAlert = true;
		persistentContextualGeneration = interactionGeneration;
		update();
	}

	void clearPersistentContextualMessage() {
		persistentContextualMessage = "";
		persistentContextualAlert = false;
		update();
	}
	
	override void deactivate() {
		counter = 0;
		informationLifetime = StatuslineInformationLifetime.timedOnly;
		update();
	}

	override void update() {
		clearLeftHelpArea();
		bool normalTextVisible = state.displayHelp;
		bool helpToggleVisible = helpToggleMessageVisible();
		bool failureVisible = failureMessageVisible();
		bool timedMessageVisible = counterMessageVisible() &&
			!helpToggleConfirmationActive;
		bool persistentVisible = persistentContextualVisible();
		bool persistentAlertVisible = normalTextVisible && !failureVisible &&
			!timedMessageVisible && !helpToggleVisible && persistentVisible &&
			persistentContextualAlert && persistentContextualMessage.length;
		bool alertVisible = failureVisible || persistentAlertVisible;
		if(alertVisible)
			showAlertGlyph();
		else
			hideAlertGlyph();

		string visibleMessage = helpToggleVisible ? message :
			failureVisible ? failureMessage :
			timedMessageVisible ? message :
			persistentVisible ? persistentContextualMessage :
			normalTextVisible ? contextualMessage : "";
		if(!visibleMessage.length)
			return;

		int textX = alertVisible ? STATUSLINE_FAILURE_TEXT_X :
			STATUSLINE_TEXT_X;
		int textWidth = alertVisible ? STATUSLINE_FAILURE_TEXT_WIDTH :
			STATUSLINE_TEXT_WIDTH;
		string color = alertVisible ? "`01" : "`0f";
		string remaining = visibleMessage;
		foreach(row; 0 .. STATUSLINE_ROWS) {
			string line = nextWrappedLine(remaining, textWidth);
			if(line.length)
				screen.fprint(textX, row, color ~ line);
			if(!remaining.length)
				break;
		}
	}

	private void showAlertGlyph() {
		video.submitStatuslineFailureGlyph(STATUSLINE_ALERT_ICON_X,
			STATUSLINE_ALERT_ICON_Y, STATUSLINE_ALERT_COLOR,
			STATUSLINE_ALERT_BACKGROUND);
	}

	private void hideAlertGlyph() {
		video.clearStatuslineFailureGlyph();
	}

	private void clearLeftHelpArea() {
		foreach(row; 0 .. STATUSLINE_ROWS) {
			for(int x = 0; x < RIGHT_VISUAL_PANEL_X; x++)
				screen.cprint(x, row, 15, 0, " ");
		}
	}

	private void clearTransientStatus() {
		counter = 0;
		message = "";
		informationLifetime = StatuslineInformationLifetime.timedOnly;
		failureCounter = 0;
		failureMessage = "";
		helpToggleConfirmationActive = false;
		hideAlertGlyph();
	}

	private void clearIneligibleTransientStatus() {
		if(counter != 0 && transientGeneration != interactionGeneration) {
			counter = 0;
			message = "";
			informationLifetime = StatuslineInformationLifetime.timedOnly;
			helpToggleConfirmationActive = false;
		}
		if(failureCounter != 0 && failureGeneration != interactionGeneration) {
			failureCounter = 0;
			failureMessage = "";
			hideAlertGlyph();
		}
	}

	private bool counterMessageVisible() {
		return state.displayHelp && counter != 0 &&
			transientGeneration == interactionGeneration;
	}

	private bool helpToggleMessageVisible() {
		return helpToggleConfirmationActive && counter != 0 &&
			transientGeneration == interactionGeneration;
	}

	private bool failureMessageVisible() {
		return state.displayHelp && failureCounter != 0 &&
			failureGeneration == interactionGeneration;
	}

	private bool persistentContextualVisible() {
		return state.displayHelp && persistentContextualMessage.length != 0 &&
			(persistentContextualAlert ||
				persistentContextualGeneration == interactionGeneration);
	}

	private static void trimLeadingSpaces(ref string text) {
		while(text.length && text[0] == ' ')
			text = text[1 .. $];
	}

	private static bool formattingCodeAt(string text, size_t idx) {
		return text[idx] == '`' && idx + 2 < text.length;
	}

	private static string trimTrailingSpacesCopy(string text) {
		while(text.length && text[$ - 1] == ' ')
			text = text[0 .. $ - 1];
		return text;
	}

	private static long forcedHintSplitIndex(string text) {
		auto hintAt = text.indexOf(STATUSLINE_JUMP_HINT);
		if(hintAt <= 0)
			return -1;

		long splitAt = cast(long)hintAt;
		if(hintAt >= 3 && formattingCodeAt(text, cast(size_t)hintAt - 3))
			splitAt = cast(long)hintAt - 3;

		if(visibleLength(text[0 .. cast(size_t)splitAt]) == 0)
			return -1;
		return splitAt;
	}

	private static int visibleLength(string text) {
		int len;
		for(size_t idx = 0; idx < text.length;) {
			if(formattingCodeAt(text, idx)) {
				idx += 3;
				continue;
			}
			idx++;
			len++;
		}
		return len;
	}

	private static string activeFormattingCode(string text) {
		string code;
		for(size_t idx = 0; idx < text.length;) {
			if(formattingCodeAt(text, idx)) {
				code = text[idx .. idx + 3];
				idx += 3;
				continue;
			}
			idx++;
		}
		return code;
	}

	private static void preserveFormattingAfterSplit(string line, ref string text) {
		if(!text.length || formattingCodeAt(text, 0))
			return;
		string code = activeFormattingCode(line);
		if(code.length)
			text = code ~ text;
	}

	private static string nextWrappedLine(ref string text, int textWidth) {
		trimLeadingSpaces(text);
		long newlineAt = text.indexOf('\n');
		if(newlineAt >= 0) {
			string line = trimTrailingSpacesCopy(
				text[0 .. cast(size_t)newlineAt]);
			text = text[cast(size_t)newlineAt + 1 .. $];
			preserveFormattingAfterSplit(line, text);
			return line;
		}

		long forcedSplitAt = forcedHintSplitIndex(text);
		if(forcedSplitAt > 0 &&
				visibleLength(text[0 .. cast(size_t)forcedSplitAt])
					<= textWidth) {
			string line = trimTrailingSpacesCopy(
				text[0 .. cast(size_t)forcedSplitAt]);
			text = text[cast(size_t)forcedSplitAt .. $];
			return line;
		}

		if(visibleLength(text) <= textWidth) {
			string line = text;
			text = "";
			return line;
		}

		long splitAt = -1;
		size_t idx;
		size_t hardEnd;
		int visibleChars;
		while(idx < text.length && visibleChars < textWidth) {
			if(formattingCodeAt(text, idx)) {
				idx += 3;
				hardEnd = idx;
				continue;
			}
			if(text[idx] == ' ')
				splitAt = cast(long)idx;
			idx++;
			hardEnd = idx;
			visibleChars++;
		}

		if(splitAt > 0) {
			string line = text[0 .. cast(size_t)splitAt];
			text = text[cast(size_t)splitAt + 1 .. $];
			preserveFormattingAfterSplit(line, text);
			return line;
		}

		string line = text[0 .. hardEnd];
		text = text[hardEnd .. $];
		preserveFormattingAfterSplit(line, text);
		return line;
	}

	void timerEvent() {
		bool redraw;
		if(failureCounter > 0) {
			--failureCounter;
			if(!failureCounter) {
				failureMessage = "";
				redraw = true;
			}
		}
		if(counter > 0) {
			--counter;
			if(!counter) {
				informationLifetime = StatuslineInformationLifetime.timedOnly;
				helpToggleConfirmationActive = false;
				redraw = true;
			}
		}
		if(redraw)
			update();
	}

private:

	static string contextualOwnerId(string sourceFile, size_t sourceLine) {
		return contextualOwnerId(sourceFile, sourceLine, null);
	}

	static string contextualOwnerId(string sourceFile, size_t sourceLine,
			string semanticContext) {
		string owner = sourceFile ~ ":" ~ to!string(sourceLine);
		if(mainui is null)
			return owner;

		Window activeWindow = mainui.activeWindow;
		Input activeInput = mainui.activeInput;
		owner ~= format(":%s", activeWindow is null ? 0 :
			cast(size_t)cast(void*)activeWindow);
		if(semanticContext !is null)
			return owner ~ ":" ~ semanticContext;
		if(activeInput !is null && activeInput.cursor !is null) {
			owner ~= format(":%s:%s:%s", activeInput.cursor.x,
				activeInput.cursor.y, activeInput.nibble);
		}
		return owner;
	}
}

final private class Toplevel : WindowSwitcher {
	InputKeyjam inputKeyjam;
	InsTable instable;
	CmdTable cmdtable;
	WindowSwitcher bottomTabSwitcher;
	WaveTable wavetable;
	PulseTable pulsetable;
	FilterTable filtertable;
	ChordTable chordtable;
	Sequencer sequencer;
	Fplay fplay;
	UI ui;
	Hotspot[] hotspots;
	bool followplay;
	enum BOTTOM_TABLE_WAVE = 0;
	enum BOTTOM_TABLE_PULSE = 1;
	enum BOTTOM_TABLE_FILTER = 2;
	enum BOTTOM_TABLE_COMMAND = 3;
	enum BOTTOM_TABLE_CHORD = 4;
	enum TOP_WINDOW_BOTTOM_TABLES = 2;
	int waveReturnInstrument = 0;
	int waveReturnColumn = INSTRUMENT_WAVE_POINTER_COLUMN;
	int pulseReturnInstrument = 0;
	int pulseReturnColumn = INSTRUMENT_PULSE_POINTER_COLUMN;
	int filterReturnInstrument = 0;
	int filterReturnColumn = INSTRUMENT_FILTER_POINTER_COLUMN;

 	this(UI ui) {
		this.ui = ui;
		int zone1x = 0;
		int zone2x = screen.width / 2 + zone1x - 1;
		int zone1y = 4;
		int zone1h = screen.height / 2 - 5;
		int zone2y = screen.height / 2;
		int zone2h = screen.height - zone2y - 5;

		inputKeyjam = new InputKeyjam();
		sequencer = new Sequencer(Rectangle(zone1x, zone1y, screen.height - 10, zone2x - zone1x));
		fplay = new Fplay(Rectangle(zone1x, zone1y, screen.height - 10, zone2x - zone1x));
		instable = new InsTable(Rectangle(zone2x, zone1y, zone1h, 3 + 8 * 3 + 12));

		int tx = zone2x;
		wavetable = new WaveTable(Rectangle(tx, zone2y, zone2h, 8));
		tx += com.fb.border + 8;
		pulsetable = new PulseTable(Rectangle(tx, zone2y, zone2h, 14));
		tx += com.fb.border + 14;
		filtertable = new FilterTable(Rectangle(tx, zone2y, zone2h, 14));
		tx += com.fb.border + 14;
		cmdtable = new CmdTable(Rectangle(tx, zone2y, zone2h, 10));
		tx += com.fb.border + 10;

		Rectangle ca;

		if(com.fb.mode == 0) {
			ca = Rectangle(tx - 6, zone1y, zone1h, 6);
		}
		else ca = Rectangle(tx, zone2y, zone2h, 6);
		chordtable = new ChordTable(ca);
		bottomTabSwitcher = new WindowSwitcher(Rectangle(zone2x, zone2y, zone2h,
												 tx + com.fb.border + 10),
									   [cast(Window)wavetable, pulsetable,
										filtertable, cmdtable, chordtable]);

		super(Rectangle(), [cast(Window)sequencer, instable, 
					   bottomTabSwitcher]);
		{
			int x1 = 4;
			int x2 = x1 + (com.fb.mode > 0 ? 64 : 48);
			int y1 = screen.height - 4;
			
			hotspots = [
				Hotspot(Rectangle(x2 + 3, y1, 1, 30), (int b){ 
							ui.activateDialog(UI.infobar); 
						}),
				Hotspot(Rectangle(x2 + INFOBAR_SID_X_OFFSET, y1 + 1, 1,
						INFOBAR_SID_HOTSPOT_WIDTH), (int b){
						b > 1 ? audio.player.toggleSIDModel() : audio.player.nextFP(); 
					}),
				Hotspot(Rectangle(x2 + INFOBAR_RATE_MULTIPLIER_X_OFFSET,
						y1 + 1, 1, INFOBAR_RATE_MULTIPLIER_WIDTH), (int b) {
						if(b == 1)
							adjustSongMultiplier(1);
						else if(b == 3)
							adjustSongMultiplier(-1);
					}),
				Hotspot(Rectangle(x2 + INFOBAR_RATE_TIMING_X_OFFSET,
						y1 + 1, 1, INFOBAR_RATE_TIMING_WIDTH), (int b) {
						if(b == 1 || b == 3)
							audio.player.setPlaybackTiming(!audio.player.ntsc);
					})
				];
		}
			refresh();
		}

	void resetSongDerivedTableState() {
		state.activeInstrument = 0;
		instable.resetSongPosition();
		wavetable.resetSongPosition();
		pulsetable.resetSongPosition();
		filtertable.resetSongPosition();
		cmdtable.resetSongPosition();
		chordtable.resetSongPosition();
		waveReturnInstrument = 0;
		waveReturnColumn = INSTRUMENT_WAVE_POINTER_COLUMN;
		pulseReturnInstrument = 0;
		pulseReturnColumn = INSTRUMENT_PULSE_POINTER_COLUMN;
		filterReturnInstrument = 0;
		filterReturnColumn = INSTRUMENT_FILTER_POINTER_COLUMN;
	}

	private void syncProgramTablePreviewsToActiveInstrument() {
		wavetable.seekCurWave();
		wavetable.placeCurrentRowAtProgramPreviewAnchor();
		pulsetable.seekCurPulse();
		pulsetable.placeCurrentRowAtProgramPreviewAnchor();
		filtertable.seekCurFilter();
		filtertable.placeCurrentRowAtProgramPreviewAnchor();
	}

		private bool clickedInfobarSpeedAt(int x, int y, int b) {
			if(b != 1)
				return false;
			int x1 = 4;
			int y1 = screen.height - 4;
			int fieldX = x1 + INFOBAR_SPEED_LABEL_X_OFFSET;
			int valueX = x1 + INFOBAR_SPEED_VALUE_X_OFFSET;
			if(y != y1 || x < fieldX || x >= valueX + 2)
				return false;
			UI.infobar.activateSpeedOnNextOpen(x >= valueX ? x - valueX : 0);
			ui.activateDialog(UI.infobar);
			return true;
		}

		private bool clickedInfobarOctaveAt(int x, int y, int b) {
			int x1 = 4;
			int y1 = screen.height - 4;
			int fieldX = x1 + INFOBAR_OCTAVE_LABEL_X_OFFSET;
			int valueX = x1 + INFOBAR_OCTAVE_VALUE_X_OFFSET;
			if(y != y1 || x < fieldX || x >= valueX + 1)
				return false;
			if(b == 1 && x >= valueX) {
				UI.infobar.activateOctaveOnNextOpen();
				ui.activateDialog(UI.infobar);
				return true;
			}
			if(b == 1)
				state.octave = clamp(state.octave + 1, 0, 6);
			else
				state.octave = clamp(state.octave - 1, 0, 6);
			UI.infobar.update();
			return true;
		}

		private bool clickedInfobarStepAt(int x, int y, int b) {
			if(b != 1)
				return false;
			int x1 = 4;
			int y1 = screen.height - 4;
			int fieldX = x1 + INFOBAR_STEP_LABEL_X_OFFSET;
			int valueX = x1 + INFOBAR_STEP_VALUE_X_OFFSET;
			if(y != y1 || x < fieldX || x >= valueX + 1)
				return false;
			UI.infobar.activateStepOnNextOpen();
			ui.activateDialog(UI.infobar);
			return true;
		}

		private bool clickedBottomTableAt(int x, int y, int b) {
			foreach(idx, win; bottomTabSwitcher.windows) {
				if(win.area.overlaps(x, y)) {
				// In narrow layout the chord table is drawn above the bottom
				// switcher's frame, so child hits must also focus the switcher.
				if(activeWindow != bottomTabSwitcher)
					activateWindow(TOP_WINDOW_BOTTOM_TABLES);
				bottomTabSwitcher.activateWindow(idx);
				bottomTabSwitcher.activeWindow.clickedAt(x, y, b);
				return true;
			}
		}
		return false;
	}

			override void clickedAt(int x, int y, int b) {
				scope(exit) retainF6OriginMarkerForActiveDestination();
				if(UI.infobar.clickedBottomControlAt(x, y, b))
					return;
				if(clickedInfobarOctaveAt(x, y, b))
					return;
			if(clickedInfobarSpeedAt(x, y, b))
				return;
			if(clickedInfobarStepAt(x, y, b))
				return;
			if(clickedBottomTableAt(x, y, b))
				return;
			foreach(idx, win; windows) { 
			if(win.area.overlaps(x, y)) {
				if(activeWindow !is win)
					activateWindow(idx);
				activeWindow.clickedAt(x, y, b);
				if(activeWindow == sequencer)
					syncTrackOverviewSelectionFromSequencerClick();
				return;
			}
		}
		foreach(idx, spot; hotspots) {
			if(spot.area.overlaps(x, y))
				spot.callback(b);
		}
	}

	override bool mouseMotionAt(int x, int y) {
		if(activeWindow == sequencer)
			return sequencer.mouseMotionAt(x, y);
		if(activeWindow == bottomTabSwitcher)
			return bottomTabSwitcher.activeWindow.mouseMotionAt(x, y);
		if(activeWindow == instable)
			return instable.mouseMotionAt(x, y);
		return false;
	}

	override bool mouseButtonUp(int button) {
		if(activeWindow == sequencer)
			return sequencer.mouseButtonUp(button);
		if(activeWindow == bottomTabSwitcher)
			return bottomTabSwitcher.activeWindow.mouseButtonUp(button);
		if(activeWindow == instable)
			return instable.mouseButtonUp(button);
		return false;
	}

	private void syncTrackOverviewSelectionFromSequencerClick() {
		int voice, trackIndex;
		ushort trackValue;
		if(!sequencer.consumeClickedTrackEntry(voice, trackIndex, trackValue))
			return;
		ui.selectTrackOverviewBlockFromEditorClick(voice, trackIndex,
			trackValue);
	}

	private void rememberInstrumentPointerReturn(
			InstrumentPointerTarget target, int instrument, int column) {
		switch(target) {
		case InstrumentPointerTarget.wave:
			waveReturnInstrument = instrument;
			waveReturnColumn = column;
			break;
		case InstrumentPointerTarget.pulse:
			pulseReturnInstrument = instrument;
			pulseReturnColumn = column;
			break;
		case InstrumentPointerTarget.filter:
			filterReturnInstrument = instrument;
			filterReturnColumn = column;
			break;
		default:
			break;
		}
	}

	private void jumpToProgramTable(InstrumentPointerTarget target, int row) {
		activateWindow(2);
		switch(target) {
		case InstrumentPointerTarget.wave:
			bottomTabSwitcher.activateWindow(BOTTOM_TABLE_WAVE);
			wavetable.seekProgramRow(row);
			break;
		case InstrumentPointerTarget.pulse:
			bottomTabSwitcher.activateWindow(BOTTOM_TABLE_PULSE);
			pulsetable.seekProgramRow(row);
			break;
		case InstrumentPointerTarget.filter:
			bottomTabSwitcher.activateWindow(BOTTOM_TABLE_FILTER);
			filtertable.seekProgramRow(row);
			break;
		default:
			break;
		}
		input = activeWindow.input;
		refresh();
	}

	private void jumpToBottomTableRow(T)(int tableIndex, T table, int row) {
		activateWindow(TOP_WINDOW_BOTTOM_TABLES);
		bottomTabSwitcher.activateWindow(tableIndex);
		table.seekRow(row);
		input = activeWindow.input;
		refresh();
		table.showByteDescription();
	}

	bool navigateToSequenceCommandReference(
			SequenceCommandReference reference) {
		final switch(reference.kind) {
		case SequenceCommandReferenceKind.none:
			return false;
		case SequenceCommandReferenceKind.command:
			jumpToBottomTableRow(BOTTOM_TABLE_COMMAND, cmdtable,
				reference.value);
			return true;
		case SequenceCommandReferenceKind.pulse:
			jumpToProgramTable(InstrumentPointerTarget.pulse, reference.value);
			return true;
		case SequenceCommandReferenceKind.filter:
			jumpToProgramTable(InstrumentPointerTarget.filter, reference.value);
			return true;
		case SequenceCommandReferenceKind.chord:
			int physicalRow;
			if(!song.resolveChordProgramRow(reference.value, physicalRow))
				return false;
			jumpToBottomTableRow(BOTTOM_TABLE_CHORD, chordtable, physicalRow);
			return true;
		}
	}

	void jumpToChordShuffleTempo() {
		jumpToBottomTableRow(BOTTOM_TABLE_CHORD, chordtable, 0);
	}

	private void returnToInstrumentPointer(int instrument, int column) {
		activateWindow(1);
		instable.seekByte(instrument, column);
		input = activeWindow.input;
		refresh();
	}

	private bool handleInstrumentPointerEnter(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveUiTopLevelKeyboardAction(key, actionId) ||
				actionId != KeyboardActionId.uiFollowInstrumentPointer)
			return false;

		if(activeWindow == instable) {
			InstrumentPointerTarget target;
			int value, instrument, column;
			if(!instable.activeTablePointer(target, value, instrument, column))
				return false;
			rememberInstrumentPointerReturn(target, instrument, column);
			jumpToProgramTable(target, value);
			return true;
		}

		if(activeWindow != bottomTabSwitcher)
			return false;

		if(bottomTabSwitcher.activeWindow == wavetable) {
			returnToInstrumentPointer(waveReturnInstrument, waveReturnColumn);
			return true;
		}
		if(bottomTabSwitcher.activeWindow == pulsetable) {
			returnToInstrumentPointer(pulseReturnInstrument, pulseReturnColumn);
			return true;
		}
		if(bottomTabSwitcher.activeWindow == filtertable) {
			returnToInstrumentPointer(filterReturnInstrument, filterReturnColumn);
			return true;
		}
		return false;
	}

	private Window activeSequenceOriginDestinationWindow() {
		if(activeWindow == instable)
			return instable;
		if(activeWindow == bottomTabSwitcher)
			return bottomTabSwitcher.activeWindow;
		return null;
	}

	private SequenceOriginDestination activeSequenceOriginDestination() {
		Window destinationWindow = activeSequenceOriginDestinationWindow();
		if(destinationWindow is instable)
			return SequenceOriginDestination.instrument;
		if(destinationWindow is cmdtable)
			return SequenceOriginDestination.command;
		if(destinationWindow is pulsetable)
			return SequenceOriginDestination.pulse;
		if(destinationWindow is filtertable)
			return SequenceOriginDestination.filter;
		if(destinationWindow is chordtable)
			return SequenceOriginDestination.chord;
		return SequenceOriginDestination.none;
	}

	private void retainF6OriginMarkerForActiveDestination() {
		sequencer.retainF6OriginMarkerForDestination(
			activeSequenceOriginDestination());
	}

	private bool handleF6OriginReturn(Keyinfo key) {
		enum modifiers = KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI;
		if(key.raw != SDLK_RETURN || (key.mods & modifiers) != 0 ||
				windows[0] !is sequencer)
			return false;

		Window destinationWindow = activeSequenceOriginDestinationWindow();
		if(destinationWindow is null ||
				!destinationWindow.allowsF6OriginReturn())
			return false;
		SequenceOriginDestination destination =
			activeSequenceOriginDestination();
		if(destination == SequenceOriginDestination.none ||
				!sequencer.tryReturnToF6Origin(destination))
			return false;

		activateWindow(0);
		return true;
	}

	private bool handleMainWindowNavigationKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveUiTopLevelKeyboardAction(key, actionId))
			return false;

		switch(actionId) {
		case KeyboardActionId.uiMainWindowPrevious:
			activeWindowNum--;
			break;
		case KeyboardActionId.uiMainWindowNext:
			activeWindowNum++;
			break;
		default:
			return false;
		}

		if(activeWindowNum < 0)
			activeWindowNum = cast(int)(windows.length - 1);
		if(activeWindowNum >= windows.length)
			activeWindowNum %= windows.length;
		activateWindow();
		return true;
	}

	private bool handleTopLevelAdjustmentKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveUiTopLevelKeyboardAction(key, actionId))
			return false;

		switch(actionId) {
		case KeyboardActionId.uiBaseOctaveDecrease:
			if(state.octave > 0)
				state.octave--;
			return true;
		case KeyboardActionId.uiBaseOctaveIncrease:
			if(state.octave < 6)
				state.octave++;
			return true;
		case KeyboardActionId.uiInstrumentPrevious:
			if(state.allowInstabNavigation) {
				instable.stepRow(-1);
			}
			return true;
		case KeyboardActionId.uiInstrumentNext:
			if(state.allowInstabNavigation) {
				instable.stepRow(1);
			}
			return true;
		default:
			return false;
		}
	}

		private bool handleEditorUndoRedoKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveEditorUndoRedoKeyboardAction(key, actionId))
				return false;

		switch(actionId) {
		case KeyboardActionId.editorUndo:
			com.session.executeUndo();
			return true;
		case KeyboardActionId.editorRedo:
			com.session.executeRedo();
			refresh();
			return true;
		default:
			return false;
			}
		}

		private bool handleSongSpeedKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveSongSpeedKeyboardAction(key, actionId))
				return false;

			switch(actionId) {
			case KeyboardActionId.songSpeedDecrease:
				if(song.speed > 0) {
					song.speed = song.speed - 1;
					timelineSeekManager().invalidate("song_speed");
				}
				return true;
			case KeyboardActionId.songSpeedIncrease:
				if(song.speed < MAX_SONG_SPEED) {
					song.speed = song.speed + 1;
					timelineSeekManager().invalidate("song_speed");
				}
				return true;
			default:
				return false;
			}
		}

		private bool handleSongMultispeedKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveSongMultispeedKeyboardAction(key, actionId))
				return false;

			switch(actionId) {
			case KeyboardActionId.songMultispeedDecrease: {
				adjustSongMultiplier(-1);
				return true;
			}
			case KeyboardActionId.songMultispeedIncrease: {
				adjustSongMultiplier(1);
				return true;
			}
			default:
				return false;
			}
		}

		private bool handleUiHelpTextToggleKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveUiHelpTextToggleKeyboardAction(key, actionId))
				return false;

			state.displayHelp ^= 1;
			UI.statusline.displayHelpTextToggleConfirmation("Help texts " ~
				(state.displayHelp ? "enabled." : "disabled."));
			return true;
		}

		private bool handleSongClearSequencesKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveSongClearSequencesKeyboardAction(key, actionId))
				return false;

			requestClearSequencesConfirmation();
			return true;
		}

		private bool handleSongOptimizeKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveSongOptimizeKeyboardAction(key, actionId))
				return false;

			requestOptimizeSongConfirmation();
			return true;
		}

		override int keypress(Keyinfo key) {
			scope(exit) retainF6OriginMarkerForActiveDestination();
			if(handleSongSpeedKey(key))
				return OK;
			if(handleSongMultispeedKey(key))
				return OK;
			if(handleMainWindowNavigationKey(key))
				return OK;

		if(key.mods & KMOD_ALT) {
			if(handleSongClearSequencesKey(key))
				return OK;
			if(handleSongOptimizeKey(key))
				return OK;

			switch(key.raw)
			{
			case SDLK_n:
				if(key.mods & KMOD_CTRL) {
					return OK;
				}
				break;
			default:
				break;
			}
			if(handleUiHelpTextToggleKey(key))
				return OK;
		}
			else if(key.mods & KMOD_CTRL) {
				if(handleEditorUndoRedoKey(key))
					return OK;
		}
		handleTopLevelAdjustmentKey(key);
		if(handleF6OriginReturn(key))
			return OK;
		if(handleInstrumentPointerEnter(key))
			return OK;
		if(state.keyjamStatus == true) {
			inputKeyjam.keypress(key);
		}
			else {
				int r = activeWindow.keypress(key);
				if(r == RETURN || r == CANCEL) {
					assert(0);
				}
		}
		return OK;
	}	

	override int keyrelease(Keyinfo key) {
		if(state.keyjamStatus == true) {
			inputKeyjam.keyrelease(key);
		}
		return activeWindow.keyrelease(key);
	}

	override void refresh() {
		foreach(t; windows) {
			t.refresh();
			t.update();
		}
		// needed because 'input' might be messed by a subdialog
		activeWindow.activate();
	}
	
	override void update() {
		foreach(t; windows) {
			t.update();
		}
	}

	bool fplayEnabled() { return followplay; }

		void timerEvent() {
			fplay.timerEvent();
		}

		bool handleSequenceRowClipboardShortcut(Keyinfo key) {
			return activeWindow == sequencer &&
				sequencer.handleSequenceRowClipboardShortcut(key);
		}

		void showCurrentContextualHelp() {
			if(activeWindow == sequencer) {
				if(input !is null)
					input.update();
				return;
			}
			if(activeWindow == instable) {
				instable.showCurrentContextualHelp();
				return;
			}
			if(activeWindow == bottomTabSwitcher) {
				auto table = cast(Table)bottomTabSwitcher.activeWindow;
				if(table !is null)
					table.showByteDescription();
			}
		}

			bool handleNonModalEditorViewSwitchKey(Keyinfo key) {
				if(windows[0] != sequencer)
					return false;
				if(activeWindow != sequencer)
					activateWindow(0);
				return sequencer.handleNonModalEditorViewSwitchKey(key);
			}

			bool handleWorkspaceNavigationAction(KeyboardActionId actionId,
					Keyinfo key) {
				scope(exit) retainF6OriginMarkerForActiveDestination();
				switch(actionId) {
				case KeyboardActionId.sequencerViewTrackTable:
				case KeyboardActionId.sequencerViewSequenceEditor:
				case KeyboardActionId.sequencerViewTrackMap:
					return handleNonModalEditorViewSwitchKey(key);
				case KeyboardActionId.workspaceActivateSequencer:
					activateWindow(0);
					return true;
				case KeyboardActionId.workspaceActivateVoice1:
					activateWindow(0);
					sequencer.activateVoice(0);
					return true;
				case KeyboardActionId.workspaceActivateVoice2:
					activateWindow(0);
					sequencer.activateVoice(1);
					return true;
				case KeyboardActionId.workspaceActivateVoice3:
					activateWindow(0);
					sequencer.activateVoice(2);
					return true;
				case KeyboardActionId.workspaceActivateInstrument:
					activateWindow(1);
					return true;
				case KeyboardActionId.workspaceActivateWave:
					activateWindow(TOP_WINDOW_BOTTOM_TABLES);
					bottomTabSwitcher.activateWindow(BOTTOM_TABLE_WAVE);
					return true;
				case KeyboardActionId.workspaceActivatePulse:
					activateWindow(TOP_WINDOW_BOTTOM_TABLES);
					bottomTabSwitcher.activateWindow(BOTTOM_TABLE_PULSE);
					return true;
				case KeyboardActionId.workspaceActivateFilter:
					activateWindow(TOP_WINDOW_BOTTOM_TABLES);
					bottomTabSwitcher.activateWindow(BOTTOM_TABLE_FILTER);
					return true;
				case KeyboardActionId.workspaceActivateCommand:
					activateWindow(TOP_WINDOW_BOTTOM_TABLES);
					bottomTabSwitcher.activateWindow(BOTTOM_TABLE_COMMAND);
					return true;
				case KeyboardActionId.workspaceActivateChord:
					activateWindow(TOP_WINDOW_BOTTOM_TABLES);
					bottomTabSwitcher.activateWindow(BOTTOM_TABLE_CHORD);
					return true;
				case KeyboardActionId.workspaceActivateTitle:
					ui.activateDialog(UI.infobar);
					return true;
				case KeyboardActionId.workspaceActivateSpeed:
					UI.infobar.activateSpeedOnNextOpen();
					ui.activateDialog(UI.infobar);
					return true;
				default:
					return false;
				}
			}

		void setTrackEntryClipboard(int subtune, int voice,
				int startTrackIndex, int endTrackIndex,
				const(Clip)[] entries) {
			sequencer.setTrackEntryClipboard(subtune, voice,
				startTrackIndex, endTrackIndex, entries);
		}

			int trackEntryClipboardEntryCount() {
				return sequencer.trackEntryClipboardEntryCount();
			}

			void clearDocumentStructuralClipboards() {
				sequencer.clearDocumentStructuralClipboards();
				instable.clearDocumentClipboard();
			}

			bool advanceSequenceRowCopyFeedback(int ticks) {
				return sequencer.advanceSequenceRowCopyFeedback(ticks);
			}

			bool advanceSequenceRowDragAutoScroll() {
				return sequencer.advanceSequenceRowDragAutoScroll();
			}

			override bool advanceGeneratedTableRowDragAutoScroll() {
				if(activeWindow != bottomTabSwitcher)
					return false;
				return bottomTabSwitcher.activeWindow.
					advanceGeneratedTableRowDragAutoScroll();
			}

		Window windowByCoord(int x, int y) {
			foreach(idx, win; windows ~ bottomTabSwitcher.windows) {
				if(win.area.overlaps(x, y))
					return win;
		}
		return null;
	}

	void flushPendingInput() {
		sequencer.flushPendingInput();
	}

	TrackOverviewEditorCursor editorCursorForOverview(
			const(TrackOverviewLane)[] overview) {
		int voice = sequencer.activeEditorVoice();
		RowData row;
		if(!sequencer.editorRowForVoice(voice, row))
			return TrackOverviewEditorCursor();
		return trackOverviewEditorCursor(overview, voice, row.trkOffset,
			row.seqOffset);
	}

	TrackOverviewPosition[] editorVoicePositionsForOverview(
			const(TrackOverviewLane)[] overview) {
		TrackOverviewPosition[] positions;
		positions.length = TRACK_OVERVIEW_VOICE_LANES;
		foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
			RowData row;
			if(!sequencer.editorRowForVoice(cast(int)voice, row))
				continue;
			positions[voice] = trackOverviewPositionAtTrackRow(overview,
				cast(int)voice, row.trkOffset, row.seqOffset);
		}
		return positions;
	}

	int activeEditorVoice() {
		return sequencer.activeEditorVoice();
	}

	bool moveEditorCursorToOverviewPosition(
			const TrackOverviewPosition position) {
		return sequencer.moveEditorCursorToOverviewPosition(position);
	}

	bool moveEditorCursorToOverviewPositionsSafeForActiveView(
			const TrackOverviewPosition[] positions, int activeVoice) {
		return sequencer.moveEditorCursorToOverviewPositionsSafeForActiveView(
			positions, activeVoice);
	}

	bool editorOverviewGlobalRow(const(TrackOverviewLane)[] overview,
			out int globalRow) {
		return sequencer.editorOverviewGlobalRow(overview, globalRow);
	}

	bool moveEditorCursorToOverviewBlockStart(int voice, int trackIndex) {
		activateWindow(0);
		return sequencer.moveEditorCursorToTrackBlockStart(voice, trackIndex);
	}

	bool insertTrackEntryAt(int voice, int trackIndex,
			ushort expectedTrackValue, out ushort insertedTrackValue) {
		return sequencer.insertTrackEntryAt(voice, trackIndex,
			expectedTrackValue, insertedTrackValue);
	}

		bool insertNextUnusedExpandedSequenceTrackEntryAfter(int voice,
				int anchorTrackIndex, ushort expectedTrackValue,
				out int insertedTrackIndex, out ushort insertedTrackValue,
				out int insertedSequenceNumber) {
			return sequencer.insertNextUnusedExpandedSequenceTrackEntryAfter(
				voice, anchorTrackIndex, expectedTrackValue, insertedTrackIndex,
				insertedTrackValue, insertedSequenceNumber);
		}

		bool setTrackEntryToNextUnusedSequenceAt(int voice, int trackIndex,
				ushort expectedTrackValue, out ushort updatedTrackValue,
				out int updatedSequenceNumber) {
			return sequencer.setTrackEntryToNextUnusedSequenceAt(
				voice, trackIndex, expectedTrackValue, updatedTrackValue,
				updatedSequenceNumber);
		}

		bool insertCopyOfTrackEntryAt(int voice, int trackIndex,
				ushort expectedTrackValue, out ushort copiedTrackValue) {
		return sequencer.insertCopyOfTrackEntryAt(voice, trackIndex,
			expectedTrackValue, copiedTrackValue);
	}

	bool deleteTrackEntryAt(int voice, int trackIndex,
			ushort expectedTrackValue) {
		return sequencer.deleteTrackEntryAt(voice, trackIndex,
			expectedTrackValue);
	}

	bool deleteTrackEntryRangeAt(int voice, int startTrackIndex,
			int endTrackIndex, const(ushort)[] expectedTrackValues) {
		return sequencer.deleteTrackEntryRangeAt(voice, startTrackIndex,
			endTrackIndex, expectedTrackValues);
	}

	bool hasTrackEntryClipboard() {
		return sequencer.hasTrackEntryClipboard();
	}

	bool pasteTrackEntryClipboardAfter(int voice, int anchorTrackIndex,
			ushort expectedTrackValue, out int firstInsertedTrackIndex,
			out int lastInsertedTrackIndex, out int insertedCount) {
		return sequencer.pasteTrackEntryClipboardAfter(voice,
			anchorTrackIndex, expectedTrackValue, firstInsertedTrackIndex,
			lastInsertedTrackIndex, insertedCount);
	}

	bool insertTrackEntriesAt(int voice, int insertionTrackIndex,
			const(Clip)[] entries,
			out int firstInsertedTrackIndex, out int lastInsertedTrackIndex,
			out int insertedCount) {
		return sequencer.insertTrackEntriesAt(voice, insertionTrackIndex,
			entries, firstInsertedTrackIndex, lastInsertedTrackIndex,
			insertedCount);
	}

	bool moveTrackEntryWithinVoice(int voice, int sourceTrackIndex,
			int insertionTrackIndex, ushort expectedTrackValue,
			out int movedTrackIndex, out ushort movedTrackValue) {
		return sequencer.moveTrackEntryWithinVoice(voice, sourceTrackIndex,
			insertionTrackIndex, expectedTrackValue, movedTrackIndex,
			movedTrackValue);
	}

	bool moveTrackEntryRangeWithinVoice(int voice, int sourceStartTrackIndex,
			int sourceEndTrackIndex, int insertionTrackIndex,
			const(ushort)[] expectedTrackValues,
			out int movedStartTrackIndex, out int movedEndTrackIndex) {
		return sequencer.moveTrackEntryRangeWithinVoice(voice,
			sourceStartTrackIndex, sourceEndTrackIndex, insertionTrackIndex,
			expectedTrackValues, movedStartTrackIndex, movedEndTrackIndex);
	}

	bool moveTrackEntryRangeToVoice(int sourceVoice,
			int sourceStartTrackIndex, int sourceEndTrackIndex,
			int targetVoice, int insertionTrackIndex,
			const(ushort)[] expectedTrackValues,
			out int movedStartTrackIndex, out int movedEndTrackIndex) {
		return sequencer.moveTrackEntryRangeToVoice(sourceVoice,
			sourceStartTrackIndex, sourceEndTrackIndex, targetVoice,
			insertionTrackIndex, expectedTrackValues, movedStartTrackIndex,
			movedEndTrackIndex);
	}

	bool moveTrackEntryToVoice(int sourceVoice, int sourceTrackIndex,
			int targetVoice, int insertionTrackIndex,
			ushort expectedTrackValue, out int movedTrackIndex,
			out ushort movedTrackValue) {
		return sequencer.moveTrackEntryToVoice(sourceVoice, sourceTrackIndex,
			targetVoice, insertionTrackIndex, expectedTrackValue,
			movedTrackIndex, movedTrackValue);
	}

	bool setLoopTargetForVoiceAtTrackIndex(int voice, int targetTrackIndex,
			ushort expectedTrackValue) {
		return sequencer.setLoopTargetForVoiceAtTrackIndex(voice,
			targetTrackIndex, expectedTrackValue);
	}

	bool setLoopTargetsForVoiceTrackIndices(int[3] targetTrackIndex,
			ushort[3] expectedTrackValue) {
		return sequencer.setLoopTargetsForVoiceTrackIndices(targetTrackIndex,
			expectedTrackValue);
	}

	bool setLoopTargetForActiveTrackEntry() {
		return sequencer.setLoopTargetForActiveTrackEntry();
	}

	void setPlaybackMarkAtCurrentEditorPosition() {
		sequencer.setPlaybackMarkAtCurrentEditorPosition();
	}

	void setActiveVoicePlaybackMarkAtCurrentEditorPosition() {
		sequencer.setActiveVoicePlaybackMarkAtCurrentEditorPosition();
	}

	void playFromCursor() {
		flushPendingInput();
		int[3] trackIndexes, sequenceRowOffsets;
		PosDataTable playbackPos;
		if(!sequencer.cursorPlaybackPosition(trackIndexes,
				sequenceRowOffsets, playbackPos))
			return;
		audio.player.start([trackIndexes[0], trackIndexes[1],
			trackIndexes[2]], [sequenceRowOffsets[0],
			sequenceRowOffsets[1], sequenceRowOffsets[2]]);
		fplay.startFromCursor(playbackPos);
	}

	TimelineSeekResult checkpointSeekFromCursor(TimelineSeekTarget target,
			TimelineSeekOptions options) {
		flushPendingInput();
		TimelineSeekResult result =
			timelineSeekManager().seekToTarget(target, options);
		if(result.status == TimelineSeekStatus.performed)
			fplay.startFromCursor();
		return result;
	}

	bool checkpointSeekFromCurrentEditorPosition() {
		flushPendingInput();
		auto overview = buildTrackOverview(song);
		int globalRow;
		if(!editorOverviewGlobalRow(overview, globalRow))
			return false;

		TrackOverviewPosition[] positions =
			editorVoicePositionsForOverview(overview);
		if(!trackOverviewTimelinePositionsAllValid(positions))
			return false;

		TrackOverviewPosition[] timelinePositions =
			trackOverviewTimelinePositionsAtRow(overview, globalRow);
		if(!trackOverviewTimelinePositionsAllValid(timelinePositions))
			return false;

		foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
			if(positions[voice].trackIndex !=
					timelinePositions[voice].trackIndex ||
					positions[voice].sequenceRowOffset !=
					timelinePositions[voice].sequenceRowOffset)
				return false;
		}

		TimelineSeekTarget target;
		target.globalRow = globalRow;
		target.allVoicesValid = true;
		foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
			target.trackOffsets[voice] = positions[voice].trackIndex;
			target.sequenceOffsets[voice] = positions[voice].sequenceRowOffset;
		}

		TimelineSeekOptions options;
		options.inputKind = TimelineSeekInputKind.keyboard;
		options.force = true;
		options.allowThrottle = false;
		options.playbackActive =
			audio.player.isPlaying && !audio.player.keyjamEnabled;

		TimelineSeekResult result = checkpointSeekFromCursor(target, options);
		if(result.status == TimelineSeekStatus.performed)
			return true;

		return false;
	}

	bool checkpointSeekFromPlaybackMarks(int[3] trackMarks) {
		flushPendingInput();
		auto overview = buildTrackOverview(song);
		TrackOverviewPosition[TRACK_OVERVIEW_VOICE_LANES] positions;
		if(!UI.storedPlayFromPositions(overview, positions))
			return false;

		int globalRow = -1;
		foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
			if(!positions[voice].valid)
				return false;
			if(globalRow < 0) {
				globalRow = positions[voice].globalRow;
			}
			else if(positions[voice].globalRow != globalRow)
				return false;
		}

		TrackOverviewPosition[] timelinePositions =
			trackOverviewTimelinePositionsAtRow(overview, globalRow);
		if(!trackOverviewTimelinePositionsAllValid(timelinePositions))
			return false;

		foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
			if(timelinePositions[voice].trackIndex != trackMarks[voice] ||
					timelinePositions[voice].sequenceRowOffset != 0)
				return false;
		}

		TimelineSeekTarget target;
		target.globalRow = globalRow;
		target.allVoicesValid = true;
		foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
			target.trackOffsets[voice] = trackMarks[voice];
			target.sequenceOffsets[voice] = 0;
		}

		TimelineSeekOptions options;
		options.inputKind = TimelineSeekInputKind.keyboard;
		options.force = true;
		options.allowThrottle = false;
		options.playbackActive =
			audio.player.isPlaying && !audio.player.keyjamEnabled;

		TimelineSeekResult result = checkpointSeekFromCursor(target, options);
		if(result.status == TimelineSeekStatus.performed)
			return true;

		return false;
	}
	
	void reset() {
		sequencer.reset();
		sequencer.resetMark();
	}

	void startFp() {
		followplay = true;
		windows[0] = fplay;
		if(activeWindow == sequencer)
			activateWindow(0);
	}

	void startFp(int mode) {
		startFp();
		if(activeWindow == fplay)
			fplay.start(mode);
	}

	void startPlayback(int j) {
		fplay.start(j);
	}

	private void stopFp() {
		followplay = false;
		windows[0] = sequencer;
		activateWindow(activeWindowNum);
	}

	void stopPlayback() {
		fplay.stop();
		if(followplay) {
			stopFp();
			followplay = false;
			activate();
			sequencer.reset(false);
		}
	}

	private void optimizeSongConfirmed() {
		refresh();
		// TODO: VALIDATION HERE BEFORE PURGING... PurgeExpception should be useless if validate covers all errorcases
		try {
			(new Purge(song,true)).purgeAll();
			timelineSeekManager().invalidate("optimize_purge");
		}
		catch(PurgeException e) {
			UI.statusline.displayFailure(e.toString);
			return;

		}

		refresh();
		UI.statusline.displayTimedOperationFeedback(
			"Song data optimized.");
	}

		private void requestOptimizeSongConfirmation() {
			mainui.activateDialog(new ConfirmationDialog(
				"Optimise/purge unused song data (No Undo) (y/n)? ",
				(int param) {
					if(param != 0)
						return;
					optimizeSongConfirmed();
			}));
	}

	private void clearSeqsConfirmed() {
		UI.stop();
		song.clearSeqs();
		timelineSeekManager().invalidate("clear_sequences");
		mainui.clearDocumentTransientState(
			DocumentReplacementScope.sequencesOnlyReplacement);
		UI.refresh();
		reset();
		com.session.resetPlaybackPositionsToSongStart();
		sequencer.placeSequenceSongStartAtTopBoundary();
		UI.statusline.displayTimedOperationFeedback(
			"Sequence data cleared.");
	}

		private void requestClearSequencesConfirmation() {
			mainui.activateDialog(new ConfirmationDialog("Clear sequence data (No Undo) (y/n)? ",
				(int param) {
					if(param != 0)
						return;
					clearSeqsConfirmed();
			}));
	}
}
 
final class UI {
		private {
			Window dialog = null;
			Window dialogBeforeHelp = null;
			Window dialogAfterActiveClose = null;
			enum VisMode { None, Regs, Oscilloscope }
			int vismode = VisMode.Oscilloscope;
			AboutDialog aboutdialog;
			AudioSettingsDialog audiodialog;
			FileSelectorDialog loaddialog;
			SaveFileDialog savedialog;
			string pendingTimedOperationFeedbackAfterDialogClose;
		short[] oscilloscopeSamples;
		HelpSessionState helpSessionState;
		}
	static Statusline statusline;
	static Infobar infobar;
	static Toplevel toplevel;
	private static TrackOverviewScrollState trackOverviewScroll;
	private static TrackOverviewPlaybackState trackOverviewPlayback;
	private static TrackOverviewBlockSelection trackOverviewSelection;
	private static TrackOverviewSelectionState trackOverviewSelectionState;
	private static bool trackOverviewPendingSelectionReveal;
	private static TrackOverviewBlockDragState trackOverviewBlockDrag;
	private static TrackOverviewCurrentEditorBlock trackOverviewCurrentBlock;
	private static TrackOverviewFocusState trackOverviewFocus;
	bool exitRequested = false;

	this() {
		statusline = new Statusline(Rectangle(0, 1, 1));
		toplevel = new Toplevel(this);

		infobar = new Infobar(Rectangle(4, screen.height - 4, 1, screen.width - 8));
	
		int dialog_width = screen.width - 32;
		int dialog_height = screen.height - 10;
		int dialog_x = screen.width / 2 - dialog_width / 2;
		int dialog_y = screen.height / 2 - dialog_height / 2;

		loaddialog = new LoadFileDialog(Rectangle(dialog_x, dialog_y, dialog_height,
												  dialog_width), &loadCallback, &importCallback);
		savedialog = new SaveFileDialog(Rectangle(dialog_x, dialog_y, dialog_height,
												  dialog_width), &saveCallback);

		int aboutdlg_width = screen.width - 18;
		int aboutdlg_height = 14;
		int aboutdlg_x = screen.width / 2 - aboutdlg_width / 2;
		int aboutdlg_y = screen.height / 2 - aboutdlg_height / 2;

		aboutdialog = new AboutDialog(Rectangle(aboutdlg_x, aboutdlg_y,
												aboutdlg_height,
												aboutdlg_width));
		int audiodlg_width = 76;
		int audiodlg_height = 25;
		audiodialog = new AudioSettingsDialog(Rectangle(
			screen.width / 2 - audiodlg_width / 2,
			screen.height / 2 - audiodlg_height / 2,
			audiodlg_height, audiodlg_width), &applyAudioSettings);

		audio.player.setMultiplier(song.multiplier);

		if(com.fb.mode > 0)
			state.shortTitles = false;
		toplevel.activate();
		activateDialog(aboutdialog);
		update();
	}

	void requestExitConfirmation() {
		activateDialog(new ConfirmationDialog("Really exit (y/n)? ", (int param) {
			if(param != 0)
				return;
			audio.player.stop();
			exitRequested = true;
		}));
	}

	bool handleQuitConfirmAction(KeyboardActionId actionId) {
		if(actionId != KeyboardActionId.appQuitConfirm)
			return false;
		requestExitConfirmation();
		return true;
	}

	@property Window activeWindow() {
		if(dialog) return dialog;
		return toplevel.activeWindow;
	}

	@property Input activeInput() {
		if(dialog)
			return dialog.input;
		if(trackOverviewOwnsInputFocus())
			return null;
		return toplevel.activeWindow.input;
	}

	void releaseInputOwnership() {
		auto currentInput = activeInput;
		if(currentInput !is null)
			currentInput.deactivate();
	}

	private bool trackOverviewOwnsInputFocus() {
		return trackOverviewActiveKeyboardContext();
	}

	private bool trackOverviewActiveKeyboardContext() {
		return toplevel !is null && trackOverviewKeyboardContextIsActive(
			trackOverviewFocus.kind,
			toplevel.activeWindow is toplevel.sequencer,
			dialog !is null);
	}

	private int rightVisualScopePanelX() {
		return RIGHT_VISUAL_PANEL_X * FONT_X + trackOverviewLeftPadding();
	}

	private int rightVisualScopePanelWidth() {
		int panelWidth = (screen.width - RIGHT_VISUAL_PANEL_X) * FONT_X;
		int scopeWidth = panelWidth - trackOverviewLeftPadding() -
			trackOverviewRightPadding();
		return scopeWidth > 0 ? scopeWidth : 0;
	}

	private void clearRightVisualPanel() {
		int textPanelX = RIGHT_VISUAL_PANEL_X * FONT_X;
		int textPanelEnd = screen.width * FONT_X;
		int scopePanelX = rightVisualScopePanelX();
		int scopePanelEnd = scopePanelX + rightVisualScopePanelWidth();
		int clearX = scopePanelX < textPanelX ? scopePanelX : textPanelX;
		int clearEnd = scopePanelEnd > textPanelEnd ? scopePanelEnd : textPanelEnd;

		video.fillRect(clearX, trackOverviewGuiStartY(),
			clearEnd - clearX, RIGHT_VISUAL_PANEL_ROWS * FONT_Y, 0);
		foreach(row; 0 .. RIGHT_VISUAL_PANEL_ROWS)
			screen.clrtoeol(RIGHT_VISUAL_PANEL_X, row, 0);
		int invalidateX = clearX / FONT_X;
		screen.invalidateRect(invalidateX, 0,
			screen.width - invalidateX, RIGHT_VISUAL_PANEL_ROWS);
	}

	private bool handleRightVisualPanelMouseDown(
			RightVisualPanelMouseHit hit) {
		if(!hit.handled)
			return false;
		audio.player.toggleVoice(hit.voice);
		drawCurrentVisualPanel();
		return true;
	}

	private string sidRegisterValue(int idx, bool active) {
		return active ? format("%02X", audio.audio.sidreg[idx]) : "--";
	}

	private bool sidRegisterLiveValuesActive() {
		auto status = audio.player.getPlaystatus();
		return status == audio.player.Status.Play ||
			status == audio.player.Status.Keyjam;
	}

	private void drawSidRegisterPanel() {
		bool active = sidRegisterLiveValuesActive();
		int x = screen.width - 42;

		clearRightVisualPanel();
		screen.cprint(x, 0, 15, 0, "V1:");
		screen.cprint(x, 1, 15, 0, "V2:");
		screen.cprint(x, 2, 15, 0, "V3:");
		screen.cprint(x+26, 0, 15, 0, "$D415 16 17 18");

		for(int i = 0; i < 7; i++) {
			screen.cprint(x+3+i*3, 0, 5,0, sidRegisterValue(i, active));
			screen.cprint(x+3+i*3, 1, 5,0, sidRegisterValue(i+7, active));
			screen.cprint(x+3+i*3, 2, 5,0, sidRegisterValue(i+14, active));
		}

		for(int i = 0; i < 4;i++) {
			screen.cprint(x+8+21+i*3, 1, 5,0,
				sidRegisterValue(i+0x15, active));
		}
	}

	private bool oscilloscopeLiveValuesActive() {
		auto status = audio.player.getPlaystatus();
		return status == audio.player.Status.Play ||
			status == audio.player.Status.Keyjam;
	}

	private int clampPixelY(int y, int top, int height) {
		if(y < top)
			return top;
		int bottom = top + height - 1;
		if(y > bottom)
			return bottom;
		return y;
	}

	private int oscilloscopeSampleY(int sample, int center, int top,
			int height) {
		long offset = cast(long)sample * height / 65536;
		return clampPixelY(cast(int)(center - offset), top, height);
	}

	private void drawMutedOscilloscopeLabel(RightVisualPaneRect pane) {
		enum label = "Off";
		int textStart = (pane.x + FONT_X - 1) / FONT_X;
		int textEnd = (pane.x + pane.width) / FONT_X;
		int textWidth = textEnd - textStart;
		if(textWidth < label.length)
			return;
		int x = textStart + (textWidth - cast(int)label.length) / 2;
		screen.cprint(x, RIGHT_VISUAL_PANEL_ROWS / 2, 12, 0, label);
	}

	private void drawOscilloscopeTrace(RightVisualPaneRect pane, int voice,
			int copiedSamples, int sampleCount) {
		int x = pane.x + 3;
		int y = pane.y + 3;
		int width = pane.width - 6;
		int height = pane.height - 6;
		if(width <= 0 || height <= 0)
			return;

		int center = y + height / 2;
		bool muted = audio.player.muted[voice] != 0;
		if(muted || copiedSamples <= 1) {
			int centerColor = muted ? 11 : 5;
			video.drawHLine(x, center, width, centerColor);
			return;
		}

		int traceColor = 13;
		int sampleStart = sampleCount - copiedSamples;
		int sampleBase = voice * sampleCount + sampleStart;
		long sampleSum = 0;
		foreach(i; 0 .. copiedSamples)
			sampleSum += oscilloscopeSamples[sampleBase + i];
		int sampleMean = cast(int)(sampleSum / copiedSamples);
		int previousTop = 0;
		int previousBottom = 0;
		bool hasPreviousColumn = false;
		foreach(px; 0 .. width) {
			int s0 = copiedSamples * px / width;
			int s1 = copiedSamples * (px + 1) / width;
			if(s1 <= s0)
				s1 = s0 + 1;
			if(s1 > copiedSamples)
				s1 = copiedSamples;

			int minSample = int.max;
			int maxSample = int.min;
			foreach(i; s0 .. s1) {
				long centeredSample = oscilloscopeSamples[sampleBase + i] -
					sampleMean;
				int sample = cast(int)(centeredSample *
					OSCILLOSCOPE_DISPLAY_GAIN_NUM /
					OSCILLOSCOPE_DISPLAY_GAIN_DEN);
				if(sample < minSample)
					minSample = sample;
				if(sample > maxSample)
					maxSample = sample;
			}

			int top = oscilloscopeSampleY(maxSample, center, y, height);
			int bottom = oscilloscopeSampleY(minSample, center, y, height);
			if(top > bottom) {
				int tmp = top;
				top = bottom;
				bottom = tmp;
			}
			if(hasPreviousColumn) {
				if(previousBottom + 1 < top) {
					video.drawVLine(x + px, previousBottom,
						top - previousBottom + 1, traceColor);
				}
				else if(bottom + 1 < previousTop) {
					video.drawVLine(x + px, bottom,
						previousTop - bottom + 1, traceColor);
				}
			}
			video.drawVLine(x + px, top, bottom - top + 1, traceColor);
			previousTop = top;
			previousBottom = bottom;
			hasPreviousColumn = true;
		}
	}

	private void drawOscilloscopePanel() {
		clearRightVisualPanel();
		video.syncScreenToFramebuffer();
		int panelX = rightVisualScopePanelX();
		int panelY = trackOverviewGuiStartY();
		int panelWidth = rightVisualScopePanelWidth();
		int panelHeight = RIGHT_VISUAL_PANEL_ROWS * FONT_Y;
		video.fillRect(panelX, panelY, panelWidth, panelHeight, 0);

		bool live = oscilloscopeLiveValuesActive();
		int sampleCount = audio.audio.oscilloscopeSampleCapacity();
		int copiedSamples = 0;
		if(live && sampleCount > 0) {
			int requiredSamples = audio.audio.OSCILLOSCOPE_VOICES *
				sampleCount;
			if(oscilloscopeSamples.length != requiredSamples)
				oscilloscopeSamples.length = requiredSamples;
			copiedSamples = audio.audio.copyOscilloscopeSamples(
				oscilloscopeSamples, sampleCount);
		}

		foreach(voice; 0 .. RIGHT_VISUAL_PANE_COUNT) {
			auto pane = rightVisualPaneRect(voice, screen.width, FONT_X, FONT_Y);
			if(pane.width < 4 || pane.height < 4)
				continue;
			bool muted = audio.player.muted[voice] != 0;
			int x = pane.x + 1;
			int y = pane.y + 1;
			int width = pane.width - 2;
			int height = pane.height - 2;
			int fillColor = muted ? 0 : 11;
			int borderColor = muted ? 11 : 12;
			video.fillRect(x, y, width, height, fillColor);
			video.drawHLine(x, y, width, borderColor);
			video.drawHLine(x, y + height - 1, width, borderColor);
			video.drawVLine(x, y, height, borderColor);
			video.drawVLine(x + width - 1, y, height, borderColor);
			drawOscilloscopeTrace(pane, voice, live ? copiedSamples : 0,
				sampleCount);
			if(muted)
				drawMutedOscilloscopeLabel(pane);
		}
	}

	private void drawCurrentVisualPanel() {
		if(vismode == VisMode.Oscilloscope) {
			drawOscilloscopePanel();
			return;
		}
		if(vismode != VisMode.Regs)
			vismode = VisMode.Regs;
		drawSidRegisterPanel();
	}

		void timerEvent(int n) {
			Exception e = audio.callback.getException();
			if(e !is null) {
			writeln("error" ~ e.toString());
			audio.player.stop();
			statusline.displayFailure(e.toString());
		}
		if((tickcounter3 >= 0) && ++tickcounter3 > 20) {
			escapecounter = 0;
			infobar.update();
			tickcounter3 = -1;
			}
			statusline.timerEvent();
			if(toplevel.advanceSequenceRowCopyFeedback(n)) {
				noteMeaningfulStatuslineInteraction();
				update();
			}
			if(dialog is null && toplevel.advanceSequenceRowDragAutoScroll()) {
				noteMeaningfulStatuslineInteraction();
				update();
			}
			if(dialog is null && toplevel.advanceGeneratedTableRowDragAutoScroll()) {
				noteMeaningfulStatuslineInteraction();
				update();
			}
			if(handleTrackOverviewBlockDragAutoScroll()) {
				noteMeaningfulStatuslineInteraction();
				update();
			}
		tickcounter1 += n;
		if(tickcounter1 >= UPDATE_RATE) {
			infobar.update();
			if(dialog) dialog.update();
			tickcounter1 = 0;
			toplevel.timerEvent();

			if(audio.player.isPlaying || audio.player.keyjamEnabled) {
				update();  // TESTME: just do video.updateFrame()
			}
			else {
				drawCurrentVisualPanel();
			}
		}
		if(vismode == VisMode.Oscilloscope &&
		   (audio.player.isPlaying || audio.player.keyjamEnabled))
			video.drawVisualizer(n);
	}

	private void toggleVisualMode() {
		vismode = vismode == VisMode.Regs ?
			VisMode.Oscilloscope : VisMode.Regs;
		drawCurrentVisualPanel();
	}

	void update() {
		infobar.update();
		toplevel.update();
		if(dialog)
			dialog.update();
		drawTrackOverviewStrip();
		drawCurrentVisualPanel();
	}

	private void noteMeaningfulStatuslineInteraction() {
		if(statusline !is null)
			statusline.noteMeaningfulInteraction();
	}

	private bool noteMeaningfulStatuslineInteractionIf(bool handled) {
		if(handled)
			noteMeaningfulStatuslineInteraction();
		return handled;
	}

	private void F1orF2(Keyinfo key, bool fromStart) {
		toplevel.flushPendingInput();
		if(audio.player.isPlaying) {
			if(key.mods & KMOD_SHIFT) { // already playing, reinit tracking
				stop(false);
				toplevel.startFp();
				return;
			}
			else if(toplevel.fplayEnabled()) { // drop tracking
				stop(false);
				seqPos.copyFrom(fplayPos);
				toplevel.stopFp();
				return;
			}
			// song is playing but plain F1 pressed; restart
		}
		int m1, m2, m3;
		m1 = seqPos.pos[0].mark;
		m2 = seqPos.pos[1].mark;
		m3 = seqPos.pos[2].mark;
		stop();
		if(!fromStart) {
			if(!toplevel.checkpointSeekFromPlaybackMarks([m1, m2, m3]))
				audio.player.start([m1, m2, m3], [0, 0, 0]);
			if(key.mods & KMOD_SHIFT) {
				toplevel.startFp();
			}
			toplevel.startPlayback(Jump.toMark);
		}
		else {
			audio.player.start();
			if(key.mods & KMOD_SHIFT) {
				toplevel.startFp(Jump.toBeginning);
			}
			toplevel.startPlayback(Jump.toBeginning);
		}
	}

	private bool executeUiGlobalAction(KeyboardActionId actionId) {
		switch(actionId) {
		case KeyboardActionId.uiToggleFullscreen:
			video.toggleFullscreen();
			return true;
		case KeyboardActionId.uiToggleInterpolation:
			audio.player.interpolate ^= 1;
			audio.player.init();
			return true;
		case KeyboardActionId.playbackTrackingToggle:
			if(!audio.player.isPlaying)
				return true;
			if(toplevel.fplayEnabled()) {
				stop(false);
				seqPos.copyFrom(fplayPos);
				toplevel.stopFp();
				statusline.displayOperationFeedback("Tracking off.");
			}
			else {
				stop(false);
				toplevel.startFp();
				statusline.displayOperationFeedback("Tracking on.");
			}
			return true;
		case KeyboardActionId.playbackFastForwardLarge:
			audio.player.fastForward(25);
			return true;
		case KeyboardActionId.playbackFastForward:
			audio.player.fastForward(5);
			return true;
		default:
			return false;
		}
	}

	private bool handleUiGlobalKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveUiGlobalKeyboardAction(key, actionId))
			return false;
		return executeUiGlobalAction(actionId);
	}

	private bool handleQuitConfirmKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveQuitConfirmKeyboardAction(key, actionId))
			return false;
		if(dialog || activeWindow == infobar)
			return false;
		if(++escapecounter <= 1) {
			tickcounter3 = 0;
			return false;
		}
		handleQuitConfirmAction(actionId);
		return true;
	}

		int keypress(Keyinfo key) {
				noteMeaningfulStatuslineInteraction();
				bool skip_imm_keypress = false; //workaround for F11 - crapchars in savedialog
			handleTrackOverviewBlockDragModifierChange(key);
					if(handleActiveHelpDialogKey(key))
						return OK;
					if(handleGlobalOpenHelpKey(key))
						return OK;
					if(handleTrueModalDialogPriorityKey(key))
						return OK;
					if(handleWorkspaceNavigationKey(key))
						return OK;
					if(handleActiveDialogPriorityKey(key))
						return OK;
				if(isEditorViewActivationKey(key))
					setTrackOverviewEditorFocus(trackOverviewFocus);
				if(trackOverviewActiveKeyboardContext() &&
						handleTrackOverviewFocusedKey(key))
					return OK;
				if(handleSequencerFocusedStructuralKey(key))
					return OK;
				if(handleSequencerPlaybackMarkKey(key))
					return OK;
				if(handleSequenceRowClipboardShortcut(key))
					return OK;
		if(trackOverviewActiveKeyboardContext()) {
			if(handleTrackOverviewScrollKey(key))
				return OK;
			if(handleTrackOverviewBlockInsertCopyKey(key))
				return OK;
			if(handleTrackOverviewBlockInsertKey(key))
				return OK;
			if(handleTrackOverviewBlockDeleteKey(key))
				return OK;
			if(handleTrackOverviewBlockNavigationKey(key))
				return OK;
		}

		if(key.mods & KMOD_ALT) {
			if(handleSongMultispeedKey(key))
				return OK;
			handleUiGlobalKey(key);
			}
			else if(key.mods & KMOD_CTRL) {
				if(!handleVoiceMuteKey(key) &&
						!handleAppFileDialogKey(key, skip_imm_keypress) &&
						!handleDocumentedMaintenanceKey(key))
					handleUiGlobalKey(key);
				if(handleSongKeyjamToggleKey(key))
					return OK;
		}
				else {
					if(!handlePlaybackTransportKey(key) &&
							!handleAppFileDialogKey(key, skip_imm_keypress)) {
						handleUiGlobalKey(key);
						if(handleQuitConfirmKey(key))
							return OK;
					}
				}
			if(dialog && !skip_imm_keypress) {
				dispatchActiveDialogKey(key);
			}
			else {
				toplevel.keypress(key);
				}
					return OK;
				}

					private bool handleAppFileDialogKey(Keyinfo key,
							ref bool skip_imm_keypress) {
					KeyboardActionId actionId;
					if(!resolveAppFileDialogKeyboardAction(key, actionId))
						return false;

					switch(actionId) {
					case KeyboardActionId.appAbout:
						activateDialog(aboutdialog);
						return true;
					case KeyboardActionId.appAudioSettings:
						openAudioSettingsDialog();
						return true;
					case KeyboardActionId.fileLoadDialog:
						openSongLoadDialog();
						return true;
					case KeyboardActionId.fileSaveExportDialog:
						openSongSaveExportDialog();
						skip_imm_keypress = true;
						return true;
					case KeyboardActionId.fileQuickSave:
						toplevel.flushPendingInput();
						savedialog.syncFilenameToFormat();
						string s = savedialog.filename;
						if(s == "")
							statusline.displayFailure(
								"Cannot Quicksave; give filename first by doing a regular save.");
						else {
							if(saveToPath(s))
								statusline.displayTimedOperationFeedback(
									format("Save complete: \"%s\".", s));
						}
						return true;
				default:
					return false;
				}
				}

	private bool instrumentSettingsContext() {
		return toplevel.activeWindow is toplevel.instable &&
			toplevel.instable.instrumentSettingsFocused();
	}

	void openContextualLoadDialog() {
		if(instrumentSettingsContext()) {
			toplevel.instable.openInstrumentLoadDialog();
			return;
		}
		openSongLoadDialog();
	}

	void openContextualSaveDialog() {
		if(instrumentSettingsContext()) {
			toplevel.instable.openInstrumentSaveDialog();
			return;
		}
		openSongSaveExportDialog();
	}

	private void openSongLoadDialog() {
		activateDialog(loaddialog);
	}

	private void openSongSaveExportDialog() {
		toplevel.flushPendingInput();
		activateDialog(savedialog);
	}

	void openAudioSettingsDialog() {
		activateDialog(audiodialog);
	}

				private bool handleDocumentedMaintenanceKey(Keyinfo key) {
					KeyboardActionId actionId;
					if(!resolveDocumentedMaintenanceKeyboardAction(key, actionId))
						return false;

					switch(actionId) {
					case KeyboardActionId.songSidModelToggle:
						song.sidModel ^= 1;
						audio.player.setSidModel(song.sidModel);
						return true;
					case KeyboardActionId.songSidFilterPresetNext:
						audio.player.nextFP();
						return true;
					case KeyboardActionId.songSidFilterPresetPrevious:
						audio.player.prevFP();
						return true;
					case KeyboardActionId.uiVisualModeToggle:
						toggleVisualMode();
						return true;
					default:
						return false;
					}
				}

				private string applyAudioSettings() {
					auto result = audio.player.applyPendingAudioConfiguration();
					if(result.status != AudioRestartStatus.applied)
						statusline.displayFailure(result.message);
					infobar.update();
					drawCurrentVisualPanel();
					return result.message;
				}

					private bool handleSongMultispeedKey(Keyinfo key) {
					KeyboardActionId actionId;
				if(!resolveSongMultispeedKeyboardAction(key, actionId))
					return false;

				switch(actionId) {
				case KeyboardActionId.songMultispeedDecrease: {
					adjustSongMultiplier(-1);
					return true;
				}
				case KeyboardActionId.songMultispeedIncrease: {
					adjustSongMultiplier(1);
					return true;
				}
				default:
					return false;
				}
			}

			private bool handleSongKeyjamToggleKey(Keyinfo key) {
				if(dialog !is null || activeWindow == infobar)
					return false;

				KeyboardActionId actionId;
				if(!resolveSongKeyjamToggleKeyboardAction(key, actionId))
					return false;
				return toggleKeyjamMode();
			}

				private bool handleSequenceRowClipboardShortcut(Keyinfo key) {
					if(dialog !is null || toplevel is null)
						return false;
				return toplevel.handleSequenceRowClipboardShortcut(key);
			}

			private bool handleActiveHelpDialogKey(Keyinfo key) {
				HelpDialog helpDialog = cast(HelpDialog)dialog;
				if(helpDialog is null)
					return false;
				KeyboardActionId actionId;
				if(resolveGlobalKeyboardAction(key, actionId) &&
						actionId == KeyboardActionId.globalOpenHelp)
					return false;
				int r = helpDialog.keypress(key);
				if(r != OK)
					closeDialog();
				return true;
			}

			private bool handleGlobalOpenHelpKey(Keyinfo key) {
				KeyboardActionId actionId;
				if(!resolveGlobalKeyboardAction(key, actionId))
				return false;
			if(actionId != KeyboardActionId.globalOpenHelp)
				return false;

			openContextHelp();
			return true;
		}

		private bool workspaceActionIsSequencerView(KeyboardActionId actionId) {
			return actionId == KeyboardActionId.sequencerViewTrackTable ||
				actionId == KeyboardActionId.sequencerViewSequenceEditor ||
				actionId == KeyboardActionId.sequencerViewTrackMap;
		}

			private bool handleWorkspaceNavigationKey(Keyinfo key) {
				KeyboardActionId actionId;
				if(!resolveWorkspaceNavigationKeyboardAction(key, actionId))
					return false;

				if(dialog !is null) {
					if(dialog != infobar)
						return false;
					closeDialog(false);
				}
				else if(workspaceActionIsSequencerView(actionId) &&
						activeWindow == toplevel.sequencer)
					return false;

				if(workspaceActionIsSequencerView(actionId))
					setTrackOverviewEditorFocus(trackOverviewFocus);
				return toplevel.handleWorkspaceNavigationAction(actionId, key);
			}

		private bool handlePlaybackTransportKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolvePlaybackTransportKeyboardAction(key, actionId))
				return false;

			switch(actionId) {
			case KeyboardActionId.playbackPlayFromMark:
			case KeyboardActionId.playbackPlayFromMarkTracking:
				F1orF2(key, false);
				return true;
			case KeyboardActionId.playbackPlayFromStart:
			case KeyboardActionId.playbackPlayFromStartTracking:
				F1orF2(key, true);
				return true;
			case KeyboardActionId.playbackPlayFromCursor:
				playFromCurrentEditorPositionAccurate();
				return true;
			case KeyboardActionId.playbackStop:
				if(toplevel.fplayEnabled())
					seqPos.copyFrom(fplayPos);
				stop();
				if(toplevel.fplayEnabled())
					toplevel.stopFp();
				return true;
			default:
				return false;
			}
		}

		private bool handleVoiceMuteKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveVoiceMuteKeyboardAction(key, actionId))
				return false;

			switch(actionId) {
			case KeyboardActionId.voiceToggleMute1:
				audio.player.toggleVoice(0);
				return true;
			case KeyboardActionId.voiceToggleMute2:
				audio.player.toggleVoice(1);
				return true;
			case KeyboardActionId.voiceToggleMute3:
				audio.player.toggleVoice(2);
				return true;
			default:
				return false;
			}
		}

			private bool handleActiveDialogPriorityKey(Keyinfo key) {
				if(dialog == infobar && infobar.inlineEditActive()) {
					if(key.mods & (KMOD_CTRL | KMOD_ALT | KMOD_GUI))
						return false;
					dispatchActiveDialogKey(key);
					return true;
				}
				return false;
			}

			private bool handleTrueModalDialogPriorityKey(Keyinfo key) {
				auto saveDialog = cast(SaveFileDialog)dialog;
				if(saveDialog !is null)
					return saveDialog.handleModalPriorityKey(key);
				return false;
			}

			private int dispatchActiveDialogKey(Keyinfo key) {
				if(dialog is null)
					return OK;
				if(key.mods & KMOD_ALT)
					return OK;
				bool jumpToChordShuffleTempo = dialog == infobar &&
					infobar.consumeSpeedChordJumpRequest();
				int r = dialog.keypress(key);
				if(r != OK) {
					jumpToChordShuffleTempo = jumpToChordShuffleTempo ||
						(dialog == infobar &&
						 infobar.consumeSpeedChordJumpRequest());
					closeDialog();
					if(dialogAfterActiveClose !is null) {
						Window nextDialog = dialogAfterActiveClose;
						dialogAfterActiveClose = null;
						activateDialog(nextDialog);
					}
					if(jumpToChordShuffleTempo)
						toplevel.jumpToChordShuffleTempo();
					flushPendingTimedOperationFeedbackAfterDialogClose();
				}
				return r;
			}

		private bool isEditorViewActivationKey(Keyinfo key) {
			KeyboardActionId actionId;
			if(!resolveSequencerKeyboardAction(key, actionId))
				return false;

			return actionId == KeyboardActionId.sequencerViewTrackTable ||
				actionId == KeyboardActionId.sequencerViewSequenceEditor ||
				actionId == KeyboardActionId.sequencerViewTrackMap;
		}

	private bool handleSequencerFocusedStructuralKey(Keyinfo key) {
		if(dialog !is null || activeWindow != toplevel.sequencer)
			return false;
		return toplevel.sequencer.handleFocusedStructuralKey(key);
	}

	private bool handleSequencerPlaybackMarkKey(Keyinfo key) {
		if(dialog !is null || activeWindow != toplevel.sequencer)
			return false;

		KeyboardActionId actionId;
		if(!resolveSequencerKeyboardAction(key, actionId))
			return false;

		switch(actionId) {
		case KeyboardActionId.sequencerPlaybackMarkSet:
			toplevel.setPlaybackMarkAtCurrentEditorPosition();
			break;
		case KeyboardActionId.sequencerPlaybackMarkSetActiveVoice:
			toplevel.setActiveVoicePlaybackMarkAtCurrentEditorPosition();
			break;
		default:
			return false;
		}

		drawTrackOverviewStrip();
		return true;
	}

	private bool handleTrackOverviewFocusedKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind == TrackOverviewFocusKind.Editor)
			return false;

		if(handleTrackOverviewFocusedGlobalKey(key))
			return true;
		if(handleTrackOverviewLoopTargetKey(key))
			return true;
		if(handleTrackOverviewBlockCopyKey(key))
			return true;
		if(handleTrackOverviewBlockPasteKey(key))
			return true;
		if(handleTrackOverviewBlockFindUnusedSequenceKey(key))
			return true;
		if(handleTrackOverviewScrollKey(key))
			return true;
		if(trackOverviewFocus.kind == TrackOverviewFocusKind.Timeline) {
			if(handleTrackOverviewTimelineInertDeleteKey(key))
				return true;
			if(handleTrackOverviewTimelineNavigationKey(key))
				return true;
		}
		if(trackOverviewFocus.kind == TrackOverviewFocusKind.Block) {
			if(handleTrackOverviewOpenActiveBlockKey(key))
				return true;
			if(handleTrackOverviewBlockInsertCopyKey(key))
				return true;
			if(handleTrackOverviewBlockInsertKey(key))
				return true;
			if(handleTrackOverviewBlockDeleteKey(key))
				return true;
			if(handleTrackOverviewBlockNavigationKey(key))
				return true;
		}

		return false;
	}

	private bool handleTrackOverviewTimelineInertDeleteKey(Keyinfo key) {
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Timeline)
			return false;

		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId))
			return false;

		return actionId == KeyboardActionId.trackOverviewDeleteSelection;
	}

	private bool handleTrackOverviewTimelineNavigationKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Timeline)
			return false;

		bool absoluteTarget;
		int targetRow;
		int rowDelta;
		if(!trackOverviewTimelineScrubKeyAction(key, song.highlight,
				absoluteTarget, targetRow, rowDelta))
			return false;

		auto overview = buildTrackOverview(song);
		int lastRow = trackOverviewLastTimelineRow(overview);
		if(lastRow < 0)
			return true;
		if(absoluteTarget && targetRow < 0)
			targetRow = lastRow;

		int currentRow;
		if(!absoluteTarget) {
			if(!toplevel.editorOverviewGlobalRow(overview, currentRow))
				return true;
			targetRow = currentRow + rowDelta;
		}

		if(targetRow < 0)
			targetRow = 0;
		if(targetRow > lastRow)
			targetRow = lastRow;
		if(!absoluteTarget && targetRow == currentRow)
			return true;

		if(!moveTrackOverviewTimelineToRow(overview, targetRow))
			return true;

		setTrackOverviewTimelineFocus(trackOverviewFocus);
		displayTrackOverviewQuickHelp();
		return true;
	}

	private static bool trackOverviewTimelineScrubKeyAction(Keyinfo key,
			int highlight, out bool absoluteTarget, out int targetRow,
			out int rowDelta) {
		absoluteTarget = false;
		targetRow = 0;
		rowDelta = 0;

		KeyboardActionId actionId;
		if(!resolveTrackOverviewTimelineKeyboardAction(key, actionId))
			return false;

		int pageStep = seq.sequencer.PAGESTEP * highlight;
		if(pageStep < 1)
			pageStep = 1;
		int shiftedPageStep = 2 * pageStep;

		switch(actionId) {
		case KeyboardActionId.trackOverviewTimelineStepLeft:
			rowDelta = -1;
			return true;
		case KeyboardActionId.trackOverviewTimelineStepRight:
			rowDelta = 1;
			return true;
		case KeyboardActionId.trackOverviewTimelinePageUp:
			rowDelta = -pageStep;
			return true;
		case KeyboardActionId.trackOverviewTimelinePageDown:
			rowDelta = pageStep;
			return true;
		case KeyboardActionId.trackOverviewTimelineLargePageUp:
			rowDelta = -shiftedPageStep;
			return true;
		case KeyboardActionId.trackOverviewTimelineLargePageDown:
			rowDelta = shiftedPageStep;
			return true;
		case KeyboardActionId.trackOverviewTimelineHome:
			absoluteTarget = true;
			targetRow = 0;
			return true;
		case KeyboardActionId.trackOverviewTimelineEnd:
			absoluteTarget = true;
			targetRow = -1;
			return true;
		default:
			return false;
		}
	}

	private static bool moveTrackOverviewTimelineToRow(
			const(TrackOverviewLane)[] overview, int row) {
		if(song is null || toplevel is null)
			return false;

		int activeVoice = toplevel.activeEditorVoice();
		if(activeVoice < 0 || activeVoice >= cast(int)overview.length)
			return false;

		TrackOverviewPosition[] positions =
			trackOverviewTimelinePositionsAtRow(overview, row);
		if(activeVoice >= cast(int)positions.length)
			return false;

		TrackOverviewPosition position = trackOverviewTimelineBestPosition(
			positions, activeVoice);
		if(!position.valid)
			return false;
		bool playbackActive = trackOverviewPlaybackActive();
		bool allVoicesValid = trackOverviewTimelinePositionsAllValid(positions);
		if(playbackActive && !allVoicesValid)
			return false;

		if(allVoicesValid) {
			if(!toplevel.moveEditorCursorToOverviewPositionsSafeForActiveView(
					positions, activeVoice))
				return false;
		}
		else if(!toplevel.moveEditorCursorToOverviewPosition(position))
			return false;

		clearTrackOverviewManualScroll(trackOverviewScroll);
		if(playbackActive)
			playFromCurrentEditorPosition();
		return true;
	}

	private bool handleTrackOverviewLoopTargetKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block)
			return false;
		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId))
			return false;
		if(actionId != KeyboardActionId.trackOverviewLoopAllVoices &&
				actionId != KeyboardActionId.trackOverviewLoopActiveVoice)
			return false;
		if(trackOverviewPlaybackActive())
			return true;

		auto overview = buildTrackOverview(song);
		validateTrackOverviewBlockSelection(trackOverviewSelection, overview);
		syncTrackOverviewSelectionState(overview);
		if(actionId == KeyboardActionId.trackOverviewLoopAllVoices)
			return setTrackOverviewAllVoiceLoopTargets(overview);

		if(trackOverviewSelection.valid) {
			toplevel.setLoopTargetForVoiceAtTrackIndex(
				trackOverviewSelection.voice,
				trackOverviewSelection.trackIndex,
				trackOverviewSelection.trackValue);
			return true;
		}

		toplevel.setLoopTargetForActiveTrackEntry();
		return true;
	}

	private static bool setTrackOverviewAllVoiceLoopTargets(
			const(TrackOverviewLane)[] overview) {
		if(!trackOverviewSelection.valid)
			return true;

		int row;
		if(!trackOverviewSelectionStartRow(overview, trackOverviewSelection, row))
			return true;

		TrackOverviewPosition[] positions =
			trackOverviewTimelinePositionsAtRow(overview, row);
		if(!trackOverviewTimelinePositionsAllValid(positions))
			return true;

		int[TRACK_OVERVIEW_VOICE_LANES] trackIndexes;
		ushort[TRACK_OVERVIEW_VOICE_LANES] trackValues;
		foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
			if(positions[voice].trackIndex < 0)
				return true;
			trackIndexes[voice] = positions[voice].trackIndex;
			trackValues[voice] = positions[voice].trackValue;
		}

		toplevel.setLoopTargetsForVoiceTrackIndices(trackIndexes, trackValues);
		return true;
	}

	private static bool trackOverviewSelectionStartRow(
			const(TrackOverviewLane)[] overview,
			const TrackOverviewBlockSelection selection, out int row) {
		row = -1;
		if(!selection.valid || selection.voice < 0 ||
				selection.voice >= cast(int)overview.length)
			return false;

		auto lane = overview[selection.voice];
		if(selection.blockIndex >= 0 &&
				selection.blockIndex < cast(int)lane.blocks.length) {
			auto block = lane.blocks[selection.blockIndex];
			if(block.trackIndex == selection.trackIndex &&
					block.trackValue == selection.trackValue) {
				row = block.startRow;
				return true;
			}
		}

		foreach(block; lane.blocks) {
			if(block.trackIndex != selection.trackIndex ||
					block.trackValue != selection.trackValue)
				continue;
			row = block.startRow;
			return true;
		}
		return false;
	}

	private bool handleTrackOverviewFocusedGlobalKey(Keyinfo key) {
		KeyboardActionId uiActionId;
		if(resolveUiGlobalKeyboardAction(key, uiActionId)) {
			switch(uiActionId) {
			case KeyboardActionId.uiToggleInterpolation:
				return executeUiGlobalAction(uiActionId);
			default:
				break;
			}
		}

		if(key.mods & KMOD_ALT) {
			switch(key.raw) {
			case SDLK_F1:
			case SDLK_F2:
			case SDLK_F3:
			case SDLK_F4:
				return true;
			default:
				return false;
			}
		}

			if(key.mods & KMOD_CTRL) {
				if(handleVoiceMuteKey(key))
					return true;
				if(handleTrackOverviewUndoRedoKey(key))
					return true;
				if(handleDocumentedMaintenanceKey(key))
					return true;
				if(handleTrackOverviewPlaybackMarkKey(key))
					return true;

				switch(key.raw) {
				case SDLK_F4:
				case SDLK_F12:
				return true;
				default:
					return false;
				}
			}

			return handlePlaybackTransportKey(key);
		}

	private bool handleTrackOverviewPlaybackMarkKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;

		KeyboardActionId actionId;
		if(!resolveSequencerKeyboardAction(key, actionId))
			return false;

		switch(actionId) {
		case KeyboardActionId.sequencerPlaybackMarkSet:
			toplevel.setPlaybackMarkAtCurrentEditorPosition();
			break;
		case KeyboardActionId.sequencerPlaybackMarkSetActiveVoice:
			toplevel.setActiveVoicePlaybackMarkAtCurrentEditorPosition();
			break;
		default:
			return false;
		}

		drawTrackOverviewStrip();
		return true;
	}

	private bool handleTrackOverviewUndoRedoKey(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveTrackOverviewFocusedKeyboardAction(key, actionId))
			return false;

		switch(actionId) {
		case KeyboardActionId.trackOverviewUndo:
			com.session.executeUndo();
			refresh();
			return true;
		case KeyboardActionId.trackOverviewRedo:
			com.session.executeRedo();
			refresh();
			return true;
		default:
			return false;
		}
	}

	void openContextHelp() {
		openHelpDialog(currentHelpContext());
	}

	private void openHelpDialog(ContextHelp ctx) {
		auto activeHelp = cast(HelpDialog)dialog;
		if(activeHelp !is null) {
			activeHelp.switchToContext(ctx);
			activeHelp.update();
			return;
		}
		int helpdlg_width = screen.width - 10;
		int helpdlg_height = 36;
		int helpdlg_x = screen.width / 2 - helpdlg_width / 2;
		int helpdlg_y = screen.height / 2 - helpdlg_height / 2;
		HelpDialog helpdialog =
			new HelpDialog(Rectangle(helpdlg_x, helpdlg_y,
									  helpdlg_height,
									  helpdlg_width), ctx, &helpSessionState);
		enableKeyjamMode(false);
		if(dialog !is null) {
			if(cast(HelpDialog)dialog is null) {
				dialog.deactivate();
				dialogBeforeHelp = dialog;
			}
			else {
				dialog.deactivate();
			}
			dialog = helpdialog;
			helpdialog.activate();
			return;
		}
		activateDialog(helpdialog);
	}

	private ContextHelp currentHelpContext() {
		if(dialog !is null)
			return dialog.contextHelp;
		switch(trackOverviewFocus.kind) {
		case TrackOverviewFocusKind.Timeline:
		case TrackOverviewFocusKind.Block:
			return ui.help.HELPTRACKOVERVIEW;
		default:
			return ui.help.contextualHelpForFocusedFamily(
				currentFocusedHelpFamily(), activeWindow.contextHelp);
		}
	}

	private ui.help.FocusedHelpFamily currentFocusedHelpFamily() {
		auto sequenceInput = cast(InputSeq)activeInput;
		if(sequenceInput is null)
			return ui.help.FocusedHelpFamily.unknown;

		switch(sequenceInput.currentNavigationColumn) {
		case InputSeq.noteColumn:
		case InputSeq.octaveColumn:
			return ui.help.FocusedHelpFamily.sequenceNote;
		case InputSeq.instrumentColumn:
			return ui.help.FocusedHelpFamily.sequenceInstrument;
		case InputSeq.commandColumn:
			return ui.help.FocusedHelpFamily.sequenceCommand;
		default:
			return ui.help.FocusedHelpFamily.sequenceGeneral;
		}
	}

	int keyrelease(Keyinfo key) {
		bool targetChanged = handleTrackOverviewBlockDragModifierChange(key);
		toplevel.keyrelease(key);
		if(targetChanged)
			update();
		return OK;
	}

	private bool selectTrackOverviewBlockFromEditorClick(int voice,
			int trackIndex, ushort trackValue) {
		if(song is null)
			return false;
		auto overview = buildTrackOverview(song);
		if(!selectTrackOverviewBlockAtTrackIndex(trackOverviewSelection,
				overview, voice, trackIndex, trackValue)) {
			clearTrackOverviewBlockSelection(trackOverviewSelection);
			syncTrackOverviewSelectionState(overview);
			setTrackOverviewEditorFocus(trackOverviewFocus);
			return false;
		}

		syncTrackOverviewSelectionState(overview);
		// Editor-origin clicks may mirror selection into the strip, but must
		// not transfer keyboard focus away from the editor.
		setTrackOverviewEditorFocus(trackOverviewFocus);
		trackOverviewPendingSelectionReveal = true;
		drawTrackOverviewStrip();
		return true;
	}

			void clickedAt(int x, int y, int b) {
				if(b == 1 || b == 3)
					noteMeaningfulStatuslineInteraction();
				if(dialog) {
				if(closeInfobarInlineEditForOutsideCellClick(x, y, b)) {
					clickedAt(x, y, b);
					return;
				}
				if(dialog == infobar && infobar.octaveEditContainsCell(x, y)) {
					if(b == 1)
						return;
					state.octave = clamp(state.octave - 1, 0, 6);
					infobar.refresh();
					return;
				}
				if(b == 1 && dialog == infobar &&
						infobar.speedEditContainsCell(x, y)) {
					infobar.setSpeedCursorFromCell(x);
					return;
				}
				if(b == 1 && dialog == infobar &&
						infobar.stepEditContainsCell(x, y))
					return;
				dialog.clickedAt(x, y, b);
			}
			else {
				setTrackOverviewEditorFocus(trackOverviewFocus);
				toplevel.clickedAt(x, y, b);
			}
		}

	bool fileDialogClickedAt(int x, int y, int button, int clicks) {
		auto fileDialog = cast(FileSelectorDialog)dialog;
			if(fileDialog is null)
				return false;
			if(button == 1 && fileDialog.fsel.contentArea.overlaps(x, y))
				noteMeaningfulStatuslineInteraction();

		bool handled;
		int result = fileDialog.clickedFileListAt(x, y, button, clicks,
			handled);
		if(handled && result != OK && dialog is fileDialog)
			closeDialog();
		return handled;
	}

	bool fileDialogMouseWheelAt(int x, int y, int rows) {
		auto fileDialog = cast(FileSelectorDialog)dialog;
		return noteMeaningfulStatuslineInteractionIf(fileDialog !is null &&
			fileDialog.scrollFileListAt(x, y, rows));
	}

	bool clickedAtPixel(int x, int y, int b, int clicks = 1) {
		if(dialog !is null && closeInfobarInlineEditForAnyPixelClick(b))
			return clickedAtPixel(x, y, b, clicks);
		auto panelHit = rightVisualPanelMouseHit(x, y, b == 1,
			vismode == VisMode.Oscilloscope, dialog !is null, screen.width,
			FONT_X, FONT_Y);
		if(dialog !is null)
			return false;
			if(handleRightVisualPanelMouseDown(panelHit)) {
				noteMeaningfulStatuslineInteraction();
				return true;
			}
			if(y < 0 || y >= trackOverviewTotalHeight())
				return false;
			if(b == 1 || b == 3)
				noteMeaningfulStatuslineInteraction();

		handleTrackOverviewMouseDown(x, y, b, clicks);
		return true;
	}

	private bool closeInfobarInlineEditForOutsideCellClick(int x, int y, int button) {
		if(button != 1 || dialog != infobar || !infobar.inlineEditActive())
			return false;
		if(infobar.octaveEditContainsCell(x, y) ||
				infobar.speedEditContainsCell(x, y) ||
				infobar.stepEditContainsCell(x, y))
			return false;
		closeDialog();
		return true;
	}

	private bool closeInfobarInlineEditForAnyPixelClick(int button) {
		if(button != 1 || dialog != infobar || !infobar.inlineEditActive())
			return false;
		closeDialog();
		return true;
	}

	bool mouseButtonUpPixel(int button) {
		if(button != 1)
			return false;

		bool hadPointerState =
			trackOverviewScroll.scrollbarDragActive ||
			trackOverviewScroll.timelineScrubActive ||
			trackOverviewBlockDrag.candidateActive ||
			trackOverviewBlockDrag.active;
		if(!hadPointerState)
			return false;

		if(!trackOverviewScroll.scrollbarDragActive &&
				!trackOverviewScroll.timelineScrubActive)
			handleTrackOverviewBlockDropRelease();

		stopTrackOverviewPointerDrag(trackOverviewScroll);
		clearTrackOverviewBlockDrag(trackOverviewBlockDrag);
		return true;
	}

	bool mouseButtonUp(int button) {
		if(dialog !is null)
			return false;
		return toplevel.mouseButtonUp(button);
	}

		bool mouseMotionPixel(int x, int y) {
			if(dialog !is null)
				return false;
			if(trackOverviewScroll.timelineScrubActive)
				return noteMeaningfulStatuslineInteractionIf(
					handleTrackOverviewTimelineScrubMotion(x));
			if(trackOverviewScroll.scrollbarDragActive)
				return noteMeaningfulStatuslineInteractionIf(
					handleTrackOverviewDragMotion(x, y));
			return noteMeaningfulStatuslineInteractionIf(
				handleTrackOverviewBlockDragMotion(x, y));
		}

		bool mouseMotionAt(int x, int y) {
			if(dialog !is null)
				return false;
			return noteMeaningfulStatuslineInteractionIf(
				toplevel.mouseMotionAt(x, y));
		}

	bool mouseWheelPixel(int x, int y, int wheelX) {
		if(dialog !is null || wheelX == 0)
			return false;
		if(y < 0 || y >= trackOverviewTotalHeight())
			return false;
		if(x < 0 || x >= screen.width * FONT_X)
			return false;
		if(trackOverviewScroll.scrollbarDragActive ||
				trackOverviewScroll.timelineScrubActive ||
				trackOverviewBlockDrag.candidateActive ||
				trackOverviewBlockDrag.active)
			return true;

			return noteMeaningfulStatuslineInteractionIf(
				handleTrackOverviewHorizontalWheel(x, y, wheelX));
		}

	private bool handleTrackOverviewScrollKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		KeyboardActionId actionId;
		if(!resolveTrackOverviewFocusedKeyboardAction(key, actionId))
			return false;

		int deltaX;
		switch(actionId) {
		case KeyboardActionId.trackOverviewScrollLeft:
			deltaX = -TRACK_OVERVIEW_KEY_SCROLL_STEP;
			break;
		case KeyboardActionId.trackOverviewScrollRight:
			deltaX = TRACK_OVERVIEW_KEY_SCROLL_STEP;
			break;
		default:
			return false;
		}

		auto overview = buildTrackOverview(song);
		int stripWidth = screen.width * FONT_X;
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		TrackOverviewEditorCursor cursor = editorCursorForOverview(overview);
		trackOverviewScrollByPixels(trackOverviewScroll, overview, contentWidth,
			deltaX, cursor.valid ? cursor.globalRow : -1);
		return true;
	}

	private static bool handleTrackOverviewHorizontalWheel(int x, int y,
			int wheelX) {
		if(song is null || toplevel is null)
			return false;
		if(y < 0 || y >= trackOverviewTotalHeight())
			return false;

		auto overview = buildTrackOverview(song);
		int stripWidth = screen.width * FONT_X;
		if(x < 0 || x >= stripWidth)
			return false;

		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		TrackOverviewEditorCursor cursor = editorCursorForOverview(overview);
		int deltaX = wheelX * TRACK_OVERVIEW_WHEEL_SCROLL_STEP;
		trackOverviewScrollByPixels(trackOverviewScroll, overview, contentWidth,
			deltaX, cursor.valid ? cursor.globalRow : -1);
		return true;
	}

	private bool handleTrackOverviewBlockNavigationKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block)
			return false;
		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId))
			return false;

		int direction;
		switch(actionId) {
		case KeyboardActionId.trackOverviewNavigatePreviousBlock:
			direction = -1;
			break;
		case KeyboardActionId.trackOverviewNavigateNextBlock:
			direction = 1;
			break;
		default:
			return false;
		}

		auto overview = buildTrackOverview(song);
		validateTrackOverviewBlockSelection(trackOverviewSelection, overview);
		validateTrackOverviewFocus(trackOverviewFocus, trackOverviewSelection);
		syncTrackOverviewSelectionState(overview);
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block ||
				!trackOverviewSelection.valid) {
			setTrackOverviewEditorFocus(trackOverviewFocus);
			return true;
		}

		if(!selectAdjacentTrackOverviewBlock(trackOverviewSelection, overview,
				direction)) {
			syncTrackOverviewSelectionState(overview);
			setTrackOverviewEditorFocus(trackOverviewFocus);
			return true;
		}

		syncTrackOverviewSelectionState(overview);
		setTrackOverviewBlockFocus(trackOverviewFocus, trackOverviewSelection);
		if(!toplevel.moveEditorCursorToOverviewBlockStart(
				trackOverviewSelection.voice,
				trackOverviewSelection.trackIndex)) {
			clearTrackOverviewBlockSelection(trackOverviewSelection);
			syncTrackOverviewSelectionState(overview);
			setTrackOverviewEditorFocus(trackOverviewFocus);
			return true;
		}

		int stripWidth = screen.width * FONT_X;
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		revealTrackOverviewBlockSelection(trackOverviewScroll,
			trackOverviewSelection, overview, contentWidth);
		return true;
	}

	private bool handleTrackOverviewOpenActiveBlockKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null ||
				trackOverviewFocus.kind != TrackOverviewFocusKind.Block)
			return false;

		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId) ||
				actionId !=
					KeyboardActionId.trackOverviewOpenActiveBlockInSequenceEditor)
			return false;

		auto overview = buildTrackOverview(song);
		validateTrackOverviewBlockSelection(trackOverviewSelection, overview);
		validateTrackOverviewFocus(trackOverviewFocus, trackOverviewSelection);
		syncTrackOverviewSelectionState(overview);
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block ||
				!trackOverviewSelection.valid ||
				trackOverviewSelectionSelectedCount(trackOverviewSelectionState) != 1)
			return true;

		TrackOverviewBlockSelection selection = trackOverviewSelection;
		int targetRow;
		if(trackOverviewPlaybackActive()) {
			TrackOverviewPlaybackCursor playback =
				playbackCursorForOverview(overview);
			if(selection.voice >= 0 &&
					selection.voice < cast(int)playback.voicePositions.length) {
				TrackOverviewPosition position =
					playback.voicePositions[selection.voice];
				if(position.valid &&
						position.trackIndex == selection.trackIndex &&
						position.sequenceNumber == selection.sequenceNumber &&
						position.trackValue == selection.trackValue)
					targetRow = position.sequenceRowOffset;
			}
		}

		TrackOverviewPosition target = trackOverviewPositionAtTrackRow(overview,
			selection.voice, selection.trackIndex, targetRow);
		if(!target.valid || target.sequenceNumber != selection.sequenceNumber ||
				target.trackValue != selection.trackValue)
			return true;

		if(!toplevel.moveEditorCursorToOverviewBlockStart(selection.voice,
				selection.trackIndex))
			return true;
		if(targetRow != 0 && !toplevel.moveEditorCursorToOverviewPosition(target))
			return true;

		setTrackOverviewEditorFocus(trackOverviewFocus);
		return true;
	}

	private enum TrackOverviewTrackEntrySelectionPolicy {
		ExactTrackIndex,
		NearTrackIndex,
	}

	private static bool selectedTrackOverviewBlockForTrackEntryMutation(
			const(TrackOverviewLane)[] overview,
			out TrackOverviewBlockSelection previousSelection) {
		validateTrackOverviewBlockSelection(trackOverviewSelection, overview);
		validateTrackOverviewFocus(trackOverviewFocus, trackOverviewSelection);
		syncTrackOverviewSelectionState(overview);
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block ||
				!trackOverviewSelection.valid)
			return false;

		previousSelection = trackOverviewSelection;
		return true;
	}

	private static bool finishTrackOverviewTrackEntryMutation(
			const(TrackOverviewLane)[] updatedOverview, int voice,
			int trackIndex, ushort trackValue,
			TrackOverviewTrackEntrySelectionPolicy selectionPolicy) {
		bool selected;
		final switch(selectionPolicy) {
		case TrackOverviewTrackEntrySelectionPolicy.ExactTrackIndex:
			selected = selectTrackOverviewBlockAtTrackIndex(
				trackOverviewSelection, updatedOverview, voice, trackIndex,
				trackValue);
			break;
		case TrackOverviewTrackEntrySelectionPolicy.NearTrackIndex:
			selected = selectTrackOverviewBlockNearTrackIndex(
				trackOverviewSelection, updatedOverview, voice, trackIndex);
			break;
		}

		if(!selected) {
			clearTrackOverviewBlockSelection(trackOverviewSelection);
			syncTrackOverviewSelectionState(updatedOverview);
			setTrackOverviewEditorFocus(trackOverviewFocus);
			return true;
		}

		syncTrackOverviewSelectionState(updatedOverview);
		setTrackOverviewBlockFocus(trackOverviewFocus, trackOverviewSelection);
		if(!toplevel.moveEditorCursorToOverviewBlockStart(
				trackOverviewSelection.voice,
				trackOverviewSelection.trackIndex)) {
			clearTrackOverviewBlockSelection(trackOverviewSelection);
			syncTrackOverviewSelectionState(updatedOverview);
			setTrackOverviewEditorFocus(trackOverviewFocus);
			return true;
		}

		int stripWidth = screen.width * FONT_X;
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		revealTrackOverviewBlockSelection(trackOverviewScroll,
			trackOverviewSelection, updatedOverview, contentWidth);
		return true;
	}

	private bool handleTrackOverviewBlockCopyKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block)
			return false;
		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId) ||
				actionId != KeyboardActionId.trackOverviewCopyEntries)
			return false;

		auto overview = buildTrackOverview(song);
		validateTrackOverviewBlockSelection(trackOverviewSelection, overview);
		validateTrackOverviewFocus(trackOverviewFocus, trackOverviewSelection);
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block ||
				!trackOverviewSelection.valid) {
			clearTrackOverviewSelectionState(trackOverviewSelectionState);
			statusline.displayOperationFeedback(
				"No track entries selected.");
			return true;
		}

		Clip[] entries;
		int voice, startTrackIndex, endTrackIndex;
		if(!collectTrackOverviewSelectedTrackEntries(
				trackOverviewSelectionState, trackOverviewSelection,
				song.subtune, overview, entries, voice, startTrackIndex,
				endTrackIndex)) {
			clearTrackOverviewBlockSelection(trackOverviewSelection);
			clearTrackOverviewSelectionState(trackOverviewSelectionState);
			setTrackOverviewEditorFocus(trackOverviewFocus);
			statusline.displayOperationFeedback(
				"No track entries selected.");
			return true;
		}

		toplevel.setTrackEntryClipboard(song.subtune, voice,
			startTrackIndex, endTrackIndex, entries);
		statusline.displayOperationFeedback(format(
			"Track selection copied: %d.",
			toplevel.trackEntryClipboardEntryCount()));
		return true;
	}

	private bool handleTrackOverviewBlockPasteKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block)
			return false;
		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId) ||
				actionId != KeyboardActionId.trackOverviewPasteEntries)
			return false;

		if(trackOverviewPlaybackActive())
			return true;

		if(!toplevel.hasTrackEntryClipboard()) {
			statusline.displayOperationFeedback(
				"No track entries copied.");
			return true;
		}

		auto overview = buildTrackOverview(song);
		TrackOverviewBlockSelection previousSelection;
		if(!selectedTrackOverviewBlockForTrackEntryMutation(overview,
				previousSelection)) {
			statusline.displayOperationFeedback(
				"No track entry selected.");
			return true;
		}

		int firstInsertedTrackIndex;
		int lastInsertedTrackIndex;
		int insertedCount;
		if(!toplevel.pasteTrackEntryClipboardAfter(previousSelection.voice,
				previousSelection.trackIndex, previousSelection.trackValue,
				firstInsertedTrackIndex, lastInsertedTrackIndex,
				insertedCount)) {
			statusline.displayFailure("Could not paste track entries.");
			return true;
		}

		auto updatedOverview = buildTrackOverview(song);
		if(!selectTrackOverviewRangeByTrackIndex(trackOverviewSelectionState,
				trackOverviewSelection, song.subtune, updatedOverview,
				previousSelection.voice, firstInsertedTrackIndex,
				lastInsertedTrackIndex)) {
			syncTrackOverviewSelectionState(updatedOverview);
			setTrackOverviewEditorFocus(trackOverviewFocus);
			statusline.displayOperationFeedback(format(
				"Track selection pasted: %d.", insertedCount));
			return true;
		}

		setTrackOverviewBlockFocus(trackOverviewFocus, trackOverviewSelection);
		if(!toplevel.moveEditorCursorToOverviewBlockStart(
				trackOverviewSelection.voice,
				trackOverviewSelection.trackIndex)) {
			clearTrackOverviewBlockSelection(trackOverviewSelection);
			syncTrackOverviewSelectionState(updatedOverview);
			setTrackOverviewEditorFocus(trackOverviewFocus);
		}

		int stripWidth = screen.width * FONT_X;
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		revealTrackOverviewBlockSelection(trackOverviewScroll,
			trackOverviewSelection, updatedOverview, contentWidth);
		statusline.displayOperationFeedback(format(
			"Track selection pasted: %d.", insertedCount));
		return true;
	}

	private bool handleTrackOverviewBlockFindUnusedSequenceKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block)
			return false;
		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId) ||
				actionId != KeyboardActionId.trackOverviewFindUnusedSequence)
			return false;

		if(trackOverviewPlaybackActive())
			return true;

		auto overview = buildTrackOverview(song);
		TrackOverviewBlockSelection previousSelection;
		if(!selectedTrackOverviewBlockForTrackEntryMutation(overview,
				previousSelection)) {
			statusline.displayOperationFeedback(
				"No track entry selected.");
			return true;
		}

		ushort updatedTrackValue;
		int updatedSequenceNumber;
		if(!toplevel.setTrackEntryToNextUnusedSequenceAt(
				previousSelection.voice, previousSelection.trackIndex,
				previousSelection.trackValue, updatedTrackValue,
				updatedSequenceNumber)) {
			statusline.displayOperationFeedback(
				trackNextUnusedSequenceUnavailableMessage());
			return true;
		}

		auto updatedOverview = buildTrackOverview(song);
		finishTrackOverviewTrackEntryMutation(updatedOverview,
			previousSelection.voice, previousSelection.trackIndex,
			updatedTrackValue,
			TrackOverviewTrackEntrySelectionPolicy.ExactTrackIndex);
		statusline.displayOperationFeedback(
			trackNextUnusedSequenceChangedMessage(updatedSequenceNumber));
		return true;
	}

	private bool handleTrackOverviewBlockInsertCopyKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block)
			return false;
		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId) ||
				actionId != KeyboardActionId.trackOverviewInsertCopyEntry)
			return false;

		auto overview = buildTrackOverview(song);
		TrackOverviewBlockSelection previousSelection;
		if(!selectedTrackOverviewBlockForTrackEntryMutation(overview,
				previousSelection))
			return false;

		if(trackOverviewPlaybackActive())
			return true;

		ushort copiedTrackValue;
		if(!toplevel.insertCopyOfTrackEntryAt(previousSelection.voice,
				previousSelection.trackIndex,
				previousSelection.trackValue, copiedTrackValue)) {
			statusline.displayFailure("Could not insert copied track entries.");
			return true;
		}

		auto updatedOverview = buildTrackOverview(song);
		return finishTrackOverviewTrackEntryMutation(updatedOverview,
			previousSelection.voice, previousSelection.trackIndex,
			copiedTrackValue,
			TrackOverviewTrackEntrySelectionPolicy.ExactTrackIndex);
	}

	private bool handleTrackOverviewBlockInsertKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block)
			return false;
		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId) ||
				actionId != KeyboardActionId.trackOverviewInsertEntry)
			return false;

		auto overview = buildTrackOverview(song);
		TrackOverviewBlockSelection previousSelection;
		if(!selectedTrackOverviewBlockForTrackEntryMutation(overview,
				previousSelection))
			return true;

		if(trackOverviewPlaybackActive())
			return true;

		ushort insertedTrackValue;
		if(!toplevel.insertTrackEntryAt(previousSelection.voice,
				previousSelection.trackIndex,
				previousSelection.trackValue, insertedTrackValue)) {
			statusline.displayFailure("Could not insert track entry.");
			return true;
		}

		auto updatedOverview = buildTrackOverview(song);
		return finishTrackOverviewTrackEntryMutation(updatedOverview,
			previousSelection.voice, previousSelection.trackIndex,
			insertedTrackValue,
			TrackOverviewTrackEntrySelectionPolicy.ExactTrackIndex);
	}

	private bool handleTrackOverviewBlockDeleteKey(Keyinfo key) {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(trackOverviewFocus.kind != TrackOverviewFocusKind.Block)
			return false;
		KeyboardActionId actionId;
		if(!resolveTrackOverviewBlockKeyboardAction(key, actionId) ||
				actionId != KeyboardActionId.trackOverviewDeleteSelection)
			return false;

		auto overview = buildTrackOverview(song);
		TrackOverviewBlockSelection previousSelection;
		if(!selectedTrackOverviewBlockForTrackEntryMutation(overview,
				previousSelection))
			return true;

		if(trackOverviewPlaybackActive())
			return true;

		Clip[] entries;
		int voice, startTrackIndex, endTrackIndex;
		if(!collectTrackOverviewSelectedTrackEntries(
				trackOverviewSelectionState, trackOverviewSelection,
				song.subtune, overview, entries, voice, startTrackIndex,
				endTrackIndex)) {
			clearTrackOverviewBlockSelection(trackOverviewSelection);
			clearTrackOverviewSelectionState(trackOverviewSelectionState);
			setTrackOverviewEditorFocus(trackOverviewFocus);
			return true;
		}

		ushort[] expectedTrackValues = trackEntryValuesFromClips(entries);
		if(!toplevel.deleteTrackEntryRangeAt(voice, startTrackIndex,
				endTrackIndex, expectedTrackValues)) {
			clearTrackOverviewBlockSelection(trackOverviewSelection);
			syncTrackOverviewSelectionState(overview);
			setTrackOverviewEditorFocus(trackOverviewFocus);
			statusline.displayFailure("Could not delete selected track entries.");
			return true;
		}

		auto updatedOverview = buildTrackOverview(song);
		return finishTrackOverviewTrackEntryMutation(updatedOverview,
			voice, startTrackIndex,
			previousSelection.trackValue,
			TrackOverviewTrackEntrySelectionPolicy.NearTrackIndex);
	}

	private static ushort[] trackEntryValuesFromClips(
			const(Clip)[] entries) {
		ushort[] values;
		values.length = entries.length;
		foreach(idx, entry; entries) {
			values[idx] = cast(ushort)(
				((cast(ushort)entry.trans) << 8) |
				(cast(ushort)entry.no & 0xff));
		}
		return values;
	}

	private bool saveToPath(string s) {
		try {
			final switch(savedialog.saveFormat) {
			case SaveFormat.CT:
				song.save(s);
				break;
			case SaveFormat.PRG:
			case SaveFormat.SID:
				ExportOptions options;
				options.relocAddress = savedialog.relocAddress;
				options.zpAddress = savedialog.zpAddress;
				options.singleSubtune = savedialog.singleSubtune;
				options.defaultTune = savedialog.defaultSubtune;
				options.skipPurge = !savedialog.purgeBeforeExport;
				options.verbose = false;
				ubyte[] data = exportSong(song,
					savedialog.saveFormat == SaveFormat.PRG ? ExportFormat.PRG : ExportFormat.SID,
					options);
				std.file.write(s, data);
				break;
			}
		}
		catch(Exception e) {
			stderr.writeln(e.toString);
			statusline.displayFailure("Could not save: " ~ e.msg);
			return false;
		}

		if(savedialog.saveFormat != SaveFormat.CT) {
			statusline.displayTimedOperationFeedback(format(
				"Export complete: \"%s\".", s));
			return true;
		}

		string path = s.strip();
		string fn = baseName(path);
		state.filename = fn;

		// sync load filesel to save filesel
		if(loaddialog.directory != savedialog.directory) {
			foreach(d; [loaddialog, savedialog]) {
				d.setFilename(fn);
				d.setDirectory(dirName(path));
			}
			loaddialog.fsel.fpos.reset();
		}
		return true;
	}

	private void saveCallback(string s) {
		saveToPath(s);
	}

	void importCallback(string s) {
		loadCallback(s, true);
	}

	void loadCallback(string s) {
		loadCallback(s, false);
	}

	private void clearDocumentTransientState(
			DocumentReplacementScope replacementScope) {
		com.session.clearDocumentHistory();
		toplevel.sequencer.clearF6OriginMarker();
		toplevel.clearDocumentStructuralClipboards();
		if(replacementScope == DocumentReplacementScope.fullSongReplacement) {
			toplevel.sequencer.clearSongLocalInputMemory();
			toplevel.resetSongDerivedTableState();
		}
		stopTrackOverviewPointerDrag(trackOverviewScroll);
		clearTrackOverviewManualScroll(trackOverviewScroll);
		clearTrackOverviewBlockDrag(trackOverviewBlockDrag);
		clearTrackOverviewBlockSelection(trackOverviewSelection);
		clearTrackOverviewSelectionState(trackOverviewSelectionState);
		trackOverviewPendingSelectionReveal = false;
		trackOverviewCurrentBlock = TrackOverviewCurrentEditorBlock();
		setTrackOverviewEditorFocus(trackOverviewFocus);
		trackOverviewScroll.scrollX = 0;
		dialogAfterActiveClose = null;
		pendingTimedOperationFeedbackAfterDialogClose = "";
	}

	private void rebindSongConsumersAfterReplacement() {
		int activeTopWindow = toplevel.activeWindowNum;
		int activeBottomTable = toplevel.bottomTabSwitcher.activeWindowNum;
		int activeVoice = activeVoiceNum;

		toplevel.deactivate();
		toplevel = new Toplevel(this);
		toplevel.sequencer.activateVoice(activeVoice);
		toplevel.bottomTabSwitcher.activateWindow(activeBottomTable);
		toplevel.activateWindow(activeTopWindow);
	}

	private void loadCallback(string s, bool doImport) {
		bool sourceAccessible = std.file.exists(s) != 0 && !std.file.isDir(s);
		if(!sourceAccessible) {
			if(doImport) {
				reportSongFileError("import", s,
					"File not found or not accessible.");
			}
			else {
				reportSongFileError("load", s,
					"File not found or not accessible.");
			}
			return;
		}

		if(!doImport) {
			Song loadedSong;
			try {
				loadedSong = new Song();
				loadedSong.open(s);
			}
			catch(Exception e) {
				reportSongFileError("load", s, e.msg);
				return;
			}
			catch(RangeError e) {
				reportSongFileError("load", s, e.msg);
				return;
			}

			stop();
			vismode = VisMode.Oscilloscope;
			com.session.commitLoadedSong(loadedSong);
			rebindSongConsumersAfterReplacement();
			timelineSeekManager().resetSession("song_loaded");
		}
		else {
			Song importedSong;
			try {
				Song insong = new Song();
				insong.open(s);
				importedSong = song.prepareImportedData(insong);
			}
			catch(Exception e) {
				reportSongFileError("import", s, e.msg);
				return;
			}
			catch(RangeError e) {
				reportSongFileError("import", s, e.msg);
				return;
			}

			stop();
			vismode = VisMode.Oscilloscope;
			com.session.commitLoadedSong(importedSong);
			rebindSongConsumersAfterReplacement();
			timelineSeekManager().resetSession("song_imported");
		}

		clearDocumentTransientState(
			DocumentReplacementScope.fullSongReplacement);
		refresh();
		// all voices ON
		audio.player.setVoicon(0,0,0);
		
		string path = s.strip();
		string fn = baseName(path);
		state.filename = fn;
		infobar.refresh();
		
		// sync save filesel to load filesel in case dir was changed
		foreach(d; [loaddialog, savedialog]) {
			d.setFilename(fn);
			d.setDirectory(dirName(path));
		}
		savedialog.fsel.fpos = loaddialog.fsel.fpos;
	
		// set variables
		audio.player.setSidModel(song.sidModel);
		audio.player.setFP(song.fppres);
		audio.player.setMultiplier(song.multiplier);
		
		enableKeyjamMode(false);

		if(doImport) {
			toplevel.reset();
		}
		toplevel.sequencer.placeSequenceSongStartAtTopBoundary();
		
		if(doImport) {
			statusline.displayTimedOperationFeedback("Import complete.");
		}

		if(dialog !is null)
			closeDialog();
		drawCurrentVisualPanel();
		}

	private void reportSongFileError(string operation, string source,
			string detail) {
		string path = source.strip();
		string filename = baseName(path);
		string safeDetail = detail.replace(path, filename);
		statusline.displayFailure(format("Could not %s \"%s\": %s", operation,
			filename, safeDetail));
	}

	void activateDialog(Window d) {
		enableKeyjamMode(false);
		releaseInputOwnership();
		if(toplevel !is null)
			toplevel.sequencer.clearF6OriginMarker();
		toplevel.mouseButtonUp(1);
		closeDialog(false);
		dialog = d;
		d.activate();
	}

	void activateDialogAfterActiveCloses(Window d) {
		dialogAfterActiveClose = d;
	}

	void queueTimedOperationFeedbackAfterDialogClose(string message) {
		if(!state.displayHelp)
			return;
		pendingTimedOperationFeedbackAfterDialogClose = message;
	}

	private void flushPendingTimedOperationFeedbackAfterDialogClose() {
		if(!pendingTimedOperationFeedbackAfterDialogClose.length)
			return;
		string message = pendingTimedOperationFeedbackAfterDialogClose;
		pendingTimedOperationFeedbackAfterDialogClose = "";
		statusline.displayTimedOperationFeedback(message);
	}
	
	void closeDialog(bool restorePreviousDialog = true) {
		Window closingDialog = dialog;
		if(closingDialog) closingDialog.deactivate();
		if(restorePreviousDialog && cast(HelpDialog)closingDialog !is null &&
		   dialogBeforeHelp !is null) {
			dialog = dialogBeforeHelp;
			dialogBeforeHelp = null;
			refresh();
			dialog.activate();
			return;
		}
		dialog = null;
		dialogBeforeHelp = null;
		refresh();
	}

	bool enableKeyjamMode(bool doEnable) {
		if(audio.player.isPlaying) return false;
/+		doEnable ? com.fb.disableKeyRepeat() :
			com.fb.enableKeyRepeat();+/
		bool changed = state.keyjamStatus != doEnable;
		state.keyjamStatus = doEnable;
		if(changed)
			updateKeyjamQuickHelp();
		return true;
	}

	bool toggleKeyjamMode() {
		if(song.ver < 7)
			return false;
		bool doEnable = !state.keyjamStatus;
		if(!enableKeyjamMode(doEnable)) {
			state.keyjamStatus = doEnable;
			updateKeyjamQuickHelp();
		}
		return true;
	}

	private static string keyjamQuickHelpMessage() {
		string label = keyboardActionPrimaryShortcutLabel(
			keyboardActionStableId(KeyboardActionId.songKeyjamToggle));
		assert(label.length);
		return "Keyjam enabled - " ~ label ~ " disables it";
	}

	private void updateKeyjamQuickHelp() {
		if(statusline is null)
			return;
		if(state.keyjamStatus) {
			statusline.setPersistentAlertMessage(keyjamQuickHelpMessage());
			return;
		}
		statusline.clearPersistentContextualMessage();
		refreshCurrentContextualHelp();
	}

	private void refreshCurrentContextualHelp() {
		if(!state.displayHelp || statusline is null || toplevel is null)
			return;
		if(trackOverviewFocus.kind == TrackOverviewFocusKind.Timeline ||
				trackOverviewFocus.kind == TrackOverviewFocusKind.Block) {
			displayTrackOverviewQuickHelp();
			return;
		}
		toplevel.showCurrentContextualHelp();
	}

	bool activateInstrumentTable(int ins) {
		if(ins < 0 || ins >= 48)
			return false;
		UI.activateInstrument(ins);
		toplevel.handleWorkspaceNavigationAction(
			KeyboardActionId.workspaceActivateInstrument,
			Keyinfo(SDLK_i, KMOD_ALT, 'i', SDL_SCANCODE_I));
		toplevel.instable.seekByte(state.activeInstrument, 0);
		toplevel.input = toplevel.activeWindow.input;
		toplevel.refresh();
		return true;
	}

	bool activateSequenceCommandReference(
			SequenceCommandReference reference) {
		return toplevel.navigateToSequenceCommandReference(reference);
	}

	static void stop() {
		stop(true);
	}

	static void stop(bool doStop) {
		if(doStop) {
			audio.player.stop();
			stopTrackOverviewPlaybackState(trackOverviewPlayback);
		}
		infobar.update();
		toplevel.stopPlayback();
		stopTrackOverviewPointerDrag(trackOverviewScroll);
		clearTrackOverviewBlockDrag(trackOverviewBlockDrag);
		clearTrackOverviewManualScroll(trackOverviewScroll);
		if(mainui !is null)
			mainui.drawCurrentVisualPanel();
	}

	static void refresh() {
		screen.clrscr();
		toplevel.refresh();
		UI.statusline.update();
		drawTrackOverviewStrip();
		if(mainui !is null)
			mainui.drawCurrentVisualPanel();
	}

	private static void syncTrackOverviewSelectionState(
			const(TrackOverviewLane)[] overview) {
		if(song is null) {
			clearTrackOverviewSelectionState(trackOverviewSelectionState);
			return;
		}

		validateTrackOverviewSelectionState(trackOverviewSelectionState,
			song.subtune, trackOverviewSelection, overview);
	}

	static void activateInstrument(int ins) {
		if(ins > 47) ins = 47;
		if(ins < 0) ins = 0;
		int previousInstrument = state.activeInstrument;
		toplevel.instable.seekRow(ins);
		state.activeInstrument = ins;
		if(previousInstrument != ins)
			toplevel.syncProgramTablePreviewsToActiveInstrument();
		toplevel.refresh();
	}

	static void previewCommittedInstrumentPointer(
			InstrumentPointerTarget target, int pointerValue) {
		final switch(target) {
		case InstrumentPointerTarget.none:
			return;
		case InstrumentPointerTarget.wave:
			toplevel.wavetable.seekRow(pointerValue);
			toplevel.wavetable.placeCurrentRowAtProgramPreviewAnchor();
			toplevel.wavetable.update();
			break;
		case InstrumentPointerTarget.pulse:
			toplevel.pulsetable.seekProgramRow(pointerValue);
			toplevel.pulsetable.placeCurrentRowAtProgramPreviewAnchor();
			toplevel.pulsetable.update();
			break;
		case InstrumentPointerTarget.filter:
			toplevel.filtertable.seekProgramRow(pointerValue);
			toplevel.filtertable.placeCurrentRowAtProgramPreviewAnchor();
			toplevel.filtertable.update();
			break;
		}
		toplevel.instable.showCurrentContextualHelp();
	}

	private static void drawTrackOverviewStrip() {
		if(video is null || song is null)
			return;
		auto overview = buildTrackOverview(song);
		validateTrackOverviewBlockSelection(trackOverviewSelection, overview);
		validateTrackOverviewFocus(trackOverviewFocus, trackOverviewSelection);
		syncTrackOverviewSelectionState(overview);
		int stripWidth = screen.width * FONT_X;
		int contentX = trackOverviewContentX(0);
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		TrackOverviewEditorCursor cursor = editorCursorForOverview(overview);
		trackOverviewCurrentBlock = trackOverviewCurrentEditorBlock(cursor);
		bool playbackActive = trackOverviewPlaybackActive();
		if(playbackActive && !trackOverviewPlayback.active)
			startTrackOverviewPlaybackMarkers();
		else if(!playbackActive)
			stopTrackOverviewPlaybackState(trackOverviewPlayback);
		auto notePreviews = buildTrackOverviewNotePreviews(song, overview);
		int[] speedMarkerRows = trackOverviewSpeedMarkerRows(overview);

		TrackOverviewPlaybackCursor playbackCursor =
			playbackCursorForOverview(overview);
		int overviewContentWidth = trackOverviewContentWidth(overview);
		if(playbackActive && playbackCursor.globalVisible) {
			bool followPlayActive = toplevel !is null && toplevel.fplayEnabled();
			if(followPlayActive && !trackOverviewScroll.scrollbarDragActive) {
				clearTrackOverviewManualScroll(trackOverviewScroll);
				trackOverviewScroll.scrollX =
					trackOverviewCenterPlaybackCursorScrollX(trackOverviewScroll.scrollX,
						overviewContentWidth, contentWidth, playbackCursor);
			}
			else if(!followPlayActive && !trackOverviewScroll.manualScrollActive) {
				trackOverviewScroll.scrollX =
					trackOverviewFollowPlaybackCursorScrollX(trackOverviewScroll.scrollX,
						overviewContentWidth, contentWidth, playbackCursor);
			}
		}
		else if(!playbackActive) {
			syncTrackOverviewManualScroll(trackOverviewScroll, cursor);
			if(!trackOverviewScroll.manualScrollActive) {
				trackOverviewScroll.scrollX =
					trackOverviewFollowEditorCursorScrollX(trackOverviewScroll.scrollX,
						overviewContentWidth, contentWidth, cursor);
			}
		}
		if(trackOverviewPendingSelectionReveal) {
			revealTrackOverviewBlockSelection(trackOverviewScroll,
				trackOverviewSelection, overview, contentWidth);
			trackOverviewPendingSelectionReveal = false;
		}
		auto viewport = trackOverviewViewport(overview, contentWidth,
			trackOverviewScroll.scrollX);
		trackOverviewScroll.scrollX = viewport.scrollX;
		TrackOverviewPosition[] editorVoicePositions = toplevel !is null ?
			toplevel.editorVoicePositionsForOverview(overview) : null;
		TrackOverviewMarkers markers = playbackActive && playbackCursor.valid ?
			playbackMarkers(playbackCursor, cursor) :
			editorCursorMarkers(cursor, editorVoicePositions);
		applyStoredPlayFromMarker(markers, overview);
		TrackOverviewVisualState visualState = trackOverviewVisualState();
			drawTrackOverview(video, overview, notePreviews,
				trackOverviewSelectionState, trackOverviewCurrentBlock, contentX, 0,
				viewport, markers,
				trackOverviewBlockDrag.dropTarget, 0, stripWidth, visualState,
				speedMarkerRows, song.highlight, song.highlightOffset);
		}

	private static int[] trackOverviewSpeedMarkerRows(
			const(TrackOverviewLane)[] overview) {
		int[] rows;
		if(song is null)
			return rows;

		bool[int] seenRows;
		foreach(lane; overview) {
			foreach(block; lane.blocks) {
				if(block.sequenceNumber < 0 ||
						block.sequenceNumber >= cast(int)song.seqs.length)
					continue;

				auto sequence = song.seqs[block.sequenceNumber];
				if(sequence is null)
					continue;

				int rowCount = block.rowLength;
				if(rowCount > sequence.rows)
					rowCount = sequence.rows;
				foreach(rowOffset; 0 .. rowCount) {
					int cmd = sequence.data[rowOffset].cmd.rawValue;
					if(cmd < 0xf1)
						continue;

					int globalRow = block.startRow + rowOffset;
					if((globalRow in seenRows) !is null)
						continue;
					seenRows[globalRow] = true;
					rows ~= globalRow;
				}
			}
		}
		return rows;
	}

	private static bool handleTrackOverviewMouseDown(int x, int y, int button,
			int clicks = 1) {
		if(button != 1 || song is null || toplevel is null)
			return true;

		clearTrackOverviewBlockDrag(trackOverviewBlockDrag);

		auto overview = buildTrackOverview(song);
		int stripWidth = screen.width * FONT_X;
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		auto viewport = trackOverviewViewport(overview, contentWidth,
			trackOverviewScroll.scrollX);
		trackOverviewScroll.scrollX = viewport.scrollX;

		validateTrackOverviewBlockSelection(trackOverviewSelection, overview);
		validateTrackOverviewFocus(trackOverviewFocus, trackOverviewSelection);
		syncTrackOverviewSelectionState(overview);

		TrackOverviewHitTest hit;
		if(trackOverviewFocus.kind == TrackOverviewFocusKind.Block) {
			hit = trackOverviewPlusHitTest(overview, trackOverviewSelection, x, y,
				0, 0, stripWidth, trackOverviewScroll.scrollX);
			if(hit.region == TrackOverviewHitRegion.Plus)
				return handleTrackOverviewPlusClick(overview, hit);
		}

		hit = trackOverviewHitTest(overview, x, y, 0, 0,
			stripWidth, trackOverviewScroll.scrollX);
		if(hit.region == TrackOverviewHitRegion.TimeRow) {
			if(clicks >= 2)
				return setActiveVoicePlayFromMarkFromTimelineRow(overview,
					hit.row);
			setTrackOverviewTimelineFocus(trackOverviewFocus);
			displayTrackOverviewQuickHelp();
			startTrackOverviewTimelineScrub(trackOverviewScroll);
			handleTrackOverviewTimelineScrubMotion(x);
			return true;
		}

		if(hit.region == TrackOverviewHitRegion.VoiceLoopLane)
			return handleTrackOverviewLoopLaneClick(overview, hit);

		if(hit.region == TrackOverviewHitRegion.VoiceLane) {
			bool shiftClick = (SDL_GetModState() & KMOD_SHIFT) != 0;
			bool selected = shiftClick ?
				selectTrackOverviewRangeFromHit(trackOverviewSelectionState,
					trackOverviewSelection, song.subtune, overview, hit) :
				selectTrackOverviewHitBlockPreservingRange(
					trackOverviewSelectionState, trackOverviewSelection,
					song.subtune, overview, hit);
			if(selected) {
				setTrackOverviewBlockFocus(trackOverviewFocus,
					trackOverviewSelection);
				toplevel.moveEditorCursorToOverviewBlockStart(hit.voice,
					hit.trackIndex);
				displayTrackOverviewQuickHelp();
				if(!trackOverviewPlaybackActive())
					startTrackOverviewBlockDragCandidate(trackOverviewBlockDrag,
						trackOverviewSelection, trackOverviewSelectionState,
						x, y);
			}
			else {
				setTrackOverviewEditorFocus(trackOverviewFocus);
				displayTrackOverviewQuickHelp(
					TrackOverviewQuickHelpKind.noBlock);
			}
			return true;
		}

		if(hit.region != TrackOverviewHitRegion.Scrollbar) {
			setTrackOverviewEditorFocus(trackOverviewFocus);
			displayTrackOverviewQuickHelp(TrackOverviewQuickHelpKind.noBlock);
			return true;
		}

		TrackOverviewEditorCursor cursor = editorCursorForOverview(overview);
		startTrackOverviewScrollbarDrag(trackOverviewScroll, viewport, hit.localX,
			cursor.valid ? cursor.globalRow : -1);
		return true;
	}

	private static bool setActiveVoicePlayFromMarkFromTimelineRow(
			const(TrackOverviewLane)[] overview, int row) {
		if(row < 0 || toplevel is null || seqPos is null)
			return true;

		int activeVoice = toplevel.activeEditorVoice();
		if(activeVoice < 0 || activeVoice >= TRACK_OVERVIEW_VOICE_LANES)
			return true;

		TrackOverviewPosition[] positions =
			trackOverviewTimelinePositionsAtRow(overview, row);
		if(activeVoice >= cast(int)positions.length ||
				!positions[activeVoice].valid ||
				positions[activeVoice].trackIndex < 0)
			return true;

		seqPos.pos[activeVoice].mark = positions[activeVoice].trackIndex;
		drawTrackOverviewStrip();
		return true;
	}

	private static bool handleTrackOverviewPlusClick(
			const(TrackOverviewLane)[] overview, const TrackOverviewHitTest hit) {
		if(hit.region != TrackOverviewHitRegion.Plus)
			return false;
		if(trackOverviewPlaybackActive())
			return true;

		TrackOverviewBlockSelection previousSelection;
		if(!selectedTrackOverviewBlockForTrackEntryMutation(overview,
				previousSelection))
			return true;

		int insertedTrackIndex;
		int insertedSequenceNumber;
		ushort insertedTrackValue;
		if(!toplevel.insertNextUnusedExpandedSequenceTrackEntryAfter(
				previousSelection.voice, previousSelection.trackIndex,
				previousSelection.trackValue, insertedTrackIndex,
				insertedTrackValue, insertedSequenceNumber)) {
			if(UI.statusline !is null)
				UI.statusline.displayOperationFeedback(
					"No unused sequence or track slot available.");
			return true;
		}

		auto updatedOverview = buildTrackOverview(song);
		return finishTrackOverviewTrackEntryMutation(updatedOverview,
			previousSelection.voice, insertedTrackIndex, insertedTrackValue,
			TrackOverviewTrackEntrySelectionPolicy.ExactTrackIndex);
	}

	private static bool handleTrackOverviewLoopLaneClick(
			const(TrackOverviewLane)[] overview, const TrackOverviewHitTest hit) {
		if(hit.region != TrackOverviewHitRegion.VoiceLoopLane)
			return false;
		if(trackOverviewPlaybackActive())
			return true;
		if(hit.voice < 0 || hit.blockIndex < 0 || hit.trackIndex < 0)
			return true;

		if(!toplevel.setLoopTargetForVoiceAtTrackIndex(hit.voice,
				hit.trackIndex, hit.trackValue)) {
			if(UI.statusline !is null)
				UI.statusline.displayFailure("Could not set LOOP target.");
			return true;
		}

		return true;
	}

	private static bool handleTrackOverviewBlockDropRelease() {
		if(song is null || toplevel is null)
			return false;
		if(!trackOverviewBlockDrag.active ||
				!trackOverviewBlockDrag.source.valid)
			return false;
		if(trackOverviewPlaybackActive())
			return false;

		bool duplicateDrop = trackOverviewDuplicateDropModeActive();
		refreshTrackOverviewBlockDropTargetForCurrentPointer(duplicateDrop);
		if(!trackOverviewBlockDrag.dropTarget.valid)
			return false;

		auto source = trackOverviewBlockDrag.source;
		auto target = trackOverviewBlockDrag.dropTarget;

		if(duplicateDrop) {
			Clip[] entries;
			if(trackOverviewBlockDrag.rangeActive) {
				entries.length =
					trackOverviewBlockDrag.rangeTrackValues.length;
				foreach(idx, trackValue;
						trackOverviewBlockDrag.rangeTrackValues) {
					entries[idx].trans = trackValue >> 8;
					entries[idx].no = trackValue & 0xff;
				}
			}
			else {
				entries.length = 1;
				entries[0].trans = source.trackValue >> 8;
				entries[0].no = source.trackValue & 0xff;
			}

			int firstInsertedTrackIndex;
			int lastInsertedTrackIndex;
			int insertedCount;
			if(!toplevel.insertTrackEntriesAt(target.voice,
					target.insertionTrackIndex, entries,
					firstInsertedTrackIndex, lastInsertedTrackIndex,
					insertedCount)) {
				if(UI.statusline !is null)
					UI.statusline.displayFailure("Could not duplicate track entries.");
				return false;
			}

			auto updatedOverview = buildTrackOverview(song);
			if(insertedCount == 1) {
				ushort insertedTrackValue =
					trackEntryValuesFromClips(entries)[0];
				return finishTrackOverviewTrackEntryMutation(updatedOverview,
					target.voice, firstInsertedTrackIndex,
					insertedTrackValue,
					TrackOverviewTrackEntrySelectionPolicy.ExactTrackIndex);
			}

			int primaryOffset =
				trackOverviewBlockDrag.rangePrimaryTrackIndex -
				trackOverviewBlockDrag.rangeStartTrackIndex;
			int anchorOffset =
				trackOverviewBlockDrag.rangeAnchorTrackIndex -
				trackOverviewBlockDrag.rangeStartTrackIndex;
			int primaryTrackIndex = firstInsertedTrackIndex + primaryOffset;
			int anchorTrackIndex = firstInsertedTrackIndex + anchorOffset;

			if(!selectTrackOverviewRangeByTrackIndexWithPrimary(
					trackOverviewSelectionState, trackOverviewSelection,
					song.subtune, updatedOverview, target.voice,
					firstInsertedTrackIndex, lastInsertedTrackIndex,
					anchorTrackIndex, primaryTrackIndex)) {
				syncTrackOverviewSelectionState(updatedOverview);
				setTrackOverviewEditorFocus(trackOverviewFocus);
				return true;
			}

			setTrackOverviewBlockFocus(trackOverviewFocus,
				trackOverviewSelection);
			if(!toplevel.moveEditorCursorToOverviewBlockStart(
					trackOverviewSelection.voice,
					trackOverviewSelection.trackIndex)) {
				clearTrackOverviewBlockSelection(trackOverviewSelection);
				syncTrackOverviewSelectionState(updatedOverview);
				setTrackOverviewEditorFocus(trackOverviewFocus);
				return true;
			}

			int stripWidth = screen.width * FONT_X;
			int contentWidth = trackOverviewContentAreaWidth(stripWidth);
			revealTrackOverviewBlockSelection(trackOverviewScroll,
				trackOverviewSelection, updatedOverview, contentWidth);
			return true;
		}

		void displayTrackOverviewMoveSelectionFailure() {
			if(UI.statusline !is null)
				UI.statusline.displayFailure(
					"Could not move selected track entries.");
		}

		void displayTrackOverviewMoveEntryFailure() {
			if(UI.statusline !is null)
				UI.statusline.displayFailure("Could not move track entry.");
		}

		if(trackOverviewBlockDrag.rangeActive) {
			int movedStartTrackIndex;
			int movedEndTrackIndex;
			if(target.voice == source.voice) {
				if(!toplevel.moveTrackEntryRangeWithinVoice(source.voice,
						trackOverviewBlockDrag.rangeStartTrackIndex,
						trackOverviewBlockDrag.rangeEndTrackIndex,
						target.insertionTrackIndex,
						trackOverviewBlockDrag.rangeTrackValues,
						movedStartTrackIndex, movedEndTrackIndex)) {
					displayTrackOverviewMoveSelectionFailure();
					return false;
				}
			}
			else {
				if(!toplevel.moveTrackEntryRangeToVoice(source.voice,
						trackOverviewBlockDrag.rangeStartTrackIndex,
						trackOverviewBlockDrag.rangeEndTrackIndex,
						target.voice, target.insertionTrackIndex,
						trackOverviewBlockDrag.rangeTrackValues,
						movedStartTrackIndex, movedEndTrackIndex)) {
					displayTrackOverviewMoveSelectionFailure();
					return false;
				}
			}

			int sourceStart = trackOverviewBlockDrag.rangeStartTrackIndex;
			int primaryOffset =
				trackOverviewBlockDrag.rangePrimaryTrackIndex - sourceStart;
			int anchorOffset =
				trackOverviewBlockDrag.rangeAnchorTrackIndex - sourceStart;
			int primaryTrackIndex = movedStartTrackIndex + primaryOffset;
			int anchorTrackIndex = movedStartTrackIndex + anchorOffset;

			auto updatedOverview = buildTrackOverview(song);
			if(!selectTrackOverviewRangeByTrackIndexWithPrimary(
					trackOverviewSelectionState, trackOverviewSelection,
					song.subtune, updatedOverview, target.voice,
					movedStartTrackIndex, movedEndTrackIndex,
					anchorTrackIndex, primaryTrackIndex)) {
				syncTrackOverviewSelectionState(updatedOverview);
				setTrackOverviewEditorFocus(trackOverviewFocus);
				return true;
			}

			setTrackOverviewBlockFocus(trackOverviewFocus,
				trackOverviewSelection);
			if(!toplevel.moveEditorCursorToOverviewBlockStart(
					trackOverviewSelection.voice,
					trackOverviewSelection.trackIndex)) {
				clearTrackOverviewBlockSelection(trackOverviewSelection);
				syncTrackOverviewSelectionState(updatedOverview);
				setTrackOverviewEditorFocus(trackOverviewFocus);
				return true;
			}

			int stripWidth = screen.width * FONT_X;
			int contentWidth = trackOverviewContentAreaWidth(stripWidth);
			revealTrackOverviewBlockSelection(trackOverviewScroll,
				trackOverviewSelection, updatedOverview, contentWidth);
			return true;
		}

		int movedTrackIndex;
		ushort movedTrackValue;
		if(target.voice == source.voice) {
			if(!toplevel.moveTrackEntryWithinVoice(source.voice,
					source.trackIndex, target.insertionTrackIndex,
					source.trackValue, movedTrackIndex, movedTrackValue)) {
				displayTrackOverviewMoveEntryFailure();
				return false;
			}
		}
		else {
			if(!toplevel.moveTrackEntryToVoice(source.voice, source.trackIndex,
					target.voice, target.insertionTrackIndex,
					source.trackValue, movedTrackIndex, movedTrackValue)) {
				displayTrackOverviewMoveEntryFailure();
				return false;
			}
		}

		auto updatedOverview = buildTrackOverview(song);
		return finishTrackOverviewTrackEntryMutation(updatedOverview,
			target.voice, movedTrackIndex, movedTrackValue,
			TrackOverviewTrackEntrySelectionPolicy.ExactTrackIndex);
	}

	private static bool handleTrackOverviewTimelineScrubMotion(int x) {
		if(song is null || toplevel is null)
			return false;

		auto overview = buildTrackOverview(song);
		int stripWidth = screen.width * FONT_X;
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		auto viewport = trackOverviewViewport(overview, contentWidth,
			trackOverviewScroll.scrollX);
		trackOverviewScroll.scrollX = viewport.scrollX;

		int overviewContentWidth = trackOverviewContentWidth(overview);
		int row = trackOverviewTimelineXToRow(x, 0, stripWidth,
			trackOverviewScroll.scrollX, overviewContentWidth);
		if(row < 0)
			return false;

		int activeVoice = toplevel.activeEditorVoice();
		if(activeVoice < 0 || activeVoice >= cast(int)overview.length)
			return false;

		TrackOverviewPosition[] positions =
			trackOverviewTimelinePositionsAtRow(overview, row);
		if(activeVoice >= cast(int)positions.length)
			return false;

		TrackOverviewPosition position = trackOverviewTimelineBestPosition(
			positions, activeVoice);
		if(!position.valid)
			return false;
		bool playbackActive = trackOverviewPlaybackActive();
		bool allVoicesValid = trackOverviewTimelinePositionsAllValid(positions);
		if(playbackActive && !allVoicesValid)
			return false;
		if(!rememberTrackOverviewTimelineScrubTargets(trackOverviewScroll,
				positions))
			return false;
		bool forceSeek = trackOverviewScroll.timelineScrubForceNextSeek;
		trackOverviewScroll.timelineScrubForceNextSeek = false;

		if(allVoicesValid) {
			if(!toplevel.moveEditorCursorToOverviewPositionsSafeForActiveView(
					positions, activeVoice))
				return false;
		}
		else if(!toplevel.moveEditorCursorToOverviewPosition(position))
				return false;

		clearTrackOverviewManualScroll(trackOverviewScroll);
		if(playbackActive) {
			TimelineSeekTarget target;
			target.globalRow = row;
			target.allVoicesValid = allVoicesValid;
			foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
				target.trackOffsets[voice] = positions[voice].trackIndex;
				target.sequenceOffsets[voice] =
					positions[voice].sequenceRowOffset;
			}

			TimelineSeekOptions options;
			options.inputKind = forceSeek ? TimelineSeekInputKind.click :
				TimelineSeekInputKind.dragMotion;
			options.force = forceSeek;
			options.allowThrottle = !forceSeek;
			options.playbackActive = playbackActive;

			TimelineSeekResult result =
				toplevel.checkpointSeekFromCursor(target, options);
			if(result.status == TimelineSeekStatus.failed) {
				playFromCurrentEditorPosition();
			}
		}
		return true;
	}

	private static void displayTrackOverviewQuickHelp() {
		if(!state.displayHelp || UI.statusline is null)
			return;
		TrackOverviewQuickHelpKind kind = trackOverviewQuickHelpKind(
			trackOverviewFocus.kind, trackOverviewSelectionState);
		displayTrackOverviewQuickHelp(kind);
	}

	private static void displayTrackOverviewQuickHelp(
			TrackOverviewQuickHelpKind kind) {
		if(!state.displayHelp || UI.statusline is null)
			return;
		string help = trackOverviewQuickHelpMessage(kind);
		if(help.length == 0)
			return;
		if(UI.statusline.counter != 0 &&
		   UI.statusline.message == help)
			return;
		UI.statusline.displayContextualSemantic(help,
			trackOverviewQuickHelpSemanticContext(kind));
	}

	private static bool handleTrackOverviewDragMotion(int x, int y) {
		if(song is null || toplevel is null)
			return false;

		auto overview = buildTrackOverview(song);
		int stripWidth = screen.width * FONT_X;
		int contentX = trackOverviewContentX(0);
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		auto viewport = trackOverviewViewport(overview, contentWidth,
			trackOverviewScroll.scrollX);
		trackOverviewScroll.scrollX = viewport.scrollX;

		TrackOverviewEditorCursor cursor = editorCursorForOverview(overview);
		return dragTrackOverviewScrollbar(trackOverviewScroll, viewport,
			x - contentX, cursor.valid ? cursor.globalRow : -1);
	}

	private static bool handleTrackOverviewBlockDragMotion(int x, int y) {
		if(song is null || toplevel is null)
			return false;
		if(!updateTrackOverviewBlockDrag(trackOverviewBlockDrag, x, y))
			return false;

		auto overview = buildTrackOverview(song);
		int stripWidth = screen.width * FONT_X;
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		auto viewport = trackOverviewViewport(overview, contentWidth,
			trackOverviewScroll.scrollX);
		trackOverviewScroll.scrollX = viewport.scrollX;
		updateTrackOverviewBlockDropTarget(trackOverviewBlockDrag, overview,
			trackOverviewDragDropTargetX(x, stripWidth), y, 0, 0, stripWidth,
			trackOverviewScroll.scrollX,
			trackOverviewDuplicateDropModeActive());
		return true;
	}

	private bool handleTrackOverviewBlockDragAutoScroll() {
		if(dialog !is null || song is null || toplevel is null)
			return false;
		if(audio.player.isPlaying)
			return false;
		if(trackOverviewScroll.timelineScrubActive ||
				trackOverviewScroll.scrollbarDragActive)
			return false;
		if(!trackOverviewBlockDrag.active)
			return false;

		int stripWidth = screen.width * FONT_X;
		int deltaX = trackOverviewDragEdgeScrollDelta(trackOverviewBlockDrag,
			stripWidth);
		if(deltaX == 0)
			return false;

		auto overview = buildTrackOverview(song);
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		TrackOverviewEditorCursor cursor = editorCursorForOverview(overview);
		bool scrolled = trackOverviewScrollByPixels(trackOverviewScroll,
			overview, contentWidth, deltaX,
			cursor.valid ? cursor.globalRow : -1);
		auto viewport = trackOverviewViewport(overview, contentWidth,
			trackOverviewScroll.scrollX);
		trackOverviewScroll.scrollX = viewport.scrollX;
		bool targetChanged = updateTrackOverviewBlockDropTarget(
			trackOverviewBlockDrag, overview,
			trackOverviewDragDropTargetX(trackOverviewBlockDrag.lastMouseX,
				stripWidth),
			trackOverviewBlockDrag.lastMouseY, 0, 0, stripWidth,
			trackOverviewScroll.scrollX,
			trackOverviewDuplicateDropModeActive());
		return scrolled || targetChanged;
	}

	private static bool trackOverviewDuplicateDropModeActive() {
		uint mods = SDL_GetModState();
		return (mods & KMOD_ALT) != 0 && (mods & KMOD_SHIFT) == 0;
	}

	private static bool handleTrackOverviewBlockDragModifierChange(Keyinfo key) {
		if(key.raw != SDLK_LALT && key.raw != SDLK_RALT &&
				key.raw != SDLK_LSHIFT && key.raw != SDLK_RSHIFT)
			return false;
		if(!trackOverviewBlockDrag.active ||
				!trackOverviewBlockDrag.source.valid)
			return false;
		refreshTrackOverviewBlockDropTargetForCurrentPointer(
			trackOverviewDuplicateDropModeActive());
		return true;
	}

	private static bool refreshTrackOverviewBlockDropTargetForCurrentPointer(
			bool duplicateMode) {
		if(song is null || toplevel is null || !trackOverviewBlockDrag.active ||
				!trackOverviewBlockDrag.source.valid)
			return false;

		auto overview = buildTrackOverview(song);
		int stripWidth = screen.width * FONT_X;
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		auto viewport = trackOverviewViewport(overview, contentWidth,
			trackOverviewScroll.scrollX);
		trackOverviewScroll.scrollX = viewport.scrollX;
		return updateTrackOverviewBlockDropTarget(trackOverviewBlockDrag, overview,
			trackOverviewDragDropTargetX(trackOverviewBlockDrag.lastMouseX,
				stripWidth),
			trackOverviewBlockDrag.lastMouseY, 0, 0, stripWidth,
			trackOverviewScroll.scrollX, duplicateMode);
	}

	private static int trackOverviewDragDropTargetX(int x, int stripWidth) {
		int contentX = trackOverviewContentX(0);
		int contentWidth = trackOverviewContentAreaWidth(stripWidth);
		if(contentWidth <= 0)
			return x;
		if(x < contentX)
			return contentX;
		int rightX = contentX + contentWidth - 1;
		if(x > rightX)
			return rightX;
		return x;
	}

	private static void playFromCurrentEditorPosition() {
		if(toplevel is null)
			return;
		clearTrackOverviewManualScroll(trackOverviewScroll);
		toplevel.playFromCursor();
	}

	private static void playFromCurrentEditorPositionAccurate() {
		if(toplevel is null)
			return;
		clearTrackOverviewManualScroll(trackOverviewScroll);
		if(toplevel.checkpointSeekFromCurrentEditorPosition())
			return;
		toplevel.playFromCursor();
	}

	static void startTrackOverviewPlaybackMarkers() {
		if(song is null)
			return;
		startTrackOverviewPlaybackState(trackOverviewPlayback);
	}

	static void advanceTrackOverviewPlaybackRows(int rows) {
		advanceTrackOverviewPlaybackState(trackOverviewPlayback, rows);
	}

	private static bool trackOverviewPlaybackActive() {
		return audio.player.isPlaying && !audio.player.keyjamEnabled;
	}

	private static TrackOverviewPlaybackCursor playbackCursorForOverview(
			const(TrackOverviewLane)[] overview) {
		int[3] trackIndexes;
		int[3] sequenceRowOffsets;
		foreach(voice; 0 .. 3) {
			trackIndexes[voice] = fplayPos.pos[voice].trkOffset;
			sequenceRowOffsets[voice] = fplayPos.pos[voice].seqOffset;
		}
		return trackOverviewPlaybackCursor(overview, trackOverviewPlayback,
			trackIndexes, sequenceRowOffsets);
	}

	private static TrackOverviewEditorCursor editorCursorForOverview(
			const(TrackOverviewLane)[] overview) {
		TrackOverviewEditorCursor cursor;
		if(toplevel is null)
			return cursor;
		return toplevel.editorCursorForOverview(overview);
	}

	private static TrackOverviewVisualState trackOverviewVisualState() {
		TrackOverviewVisualState visualState;
		foreach(voice; 0 .. visualState.mutedVoices.length) {
			visualState.mutedVoices[voice] = audio.player.muted[voice] != 0;
		}
		visualState.showSelectedBlockPlus =
			trackOverviewFocus.kind == TrackOverviewFocusKind.Block &&
			trackOverviewSelection.valid;
		visualState.showDuplicateDropIndicator =
			trackOverviewBlockDrag.active &&
			trackOverviewBlockDrag.dropTarget.valid &&
			trackOverviewDuplicateDropModeActive();
		return visualState;
	}

	private static TrackOverviewMarkers editorCursorMarkers(
			const TrackOverviewEditorCursor cursor,
			const TrackOverviewPosition[] voicePositions) {
		TrackOverviewMarkers markers;
		if(!cursor.valid || cursor.voice < 0 ||
				cursor.voice >= markers.voiceMarkers.length)
			return markers;

		markers.globalVisible = true;
		markers.globalRow = cursor.globalRow;
		foreach(voice, position; voicePositions) {
			if(voice >= markers.voiceMarkers.length)
				break;
			if(!position.valid)
				continue;
			if(cast(int)voice == cursor.voice)
				continue;
			markers.voiceMarkers[voice].visible = true;
			markers.voiceMarkers[voice].position = position;
		}
		markers.editorVoiceMarker.visible = true;
		markers.editorVoiceMarker.position = cursor.position;
		return markers;
	}

	private static TrackOverviewMarkers playbackMarkers(
			const TrackOverviewPlaybackCursor cursor,
			const TrackOverviewEditorCursor editorCursor) {
		TrackOverviewMarkers markers;
		if(cursor.globalVisible) {
			markers.globalVisible = true;
			markers.globalRow = cursor.globalRow;
		}

		foreach(voice, position; cursor.voicePositions) {
			if(!position.valid)
				continue;
			markers.voiceMarkers[voice].visible = true;
			markers.voiceMarkers[voice].position = position;
		}

		if(editorCursor.valid && editorCursor.voice >= 0 &&
				editorCursor.voice < markers.voiceMarkers.length) {
			markers.editorGlobalVisible = true;
			markers.editorGlobalRow = editorCursor.globalRow;
			markers.editorVoiceMarker.visible = true;
			markers.editorVoiceMarker.position = editorCursor.position;
		}

		return markers;
	}

	private static void applyStoredPlayFromMarker(ref TrackOverviewMarkers markers,
			const(TrackOverviewLane)[] overview) {
		TrackOverviewPosition[TRACK_OVERVIEW_VOICE_LANES] positions;
		if(!storedPlayFromPositions(overview, positions))
			return;

		foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
			if(!positions[voice].valid)
				continue;
			markers.playFromVoiceMarkers[voice].visible = true;
			markers.playFromVoiceMarkers[voice].position = positions[voice];
		}
	}

	private static bool storedPlayFromPositions(const(TrackOverviewLane)[] overview,
			out TrackOverviewPosition[TRACK_OVERVIEW_VOICE_LANES] positions) {
		positions = positions.init;
		if(seqPos is null || overview.length < TRACK_OVERVIEW_VOICE_LANES)
			return false;

		bool anyValid;
		foreach(voice; 0 .. TRACK_OVERVIEW_VOICE_LANES) {
			if(storedPlayFromVoicePosition(overview, cast(int)voice,
					positions[voice]))
				anyValid = true;
		}

		return anyValid;
	}

	private static bool storedPlayFromVoicePosition(
			const(TrackOverviewLane)[] overview, int voice,
			out TrackOverviewPosition position) {
		position = position.init;
		if(voice < 0 || voice >= TRACK_OVERVIEW_VOICE_LANES)
			return false;

		int mark = seqPos.pos[voice].mark;
		if(mark < 0)
			return false;

		foreach(lane; overview) {
			if(lane.voice != voice)
				continue;
			foreach(block; lane.blocks) {
				if(block.trackIndex != mark)
					continue;
				position.valid = true;
				position.voice = voice;
				position.globalRow = block.startRow;
				position.localRow = block.startRow;
				position.trackIndex = block.trackIndex;
				position.blockIndex = -1;
				position.sequenceNumber = block.sequenceNumber;
				position.trackValue = block.trackValue;
				position.sequenceRowOffset = 0;
				return true;
			}
			return false;
		}

		return false;
	}
}
