/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.help;

import std.string : format;
import com.util;
import derelict.sdl2.sdl : KMOD_ALT;
import ui.input : KeyboardHelpRow, KeyboardHelpSection,
	keyboardActionPrimaryShortcutLabel, keyboardActionShortcutLabelList,
	keyboardHelpRowShortcutLabel,
	keyboardHelpRows, keyboardModifierDisplayLabel;

// This module renders canonical keyboard-registry rows and owns Help layout,
// prose, diagrams, and true non-keyboard instructions. Bindings and their
// short Help facts belong to ui.input.

enum int HELP_CONTENT_LINE_WIDTH = 80;

struct ContextHelp {
	string title;
	string[] text;
}

struct HelpInstructionRow {
	string label;
	string description;
}

struct HelpTopicMetadata {
	string id;
	string title;
	string tabLabel;
	string existingContext;
	bool implemented;
	string notes;
}

struct HelpTopicHit {
	bool valid;
	string topicId;
	int topicIndex;
}

enum FocusedHelpFamily {
	unknown,
	sequenceGeneral,
	sequenceNote,
	sequenceInstrument,
	sequenceCommand
}

enum string CHORD_TABLE_TOPIC_ID = "chord_table";
enum ubyte CHORD_JUMP_MARKER_MIN = 0x80;

bool isChordJumpMarker(ubyte value) {
	return value >= CHORD_JUMP_MARKER_MIN;
}

int chordSemitoneOffset(ubyte value) {
	int offset = value;
	if(offset >= 0x40)
		offset -= 0x80;
	return offset;
}

ubyte chordJumpDestination(ubyte value) {
	return cast(ubyte)(value & 0x7f);
}

bool chordShuffleModeForSpeed(ubyte speed) {
	return speed < 2;
}

bool chordRowUsesShuffleQuickHelp(ubyte speed, const(ubyte)[] data, int row) {
	if(!chordShuffleModeForSpeed(speed) || row < 0 || data.length == 0)
		return false;
	if(cast(size_t)row >= data.length)
		return false;

	foreach(size_t index, value; data) {
		if(row == cast(int)index)
			return true;
		if(isChordJumpMarker(value))
			return false;
	}
	return true;
}

enum string CHORD_NORMAL_VALUES_QUICKHELP =
	"Chord: $00-$3F positive; $40-$7F negative.\n" ~
	"$00 unchanged; $07 up 7; $7C down 4.";
enum string CHORD_JUMP_MARKER_QUICKHELP =
	"$80-$FF jump marker; $94 -> row $14.";
enum string CHORD_SHUFFLE_SPEED_QUICKHELP =
	"Speed $0/$1: row $00 stores shuffle lengths.\n" ~
	"Values are frames; use $02-$7F.\n" ~
	"04 06 80 alternates 4/6 then jumps to $00.";

string chordTableQuickHelp(ubyte speed, const(ubyte)[] data, int row) {
	if(chordRowUsesShuffleQuickHelp(speed, data, row))
		return CHORD_SHUFFLE_SPEED_QUICKHELP;
	return CHORD_NORMAL_VALUES_QUICKHELP ~ "\n" ~ CHORD_JUMP_MARKER_QUICKHELP;
}

// Registry-to-presentation adapters and shared shortcut hints.

string helpMoreStatusHint() {
	return "`01[" ~ keyboardActionShortcutLabelList(
		"global.open_help", "/") ~ " for more]";
}

string helpJumpStatusHint() {
	return "`01[" ~ keyboardActionPrimaryShortcutLabel(
		"ui.follow_instrument_pointer") ~ " to jump]";
}

private HelpInstructionRow[] keyboardShortcutHelpRows(
		KeyboardHelpSection section) {
	HelpInstructionRow[] rows;
	foreach(source; keyboardHelpRows(section))
		rows ~= HelpInstructionRow(
			keyboardHelpRowShortcutLabel(source, "/"),
			source.description);
	return rows;
}

private enum string GENERATED_TABLE_ROW_DELETE_KEY_NOTE =
	"Mac Delete is Backspace; Fn-Delete is Forward Delete";

private string generatedTableRowEditHelp() {
	return keyboardActionShortcutLabelList(
		"table.row_insert", " / ") ~ " = insert row\n" ~
		keyboardActionShortcutLabelList(
		"table.row_delete", " / ") ~ " = delete row\n" ~
		GENERATED_TABLE_ROW_DELETE_KEY_NOTE;
}

private string generatedProgramTableRowSelectionHelp() {
	return keyboardActionShortcutLabelList(
			"table.row_selection_extend_up", " / ") ~
		" / " ~ keyboardActionShortcutLabelList(
			"table.row_selection_extend_down", " / ") ~
		" = extend row selection up/down\n" ~
		keyboardActionShortcutLabelList(
			"table.row_selection_extend_page_up", " / ") ~
		" / " ~ keyboardActionShortcutLabelList(
			"table.row_selection_extend_page_down", " / ") ~
		" = extend selection by page\n" ~
		keyboardActionShortcutLabelList(
			"table.row_selection_extend_home", " / ") ~
		" / " ~ keyboardActionShortcutLabelList(
			"table.row_selection_extend_end", " / ") ~
		" = extend selection to first/final row\n" ~
		keyboardActionShortcutLabelList("table.row_selection_clear", " / ") ~
			" = clear selection";
}

private string generatedProgramTableRowHelp() {
	return generatedTableRowEditHelp() ~ "\n" ~
		generatedProgramTableRowSelectionHelp() ~ "\n" ~
		"Click-drag = select rows\n" ~
		"Shift+click = extend row selection\n" ~
		keyboardActionShortcutLabelList("table.row_copy", " / ") ~
			" = copy selected rows\n" ~
		keyboardActionShortcutLabelList("table.row_paste", " / ") ~
			" = paste selected rows";
}

// Shortcut-row layout and wrapping.

private string shortcutHelpPadding(int count) {
	string padding;
	foreach(i; 0 .. count)
		padding ~= " ";
	return padding;
}

private size_t shortcutHelpFirstDescriptionLineLength(string description) {
	size_t length;
	foreach(ch; description) {
		if(ch == '\n')
			break;
		length++;
	}
	return length;
}

private string shortcutHelpWrappedDescription(string description,
		string firstPrefix, string continuationPrefix) {
	string text = firstPrefix;
	size_t lineLength = firstPrefix.length;
	bool lineHasText;
	size_t cursor;

	while(cursor < description.length) {
		if(description[cursor] == '\n') {
			text ~= "\n" ~ continuationPrefix;
			lineLength = continuationPrefix.length;
			lineHasText = false;
			cursor++;
			continue;
		}
		if(description[cursor] == ' ' || description[cursor] == '\t') {
			cursor++;
			continue;
		}

		size_t wordStart = cursor;
		while(cursor < description.length &&
				description[cursor] != ' ' &&
				description[cursor] != '\t' &&
				description[cursor] != '\n')
			cursor++;
		size_t wordEnd = cursor;

		while(wordStart < wordEnd) {
			size_t separatorLength = lineHasText ? 1 : 0;
			size_t available = lineLength + separatorLength <
					HELP_CONTENT_LINE_WIDTH ?
				HELP_CONTENT_LINE_WIDTH - lineLength - separatorLength : 0;
			if(available == 0) {
				text ~= "\n" ~ continuationPrefix;
				lineLength = continuationPrefix.length;
				lineHasText = false;
				continue;
			}

			size_t remaining = wordEnd - wordStart;
			if(lineHasText && remaining > available) {
				text ~= "\n" ~ continuationPrefix;
				lineLength = continuationPrefix.length;
				lineHasText = false;
				continue;
			}
			size_t partLength = remaining < available ? remaining : available;
			if(lineHasText) {
				text ~= " ";
				lineLength++;
			}
			text ~= description[wordStart .. wordStart + partLength];
			lineLength += partLength;
			lineHasText = true;
			wordStart += partLength;

			if(wordStart < wordEnd) {
				text ~= "\n" ~ continuationPrefix;
				lineLength = continuationPrefix.length;
				lineHasText = false;
			}
		}
	}
	return text;
}

private string shortcutHelpLine(const HelpInstructionRow shortcut,
		int labelWidth) {
	string label = shortcut.label;
	int padCount = labelWidth - cast(int)label.length;
	if(padCount < 0)
		padCount = 0;

	string alignedPrefix = label ~ shortcutHelpPadding(padCount) ~ " > ";
	string alignedContinuation = shortcutHelpPadding(labelWidth + 3);
	size_t descriptionLength =
		shortcutHelpFirstDescriptionLineLength(shortcut.description);
	if(alignedPrefix.length + descriptionLength <= HELP_CONTENT_LINE_WIDTH)
		return shortcutHelpWrappedDescription(shortcut.description,
			alignedPrefix, alignedContinuation);

	string compactPrefix = label ~ " > ";
	string compactContinuation =
		shortcutHelpPadding(cast(int)compactPrefix.length);
	if(compactPrefix.length + descriptionLength <= HELP_CONTENT_LINE_WIDTH)
		return shortcutHelpWrappedDescription(shortcut.description,
			compactPrefix, compactContinuation);

	enum int stackedArrowIndent = 5;
	string stackedPrefix = shortcutHelpPadding(stackedArrowIndent) ~ "> ";
	string stackedContinuation =
		shortcutHelpPadding(cast(int)stackedPrefix.length);
	return label ~ "\n" ~ shortcutHelpWrappedDescription(
		shortcut.description, stackedPrefix, stackedContinuation);
}

private int shortcutHelpLabelWidth(const HelpInstructionRow[] shortcuts,
		int labelWidth = 0) {
	foreach(shortcut; shortcuts) {
		int labelLength = cast(int)shortcut.label.length;
		if(labelLength > labelWidth)
			labelWidth = labelLength;
	}
	return labelWidth;
}

private void appendShortcutHelpLines(ref string text,
		const HelpInstructionRow[] shortcuts, int labelWidth) {
	foreach(shortcut; shortcuts) {
		if(text.length > 0)
			text ~= "\n";
		text ~= shortcutHelpLine(shortcut, labelWidth);
	}
}

private string shortcutHelpLines(const HelpInstructionRow[] shortcuts) {
	string text;
	int labelWidth = shortcutHelpLabelWidth(shortcuts);
	appendShortcutHelpLines(text, shortcuts, labelWidth);
	return text;
}

private string shortcutHelpLinesCombined(const HelpInstructionRow[] first,
		const HelpInstructionRow[] second) {
	string text;
	int labelWidth = shortcutHelpLabelWidth(first);
	labelWidth = shortcutHelpLabelWidth(second, labelWidth);
	appendShortcutHelpLines(text, first, labelWidth);
	appendShortcutHelpLines(text, second, labelWidth);
	return text;
}

enum string HELP_BYTE_DESCRIPTIONS_TOGGLE_HINT =
	"Press " ~ keyboardActionShortcutLabelList(
		"ui.toggle_help_text", "/") ~
	" to turn the byte descriptions off.";

// Help topic index and page composition.

enum HelpTopicMetadata[] HELP_TOPIC_METADATA = [
	HelpTopicMetadata(
		"global_overview",
		"Global / overview",
		"Global",
		"HELPMAIN",
		true,
		"Current default/global help context."),
	HelpTopicMetadata(
		"track_overview",
		"Track overview strip",
		"Track strip",
		"HELPTRACKOVERVIEW",
		true,
		"Current Track overview strip contextual help."),
		HelpTopicMetadata(
			"sequence_editor",
			"Sequence editor / Pattern list",
			"Sequence",
			"HELPSEQUENCER",
			true,
			"Current Sequencer help context covers F5/F6/F7 navigation and editing."),
		HelpTopicMetadata(
			"pattern_columns",
			"Pattern columns xxx yy zz",
			"Columns",
			"HELPSEQUENCECOLUMNS",
			true,
			"Current F6 contextual pattern-column reference."),
		HelpTopicMetadata(
			"sequence_instrument_column",
			"Sequence Instrument column",
			"Seq Inst",
			"HELPSEQUENCEINSTRUMENTCOLUMN",
			true,
			"Current F6 Instrument-column contextual help."),
		HelpTopicMetadata(
			"command_effects",
			"Command list / effects",
			"Effects",
			"HELPEFFECTS",
			true,
			"Promoted from Pattern column help into a standalone selectable topic."),
	HelpTopicMetadata(
		"track_table",
		"Track table",
		"Track table",
		"HELPTRACKTABLE",
		true,
		"Promoted from Sequencer help into a standalone selectable topic."),
	HelpTopicMetadata(
		"track_map",
		"Track map",
		"Track map",
		"HELPTRACKMAP",
		true,
		"Promoted from Sequencer help into a standalone selectable topic."),
		HelpTopicMetadata(
			"playback",
			"Playback",
			"Playback",
			"HELPPLAYBACK",
			true,
			"Promoted from Main help into a standalone selectable topic."),
	HelpTopicMetadata(
		"file_app",
		"File/app shortcuts",
		"File/App",
		"HELPFILEAPP",
		true,
		"Promoted from Main help into a standalone selectable topic."),
	HelpTopicMetadata(
		"instrument_table",
		"Instrument table",
		"Instrument",
		"generated player/table help",
		true,
		"Generated table help when player byte descriptions are available."),
	HelpTopicMetadata(
		"command_table",
		"Command table",
		"Command",
		"generated player/table help",
		true,
		"Generated table help when player byte descriptions are available."),
	HelpTopicMetadata(
		"wave_table",
		"Wave table",
		"Wave",
		"generated player/table help",
		true,
		"Generated table help when player byte descriptions are available."),
	HelpTopicMetadata(
		"pulse_table",
		"Pulse table",
		"Pulse",
		"generated player/table help",
		true,
		"Generated table help when player byte descriptions are available."),
		HelpTopicMetadata(
			"filter_table",
			"Filter table",
			"Filter",
			"generated player/table help",
			true,
			"Generated table help when player byte descriptions are available."),
		HelpTopicMetadata(
			CHORD_TABLE_TOPIC_ID,
			"Chord table",
			"Chord",
			"HELPCHORDTABLE",
			true,
			"Current Chord-table contextual help."),
	];

enum size_t HELP_TOPIC_COUNT = HELP_TOPIC_METADATA.length;

struct HelpSessionState {
	int[HELP_TOPIC_COUNT] scrollOffsets;
}

HelpTopicMetadata[] helpTopicMetadataInDisplayOrder() {
	HelpTopicMetadata[] topics;
	foreach(topic; HELP_TOPIC_METADATA)
		topics ~= topic;
	return topics;
}

int helpTopicIndexForId(string topicId) {
	foreach(i, topic; HELP_TOPIC_METADATA) {
		if(topic.id == topicId)
			return cast(int)i;
	}
	return -1;
}

enum size_t HELP_TOPIC_HEADER_LINE_WIDTH = 68;
enum string HELP_TOPIC_HEADER_SEPARATOR = " ";
enum string HELP_TOPIC_HEADER_INACTIVE_COLOR = "`+c";
enum string HELP_TOPIC_HEADER_ACTIVE_COLOR = "`+1";

private string helpTopicHeaderLabelText(const HelpTopicMetadata topic,
										string currentTopicId) {
	if(topic.id == currentTopicId)
		return "[" ~ topic.tabLabel ~ "]";
	return " " ~ topic.tabLabel ~ " ";
}

private string helpTopicHeaderLabel(const HelpTopicMetadata topic,
									string currentTopicId) {
	string color = topic.id == currentTopicId ?
		HELP_TOPIC_HEADER_ACTIVE_COLOR : HELP_TOPIC_HEADER_INACTIVE_COLOR;
	return color ~ helpTopicHeaderLabelText(topic, currentTopicId);
}

private string helpTopicHeader(string currentTopicId) {
	string text = "`+dTopics (" ~ keyboardActionShortcutLabelList(
		"help.topic_previous", "/") ~ "/" ~
		keyboardActionShortcutLabelList("help.topic_next", "/") ~ ")\n";
	string line;
	size_t lineVisibleLength;
	foreach(topic; HELP_TOPIC_METADATA) {
		string labelText = helpTopicHeaderLabelText(topic, currentTopicId);
		string label = helpTopicHeaderLabel(topic, currentTopicId);
		size_t separatorLength = line.length == 0 ?
			0 : HELP_TOPIC_HEADER_SEPARATOR.length;
		if(line.length == 0) {
			line = label;
			lineVisibleLength = labelText.length;
			continue;
		}
		if(lineVisibleLength + separatorLength + labelText.length >
				HELP_TOPIC_HEADER_LINE_WIDTH) {
			text ~= line ~ "\n";
			line = label;
			lineVisibleLength = labelText.length;
		}
		else {
			line ~= HELP_TOPIC_HEADER_SEPARATOR ~ label;
			lineVisibleLength += separatorLength + labelText.length;
		}
	}
	if(line.length > 0)
		text ~= line;
	return text;
}

string helpTopicHeaderText(string currentTopicId) {
	return helpTopicHeader(currentTopicId);
}

HelpTopicHit helpTopicAt(int x, int y, int textOriginX, int headerOriginY,
		string currentTopicId) {
	int labelY = headerOriginY + 1;
	int labelX = textOriginX;
	size_t lineVisibleLength;

	foreach(i, topic; HELP_TOPIC_METADATA) {
		string labelText = helpTopicHeaderLabelText(topic, currentTopicId);
		int separatorLength = lineVisibleLength == 0 ?
			0 : cast(int)HELP_TOPIC_HEADER_SEPARATOR.length;
		if(lineVisibleLength != 0 &&
				lineVisibleLength + separatorLength + labelText.length >
				HELP_TOPIC_HEADER_LINE_WIDTH) {
			labelY++;
			labelX = textOriginX;
			lineVisibleLength = 0;
			separatorLength = 0;
		}
		if(separatorLength) {
			labelX += separatorLength;
			lineVisibleLength += separatorLength;
		}
		if(y == labelY && x >= labelX &&
				x < labelX + cast(int)labelText.length)
			return HelpTopicHit(true, topic.id, cast(int)i);
		labelX += cast(int)labelText.length;
		lineVisibleLength += labelText.length;
	}
	return HelpTopicHit(false, "", -1);
}

private string helpTopicPage(string currentTopicId, string pageText) {
	return helpTopicHeader(currentTopicId) ~ "\n\n" ~ pageText;
}

private string helpTopicIndexLine(const HelpTopicMetadata topic) {
	string label = topic.tabLabel;
	int dotCount = 22 - cast(int)label.length;
	if(dotCount < 1)
		dotCount = 1;
	string dots;
	foreach(i; 0 .. dotCount)
		dots ~= ".";
	return label ~ dots ~ topic.title ~
		(topic.implemented ? "" : " (planned)");
}

private string helpTopicIndex() {
	string text =
		"`+dUnified help browser\n\n" ~
		keyboardActionShortcutLabelList("global.open_help", "/") ~
			" opens help for the current focus.\n" ~
		keyboardActionShortcutLabelList("help.topic_previous", "/") ~ "/" ~
			keyboardActionShortcutLabelList("help.topic_next", "/") ~
			" changes topic while help is open.\n" ~
		keyboardActionShortcutLabelList("help.scroll_up", "/") ~ "/" ~
			keyboardActionShortcutLabelList("help.scroll_down", "/") ~
			" scrolls the current topic.\n\n" ~
		"`+dTopics\n";

	foreach(topic; HELP_TOPIC_METADATA)
		text ~= helpTopicIndexLine(topic) ~ "\n";

	text ~=
		"\nTopics marked planned are future split-outs.\n" ~
		"Generated table topics appear when player data is available.";
	return text;
}

private string helpTopicIdForGeneratedHelpTitle(string title) {
	if(title == "Instrument table")
		return "instrument_table";
	if(title == "Command table")
		return "command_table";
	if(title == "Wave table")
		return "wave_table";
	if(title == "Pulse table")
		return "pulse_table";
	if(title == "Filter table")
		return "filter_table";
	if(title == "Chord table")
		return CHORD_TABLE_TOPIC_ID;
	return "";
}

string helpTopicIdForContext(ContextHelp ctx) {
	if(ctx.title == "Main help")
		return "global_overview";
	if(ctx.title == "Track overview strip help")
		return "track_overview";
	if(ctx.title == "Track table help")
		return "track_table";
	if(ctx.title == "Track map help")
		return "track_map";
	if(ctx.title == "Sequencer help")
		return "sequence_editor";
	if(ctx.title == "Pattern column help")
		return "pattern_columns";
	if(ctx.title == "Sequence Instrument column help")
		return "sequence_instrument_column";
	if(ctx.title == "Effects help")
		return "command_effects";
	if(ctx.title == "Playback help")
		return "playback";
	if(ctx.title == "File/App help")
		return "file_app";
	if(ctx.title == "Chord table help")
		return CHORD_TABLE_TOPIC_ID;
	string generatedTopicId = helpTopicIdForGeneratedHelpTitle(ctx.title);
	if(generatedTopicId.length > 0)
		return generatedTopicId;
	return "";
}

bool staticHelpContextForTopicId(string topicId, out ContextHelp ctx) {
	if(topicId == "global_overview") {
		ctx = HELPMAIN;
		return true;
	}
	if(topicId == "track_overview") {
		ctx = HELPTRACKOVERVIEW;
		return true;
	}
	if(topicId == "track_table") {
		ctx = HELPTRACKTABLE;
		return true;
	}
	if(topicId == "track_map") {
		ctx = HELPTRACKMAP;
		return true;
	}
	if(topicId == "sequence_editor") {
		ctx = HELPSEQUENCER;
		return true;
	}
	if(topicId == "pattern_columns") {
		ctx = HELPSEQUENCECOLUMNS;
		return true;
	}
	if(topicId == "sequence_instrument_column") {
		ctx = HELPSEQUENCEINSTRUMENTCOLUMN;
		return true;
	}
	if(topicId == "command_effects") {
		ctx = HELPEFFECTS;
		return true;
	}
	if(topicId == "playback") {
		ctx = HELPPLAYBACK;
		return true;
	}
	if(topicId == "file_app") {
		ctx = HELPFILEAPP;
		return true;
	}
	if(topicId == CHORD_TABLE_TOPIC_ID) {
		ctx = HELPCHORDTABLE;
		return true;
	}
	return false;
}

ContextHelp contextualHelpForFocusedFamily(FocusedHelpFamily family,
		ContextHelp activeViewContext = ContextHelp.init) {
	final switch(family) {
	case FocusedHelpFamily.unknown:
		break;
	case FocusedHelpFamily.sequenceGeneral:
		return HELPSEQUENCER;
	case FocusedHelpFamily.sequenceNote:
		return HELPSEQUENCECOLUMNS;
	case FocusedHelpFamily.sequenceInstrument:
		return HELPSEQUENCEINSTRUMENTCOLUMN;
	case FocusedHelpFamily.sequenceCommand:
		return HELPEFFECTS;
	}

	if(activeViewContext.title.length > 0 || activeViewContext.text.length > 0)
		return activeViewContext;
	return HELPMAIN;
}

enum string SEQUENCE_ROW_CLIPBOARD_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.sequenceRowClipboard));

enum string TRACK_OVERVIEW_NAVIGATION_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackOverviewNavigation));

enum string TRACK_OVERVIEW_EDIT_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackOverviewEdit));

enum string TRACK_OVERVIEW_DISPLAY_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackOverviewDisplay));

enum string TRACK_OVERVIEW_TIMELINE_HELP =
	"Timeline is true-scale; use scrollbar for long songs.\n\n" ~
	"Speed dot:         voice 1, 2 or 3 has a speed event at this row.\n" ~
	"Click/drag:        Move or scrub the global song position\n" ~
	"During playback:   Scrub restarts playback from that row\n" ~
	"Double-click:      Set active editor voice play-from mark for " ~
		keyboardActionShortcutLabelList("playback.play_from_mark", "/") ~ "\n" ~
	"Play-from markers: Per-voice markers in the timeline\n" ~
	"Scrollbar drag:    Scroll horizontally\n" ~
	"Trackpad/wheel:    Scroll horizontally";

enum string TRACK_OVERVIEW_LANES_HELP =
	"Block click:      Select block and jump editor to its start\n" ~
	"Shift-click:      Select a range in the same voice\n" ~
	"Loop lane click:  Set LOOP target for that voice\n" ~
	"Drag block/range: Move selected track entry/range\n" ~
	keyboardModifierDisplayLabel(KMOD_ALT) ~
		"-drag block/range: Duplicate selected track entry/range\n" ~
	"Drag at edge: Auto-scroll strip\n" ~
	"+ on block:       Create expanded next-unused block\n" ~
	"While playing:    Playback position is unchanged";

enum HelpInstructionRow[] MAIN_SONG_VARIABLE_INSTRUCTIONS = [
	HelpInstructionRow("Click Spd",
		"Edit default song speed directly (hex 0-1F)"),
	HelpInstructionRow("Click St",
		"Edit cursor step value directly (1-9)"),
	HelpInstructionRow("Click Rate 01",
		"Left increases, right decreases multiplier (01-16)"),
	HelpInstructionRow("Click 50/60 Hz",
		"Toggle PAL/NTSC session playback timing; exported Song timing unchanged"),
	HelpInstructionRow("Click Audio icon", "Open Audio Settings"),
	HelpInstructionRow("Click Keyjam icon", "Enable or disable keyjam"),
	HelpInstructionRow("Click Save icon",
		"Save Instrument in byte editor; otherwise save/export Song"),
	HelpInstructionRow("Click Load icon",
		"Load Instrument in byte editor; otherwise load Song"),
];

enum string MAIN_APP_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.mainApp));

enum string MAIN_PLAYBACK_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.mainPlayback));

enum string PLAYBACK_STOPPED_ONLY_EDIT_HELP = "
`+dEdits that need stopped playback

Stop with " ~ keyboardActionShortcutLabelList("playback.stop", " / ") ~
" before changing Track overview track entries or LOOP targets.
While playback is running these edit actions are ignored:

Paste track entries....." ~ keyboardActionShortcutLabelList(
	"track_overview.paste_entries", " / ") ~ "
Insert track entry......" ~ keyboardActionShortcutLabelList(
	"track_overview.insert_entry", " / ") ~ "
Insert copy............." ~ keyboardActionShortcutLabelList(
	"track_overview.insert_copy_entry", " / ") ~ "
Expanded + block........+ on a Track overview block
Delete block/range......" ~ keyboardActionShortcutLabelList(
	"track_overview.delete_selection", " / ") ~ "
Drag/drop blocks........Move a block or selected range
Set LOOP target.........Loop lane click or " ~
keyboardActionShortcutLabelList(
	"track_overview.loop_active_voice", " / ") ~ "

Still works while playing: copy, select/navigate, mute voices, timeline
scrub/restart playback, and the normal transport keys.
";

enum string MAIN_SONG_VARIABLE_HELP =
	shortcutHelpLines(
		keyboardShortcutHelpRows(KeyboardHelpSection.mainSongBeforeClicks) ~
		MAIN_SONG_VARIABLE_INSTRUCTIONS ~
		keyboardShortcutHelpRows(KeyboardHelpSection.mainSongAfterClicks));

enum string MAIN_TABLE_NAVIGATION_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.mainTableNavigation));

enum string MAIN_INSTRUMENT_TABLE_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.mainInstrumentTable));

enum string SAVE_EXPORT_SHORTCUT_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.saveExport));

enum string SAVE_EXPORT_HELP = "
`+dSave/Export settings

" ~ SAVE_EXPORT_SHORTCUT_HELP ~ "

CT (.ct)....Native editable Song/project. Preserves the data needed to reopen
            and continue editing; use this for normal project saving.
SID (.sid)..Playback export for SID players and emulators. Contains the built
            player/music data and init/play metadata; it is not editable.
PRG (.prg)..Embeddable C64 player-and-Song payload, not a BASIC LOAD/RUN
            program. Its first two bytes are the little-endian load address.
            At default Load $1000: init is $1000 (A = zero-based subtune),
            play is $1003, and multispeed play is $1006 when used. The host
            program must call init, then call play at the required cadence.

Fmt.........Select .ct, .prg or .sid and the matching filename suffix.
Load........SID/PRG page-aligned relocation address; default $1000.
ZP..........SID/PRG first byte of the player's two-byte zero-page pointer.
            Default $FB uses $FB/$FC; valid overrides are $02-$FE.
Sub 00......SID/PRG export all subtunes.
Sub 01-32...SID/PRG export one subtune; it becomes output tune 1.
Def 01-32...SID only with Sub 00: tune a SID player starts by default.
Purge yes...SID/PRG remove unused sequences, instruments and tables.
Purge no....SID/PRG retain unused data in the exported file.

Disabled controls do not apply to the selected format.
";

ContextHelp HELPMAIN = ContextHelp("Main help",
[helpTopicPage("global_overview",
helpTopicIndex() ~ "

`+dGlobal shortcuts

" ~ MAIN_APP_HELP ~ "

`+dUndo/Redo

" ~ GLOBAL_UNDO_REDO_HELP ~ "

`+dPlayback

" ~ MAIN_PLAYBACK_HELP ~ "

`+dSong variables

" ~ MAIN_SONG_VARIABLE_HELP ~ "
Base octave......Range 0-6.
Cursor step......Range 1-9.
Tempo speed......2-1F = steady song tempo.
                 0 or 1 = shuffle tempo from Chord row 00.
Shuffle example..Chord row 00 can contain 04 06 80.
                 Set Spd to 1, or use F1 in the command
                 column. 80 wraps the example list.

`+dMoving between tables

" ~ MAIN_TABLE_NAVIGATION_HELP ~ "

`+dInstrument table functions

" ~ MAIN_INSTRUMENT_TABLE_HELP ~ "
		")]);

ContextHelp HELPPLAYBACK = ContextHelp("Playback help",
[helpTopicPage("playback", "`+1`+dPlayback

" ~ MAIN_PLAYBACK_HELP ~ "
" ~ PLAYBACK_STOPPED_ONLY_EDIT_HELP ~ "
")]);

ContextHelp HELPFILEAPP = ContextHelp("File/App help",
[helpTopicPage("file_app", "`+1`+dFile/App

" ~ MAIN_APP_HELP ~ "

" ~ SAVE_EXPORT_HELP ~ "
")]);

ContextHelp HELPSAVE = ContextHelp("File/App help",
[helpTopicPage("file_app", "`+1" ~ SAVE_EXPORT_HELP ~ "

`+dFile/App shortcuts

" ~ MAIN_APP_HELP ~ "
")]);

enum string SEQUENCER_GENERAL_HELP =
	shortcutHelpLines(
		keyboardShortcutHelpRows(
			KeyboardHelpSection.sequencerGeneralBeforeVoiceTab) ~
		keyboardShortcutHelpRows(
			KeyboardHelpSection.sequencerGeneralAfterVoiceTab));

enum string SUBTUNE_DIRECT_EDIT_HELP =
	"Click #xx, edit 00-1F; Up/Down selects a subtune.";

enum string SEQUENCER_VIEW_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.sequencerViews));

enum string TRACK_TABLE_VIEW_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackTableView));

enum string TRACK_MAP_VIEW_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackMapView));

enum string SEQUENCER_NAVIGATION_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.sequencerNavigation));

enum string GLOBAL_UNDO_REDO_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.globalUndoRedo));

enum string SEQUENCE_ROW_COPY_INSERT_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.sequenceDialogs));

enum string SEQUENCE_EDITING_HELP =
	shortcutHelpLines(
		keyboardShortcutHelpRows(KeyboardHelpSection.sequenceTranspose) ~
		keyboardShortcutHelpRows(KeyboardHelpSection.sequenceEditingInput) ~
		keyboardShortcutHelpRows(
			KeyboardHelpSection.sequenceEditingSequencer));

enum string SEQUENCE_ROW_TRANSPOSE_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.sequenceTranspose));

enum string NOTE_COLUMN_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.noteColumn));

enum string TRACK_COLUMN_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackColumn));

enum string TRACK_MAP_COLUMN_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackColumn)[1 .. $]);

enum string TRACK_LOOP_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackLoop));

enum string TRACK_COLUMN_ADVANCED_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackColumnAdvanced));

enum string SEQUENCE_PLAYBACK_MARK_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.sequencePlaybackMarkStart));

enum string SEQUENCE_ROW_PLATFORM_EDIT_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.sequenceRowPlatformEdit));

enum string TRACK_COLUMN_PLATFORM_HELP =
	shortcutHelpLines(keyboardShortcutHelpRows(
		KeyboardHelpSection.trackColumnPlatform));

enum string TRACK_COLUMN_COMBINED_HELP =
	shortcutHelpLinesCombined(
		keyboardShortcutHelpRows(KeyboardHelpSection.trackColumn),
		keyboardShortcutHelpRows(KeyboardHelpSection.trackColumnPlatform));

enum string TRACK_MAP_COLUMN_COMBINED_HELP =
	shortcutHelpLinesCombined(
		keyboardShortcutHelpRows(KeyboardHelpSection.trackColumn)[1 .. $],
		keyboardShortcutHelpRows(KeyboardHelpSection.trackColumnPlatform));

enum string SEQUENCE_ROW_EDIT_HELP =
	SEQUENCE_PLAYBACK_MARK_HELP ~ "

`+dSequence row editing

" ~ SEQUENCE_ROW_COPY_INSERT_HELP ~ "
" ~ SEQUENCE_ROW_CLIPBOARD_HELP ~ "
" ~ SEQUENCE_ROW_PLATFORM_EDIT_HELP;

enum string COMMAND_EFFECTS_HELP = "
`+dzz command/effect column

-- or 00........No command
01-3F...........Run command table entry 01-3F
40-5F...........Set pulse table program 00-1F
60-7F...........Set filter table program 00-1F
80-9F...........Set chord program 00-1F
A0-AF...........Set attack 0-F
B0-BF...........Set decay 0-F
C0-CF...........Set sustain 0-F
D0-DF...........Set release 0-F
E0-EF...........Set SID master volume 0-F
F0..............Export sync marker for demo/code events
F1..............Use Chord table row 00 as shuffle tempo list
F2-FF...........Set fixed playback speed 2-F

`+dCommand table entries

Command table rows contain command number plus parameters.
0...............Slide up
1...............Slide down
2...............Hi-fi vibrato
3...............Detune current note
4...............Set ADSR for current note
5...............Lo-fi vibrato
6...............Set wave
7...............Portamento a tied note
8...............Stop portamento";

ContextHelp HELPSEQUENCECOLUMNS = ContextHelp("Pattern column help",
[helpTopicPage("pattern_columns", "`+1`+dF7 voice/pattern row columns

Patterns are constructed in the format below

xxx yy zz
xxx = Note........Note/action column
yy = Instrument...Instrument column
zz = Command......Command/effect byte

`+dxxx note column

---.............Empty/rest
===.............Gate off/key off
+++.............Gate on/key on
Notes...........Keyboard note keys enter notes at base octave.
Octave keys.....0-8 retune an existing note when it stays in range.
Range...........Source note values 03-5E; out-of-range displays ???.
Row tint........Sequence row-number tint follows the Track Overview block for
                the current physical Sequence occurrence. It is visual only.

`+dCopy/paste pattern rows

These copy/paste the selected pattern rows, including notes.
" ~ SEQUENCE_ROW_CLIPBOARD_HELP ~ "

`+dTranspose pattern rows

" ~ SEQUENCE_ROW_TRANSPOSE_HELP ~ "

`+dyy instrument column

00-2F...........Instrument number
--..............No instrument on this row

`+dPattern column shortcuts

" ~ NOTE_COLUMN_HELP ~ "

" ~ COMMAND_EFFECTS_HELP ~ "
")]);

ContextHelp HELPSEQUENCEINSTRUMENTCOLUMN = ContextHelp(
		"Sequence Instrument column help",
[helpTopicPage("sequence_instrument_column",
"`+1`+dF6 Instrument column

The Instrument field is the middle value in a Sequence row:

xxx yy zz
yy = Instrument...Instrument number used by this row

00-2F...........Instrument number
--..............No instrument on this row

`+dInstrument-column shortcuts

" ~ shortcutHelpLines(keyboardShortcutHelpRows(
	KeyboardHelpSection.sequenceEditingInput)) ~ "
")]);

ContextHelp HELPEFFECTS = ContextHelp("Effects help",
	[helpTopicPage("command_effects", "`+1" ~ COMMAND_EFFECTS_HELP ~ "
")]);

ContextHelp HELPCHORDTABLE = ContextHelp("Chord table help",
	[helpTopicPage(CHORD_TABLE_TOPIC_ID, "`+1`+dChord table

The Chord table supplies relative semitone patterns. Sequence commands $80-$9F
select Chord programs $00-$1F.

`+dNormal values

$00-$3F........Transpose upwards by 0-63 semitones.
$40-$7F........Transpose downwards by 64-1 semitones.
$00............Leaves the current note unchanged.

These are semitone offsets from the current note, not absolute note numbers.
For example, $07 is seven semitones above the current note, and $7C is four
semitones below it.

`+dJump markers

$80-$FF........Jump to Chord row $00-$7F.

The jump destination is the value without its leading high bit: $94 jumps to
row $14. A jump marker can send playback backwards and therefore create a loop,
but there is no separate loop opcode. Referenced Chord programs must contain a
jump marker before the table ends for valid export.

`+dShuffle timing

At song speed 0 or 1, Chord row $00 is used as a shuffle row-length list.
Sequence command F1 sets speed 1 and therefore selects this timing mode.
Values are playback-frame row lengths; use $02-$7F for useful row lengths.

Example:

04 06 80

This alternates row lengths of four and six frames, then $80 jumps back to
row $00. PAL/NTSC changes the duration of each frame, not the stored values.

`+dPractical notes

Chord program starts are derived from jump markers in the table. Loading a new
Instrument resets active Chord state until a Sequence Chord command selects a
program. The editor permits any byte; malformed jumps are not corrected
automatically.

" ~ HELP_BYTE_DESCRIPTIONS_TOGGLE_HINT ~ "
")]);

ContextHelp HELPTRACKTABLE = ContextHelp("Track table help",
	[helpTopicPage("track_table", "`+1`+dTrack table / order list

" ~ TRACK_TABLE_VIEW_HELP ~ "

`+dTrack column

" ~ TRACK_COLUMN_COMBINED_HELP ~ "

`+dTrack LOOP terminology

Track lists have an end marker displayed as LOOP.
That LOOP/end marker stores the target track position to wrap to.
" ~ TRACK_LOOP_HELP ~ "

For a musical ending, set LOOP to a silent/rest sequence.
The player does not auto-stop at the track end marker.

`+dTrack column advanced

" ~ TRACK_COLUMN_ADVANCED_HELP ~ "
")]);

ContextHelp HELPTRACKMAP = ContextHelp("Track map help",
[helpTopicPage("track_map", "`+1`+dTrack map

" ~ TRACK_MAP_VIEW_HELP ~ "

Track map shows all three voice order lists side by side.
Each row shows sequence, row count, and running song row position.

`+dTrack map entries

" ~ TRACK_MAP_COLUMN_COMBINED_HELP ~ "

`+dTrack LOOP terminology

Track lists have an end marker displayed as LOOP.
That LOOP/end marker stores the target track position to wrap to.
" ~ TRACK_LOOP_HELP ~ "

For a musical ending, set LOOP to a silent/rest sequence.
The player does not auto-stop at the track end marker.

`+dTrack column advanced

" ~ TRACK_COLUMN_ADVANCED_HELP ~ "
")]);

ContextHelp HELPSEQUENCER = ContextHelp("Sequencer help",
[helpTopicPage("sequence_editor", "`+1`+dGeneral

" ~ SEQUENCER_GENERAL_HELP ~ "

" ~ SUBTUNE_DIRECT_EDIT_HELP ~ "

`+dSequencer views

" ~ SEQUENCER_VIEW_HELP ~ "

" ~ SEQUENCER_NAVIGATION_HELP ~ "

`+dTrack overview strip

`+dTimeline

" ~ TRACK_OVERVIEW_TIMELINE_HELP ~ "

`+dTrack lanes V1/V2/V3

" ~ TRACK_OVERVIEW_LANES_HELP ~ "

`+dTrack overview keyboard

" ~ TRACK_OVERVIEW_NAVIGATION_HELP ~ "

`+dTrack overview strip display

Block colours............Same sequence number uses the same colour
Voice cursors............Each lane shows resolved play/edit position
Note previews............Small note shapes show note activity in blocks
Loop lines...............Show each voice's LOOP range once
Timeline side edges......Clicking padding clamps to nearest valid row

`+dSequence editing
" ~ SEQUENCE_ROW_EDIT_HELP ~ "
" ~ SEQUENCE_EDITING_HELP ~ "
"), "`+dIn the note column (F6)

 2 3   5 6 7   9 0
Q W E R T Y U I O P.......Enter notes (base octave+1)
 S D   G H J
Z X C V B N M.............Enter notes (base octave)

" ~ NOTE_COLUMN_HELP ~ "
", "`+dIn the track column (F5)

" ~ TRACK_COLUMN_COMBINED_HELP ~ "
", "`+dTrack LOOP terminology

Track lists have an end marker displayed as LOOP.
That LOOP/end marker stores the target track position to wrap to.
" ~ TRACK_LOOP_HELP ~ "

For a musical ending, set LOOP to a silent/rest sequence.
The player does not auto-stop at the track end marker.

`+dTrack column advanced

" ~ TRACK_COLUMN_ADVANCED_HELP ~ "
"]);

ContextHelp HELPTRACKOVERVIEW = ContextHelp("Track overview strip help",
[helpTopicPage("track_overview", "`+dTrack overview strip

`+dTimeline

" ~ TRACK_OVERVIEW_TIMELINE_HELP ~ "

`+dTrack lanes V1/V2/V3

" ~ TRACK_OVERVIEW_LANES_HELP ~ "

`+dTrack overview keyboard

" ~ TRACK_OVERVIEW_NAVIGATION_HELP ~ "

`+dTrack entry edits

" ~ TRACK_OVERVIEW_EDIT_HELP ~ "
Edits while playing......Ignored until playback is stopped

`+dPlayback and display

" ~ TRACK_OVERVIEW_DISPLAY_HELP ~ "
Block colours............Same sequence number uses the same colour
Voice cursors............Each lane shows resolved play/edit position
Note previews............Small note shapes show note activity in blocks
Loop lines...............Show each voice's LOOP range once
" ~ keyboardActionShortcutLabelList("global.open_help", "/") ~
"......................Track overview strip help
")]);

private enum string FILTER_TABLE_HELP = "
Format: rr: ab cd ef gh

Each pair is one byte. Each letter is one hex nibble.
The first byte ab decides the row type.

`+dSweep row

ab = 00-7F = duration in frames
     00 still applies the row once before advancing

cd = signed and scaled cutoff change
     00 = hold
     01-7F = add upward
     80-FF = subtract downward
     40 changes the cutoff byte by about +$10 per frame
     C0 changes the cutoff byte by about -$10 per frame
     The signed step is applied at one quarter cutoff-byte unit per update.
     Fractional movement is accumulated between updates.

ef = starting filter cutoff byte
     00-FE = set cutoff
     FF = keep current cutoff

gh = next / jump / stop
     00    = continue to next row
     01-3F = jump to filter row
     7F    = stop filter program
     40-7E and 80-FF are unsupported

`+dSweep examples

06 40 FF 7F > For 6 frames, add about +$10 to cutoff each frame, then stop.
06 C0 FF 7F > For 6 frames, change cutoff by about -$10 each frame, then stop.
10 04 20 00 > Set cutoff=$20, add slowly for $10 frames, then continue.
06 00 FF 10 > Hold for 6 frames, then jump to row $10.

`+dSetup row

ab = 80-FF = filter mode/setup byte
     a = mode nibble
     b = stored but ignored by playback; use 0 in help/examples
     Canonical setup form uses x0.

`+dMode values

80-8F = no filter mode
90-9F = low-pass
A0-AF = band-pass
B0-BF = low-pass + band-pass
C0-CF = high-pass
D0-DF = low-pass + high-pass
E0-EF = band-pass + high-pass
F0-FF = low-pass + band-pass + high-pass

cd = resonance + voice/input mask
     c = resonance 0-F
     d = voice/input mask

`+dVoice/input mask

1 = voice 1
2 = voice 2
4 = voice 3
8 = external input
Add values for combinations.
Example: 7 = voices 1+2+3, F = voices 1+2+3 + external input.

ef = starting filter cutoff byte
     00-FE = set cutoff
     FF = keep current cutoff

gh = next / jump / stop
     00    = continue to next row
     01-3F = jump to filter row
     7F    = stop filter program
     40-7E and 80-FF are unsupported

`+dSetup examples

90 F4 40 01 > Low-pass, resonance F, voice 3, set cutoff=$40,
               then jump to row $01.
A0 72 20 01 > Band-pass, resonance 7, voice 2, set cutoff=$20,
               then jump to row $01.
C0 11 80 01 > High-pass, resonance 1, voice 1, set cutoff=$80,
               then jump to row $01.
F0 F7 60 01 > Low+band+high, resonance F, voices 1+2+3,
               set cutoff=$60, then jump to row $01.

`+dRows

" ~ generatedProgramTableRowHelp() ~ "
";

private enum string PULSE_TABLE_HELP = "
Format: rr: ab cd ef gh

ab = duration and direction
     00-7F = increase for the low-seven-bit duration counter
     80-FF = decrease for the low-seven-bit duration counter
     00 and 80 still apply the row once before advancing

cd = pulse-width change each frame
     00 = hold
     01-FF = step amount per update
     Direction comes from ab. The step is not shifted or scaled.

ef = packed starting pulse width
     ef = XY    > pulse width $0YX0
          eg 01 > pulse width $0100
          eg 10 > pulse width $0010
          eg 48 > pulse width $0840
     FF = keep current pulse width before packing

gh = next / jump / stop
     00    = continue to next row
     01-3F = jump to pulse row
     7F    = stop pulse program
     40-7E and 80-FF are unsupported

`+dPulse examples

04 02 48 7F > Set pulse width $0840, increase by $02, then stop.
06 10 FF 7F > Keep current pulse width, increase by $10, then stop.
86 08 FF 7F > Keep current pulse width, decrease by $08, then stop.
04 01 48 02 > Set pulse width $0840, increase slowly, then jump to row $02.

`+dRows

" ~ generatedProgramTableRowHelp() ~ "
";

private enum string WAVE_TABLE_HELP = "
Format: ab cd

ab = note / transpose / flow
     00-7D = relative note offset
     7E    = loop previous wave row; cd is ignored
     7F    = jump marker; cd is target row
     80-FF = absolute note

cd = waveform / delay / target
     00    = keep current waveform/control
     01-0F = hold/delay in frames
     10-DF = waveform/control
             high nibble: 1 tri, 2 saw, 4 pulse, 8 noise
             low nibble:  1 gate, 2 sync, 4 ring, 8 test
     E0-FF = control-only; low nibble sets gate/sync/ring/test

`+dWave examples

00 41 > same note, pulse waveform with gate
00 03 > hold for 3 frames, no waveform change
7E 00 > loop previous row
7F 04 > jump to wave row 04

`+dRows

" ~ generatedProgramTableRowHelp() ~ "
";

private enum string COMMAND_TABLE_HELP = "
Format: x-yy zz

Commands
x = 0 = Slide up: yyzz is slide speed
x = 1 = Slide down: yyzz is slide speed
x = 2 = Hi-fi vibrato
        yy low nibble = feel
        zz high nibble = speed
        zz low nibble = depth divider
x = 3 = Detune current note: yyzz is signed 16-bit
x = 4 = Set ADSR: yy = attack/decay, zz = sustain/release
x = 5 = Lo-fi vibrato: yy = speed, zz = depth
x = 6 = Set wave: yy unused, zz = SID waveform/control
x = 7 = Portamento tie note: yy low nibble + zz = speed
x = 8 = Stop portamento
";

private enum string INSTRUMENT_TABLE_HELP = "
Byte selection:
        Shift+Left/Right selects complete bytes in the current Instrument row.
        Click-drag selects complete bytes in the current Instrument row.
        Shift+click extends byte selection from the current byte.
        Copy with a byte selection copies those bytes; with no byte selection,
        Copy copies the whole Instrument.
        Paste uses the most recently copied Instrument data: selected bytes or
        the whole Instrument.
        Escape clears the visible byte selection.
        Changing Instrument clears only the visible selection; copied bytes
        remain available.

Byte 1: Attack / decay
        ADSR attack in high nibble, decay in low nibble.

Byte 2: Sustain / release
        ADSR sustain in high nibble, release in low nibble.

Byte 3: Restart mode / wave timing
        $00 mode         = 3-frame restart
        $40 mode         = Soft restart
        $80 mode         = Hard restart
        Low nibble $0-$F = wave timing delay
        
        Mode bits and low nibble can be combined, e.g. $45 or $8A.

Byte 4: Hard-restart waveform
        SID waveform/control value used during hard restart.

Byte 5: Filter table pointer
        $00     = no filter reset
        $01-$3F = Filter table row

Byte 6: Pulse table pointer / direct pulse
        $00     = no pulse reset
        $01-$3F = Pulse table row
        $8x-$Fx = set pulse width $x00
                  High nibble 8-F selects direct mode.
                  Example: $8B and $FB both give pulse $B00.

Byte 7: Hard-restart sustain/release
        SR envelope value used during hard restart.

Byte 8: Wave table pointer
        $00-$FF = Wave table row
        Must point to a valid wrapping Wave program.
";

ContextHelp genPlayerContextHelp(string title, char*[] descriptions) {
	string text;
	text = "`+1`+d" ~ title ~ "\n";
	if(title == "Instrument table") {
		auto instrumentFileShortcuts = keyboardShortcutHelpRows(
			KeyboardHelpSection.mainInstrumentTable)[0 .. 2];
		text ~= "\n" ~ shortcutHelpLines(instrumentFileShortcuts) ~
			"\n\n`+dActive Instrument\n" ~
			shortcutHelpLines(keyboardShortcutHelpRows(
				KeyboardHelpSection.mainInstrumentSelection)) ~
			"\n\n`+dInstrument byte settings\n" ~
			INSTRUMENT_TABLE_HELP;
	}
	else if(title == "Filter table") {
		// Filter F12 help is curated here so it does not mix terse player
		// metadata with expanded user-facing nibble documentation.
		text ~= "\n" ~ FILTER_TABLE_HELP;
	}
	else if(title == "Pulse table") {
		text ~= "\n" ~ PULSE_TABLE_HELP;
	}
	else if(title == "Wave table") {
		text ~= "\n" ~ WAVE_TABLE_HELP;
	}
	else if(title == "Command table") {
		text ~= "\n" ~ COMMAND_TABLE_HELP;
	}
	else {
		foreach(idx, char* line; descriptions) {
			text ~= format("\n`0fByte %d: %s", idx + 1, petscii2D(line));
		}
	}
	if(title == "Wave table") {
		text ~= "\n\n`+dWave table shortcuts\n";
		text ~= shortcutHelpLines(keyboardShortcutHelpRows(
			KeyboardHelpSection.waveTableHelp));
	}
	text ~= "\n\n" ~ HELP_BYTE_DESCRIPTIONS_TOGGLE_HINT;
	string topicId = helpTopicIdForGeneratedHelpTitle(title);
	if(topicId.length > 0)
		text = helpTopicPage(topicId, text);
	ContextHelp ctx = ContextHelp(title, [text]);
	return ctx;
}
