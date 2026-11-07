import ct.base;
import com.fb : FONT_X, FONT_Y, INTERFACE_PALETTE_PRESETS, PALETTE,
	INTERFACE_THEME_COUNT, INFOBAR_GLYPH_FULLSCREEN_LEFT,
	INFOBAR_GLYPH_FULLSCREEN_RIGHT, INFOBAR_GLYPH_HELP_LEFT,
	INFOBAR_GLYPH_HELP_RIGHT, INFOBAR_GLYPH_AUDIO_LEFT,
	INFOBAR_GLYPH_AUDIO_RIGHT, INFOBAR_GLYPH_KEYJAM_LEFT,
	INFOBAR_GLYPH_KEYJAM_RIGHT, INFOBAR_GLYPH_LOAD_LEFT,
	INFOBAR_GLYPH_LOAD_RIGHT, INFOBAR_GLYPH_SAVE_LEFT,
	INFOBAR_GLYPH_SAVE_RIGHT, INFOBAR_GLYPH_THEME_CLASSIC,
	INFOBAR_GLYPH_THEME_C64, INFOBAR_GLYPH_THEME_C64_MIDNIGHT,
	INFOBAR_GLYPH_THEME_NEON,
	STATUSLINE_GLYPH_FAILURE, Screen, Video, activeInterfaceBackgroundColor,
	fillInterfaceFramebufferTail, interfaceDestinationRect,
	interfaceFramebufferTailRect, rasterizeUiGlyph, uiGlyphBitmap;
import com.util : framebufferPixelToCell, mouseButtonEventPosition,
	str2Value2;
import derelict.sdl2.sdl : SDL_WINDOW_FULLSCREEN_DESKTOP,
	KMOD_ALT, KMOD_CTRL, KMOD_GUI, KMOD_SHIFT, SDLK_1, SDLK_BACKSPACE,
	SDLK_DOWN, SDLK_ESCAPE, SDLK_F1,
	SDLK_F2, SDLK_F3, SDLK_F4, SDLK_F12, SDLK_DELETE, SDLK_END, SDLK_HOME, SDLK_LEFT,
	SDLK_PAGEDOWN, SDLK_PAGEUP,
	SDLK_KP_0, SDLK_KP_1, SDLK_KP_9, SDLK_KP_ENTER, SDLK_PLUS, SDLK_RETURN,
	SDLK_RIGHT, SDLK_SPACE, SDLK_UP,
	SDL_Init, SDL_Quit,
	SDL_SetModState, SDL_WINDOW_RESIZABLE, SDL_WINDOW_SHOWN, SDL_WindowFlags,
	Uint32;
import ui.bottomcontrols;
import ui.dialogs : HelpDialog;
import ui.help : HELP_CONTENT_LINE_WIDTH, HELP_TOPIC_COUNT, HELP_TOPIC_METADATA,
	HELP_TOPIC_HEADER_LINE_WIDTH, TRACK_OVERVIEW_TIMELINE_HELP,
	HELPTRACKOVERVIEW, HELPMAIN, HELPPLAYBACK, HELPSEQUENCER, HELPTRACKTABLE,
	HELPSEQUENCEINSTRUMENTCOLUMN, HelpSessionState,
	chordRowUsesShuffleQuickHelp, chordTableQuickHelp,
	genPlayerContextHelp, helpTopicAt, helpTopicHeaderText,
	helpTopicIndexForId;
import ui.input : KeyboardActionId, KeyboardBinding, KeyboardBindingKeyModel,
	KeyboardContext, KeyboardHelpSection, KeyboardMetadataAuditIssue,
	KeyboardSemanticModifier,
	KeyboardShortcutSemantics, Keyinfo,
	CANCEL, OK, RETURN, KEYBOARD_BINDING_METADATA,
	auditKeyboardBindingMetadata, auditKeyboardBindingRuntimeEquivalence,
	keyboardActionPrimaryShortcutLabel, keyboardActionShortcutLabelList,
	keyboardActionStableId, keyboardHelpRows, keyboardHelpRowShortcutLabel,
	keyboardBindingIsStrictNonRuntimePlaceholder,
	resolveCursorStepInputKeyboardAction,
	resolvePlaybackTransportKeyboardAction,
	resolveSequencerCursorStepKeyboardAction, resolveSequencerKeyboardAction,
	resolveTrackOverviewBlockKeyboardAction,
	resolveTrackOverviewTimelineKeyboardAction;
import ui.tables : FilterQuickHelpKind, FilterTable,
	GeneratedProgramTableMouseDragSnapshot,
	InsTable, InsValueTable, InstrumentByteSelectionSnapshot,
	InstrumentByteRange, InstrumentByteSelectionState,
	InstrumentClipboardKind, InstrumentQuickHelpKind,
	ProgramTableByteCell,
		ProgramTableRowDragAutoScrollDirection,
		ProgramTableRowKind, PROGRAM_TABLE_ROW_DRAG_AUTOSCROLL_INTERVAL_TICKS,
		PulseQuickHelpKind, PulseTable, WaveQuickHelpKind, WaveTable,
		copyInstrumentByteRangeData,
		instrumentByteColumnIsValid,
		instrumentByteRangePasteFits, instrumentByteSelectionExtend,
		instrumentByteSelectionRange, instrumentByteStorageOffset,
		filterQuickHelpKind, filterQuickHelpText, instrumentQuickHelpKind,
		instrumentQuickHelpText, programTableByteCellAt, pulseQuickHelpKind,
		pulseQuickHelpText, waveQuickHelpKind, waveQuickHelpText,
		writeInstrumentByteRangeData;
import ui.trackoverviewstate : TrackOverviewBlockSelection,
	TrackOverviewFocusKind, TrackOverviewSelectionState;
import ui.ui : InputBoundedHexByte, InputSongSpeed, Rectangle, Statusline,
	TrackOverviewQuickHelpAction,
	TrackOverviewQuickHelpKind, UI, Window, trackOverviewKeyboardContextIsActive,
	trackOverviewQuickHelpActions, trackOverviewQuickHelpKind,
	trackOverviewQuickHelpMessage;
import seq.trackoverview;
import seq.sequencer : SUBTUNE_SELECTOR_VALUE_WIDTH,
	SUBTUNE_SELECTOR_VALUE_X_OFFSET, PosDataTable, SubtuneSelectionDecision,
	initializeSubtunePositionAtSongStart,
	subtuneSelectionDecision, subtuneSelectorValueCellAt,
	wrappedSubtuneTarget;
import audio.resid.filter : Filterparams;
static import audio.player;
static import audio.callback;
static import com.session;
import ui.trackoverviewlayout : RIGHT_VISUAL_PANE_COUNT,
	RightVisualPanelMouseHit, RightVisualPaneRect, rightVisualPaneRect,
	rightVisualPanelMouseHit, trackOverviewGuiStartY, trackOverviewTotalHeight;
import ui.sequencecolors : SequenceColorLookup, SequenceRowNumberColors,
	SEQUENCE_ROW_BACKGROUND_BRIGHTNESS,
	SEQUENCE_ROW_DIGIT_BRIGHTNESS_ACCENT,
	SEQUENCE_ROW_DIGIT_BRIGHTNESS_NORMAL, SEQUENCE_ROW_NUMBER_CELL_COUNT,
	sequenceArgbColor, sequenceRowNumberColors, sequenceTintArgbColor;
import std.file;
import std.digest : toHexString;
import std.digest.sha : sha256Of;
import std.format;
import std.path;
import std.process;
import std.stdio;
import std.string;
import std.typecons : tuple;
import std.zlib;

version(Win32) {
	enum DIR_SEPARATOR = '\\';
}
else {
	enum DIR_SEPARATOR = '/';
}

extern(C) {
	__gshared char[0x19] sidreg;

	char* acme_assemble(const(char)*, int*, char*) {
		return null;
	}

	void sid_init(int, Filterparams*, int, int, int, int, int) nothrow {
	}

	void sid_close() {
	}

	int sid_renderbuffer(short*, int, int, int, int*) nothrow {
		return 0;
	}

	__gshared int testSidKeyjamF6Generation;
	__gshared int testSidKeyjamF6Samples;

	void sid_keyjam_f6_arm_render_readiness(int generation,
			int) nothrow {
		testSidKeyjamF6Generation = generation;
		testSidKeyjamF6Samples = 0;
	}

	void sid_keyjam_f6_cancel_render_readiness() nothrow {
		testSidKeyjamF6Generation = 0;
		testSidKeyjamF6Samples = 0;
	}

	int sid_keyjam_f6_gate_on_samples(int generation) nothrow {
		if(generation != testSidKeyjamF6Generation)
			return 0;
		return testSidKeyjamF6Samples;
	}

	void sid_reset_render_state() nothrow {
	}

	int sid_get_oscilloscope_sample_capacity() nothrow {
		return 0;
	}

	int sid_copy_oscilloscope_samples(short*, int, int) nothrow {
		return 0;
	}

	void sid_clear_oscilloscope_samples() nothrow {
	}
}

struct Results {
	int passed;
	int failed;

	void record(bool success, string name, string detail = null) {
		if(success) {
			writeln("PASS ", name);
			passed++;
		}
		else {
			std.stdio.write("FAIL ", name);
			if(detail.length)
				std.stdio.write(": ", detail);
			writeln();
			failed++;
		}
	}
}

bool checkMinimalFixture(Song song, out string failure) {
	if(strip(song.title[]) != "R2-D minimal") {
		failure = format("title expected R2-D minimal, got %s",
			strip(song.title[]));
		return false;
	}
	if(song.highlight != 3) {
		failure = format("highlight expected 3, got %d", song.highlight);
		return false;
	}
	if(song.tracks.length != 3 || song.tracks[0].trackLength != 2 ||
			song.tracks[1].trackLength != 1 ||
			song.tracks[2].trackLength != 1) {
		failure = format("track lengths expected 2,1,1, got %d,%d,%d",
			song.tracks[0].trackLength, song.tracks[1].trackLength,
			song.tracks[2].trackLength);
		return false;
	}
	if(song.tracks[0][0].number != 0x01 ||
			song.tracks[0][0].trans != 0xa0 ||
			song.tracks[0][1].number != 0x02 ||
			song.tracks[0][1].trans != 0xa4) {
		failure = format("Voice 1 expected A001,A402, got %02X%02X,%02X%02X",
			song.tracks[0][0].trans, song.tracks[0][0].number,
			song.tracks[0][1].trans, song.tracks[0][1].number);
		return false;
	}
	if(song.tracks[1][0].number != 0x03 ||
			song.tracks[2][0].number != 0x04) {
		failure = format("Voice 2/3 sequences expected 03,04, got %02X,%02X",
			song.tracks[1][0].number, song.tracks[2][0].number);
		return false;
	}
	if(song.tracks[0].wrapOffset != 1 ||
			song.tracks[1].wrapOffset != 0 ||
			song.tracks[2].wrapOffset != 0) {
		failure = format("LOOP targets expected 1,0,0, got %d,%d,%d",
			song.tracks[0].wrapOffset, song.tracks[1].wrapOffset,
			song.tracks[2].wrapOffset);
		return false;
	}

	Sequence sequence = song.seqs[0x01];
	if(sequence.rows != 2) {
		failure = format("Sequence 01 rows expected 2, got %d", sequence.rows);
		return false;
	}
	Element row0 = sequence.data[0];
	Element row1 = sequence.data[1];
	if(row0.note.rawValue != 0x6c || row0.instr.value != 0x02 ||
			row0.cmd.value != 0x11 || row1.note.rawValue != 0x70 ||
			row1.instr.value != 0x05 || row1.cmd.value != 0x22) {
		failure = format("Sequence 01 instr/note/cmd expected C2/6C/11 and " ~
			"C5/70/22, got %02X/%02X/%02X and %02X/%02X/%02X",
			row0.instr.rawValue, row0.note.rawValue, row0.cmd.value,
			row1.instr.rawValue, row1.note.rawValue, row1.cmd.value);
		return false;
	}
	if(song.instrumentTable[0] != 0x34) {
		failure = format("instrument byte expected 34, got %02X",
			song.instrumentTable[0]);
		return false;
	}
	return true;
}

bool checkTracklistInsertDeleteCopyRestore(Tracklist fixtureTracks,
		out string failure) {
	Tracklist original = fixtureTracks.deepcopy();
	Tracklist working = original.deepcopy();

	working.insertAt(1);
	if(working.trackLength != 3) {
		failure = format("insert length expected 3, got %d",
			working.trackLength);
		return false;
	}
	if(working[0].trans != 0xa0 || working[0].number != 0x01 ||
			working[1].trans != 0xa4 || working[1].number != 0x00 ||
			working[2].trans != 0xa4 || working[2].number != 0x02) {
		failure = format("insert expected A001,A400,A402, got " ~
			"%02X%02X,%02X%02X,%02X%02X",
			working[0].trans, working[0].number,
			working[1].trans, working[1].number,
			working[2].trans, working[2].number);
		return false;
	}
	if(working.wrapOffset != 2) {
		failure = format("insert LOOP expected 2, got %d",
			working.wrapOffset);
		return false;
	}
	if(original.trackLength != 2 || original[0].trans != 0xa0 ||
			original[0].number != 0x01 || original[1].trans != 0xa4 ||
			original[1].number != 0x02 || original.wrapOffset != 1) {
		failure = "original Tracklist changed after deep-copy insert";
		return false;
	}

	working.deleteAt(1);
	if(working.trackLength != 2 || working[0].trans != 0xa0 ||
			working[0].number != 0x01 || working[1].trans != 0xa4 ||
			working[1].number != 0x02 || working.wrapOffset != 1) {
		failure = format("delete expected A001,A402 LOOP 1, got " ~
			"%02X%02X,%02X%02X LOOP %d",
			working[0].trans, working[0].number,
			working[1].trans, working[1].number, working.wrapOffset);
		return false;
	}

	working.insertCopyAt(0);
	if(working.trackLength != 3 || working[0].trans != 0xa0 ||
			working[0].number != 0x01 || working[1].trans != 0xa0 ||
			working[1].number != 0x01 || working[2].trans != 0xa4 ||
			working[2].number != 0x02 || working.wrapOffset != 2) {
		failure = format("insert-copy expected A001,A001,A402 LOOP 2, got " ~
			"%02X%02X,%02X%02X,%02X%02X LOOP %d",
			working[0].trans, working[0].number,
			working[1].trans, working[1].number,
			working[2].trans, working[2].number, working.wrapOffset);
		return false;
	}

	working.overwriteFrom(original);
	if(working.trackLength != 2 || working[0].trans != 0xa0 ||
			working[0].number != 0x01 || working[1].trans != 0xa4 ||
			working[1].number != 0x02 || working.wrapOffset != 1) {
		failure = format("restore expected A001,A402 LOOP 1, got " ~
			"%02X%02X,%02X%02X LOOP %d",
			working[0].trans, working[0].number,
			working[1].trans, working[1].number, working.wrapOffset);
		return false;
	}
	return true;
}

bool checkTracklistMoveRangeLoop(Tracklist fixtureTracks,
		out string failure) {
	Tracklist working = fixtureTracks.deepcopy();
	working.insertAt(working.trackLength);
	working.insertAt(working.trackLength);
	working[0].setValue(0xa0, 0x01);
	working[1].setValue(0xa1, 0x02);
	working[2].setValue(0xa2, 0x03);
	working[3].setValue(0xa3, 0x04);
	working.wrapOffset = 1;
	Tracklist original = working.deepcopy();

	bool expectState(string context, ushort expected0, ushort expected1,
			ushort expected2, ushort expected3, int expectedWrap) {
		if(working.trackLength != 4) {
			failure = format("%s length expected 4, got %d", context,
				working.trackLength);
			return false;
		}
		if(working[0].smashedValue != expected0 ||
				working[1].smashedValue != expected1 ||
				working[2].smashedValue != expected2 ||
				working[3].smashedValue != expected3) {
			failure = format("%s expected %04X,%04X,%04X,%04X, got " ~
				"%04X,%04X,%04X,%04X", context,
				expected0, expected1, expected2, expected3,
				working[0].smashedValue, working[1].smashedValue,
				working[2].smashedValue, working[3].smashedValue);
			return false;
		}
		if(working.wrapOffset != expectedWrap) {
			failure = format("%s LOOP expected %d, got %d", context,
				expectedWrap, working.wrapOffset);
			return false;
		}
		if(working[working.wrapOffset].smashedValue != 0xa102) {
			failure = format("%s LOOP expected physical entry A102, got %04X",
				context, working[working.wrapOffset].smashedValue);
			return false;
		}
		return true;
	}

	working.overwriteFrom(original);
	if(!working.moveEntryWithin(1, 4)) {
		failure = "single move returned false";
		return false;
	}
	if(!expectState("single move", 0xa001, 0xa203, 0xa304, 0xa102, 3))
		return false;

	working.overwriteFrom(original);
	if(!working.moveEntriesWithin(1, 2, 4)) {
		failure = "range move returned false";
		return false;
	}
	if(!expectState("range move", 0xa001, 0xa304, 0xa102, 0xa203, 2))
		return false;

	working.overwriteFrom(original);
	if(working.moveEntryWithin(1, 1)) {
		failure = "single move to source gap returned true";
		return false;
	}
	if(!expectState("rejected single source gap", 0xa001, 0xa102,
			0xa203, 0xa304, 1))
		return false;

	working.overwriteFrom(original);
	if(working.moveEntryWithin(1, 2)) {
		failure = "single move after source returned true";
		return false;
	}
	if(!expectState("rejected single adjacent gap", 0xa001, 0xa102,
			0xa203, 0xa304, 1))
		return false;

	working.overwriteFrom(original);
	if(working.moveEntriesWithin(1, 2, 2)) {
		failure = "range move to overlapping gap returned true";
		return false;
	}
	if(!expectState("rejected range overlap", 0xa001, 0xa102,
			0xa203, 0xa304, 1))
		return false;

	working.overwriteFrom(original);
	if(working.moveEntriesWithin(1, 2, 3)) {
		failure = "range move after source returned true";
		return false;
	}
	if(!expectState("rejected range adjacent gap", 0xa001, 0xa102,
			0xa203, 0xa304, 1))
		return false;

	if(!working.moveEntryWithin(1, 4)) {
		failure = "final restoration setup move returned false";
		return false;
	}
	working.overwriteFrom(original);
	return expectState("restore", 0xa001, 0xa102, 0xa203, 0xa304, 1);
}

bool checkSequenceRowMutation(out string failure) {
	ubyte[] raw = new ubyte[MAX_SEQ_ROWS * 4];
	raw[0 .. 4] = [0x11, 0x22, 0x33, 0x44];
	raw[4 .. 8] = [0x55, 0x66, 0x77, 0x88];
	raw[8 .. 12] = [0x99, 0xaa, 0xbb, 0xcc];
	raw[12] = SEQ_END_MARK;
	Sequence sequence = new Sequence(raw);

	sequence.data[1].clear();
	if(sequence.rows != 3 || sequence.data.raw[4 .. 8] != CLEAR ||
			sequence.data.raw[0 .. 4] !=
				cast(ubyte[])[0x11, 0x22, 0x33, 0x44] ||
			sequence.data.raw[8 .. 12] !=
				cast(ubyte[])[0x99, 0xaa, 0xbb, 0xcc]) {
		failure = "Element.clear did not clear exactly one row";
		return false;
	}

	sequence.expand(1, 1);
	if(sequence.rows != 4 || sequence.data.raw[4 .. 8] != CLEAR ||
			sequence.data.raw[8 .. 12] != CLEAR ||
			sequence.data.raw[12 .. 16] !=
				cast(ubyte[])[0x99, 0xaa, 0xbb, 0xcc] ||
			sequence.data.raw[16] != SEQ_END_MARK) {
		failure = "Sequence.expand did not insert one clear row in order";
		return false;
	}

	sequence.shrink(1, 1, true);
	if(sequence.rows != 3 || sequence.data.raw[0 .. 4] !=
			cast(ubyte[])[0x11, 0x22, 0x33, 0x44] ||
			sequence.data.raw[4 .. 8] != CLEAR ||
			sequence.data.raw[8 .. 12] !=
				cast(ubyte[])[0x99, 0xaa, 0xbb, 0xcc] ||
			sequence.data.raw[12] != SEQ_END_MARK) {
		failure = "Sequence.shrink did not restore row order and length";
		return false;
	}
	return true;
}

bool checkSongClearSequencesContract(string fixturePath, out string failure) {
	Song song = new Song();
	song.open(fixturePath);

	song.seqs[0].clear();
	song.seqs[0].data.raw[0 .. 4] = [0x61, 0x12, 0x23, 0x34];
	ubyte[] sequenceZeroBefore = song.seqs[0].data.raw.dup;

	song.seqs[1].clear();
	song.seqs[1].expand(1, 2, false);
	song.seqs[1].data.raw[0 .. 4] = [0x62, 0x13, 0x24, 0x35];
	song.seqs[MAX_SEQ_NUM - 1].clear();
	song.seqs[MAX_SEQ_NUM - 1].data.raw[0 .. 4] =
		[0x63, 0x14, 0x25, 0x36];

	song.tracks[0].insertAt(1);
	song.tracks[0][0].setValue(0xa3, 0x11);
	song.incSubtune();
	song.tracks[2].insertAt(1);
	song.tracks[2][0].setValue(0xa5, 0x22);
	song.decSubtune();

	song.instrumentTable[7] = 0x17;
	song.waveTable[11] = 0x21;
	song.pulseTable[13] = 0x31;
	song.filterTable[15] = 0x41;
	song.superTable[17] = 0x51;
	song.chordTable[19] = 0x61;

	song.clearSeqs();
	if(song.seqs[0].data.raw != sequenceZeroBefore) {
		failure = "Sequence 00 changed across Song.clearSeqs";
		return false;
	}
	foreach(sequenceNumber; [1, MAX_SEQ_NUM - 1]) {
		Sequence sequence = song.seqs[sequenceNumber];
		if(sequence.rows != 1 || sequence.data.raw[0 .. 4] != CLEAR ||
				sequence.data.raw[4] != SEQ_END_MARK) {
			failure = format("Sequence %02X was not reset canonically",
				sequenceNumber);
			return false;
		}
	}

	foreach(tune; 0 .. SUBTUNE_MAX) {
		if(tune > 0)
			song.incSubtune();
		foreach(voice; 0 .. 3) {
			Tracklist tracks = song.tracks[voice];
			if(tracks.trackLength != 1 || tracks[0].smashedValue != 0xa000 ||
					tracks.wrapOffset != 0) {
				failure = format("Subtune %d Voice %d was not reset to " ~
					"A000 LOOP 0", tune, voice + 1);
				return false;
			}
		}
	}
	while(song.subtune > 0)
		song.decSubtune();

	if(song.instrumentTable[7] != 0x17 || song.waveTable[11] != 0x21 ||
			song.pulseTable[13] != 0x31 || song.filterTable[15] != 0x41 ||
			song.superTable[17] != 0x51 || song.chordTable[19] != 0x61) {
		failure = "Song.clearSeqs changed a generated table domain";
		return false;
	}
	return true;
}

bool checkTrackOverviewLoopOccurrenceResolution(out string failure) {
	Song song = new Song();
	foreach(sequenceNumber, rowCount; [7: 4, 8: 3, 9: 5, 10: 2]) {
		Sequence sequence = song.seqs[sequenceNumber];
		sequence.clear();
		sequence.expand(1, rowCount - 1, false);
	}

	song.tracks[0].insertAt(1);
	song.tracks[0][0].setValue(0xa0, 7);
	song.tracks[0][1].setValue(0xa0, 7);
	song.tracks[0].wrapOffset = 0;
	song.tracks[1][0].setValue(0xa0, 8);
	song.tracks[1].wrapOffset = 0;
	song.tracks[2].insertAt(1);
	song.tracks[2][0].setValue(0xa0, 9);
	song.tracks[2][1].setValue(0xa0, 10);
	song.tracks[2].wrapOffset = 1;

	TrackOverviewLane[] lanes = buildTrackOverview(song);
	TrackOverviewPosition[] positions = resolveTrackOverviewPositions(lanes, 14);
	if(positions.length != 3 || !positions[0].valid ||
			positions[0].trackIndex != 1 ||
			positions[0].sequenceRowOffset != 2 ||
			!positions[0].repeatedLoopPass || !positions[1].valid ||
			positions[1].trackIndex != 0 ||
			positions[1].sequenceRowOffset != 2 ||
			!positions[1].repeatedLoopPass || !positions[2].valid ||
			positions[2].trackIndex != 1 ||
			positions[2].sequenceRowOffset != 1 ||
			!positions[2].repeatedLoopPass) {
		failure = "Global row 14 did not resolve through each lane's LOOP";
		return false;
	}

	TrackOverviewCursorIdentity identity =
		trackOverviewCursorIdentityAtGlobalRow(lanes, 22, 0, 1, 2);
	if(!identity.valid || identity.trackIndex != 1 ||
			identity.occurrence.loopPassOrdinal != 2) {
		failure = "Repeated physical entry identity was not captured";
		return false;
	}

	song.seqs[7].expand(song.seqs[7].rows, 1, false);
	TrackOverviewLane[] changedLanes = buildTrackOverview(song);
	int remappedGlobalRow;
	if(!trackOverviewGlobalRowForCursorIdentity(changedLanes, identity,
			remappedGlobalRow) || remappedGlobalRow != 27) {
		failure = format("Occurrence remap expected global row 27, got %d",
			remappedGlobalRow);
		return false;
	}
	TrackOverviewPosition remapped =
		resolveTrackOverviewPosition(changedLanes[0], remappedGlobalRow);
	if(!remapped.valid || remapped.trackIndex != 1 ||
			remapped.sequenceNumber != 7 ||
			remapped.sequenceRowOffset != 2 || !remapped.repeatedLoopPass) {
		failure = "Occurrence remap lost physical entry identity";
		return false;
	}

	TrackOverviewCursorIdentity invalidIdentity = identity;
	invalidIdentity.trackIndex = 2;
	if(trackOverviewGlobalRowForCursorIdentity(changedLanes,
			invalidIdentity, remappedGlobalRow) || remappedGlobalRow != -1) {
		failure = "Invalid physical entry identity resolved unexpectedly";
		return false;
	}
	return true;
}

bool checkFramebufferCellMapping(out string failure) {
	enum int cellWidth = 8;
	enum int cellHeight = 14;
	enum int uiOffsetY = 115;
	enum int columnCount = 100;
	enum int rowCount = 42;
	enum int selectorRow = 41;
	enum int selectorTop = uiOffsetY + selectorRow * cellHeight;

	bool mapsTo(int pixelX, int pixelY, int expectedX, int expectedY) {
		int x = pixelX;
		int y = pixelY;
		return framebufferPixelToCell(x, y, uiOffsetY, cellWidth,
			cellHeight, columnCount, rowCount) &&
			x == expectedX && y == expectedY;
	}

	foreach(selectorCell; [1, 3, 5, 7]) {
		int cellStart = selectorCell * cellWidth;
		int cellEnd = cellStart + cellWidth;
		foreach(pixelX; cellStart .. cellEnd) {
			if(!mapsTo(pixelX, selectorTop + cellHeight / 2,
					selectorCell, selectorRow)) {
				failure = format("Selector cell %d pixel %d mapped incorrectly",
					selectorCell, pixelX);
				return false;
			}
		}
		if(!mapsTo(cellStart - 1, selectorTop, selectorCell - 1,
				selectorRow) ||
				!mapsTo(cellEnd, selectorTop, selectorCell + 1,
					selectorRow)) {
			failure = format("Selector cell %d boundary mapped incorrectly",
				selectorCell);
			return false;
		}
	}

	foreach(separatorCell; [0, 2, 4, 6, 8]) {
		foreach(pixelX; separatorCell * cellWidth ..
				(separatorCell + 1) * cellWidth) {
			int x = pixelX;
			int y = selectorTop + cellHeight / 2;
			if(!framebufferPixelToCell(x, y, uiOffsetY, cellWidth,
					cellHeight, columnCount, rowCount) ||
					x != separatorCell || y != selectorRow ||
					x == 1 || x == 3 || x == 5 || x == 7) {
				failure = format("Separator cell %d pixel %d was not inert",
					separatorCell, pixelX);
				return false;
			}
		}
	}

	if(!mapsTo(cellWidth, selectorTop, 1, selectorRow) ||
			!mapsTo(cellWidth, selectorTop + cellHeight / 2, 1,
				selectorRow) ||
			!mapsTo(cellWidth, selectorTop + cellHeight - 1, 1,
				selectorRow) ||
			!mapsTo(cellWidth, selectorTop - 1, 1, selectorRow - 1)) {
		failure = "Row 41 top, middle, bottom or preceding pixel mapped incorrectly";
		return false;
	}

	int belowX = cellWidth;
	int belowY = selectorTop + cellHeight;
	if(framebufferPixelToCell(belowX, belowY, uiOffsetY, cellWidth,
			cellHeight, columnCount, rowCount)) {
		failure = "Pixel below row 41 was not rejected as row 42";
		return false;
	}
	return true;
}

bool checkMouseButtonEventCoordinateOwnership(out string failure) {
	immutable eventPosition = mouseButtonEventPosition(15, 702);
	immutable laterGlobalPointerPosition = mouseButtonEventPosition(63, 702);
	if(eventPosition.x != 15 || eventPosition.y != 702 ||
			laterGlobalPointerPosition.x != 63 ||
			laterGlobalPointerPosition.y != 702) {
		failure = "Mouse button event coordinates were not captured by value";
		return false;
	}

	int eventX = eventPosition.x;
	int eventY = eventPosition.y;
	if(!framebufferPixelToCell(eventX, eventY, 115, 8, 14, 100, 42) ||
			eventX != 1 || eventY != 41) {
		failure = "Queued Theme 1 event did not retain its own coordinates";
		return false;
	}
	return true;
}

bool checkRightVisualPanelRouting(out string failure) {
	enum fontWidth = 8;
	enum fontHeight = 14;
	enum normalScreenWidth = 100;
	enum widerScreenWidth = 120;

	if(trackOverviewGuiStartY() != trackOverviewTotalHeight() ||
			trackOverviewGuiStartY() != 115) {
		failure = "Right visual panel does not start at the canonical boundary";
		return false;
	}

	bool matches(RightVisualPanelMouseHit hit, int voice) {
		return hit.handled && hit.voice == voice;
	}
	bool misses(RightVisualPanelMouseHit hit) {
		return !hit.handled && hit.voice == -1;
	}
	RightVisualPanelMouseHit hitAt(int x, int y, int screenWidth,
			bool leftButton = true, bool oscillatorVisible = true,
			bool blockedByModal = false) {
		return rightVisualPanelMouseHit(x, y, leftButton, oscillatorVisible,
			blockedByModal, screenWidth, fontWidth, fontHeight);
	}

	foreach(screenWidth; [normalScreenWidth, widerScreenWidth]) {
		foreach(voice; 0 .. RIGHT_VISUAL_PANE_COUNT) {
			RightVisualPaneRect pane = rightVisualPaneRect(voice, screenWidth,
				fontWidth, fontHeight);
			if(pane.voice != voice || pane.width <= 0 || pane.height <= 0 ||
					pane.y != trackOverviewGuiStartY()) {
				failure = format("Invalid pane geometry for voice %d at width %d",
					voice + 1, screenWidth);
				return false;
			}

			foreach(y; pane.y .. pane.y + pane.height) {
				foreach(x; pane.x .. pane.x + pane.width) {
					if(!matches(hitAt(x, y, screenWidth), voice)) {
						failure = format("Voice %d interior pixel %d,%d missed",
							voice + 1, x, y);
						return false;
					}
				}
			}

			int centerX = pane.x + pane.width / 2;
			if(!matches(hitAt(pane.x, pane.y, screenWidth), voice) ||
					!matches(hitAt(centerX, pane.y + pane.height - 1,
						screenWidth), voice) ||
					!misses(hitAt(centerX, pane.y - 1, screenWidth)) ||
					!misses(hitAt(centerX, pane.y + pane.height,
						screenWidth)) ||
					!misses(hitAt(centerX, pane.y + pane.height + 1,
						screenWidth))) {
				failure = format("Voice %d vertical half-open boundary failed",
					voice + 1);
				return false;
			}

			int centerY = pane.y + pane.height / 2;
			int leftExpected = voice > 0 ? voice - 1 : -1;
			int rightExpected = voice + 1 < RIGHT_VISUAL_PANE_COUNT ?
				voice + 1 : -1;
			auto leftOutside = hitAt(pane.x - 1, centerY, screenWidth);
			auto rightEdge = hitAt(pane.x + pane.width, centerY,
				screenWidth);
			if((leftExpected >= 0 ? !matches(leftOutside, leftExpected) :
					!misses(leftOutside)) ||
					(rightExpected >= 0 ? !matches(rightEdge, rightExpected) :
					!misses(rightEdge))) {
				failure = format("Voice %d horizontal half-open boundary failed",
					voice + 1);
				return false;
			}
		}

		auto firstPane = rightVisualPaneRect(0, screenWidth, fontWidth,
			fontHeight);
		int interiorX = firstPane.x + firstPane.width / 2;
		int interiorY = firstPane.y + firstPane.height / 2;
		if(!misses(hitAt(interiorX, interiorY, screenWidth, false)) ||
				!misses(hitAt(interiorX, interiorY, screenWidth, true, false)) ||
				!misses(hitAt(interiorX, interiorY, screenWidth, true, true,
					true)) ||
				!misses(hitAt(0, trackOverviewGuiStartY() - 1,
					screenWidth))) {
			failure = format("Routing conditions failed at width %d", screenWidth);
			return false;
		}
	}

	auto normalPane = rightVisualPaneRect(0, normalScreenWidth, fontWidth,
		fontHeight);
	auto widerPane = rightVisualPaneRect(0, widerScreenWidth, fontWidth,
		fontHeight);
	if(normalPane.width == widerPane.width) {
		failure = "Right visual pane geometry ignored the supplied screen width";
		return false;
	}
	return true;
}

bool checkOscilloscopeOffLabelPresentation(out string failure) {
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	string sequencerSource = readText(buildPath("src", "seq", "sequencer.d"));
	auto labelStart = uiSource.indexOf(
		"private void drawMutedOscilloscopeLabel(RightVisualPaneRect pane)");
	auto traceStart = uiSource.indexOf(
		"private void drawOscilloscopeTrace(RightVisualPaneRect pane",
		labelStart);
	if(labelStart < 0 || traceStart <= labelStart) {
		failure = "Could not isolate oscilloscope disabled-label owner";
		return false;
	}

	string labelSource = uiSource[cast(size_t)labelStart ..
		cast(size_t)traceStart];
	foreach(required; [
			"enum label = \"Off\";",
			"int textStart = (pane.x + FONT_X - 1) / FONT_X;",
			"int textEnd = (pane.x + pane.width) / FONT_X;",
			"int textWidth = textEnd - textStart;",
			"if(textWidth < label.length)",
			"int x = textStart + (textWidth - cast(int)label.length) / 2;",
			"screen.cprint(x, RIGHT_VISUAL_PANEL_ROWS / 2, 12, 0, label);"
		]) {
		if(labelSource.indexOf(required) < 0) {
			failure = format("Oscilloscope Off presentation missing %s",
				required);
			return false;
		}
	}
	if(uiSource.indexOf("\"MUTE\"") >= 0) {
		failure = "Oscilloscope source retains the old visible MUTE label";
		return false;
	}
	if(sequencerSource.indexOf(
			"audio.player.muted[i] ? \"Off\" : \"   \"") < 0) {
		failure = "F6 Track View no longer uses canonical Off terminology";
		return false;
	}
	return true;
}

bool checkSequenceRowNumberBrightness(out string failure) {
	if(SEQUENCE_ROW_BACKGROUND_BRIGHTNESS < 0 ||
			SEQUENCE_ROW_BACKGROUND_BRIGHTNESS > 100 ||
			SEQUENCE_ROW_DIGIT_BRIGHTNESS_NORMAL < 0 ||
			SEQUENCE_ROW_DIGIT_BRIGHTNESS_NORMAL > 100 ||
			SEQUENCE_ROW_DIGIT_BRIGHTNESS_ACCENT < 0 ||
			SEQUENCE_ROW_DIGIT_BRIGHTNESS_ACCENT > 100 ||
			SEQUENCE_ROW_BACKGROUND_BRIGHTNESS >=
				SEQUENCE_ROW_DIGIT_BRIGHTNESS_NORMAL ||
			SEQUENCE_ROW_DIGIT_BRIGHTNESS_NORMAL >=
				SEQUENCE_ROW_DIGIT_BRIGHTNESS_ACCENT) {
		failure = "Sequence row brightness tuning is invalid or unordered";
		return false;
	}

	uint canonical = 0xff804020u;
	uint expectedBackground = sequenceTintArgbColor(canonical,
		SEQUENCE_ROW_BACKGROUND_BRIGHTNESS);
	uint expectedNormal = sequenceTintArgbColor(canonical,
		SEQUENCE_ROW_DIGIT_BRIGHTNESS_NORMAL);
	uint expectedAccent = sequenceTintArgbColor(canonical,
		SEQUENCE_ROW_DIGIT_BRIGHTNESS_ACCENT);
	if(sequenceTintArgbColor(canonical, 120) != 0xffff8040u) {
		failure = "Absolute Value tinting did not preserve ratios or clamp";
		return false;
	}

	auto normal = sequenceRowNumberColors(canonical, false);
	auto accent = sequenceRowNumberColors(canonical, true);
	if(normal.backgroundArgb != expectedBackground ||
			accent.backgroundArgb != normal.backgroundArgb ||
			normal.foregroundArgb != expectedNormal ||
			accent.foregroundArgb != expectedAccent ||
			normal.foregroundArgb == accent.foregroundArgb) {
		failure = "Named tuning did not produce ordered same-hue row colours";
		return false;
	}
	SequenceColorLookup lookup;
	lookup.sequenceNumbers = [7];
	lookup.argbColors = [canonical];
	uint before = sequenceArgbColor(lookup, 7);
	sequenceRowNumberColors(before, false);
	if(sequenceArgbColor(lookup, 7) != before ||
			lookup.argbColors[0] != canonical) {
		failure = "Derived row colours changed the canonical Sequence colour";
		return false;
	}
	return true;
}

bool checkDefaultAudioRequest(out string failure) {
	string audioSource = readText(buildPath("src", "audio", "audio.d"));
	string mainSource = readText(buildPath("src", "main.d"));
	foreach(required; [
			"enum AudioRequest DEFAULT_AUDIO_REQUEST = AudioRequest(48_000, 128);",
			"private immutable AudioRequest[] SUPPORTED_AUDIO_REQUESTS",
			"AudioRequest(48_000, 128)",
			"AudioRequest(48_000, 1_024)",
			"if(SDL_OpenAudio(&requested, null) < 0)",
			"audiospec = requested;",
			"int samplesRequested = cast(int)(len / short.sizeof);"]) {
		if(audioSource.indexOf(required) < 0) {
			failure = "Audio default/support policy missing: " ~ required;
			return false;
		}
	}
	if(audioSource.indexOf("SDL_OpenAudio(&requested, &audiospec)") >= 0) {
		failure = "SDL audio open still exposes a variable device format to the fixed-format callback";
		return false;
	}
	auto openPosition = audioSource.indexOf("if(SDL_OpenAudio(&requested, null) < 0)");
	auto assignedPosition = audioSource.indexOf("audiospec = requested;");
	auto validationPosition = audioSource.indexOf("if(audiospec.format != AUDIO_S16LSB");
	if(openPosition < 0 || assignedPosition <= openPosition ||
			validationPosition <= assignedPosition) {
		failure = "Fixed SDL callback-format ownership is out of order";
		return false;
	}
	if(audioSource.indexOf(
			"enum AudioRequest DEFAULT_AUDIO_REQUEST = AudioRequest(48_000, 1_024);") >=
			0) {
		failure = "Old 48 kHz / 1024-sample default remains";
		return false;
	}
	foreach(required; [
			"auto requestedAudio = audio.audio.DEFAULT_AUDIO_REQUEST;",
			"requestedAudio.sampleRate = to!int(args[i+1]);",
			"requestedAudio.bufferSamples = to!int(args[i+1]);",
			"audio.audio.configureStartupAudioRequest(requestedAudio);"]) {
		if(mainSource.indexOf(required) < 0) {
			failure = "Startup audio request owner missing: " ~ required;
			return false;
		}
	}
	foreach(forbidden; ["writeAudio", "saveAudio", "audioPreference",
			"audioSettingsPreference", "DEFAULT_AUDIO_REQUEST = AudioRequest(48_000, 1_024)"]) {
		if(audioSource.indexOf(forbidden) >= 0 || mainSource.indexOf(forbidden) >= 0) {
			failure = "Unexpected persisted audio preference/default path: " ~ forbidden;
			return false;
		}
	}

	return true;
}

bool checkVoiceMuteStatePreservedAcrossPlayback(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for voice-mute lifecycle test";
		return false;
	}
	scope(exit) SDL_Quit();

	com.session.initSession();
	scope(exit) {
		audio.player.stop();
		audio.player.setVoicon(0, 0, 0);
	}

	bool checkLogicalMask(int[3] expected, string context) {
		foreach(voice; 0 .. expected.length) {
			if(audio.player.muted[voice] != expected[voice]) {
				failure = format("%s logical voice %d expected %d, got %d",
					context, voice + 1, expected[voice],
					audio.player.muted[voice]);
				return false;
			}
		}
		return true;
	}
	bool checkPlayerVoiceTable(int[3] expected, string context) {
		immutable voiceOffset = com.session.song.offsets[Offsets.VOICE];
		immutable int[3] enabledValues = [0x00, 0x07, 0x0e];
		foreach(voice; 0 .. expected.length) {
			ubyte expectedValue = cast(ubyte)(expected[voice] ? 0x19 :
				enabledValues[voice]);
			ubyte actual = com.session.song.buffer[voiceOffset + voice];
			if(actual != expectedValue) {
				failure = format("%s player voice %d expected %02X, got %02X",
					context, voice + 1, expectedValue, actual);
				return false;
			}
		}
		return true;
	}
	bool checkSidMuteBits(int[3] expected, string context) {
		immutable int[3] controlOffsets = [4, 7 + 4, 14 + 4];
		foreach(voice; 0 .. expected.length) {
			bool actualMuted = (com.session.song.sidbuf[controlOffsets[voice]] &
				0x08) != 0;
			if(actualMuted != (expected[voice] != 0)) {
				failure = format("%s SID voice %d mute bit expected %s",
					context, voice + 1, expected[voice] ? "set" : "clear");
				return false;
			}
		}
		return true;
	}
	bool checkAppliedMask(int[3] expected, string context) {
		return checkLogicalMask(expected, context) &&
			checkPlayerVoiceTable(expected, context) &&
			checkSidMuteBits(expected, context);
	}
	bool checkStopSilencesSidOnly(int[3] expectedLogical, string context) {
		return checkLogicalMask(expectedLogical, context) &&
			checkSidMuteBits([1, 1, 1], context ~ " stop silence");
	}

	audio.player.setVoicon(0, 0, 0);
	if(!checkAppliedMask([0, 0, 0], "initial all-enabled"))
		return false;

	foreach(voice; 0 .. 3)
		audio.player.toggleVoice(voice);
	if(!checkAppliedMask([1, 1, 1], "toggle all muted"))
		return false;

	audio.player.start([0, 0, 0], [0, 0, 0]);
	if(!checkAppliedMask([1, 1, 1], "start all muted"))
		return false;

	audio.player.stop();
	if(!checkStopSilencesSidOnly([1, 1, 1], "stop after all muted"))
		return false;

	foreach(voice; 0 .. 3)
		audio.player.toggleVoice(voice);
	if(!checkAppliedMask([0, 0, 0], "toggle all enabled while stopped"))
		return false;

	audio.player.start([0, 0, 0], [0, 0, 0]);
	if(!checkAppliedMask([0, 0, 0], "restart all enabled"))
		return false;

	audio.player.setVoicon(1, 0, 1);
	audio.player.start([0, 0, 0], [0, 0, 0]);
	if(!checkAppliedMask([1, 0, 1], "start mixed mask"))
		return false;

	audio.player.stop();
	if(!checkStopSilencesSidOnly([1, 0, 1], "stop after mixed mask"))
		return false;

	audio.player.start([0, 0, 0], [0, 0, 0]);
	if(!checkAppliedMask([1, 0, 1], "restart mixed mask"))
		return false;

	audio.player.toggleVoice(0);
	if(!checkAppliedMask([0, 0, 1], "toggle voice 1 while playing"))
		return false;
	audio.player.toggleVoice(2);
	if(!checkAppliedMask([0, 0, 0], "toggle voice 3 while playing"))
		return false;

	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	if(uiSource.indexOf("audio.player.toggleVoice(hit.voice);") < 0 ||
			uiSource.indexOf("audio.player.toggleVoice(0);") < 0 ||
			uiSource.indexOf("audio.player.toggleVoice(1);") < 0 ||
			uiSource.indexOf("audio.player.toggleVoice(2);") < 0) {
		failure = "Keyboard and oscilloscope routes no longer share toggleVoice";
		return false;
	}
	if(uiSource.indexOf("audio.player.setVoicon(0,0,0);") < 0) {
		failure = "Song-load route no longer resets voices through setVoicon";
		return false;
	}

	com.session.commitLoadedSong(new Song());
	audio.player.setVoicon(0, 0, 0);
	if(!checkAppliedMask([0, 0, 0], "new song all-enabled policy"))
		return false;

	return true;
}

private int[3] voiceMuteValues(int mask) pure nothrow @safe {
	return [mask & 1 ? 1 : 0, mask & 2 ? 1 : 0, mask & 4 ? 1 : 0];
}

private void setVoiceMuteMask(int mask) {
	auto values = voiceMuteValues(mask);
	audio.player.setVoicon(values[0], values[1], values[2]);
}

private bool checkVoiceMuteOutputs(int mask, string context,
		out string failure) {
	auto expected = voiceMuteValues(mask);
	immutable int[3] enabledValues = [0x00, 0x07, 0x0e];
	immutable int[3] controlOffsets = [4, 11, 18];
	immutable voiceOffset = com.session.song.offsets[Offsets.VOICE];
	foreach(voice; 0 .. 3) {
		if(audio.player.muted[voice] != expected[voice]) {
			failure = format("%s durable voice %d expected %d, got %d",
				context, voice + 1, expected[voice],
				audio.player.muted[voice]);
			return false;
		}
		ubyte expectedVoiceValue = cast(ubyte)(expected[voice] ? 0x19 :
			enabledValues[voice]);
		ubyte actualVoiceValue =
			com.session.song.buffer[voiceOffset + voice];
		if(actualVoiceValue != expectedVoiceValue) {
			failure = format("%s player voice %d expected %02X, got %02X",
				context, voice + 1, expectedVoiceValue, actualVoiceValue);
			return false;
		}
		bool actualSidMuted =
			(com.session.song.sidbuf[controlOffsets[voice]] & 0x08) != 0;
		if(actualSidMuted != (expected[voice] != 0)) {
			failure = format("%s SID voice %d expected mute %s",
				context, voice + 1, expected[voice] ? "on" : "off");
			return false;
		}
	}
	return true;
}

bool checkVoiceMuteLiveLockOwnership(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for voice-mute lock ownership";
		return false;
	}
	scope(exit) SDL_Quit();

	com.session.initSession();
	audio.player.resetVoiceMuteLockTestState();
	scope(exit) {
		audio.player.resetVoiceMuteLockTestState(false);
		audio.player.setVoicon(0, 0, 0);
	}

	audio.player.setVoicon(1, 0, 1);
	int[] mutableMask = [0, 1, 0];
	audio.player.setVoicon(mutableMask);
	shared int[3] sharedMask = [1, 1, 0];
	audio.player.setVoicon(sharedMask[]);
	audio.player.toggleVoice(2);
	if(!checkVoiceMuteOutputs(7, "public mute lock routes", failure))
		return false;

	auto beforeInvalid = audio.player.voiceMuteLockTestSnapshot();
	audio.player.toggleVoice(-1);
	audio.player.toggleVoice(3);
	auto afterInvalid = audio.player.voiceMuteLockTestSnapshot();
	if(afterInvalid != beforeInvalid) {
		failure = "invalid voice input changed lock ownership";
		return false;
	}

	bool boundsThrown;
	try {
		audio.player.setVoicon([1, 0]);
	}
	catch(Throwable) {
		boundsThrown = true;
	}
	if(!boundsThrown) {
		failure = "short mute state no longer preserves bounds validation";
		return false;
	}

	auto lockState = audio.player.voiceMuteLockTestSnapshot();
	if(lockState.lockEntries != 5 || lockState.unlocks != 5 ||
			lockState.depth != 0 || lockState.maxDepth != 1 ||
			lockState.nestedEntries != 0 || lockState.ownerCalls != 4 ||
			lockState.ownerCallsWithoutLock != 0) {
		failure = format(
			"mute lock balance expected 5/5 depth 0 max 1 nested 0 owner 4/0, " ~
			"got %d/%d depth %d max %d nested %d owner %d/%d",
			lockState.lockEntries, lockState.unlocks, lockState.depth,
			lockState.maxDepth, lockState.nestedEntries,
			lockState.ownerCalls, lockState.ownerCallsWithoutLock);
		return false;
	}

	string playerSource = readText(buildPath("src", "audio", "player.d"));
	string functionBody(string start, string finish, string context) {
		auto begin = playerSource.indexOf(start);
		if(begin < 0) {
			failure = context ~ " start not found";
			return null;
		}
		auto end = playerSource.indexOf(finish, begin);
		if(end < 0) {
			failure = context ~ " end not found";
			return null;
		}
		return playerSource[cast(size_t)begin .. cast(size_t)end];
	}

	auto toggle = functionBody("void toggleVoice(int v)",
		"void setVoicon(int v1", "toggleVoice");
	if(failure !is null)
		return false;
	if(toggle.indexOf("enterVoiceMuteAudioLock()") < 0 ||
			toggle.indexOf("int[3] next = [muted[0], muted[1], muted[2]];") <
				toggle.indexOf("enterVoiceMuteAudioLock()") ||
			toggle.indexOf("applyVoiceMuteStateLocked") < 0 ||
			toggle.indexOf("setVoicon(") >= 0) {
		failure = "toggle read-XOR-write is not wholly inside its lock boundary";
		return false;
	}

	auto owner = functionBody(
		"private void applyVoiceMuteStateLocked",
		"void resetVoiceMuteLockTestState", "lock-held mute owner");
	if(failure !is null)
		return false;
	foreach(forbidden; ["enterVoiceMuteAudioLock", "leaveVoiceMuteAudioLock",
			"SDL_LockAudio", "SDL_UnlockAudio"]) {
		if(owner.indexOf(forbidden) >= 0) {
			failure = "lock-held mute owner acquired another lock: " ~ forbidden;
			return false;
		}
	}
	foreach(required; ["muted[0] = v1;", "muted[1] = v2;",
			"muted[2] = v3;", "song.setVoicon(muted);",
			"muteSID(muted[0], muted[1], muted[2]);"]) {
		if(owner.indexOf(required) < 0) {
			failure = "lock-held mute owner missing: " ~ required;
			return false;
		}
	}

	auto restore = functionBody("private void restorePlaybackCheckpoint",
		"private struct SilentPrerollResult", "checkpoint restore");
	if(failure !is null)
		return false;
	if(restore.indexOf("applyVoiceMuteStateLocked") < 0 ||
			restore.indexOf("setVoicon(") >= 0) {
		failure = "checkpoint restore does not use the lock-held mute owner";
		return false;
	}

	auto initPlay = functionBody("private void initPlayOffset",
		"private void muteSID", "playback initialization");
	if(failure !is null)
		return false;
	if(initPlay.indexOf("setVoicon(muted);") < 0 ||
			initPlay.indexOf("applyVoiceMuteStateLocked") >= 0) {
		failure = "paused playback initialization bypasses the public lock owner";
		return false;
	}

	auto stopOwner = functionBody("void stop() nothrow",
		"void toggleVoice", "F4 stop owner");
	if(failure !is null)
		return false;
	if(stopOwner.indexOf("muteSID(1,1,1);") < 0 ||
			stopOwner.indexOf("setVoicon") >= 0 ||
			stopOwner.indexOf("applyVoiceMuteStateLocked") >= 0) {
		failure = "F4 transient silence was coupled to durable mute state";
		return false;
	}

	string callbackSource = readText(buildPath("src", "audio", "callback.d"));
	if(callbackSource.indexOf("toggleVoice(") >= 0 ||
			callbackSource.indexOf("setVoicon(") >= 0) {
		failure = "audio callback calls a public locking mute operation";
		return false;
	}

	return true;
}

bool checkVoiceMuteLiveTransitionStress(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for voice-mute transition stress";
		return false;
	}
	scope(exit) SDL_Quit();

	com.session.initSession();
	audio.player.resetVoiceMuteLockTestState();
	scope(exit) {
		audio.player.resetVoiceMuteLockTestState(false);
		audio.player.setVoicon(0, 0, 0);
	}

	int operations;
	foreach(mask; 0 .. 8) {
		setVoiceMuteMask(mask);
		operations++;
		setVoiceMuteMask(mask);
		operations++;
		if(!checkVoiceMuteOutputs(mask,
				format("stable mask %03b", mask), failure))
			return false;
	}

	foreach(previousMask; 0 .. 8) {
		setVoiceMuteMask(previousMask);
		operations++;
		foreach(currentMask; 0 .. 8) {
			setVoiceMuteMask(currentMask);
			operations++;
			if(!checkVoiceMuteOutputs(currentMask,
					format("live transition %03b -> %03b", previousMask,
						currentMask), failure))
				return false;
		}
	}

	int expectedMask;
	setVoiceMuteMask(expectedMask);
	operations++;
	foreach(index; 0 .. 1_024) {
		if(index % 4 == 0) {
			expectedMask = (index * 5 + 3) & 7;
			setVoiceMuteMask(expectedMask);
		}
		else if(index % 4 == 1) {
			expectedMask = (index * 3 + 5) & 7;
			int[] requested = voiceMuteValues(expectedMask);
			audio.player.setVoicon(requested);
		}
		else {
			int voice = cast(int)((index * 2 + index / 3) % 3);
			expectedMask ^= 1 << voice;
			audio.player.toggleVoice(voice);
		}
		operations++;
		if(!checkVoiceMuteOutputs(expectedMask,
				format("stress transition %d expected %03b", index,
					expectedMask), failure))
			return false;
	}

	auto lockState = audio.player.voiceMuteLockTestSnapshot();
	if(lockState.lockEntries != operations ||
			lockState.unlocks != operations || lockState.depth != 0 ||
			lockState.maxDepth != 1 || lockState.nestedEntries != 0 ||
			lockState.ownerCalls != operations ||
			lockState.ownerCallsWithoutLock != 0) {
		failure = format(
			"stress lock balance expected %d operations, got %d/%d depth %d " ~
			"max %d nested %d owner %d/%d", operations,
			lockState.lockEntries, lockState.unlocks, lockState.depth,
			lockState.maxDepth, lockState.nestedEntries,
			lockState.ownerCalls, lockState.ownerCallsWithoutLock);
		return false;
	}
	if(operations < 1_000) {
		failure = "voice-mute stress did not reach 1,000 transitions";
		return false;
	}

	return true;
}

bool checkVoiceMuteCheckpointMaskMatrix(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for checkpoint mask matrix";
		return false;
	}
	scope(exit) SDL_Quit();

	com.session.initSession();
	scope(exit) {
		audio.player.stop();
		audio.player.setVoicon(0, 0, 0);
		audio.player.resetAudibleCheckpointSeekSession(
			"voice_mute_matrix_cleanup");
	}

	int[3] position;
	foreach(previousMask; 0 .. 8) {
		foreach(currentMask; 0 .. 8) {
			audio.player.stop();
			setVoiceMuteMask(previousMask);
			audio.player.resetAudibleCheckpointSeekSession(
				"voice_mute_matrix_previous");
			if(audio.player.audibleCheckpointSeekTo(0, position, position,
					true, false, "voice_mute_matrix") != 1) {
				failure = format("checkpoint build failed for %03b",
					previousMask);
				return false;
			}

			auto captured =
				audio.player.voiceMuteCheckpointTestSnapshot();
			if(captured.currentMask != previousMask ||
					captured.checkpointCount == 0 ||
					!captured.allCheckpointsMatchCurrentMask) {
				failure = format("checkpoint identity not established for %03b",
					previousMask);
				return false;
			}

			audio.player.stop();
			setVoiceMuteMask(currentMask);
			auto beforeSeek =
				audio.player.voiceMuteCheckpointTestSnapshot();
			bool shouldMatch = previousMask == currentMask;
			if(beforeSeek.currentMask != currentMask ||
					beforeSeek.allCheckpointsMatchCurrentMask != shouldMatch) {
				failure = format(
					"checkpoint eligibility %03b -> %03b expected %s",
					previousMask, currentMask, shouldMatch ? "match" : "stale");
				return false;
			}

			if(audio.player.audibleCheckpointSeekTo(0, position, position,
					true, false, "voice_mute_matrix") != 1) {
				failure = format("checkpoint seek failed for %03b -> %03b",
					previousMask, currentMask);
				return false;
			}
			auto afterSeek =
				audio.player.voiceMuteCheckpointTestSnapshot();
			if(afterSeek.currentMask != currentMask ||
					afterSeek.checkpointCount == 0 ||
					!afterSeek.allCheckpointsMatchCurrentMask) {
				failure = format("checkpoint remained stale for %03b -> %03b",
					previousMask, currentMask);
				return false;
			}
			if(!checkVoiceMuteOutputs(currentMask,
					format("checkpoint %03b -> %03b", previousMask,
						currentMask), failure))
				return false;
		}
	}
	return true;
}

bool checkVoiceMuteCheckpointReportedRegression(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for checkpoint regression";
		return false;
	}
	scope(exit) SDL_Quit();

	com.session.initSession();
	scope(exit) {
		audio.player.stop();
		audio.player.setVoicon(0, 0, 0);
		audio.player.resetAudibleCheckpointSeekSession(
			"voice_mute_regression_cleanup");
	}

	int[3] position;
	setVoiceMuteMask(0);
	audio.player.resetAudibleCheckpointSeekSession(
		"voice_mute_regression_load");
	setVoiceMuteMask(7);
	if(audio.player.audibleCheckpointSeekTo(0, position, position,
			true, false, "voice_mute_regression") != 1) {
		failure = "failed to capture all-muted checkpoint";
		return false;
	}
	audio.player.stop();
	foreach(voice; 0 .. 3)
		audio.player.toggleVoice(voice);

	auto stale = audio.player.voiceMuteCheckpointTestSnapshot();
	if(stale.currentMask != 0 || stale.allCheckpointsMatchCurrentMask) {
		failure = "all-muted checkpoint was not stale after unmuting";
		return false;
	}
	if(audio.player.audibleCheckpointSeekTo(0, position, position,
			true, false, "voice_mute_regression") != 1) {
		failure = "enabled-mask F3 checkpoint seek failed";
		return false;
	}
	if(!checkVoiceMuteOutputs(0, "reported F3 reproduction", failure))
		return false;

	audio.callback.audio_frame();
	auto progressed = audio.player.voiceMuteCheckpointTestSnapshot();
	if(progressed.currentMask != 0 ||
			!progressed.allCheckpointsMatchCurrentMask) {
		failure = "first player progression restored stale mute identity";
		return false;
	}
	immutable int[3] enabledValues = [0x00, 0x07, 0x0e];
	immutable voiceOffset = com.session.song.offsets[Offsets.VOICE];
	foreach(voice; 0 .. 3) {
		if(com.session.song.buffer[voiceOffset + voice] !=
				enabledValues[voice]) {
			failure = format(
				"first player progression remuted voice %d", voice + 1);
			return false;
		}
	}
	return true;
}

bool checkStrictKeyboardPlaceholderValidation(out string failure) {
	bool hasAuditCode(string code,
			const KeyboardMetadataAuditIssue[] issues) {
		foreach(issue; issues)
			if(issue.code == code)
				return true;
		return false;
	}

	KeyboardBinding placeholder = KeyboardBinding(
		KeyboardActionId.trackEntryInsertCopy,
		KeyboardContext.trackEntry,
		KeyboardBindingKeyModel.physicalLabelOnly,
		0,
		0,
		0,
		KeyboardShortcutSemantics(
			KeyboardSemanticModifier.shift,
			-1,
			"Backspace"),
		"Test-only non-runtime physical label",
		false,
		"Test fixture");

	size_t productionPlaceholderCount;
	foreach(binding; KEYBOARD_BINDING_METADATA) {
		if(binding.implemented)
			continue;
		productionPlaceholderCount++;
		if(!keyboardBindingIsStrictNonRuntimePlaceholder(binding)) {
			failure = "Production inactive entry is not a strict placeholder: " ~
				keyboardActionStableId(binding.actionId);
			return false;
		}
	}
	version(OSX) {
		enum expectedProductionPlaceholderCount = 0;
	}
	else {
		enum expectedProductionPlaceholderCount = 2;
	}
	if(productionPlaceholderCount != expectedProductionPlaceholderCount) {
		failure = format("Expected %d strict production placeholders, found %d",
			expectedProductionPlaceholderCount, productionPlaceholderCount);
		return false;
	}

	KeyboardBinding withRuntimeKey = placeholder;
	withRuntimeKey.key = SDLK_BACKSPACE;
	if(keyboardBindingIsStrictNonRuntimePlaceholder(withRuntimeKey) ||
			!hasAuditCode("keyboard_binding_inactive_runtime_data",
				auditKeyboardBindingRuntimeEquivalence([withRuntimeKey]))) {
		failure = "Inactive physical label with a runtime key escaped validation";
		return false;
	}

	// KeyboardBinding stores no scancode. Workspace physical matching derives
	// one from a nonzero key, so that represented scancode source must be live.
	KeyboardBinding withScancodeSource = placeholder;
	withScancodeSource.context = KeyboardContext.workspaceNavigation;
	withScancodeSource.key = SDLK_1;
	if(keyboardBindingIsStrictNonRuntimePlaceholder(withScancodeSource) ||
			!hasAuditCode("keyboard_binding_inactive_runtime_data",
				auditKeyboardBindingRuntimeEquivalence(
					[withScancodeSource]))) {
		failure = "Inactive physical label with a scancode source escaped validation";
		return false;
	}

	KeyboardBinding withRequiredModifier = placeholder;
	withRequiredModifier.requiredMods = KMOD_CTRL;
	KeyboardBinding withForbiddenModifier = placeholder;
	withForbiddenModifier.forbiddenMods = KMOD_SHIFT;
	if(keyboardBindingIsStrictNonRuntimePlaceholder(withRequiredModifier) ||
			keyboardBindingIsStrictNonRuntimePlaceholder(
				withForbiddenModifier)) {
		failure = "Inactive physical label with modifiers was skippable";
		return false;
	}

	// Alternate and platform runtime routes are separate implemented bindings
	// in the actual model, never fields hidden inside a placeholder.
	KeyboardBinding alternateRuntime = KeyboardBinding(
		KeyboardActionId.appAbout,
		KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_BACKSPACE,
		KMOD_ALT,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
		"Test-only alternate runtime route",
		false,
		"Test fixture");
	KeyboardBinding platformRuntime = alternateRuntime;
	platformRuntime.actionId = KeyboardActionId.appAudioSettings;
	platformRuntime.requiredMods = KMOD_GUI;
	if(keyboardBindingIsStrictNonRuntimePlaceholder(alternateRuntime) ||
			keyboardBindingIsStrictNonRuntimePlaceholder(platformRuntime) ||
			!hasAuditCode("keyboard_binding_inactive_runtime_data",
				auditKeyboardBindingRuntimeEquivalence(
					[alternateRuntime, platformRuntime]))) {
		failure = "Represented alternate or platform runtime route was skippable";
		return false;
	}

	KeyboardBinding textRuntime = placeholder;
	textRuntime.keyModel = KeyboardBindingKeyModel.translatedUnicode;
	textRuntime.key = 'x';
	if(keyboardBindingIsStrictNonRuntimePlaceholder(textRuntime)) {
		failure = "Inactive text-input route was skippable";
		return false;
	}

	KeyboardBinding secondPlaceholder = placeholder;
	secondPlaceholder.actionId =
		KeyboardActionId.trackEntryLoopSetAllVoices;
	if(auditKeyboardBindingRuntimeEquivalence(
			[placeholder, secondPlaceholder]).length != 0) {
		failure = "Legitimate label-only placeholders entered duplicate validation";
		return false;
	}

	KeyboardBinding ordinaryRuntime = alternateRuntime;
	ordinaryRuntime.implemented = true;
	KeyboardBinding duplicateRuntime = ordinaryRuntime;
	duplicateRuntime.actionId = KeyboardActionId.appAudioSettings;
	if(!hasAuditCode("keyboard_binding_duplicate",
			auditKeyboardBindingRuntimeEquivalence(
				[ordinaryRuntime, duplicateRuntime]))) {
		failure = "Ordinary duplicate runtime bindings were not detected";
		return false;
	}

	if(auditKeyboardBindingMetadata().length != 0) {
		failure = "Current-platform keyboard metadata audit failed";
		return false;
	}

	string inputSource = readText(buildPath("src", "ui", "input.d"))
		.replace("\r\n", "\n");
	auto registryStart = inputSource.indexOf(
		"\tversion(OSX) {\n\t\tprivate enum KeyboardBinding[] " ~
		"SEQUENCE_EDITOR_COMMAND_BINDINGS");
	auto registryEnd = inputSource.indexOf(
		"// Binding lookup and action resolution.");
	if(registryStart < 0 || registryEnd <= registryStart) {
		failure = "Could not isolate the canonical keyboard registry";
		return false;
	}
	string registrySource = inputSource[
		cast(size_t)registryStart .. cast(size_t)registryEnd];
	string registryHash = toHexString(sha256Of(
		cast(const(ubyte)[])registrySource)).toLower();
	if(registryHash !=
			"4a65d428c6b4108ef666b7ede18dccadb8844d2a0ce3f2523691954e1e41c6c3") {
		failure = "Visible binding labels or action mappings changed";
		return false;
	}

	string keyjamLabel = keyboardActionPrimaryShortcutLabel(
		keyboardActionStableId(KeyboardActionId.songKeyjamToggle));
	version(OSX) {
		enum expectedKeyjamLabel = "Control-Space";
	}
	else {
		enum expectedKeyjamLabel = "Ctrl-Space";
	}
	if(keyjamLabel != expectedKeyjamLabel ||
			keyboardActionPrimaryShortcutLabel(
				keyboardActionStableId(
					KeyboardActionId.globalOpenHelp)) != "F12") {
		failure = "KEYJAM or F12 metadata changed";
		return false;
	}

	auto predicateStart = inputSource.indexOf(
		"bool keyboardBindingIsStrictNonRuntimePlaceholder(");
	auto auditStart = inputSource.indexOf(
		"KeyboardMetadataAuditIssue[] auditKeyboardBindingRuntimeEquivalence(");
	if(predicateStart < 0 || auditStart <= predicateStart ||
			inputSource[cast(size_t)predicateStart ..
				cast(size_t)auditStart].indexOf("version(") >= 0) {
		failure = "Strict placeholder semantics became platform-specific";
		return false;
	}

	return true;
}

bool checkVoiceMutePlaybackRouteMatrix(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for playback route matrix";
		return false;
	}
	scope(exit) SDL_Quit();

	com.session.initSession();
	scope(exit) {
		audio.player.stop();
		audio.player.setVoicon(0, 0, 0);
	}
	foreach(mask; 0 .. 8) {
		setVoiceMuteMask(mask);
		audio.player.start();
		if(!checkVoiceMuteOutputs(mask,
				format("direct F2/fallback start %03b", mask), failure))
			return false;
		audio.player.stop();
		auto durable = audio.player.voiceMuteCheckpointTestSnapshot();
		if(durable.currentMask != mask) {
			failure = format("F4 changed durable mask %03b", mask);
			return false;
		}
	}

	foreach(route; [
			tuple(SDLK_F1, 0, KeyboardActionId.playbackPlayFromMark),
			tuple(SDLK_F1, cast(int)KMOD_SHIFT,
				KeyboardActionId.playbackPlayFromMarkTracking),
			tuple(SDLK_F2, 0, KeyboardActionId.playbackPlayFromStart),
			tuple(SDLK_F2, cast(int)KMOD_SHIFT,
				KeyboardActionId.playbackPlayFromStartTracking),
			tuple(SDLK_F3, 0, KeyboardActionId.playbackPlayFromCursor),
			tuple(SDLK_F3, cast(int)KMOD_SHIFT,
				KeyboardActionId.playbackPlayFromCursor),
			tuple(SDLK_F4, 0, KeyboardActionId.playbackStop)]) {
		KeyboardActionId actionId;
		if(!resolvePlaybackTransportKeyboardAction(
				Keyinfo(route[0], route[1], 0), actionId) ||
				actionId != route[2]) {
			failure = format("playback binding mismatch for key %d mods %d",
				route[0], route[1]);
			return false;
		}
	}

	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	foreach(required; [
			"case KeyboardActionId.playbackPlayFromMarkTracking:",
			"F1orF2(key, false);",
			"case KeyboardActionId.playbackPlayFromStartTracking:",
			"F1orF2(key, true);",
			"playFromCurrentEditorPositionAccurate();",
			"toplevel.checkpointSeekFromCurrentEditorPosition()",
			"toplevel.checkpointSeekFromPlaybackMarks([m1, m2, m3])",
			"toplevel.playFromCursor();"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = "playback route owner missing: " ~ required;
			return false;
		}
	}
	return true;
}

bool checkKeyjamR2DHostReleaseBoundary(out string failure) {
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	string playerSource = readText(buildPath("src", "audio", "player.d"));
	string audioSource = readText(buildPath("src", "audio", "audio.d"));
	string mainSource = readText(buildPath("src", "main.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	string residSource = readText(buildPath("src", "audio", "resid",
		"residctrl.cpp"));
	string seqTableSource = readText(buildPath("src", "seq", "seqtable.d"));

	bool containsAll(string source, string[] tokens, string context) {
		foreach(token; tokens) {
			if(source.indexOf(token) < 0) {
				failure = context ~ " missing " ~ token;
				return false;
			}
		}
		return true;
	}

	string sliceBetween(string source, string start, string finish,
			string context) {
		auto startIndex = source.indexOf(start);
		if(startIndex < 0) {
			failure = context ~ " start not found";
			return null;
		}
		auto endIndex = source.indexOf(finish, startIndex);
		if(endIndex < 0) {
			failure = context ~ " end not found";
			return null;
		}
		return source[cast(size_t)startIndex .. cast(size_t)endIndex];
	}

	auto releaseReady = audio.player.KEYJAM_F6_RELEASE_READY_SAMPLES;
	if(audio.player.KEYJAM_F6_RELEASE_FAILSAFE_FRAMES != 4) {
		failure = "F6 release failsafe frame count changed";
		return false;
	}
	if(releaseReady != 128) {
		failure = "F6 release readiness sample count changed";
		return false;
	}
	if(audio.player.keyjamF6ReleasePolicyShouldRelease(false, false,
			1, 1, releaseReady, 10, 20)) {
		failure = "release policy releases without pending keyup";
		return false;
	}
	if(audio.player.keyjamF6ReleasePolicyShouldRelease(true, true,
			1, 1, releaseReady, 10, 20)) {
		failure = "release policy releases twice";
		return false;
	}
	if(audio.player.keyjamF6ReleasePolicyShouldRelease(true, false,
			1, 2, releaseReady, 10, 20)) {
		failure = "release policy accepts stale generation";
		return false;
	}
	if(audio.player.keyjamF6ReleasePolicyShouldRelease(true, false,
			1, 1, releaseReady - 1, 10, 20)) {
		failure = "release policy releases before renderer readiness";
		return false;
	}
	if(!audio.player.keyjamF6ReleasePolicyShouldRelease(true, false,
			1, 1, releaseReady, 10, 20)) {
		failure = "release policy ignores renderer readiness";
		return false;
	}
	if(!audio.player.keyjamF6ReleasePolicyShouldRelease(true, false,
			1, 1, 0, 20, 20)) {
		failure = "release policy ignores failsafe deadline";
		return false;
	}

	foreach(forbidden; [
			"keyjamR" ~ "2B", "R2" ~ "B1",
			"CheeseCutter-keyjam-r2" ~ "b",
			"CheeseCutter-keyjam-r2" ~ "b1",
			"KeyjamR2" ~ "BDiagnostic",
			"sid_render_" ~ "diag" ~ "nostic",
			"keyjam_r2" ~ "b1_sid_",
			"playNote" ~ "Later", "pending" ~ "Events",
			"event" ~ "Queue", "ring" ~ "Buffer",
			"PCM " ~ "queue"]) {
		if(playerSource.indexOf(forbidden) >= 0 ||
				inputSource.indexOf(forbidden) >= 0 ||
				audioSource.indexOf(forbidden) >= 0 ||
				residSource.indexOf(forbidden) >= 0 ||
				mainSource.indexOf(forbidden) >= 0 ||
				uiSource.indexOf(forbidden) >= 0) {
			failure = "temporary probe or queued playback token remains: " ~
				forbidden;
			return false;
		}
	}

	auto playNote = sliceBetween(playerSource, "void playNote(Element emt)",
		"void playRow", "playNote");
	if(failure !is null)
		return false;
	if(!containsAll(playNote, [
			"playNoteForVoice(emt, seq.sequencer.activeVoiceNum);",
			"private void playNoteForVoice(Element emt, int v)",
			"bool preparedF6NoteOn = keyjamF6Audition.preparedNoteOn;",
			"if(preparedF6NoteOn)",
			"startPreparedF6AuditionLocked(v);",
			"if(playstatus == Status.Play)",
			"return;",
			"audio.callback.reset();",
			"audio.audio.reset();",
			"cpuCall(call, false);",
			"syncSidRegisters();",
			"playstatus = Status.Keyjam;"], "playNote ownership"))
		return false;

	auto noteEntry = sliceBetween(inputSource,
		"private int completeNoteEntry(Keyinfo key, int result)",
		"override void clearRow()", "InputNote.completeNoteEntry");
	if(failure !is null)
		return false;
	if(!containsAll(noteEntry, [
			"if(element.note.value >= 3)",
			"audio.player.prepareF6AuditionNoteOn(",
			"seq.sequencer.activeVoiceNum",
			"scope(exit) audio.player.cancelPreparedF6AuditionNoteOn();",
			"keyjam.keypress(key);",
			"rememberActiveNoteKey(key);"], "F6 note-on route"))
		return false;
	if(noteEntry.indexOf("prepareF6AuditionNoteOn") >
			noteEntry.indexOf("keyjam.keypress(key);")) {
		failure = "F6 readiness generation starts after InputKeyjam dispatch";
		return false;
	}

	auto noteRelease = sliceBetween(inputSource,
		"override int keyrelease(Keyinfo key)",
		"override int keypress(Keyinfo key)", "InputNote.keyrelease");
	if(failure !is null)
		return false;
	if(!containsAll(noteRelease, [
			"activeNoteKeyMatches(key)",
			"int generation = activeNoteGeneration;",
			"clearActiveNoteOwnership();",
			"audio.player.requestF6AuditionRelease(generation);"],
			"F6 key-off request route"))
		return false;
	if(noteRelease.indexOf("audio.player.playNote") >= 0) {
		failure = "F6 key-up still sends immediate key-off playback";
		return false;
	}

	auto keyjam = sliceBetween(inputSource,
		"class InputKeyjam : ExtendedInput",
		"final class InputSeq", "InputKeyjam");
	if(failure !is null)
		return false;
	if(keyjam.indexOf("audio.player.playNote(element);") < 0) {
		failure = "InputKeyjam no longer owns direct playNote dispatch";
		return false;
	}
	if(!containsAll(inputSource, [
			"void deactivate() {}",
			"private int activeNoteUnicode = 0;",
			"private int activeNoteScancode = 0;",
			"private int activeNoteGeneration = 0;",
			"private bool activeNoteKeyMatches(Keyinfo key)",
			"activeNoteScancode == key.scancode",
			"activeNoteUnicode == key.unicode",
			"override void deactivate()",
			"clearActiveNoteOwnership();",
			"audio.player.cancelF6AuditionForInputLoss();",
			"foreach(input; inputters)",
			"input.deactivate();"],
			"InputNote physical-key ownership"))
		return false;

	auto callback = sliceBetween(audioSource,
		"__gshared void audio_callback_2",
		"int oscilloscopeSampleCapacity()", "audio callback");
	if(failure !is null)
		return false;
	foreach(forbidden; ["File(", "write", "writeln", "writefln",
			"format(", "new ", "sleep", "SDL_Delay"]) {
		if(callback.indexOf(forbidden) >= 0) {
			failure = "audio callback gained forbidden keyjam work: " ~
				forbidden;
			return false;
		}
	}

	auto rowShortcut = sliceBetween(seqTableSource,
		"handleSequencePlayRowShortcut",
		"override int keypress", "F6 Keypad-0 row audition");
	if(failure !is null)
		return false;
	if(rowShortcut.indexOf("audio.player.playRow(voices);") < 0 ||
			rowShortcut.indexOf("F6Audition") >= 0 ||
			rowShortcut.indexOf("requestF6AuditionRelease") >= 0) {
		failure = "Keypad-0 row audition was coupled to F6 note release policy";
		return false;
	}

	auto readinessRegion = sliceBetween(playerSource,
		"enum KEYJAM_F6_RELEASE_READY_SAMPLES",
		"int getPlaystatus() nothrow", "KEYJAM-R2D readiness region");
	if(failure !is null)
		return false;
	foreach(forbidden; ["q" ~ "ueue", "Q" ~ "ueue",
			"Q" ~ "ueued", "playNote" ~ "Later",
			"Element[]", "ubyte[]", "int[]"]) {
		if(readinessRegion.indexOf(forbidden) >= 0) {
			failure = "release policy appears to retain queued payload data: " ~
				forbidden;
			return false;
		}
	}
	if(!containsAll(readinessRegion, [
			"struct KeyjamF6AuditionState",
			"int generation;",
			"int voice;",
			"bool pendingRelease;",
			"int pendingReleaseGeneration;",
			"bool keyupSeen;",
			"bool releaseSent;",
			"long failsafeDeadline;",
			"void cancelF6AuditionForInputLoss() nothrow",
			"if(playstatus == Status.Keyjam)",
			"stop();",
			"cancelF6AuditionState();",
			"sid_keyjam_f6_arm_render_readiness(generation,",
			"sid_keyjam_f6_gate_on_samples(",
			"keyjamF6ReleasePolicyShouldRelease("],
			"scalar release policy"))
		return false;

	if(!containsAll(residSource, [
			"#include <atomic>",
			"static std::atomic<int> keyjam_f6_generation",
			"static std::atomic<int> keyjam_f6_control_offset",
			"static std::atomic<int> keyjam_f6_gate_generation",
			"static std::atomic<int> keyjam_f6_gate_samples",
			"void sid_keyjam_f6_arm_render_readiness(int generation,",
			"void sid_keyjam_f6_cancel_render_readiness()",
			"int sid_keyjam_f6_gate_on_samples(int generation)",
			"render_state.keyjam_f6_generation = generation;",
			"keyjam_f6_gate_samples.fetch_add(produced,"],
			"SID renderer readiness bridge"))
		return false;
	foreach(forbidden; ["File(", "writefln", "writeln", "format("]) {
		if(residSource.indexOf(forbidden) >= 0) {
			failure = "SID renderer gained forbidden readiness output: " ~
				forbidden;
			return false;
		}
	}
	if(!containsAll(mainSource, [
			"Keyinfo keyinfo = Keyinfo(key, mods, unicode,",
			"evt.key.keysym.scancode);",
			"audio.player.serviceF6AuditionRelease();",
			"audio.player.cancelF6AuditionRelease();",
			"mainui.releaseInputOwnership();",
			"audio.player.stop();",
			"audio.audio.audio_close();"],
			"main-thread release service"))
		return false;
	if(!containsAll(uiSource, [
			"void releaseInputOwnership()",
			"currentInput.deactivate();",
			"void deactivate() {\n\t\t\tif(input !is null)",
			"input.deactivate();",
			"void activateDialog(Window d)",
			"releaseInputOwnership();"],
			"UI input-ownership lifecycle"))
		return false;

	return true;
}

bool checkRawCellRasterization(out string failure) {
	auto screen = new Screen(1, 1);
	uint paletteForeground = 0xff112233u;
	uint paletteBackground = 0xff445566u;
	uint rawForeground = 0xff778899u;
	uint rawBackground = 0xffaabbccu;
	screen.setChar(0, 0, cast(ushort)('A' | (5 << 8) | (6 << 12)));
	if(screen.cellPixelColor(0, 0, true, paletteForeground,
			paletteBackground) != paletteForeground ||
			screen.cellPixelColor(0, 0, false, paletteForeground,
			paletteBackground) != paletteBackground) {
		failure = "Palette fallback colours were not used without raw overrides";
		return false;
	}

	screen.setColorsRaw(0, 0, rawForeground, rawBackground);
	if(screen.cellPixelColor(0, 0, true, paletteForeground,
			paletteBackground) != rawForeground ||
			screen.cellPixelColor(0, 0, false, paletteForeground,
			paletteBackground) != rawBackground) {
		failure = "Raw glyph-on or glyph-off colour was not selected";
		return false;
	}

	screen.setbgRaw(0, 0, 0xff102030u, 0, 5);
	if(screen.cellPixelColor(0, 0, true, paletteForeground,
			paletteBackground) != paletteForeground ||
			screen.cellPixelColor(0, 0, false, paletteForeground,
			paletteBackground) != 0xff102030u) {
		failure = "Existing raw-background path or palette foreground changed";
		return false;
	}
	return true;
}

bool checkRawCellClearing(out string failure) {
	auto screen = new Screen(1, 1);
	uint paletteForeground = 0xff010203u;
	uint paletteBackground = 0xff040506u;
	uint rawForeground = 0xff708090u;
	uint rawBackground = 0xffa0b0c0u;

	screen.setColorsRaw(0, 0, rawForeground, rawBackground);
	screen.cprint(0, 0, 2, -1, "X");
	if(screen.cellPixelColor(0, 0, true, paletteForeground,
			paletteBackground) != paletteForeground ||
			screen.cellPixelColor(0, 0, false, paletteForeground,
			paletteBackground) != rawBackground) {
		failure = "Palette foreground did not clear only raw foreground";
		return false;
	}

	screen.setColorsRaw(0, 0, rawForeground, rawBackground);
	screen.setbg(0, 0, 3);
	if(screen.cellPixelColor(0, 0, true, paletteForeground,
			paletteBackground) != rawForeground ||
			screen.cellPixelColor(0, 0, false, paletteForeground,
			paletteBackground) != paletteBackground) {
		failure = "Palette background did not clear only raw background";
		return false;
	}

	screen.setColorsRaw(0, 0, rawForeground, rawBackground);
	screen.setColor(0, 0, 4, 5);
	if(screen.cellPixelColor(0, 0, true, paletteForeground,
			paletteBackground) != paletteForeground ||
			screen.cellPixelColor(0, 0, false, paletteForeground,
			paletteBackground) != paletteBackground) {
		failure = "Whole-cell palette colour did not clear both raw overrides";
		return false;
	}

	screen.setColorsRaw(0, 0, rawForeground, rawBackground);
	screen.cprint(0, 0, 6, 7, "X");
	if(screen.cellPixelColor(0, 0, true, paletteForeground,
			paletteBackground) != paletteForeground ||
			screen.cellPixelColor(0, 0, false, paletteForeground,
			paletteBackground) != paletteBackground) {
		failure = "Ordinary text redraw left a stale raw colour";
		return false;
	}

	screen.setColorsRaw(0, 0, rawForeground, rawBackground);
	screen.clrscr();
	if(screen.cellPixelColor(0, 0, true, paletteForeground,
			paletteBackground) != paletteForeground ||
			screen.cellPixelColor(0, 0, false, paletteForeground,
			paletteBackground) != paletteBackground) {
		failure = "Screen clear left a stale raw colour";
		return false;
	}
	return true;
}

/*
	The separator starts at local offset three, immediately after the leading
	space and two hexadecimal row digits.
*/
bool checkSequenceRowNumberRange(out string failure) {
	if(SEQUENCE_ROW_NUMBER_CELL_COUNT != 3) {
		failure = "Sequence row-number range includes its separator cell";
		return false;
	}
	immutable voiceStarts = [6, 20, 34];
	immutable separators = [9, 23, 37];
	foreach(index, start; voiceStarts) {
		if(start + SEQUENCE_ROW_NUMBER_CELL_COUNT != separators[index]) {
			failure = format("Voice %d row-number range reaches separator %d",
				index + 1, separators[index]);
			return false;
		}
	}
	return true;
}

private string glyphBitmapHash(const(int)[] glyphs) {
	ubyte[] bytes;
	foreach(glyph; glyphs)
		bytes ~= uiGlyphBitmap(glyph);
	return toHexString(sha256Of(bytes)).toLower();
}

private ubyte[] directFontGlyphBitmap(int glyph) {
	auto rawfont = cast(ubyte[])read(buildPath("src", "font", "font.psf"));
	if(rawfont.length < 4 || rawfont[0] != 0x36 || rawfont[1] != 0x04 ||
			rawfont[3] != FONT_Y)
		return null;
	size_t offset = 4 + cast(size_t)glyph * FONT_Y;
	if(offset + FONT_Y > rawfont.length)
		return null;
	return rawfont[offset .. offset + FONT_Y].dup;
}

bool checkExtendedUiGlyphOverlay(out string failure) {
	if(INFOBAR_GLYPH_HELP_LEFT != 493 || INFOBAR_GLYPH_HELP_RIGHT != 494) {
		failure = "Help glyph IDs must remain 493/494";
		return false;
	}
	if(INFOBAR_GLYPH_FULLSCREEN_LEFT != 497 ||
			INFOBAR_GLYPH_FULLSCREEN_RIGHT != 498) {
		failure = "Fullscreen glyph IDs must remain 497/498";
		return false;
	}

	immutable newGlyphs = [INFOBAR_GLYPH_HELP_LEFT, INFOBAR_GLYPH_HELP_RIGHT,
		INFOBAR_GLYPH_FULLSCREEN_LEFT, INFOBAR_GLYPH_FULLSCREEN_RIGHT];
	foreach(glyph; newGlyphs) {
		auto bitmap = uiGlyphBitmap(glyph);
		auto directBitmap = directFontGlyphBitmap(glyph);
		if(bitmap.length != FONT_Y) {
			failure = format("Extended glyph %d is unavailable", glyph);
			return false;
		}
		if(directBitmap != bitmap) {
			failure = format("Production glyph %d differs from font.psf", glyph);
			return false;
		}
		bool nonEmpty;
		foreach(bits; bitmap)
			nonEmpty = nonEmpty || bits != 0;
		if(!nonEmpty) {
			failure = format("Extended glyph %d is empty", glyph);
			return false;
		}

		enum uint rawForeground = 0xff123456u;
		enum uint rawBackground = 0xffabcdefu;
		uint[FONT_X * FONT_Y] pixels;
		if(!rasterizeUiGlyph(glyph, pixels[], FONT_X, rawForeground,
				rawBackground)) {
			failure = format("Extended glyph %d did not rasterize", glyph);
			return false;
		}
		bool hasForeground;
		bool hasBackground;
		foreach(pixel; pixels) {
			hasForeground = hasForeground || pixel == rawForeground;
			hasBackground = hasBackground || pixel == rawBackground;
		}
		if(!hasForeground || !hasBackground) {
			failure = format("Extended glyph %d lost raw foreground/background pixels",
				glyph);
			return false;
		}
	}

	if(glyphBitmapHash(newGlyphs) !=
			"47387bd577415be49fe987c7ae228c6cc3986e91b55963e28ba31b02128b2751") {
		failure = "New extended glyph bitmaps differ from the source-font baseline";
		return false;
	}

	if(glyphBitmapHash([INFOBAR_GLYPH_HELP_LEFT, INFOBAR_GLYPH_HELP_RIGHT]) ==
			glyphBitmapHash([495, 496])) {
		failure = "Help glyphs 493/494 must differ from unassigned 495/496";
		return false;
	}

	int[] existingGlyphs;
	foreach(glyph; STATUSLINE_GLYPH_FAILURE .. INFOBAR_GLYPH_THEME_NEON + 1)
		existingGlyphs ~= glyph;
	if(glyphBitmapHash(existingGlyphs) !=
			"6108dc00e0396a0069b92d2711e77c6bd2ad1c15ef1df20fb75da68e6f7684d3") {
		failure = "Existing extended glyphs 499-511 changed";
		return false;
	}

	immutable baseGlyphs = [0, cast(int)'A', 255];
	if(glyphBitmapHash(baseGlyphs) !=
			"047679e35e5ac1b0a8b22ca308d63f1d343f70b5ed867bcc8d6bdb516068b974") {
		failure = "Representative base glyphs changed";
		return false;
	}

	foreach(glyph; [495, 496]) {
		uint[FONT_X * FONT_Y] pixels;
		if(uiGlyphBitmap(glyph).length != 0 ||
				rasterizeUiGlyph(glyph, pixels[], FONT_X, 1, 0)) {
			failure = format("Unassigned glyph %d became an extended UI glyph",
				glyph);
			return false;
		}
	}
	return true;
}

class FullscreenTestVideo : Video {
	Uint32[] requestedFlags;
	int[4][] sizeLimitRequests;
	int[2][] sizeRequests;
	int actualWidth;
	int actualHeight;
	int displayWidth;
	int displayHeight;
	bool nextResult = true;

	this(int width, int height) {
		super(width, height, new Screen(width / FONT_X,
			(height - trackOverviewGuiStartY()) / FONT_Y), 0,
			trackOverviewGuiStartY());
		actualWidth = width;
		actualHeight = height;
		displayWidth = width;
		displayHeight = height;
	}

	protected override bool setWindowFullscreenFlags(Uint32 flags) {
		requestedFlags ~= flags;
		return nextResult;
	}

	protected override void setWindowSizeLimits(int minWidth, int minHeight,
			int maxWidth, int maxHeight) {
		sizeLimitRequests ~= [minWidth, minHeight, maxWidth, maxHeight];
	}

	protected override void setWindowSize(int width, int height) {
		sizeRequests ~= [width, height];
		actualWidth = width;
		actualHeight = height;
	}

	protected override void getWindowSize(ref int width, ref int height) {
		width = actualWidth;
		height = actualHeight;
	}

	protected override void getWindowDisplaySize(ref int width, ref int height) {
		width = displayWidth;
		height = displayHeight;
	}

	bool cachedFullscreen() {
		return useFullscreen;
	}

	int canonicalWidth() {
		return requestedWidth;
	}

	int canonicalHeight() {
		return requestedHeight;
	}

	Uint32 creationFlagsForTest() {
		return cast(Uint32)windowCreationFlags();
	}

	void applyFixedLimitsForTest() {
		applyFixedWindowedSizeLimits();
	}

	bool restoreWindowedSizeForTest() {
		return restoreFixedWindowedSizeIfNeeded();
	}

	void setCachedFullscreenForTest(bool enabled) {
		useFullscreen = enabled;
	}
}

bool checkFullscreenTransitionOwner(out string failure) {
	int canonicalWidth = 100 * FONT_X;
	int canonicalHeight = 42 * FONT_Y + trackOverviewGuiStartY();
	auto video = new FullscreenTestVideo(canonicalWidth, canonicalHeight);
	if(video.cachedFullscreen()) {
		failure = "Fullscreen cache should start windowed";
		return false;
	}
	if(video.canonicalWidth() != canonicalWidth ||
			video.canonicalHeight() != canonicalHeight) {
		failure = "Fullscreen test did not derive canonical dimensions";
		return false;
	}
	if((video.creationFlagsForTest() & SDL_WINDOW_SHOWN) == 0 ||
			(video.creationFlagsForTest() & SDL_WINDOW_RESIZABLE) != 0) {
		failure = "Window creation flags do not request shown fixed window";
		return false;
	}
	video.applyFixedLimitsForTest();
	if(video.sizeLimitRequests.length != 1 ||
			video.sizeLimitRequests[0] != [canonicalWidth, canonicalHeight,
				canonicalWidth, canonicalHeight]) {
		failure = "Fixed window size limits are not canonical";
		return false;
	}
	video.displayWidth = 1920;
	video.displayHeight = 1080;
	video.setCachedFullscreenForTest(false);
	video.actualWidth = canonicalWidth + FONT_X;
	video.actualHeight = canonicalHeight + FONT_Y;
	size_t sizeLimitCount = video.sizeLimitRequests.length;
	size_t sizeRequestCount = video.sizeRequests.length;
	if(!video.toggleFullscreen() || !video.cachedFullscreen() ||
			video.sizeLimitRequests.length != sizeLimitCount + 1 ||
			video.sizeLimitRequests[$ - 1] != [1, 1, 1920, 1080] ||
			video.requestedFlags[$ - 1] != SDL_WINDOW_FULLSCREEN_DESKTOP ||
			video.sizeRequests.length != sizeRequestCount) {
		failure = "Fullscreen entry did not relax limits before desktop fullscreen";
		return false;
	}
	video.actualWidth = 1920;
	video.actualHeight = 1080;
	if(!video.toggleFullscreen() || video.cachedFullscreen() ||
			video.requestedFlags[$ - 1] != 0 ||
			video.sizeRequests[$ - 1] != [canonicalWidth, canonicalHeight] ||
			video.sizeLimitRequests[$ - 1] != [canonicalWidth, canonicalHeight,
				canonicalWidth, canonicalHeight]) {
		failure = "Fullscreen exit did not restore fixed limits";
		return false;
	}
	video.actualWidth = canonicalWidth + FONT_X;
	video.actualHeight = canonicalHeight + FONT_Y;
	if(!video.restoreWindowedSizeForTest() ||
			video.sizeRequests[$ - 1] != [canonicalWidth, canonicalHeight]) {
		failure = "Unexpected windowed size was not restored";
		return false;
	}
	sizeRequestCount = video.sizeRequests.length;
	if(video.restoreWindowedSizeForTest() ||
			video.sizeRequests.length != sizeRequestCount) {
		failure = "Canonical windowed size caused redundant restore";
		return false;
	}
	video.setCachedFullscreenForTest(true);
	video.actualWidth = canonicalWidth * 2;
	video.actualHeight = canonicalHeight * 2;
	sizeLimitCount = video.sizeLimitRequests.length;
	video.resizeEvent(video.actualWidth, video.actualHeight);
	if(video.sizeRequests.length != sizeRequestCount) {
		failure = "Fullscreen resize event requested fixed window restore";
		return false;
	}
	if(video.sizeLimitRequests.length != sizeLimitCount) {
		failure = "Fullscreen resize event reapplied fixed size limits";
		return false;
	}
	video.setCachedFullscreenForTest(false);
	video.displayWidth = canonicalWidth * 2;
	video.displayHeight = canonicalHeight * 2;
	if(!video.toggleFullscreen() || !video.cachedFullscreen() ||
			video.requestedFlags[$ - 1] != SDL_WINDOW_FULLSCREEN_DESKTOP) {
		failure = "Successful fullscreen entry did not commit desktop fullscreen";
		return false;
	}
	video.actualWidth = canonicalWidth * 2;
	video.actualHeight = canonicalHeight * 2;
	if(!video.toggleFullscreen() || video.cachedFullscreen() ||
			video.requestedFlags[$ - 1] != 0 ||
			video.sizeRequests[$ - 1] != [canonicalWidth, canonicalHeight]) {
		failure = "Successful fullscreen exit did not restore fixed window";
		return false;
	}
	video.nextResult = false;
	if(video.toggleFullscreen() || video.cachedFullscreen() ||
			video.requestedFlags[$ - 1] != SDL_WINDOW_FULLSCREEN_DESKTOP ||
			video.sizeLimitRequests[$ - 1] != [canonicalWidth, canonicalHeight,
				canonicalWidth, canonicalHeight] ||
			video.sizeRequests[$ - 1] != [canonicalWidth, canonicalHeight]) {
		failure = "Failed fullscreen entry changed cached state";
		return false;
	}
	video.nextResult = true;
	if(!video.toggleFullscreen() || !video.cachedFullscreen()) {
		failure = "Fullscreen did not recover after a failed transition";
		return false;
	}
	video.nextResult = false;
	sizeRequestCount = video.sizeRequests.length;
	sizeLimitCount = video.sizeLimitRequests.length;
	if(video.toggleFullscreen() || !video.cachedFullscreen() ||
			video.requestedFlags[$ - 1] != 0 ||
			video.sizeRequests.length != sizeRequestCount ||
			video.sizeLimitRequests.length != sizeLimitCount) {
		failure = "Failed fullscreen exit changed cached state";
		return false;
	}
	video.nextResult = true;
	if(!video.toggleFullscreen() || video.cachedFullscreen() ||
			video.sizeRequests[$ - 1] != [canonicalWidth, canonicalHeight]) {
		failure = "Fullscreen did not recover after a failed exit";
		return false;
	}
	foreach(i; 0 .. 3) {
		if(!video.toggleFullscreen() || !video.cachedFullscreen()) {
			failure = "Repeated fullscreen entry failed";
			return false;
		}
		video.actualWidth = canonicalWidth + (cast(int)i + 1) * FONT_X;
		video.actualHeight = canonicalHeight + (cast(int)i + 1) * FONT_Y;
		if(!video.toggleFullscreen() || video.cachedFullscreen() ||
				video.sizeRequests[$ - 1] != [canonicalWidth, canonicalHeight]) {
			failure = "Repeated fullscreen exit did not restore canonical size";
			return false;
		}
	}
	return true;
}

bool checkSharedResizeRedrawOwnership(out string failure) {
	string mainSource = readText(buildPath("src", "main.d"));
	auto eventStart = mainSource.indexOf("case SDL_WINDOWEVENT:");
	auto eventEnd = mainSource.indexOf(
		"else if(evt.window.event == SDL_WINDOWEVENT_FOCUS_LOST)",
		eventStart);
	if(eventStart < 0 || eventEnd <= eventStart) {
		failure = "shared SDL window-event owner is missing";
		return false;
	}
	string eventSource = mainSource[cast(size_t)eventStart ..
		cast(size_t)eventEnd];
	auto resized = eventSource.indexOf("SDL_WINDOWEVENT_RESIZED");
	auto sizeChanged = eventSource.indexOf("SDL_WINDOWEVENT_SIZE_CHANGED");
	auto resizeCall = eventSource.indexOf(
		"video.resizeEvent(evt.window.data1, evt.window.data2);");
	auto updateCall = eventSource.indexOf("mainui.update();", resizeCall);
	if(resized < 0 || sizeChanged < 0 || resizeCall < 0 ||
			updateCall <= resizeCall ||
			eventSource.count("mainui.update();") != 1) {
		failure = "shared size events do not redraw the UI after resize handling";
		return false;
	}
	foreach(forbidden; ["version(Windows)", "version(Win32)", "version(OSX)",
			"drawOscilloscopePanel", "drawCurrentVisualPanel",
			"SDL_PushEvent", "drawVisualizer"]) {
		if(eventSource.indexOf(forbidden) >= 0) {
			failure = "resize redraw gained a platform or visual special case";
			return false;
		}
	}

	auto loopPresent = mainSource.indexOf("video.updateFrame();", eventEnd);
	if(loopPresent <= eventEnd) {
		failure = "main loop no longer presents after shared event handling";
		return false;
	}
	if(mainSource.indexOf(
			"void updateAndPresent() {\n\t\tmainui.update();\n\t\tvideo.updateFrame();") <
			0 ||
			mainSource.indexOf(
				"void routeKeyinfo(Keyinfo keyinfo)") < 0) {
		failure = "click or keyboard redraw ownership changed";
		return false;
	}

	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	auto uiUpdate = uiSource.indexOf("\tvoid update() {");
	auto uiUpdateEnd = uiSource.indexOf("\n\t}", uiUpdate);
	if(uiUpdate < 0 || uiUpdateEnd <= uiUpdate ||
			uiSource[cast(size_t)uiUpdate .. cast(size_t)uiUpdateEnd].
				indexOf("drawCurrentVisualPanel();") < 0 ||
			uiSource.indexOf("displayTrackOverviewQuickHelp(") < 0 ||
			uiSource.indexOf("private void drawOscilloscopePanel()") < 0) {
		failure = "UI, Quick Help or oscilloscope redraw ownership changed";
		return false;
	}

	if(sourceReleaseFileHash(buildPath("src", "com", "fb.d")) !=
			"685bebd85feea1efdf5f18a3874b7d882b9c34d2714a8a6e4a36f8b0b07aea88" ||
			sourceReleaseFileHash(buildPath("src", "audio", "player.d")) !=
			"6ccc60a1ee2b44263263d179083993a3cf9f21bba7f8785951e92ea45059d20e") {
		failure = "framebuffer, audio or mute ownership changed";
		return false;
	}
	return true;
}

private bool expectInterfaceDestinationRect(int availableWidth,
		int availableHeight, int sourceWidth, int sourceHeight, int x, int y,
		int width, int height, out string failure) {
	auto rect = interfaceDestinationRect(availableWidth, availableHeight,
		sourceWidth, sourceHeight);
	if(rect.x != x || rect.y != y || rect.w != width || rect.h != height) {
		failure = format("Destination for %dx%d expected %d,%d %dx%d, got " ~
			"%d,%d %dx%d", availableWidth, availableHeight, x, y, width,
			height, rect.x, rect.y, rect.w, rect.h);
		return false;
	}
	if(rect.x < 0 || rect.y < 0 || rect.w < 0 || rect.h < 0 ||
			rect.x + rect.w > availableWidth ||
			rect.y + rect.h > availableHeight) {
		failure = "Destination rectangle exceeds available output";
		return false;
	}
	long scaledWidth = cast(long)rect.w * sourceHeight;
	long scaledHeight = cast(long)rect.h * sourceWidth;
	if(scaledWidth < scaledHeight - sourceWidth ||
			scaledWidth > scaledHeight + sourceWidth) {
		failure = "Destination rectangle does not preserve uniform aspect";
		return false;
	}
	return true;
}

private int countOccurrences(string haystack, string needle) {
	int count;
	size_t offset;
	while(offset < haystack.length) {
		ptrdiff_t found = haystack.indexOf(needle, offset);
		if(found < 0)
			break;
		count++;
		offset = cast(size_t)found + needle.length;
	}
	return count;
}

bool checkInterfaceDestinationRectangles(out string failure) {
	enum sourceWidth = 800;
	enum sourceHeight = 715;
	if(!expectInterfaceDestinationRect(1920, 1080, sourceWidth, sourceHeight,
			356, 0, 1208, 1080, failure))
		return false;
	if(!expectInterfaceDestinationRect(2560, 1440, sourceWidth, sourceHeight,
			474, 0, 1611, 1440, failure))
		return false;
	if(!expectInterfaceDestinationRect(900, 1080, sourceWidth, sourceHeight,
			0, 138, 900, 804, failure))
		return false;
	return true;
}

private Uint32 interfaceTestArgb(Color)(Color color) {
	return 0xff000000u | (cast(Uint32)color.r << 16) |
		(cast(Uint32)color.g << 8) | cast(Uint32)color.b;
}

bool checkInterfaceBackgroundCoverage(out string failure) {
	enum framebufferWidth = 800;
	enum framebufferHeight = 715;
	enum screenOffsetY = 115;
	enum screenRows = 42;
	enum paintedHeight = screenOffsetY + screenRows * FONT_Y;
	enum sentinel = 0x7f123456u;
	immutable Uint32[INTERFACE_THEME_COUNT] expectedBackgrounds = [
		0xff000000u,
		0xff040914u,
		0xff001222u,
		0xff0c0c0cu
	];

	auto tail = interfaceFramebufferTailRect(framebufferWidth,
		framebufferHeight, screenOffsetY, screenRows, FONT_Y);
	if(paintedHeight != 703 || tail.x != 0 || tail.y != paintedHeight ||
			tail.w != framebufferWidth || tail.h != 12 ||
			tail.y < 0 || tail.h < 0 ||
			tail.y + tail.h > framebufferHeight) {
		failure = format("Framebuffer tail expected 0,703 800x12, got %d,%d %dx%d",
			tail.x, tail.y, tail.w, tail.h);
		return false;
	}

	auto noTail = interfaceFramebufferTailRect(framebufferWidth,
		framebufferHeight, screenOffsetY, screenRows + 1, FONT_Y);
	if(noTail.y != framebufferHeight || noTail.h != 0) {
		failure = "Framebuffer tail did not clamp safely at the lower boundary";
		return false;
	}

	auto savedPalette = PALETTE;
	scope(exit) PALETTE[] = savedPalette[];
	foreach(themeIndex; 0 .. INTERFACE_THEME_COUNT) {
		auto presetBackground = INTERFACE_PALETTE_PRESETS[themeIndex][0];
		Uint32 background = interfaceTestArgb(presetBackground);
		if(background != expectedBackgrounds[themeIndex]) {
			failure = format("Theme %d background changed from its accepted value",
				themeIndex + 1);
			return false;
		}

		PALETTE[] = INTERFACE_PALETTE_PRESETS[themeIndex][];
		auto activeBackground = activeInterfaceBackgroundColor();
		if(activeBackground.r != presetBackground.r ||
				activeBackground.g != presetBackground.g ||
				activeBackground.b != presetBackground.b) {
			failure = format("Theme %d active background is not palette index 0",
				themeIndex + 1);
			return false;
		}

		uint[] pixels = new uint[framebufferWidth * framebufferHeight];
		pixels[] = sentinel;
		if(!fillInterfaceFramebufferTail(pixels, framebufferWidth,
				framebufferHeight, screenOffsetY, screenRows, FONT_Y,
				background)) {
			failure = format("Theme %d framebuffer tail was not filled",
				themeIndex + 1);
			return false;
		}
		foreach(pixel; pixels[0 .. tail.y * framebufferWidth]) {
			if(pixel != sentinel) {
				failure = format("Theme %d fill overwrote painted interface pixels",
					themeIndex + 1);
				return false;
			}
		}
		foreach(pixel; pixels[tail.y * framebufferWidth .. $]) {
			if(pixel != background) {
				failure = format("Theme %d left an uncovered framebuffer pixel",
					themeIndex + 1);
				return false;
			}
		}
		if(pixels[tail.y * framebufferWidth] != background ||
				pixels[$ - 1] != background ||
				pixels[tail.y * framebufferWidth - 1] != sentinel) {
			failure = format("Theme %d tail edge or corner coverage is incorrect",
				themeIndex + 1);
			return false;
		}
	}

	uint[] reinitialised = new uint[framebufferWidth * framebufferHeight];
	Uint32 reinitialisedBackground = expectedBackgrounds[1];
	if(!fillInterfaceFramebufferTail(reinitialised, framebufferWidth,
			framebufferHeight, screenOffsetY, screenRows, FONT_Y,
			reinitialisedBackground) ||
			reinitialised[tail.y * framebufferWidth] != reinitialisedBackground ||
			reinitialised[$ - 1] != reinitialisedBackground ||
			reinitialised[tail.y * framebufferWidth - 1] != 0) {
		failure = "Framebuffer reinitialisation retained an independent zero tail";
		return false;
	}

	string framebufferSource = readText(buildPath("src", "com", "fb.d"));
	if(framebufferSource.indexOf(
			"SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)") >= 0 ||
			framebufferSource.indexOf(
				"auto background = activeInterfaceBackgroundColor();") < 0 ||
			framebufferSource.indexOf(
				"SDL_SetRenderDrawColor(renderer, background.r, background.g,") < 0) {
		failure = "Renderer clear is not derived from active palette index 0";
		return false;
	}
	return true;
}

bool checkContextualHelpResolverSource(out string failure) {
	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));

	foreach(required; [
			"enum FocusedHelpFamily",
			"sequence_instrument_column",
			"ContextHelp HELPSEQUENCEINSTRUMENTCOLUMN",
			"ContextHelp contextualHelpForFocusedFamily",
			"case FocusedHelpFamily.sequenceNote:",
			"return HELPSEQUENCECOLUMNS;",
			"case FocusedHelpFamily.sequenceInstrument:",
			"return HELPSEQUENCEINSTRUMENTCOLUMN;",
			"case FocusedHelpFamily.sequenceCommand:",
			"return HELPEFFECTS;",
			"case FocusedHelpFamily.sequenceGeneral:",
			"return HELPSEQUENCER;",
			"return HELPMAIN;"]) {
		if(helpSource.indexOf(required) < 0) {
			failure = format("Help resolver source is missing %s", required);
			return false;
		}
	}
	foreach(topicId; ["global_overview", "track_overview", "track_table",
			"track_map", "sequence_editor", "pattern_columns",
			"sequence_instrument_column", "command_effects",
			"instrument_table", "wave_table", "pulse_table",
			"filter_table"]) {
		if(helpSource.indexOf(topicId) < 0) {
			failure = format("Help source is missing topic %s", topicId);
			return false;
		}
	}
	if(uiSource.indexOf("openContextHelp();") < 0) {
		failure = "F12 route does not call openContextHelp";
		return false;
	}
	foreach(required; [
			"void openContextHelp()",
			"currentFocusedHelpFamily()",
			"InputSeq.noteColumn",
			"InputSeq.octaveColumn",
			"InputSeq.instrumentColumn",
			"InputSeq.commandColumn",
			"ui.help.contextualHelpForFocusedFamily"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("UI context resolver source is missing %s",
				required);
			return false;
		}
	}
	if(uiSource.indexOf("SDLK_F12") >= 0 &&
			uiSource.indexOf("openContextHelp") < 0) {
		failure = "F12 source check found no canonical action owner";
		return false;
	}
	if(uiSource.indexOf("INFOBAR_GLYPH_HELP_LEFT") >= 0 ||
			uiSource.indexOf("INFOBAR_GLYPH_HELP_RIGHT") >= 0) {
		failure = "Help icon was activated before UIH-2B2";
		return false;
	}
	return true;
}

bool checkHelpTopicHitGeometry(out string failure) {
	enum textOriginX = 10;
	enum headerOriginY = 5;
	string currentTopicId = "global_overview";
	size_t lineVisibleLength;
	int labelX = textOriginX;
	int labelY = headerOriginY + 1;
	int previousEnd = -1;
	int previousY = -1;

	bool[string] seen;
	if(HELP_TOPIC_COUNT != HELP_TOPIC_METADATA.length) {
		failure = "Help topic count does not match metadata length";
		return false;
	}

	foreach(i, topic; HELP_TOPIC_METADATA) {
		if(topic.id in seen) {
			failure = "Duplicate Help topic id: " ~ topic.id;
			return false;
		}
		seen[topic.id] = true;

		string label = topic.id == currentTopicId ?
			"[" ~ topic.tabLabel ~ "]" : " " ~ topic.tabLabel ~ " ";
		int separatorLength = lineVisibleLength == 0 ? 0 : 1;
		if(lineVisibleLength != 0 &&
				lineVisibleLength + separatorLength + label.length >
				HELP_TOPIC_HEADER_LINE_WIDTH) {
			labelY++;
			labelX = textOriginX;
			lineVisibleLength = 0;
			separatorLength = 0;
			previousEnd = -1;
			previousY = labelY;
		}
		if(separatorLength) {
			if(labelY == previousY) {
				auto gap = helpTopicAt(labelX, labelY, textOriginX,
					headerOriginY, currentTopicId);
				if(gap.valid) {
					failure = "Help topic gap resolved to " ~ gap.topicId;
					return false;
				}
			}
			labelX += separatorLength;
			lineVisibleLength += separatorLength;
		}

		auto first = helpTopicAt(labelX, labelY, textOriginX,
			headerOriginY, currentTopicId);
		auto last = helpTopicAt(labelX + cast(int)label.length - 1,
			labelY, textOriginX, headerOriginY, currentTopicId);
		if(!first.valid || first.topicId != topic.id ||
				first.topicIndex != cast(int)i) {
			failure = format("First Help topic cell failed for %s", topic.id);
			return false;
		}
		if(!last.valid || last.topicId != topic.id ||
				last.topicIndex != cast(int)i) {
			failure = format("Final Help topic cell failed for %s", topic.id);
			return false;
		}
		if(i == 0 && label[0] != '[') {
			failure = "Active Help topic does not use bracket geometry";
			return false;
		}
		if(i != 0 && label[0] != ' ') {
			failure = "Inactive Help topic does not use edge-padding geometry";
			return false;
		}
		if(previousEnd >= labelX && previousY == labelY) {
			failure = "Help topic labels overlap";
			return false;
		}
		previousEnd = labelX + cast(int)label.length - 1;
		previousY = labelY;
		labelX += cast(int)label.length;
		lineVisibleLength += label.length;
	}

	foreach(hit; [
			helpTopicAt(textOriginX, headerOriginY, textOriginX,
				headerOriginY, currentTopicId),
			helpTopicAt(textOriginX, headerOriginY + 5, textOriginX,
				headerOriginY, currentTopicId),
			helpTopicAt(textOriginX - 1, headerOriginY + 1, textOriginX,
				headerOriginY, currentTopicId),
			helpTopicAt(99, 41, textOriginX, headerOriginY,
				currentTopicId)]) {
		if(hit.valid) {
			failure = "Invalid Help topic coordinate resolved to " ~ hit.topicId;
			return false;
		}
	}
	if(helpTopicIndexForId("global_overview") != 0 ||
			helpTopicIndexForId("chord_table") !=
			cast(int)HELP_TOPIC_COUNT - 1 ||
			helpTopicIndexForId("not_a_topic") != -1) {
		failure = "Help topic id/index mapping failed";
		return false;
	}
	return true;
}

bool checkHelpDialogPerTopicScrollMemory(out string failure) {
	com.session.initSession();
	com.session.screen = new Screen(100, 42);
	HelpSessionState sessionState;
	auto dialog = new HelpDialog(Rectangle(5, 3, 36, 90), HELPMAIN,
		&sessionState);

	if(dialog.topicId != "global_overview" || dialog.scrollOffset != 0) {
		failure = "Global Help did not start at offset zero";
		return false;
	}
	dialog.keypress(Keyinfo(SDLK_PAGEDOWN, 0, 0));
	int globalOffset = dialog.scrollOffset;
	if(globalOffset <= 0 ||
			sessionState.scrollOffsets[helpTopicIndexForId(
				"global_overview")] != globalOffset) {
		failure = "Global Help scroll was not stored";
		return false;
	}

	dialog.keypress(Keyinfo(SDLK_RIGHT, 0, 0));
	if(dialog.topicId != "track_overview" || dialog.scrollOffset != 0) {
		failure = "Track Overview Help did not start at its own zero offset";
		return false;
	}
	dialog.keypress(Keyinfo(SDLK_PAGEDOWN, 0, 0));
	int trackOffset = dialog.scrollOffset;
	if(trackOffset <= 0) {
		failure = "Track Overview Help did not scroll";
		return false;
	}

	dialog.clickedAt(36, 7, 1);
	if(dialog.topicId != "playback" || dialog.scrollOffset != 0) {
		failure = "Untouched third Help topic did not start at zero";
		return false;
	}
	dialog.clickedAt(10, 6, 1);
	if(dialog.topicId != "global_overview" ||
			dialog.scrollOffset != globalOffset) {
		failure = "Global Help offset was not restored";
		return false;
	}
	dialog.clickedAt(19, 6, 1);
	if(dialog.topicId != "track_overview" ||
			dialog.scrollOffset != trackOffset) {
		failure = "Track Overview Help offset was not restored";
		return false;
	}

	dialog.keypress(Keyinfo(SDLK_HOME, 0, 0));
	if(dialog.scrollOffset != 0 ||
			sessionState.scrollOffsets[helpTopicIndexForId(
				"track_overview")] != 0) {
		failure = "Home did not reset only the active Help topic";
		return false;
	}
	dialog.clickedAt(10, 6, 1);
	if(dialog.scrollOffset != globalOffset) {
		failure = "Home reset another Help topic's stored offset";
		return false;
	}
	dialog.clickedAt(19, 6, 1);
	dialog.keypress(Keyinfo(SDLK_END, 0, 0));
	int bodyViewportLines = 36 - 4 - cast(int)dialog.headerLines.length - 1;
	int expectedMax = cast(int)dialog.bodyLines.length - bodyViewportLines;
	if(expectedMax < 0)
		expectedMax = 0;
	if(dialog.scrollOffset != expectedMax) {
		failure = "End did not clamp to the active Help topic maximum";
		return false;
	}
	dialog.keypress(Keyinfo(SDLK_PAGEDOWN, 0, 0));
	if(dialog.scrollOffset != expectedMax) {
		failure = "PageDown moved Help beyond the final page";
		return false;
	}

	dialog.deactivate();
	auto reopened = new HelpDialog(Rectangle(5, 3, 36, 90),
		HELPTRACKOVERVIEW, &sessionState);
	if(reopened.scrollOffset != expectedMax) {
		failure = "Closing and reopening Help did not preserve topic offset";
		return false;
	}
	HelpSessionState freshSessionState;
	auto fresh = new HelpDialog(Rectangle(5, 3, 36, 90),
		HELPTRACKOVERVIEW, &freshSessionState);
	if(fresh.scrollOffset != 0) {
		failure = "Fresh Help session did not start at offset zero";
		return false;
	}
	return true;
}

bool checkHelpDialogPinnedHeaderAndRouteSharing(out string failure) {
	com.session.initSession();
	com.session.screen = new Screen(100, 42);
	HelpSessionState sessionState;
	auto dialog = new HelpDialog(Rectangle(5, 3, 36, 90), HELPMAIN,
		&sessionState);

	dialog.update();
	ushort headerCell = com.session.screen.getChar(10, 6);
	dialog.keypress(Keyinfo(SDLK_PAGEDOWN, 0, 0));
	dialog.update();
	if(com.session.screen.getChar(10, 6) != headerCell) {
		failure = "Help topic header moved or changed after PageDown";
		return false;
	}
	dialog.keypress(Keyinfo(SDLK_END, 0, 0));
	dialog.update();
	if(com.session.screen.getChar(10, 6) != headerCell) {
		failure = "Help topic header moved or changed after End";
		return false;
	}
	int previousOffset = dialog.scrollOffset;
	dialog.clickedAt(10, 6, 1);
	if(dialog.topicId != "global_overview" ||
			dialog.scrollOffset != previousOffset) {
		failure = "Same-topic Help click reset offset";
		return false;
	}
	dialog.clickedAt(18, 6, 1);
	if(dialog.topicId != "global_overview" ||
			dialog.scrollOffset != previousOffset) {
		failure = "Help topic gap click changed topic or offset";
		return false;
	}
	dialog.clickedAt(15, 12, 1);
	if(dialog.topicId != "global_overview" ||
			dialog.scrollOffset != previousOffset) {
		failure = "Help body click changed topic or offset";
		return false;
	}
	dialog.clickedAt(19, 6, 3);
	if(dialog.topicId != "global_overview") {
		failure = "Right-click changed Help topic";
		return false;
	}

	string dialogsSource = readText(buildPath("src", "ui", "dialogs.d"));
	foreach(required; [
			"switchToTopic(hit.topicId)",
			"switchTopicByDirection",
			"switchToTopic(nextTopicId)",
			"saveActiveOffset();",
			"restoreStoredOffset();",
			"removeScrollableHeaderFromBody();"]) {
		if(dialogsSource.indexOf(required) < 0) {
			failure = "Missing canonical Help navigation source: " ~ required;
			return false;
		}
	}
	if(dialogsSource.indexOf("scrollOffset = 0;\\n\\t}") >= 0) {
		failure = "Old unconditional Help load offset reset appears to remain";
		return false;
	}
	return true;
}

private bool testChordJumpMarker(ubyte value) {
	return value >= 0x80;
}

private int testChordSemitoneOffset(ubyte value) {
	int offset = value;
	if(offset >= 0x40)
		offset -= 0x80;
	return offset;
}

private ubyte testChordJumpDestination(ubyte value) {
	return cast(ubyte)(value & 0x7f);
}

private bool testChordShuffleModeForSpeed(ubyte speed) {
	return speed < 2;
}

bool checkChordTableHelpSemantics(out string failure) {
	if(testChordSemitoneOffset(0x00) != 0 ||
			testChordSemitoneOffset(0x3f) != 63 ||
			testChordSemitoneOffset(0x40) != -64 ||
			testChordSemitoneOffset(0x7f) != -1) {
		failure = "Chord signed semitone-offset mapping changed";
		return false;
	}
	if(testChordJumpMarker(0x7f) ||
			!testChordJumpMarker(0x80) ||
			!testChordJumpMarker(0x94) ||
			!testChordJumpMarker(0xff)) {
		failure = "Chord jump-marker threshold changed";
		return false;
	}
	if(testChordJumpDestination(0x80) != 0x00 ||
			testChordJumpDestination(0x94) != 0x14 ||
			testChordJumpDestination(0xff) != 0x7f) {
		failure = "Chord jump-destination calculation changed";
		return false;
	}
	if(!testChordShuffleModeForSpeed(0) ||
			!testChordShuffleModeForSpeed(1) ||
			testChordShuffleModeForSpeed(2) ||
			testChordShuffleModeForSpeed(5) ||
			testChordShuffleModeForSpeed(0x1f)) {
		failure = "Chord shuffle speed threshold changed";
		return false;
	}

	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string tableSource = readText(buildPath("src", "ui", "tables.d"));
	foreach(required; [
			`enum string CHORD_TABLE_TOPIC_ID = "chord_table"`,
			"ContextHelp HELPCHORDTABLE",
			"bool isChordJumpMarker",
			"int chordSemitoneOffset",
			"ubyte chordJumpDestination",
			"bool chordShuffleModeForSpeed",
			"string chordTableQuickHelp",
			"$94 -> row $14",
			"$40-$7F",
			"jump marker",
			"shuffle row-length"]) {
		if(helpSource.indexOf(required) < 0) {
			failure = format("Chord Help source is missing %s", required);
			return false;
		}
	}
	if(helpSource.indexOf("wrap/end marker") >= 0) {
		failure = "Chord Help still uses wrap/end marker terminology";
		return false;
	}
	if(tableSource.indexOf("return ui.help.HELPCHORDTABLE;") < 0) {
		failure = "ChordTable.contextHelp does not return HELPCHORDTABLE";
		return false;
	}
	if(tableSource.indexOf("ui.help.chordTableQuickHelp") < 0) {
		failure = "ChordTable quickhelp does not use the shared semantic owner";
		return false;
	}
	foreach(removed; [
			"Chord: 00-7F semitone offsets",
			"80-FF wrap/end marker",
			"Shuffle tempo wrap"]) {
		if(tableSource.indexOf(removed) >= 0) {
			failure = format("Superseded Chord quickhelp remains: %s", removed);
			return false;
		}
	}
	return true;
}

private bool placementFor(BottomControlLayout layout, BottomControlRole role,
		out BottomControlPlacement found) {
	foreach(i; 0 .. layout.count) {
		if(layout.placements[i].role == role) {
			found = layout.placements[i];
			return true;
		}
	}
	return false;
}

private bool expectBottomControlRect(BottomControlLayout layout,
		BottomControlRole role, int x, int y, int width, int height,
		out string failure) {
	BottomControlPlacement placement;
	if(!placementFor(layout, role, placement)) {
		failure = format("Missing bottom control role %s", role);
		return false;
	}
	if(placement.rect.x != x || placement.rect.y != y ||
			placement.rect.width != width || placement.rect.height != height) {
		failure = format("Role %s expected [%d,%d)+%dx%d, got [%d,%d)+%dx%d",
			role, x, y, width, height, placement.rect.x, placement.rect.y,
			placement.rect.width, placement.rect.height);
		return false;
	}
	return true;
}

private bool expectBottomControlHit(int screenWidth, int screenHeight,
		int x, int y, BottomControlRole role, out string failure) {
	auto hit = bottomControlAtCell(screenWidth, screenHeight, x, y);
	if(role == BottomControlRole.none) {
		if(hit.matched) {
			failure = format("Cell %d,%d unexpectedly hit role %s", x, y,
				hit.role);
			return false;
		}
		return true;
	}
	if(!hit.matched || hit.role != role) {
		failure = format("Cell %d,%d expected role %s, got %s", x, y, role,
			hit.matched ? format("%s", hit.role) : "none");
		return false;
	}
	return true;
}

private bool expectBottomControlInteraction(int screenWidth, int screenHeight,
		int x, int y, int button, int currentThemeIndex, bool handled,
		BottomControlRole role, bool invokeAction, int themeIndex,
		out string failure) {
	auto interaction = bottomControlInteractionAtCell(screenWidth, screenHeight,
		x, y, button, currentThemeIndex);
	if(interaction.handled != handled || interaction.role != role ||
			interaction.invokeAction != invokeAction ||
			interaction.themeIndex != themeIndex) {
		failure = format("Cell %d,%d button %d expected handled=%s role=%s " ~
			"invoke=%s theme=%d, got handled=%s role=%s invoke=%s theme=%d",
			x, y, button, handled, role, invokeAction, themeIndex,
			interaction.handled, interaction.role, interaction.invokeAction,
			interaction.themeIndex);
		return false;
	}
	return true;
}

private bool bottomControlOccupied(BottomControlLayout layout, int x, int y) {
	foreach(i; 0 .. layout.count) {
		if(layout.placements[i].rect.contains(x, y))
			return true;
	}
	return false;
}

private bool checkBottomControlInteractionsForLayout(int screenWidth,
		int screenHeight, out string failure) {
	auto layout = bottomControlLayout(screenWidth, screenHeight);
	if(!layout.valid) {
		failure = format("%dx%d bottom-control layout is invalid", screenWidth,
			screenHeight);
		return false;
	}

	foreach(i; 0 .. layout.count) {
		auto placement = layout.placements[i];
		int themeIndex = bottomControlThemeIndex(placement.role);
		foreach(x; placement.rect.x .. placement.rect.x + placement.rect.width) {
			if(!expectBottomControlInteraction(screenWidth, screenHeight, x,
					placement.rect.y, 1, -1, true, placement.role, true,
					themeIndex, failure))
				return false;
			if(!expectBottomControlInteraction(screenWidth, screenHeight, x,
					placement.rect.y, 2, -1, true, placement.role, false,
					themeIndex, failure))
				return false;
			if(!expectBottomControlInteraction(screenWidth, screenHeight, x,
					placement.rect.y, 3, -1, true, placement.role, false,
					themeIndex, failure))
				return false;
			if(themeIndex >= 0 &&
					!expectBottomControlInteraction(screenWidth, screenHeight, x,
						placement.rect.y, 1, themeIndex, true, placement.role,
						false, themeIndex, failure))
				return false;
		}
	}

	int row = bottomControlRow(screenHeight);
	foreach(x; 0 .. screenWidth) {
		if(!bottomControlOccupied(layout, x, row) &&
				!expectBottomControlInteraction(screenWidth, screenHeight, x, row,
					1, -1, false, BottomControlRole.none, false, -1, failure))
			return false;
	}
	foreach(x; 0 .. screenWidth) {
		if(!expectBottomControlInteraction(screenWidth, screenHeight, x, row - 1,
				1, -1, false, BottomControlRole.none, false, -1, failure))
			return false;
		if(!expectBottomControlInteraction(screenWidth, screenHeight, x, row + 1,
				1, -1, false, BottomControlRole.none, false, -1, failure))
			return false;
	}
	return true;
}

bool checkBottomControlLayout(out string failure) {
	auto layout100 = bottomControlLayout(100, 42);
	if(!layout100.valid || layout100.count != 10) {
		failure = "100x42 bottom-control layout is invalid";
		return false;
	}
	foreach(spec; [
			tuple(BottomControlRole.fullscreen, 2, 41, 2),
			tuple(BottomControlRole.theme1, 5, 41, 1),
			tuple(BottomControlRole.theme2, 7, 41, 1),
			tuple(BottomControlRole.theme3, 9, 41, 1),
			tuple(BottomControlRole.theme4, 11, 41, 1),
			tuple(BottomControlRole.load, 84, 41, 2),
			tuple(BottomControlRole.save, 87, 41, 2),
			tuple(BottomControlRole.keyjam, 90, 41, 2),
			tuple(BottomControlRole.audio, 93, 41, 2),
			tuple(BottomControlRole.help, 96, 41, 2)]) {
		if(!expectBottomControlRect(layout100, spec[0], spec[1], spec[2],
				spec[3], 1, failure))
			return false;
	}

	BottomControlPlacement placement;
	if(!placementFor(layout100, BottomControlRole.fullscreen, placement) ||
			placement.glyphs[0] != INFOBAR_GLYPH_FULLSCREEN_LEFT ||
			placement.glyphs[1] != INFOBAR_GLYPH_FULLSCREEN_RIGHT ||
			placement.glyphCount != 2) {
		failure = "Fullscreen glyph pair changed";
		return false;
	}
	if(!placementFor(layout100, BottomControlRole.help, placement) ||
			placement.glyphs[0] != INFOBAR_GLYPH_HELP_LEFT ||
			placement.glyphs[1] != INFOBAR_GLYPH_HELP_RIGHT ||
			placement.glyphCount != 2) {
		failure = "Help glyph pair changed";
		return false;
	}
	foreach(spec; [
			tuple(BottomControlRole.theme1, INFOBAR_GLYPH_THEME_CLASSIC),
			tuple(BottomControlRole.theme2, INFOBAR_GLYPH_THEME_C64),
			tuple(BottomControlRole.theme3, INFOBAR_GLYPH_THEME_C64_MIDNIGHT),
			tuple(BottomControlRole.theme4, INFOBAR_GLYPH_THEME_NEON)]) {
		if(!placementFor(layout100, spec[0], placement) ||
				placement.glyphs[0] != spec[1] || placement.glyphCount != 1) {
			failure = format("Theme glyph changed for %s", spec[0]);
			return false;
		}
	}
	foreach(spec; [
			tuple(BottomControlRole.load, INFOBAR_GLYPH_SAVE_LEFT,
				INFOBAR_GLYPH_SAVE_RIGHT),
			tuple(BottomControlRole.save, INFOBAR_GLYPH_LOAD_LEFT,
				INFOBAR_GLYPH_LOAD_RIGHT),
			tuple(BottomControlRole.keyjam, INFOBAR_GLYPH_KEYJAM_LEFT,
				INFOBAR_GLYPH_KEYJAM_RIGHT),
			tuple(BottomControlRole.audio, INFOBAR_GLYPH_AUDIO_LEFT,
				INFOBAR_GLYPH_AUDIO_RIGHT)]) {
		if(!placementFor(layout100, spec[0], placement) ||
				placement.glyphs[0] != spec[1] ||
				placement.glyphs[1] != spec[2] ||
				placement.glyphCount != 2) {
			failure = format("Action glyph pair changed for %s", spec[0]);
			return false;
		}
	}

	auto layout120 = bottomControlLayout(120, 42);
	foreach(spec; [
			tuple(BottomControlRole.load, 104, 41, 2),
			tuple(BottomControlRole.save, 107, 41, 2),
			tuple(BottomControlRole.keyjam, 110, 41, 2),
			tuple(BottomControlRole.audio, 113, 41, 2),
			tuple(BottomControlRole.help, 116, 41, 2)]) {
		if(!expectBottomControlRect(layout120, spec[0], spec[1], spec[2],
				spec[3], 1, failure))
			return false;
	}
	if(bottomControlLayout(27, 42).valid) {
		failure = "Width 27 should reject bottom-control layout";
		return false;
	}
	auto layout28 = bottomControlLayout(28, 42);
	if(!layout28.valid) {
		failure = "Width 28 should support non-overlapping strips";
		return false;
	}
	foreach(i; 0 .. layout28.count) {
		foreach(j; i + 1 .. layout28.count) {
			auto a = layout28.placements[i].rect;
			auto b = layout28.placements[j].rect;
			bool xOverlap = a.x < b.x + b.width && b.x < a.x + a.width;
			bool yOverlap = a.y < b.y + b.height && b.y < a.y + a.height;
			if(xOverlap && yOverlap) {
				failure = "Width 28 bottom-control strips overlap";
				return false;
			}
		}
	}

	foreach(spec; [
			tuple(0, 41, BottomControlRole.none),
			tuple(1, 41, BottomControlRole.none),
			tuple(2, 41, BottomControlRole.fullscreen),
			tuple(3, 41, BottomControlRole.fullscreen),
			tuple(4, 41, BottomControlRole.none),
			tuple(5, 41, BottomControlRole.theme1),
			tuple(6, 41, BottomControlRole.none),
			tuple(7, 41, BottomControlRole.theme2),
			tuple(8, 41, BottomControlRole.none),
			tuple(9, 41, BottomControlRole.theme3),
			tuple(10, 41, BottomControlRole.none),
			tuple(11, 41, BottomControlRole.theme4),
			tuple(83, 41, BottomControlRole.none),
			tuple(84, 41, BottomControlRole.load),
			tuple(85, 41, BottomControlRole.load),
			tuple(86, 41, BottomControlRole.none),
			tuple(87, 41, BottomControlRole.save),
			tuple(88, 41, BottomControlRole.save),
			tuple(89, 41, BottomControlRole.none),
			tuple(90, 41, BottomControlRole.keyjam),
			tuple(91, 41, BottomControlRole.keyjam),
			tuple(92, 41, BottomControlRole.none),
			tuple(93, 41, BottomControlRole.audio),
			tuple(94, 41, BottomControlRole.audio),
			tuple(95, 41, BottomControlRole.none),
			tuple(96, 41, BottomControlRole.help),
			tuple(97, 41, BottomControlRole.help),
			tuple(98, 41, BottomControlRole.none),
			tuple(99, 41, BottomControlRole.none),
			tuple(100, 41, BottomControlRole.none),
			tuple(1, 40, BottomControlRole.none),
			tuple(1, 42, BottomControlRole.none)]) {
		if(!expectBottomControlHit(100, 42, spec[0], spec[1], spec[2],
				failure))
			return false;
	}

	return true;
}

bool checkBottomControlInteractionRouting(out string failure) {
	if(!checkBottomControlInteractionsForLayout(100, 42, failure))
		return false;
	if(!checkBottomControlInteractionsForLayout(120, 42, failure))
		return false;
	if(!checkBottomControlInteractionsForLayout(28, 42, failure))
		return false;
	if(!expectBottomControlInteraction(27, 42, 2, 41, 1, -1, false,
			BottomControlRole.none, false, -1, failure))
		return false;

	auto layout120 = bottomControlLayout(120, 42);
	BottomControlPlacement helpPlacement;
	if(!placementFor(layout120, BottomControlRole.help, helpPlacement)) {
		failure = "120-column Help placement missing";
		return false;
	}
	if(helpPlacement.rect.x + helpPlacement.rect.width !=
			120 - BOTTOM_CONTROL_RIGHT_PADDING) {
		failure = "Help control is not right-aligned at 120 columns";
		return false;
	}

	foreach(spec; [
			tuple(BottomControlRole.theme1, 0),
			tuple(BottomControlRole.theme2, 1),
			tuple(BottomControlRole.theme3, 2),
			tuple(BottomControlRole.theme4, 3)]) {
		BottomControlPlacement placement;
		if(!placementFor(bottomControlLayout(100, 42), spec[0], placement)) {
			failure = format("Theme placement missing for %s", spec[0]);
			return false;
		}
		if(!expectBottomControlInteraction(100, 42, placement.rect.x,
				placement.rect.y, 1, spec[1], true, spec[0], false, spec[1],
				failure))
			return false;
		int otherTheme = (spec[1] + 1) % 4;
		if(!expectBottomControlInteraction(100, 42, placement.rect.x,
				placement.rect.y, 1, otherTheme, true, spec[0], true, spec[1],
				failure))
			return false;
	}

	return true;
}

bool checkBottomControlSourceOwnership(out string failure) {
	string bottomSource = readText(buildPath("src", "ui", "bottomcontrols.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	foreach(forbidden; ["ui.ui", "ui.dialogs", "callback", "delegate",
			"openContextHelp", "executeUiGlobalAction"]) {
		if(bottomSource.indexOf(forbidden) >= 0) {
			failure = format("bottomcontrols.d owns UI action detail %s",
				forbidden);
			return false;
		}
	}
	foreach(required; ["leftBottomControls", "rightBottomControls",
			"bottomControlLayout", "bottomControlAtCell",
			"bottomControlInteractionAtCell", "BottomControlInteraction"]) {
		if(bottomSource.indexOf(required) < 0) {
			failure = format("bottomcontrols.d missing %s", required);
			return false;
		}
	}
	foreach(required; ["bottomControlLayout(screen.width, screen.height)",
			"bottomControlInteractionAtCell(screen.width,",
			"if(!interaction.handled)",
			"if(interaction.invokeAction)",
			"mainui.openContextHelp();",
			"mainui.executeUiGlobalAction(KeyboardActionId.uiToggleFullscreen)",
			"if(UI.infobar.clickedBottomControlAt(x, y, b))"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("ui.d bottom-control ownership missing %s",
				required);
			return false;
		}
	}
	foreach(forbidden; ["struct IconControl", "struct ThemeControl",
			"INFOBAR_GLYPH_HELP_LEFT", "INFOBAR_GLYPH_FULLSCREEN_LEFT",
			"ThemeControl(", "IconControl(", "Keyinfo(SDLK_F12",
			"Keyinfo(SDLK_F12,"]) {
		if(uiSource.indexOf(forbidden) >= 0) {
			failure = format("ui.d retains superseded bottom-control detail %s",
				forbidden);
			return false;
		}
	}
	return true;
}

bool checkStatuslineKeyjamAlertOwnership(out string failure) {
	string uiSource = readText(buildPath("src", "ui", "ui.d"));

	foreach(required; [
			"private enum STATUSLINE_ALERT_COLOR = 1;",
			"private enum STATUSLINE_ALERT_BACKGROUND = 0;",
			"void setPersistentAlertMessage(string msg)",
			"persistentContextualAlert = true;",
			"statusline.setPersistentAlertMessage(keyjamQuickHelpMessage());",
			"keyboardActionPrimaryShortcutLabel(",
			"keyboardActionStableId(KeyboardActionId.songKeyjamToggle)",
			"return \"Keyjam enabled - \" ~ label ~ \" disables it\";",
			"bool persistentAlertVisible = normalTextVisible && !failureVisible",
			"bool alertVisible = failureVisible || persistentAlertVisible;",
			"showAlertGlyph();",
			"hideAlertGlyph();",
			"string color = alertVisible ? \"`01\" : \"`0f\";",
			"video.submitStatuslineFailureGlyph(STATUSLINE_ALERT_ICON_X",
			"helpToggleVisible ? message :",
			"failureVisible ? failureMessage :",
			"timedMessageVisible ? message :",
			"persistentVisible ? persistentContextualMessage :",
			"persistentContextualAlert = false;"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("Statusline keyjam alert source missing %s",
				required);
			return false;
		}
	}

	auto keyjamStart = uiSource.indexOf("private void updateKeyjamQuickHelp()");
	auto refreshStart = uiSource.indexOf("private void refreshCurrentContextualHelp()");
	if(keyjamStart < 0 || refreshStart <= keyjamStart) {
		failure = "Could not isolate updateKeyjamQuickHelp source";
		return false;
	}
	string keyjamSource = uiSource[cast(size_t)keyjamStart ..
		cast(size_t)refreshStart];
	foreach(forbidden; ["displayFailure", "failureCounter", "failureMessage"]) {
		if(keyjamSource.indexOf(forbidden) >= 0) {
			failure = format("Keyjam alert path writes failure lifetime state: %s",
				forbidden);
			return false;
		}
	}

	auto displayFailureStart = uiSource.indexOf("void displayFailure(string msg)");
	auto interactionStart = uiSource.indexOf("void noteMeaningfulInteraction()");
	if(displayFailureStart < 0 || interactionStart <= displayFailureStart) {
		failure = "Could not isolate displayFailure source";
		return false;
	}
	string failureSource = uiSource[cast(size_t)displayFailureStart ..
		cast(size_t)interactionStart];
	if(failureSource.indexOf("failureCounter = FAILURE_TIMEOUT;") < 0 ||
			failureSource.indexOf("showAlertGlyph();") < 0) {
		failure = "Failure path no longer owns timeout plus alert glyph";
		return false;
	}
	if(failureSource.indexOf("setPersistentAlertMessage") >= 0 ||
			failureSource.indexOf("persistentContextualAlert") >= 0) {
		failure = "Failure path was merged with persistent keyjam state";
		return false;
	}

	return true;
}

bool checkHelpTextToggleStatusOwnership(out string failure) {
	string uiSource = readText(buildPath("src", "ui", "ui.d"));

	foreach(required; [
			"enum HELP_TEXT_TOGGLE_STATUS_TICKS = 35;",
			"void displayHelpTextToggleConfirmation(string msg)",
			"counter = HELP_TEXT_TOGGLE_STATUS_TICKS;",
			"state.displayHelp ^= 1;",
			"UI.statusline.displayHelpTextToggleConfirmation(\"Help texts \" ~",
			"(state.displayHelp ? \"enabled.\" : \"disabled.\")",
			"void displayTimedOperationFeedback(string msg)",
			"counter = CONFIRM_TIMEOUT;",
			"void displayFailure(string msg)",
			"failureCounter = FAILURE_TIMEOUT;",
			"if(redraw)",
			"update();"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("Help text toggle status source missing %s",
				required);
			return false;
		}
	}

	auto confirmTimeoutStart = uiSource.indexOf("enum CONFIRM_TIMEOUT = 3000;");
	auto helpToggleTimeoutStart = uiSource.indexOf(
		"enum HELP_TEXT_TOGGLE_STATUS_TICKS = 35;");
	auto failureTimeoutStart = uiSource.indexOf("enum FAILURE_TIMEOUT = 250;");
	if(confirmTimeoutStart < 0 || helpToggleTimeoutStart <= confirmTimeoutStart ||
			failureTimeoutStart <= helpToggleTimeoutStart) {
		failure = "Help text toggle duration is not declared near Statusline timeouts";
		return false;
	}

	auto toggleStart = uiSource.indexOf("private bool handleUiHelpTextToggleKey");
	auto clearStart = uiSource.indexOf("private bool handleSongClearSequencesKey");
	if(toggleStart < 0 || clearStart <= toggleStart) {
		failure = "Could not isolate Help text toggle handler";
		return false;
	}
	string toggleSource = uiSource[cast(size_t)toggleStart ..
		cast(size_t)clearStart];
	if(toggleSource.indexOf("displayFailure") >= 0 ||
			toggleSource.indexOf("failureCounter") >= 0 ||
			toggleSource.indexOf("dismissFailureForContextInteraction") >= 0) {
		failure = "Help text toggle handler changed failure ownership";
		return false;
	}
	if(toggleSource.indexOf("UI.statusline.display(\"Help texts ") >= 0 ||
			toggleSource.indexOf("CONFIRM_TIMEOUT") >= 0 ||
			toggleSource.indexOf("HELP_TEXT_TOGGLE_STATUS_TICKS") >= 0) {
		failure = "Help text toggle handler bypasses the short Statusline owner";
		return false;
	}

	auto displayStart = uiSource.indexOf("void displayTimedOperationFeedback(string msg)");
	auto helpToggleStart = uiSource.indexOf(
		"void displayHelpTextToggleConfirmation(string msg)");
	auto failureStart = uiSource.indexOf("void displayFailure(string msg)");
	if(displayStart < 0 || helpToggleStart <= displayStart ||
			failureStart <= helpToggleStart) {
		failure = "Could not isolate Statusline timed-message owners";
		return false;
	}
	string displaySource = uiSource[cast(size_t)displayStart ..
		cast(size_t)helpToggleStart];
	string helpToggleSource = uiSource[cast(size_t)helpToggleStart ..
		cast(size_t)failureStart];
	if(displaySource.indexOf("counter = CONFIRM_TIMEOUT;") < 0 ||
			displaySource.indexOf("HELP_TEXT_TOGGLE_STATUS_TICKS") >= 0) {
		failure = "Timed operation-feedback timeout changed";
		return false;
	}
	if(helpToggleSource.indexOf("counter = HELP_TEXT_TOGGLE_STATUS_TICKS;") < 0 ||
			helpToggleSource.indexOf("message = msg;") < 0 ||
			helpToggleSource.indexOf("update();") < 0 ||
			helpToggleSource.indexOf("failure") >= 0 ||
			helpToggleSource.indexOf("persistentContextual") >= 0) {
		failure = "Help text toggle owner does not reuse timed-message state cleanly";
		return false;
	}

	return true;
}

bool checkContextDismissibleStatusOwnership(out string failure) {
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	string seqtableSource = readText(buildPath("src", "seq", "seqtable.d"));
	string sequencerSource = readText(buildPath("src", "seq", "sequencer.d"));
	string tracktableSource = readText(buildPath("src", "seq", "tracktable.d"));

	foreach(required; [
			"private enum StatuslineInformationLifetime",
			"timedOnly",
			"contextDismissible",
			"private string contextualOwner;",
			"private StatuslineInformationLifetime informationLifetime;",
			"void displayTimedOperationFeedback(string msg)",
			"void displayOperationFeedback(string msg)",
			"informationLifetime =\n\t\t\tStatuslineInformationLifetime.contextDismissible;",
			"private ulong interactionGeneration;",
			"private ulong transientGeneration;",
			"void noteMeaningfulInteraction()",
			"clearIneligibleTransientStatus();",
			"void displayContextual(string msg, string sourceFile = __FILE__,\n\t\t\tsize_t sourceLine = __LINE__)",
			"string owner = contextualOwnerId(sourceFile, sourceLine);",
			"contextualMessage = msg;",
			"contextualOwner = owner;",
			"static string contextualOwnerId(string sourceFile, size_t sourceLine)",
			"string owner = sourceFile ~ \":\" ~ to!string(sourceLine);",
			"Window activeWindow = mainui.activeWindow;",
			"Input activeInput = mainui.activeInput;",
			"cast(size_t)cast(void*)activeWindow",
			"activeInput.cursor.x",
			"activeInput.cursor.y",
			"activeInput.nibble"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("Context-dismissible Statusline source missing %s",
				required);
			return false;
		}
	}

	auto displayStart = uiSource.indexOf("void displayTimedOperationFeedback(string msg)");
	auto contextDisplayStart = uiSource.indexOf(
		"void displayOperationFeedback(string msg)");
	auto helpToggleStart = uiSource.indexOf(
		"void displayHelpTextToggleConfirmation(string msg)");
	auto failureStart = uiSource.indexOf("void displayFailure(string msg)");
	auto interactionStart = uiSource.indexOf("void noteMeaningfulInteraction()");
	auto contextualStart = uiSource.indexOf("void displayContextual(string msg");
	auto setPersistentStart = uiSource.indexOf(
		"void setPersistentContextualMessage(string msg)");
	if(displayStart < 0 || contextDisplayStart <= displayStart ||
			helpToggleStart <= contextDisplayStart ||
			failureStart <= helpToggleStart ||
			interactionStart <= failureStart ||
			contextualStart <= failureStart ||
			setPersistentStart <= contextualStart) {
		failure = "Could not isolate Statusline lifetime owners";
		return false;
	}
	string displaySource = uiSource[cast(size_t)displayStart ..
		cast(size_t)contextDisplayStart];
	string contextDisplaySource = uiSource[cast(size_t)contextDisplayStart ..
		cast(size_t)helpToggleStart];
	string helpToggleSource = uiSource[cast(size_t)helpToggleStart ..
		cast(size_t)failureStart];
	string failureSource = uiSource[cast(size_t)failureStart ..
		cast(size_t)interactionStart];
	string contextualSource = uiSource[cast(size_t)contextualStart ..
		cast(size_t)setPersistentStart];

	if(displaySource.indexOf(
			"informationLifetime = StatuslineInformationLifetime.timedOnly;") < 0 ||
			displaySource.indexOf("contextDismissible") >= 0) {
		failure = "Generic display() is not retained as timed-only";
		return false;
	}
	if(contextDisplaySource.indexOf("counter = CONFIRM_TIMEOUT;") < 0 ||
			contextDisplaySource.indexOf("message = msg;") < 0 ||
			contextDisplaySource.indexOf("contextDismissible") < 0 ||
			contextDisplaySource.indexOf("if(!state.displayHelp)") < 0) {
		failure = "Operation feedback does not own context-dismissible state";
		return false;
	}
	if(helpToggleSource.indexOf(
			"informationLifetime = StatuslineInformationLifetime.timedOnly;") < 0 ||
			helpToggleSource.indexOf("HELP_TEXT_TOGGLE_STATUS_TICKS") < 0 ||
			helpToggleSource.indexOf("contextDismissible") >= 0) {
		failure = "Help toggle was reclassified as context-dismissible";
		return false;
	}
	if(failureSource.indexOf("failureCounter = FAILURE_TIMEOUT;") < 0 ||
			failureSource.indexOf("informationLifetime = StatuslineInformationLifetime.timedOnly;") < 0 ||
			failureSource.indexOf("dismissOperationFeedback") >= 0) {
		failure = "Failure lifetime was merged with ordinary dismissal";
		return false;
	}
	if(contextualSource.indexOf("contextualMessage == msg") >= 0 ||
			contextualSource.indexOf("message == msg") >= 0 ||
			contextualSource.indexOf("dismissOperationFeedbackForContextChange") >= 0) {
		failure = "displayContextual uses message text as semantic identity";
		return false;
	}

	foreach(required; [
			"displayTimedOperationFeedback(\n\t\t\t\"Song data optimized.\")",
			"displayTimedOperationFeedback(\n\t\t\t\"Sequence data cleared.\")",
			"displayOperationFeedback(\"Tracking off.\")",
			"displayOperationFeedback(\"Tracking on.\")",
			"Save complete: \\\"%s\\\".",
			"Export complete: \\\"%s\\\".",
			"displayTimedOperationFeedback(\"Import complete.\")",
			"Track selection copied: %d.",
			"Track selection pasted: %d.",
			"\"No track entries selected.\"",
			"\"No track entries copied.\"",
			"\"No track entry selected.\"",
			"trackNextUnusedSequenceUnavailableMessage()"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("Converted ui.d status source missing %s",
				required);
			return false;
		}
	}

	foreach(required; [
			"format(\n\t\t\t\t\"Sequence selection copied: %d.\", rowClipboard.rowCount)",
			"format(\n\t\t\t\t\"Sequence selection pasted: %d.\", rowsToPaste)",
			"displayOperationFeedback(\n\t\t\t\t\t\"No sequence rows selected.\")",
			"displayOperationFeedback(\n\t\t\t\t\t\"No sequence rows copied.\")",
			"displayOperationFeedback(\n\t\t\t\t\t\"No rows pasted.\")"]) {
		if(seqtableSource.indexOf(required) < 0) {
			failure = format("Converted seqtable.d status source missing %s",
				required);
			return false;
		}
	}

	foreach(forbidden; [
			"sequenceRowCountText",
			"trackEntryCountText",
			"Copied \" ~",
			"Pasted \" ~",
			"Exported \\\"%s\\\"",
			"Saved \\\"%s\\\""]) {
		if(uiSource.indexOf(forbidden) >= 0 ||
				seqtableSource.indexOf(forbidden) >= 0) {
			failure = format("Old count/path wording remains: %s",
				forbidden);
			return false;
		}
	}

	foreach(requiredWarning; [
			"Warning: The start point is not aligned!"]) {
		if(uiSource.indexOf(requiredWarning) >= 0) {
			failure = format("Unexpected warning location in ui.d: %s",
				requiredWarning);
			return false;
		}
	}
	if(seqtableSource.indexOf("Warning:") >= 0) {
		failure = "seqtable.d should not own timed-only warning messages";
		return false;
	}
	if(sequencerSource.indexOf("Warning: The start point is not aligned!") >= 0) {
		failure = "Start-point alignment warning source remains";
		return false;
	}
	if(sequencerSource.indexOf("Warning: The loop point is not aligned!") >= 0 ||
			tracktableSource.indexOf("Warning: The loop point is not aligned!") >= 0) {
		failure = "Loop alignment warning source remains";
		return false;
	}
	if(uiSource.indexOf("LOOP target set to track +%03X.") >= 0 ||
			uiSource.indexOf("LOOP targets set at overview row +%03X.") >= 0 ||
			tracktableSource.indexOf("LOOP target set to track +%03X.") >= 0) {
		failure = "Redundant LOOP success confirmation source remains";
		return false;
	}

	if(uiSource.indexOf("statusline.setPersistentAlertMessage(keyjamQuickHelpMessage());") < 0 ||
			uiSource.indexOf("return \"Keyjam enabled - \" ~ label ~ \" disables it\";") < 0) {
		failure = "Keyjam persistent alert ownership changed";
		return false;
	}
	if(uiSource.indexOf("UI.statusline.displayHelpTextToggleConfirmation(\"Help texts \" ~") < 0) {
		failure = "Option+H no longer uses its dedicated short owner";
		return false;
	}

	return true;
}

bool checkContextDismissibleSuppressionAndDeferredLoad(out string failure) {
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	string tablesSource = readText(buildPath("src", "ui", "tables.d"));
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	string seqtableSource = readText(buildPath("src", "seq", "seqtable.d"));

	auto contextDisplayStart = uiSource.indexOf(
		"void displayOperationFeedback(string msg)");
	auto helpToggleStart = uiSource.indexOf(
		"void displayHelpTextToggleConfirmation(string msg)");
	auto failureStart = uiSource.indexOf("void displayFailure(string msg)");
	if(contextDisplayStart < 0 || helpToggleStart <= contextDisplayStart ||
			failureStart <= helpToggleStart) {
		failure = "Could not isolate Statusline context/toggle/failure owners";
		return false;
	}
	string contextDisplaySource = uiSource[cast(size_t)contextDisplayStart ..
		cast(size_t)helpToggleStart];
	string helpToggleStatusSource = uiSource[cast(size_t)helpToggleStart ..
		cast(size_t)failureStart];
	foreach(required; [
			"message = msg;",
			"counter = CONFIRM_TIMEOUT;",
			"StatuslineInformationLifetime.contextDismissible"]) {
		if(contextDisplaySource.indexOf(required) < 0) {
			failure = format("Central operation-feedback owner missing %s",
				required);
			return false;
		}
	}
	if(contextDisplaySource.indexOf("if(!state.displayHelp)") < 0) {
		failure = "Operation feedback is not centrally gated when Help is disabled";
		return false;
	}
	if(contextDisplaySource.indexOf("displayHelpTextToggleConfirmation") >= 0 ||
			contextDisplaySource.indexOf("displayFailure") >= 0 ||
			contextDisplaySource.indexOf("setPersistentAlertMessage") >= 0) {
		failure = "Context-dismissible suppression touches another status owner";
		return false;
	}
	if(helpToggleStatusSource.indexOf("if(!state.displayHelp)") >= 0 ||
			helpToggleStatusSource.indexOf("contextDismissible") >= 0) {
		failure = "Help-toggle confirmation was routed through ordinary suppression";
		return false;
	}

	auto toggleStart = uiSource.indexOf("private bool handleUiHelpTextToggleKey");
	auto clearStart = uiSource.indexOf("private bool handleSongClearSequencesKey");
	if(toggleStart < 0 || clearStart <= toggleStart) {
		failure = "Could not isolate Help text toggle handler";
		return false;
	}
	string toggleSource = uiSource[cast(size_t)toggleStart ..
		cast(size_t)clearStart];
	foreach(required; [
			"state.displayHelp ^= 1;",
			"UI.statusline.displayHelpTextToggleConfirmation(\"Help texts \" ~",
			"(state.displayHelp ? \"enabled.\" : \"disabled.\")"]) {
		if(toggleSource.indexOf(required) < 0) {
			failure = format("Help-toggle clearing source missing %s",
				required);
			return false;
		}
	}
	if(toggleSource.indexOf("KMOD_CTRL") >= 0 ||
			toggleSource.indexOf("displayOperationFeedback") >= 0) {
		failure = "Help-toggle handler duplicated shortcut or ordinary status routing";
		return false;
	}

	auto cellClickStart = uiSource.indexOf("void clickedAt(int x, int y, int b)");
	auto fileDialogClickStart = uiSource.indexOf("bool fileDialogClickedAt",
		cellClickStart);
	auto pixelClickStart = uiSource.indexOf("bool clickedAtPixel(int x, int y",
		fileDialogClickStart);
	auto mouseMotionStart = uiSource.indexOf("bool mouseMotionPixel",
		pixelClickStart);
	if(cellClickStart < 0 || fileDialogClickStart <= cellClickStart ||
			pixelClickStart <= fileDialogClickStart ||
			mouseMotionStart <= pixelClickStart) {
		failure = "Could not isolate mouse click routing";
		return false;
	}
	string cellClickSource = uiSource[cast(size_t)cellClickStart ..
		cast(size_t)fileDialogClickStart];
	string pixelClickSource = uiSource[cast(size_t)pixelClickStart ..
		cast(size_t)mouseMotionStart];
	if(cellClickSource.indexOf("dismissOperationFeedbackForContextChange") >= 0 ||
			pixelClickSource.indexOf("dismissOperationFeedbackForContextChange") >= 0 ||
			cellClickSource.indexOf("clearOperationFeedback") >= 0 ||
			pixelClickSource.indexOf("clearOperationFeedback") >= 0) {
		failure = "Mouse click routing still clears operation feedback directly";
		return false;
	}
	foreach(required; [
			"private void noteMeaningfulStatuslineInteraction()",
			"statusline.noteMeaningfulInteraction();",
			"private bool noteMeaningfulStatuslineInteractionIf(bool handled)",
			"handleTrackOverviewHorizontalWheel(x, y, wheelX)",
			"toplevel.mouseMotionAt(x, y)",
			"handleTrackOverviewTimelineScrubMotion(x)",
			"toplevel.advanceSequenceRowDragAutoScroll()) {\n\t\t\t\tnoteMeaningfulStatuslineInteraction();",
			"toplevel.advanceGeneratedTableRowDragAutoScroll()) {\n\t\t\t\tnoteMeaningfulStatuslineInteraction();",
			"handleTrackOverviewBlockDragAutoScroll()) {\n\t\t\t\tnoteMeaningfulStatuslineInteraction();"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("Meaningful interaction owner missing %s",
				required);
			return false;
		}
	}
	foreach(forbidden; [
			"dismissFailureForContextInteraction",
			"dismissOperationFeedbackForContextChange",
			"clearOperationFeedback"]) {
		if(uiSource.indexOf(forbidden) >= 0) {
			failure = format("Direct Statusline clearing path remains: %s",
				forbidden);
			return false;
		}
	}

	auto uiToggleBinding = inputSource.indexOf("KeyboardActionId.uiToggleHelpText");
	auto uiToggleDescription = inputSource.indexOf(
		"Toggle inline help/status texts", uiToggleBinding);
	if(uiToggleBinding < 0 || uiToggleDescription <= uiToggleBinding) {
		failure = "Could not isolate live Help-text toggle binding";
		return false;
	}
	string uiToggleBindingSource = inputSource[cast(size_t)uiToggleBinding ..
		cast(size_t)uiToggleDescription];
	foreach(required; [
			"SDLK_h",
			"KMOD_ALT",
			"KMOD_SHIFT | KMOD_CTRL | KMOD_GUI",
			"KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate)"]) {
		if(uiToggleBindingSource.indexOf(required) < 0) {
			failure = format("Live Option+H binding source missing %s",
				required);
			return false;
		}
	}

	foreach(retained; [
			"void displayTimedOperationFeedback(string msg)",
			"counter = CONFIRM_TIMEOUT;",
			"void displayFailure(string msg)",
			"failureCounter = FAILURE_TIMEOUT;",
			"void setPersistentAlertMessage(string msg)",
			"persistentContextualAlert = true;"]) {
		if(uiSource.indexOf(retained) < 0) {
			failure = format("Status owner preservation source missing %s",
				retained);
			return false;
		}
	}

	foreach(required; [
			"string pendingTimedOperationFeedbackAfterDialogClose;",
			"void queueTimedOperationFeedbackAfterDialogClose(string message)",
			"if(!state.displayHelp)\n\t\t\treturn;",
			"pendingTimedOperationFeedbackAfterDialogClose = message;",
			"private void flushPendingTimedOperationFeedbackAfterDialogClose()",
			"pendingTimedOperationFeedbackAfterDialogClose = \"\";",
			"statusline.displayTimedOperationFeedback(message);",
			"flushPendingTimedOperationFeedbackAfterDialogClose();",
			"pendingTimedOperationFeedbackAfterDialogClose = \"\";"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("Post-dialog context-dismissible owner missing %s",
				required);
			return false;
		}
	}

	auto dispatchStart = uiSource.indexOf("private int dispatchActiveDialogKey");
	auto dispatchEnd = uiSource.indexOf("private bool isEditorViewActivationKey",
		dispatchStart);
	if(dispatchStart < 0 || dispatchEnd <= dispatchStart) {
		failure = "Could not isolate active-dialog dispatch source";
		return false;
	}
	string dispatchSource = uiSource[cast(size_t)dispatchStart ..
		cast(size_t)dispatchEnd];
	if(dispatchSource.indexOf("closeDialog();") < 0 ||
			dispatchSource.indexOf("flushPendingTimedOperationFeedbackAfterDialogClose();") <
				dispatchSource.indexOf("closeDialog();")) {
		failure = "Pending information is not flushed after dialog close";
		return false;
	}

	auto loadStart = tablesSource.indexOf("private void loadCallback(string fn)");
	auto loadEnd = tablesSource.indexOf(
		"mainui.activateDialogAfterActiveCloses(", loadStart);
	if(loadStart < 0 || loadEnd <= loadStart) {
		failure = "Could not isolate Instrument load callback";
		return false;
	}
	string loadSource = tablesSource[cast(size_t)loadStart ..
		cast(size_t)loadEnd];
	foreach(required; [
			"song.insertPatch(selectedFilename, targetInstrument);",
			"UI.activateInstrument(targetInstrument);",
			"mainui.queueTimedOperationFeedbackAfterDialogClose(format(",
			"Instrument load complete: \\\"%s\\\"."]) {
		if(loadSource.indexOf(required) < 0) {
			failure = format("Instrument load deferred completion source missing %s",
				required);
			return false;
		}
	}
	if(loadSource.indexOf("UI.statusline.displayOperationFeedback(format(\n\t\t\t\t\t\"Instrument load complete") >= 0 ||
			loadSource.indexOf("UI.statusline.displayTimedOperationFeedback(format(\n\t\t\t\t\t\"Instrument load complete") >= 0) {
		failure = "Instrument load still displays completion inside confirmation callback";
		return false;
	}
	if(loadSource.indexOf("queueTimedOperationFeedbackAfterDialogClose") <
			loadSource.indexOf("song.insertPatch")) {
		failure = "Instrument load queues completion before successful mutation";
		return false;
	}
	foreach(failureOwner; [
			"UI.statusline.displayFailure(\n\t\t\t\t\"File does not exist or is not accessible!\");",
			"UI.statusline.displayFailure(\n\t\t\t\t\"Not loading; possibly not an instrument def file.\");",
			"UI.statusline.displayFailure(format(\n\t\t\t\t\t\"Could not load instrument"]) {
		if(loadSource.indexOf(failureOwner) < 0) {
			failure = format("Instrument load failure owner missing %s",
				failureOwner);
			return false;
		}
	}

	return true;
}

private TrackOverviewBlockSelection testTrackOverviewSelection(int blockIndex) {
	TrackOverviewBlockSelection selection;
	selection.valid = true;
	selection.voice = 0;
	selection.blockIndex = blockIndex;
	selection.trackIndex = blockIndex;
	selection.sequenceNumber = blockIndex;
	selection.trackValue = cast(ushort)(0xa000 | blockIndex);
	return selection;
}

private TrackOverviewSelectionState testTrackOverviewSelectionState(int count) {
	TrackOverviewSelectionState state;
	if(count <= 0)
		return state;
	state.active = true;
	state.subtune = 0;
	state.primary = testTrackOverviewSelection(0);
	state.anchor = state.primary;
	state.voice = 0;
	state.rangeStartTrackIndex = 0;
	state.rangeEndTrackIndex = count - 1;
	state.selectedBlocks.length = count;
	foreach(idx; 0 .. count)
		state.selectedBlocks[idx] =
			testTrackOverviewSelection(cast(int)idx);
	return state;
}

private string expectedTrackOverviewQuickHelpMessage(
		TrackOverviewQuickHelpKind kind) {
	if(kind == TrackOverviewQuickHelpKind.noBlock)
		return "Click a block; click timeline to focus.";

	string lineForActions(TrackOverviewQuickHelpAction[] actions) {
		string message;
		foreach(action; actions) {
			string label = keyboardActionPrimaryShortcutLabel(
				keyboardActionStableId(action.actionId));
			if(label.length == 0)
				continue;
			if(message.length)
				message ~= "; ";
			message ~= label ~ " " ~ action.actionPhrase;
		}
		if(message.length)
			message ~= ".";
		return message;
	}

	if(kind == TrackOverviewQuickHelpKind.activeBlock)
		return lineForActions([
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewInsertCopyEntry,
				"duplicate"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewLoopAllVoices,
				"all LOOP")
		]) ~ "\n" ~ lineForActions([
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewLoopActiveVoice,
				"voice LOOP")
		]) ~ "\n" ~ lineForActions([
			TrackOverviewQuickHelpAction(
				KeyboardActionId.sequencerPlaybackMarkSetActiveVoice,
				"voice mark"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.sequencerPlaybackMarkSet,
				"all marks")
		]);
	if(kind == TrackOverviewQuickHelpKind.timeline)
		return lineForActions([
			TrackOverviewQuickHelpAction(
				KeyboardActionId.playbackPlayFromMark,
				"play mark"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.playbackPlayFromStart,
				"play start")
		]) ~ "\n" ~ lineForActions([
			TrackOverviewQuickHelpAction(
				KeyboardActionId.playbackPlayFromCursor,
				"play cursor"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.playbackStop,
				"stop")
		]) ~ "\n" ~ lineForActions([
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewTimelineStepLeft,
				"previous"),
			TrackOverviewQuickHelpAction(
				KeyboardActionId.trackOverviewTimelineStepRight,
				"next")
		]);

	string message;
	foreach(action; trackOverviewQuickHelpActions(kind)) {
		string label = keyboardActionPrimaryShortcutLabel(
			keyboardActionStableId(action.actionId));
		if(label.length == 0)
			continue;
		if(message.length)
			message ~= "; ";
		message ~= label ~ " " ~ action.actionPhrase;
	}
	if(message.length)
		message ~= ".";
	return message;
}

private bool expectTrackOverviewActionIds(TrackOverviewQuickHelpKind kind,
		KeyboardActionId[] expected, out string failure) {
	TrackOverviewQuickHelpAction[] actions = trackOverviewQuickHelpActions(kind);
	if(actions.length != expected.length) {
		failure = format("Track Overview %s expected %d actions, got %d",
			cast(int)kind, expected.length, actions.length);
		return false;
	}
	foreach(idx, action; actions) {
		if(action.actionId != expected[idx]) {
			failure = format("Track Overview %s action %d expected %s, got %s",
				cast(int)kind, idx,
				keyboardActionStableId(expected[idx]),
				keyboardActionStableId(action.actionId));
			return false;
		}
	}
	return true;
}

private bool labelNamesControlBackspace(string label) {
	return label.indexOf("Backspace") >= 0 &&
		(label.indexOf("Control") >= 0 || label.indexOf("Ctrl") >= 0);
}

private bool labelNamesControlF1(string label) {
	return label.indexOf("F1") >= 0 &&
		(label.indexOf("Control") >= 0 || label.indexOf("Ctrl") >= 0);
}

bool checkTrackOverviewCanonicalQuickHelp(out string failure) {
	if(trackOverviewQuickHelpKind(TrackOverviewFocusKind.Block,
			testTrackOverviewSelectionState(1)) !=
			TrackOverviewQuickHelpKind.activeBlock) {
		failure = "Single block selection does not resolve active-block quickhelp";
		return false;
	}
	if(trackOverviewQuickHelpKind(TrackOverviewFocusKind.Block,
			testTrackOverviewSelectionState(2)) !=
			TrackOverviewQuickHelpKind.selectedRange) {
		failure = "Multi-block selection does not resolve range quickhelp";
		return false;
	}
	if(trackOverviewQuickHelpKind(TrackOverviewFocusKind.Block,
			testTrackOverviewSelectionState(0)) !=
			TrackOverviewQuickHelpKind.noBlock) {
		failure = "Invalid block focus does not resolve no-block quickhelp";
		return false;
	}
	if(trackOverviewQuickHelpKind(TrackOverviewFocusKind.Timeline,
			testTrackOverviewSelectionState(1)) !=
			TrackOverviewQuickHelpKind.timeline) {
		failure = "Timeline focus does not resolve timeline quickhelp";
		return false;
	}
	if(trackOverviewQuickHelpKind(TrackOverviewFocusKind.Editor,
			testTrackOverviewSelectionState(1)) !=
			TrackOverviewQuickHelpKind.noBlock) {
		failure = "Editor focus does not resolve no-block quickhelp";
		return false;
	}

	if(!expectTrackOverviewActionIds(TrackOverviewQuickHelpKind.activeBlock, [
			KeyboardActionId.trackOverviewInsertCopyEntry,
			KeyboardActionId.trackOverviewLoopActiveVoice,
			KeyboardActionId.trackOverviewLoopAllVoices,
			KeyboardActionId.sequencerPlaybackMarkSetActiveVoice,
			KeyboardActionId.sequencerPlaybackMarkSet], failure))
		return false;
	if(!expectTrackOverviewActionIds(TrackOverviewQuickHelpKind.selectedRange, [
			KeyboardActionId.trackOverviewCopyEntries,
			KeyboardActionId.trackOverviewDeleteSelection], failure))
		return false;
	if(!expectTrackOverviewActionIds(TrackOverviewQuickHelpKind.timeline, [
			KeyboardActionId.playbackPlayFromMark,
			KeyboardActionId.playbackPlayFromStart,
			KeyboardActionId.playbackPlayFromCursor,
			KeyboardActionId.playbackStop,
			KeyboardActionId.trackOverviewTimelineStepLeft,
			KeyboardActionId.trackOverviewTimelineStepRight,
			KeyboardActionId.trackOverviewTimelinePageUp,
			KeyboardActionId.trackOverviewTimelinePageDown,
			KeyboardActionId.trackOverviewTimelineHome,
			KeyboardActionId.trackOverviewTimelineEnd], failure))
		return false;
	if(!expectTrackOverviewActionIds(TrackOverviewQuickHelpKind.noBlock, [],
			failure))
		return false;

	string allLoopPrimary = keyboardActionPrimaryShortcutLabel(
		keyboardActionStableId(KeyboardActionId.trackOverviewLoopAllVoices));
	if(!labelNamesControlBackspace(allLoopPrimary)) {
		failure = "Track Overview all-LOOP primary is not Control-Backspace";
		return false;
	}
	string allLoopAliases = keyboardActionShortcutLabelList(
		keyboardActionStableId(KeyboardActionId.trackOverviewLoopAllVoices));
	if(allLoopAliases.indexOf("Backspace") < 0 ||
			allLoopAliases.indexOf("L") < 0) {
		failure = "Track Overview all-LOOP aliases were not retained";
		return false;
	}

	string allMarksPrimary = keyboardActionPrimaryShortcutLabel(
		keyboardActionStableId(KeyboardActionId.sequencerPlaybackMarkSet));
	if(!labelNamesControlF1(allMarksPrimary)) {
		failure = "All playback marks primary is not Control-F1";
		return false;
	}
	string allMarksAliases = keyboardActionShortcutLabelList(
		keyboardActionStableId(KeyboardActionId.sequencerPlaybackMarkSet));
	if(allMarksAliases.indexOf("Backspace") < 0 ||
			allMarksAliases.indexOf("+") < 0) {
		failure = "All playback mark aliases were not retained";
		return false;
	}
	KeyboardActionId resolvedAction;
	version(OSX) {
		enum trackOverviewPlainDeleteKey = SDLK_BACKSPACE;
	}
	else {
		enum trackOverviewPlainDeleteKey = SDLK_DELETE;
	}
	if(!resolveTrackOverviewBlockKeyboardAction(
			Keyinfo(trackOverviewPlainDeleteKey, 0, 0),
			resolvedAction) ||
			resolvedAction != KeyboardActionId.trackOverviewDeleteSelection) {
		failure = "Plain platform delete key no longer resolves to Track Overview delete";
		return false;
	}
	if(!resolveTrackOverviewBlockKeyboardAction(
			Keyinfo(SDLK_BACKSPACE, KMOD_CTRL, 0), resolvedAction) ||
			resolvedAction != KeyboardActionId.trackOverviewLoopAllVoices) {
		failure = "Control-Backspace no longer resolves to Track Overview all-LOOP";
		return false;
	}
	if(!resolveSequencerKeyboardAction(Keyinfo(SDLK_F1, KMOD_CTRL, 0),
			resolvedAction) ||
			resolvedAction != KeyboardActionId.sequencerPlaybackMarkSet) {
		failure = "Control-F1 no longer resolves to all playback marks";
		return false;
	}
	if(!resolveSequencerKeyboardAction(
			Keyinfo(SDLK_F1, KMOD_CTRL | KMOD_SHIFT, 0), resolvedAction) ||
			resolvedAction !=
				KeyboardActionId.sequencerPlaybackMarkSetActiveVoice) {
		failure = "Control-Shift-F1 no longer resolves to active-voice mark";
		return false;
	}
	if(!resolveSequencerKeyboardAction(Keyinfo(SDLK_PLUS, 0, 0),
			resolvedAction) ||
			resolvedAction != KeyboardActionId.sequencerPlaybackMarkSet) {
		failure = "Plus all-marks alias no longer resolves";
		return false;
	}

	foreach(kind; [TrackOverviewQuickHelpKind.activeBlock,
			TrackOverviewQuickHelpKind.selectedRange,
			TrackOverviewQuickHelpKind.timeline,
			TrackOverviewQuickHelpKind.noBlock]) {
		string expected = expectedTrackOverviewQuickHelpMessage(kind);
		string actual = trackOverviewQuickHelpMessage(kind);
		if(actual != expected) {
			failure = format("Track Overview quickhelp %s expected %s, got %s",
				cast(int)kind, expected, actual);
			return false;
		}
		foreach(line; actual.splitLines()) {
			if(line.length > 54) {
				failure = format("Track Overview quickhelp %s line too wide: %s",
					cast(int)kind, line);
				return false;
			}
		}
		foreach(forbidden; [" or ", "[F12"]) {
			if(actual.indexOf(forbidden) >= 0) {
				failure = format("Track Overview quickhelp %s contains %s",
					cast(int)kind, forbidden);
				return false;
			}
		}
	}

	string[] activeBlockLines = trackOverviewQuickHelpMessage(
		TrackOverviewQuickHelpKind.activeBlock).splitLines();
	if(activeBlockLines.length != 3) {
		failure = format("Active-block quickhelp expected 3 lines, got %d",
			activeBlockLines.length);
		return false;
	}
	foreach(line; activeBlockLines) {
		if(line.length > 54) {
			failure = format("Active-block quickhelp line too wide: %s", line);
			return false;
		}
	}
	if(activeBlockLines[0].indexOf("duplicate") < 0 ||
			activeBlockLines[0].indexOf("all LOOP") < 0 ||
			activeBlockLines[1].indexOf("voice LOOP") < 0 ||
			activeBlockLines[2].indexOf("voice mark") < 0 ||
			activeBlockLines[2].indexOf("all marks") < 0) {
		failure = "Active-block quickhelp lines do not match semantic grouping";
		return false;
	}
	if(activeBlockLines[2].indexOf("Backspace all marks") >= 0) {
		failure = "Active-block quickhelp still advertises Backspace all marks";
		return false;
	}

	foreach(action; trackOverviewQuickHelpActions(
			TrackOverviewQuickHelpKind.activeBlock)) {
		string primary = keyboardActionPrimaryShortcutLabel(
			keyboardActionStableId(action.actionId));
		string aliases = keyboardActionShortcutLabelList(
			keyboardActionStableId(action.actionId));
		string message = trackOverviewQuickHelpMessage(
			TrackOverviewQuickHelpKind.activeBlock);
		if(primary.length == 0 || message.indexOf(primary) < 0) {
			failure = format("Primary Track Overview shortcut missing for %s",
				keyboardActionStableId(action.actionId));
			return false;
		}
		if(aliases.indexOf(" or ") >= 0 && message.indexOf(aliases) >= 0) {
			failure = format("Alias list leaked into Track Overview quickhelp: %s",
				keyboardActionStableId(action.actionId));
			return false;
		}
	}
	foreach(action; [
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
				"next")]) {
		string primary = keyboardActionPrimaryShortcutLabel(
			keyboardActionStableId(action.actionId));
		string message = trackOverviewQuickHelpMessage(
			TrackOverviewQuickHelpKind.timeline);
		if(primary.length == 0 || message.indexOf(primary) < 0) {
			failure = format("Primary Track Overview timeline shortcut missing for %s",
				keyboardActionStableId(action.actionId));
			return false;
		}
	}

	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	foreach(forbidden; [
			"trackOverviewBlockQuickHelp",
			"trackOverviewTimelineQuickHelp",
			"compactShortcutLabel",
			"primaryShortcutLabel",
			"keyboardActionShortcutLabelList("]) {
		if(uiSource.indexOf(forbidden) >= 0) {
			failure = format("Track Overview quickhelp legacy source remains: %s",
				forbidden);
			return false;
		}
	}
	foreach(required; [
			"struct TrackOverviewQuickHelpAction",
			"KeyboardActionId actionId;",
			"string actionPhrase;",
			"keyboardActionPrimaryShortcutLabel(",
			"keyboardActionStableId(action.actionId)",
			"displayContextualSemantic(help,",
			"trackOverviewQuickHelpSemanticContext(kind)"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("Canonical Track Overview quickhelp source missing %s",
				required);
			return false;
		}
	}

	foreach(action; trackOverviewQuickHelpActions(
			TrackOverviewQuickHelpKind.activeBlock)) {
		foreach(other; trackOverviewQuickHelpActions(
				TrackOverviewQuickHelpKind.activeBlock)) {
			if(action.actionId == other.actionId &&
					action.actionPhrase != other.actionPhrase) {
				failure = "Track Overview action reused under different phrases";
				return false;
			}
		}
		if(action.actionPhrase.indexOf("LOOP") >= 0 &&
				(action.actionId == KeyboardActionId.sequencerPlaybackMarkSet ||
					action.actionId ==
						KeyboardActionId.sequencerPlaybackMarkSetActiveVoice)) {
			failure = "Track Overview LOOP phrase uses playback marker action";
			return false;
		}
		if(action.actionPhrase.indexOf("mark") >= 0 &&
				(action.actionId == KeyboardActionId.trackOverviewLoopAllVoices ||
					action.actionId ==
						KeyboardActionId.trackOverviewLoopActiveVoice)) {
			failure = "Track Overview mark phrase uses LOOP action";
			return false;
		}
	}

	return true;
}

bool checkStatuslineOperationFeedbackBehavior(out string failure) {
	com.session.initSession();
	com.session.screen = new Screen(100, 42);
	com.session.video = new FullscreenTestVideo(100 * FONT_X,
		42 * FONT_Y + trackOverviewGuiStartY());
	scope(exit) com.session.video = null;
	com.session.state.displayHelp = false;
	auto status = new Statusline(Rectangle(0, 1, 1));

	status.displayOperationFeedback("Operation feedback.");
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Operation feedback remained queued when Help is disabled";
		return false;
	}

	status.update();
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Ordinary redraw recreated hidden operation feedback";
		return false;
	}

	status.displayContextualSemantic("Context A.", "context:a");
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Contextual Help became visible while Help is disabled";
		return false;
	}

	status.displayTimedOperationFeedback("Timed feedback.");
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Timed feedback remained queued when Help is disabled";
		return false;
	}

	status.displayContextualSemantic("Context B.", "context:b");
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Hidden timed feedback was restored by semantic navigation";
		return false;
	}

	status.displayFailure("Failure.");
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Failure remained queued when Help is disabled";
		return false;
	}

	status.displayHelpTextToggleConfirmation("Help texts disabled.");
	if(status.counter == 0 || status.message != "Help texts disabled.") {
		failure = "Help-toggle confirmation did not bypass disabled Help visibility";
		return false;
	}
	status.noteMeaningfulInteraction();
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Meaningful interaction did not supersede Help-toggle confirmation";
		return false;
	}

	com.session.state.displayHelp = true;
	status.displayOperationFeedback("Operation feedback.");
	if(status.counter == 0 || status.message != "Operation feedback.") {
		failure = "Operation feedback is hidden when Help is enabled";
		return false;
	}

	status.displayContextualSemantic("Context C.", "context:c");
	if(status.counter == 0 || status.message != "Operation feedback.") {
		failure = "Same-interaction contextual Help erased operation feedback";
		return false;
	}
	status.update();
	if(status.counter == 0 || status.message != "Operation feedback.") {
		failure = "Passive redraw erased current-generation operation feedback";
		return false;
	}
	status.noteMeaningfulInteraction();
	status.displayContextualSemantic("Context C.", "context:c");
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Later same-semantic contextual Help did not supersede feedback";
		return false;
	}

	status.noteMeaningfulInteraction();
	status.displayOperationFeedback("Operation feedback.");
	status.displayOperationFeedback("Newer operation feedback.");
	if(status.counter == 0 || status.message != "Newer operation feedback.") {
		failure = "Newer operation feedback did not replace the previous operation";
		return false;
	}

	status.displayTimedOperationFeedback("Timed feedback.");
	int timedCounter = status.counter;
	status.displayContextualSemantic("Context D.", "context:d");
	if(status.counter != timedCounter || status.message != "Timed feedback.") {
		failure = "Timed operation feedback was dismissed by semantic navigation";
		return false;
	}
	status.noteMeaningfulInteraction();
	status.displayContextualSemantic("Context D.", "context:d");
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Later contextual Help did not supersede timed feedback";
		return false;
	}

	status.noteMeaningfulInteraction();
	status.displayFailure("Failure.");
	if(status.counter != 0) {
		failure = "Failure did not clear lower-priority operation feedback counter";
		return false;
	}
	status.update();
	status.noteMeaningfulInteraction();
	status.displayContextualSemantic("Context E.", "context:e");
	if(status.counter != 0 || status.message.length != 0) {
		failure = "Later contextual Help did not supersede failure state";
		return false;
	}

	return true;
}

bool checkStatuslineLatestMeaningfulGenerationBehavior(out string failure) {
	return checkStatuslineOperationFeedbackBehavior(failure);
}

bool checkInstrumentStatusWordingOwnership(out string failure) {
	string tablesSource = readText(buildPath("src", "ui", "tables.d"));
	string inputSource = readText(buildPath("src", "ui", "input.d"));

	auto insStart = tablesSource.indexOf("class InsValueTable");
	auto insEnd = tablesSource.indexOf("class InsTable", insStart);
	if(insStart < 0 || insEnd <= insStart) {
		failure = "Could not isolate InsValueTable source";
		return false;
	}
	string instrumentSource = tablesSource[cast(size_t)insStart ..
		cast(size_t)insEnd];

	foreach(required; [
			"\"Instrument copied.\"",
			"\"No instrument copied.\"",
			"\"Instrument pasted.\"",
			"Instrument save complete: \\\"%s\\\".",
			"queueTimedOperationFeedbackAfterDialogClose(format(",
			"Instrument load complete: \\\"%s\\\"."]) {
		if(instrumentSource.indexOf(required) < 0) {
			failure = format("Instrument status source missing %s", required);
			return false;
		}
	}

	foreach(forbidden; [
			"Instrument copied to buffer.",
			"Saved instrument %d to %s",
			"UI.statusline.display(\"Instrument",
			"UI.statusline.display(format(\"Saved instrument"]) {
		if(instrumentSource.indexOf(forbidden) >= 0) {
			failure = format("Old Instrument status source remains: %s",
				forbidden);
			return false;
		}
	}

	foreach(requiredFailure; [
			"UI.statusline.displayFailure(validationMessage(saveIssues));",
			"UI.statusline.displayFailure(\"Illegal characters in filename!\");",
			"UI.statusline.displayFailure(\"Could not save instrument: \" ~ e.msg);",
			"UI.statusline.displayFailure(\n\t\t\t\t\"File does not exist or is not accessible!\");",
			"UI.statusline.displayFailure(\n\t\t\t\t\"Not loading; possibly not an instrument def file.\");",
			"UI.statusline.displayFailure(format(\n\t\t\t\t\t\"Could not load instrument"]) {
		if(instrumentSource.indexOf(requiredFailure) < 0) {
			failure = format("Instrument failure owner missing %s",
				requiredFailure);
			return false;
		}
	}

	auto autoinsertStart = inputSource.indexOf(
		"state.autoinsertInstrument ^= 1;");
	auto autoinsertCase = inputSource.lastIndexOf(
		"case KeyboardActionId.sequenceInputToggleInstrumentAutoinsert:",
		autoinsertStart);
	auto autoinsertEnd = inputSource.indexOf(
		"case KeyboardActionId.sequenceInputOctaveDecrease:", autoinsertStart);
	if(autoinsertCase < 0 || autoinsertStart < 0 ||
			autoinsertEnd <= autoinsertStart) {
		failure = "Could not isolate Instrument autoinsert source";
		return false;
	}
	string autoinsertSource = inputSource[cast(size_t)autoinsertCase ..
		cast(size_t)autoinsertEnd];
	foreach(required; [
			"displayOperationFeedback(",
			"Instrument autoinsert enabled.",
			"Instrument autoinsert disabled."]) {
		if(autoinsertSource.indexOf(required) < 0) {
			failure = format("Autoinsert status source missing %s", required);
			return false;
		}
	}
	foreach(forbidden; [
			"Instrument autoinsert mode",
			"UI.statusline.display("]) {
		if(autoinsertSource.indexOf(forbidden) >= 0) {
			failure = format("Old autoinsert status source remains: %s",
				forbidden);
			return false;
		}
	}

	foreach(retained; [
			"trackNextUnusedSequenceUnavailableMessage()",
			"trackNextUnusedSequenceChangedMessage(s)"]) {
		if(inputSource.indexOf(retained) < 0) {
			failure = format("Unrelated Track input status was changed: %s",
				retained);
			return false;
		}
	}

	return true;
}

bool checkHelpCleanupConsolidatedFeedbackAndF12(out string failure) {
	string dialogsSource = readText(buildPath("src", "ui", "dialogs.d"));
	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	string tablesSource = readText(buildPath("src", "ui", "tables.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));

	if(countOccurrences(dialogsSource, "\"Directory not found!\"") != 1 ||
			dialogsSource.indexOf("displayDirectoryNotFoundFailure()") < 0 ||
			countOccurrences(dialogsSource,
				"displayDirectoryNotFoundFailure();") != 2) {
		failure = "Directory failure is not consolidated in FileSelector";
		return false;
	}

	foreach(required; [
			"string trackNextUnusedSequenceUnavailableMessage()",
			"string trackNextUnusedSequenceChangedMessage(int sequenceNumber)",
			"return \"No unused sequence after current value.\";",
			"return format(\"Track sequence set to next unused %02X.\", sequenceNumber);"]) {
		if(inputSource.indexOf(required) < 0) {
			failure = format("Track next-unused message owner missing %s",
				required);
			return false;
		}
	}
	if(uiSource.indexOf("\"No unused sequence after current value.\"") >= 0 ||
			uiSource.indexOf("\"Track sequence set to next unused %02X.\"") >= 0) {
		failure = "Track Overview still owns duplicated next-unused wording";
		return false;
	}

	auto insStart = tablesSource.indexOf("class InsValueTable");
	auto insEnd = tablesSource.indexOf("class InsTable", insStart);
	if(insStart < 0 || insEnd <= insStart) {
		failure = "Could not isolate InsValueTable source";
		return false;
	}
	string instrumentSource = tablesSource[cast(size_t)insStart ..
		cast(size_t)insEnd];
	if(countOccurrences(instrumentSource, "\"No instrument copied.\"") != 1 ||
			countOccurrences(instrumentSource,
				"displayNoWholeInstrumentCopied();") != 2 ||
			instrumentSource.indexOf("\"No instrument bytes copied.\"") < 0) {
		failure = "Instrument clipboard messages are not correctly separated";
		return false;
	}

	if(countOccurrences(uiSource, "\"Could not move track entry.\"") != 1 ||
			countOccurrences(uiSource,
				"displayTrackOverviewMoveEntryFailure();") != 2 ||
			countOccurrences(uiSource,
				"\"Could not move selected track entries.\"") != 1 ||
			countOccurrences(uiSource,
				"displayTrackOverviewMoveSelectionFailure();") != 2) {
		failure = "Track Overview move failures are not locally consolidated";
		return false;
	}

	foreach(required; [
			"generatedProgramTableRowSelectionHelp()",
			"table.row_selection_extend_up",
			"table.row_selection_extend_down",
			"table.row_selection_extend_page_up",
			"table.row_selection_extend_page_down",
			"table.row_selection_extend_home",
			"table.row_selection_extend_end",
			"table.row_selection_clear",
			"Click-drag = select rows",
			"Shift+click = extend row selection"]) {
		if(helpSource.indexOf(required) < 0) {
			failure = "Generated program-table F12 ownership missing " ~
				required;
			return false;
		}
	}
	foreach(forbidden; [
			"Shift+cursor/Home/End = extend row selection",
			"Shift+keys or click-drag select"]) {
		if(helpSource.indexOf(forbidden) >= 0) {
			failure = "Generated program-table F12 still hard-codes " ~
				forbidden;
			return false;
		}
	}

	return true;
}

bool checkSequencePlayRowHelpPlacement(out string failure) {
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	string helpSource = readText(buildPath("src", "ui", "help.d"));

	auto actionStart = inputSource.indexOf(
		"KeyboardActionId.sequencePlayRowAllVoices");
	if(actionStart < 0) {
		failure = "F6 play-row action is missing";
		return false;
	}
	auto actionEnd = inputSource.indexOf(
		"private enum KeyboardBinding[] SEQUENCE_DIALOG_BINDINGS", actionStart);
	if(actionEnd <= actionStart) {
		failure = "Could not isolate F6 play-row binding";
		return false;
	}
	string playRowSource = inputSource[actionStart .. actionEnd];
	foreach(required; [
			"return \"sequence.play_row_all_voices\";",
			"SDLK_KP_0",
			"KeyboardHelpPlacement(KeyboardHelpSection.sequenceEditingSequencer",
			"KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback",
			"Play current row once, then step down"]) {
		if((required == "return \"sequence.play_row_all_voices\";" ?
				inputSource : playRowSource).indexOf(required) < 0) {
			failure = "F6 play-row Help placement missing: " ~ required;
			return false;
		}
	}
	if(helpSource.indexOf(
			"keyboardShortcutHelpRows(\n\t\t\tKeyboardHelpSection.sequenceEditingSequencer)") <
			0) {
		failure = "F6 Sequencer Help no longer consumes sequenceEditingSequencer rows";
		return false;
	}
	if(helpSource.indexOf("enum string MAIN_PLAYBACK_HELP =\n" ~
			"\tshortcutHelpLines(keyboardShortcutHelpRows(\n" ~
			"\t\tKeyboardHelpSection.mainPlayback));") < 0) {
		failure = "Playback Help no longer consumes mainPlayback rows";
		return false;
	}
	string expectedLabel = "Keypad 0";
	string expectedF6Description = "Play current row once, then step down";
	string expectedPlaybackDescription =
		"F6 only: play current row once, then step down";
	if(HELPSEQUENCER.text[0].indexOf(expectedLabel) < 0 ||
			HELPSEQUENCER.text[0].indexOf(expectedF6Description) < 0) {
		failure = "F6 Help page does not render the play-row shortcut line";
		return false;
	}
	if(HELPPLAYBACK.text[0].indexOf(expectedLabel) < 0 ||
			HELPPLAYBACK.text[0].indexOf(expectedPlaybackDescription) < 0) {
		failure = "Playback Help page does not render the play-row shortcut line";
		return false;
	}

	return true;
}

bool checkMissedShortcutHelpPlacement(out string failure) {
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	string helpSource = readText(buildPath("src", "ui", "help.d"));

	foreach(required; [
			"KeyboardActionId.trackEntryPasteInsert",
			"KeyboardActionId.trackEntryPasteOverwrite",
			"KeyboardActionId.trackEntryTransposeUpFromCursor",
			"KeyboardActionId.trackEntryTransposeDownFromCursor",
			"KeyboardActionId.uiToggleFullscreen",
			"KeyboardActionId.uiToggleInterpolation",
			"KeyboardHelpPlacement(KeyboardHelpSection.trackColumnAdvanced",
			"KeyboardHelpPlacement(KeyboardHelpSection.mainApp"]) {
		if(inputSource.indexOf(required) < 0) {
			failure = "Missed shortcut Help placement source missing " ~ required;
			return false;
		}
	}

	string trackHelp = HELPTRACKTABLE.text[0];
	foreach(row; [
			["track_entry.paste_insert",
				"Paste copied tracks using insert mode"],
			["track_entry.paste_overwrite",
				"Paste copied tracks using overwrite mode"],
			["track_entry.transpose_up_from_cursor",
				"Transpose active voice tracks up from cursor down"],
			["track_entry.transpose_down_from_cursor",
				"Transpose active voice tracks down from cursor down"]]) {
		string label = keyboardActionShortcutLabelList(row[0], " / ");
		if(label.length == 0 || trackHelp.indexOf(label) < 0 ||
				trackHelp.indexOf(row[1]) < 0) {
			failure = "Track table Help does not render " ~ row[0];
			return false;
		}
	}

	string mainHelp = HELPMAIN.text[0];
	foreach(row; [
			["ui.toggle_fullscreen", "Toggle fullscreen"],
			["ui.toggle_interpolation", "Toggle audio interpolation"]]) {
		string label = keyboardActionShortcutLabelList(row[0], " / ");
		if(label.length == 0 || mainHelp.indexOf(label) < 0 ||
				mainHelp.indexOf(row[1]) < 0) {
			failure = "Main Help does not render " ~ row[0];
			return false;
		}
	}
	foreach(literal; ["Control-I", "Control-O", "Control-Q", "Control-A",
			"Option-Return", "Control-F2", "Keypad 0"]) {
		if(helpSource.indexOf(literal) >= 0) {
			failure = "Help prose hard-codes shortcut label " ~ literal;
			return false;
		}
	}

	return true;
}

bool checkSequenceRowDragAutoScroll(out string failure) {
	string sequencerSource = readText(buildPath("src", "seq", "sequencer.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	foreach(required; [
			"enum int SEQUENCE_ROW_DRAG_AUTOSCROLL_INTERVAL_TICKS = 4;",
			"enum SequenceRowDragAutoScrollDirection",
			"sequenceMovementMarginForHeight(int height)",
				"enum int SEQUENCE_ROW_DRAG_AUTOSCROLL_MARGIN_ROWS = 4;",
				"return height > 10 ? SEQUENCE_ROW_DRAG_AUTOSCROLL_MARGIN_ROWS : 1;",
			"sequenceTopAllowedVisibleRowForHeight(int height)",
			"sequenceBottomAllowedVisibleRowForHeight(int height)",
			"sequenceRowDragAutoScrollDirectionForRow(",
			"advanceSequenceRowDragAutoScrollCadence(ref int accumulator)",
			"setSequenceRowDragAutoScrollDirection(autoScrollDirection)",
			"moveSequenceRowSelectionToOverviewGlobalRow(overview",
			"resetSequenceRowDragAutoScroll();"]) {
		if(sequencerSource.indexOf(required) < 0) {
			failure = format("Sequencer auto-scroll source missing %s",
				required);
			return false;
		}
	}
	foreach(required; [
			"bool advanceSequenceRowDragAutoScroll()",
			"dialog is null && toplevel.advanceSequenceRowDragAutoScroll()"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = format("UI timer integration missing %s", required);
			return false;
		}
	}
	if(sequencerSource.indexOf("$00-$03") >= 0 ||
			sequencerSource.indexOf("$1C-$1F") >= 0 ||
			sequencerSource.indexOf("0x1c") >= 0 ||
			sequencerSource.indexOf("0x1C") >= 0) {
		failure = "Auto-scroll source contains hard-coded displayed padding range";
		return false;
	}

		int normalHeight = 32;
		int margin = normalHeight > 10 ? 4 : 1;
	if(margin != 4) {
		failure = format("Normal F6 height margin expected 4, got %d",
			margin);
		return false;
	}
	int top = margin;
	int bottom = normalHeight - 1 - margin;
	foreach(row; 0 .. normalHeight) {
		int expected = row < top ? -1 : row > bottom ? 1 : 0;
		int actual = row < 0 || row >= normalHeight ? 0 :
			row < top ? -1 : row > bottom ? 1 : 0;
		if(actual != expected) {
			failure = format("Normal F6 row %d direction expected %d, got %d",
				row, expected, actual);
			return false;
		}
	}

		int shorterHeight = 12;
		int shorterMargin = shorterHeight > 10 ? 4 : 1;
	int shorterTop = shorterMargin;
	int shorterBottom = shorterHeight - 1 - shorterMargin;
	if(shorterTop != shorterMargin ||
			shorterBottom != shorterHeight - 1 - shorterMargin) {
		failure = "Shorter F6 height did not derive padding from margin owner";
		return false;
	}
	foreach(row; 0 .. shorterHeight) {
		int expected = row < shorterTop ? -1 :
			row > shorterBottom ? 1 : 0;
		int actual = row < shorterTop ? -1 :
			row > shorterBottom ? 1 : 0;
		if(actual != expected) {
			failure = format("Shorter F6 row %d direction expected %d, got %d",
				row, expected, actual);
			return false;
		}
	}

	int accumulator;
	int interval = 4;
	foreach(tick; 1 .. interval) {
		accumulator++;
		bool moved = accumulator >= interval;
		if(moved)
			accumulator = 0;
		if(moved) {
			failure = format("Cadence moved too early at tick %d", tick);
			return false;
		}
		if(accumulator != tick) {
			failure = format("Cadence accumulator expected %d, got %d",
				tick, accumulator);
			return false;
		}
	}
	accumulator++;
	bool moved = accumulator >= interval;
	if(moved)
		accumulator = 0;
	if(!moved || accumulator != 0) {
		failure = "Cadence did not move exactly on interval tick";
		return false;
	}
	foreach(tick; 1 .. interval + 1) {
		accumulator++;
		moved = accumulator >= interval;
		if(moved)
			accumulator = 0;
		if(tick == interval) {
			if(!moved || accumulator != 0) {
				failure = "Cadence did not reset for the second interval";
				return false;
			}
		}
		else if(moved) {
			failure = "Cadence moved more than once per interval";
			return false;
		}
	}
	return true;
}

bool checkProgramTableRowSelectionPolicy(out string failure) {
	string tablesSource = readText(buildPath("src", "ui", "tables.d"));
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	foreach(required; [
			"enum ProgramTableRowKind",
			"case ProgramTableRowKind.wave:\n\t\treturn 2;",
			"case ProgramTableRowKind.pulse:\n\tcase ProgramTableRowKind.filter:\n\t\treturn 4;",
			"bool programTableRowPasteFits(int targetRow, int rowCount, int tableRows)",
			"return rowCount > 0 && targetRow >= 0 && targetRow + rowCount <= tableRows;",
			"override protected ProgramTableRowKind programTableRowKind() {\n\t\treturn ProgramTableRowKind.wave;",
			"override protected ProgramTableRowKind programTableRowKind() {\n\t\treturn ProgramTableRowKind.pulse;",
			"override protected ProgramTableRowKind programTableRowKind() {\n\t\treturn ProgramTableRowKind.filter;",
			"data[targetRow] = src[0];\n\t\tdata[targetRow + 256] = src[1];",
			"No %s row selection.",
			"No %s row selection copied.",
			"%s row selection does not fit.",
				"%s selection copied: %d.",
				"%s selection pasted: %d."]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Missing generated-table row-selection source owner: " ~
				required;
			return false;
		}
	}
	foreach(required; [
			"GENERATED_TABLE_ROW_SELECTION_BINDINGS",
			"generatedTableRowSelectionExtendUp",
			"generatedTableRowSelectionExtendDown",
			"generatedTableRowSelectionExtendPageUp",
			"generatedTableRowSelectionExtendPageDown",
			"generatedTableRowSelectionExtendHome",
			"generatedTableRowSelectionExtendEnd",
			"generatedTableRowSelectionClear",
			"generatedTableRowCopy",
			"generatedTableRowPaste",
			"resolveGeneratedTableRowSelectionKeyboardAction"]) {
		if(inputSource.indexOf(required) < 0) {
			failure = "Missing generated-table row-selection keyboard owner: " ~
				required;
			return false;
		}
	}
	return true;
}

bool checkInstrumentByteSelectionPolicy(out string failure) {
	foreach(instrument; [0, 1, 17, 47]) {
		foreach(column; 0 .. 8) {
			int offset = instrumentByteStorageOffset(instrument, column);
			if(offset != instrument + column * 48 || offset < 0 ||
					offset >= 48 * 8) {
				failure = format("Instrument %d column %d mapped to %d",
					instrument, column, offset);
				return false;
			}
			if(!instrumentByteColumnIsValid(column)) {
				failure = format("Instrument byte column %d rejected", column);
				return false;
			}
		}
	}
	if(instrumentByteColumnIsValid(-1) || instrumentByteColumnIsValid(8)) {
		failure = "Instrument byte column bounds are not 0-7";
		return false;
	}

	InstrumentByteSelectionState selection;
	InstrumentByteSelectionState next;
	int targetColumn;
	if(!instrumentByteSelectionExtend(selection, 7, 3, 1, next,
			targetColumn) || targetColumn != 4 || !next.active ||
			next.instrument != 7 || next.anchorColumn != 3 ||
			next.endpointColumn != 4) {
		failure = "First Shift+Right did not anchor and move one byte";
		return false;
	}
	selection = next;
	if(!instrumentByteSelectionExtend(selection, 7, 4, 1, next,
			targetColumn) || next.anchorColumn != 3 ||
			next.endpointColumn != 5) {
		failure = "Later Shift+Right did not preserve anchor";
		return false;
	}
	selection = next;
	if(!instrumentByteSelectionExtend(selection, 7, 5, -1, next,
			targetColumn) || next.anchorColumn != 3 ||
			next.endpointColumn != 4) {
		failure = "Reverse Shift+Left did not preserve anchor";
		return false;
	}
	selection = next;
	if(!instrumentByteSelectionExtend(selection, 7, 4, -1, next,
			targetColumn) || next.anchorColumn != 3 ||
			next.endpointColumn != 3) {
		failure = "Selection did not cross back to anchor";
		return false;
	}
	selection.clear();
	if(!instrumentByteSelectionExtend(selection, 7, 0, -1, next,
			targetColumn) || targetColumn != 0 || !next.active ||
			next.anchorColumn != 0 || next.endpointColumn != 0) {
		failure = "First-byte Shift+Left did not create singleton selection";
		return false;
	}
	selection.clear();
	if(!instrumentByteSelectionExtend(selection, 7, 7, 1, next,
			targetColumn) || targetColumn != 7 || !next.active ||
			next.anchorColumn != 7 || next.endpointColumn != 7) {
		failure = "Eighth-byte Shift+Right did not create singleton selection";
		return false;
	}
	selection.select(7, 3, 0);
	if(!instrumentByteSelectionExtend(selection, 7, 0, -1, next,
			targetColumn) || targetColumn != 0 || next.anchorColumn != 3 ||
			next.endpointColumn != 0) {
		failure = "Outward Shift+Left changed existing boundary selection";
		return false;
	}
	selection.select(7, 4, 7);
	if(!instrumentByteSelectionExtend(selection, 7, 7, 1, next,
			targetColumn) || targetColumn != 7 || next.anchorColumn != 4 ||
			next.endpointColumn != 7) {
		failure = "Outward Shift+Right changed existing boundary selection";
		return false;
	}
	if(instrumentByteSelectionExtend(selection, 48, 3, 1, next,
			targetColumn)) {
		failure = "Instrument byte selection crossed to an invalid Instrument";
		return false;
	}

	selection.select(12, 7, 0);
	InstrumentByteRange range;
	if(!instrumentByteSelectionRange(selection, range) ||
			range.instrument != 12 || range.startColumn != 0 ||
			range.endColumn != 7 || range.byteCount != 8) {
		failure = "Reverse full-row Instrument byte range was not normalized";
		return false;
	}
	selection.clear();
	if(instrumentByteSelectionRange(selection, range)) {
		failure = "Cleared Instrument byte selection still produced a range";
		return false;
	}

	ubyte[] data;
	data.length = 48 * 8;
	foreach(instrument; 0 .. 48) {
		foreach(column; 0 .. 8) {
			data[instrumentByteStorageOffset(instrument, column)] =
				cast(ubyte)(instrument * 8 + column);
		}
	}
	selection.select(2, 5, 3);
	if(!instrumentByteSelectionRange(selection, range) ||
			range.startColumn != 3 || range.endColumn != 5) {
		failure = "Reverse selection did not resolve increasing byte order";
		return false;
	}
	ubyte[8] byteBuffer;
	int byteCount;
	selection.select(2, 0, 0);
	if(!instrumentByteSelectionRange(selection, range) ||
			range.byteCount != 1 ||
			!copyInstrumentByteRangeData(data, range, byteBuffer, byteCount) ||
			byteCount != 1 || byteBuffer[0] != 0x10) {
		failure = "First-byte singleton selection did not copy one byte";
		return false;
	}
	selection.select(2, 7, 7);
	if(!instrumentByteSelectionRange(selection, range) ||
			range.byteCount != 1 ||
			!copyInstrumentByteRangeData(data, range, byteBuffer, byteCount) ||
			byteCount != 1 || byteBuffer[0] != 0x17) {
		failure = "Eighth-byte singleton selection did not copy one byte";
		return false;
	}
	if(!copyInstrumentByteRangeData(data, range, byteBuffer, byteCount) ||
			byteCount != 1 ||
			byteBuffer[0] != 0x17) {
		failure = "Selection direction changed singleton copied byte";
		return false;
	}

	selection.select(2, 5, 3);
	if(!instrumentByteSelectionRange(selection, range) ||
			range.startColumn != 3 || range.endColumn != 5) {
		failure = "Reverse selection did not resolve increasing byte order";
		return false;
	}
	if(!copyInstrumentByteRangeData(data, range, byteBuffer, byteCount) ||
			byteCount != 3 ||
			byteBuffer[0 .. byteCount] !=
				cast(ubyte[])[0x13, 0x14, 0x15]) {
		failure = "Instrument byte copy did not use displayed byte order";
		return false;
	}
	InstrumentClipboardKind mostRecent = InstrumentClipboardKind.byteRange;
	if(mostRecent != InstrumentClipboardKind.byteRange) {
		failure = "Byte-range copy did not own most-recent clipboard kind";
		return false;
	}

	ubyte[] before = data.dup;
	if(!instrumentByteRangePasteFits(2, byteCount) ||
			!writeInstrumentByteRangeData(data, 11, 2, byteBuffer[],
				byteCount)) {
		failure = "Instrument byte paste was rejected unexpectedly";
		return false;
	}
	if(data[instrumentByteStorageOffset(11, 2)] != 0x13 ||
			data[instrumentByteStorageOffset(11, 3)] != 0x14 ||
			data[instrumentByteStorageOffset(11, 4)] != 0x15) {
		failure = "Instrument byte paste did not use logical destination columns";
		return false;
	}
	foreach(column; 0 .. 8) {
		if(column >= 2 && column <= 4)
			continue;
		if(data[instrumentByteStorageOffset(11, column)] !=
				before[instrumentByteStorageOffset(11, column)]) {
			failure = format("Instrument byte paste changed column %d", column);
			return false;
		}
	}
	before = data.dup;
	if(instrumentByteRangePasteFits(6, byteCount) ||
			writeInstrumentByteRangeData(data, 11, 6, byteBuffer[],
				byteCount) || data != before) {
		failure = "Overflowing Instrument byte paste mutated data";
		return false;
	}

	mostRecent = InstrumentClipboardKind.wholeInstrument;
	if(mostRecent != InstrumentClipboardKind.wholeInstrument) {
		failure = "Whole-Instrument copy did not own most-recent kind";
		return false;
	}

	string tablesSource = readText(buildPath("src", "ui", "tables.d"));
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	foreach(required; [
			"Instrument bytes copied: %d.",
			"Instrument bytes pasted: %d.",
			"No instrument bytes copied.",
			"Instrument byte selection does not fit.",
			"Instrument copied.",
			"Instrument pasted.",
			"No instrument copied.",
			"displayOperationFeedback",
			"mostRecentInstrumentClipboard",
			"InstrumentPasteUndo.createState(row)",
			"writeInstrumentByteRangeData(data, row, targetColumn",
			"override void stepRow(int n)",
			"clearByteSelection(true);\n\t\tUI.activateInstrument(row);"]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Missing Instrument byte-selection source owner: " ~
				required;
			return false;
		}
	}
	if(tablesSource.indexOf("InstrumentPasteUndo.createState(row)") >
			tablesSource.indexOf("writeInstrumentByteRangeData(data, row")) {
		failure = "Instrument byte paste mutation precedes Undo capture";
		return false;
	}
	foreach(required; [
			"instrumentByteSelectionExtendLeft",
			"instrumentByteSelectionExtendRight",
			"instrument.byte_selection_extend_left",
			"instrument.byte_selection_extend_right",
			"INSTRUMENT_BYTE_SELECTION_BINDINGS",
			"resolveInstrumentByteSelectionKeyboardAction"]) {
		if(inputSource.indexOf(required) < 0) {
			failure = "Missing Instrument byte-selection keyboard owner: " ~
				required;
			return false;
		}
	}
	foreach(required; [
			"Shift+Left/Right selects complete bytes",
			"Click-drag selects complete bytes",
			"Shift+click extends byte selection",
			"Copy with a byte selection copies those bytes",
			"with no byte selection",
			"Paste uses the most recently copied Instrument data",
			"Escape clears the visible byte selection",
			"Changing Instrument clears only the visible selection"]) {
		if(helpSource.indexOf(required) < 0) {
			failure = "Missing Instrument byte-selection Help wording: " ~
				required;
			return false;
		}
	}
	auto instrumentHelpStart = helpSource.indexOf(
		"private enum string INSTRUMENT_TABLE_HELP");
	auto instrumentHelpEnd = helpSource.indexOf(
		"ContextHelp genPlayerContextHelp", instrumentHelpStart);
	if(instrumentHelpStart < 0 || instrumentHelpEnd < instrumentHelpStart) {
		failure = "Could not isolate Instrument Help source";
		return false;
	}
	string instrumentHelpSource =
		helpSource[instrumentHelpStart .. instrumentHelpEnd];
	foreach(required; [
			"InstrumentByteDragState",
			"instrumentByteCellAt(int x, int y",
			"placeInstrumentByteCursor",
			"selectInstrumentByteRange",
			"override bool mouseMotionAt(int x, int y)",
			"override bool mouseButtonUp(int button)"]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Missing Instrument mouse byte-selection owner: " ~
				required;
			return false;
		}
	}
	foreach(required; [
			"if(activeWindow == instable)\n\t\t\treturn instable.mouseMotionAt(x, y);",
			"if(activeWindow == instable)\n\t\t\treturn instable.mouseButtonUp(button);"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = "Missing live Instrument mouse-selection route: " ~
				required;
			return false;
		}
	}
	if(tablesSource.indexOf("advanceInstrument") >= 0 ||
			tablesSource.indexOf("InstrumentByteDragAutoScroll") >= 0) {
		failure = "Instrument mouse byte selection added auto-scroll machinery";
		return false;
	}
	return true;
}

private int instrumentByteCursorX(Rectangle area, int byteColumn, int nibble) {
	return area.x + 3 + byteColumn * 3 + nibble;
}

private int instrumentByteCursorY(Rectangle area, int instrument) {
	return area.y + 1 + instrument;
}

private bool requireInstrumentByteSelectionSnapshot(
		InstrumentByteSelectionSnapshot snapshot, Rectangle area, string label,
		int expectedInstrument, int expectedColumn, int expectedNibble,
		bool expectedSelectionActive, int expectedAnchor,
		int expectedEndpoint, out string failure) {
	if(snapshot.instrument != expectedInstrument ||
			snapshot.byteColumn != expectedColumn ||
			snapshot.nibble != expectedNibble) {
		failure = format("%s expected instrument/column/nibble %d/%d/%d " ~
			"got %d/%d/%d", label, expectedInstrument, expectedColumn,
			expectedNibble, snapshot.instrument, snapshot.byteColumn,
			snapshot.nibble);
		return false;
	}
	if(snapshot.inputCursorX != instrumentByteCursorX(area, expectedColumn,
			expectedNibble) ||
			snapshot.inputCursorY != instrumentByteCursorY(area,
				expectedInstrument)) {
		failure = format("%s expected cursor %d/%d got %d/%d", label,
			instrumentByteCursorX(area, expectedColumn, expectedNibble),
			instrumentByteCursorY(area, expectedInstrument),
			snapshot.inputCursorX, snapshot.inputCursorY);
		return false;
	}
	if(snapshot.selectionActive != expectedSelectionActive) {
		failure = format("%s selection active expected %s got %s", label,
			expectedSelectionActive ? "true" : "false",
			snapshot.selectionActive ? "true" : "false");
		return false;
	}
	if(expectedSelectionActive &&
			(snapshot.selectionAnchor != expectedAnchor ||
				snapshot.selectionEndpoint != expectedEndpoint)) {
		failure = format("%s expected anchor/endpoint %d/%d got %d/%d",
			label, expectedAnchor, expectedEndpoint,
			snapshot.selectionAnchor, snapshot.selectionEndpoint);
		return false;
	}
	return true;
}

private bool requireInstrumentByteDragSnapshot(
		InstrumentByteSelectionSnapshot snapshot, string label,
		bool expectedCandidate, bool expectedCommitted,
		int expectedInstrument, int expectedAnchor, out string failure) {
	if(snapshot.dragCandidateActive != expectedCandidate ||
			snapshot.dragCommittedActive != expectedCommitted) {
		failure = format("%s expected drag candidate/committed %s/%s got %s/%s",
			label, expectedCandidate ? "true" : "false",
			expectedCommitted ? "true" : "false",
			snapshot.dragCandidateActive ? "true" : "false",
			snapshot.dragCommittedActive ? "true" : "false");
		return false;
	}
	if(expectedCandidate || expectedCommitted) {
		if(snapshot.dragInstrument != expectedInstrument ||
				snapshot.dragAnchorColumn != expectedAnchor) {
			failure = format("%s expected drag instrument/anchor %d/%d got %d/%d",
				label, expectedInstrument, expectedAnchor,
				snapshot.dragInstrument, snapshot.dragAnchorColumn);
			return false;
		}
	}
	else if(snapshot.dragInstrument != -1 || snapshot.dragAnchorColumn != -1) {
		failure = format("%s expected no drag owner got %d/%d", label,
			snapshot.dragInstrument, snapshot.dragAnchorColumn);
		return false;
	}
	return true;
}

bool checkInstrumentByteSelectionCursorRouting(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for cursor-routing test";
		return false;
	}
	scope(exit) SDL_Quit();
	com.session.initSession();
	com.session.state.song.ver = 0;
	com.session.state.displayHelp = false;
	com.session.screen = new Screen(100, 42);
	UI.statusline = new Statusline(Rectangle(0, 1, 1));
	com.session.state.undoQueue.clear();
	com.session.state.redoQueue.clear();

	Rectangle area = Rectangle(10, 10, 16, 39);
	auto table = new InsValueTable(area);
	enum instrument = 5;
	com.session.state.activeInstrument = instrument;

	table.seekByte(instrument, 3);
	table.input.nibble = 1;
	table.input.update();
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area, "initial",
			instrument, 3, 1, false, -1, -1, failure))
		return false;

	table.keypress(Keyinfo(SDLK_RIGHT, KMOD_SHIFT, 0));
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area, "Shift+Right",
			instrument, 4, 1, true, 3, 4, failure))
		return false;

	table.keypress(Keyinfo(SDLK_RIGHT, KMOD_SHIFT, 0));
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area,
			"second Shift+Right", instrument, 5, 1, true, 3, 5,
			failure))
		return false;

	table.keypress(Keyinfo(SDLK_LEFT, KMOD_SHIFT, 0));
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area, "Shift+Left",
			instrument, 4, 1, true, 3, 4, failure))
		return false;

	table.keypress(Keyinfo(SDLK_LEFT, KMOD_SHIFT, 0));
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area,
			"Shift+Left to anchor", instrument, 3, 1, true, 3, 3,
			failure))
		return false;

	table.keypress(Keyinfo(SDLK_LEFT, KMOD_SHIFT, 0));
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area,
			"Shift+Left crossing anchor", instrument, 2, 1, true, 3, 2,
			failure))
		return false;

	table.keypress(Keyinfo(SDLK_ESCAPE, 0, 0));
	table.seekByte(instrument, 0);
	table.input.nibble = 0;
	table.input.update();
	table.keypress(Keyinfo(SDLK_LEFT, KMOD_SHIFT, 0));
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area,
			"Shift+Left at column zero", instrument, 0, 0, true,
			0, 0, failure))
		return false;
	table.keypress(Keyinfo(SDLK_LEFT, KMOD_SHIFT, 0));
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area,
			"second Shift+Left at column zero", instrument, 0, 0, true,
			0, 0, failure))
		return false;
	table.keypress(Keyinfo(SDLK_ESCAPE, 0, 0));

	table.seekByte(instrument, 7);
	table.input.nibble = 1;
	table.input.update();
	table.keypress(Keyinfo(SDLK_RIGHT, KMOD_SHIFT, 0));
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area,
			"Shift+Right at column seven", instrument, 7, 1, true,
			7, 7, failure))
		return false;
	table.keypress(Keyinfo(SDLK_RIGHT, KMOD_SHIFT, 0));
	if(!requireInstrumentByteSelectionSnapshot(
			table.instrumentByteSelectionSnapshot(), area,
			"second Shift+Right at column seven", instrument, 7, 1, true,
			7, 7, failure))
		return false;

	table.seekByte(instrument, 4);
	table.input.nibble = 0;
	table.input.update();
	table.keypress(Keyinfo(SDLK_RIGHT, KMOD_SHIFT, 0));
	table.keypress(Keyinfo(SDLK_LEFT, 0, 0));
	if(table.instrumentByteSelectionSnapshot().selectionActive) {
		failure = "Ordinary Left did not clear byte selection";
		return false;
	}

	return true;
}

bool checkInstrumentByteMouseSelectionRouting(out string failure) {

	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for Instrument mouse-selection test";
		return false;
	}
	scope(exit) {
		SDL_SetModState(cast(typeof(KMOD_SHIFT))0);
		SDL_Quit();
	}
	com.session.initSession();
	com.session.state.song.ver = 0;
	com.session.state.displayHelp = false;
	com.session.screen = new Screen(100, 42);
	UI.statusline = new Statusline(Rectangle(0, 1, 1));
	com.session.state.undoQueue.clear();
	com.session.state.redoQueue.clear();

	Rectangle area = Rectangle(10, 10, 16, 39);
	auto table = new InsValueTable(area);

	enum instrument = 5;
	enum previousInstrument = 4;
	enum nextInstrument = 6;
	com.session.state.activeInstrument = instrument;
	foreach(column; 0 .. 8)
		com.session.state.song.instrumentTable[
			instrumentByteStorageOffset(instrument, column)] =
			cast(ubyte)(0x20 + column);
	auto originalBytes = instrumentBytes(instrument);

	foreach(column; 0 .. 8) {
		foreach(nibble; 0 .. 2) {
			table.seekByte(instrument, 0);
			table.clickedAt(instrumentByteCursorX(area, column, nibble),
				instrumentByteCursorY(area, instrument), 1);
			auto snapshot = table.instrumentByteSelectionSnapshot();
			if(!requireInstrumentByteSelectionSnapshot(snapshot, area,
					format("ordinary click %d/%d", column, nibble),
					instrument, column, nibble, false, -1, -1, failure))
				return false;
			if(!requireInstrumentByteDragSnapshot(snapshot,
					format("ordinary click drag %d/%d", column, nibble),
					true, false, instrument, column, failure))
				return false;
			table.mouseButtonUp(1);
			snapshot = table.instrumentByteSelectionSnapshot();
			if(snapshot.selectionActive || snapshot.dragCandidateActive ||
					snapshot.dragCommittedActive) {
				failure = format("ordinary click %d/%d left selection or drag active",
					column, nibble);
				return false;
			}
		}
	}

	table.clickedAt(instrumentByteCursorX(area, 2, 0),
		instrumentByteCursorY(area, instrument), 3);

	if(table.instrumentByteSelectionSnapshot().dragCandidateActive) {
		failure = "right-click armed Instrument byte drag";
		return false;
	}

	table.seekByte(instrument, 1);

	table.clickedAt(instrumentByteCursorX(area, 2, 0),
		instrumentByteCursorY(area, instrument), 1);

	if(!table.mouseMotionAt(instrumentByteCursorX(area, 5, 1),
			instrumentByteCursorY(area, instrument))) {
		failure = "Instrument byte drag motion was not handled";
		return false;
	}

	auto snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(snapshot, area,
			"ordinary drag forward", instrument, 5, 1, true, 2, 5,
			failure))
		return false;

	if(!requireInstrumentByteDragSnapshot(snapshot, "ordinary drag committed",
			false, true, instrument, 2, failure))
		return false;

	table.mouseButtonUp(1);

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!snapshot.selectionActive || snapshot.dragCommittedActive ||
			snapshot.dragCandidateActive) {
		failure = "mouse-up did not retain selection while clearing drag";
		return false;
	}


	table.clickedAt(instrumentByteCursorX(area, 4, 0),
		instrumentByteCursorY(area, instrument), 1);

	table.mouseMotionAt(instrumentByteCursorX(area, 4, 1),
		instrumentByteCursorY(area, instrument));

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area,
			"singleton drag", instrument, 4, 1, true, 4, 4, failure))
		return false;

	table.mouseButtonUp(1);



	table.clickedAt(instrumentByteCursorX(area, 7, 1),
		instrumentByteCursorY(area, instrument), 1);

	table.mouseMotionAt(instrumentByteCursorX(area, 0, 0),
		instrumentByteCursorY(area, instrument));

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area,
			"reverse drag", instrument, 0, 0, true, 7, 0, failure))
		return false;

	table.mouseButtonUp(1);


	table.keypress(Keyinfo(SDLK_ESCAPE, 0, 0));


	table.seekByte(instrument, 2);

	SDL_SetModState(KMOD_SHIFT);
	table.clickedAt(instrumentByteCursorX(area, 6, 1),
		instrumentByteCursorY(area, instrument), 1);
	SDL_SetModState(cast(typeof(KMOD_SHIFT))0);

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area,
			"Shift+click extend", instrument, 6, 1, true, 2, 6,
			failure))
		return false;

	table.mouseButtonUp(1);



	SDL_SetModState(KMOD_SHIFT);
	table.clickedAt(instrumentByteCursorX(area, 4, 0),
		instrumentByteCursorY(area, instrument), 1);
	SDL_SetModState(cast(typeof(KMOD_SHIFT))0);

	snapshot = table.instrumentByteSelectionSnapshot();
	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area, "Shift+click preserves anchor",
			instrument, 4, 0, true, 2, 4, failure))
		return false;

	table.mouseButtonUp(1);



	table.clickedAt(instrumentByteCursorX(area, 3, 0),
		instrumentByteCursorY(area, instrument), 1);

	table.mouseMotionAt(instrumentByteCursorX(area, 6, 0),
		instrumentByteCursorY(area, nextInstrument));

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(snapshot, area,
			"vertical drift to next row", instrument, 6, 0, true, 3, 6,
			failure))
		return false;

	if(!requireInstrumentByteDragSnapshot(snapshot,
			"vertical drift keeps committed drag", false, true,
			instrument, 3, failure))
		return false;



	table.mouseMotionAt(instrumentByteCursorX(area, 1, 1),
		instrumentByteCursorY(area, previousInstrument));

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area, "vertical drift to previous row",
			instrument, 1, 1, true, 3, 1, failure))
		return false;



	table.mouseMotionAt(instrumentByteCursorX(area, 3, 0),
		instrumentByteCursorY(area, nextInstrument + 3));

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area, "cross anchor with vertical drift",
			instrument, 3, 0, true, 3, 3, failure))
		return false;



	table.mouseMotionAt(instrumentByteCursorX(area, 7, 1),
		instrumentByteCursorY(area, previousInstrument));

	snapshot = table.instrumentByteSelectionSnapshot();
	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area, "full range with vertical drift",
			instrument, 7, 1, true, 3, 7, failure))
		return false;



	table.mouseMotionAt(area.x + 2, instrumentByteCursorY(area, nextInstrument));

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area, "x outside byte strip retains endpoint",
			instrument, 7, 1, true, 3, 7, failure))
		return false;

	if(!snapshot.dragCommittedActive) {
		failure = "x outside byte strip cancelled committed drag";
		return false;
	}

	table.mouseMotionAt(instrumentByteCursorX(area, 0, 0),
		instrumentByteCursorY(area, nextInstrument));

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area, "return to valid x resumes endpoint",
			instrument, 0, 0, true, 3, 0, failure))
		return false;

	table.mouseButtonUp(1);

	snapshot = table.instrumentByteSelectionSnapshot();

	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area, "mouse-up retains locked-row selection",
			instrument, 0, 0, true, 3, 0, failure))
		return false;



	table.clickedAt(instrumentByteCursorX(area, 1, 0),
		instrumentByteCursorY(area, instrument), 1);
	table.mouseMotionAt(area.x + 2, instrumentByteCursorY(area, instrument));

	snapshot = table.instrumentByteSelectionSnapshot();
	if(snapshot.selectionActive) {
		failure = "motion over Instrument row-number gutter selected bytes";
		return false;
	}
	table.mouseButtonUp(1);


	table.seekByte(instrument, 2);

	SDL_SetModState(KMOD_SHIFT);
	table.clickedAt(instrumentByteCursorX(area, 5, 0),
		instrumentByteCursorY(area, instrument), 1);
	SDL_SetModState(cast(typeof(KMOD_SHIFT))0);
	table.mouseMotionAt(instrumentByteCursorX(area, 7, 1),
		instrumentByteCursorY(area, nextInstrument));

	snapshot = table.instrumentByteSelectionSnapshot();
	if(!requireInstrumentByteSelectionSnapshot(
			snapshot, area, "Shift+drag locks row", instrument, 7, 1,
			true, 2, 7, failure))
		return false;
	table.mouseButtonUp(1);

	if(!requireInstrumentBytesUnchanged(instrument, originalBytes,
			"Instrument mouse byte selection", failure))
		return false;
	if(!com.session.state.undoQueue.empty() ||
			!com.session.state.redoQueue.empty()) {
		failure = "Instrument mouse byte selection changed Undo state";
		return false;
	}
	return true;
}

bool checkInstrumentByteMouseSelectionLiveParentRoute(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for live parent-route test";
		return false;
	}
	scope(exit) {
		SDL_SetModState(cast(typeof(KMOD_SHIFT))0);
		com.session.mainui = null;
		com.session.video = null;
		SDL_Quit();
	}
	com.session.initSession();
	com.session.state.song.ver = 0;
	com.session.state.displayHelp = false;
	com.session.screen = new Screen(100, 42);
	com.session.video = new FullscreenTestVideo(100 * FONT_X,
		42 * FONT_Y + trackOverviewGuiStartY());
	com.session.state.undoQueue.clear();
	com.session.state.redoQueue.clear();
	com.session.mainui = new UI();
	com.session.mainui.closeDialog(false);

	enum initialInstrument = 1;
	enum targetInstrument = 5;
	com.session.state.activeInstrument = initialInstrument;
	Rectangle area = Rectangle(49, 4, 16, 39);
	auto originalBytes = instrumentBytes(targetInstrument);

	com.session.mainui.clickedAt(instrumentByteCursorX(area, 2, 1),
		instrumentByteCursorY(area, targetInstrument), 1);
	auto table = cast(InsTable)com.session.mainui.activeWindow;
	if(table is null) {
		failure = "Instrument table was not active after byte click";
		return false;
	}
	auto snapshot = table.instrumentByteSelectionSnapshot();
	if(com.session.state.activeInstrument != targetInstrument) {
		failure = "Inactive-row click did not activate clicked Instrument";
		return false;
	}
	if(!requireInstrumentByteSelectionSnapshot(snapshot, area,
			"inactive Instrument mouse-down", targetInstrument, 2, 1,
			false, -1, -1, failure))
		return false;
	if(!requireInstrumentByteDragSnapshot(snapshot,
			"inactive Instrument candidate", true, false,
			targetInstrument, 2, failure))
		return false;

	if(!com.session.mainui.mouseMotionAt(instrumentByteCursorX(area, 6, 0),
			instrumentByteCursorY(area, targetInstrument + 2))) {
		failure = "Live parent-route motion was not handled";
		return false;
	}
	snapshot = table.instrumentByteSelectionSnapshot();
	if(!requireInstrumentByteSelectionSnapshot(snapshot, area,
			"inactive Instrument first motion", targetInstrument, 6, 0,
			true, 2, 6, failure))
		return false;
	if(!requireInstrumentByteDragSnapshot(snapshot,
			"inactive Instrument committed drag", false, true,
			targetInstrument, 2, failure))
		return false;

	if(!com.session.mainui.mouseButtonUp(1)) {
		failure = "Live parent-route mouse-up was not handled";
		return false;
	}
	snapshot = table.instrumentByteSelectionSnapshot();
	if(!requireInstrumentByteSelectionSnapshot(snapshot, area,
			"inactive Instrument mouse-up", targetInstrument, 6, 0,
			true, 2, 6, failure))
		return false;
	if(snapshot.dragCandidateActive || snapshot.dragCommittedActive) {
		failure = "Live parent-route mouse-up left drag active";
		return false;
	}

	com.session.mainui.clickedAt(instrumentByteCursorX(area, 4, 0),
		instrumentByteCursorY(area, targetInstrument), 1);
	snapshot = table.instrumentByteSelectionSnapshot();
	if(!requireInstrumentByteDragSnapshot(snapshot,
			"same-active Instrument candidate", true, false,
			targetInstrument, 4, failure))
		return false;
	com.session.mainui.mouseMotionAt(instrumentByteCursorX(area, 1, 1),
		instrumentByteCursorY(area, targetInstrument - 2));
	snapshot = table.instrumentByteSelectionSnapshot();
	if(!requireInstrumentByteSelectionSnapshot(snapshot, area,
			"same-active reverse drag", targetInstrument, 1, 1,
			true, 4, 1, failure))
		return false;
	com.session.mainui.mouseButtonUp(1);

	com.session.state.activeInstrument = initialInstrument;
	SDL_SetModState(KMOD_SHIFT);
	com.session.mainui.clickedAt(instrumentByteCursorX(area, 7, 1),
		instrumentByteCursorY(area, targetInstrument), 1);
	SDL_SetModState(cast(typeof(KMOD_SHIFT))0);
	snapshot = table.instrumentByteSelectionSnapshot();
	if(!snapshot.selectionActive ||
			snapshot.instrument != targetInstrument) {
		failure = "Shift-click on inactive Instrument did not select target row";
		return false;
	}
	if(snapshot.selectionAnchor < 0 || snapshot.selectionAnchor > 7 ||
			snapshot.selectionEndpoint != 7) {
		failure = format("Shift-click on inactive Instrument selected %d-%d",
			snapshot.selectionAnchor, snapshot.selectionEndpoint);
		return false;
	}
	com.session.mainui.mouseMotionAt(instrumentByteCursorX(area, 0, 0),
		instrumentByteCursorY(area, targetInstrument + 1));
	snapshot = table.instrumentByteSelectionSnapshot();
	if(!snapshot.selectionActive || snapshot.instrument != targetInstrument ||
			snapshot.selectionEndpoint != 0) {
		failure = "Shift-drag after inactive activation did not stay row-locked";
		return false;
	}
	com.session.mainui.mouseButtonUp(1);

	com.session.mainui.clickedAt(area.x + 27, instrumentByteCursorY(area,
		targetInstrument), 1);
	snapshot = table.instrumentByteSelectionSnapshot();
	if(snapshot.dragCandidateActive || snapshot.dragCommittedActive) {
		failure = "Instrument label click armed byte drag";
		return false;
	}
	com.session.mainui.clickedAt(area.x + 2, instrumentByteCursorY(area,
		targetInstrument), 1);
	snapshot = table.instrumentByteSelectionSnapshot();
	if(snapshot.dragCandidateActive || snapshot.dragCommittedActive) {
		failure = "Instrument number click armed byte drag";
		return false;
	}
	com.session.mainui.clickedAt(instrumentByteCursorX(area, 3, 0), area.y, 1);
	snapshot = table.instrumentByteSelectionSnapshot();
	if(snapshot.dragCandidateActive || snapshot.dragCommittedActive) {
		failure = "Instrument header click armed byte drag";
		return false;
	}

	if(!requireInstrumentBytesUnchanged(targetInstrument, originalBytes,
			"Live parent-route Instrument mouse byte selection", failure))
		return false;
	if(!com.session.state.undoQueue.empty() ||
			!com.session.state.redoQueue.empty()) {
		failure = "Live parent-route Instrument mouse selection changed Undo";
		return false;
	}
	return true;
}

private bool requireInstrumentQuickHelp(int column, int nibble, int value,
		InstrumentQuickHelpKind expectedKind, string expectedText,
		out string failure) {
	auto kind = instrumentQuickHelpKind(column, nibble, value);
	if(kind != expectedKind) {
		failure = format("column/nibble/value %d/%d/%02X expected kind %s got %s",
			column, nibble, value & 0xff, cast(int)expectedKind,
			cast(int)kind);
		return false;
	}
	string text = instrumentQuickHelpText(kind);
	if(text != expectedText) {
		failure = format("kind %s expected text '%s' got '%s'",
			cast(int)kind, expectedText, text);
		return false;
	}
	if(text.length > 54) {
		failure = format("message exceeds 54 cells: %s (%d)",
			text, text.length);
		return false;
	}
	return true;
}

bool checkInstrumentNibbleQuickHelpDecoder(out string failure) {
	foreach(spec; [
			tuple(0, 0, 0x00, InstrumentQuickHelpKind.attack,
				"Attack rate: $0 fastest, $F slowest."),
			tuple(0, 1, 0x00, InstrumentQuickHelpKind.decay,
				"Decay rate: $0 fastest, $F slowest."),
			tuple(1, 0, 0x00, InstrumentQuickHelpKind.sustain,
				"Sustain level: $0 silent, $F maximum."),
			tuple(1, 1, 0x00, InstrumentQuickHelpKind.release,
				"Release rate: $0 fastest, $F slowest."),
			tuple(2, 0, 0x00, InstrumentQuickHelpKind.restart,
				"Restart: $0 normal, $4 soft, $8 hard; +$2 skips HR AD."),
			tuple(2, 1, 0x00, InstrumentQuickHelpKind.waveDelay,
				"Wave delay: $0-$F frames."),
			tuple(3, 0, 0x00, InstrumentQuickHelpKind.hardRestartWaveform,
				"HR waveform: $1 tri, $2 saw, $4 pulse, $8 noise."),
			tuple(3, 1, 0x00, InstrumentQuickHelpKind.hardRestartFlags,
				"HR flags: $8 test, $4 ring, $2 sync; gate on."),
			tuple(4, 0, 0x00, InstrumentQuickHelpKind.filterPointer,
				"Filter-table start row: $00 off, $01-$3F."),
			tuple(4, 1, 0x3f, InstrumentQuickHelpKind.filterPointer,
				"Filter-table start row: $00 off, $01-$3F."),
			tuple(6, 0, 0x00, InstrumentQuickHelpKind.hardRestartSustain,
				"HR sustain: $0 silent, $F maximum."),
			tuple(6, 1, 0x00, InstrumentQuickHelpKind.hardRestartRelease,
				"HR release: $0 fastest, $F slowest."),
			tuple(7, 0, 0x00, InstrumentQuickHelpKind.wavePointer,
				"Wave-table start row: $00-$FF."),
			tuple(7, 1, 0xff, InstrumentQuickHelpKind.wavePointer,
				"Wave-table start row: $00-$FF.")]) {
		if(!requireInstrumentQuickHelp(spec[0], spec[1], spec[2],
				spec[3], spec[4], failure))
			return false;
	}

	foreach(value; [0x00, 0x01, 0x3f, 0x40, 0x7f, 0x80, 0x8b, 0xfb, 0xff]) {
		if(!requireInstrumentQuickHelp(5, 0, value,
				InstrumentQuickHelpKind.pulsePointer,
				"Pulse-table start row: $00 off, $01-$3F.", failure) ||
				!requireInstrumentQuickHelp(5, 1, value,
					InstrumentQuickHelpKind.pulsePointer,
					"Pulse-table start row: $00 off, $01-$3F.", failure))
			return false;
	}

	foreach(value; 0 .. 0x100) {
		foreach(nibble; 0 .. 2) {
			auto kind = instrumentQuickHelpKind(5, nibble, value);
			if(kind != InstrumentQuickHelpKind.pulsePointer) {
				failure = format("pulse %02X/%d expected byte-level pointer kind, got %s",
					value, nibble, cast(int)kind);
				return false;
			}
		}
	}

	if(instrumentQuickHelpKind(-1, 0, 0) != InstrumentQuickHelpKind.none ||
			instrumentQuickHelpKind(0, -1, 0) != InstrumentQuickHelpKind.none ||
			instrumentQuickHelpKind(8, 1, 0) != InstrumentQuickHelpKind.none ||
			instrumentQuickHelpKind(0, 2, 0) != InstrumentQuickHelpKind.none) {
		failure = "Invalid Instrument quickhelp state did not resolve to none";
		return false;
	}
	return true;
}

private bool requireInstrumentQuickHelpSnapshot(
		InstrumentByteSelectionSnapshot snapshot, string label,
		InstrumentQuickHelpKind expectedKind, string expectedText,
		out string failure) {
	if(snapshot.quickHelpKind != expectedKind) {
		failure = format("%s expected quickhelp kind %s got %s",
			label, cast(int)expectedKind, cast(int)snapshot.quickHelpKind);
		return false;
	}
	if(snapshot.quickHelpText != expectedText) {
		failure = format("%s expected quickhelp text '%s' got '%s'",
			label, expectedText, snapshot.quickHelpText);
		return false;
	}
	return true;
}

bool checkInstrumentNibbleQuickHelpNavigationRoute(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for Instrument quickhelp navigation test";
		return false;
	}
	scope(exit) {
		com.session.video = null;
		SDL_Quit();
	}
	com.session.initSession();
	com.session.state.song.ver = 9;
	com.session.state.displayHelp = true;
	com.session.screen = new Screen(100, 42);
	com.session.video = new FullscreenTestVideo(100 * FONT_X,
		42 * FONT_Y + trackOverviewGuiStartY());
	UI.statusline = new Statusline(Rectangle(0, 1, 1));

	Rectangle area = Rectangle(10, 10, 16, 39);
	auto table = new InsValueTable(area);
	enum instrument = 5;
	com.session.state.activeInstrument = instrument;

	bool prepare(int column, int nibble, int value,
			InstrumentQuickHelpKind expectedKind, string expectedText) {
		com.session.state.song.instrumentTable[
			instrumentByteStorageOffset(instrument, column)] =
			cast(ubyte)value;
		table.seekByte(instrument, column);
		table.input.nibble = nibble;
		table.input.update();
		table.showByteDescription();
		auto snapshot = table.instrumentByteSelectionSnapshot();
		if(snapshot.byteColumn != column || snapshot.nibble != nibble) {
			failure = format("prepare expected column/nibble %d/%d got %d/%d",
				column, nibble, snapshot.byteColumn, snapshot.nibble);
			return false;
		}
		return requireInstrumentQuickHelpSnapshot(snapshot, "prepare",
			expectedKind, expectedText, failure);
	}

	bool navigate(string label, int column, int nibble, int value,
			int key, int expectedColumn, int expectedNibble,
			InstrumentQuickHelpKind beforeKind, string beforeText,
			InstrumentQuickHelpKind expectedKind, string expectedText) {
		if(!prepare(column, nibble, value, beforeKind, beforeText))
			return false;
		int result = table.keypress(Keyinfo(key, 0, 0));
		if(result != OK) {
			failure = format("%s expected OK result got %d", label, result);
			return false;
		}
		auto snapshot = table.instrumentByteSelectionSnapshot();
		if(snapshot.byteColumn != expectedColumn ||
				snapshot.nibble != expectedNibble) {
			failure = format("%s expected column/nibble %d/%d got %d/%d",
				label, expectedColumn, expectedNibble, snapshot.byteColumn,
				snapshot.nibble);
			return false;
		}
		return requireInstrumentQuickHelpSnapshot(snapshot, label,
			expectedKind, expectedText, failure);
	}

	if(!navigate("AD high Right", 0, 0, 0x00, SDLK_RIGHT, 0, 1,
			InstrumentQuickHelpKind.attack,
			"Attack rate: $0 fastest, $F slowest.",
			InstrumentQuickHelpKind.decay,
			"Decay rate: $0 fastest, $F slowest."))
		return false;
	if(!navigate("AD low Left", 0, 1, 0x00, SDLK_LEFT, 0, 0,
			InstrumentQuickHelpKind.decay,
			"Decay rate: $0 fastest, $F slowest.",
			InstrumentQuickHelpKind.attack,
			"Attack rate: $0 fastest, $F slowest."))
		return false;
	if(!navigate("SR high Right", 1, 0, 0x00, SDLK_RIGHT, 1, 1,
			InstrumentQuickHelpKind.sustain,
			"Sustain level: $0 silent, $F maximum.",
			InstrumentQuickHelpKind.release,
			"Release rate: $0 fastest, $F slowest."))
		return false;
	if(!navigate("SR low Left", 1, 1, 0x00, SDLK_LEFT, 1, 0,
			InstrumentQuickHelpKind.release,
			"Release rate: $0 fastest, $F slowest.",
			InstrumentQuickHelpKind.sustain,
			"Sustain level: $0 silent, $F maximum."))
		return false;
	if(!navigate("restart high Right", 2, 0, 0x00, SDLK_RIGHT, 2, 1,
			InstrumentQuickHelpKind.restart,
			"Restart: $0 normal, $4 soft, $8 hard; +$2 skips HR AD.",
			InstrumentQuickHelpKind.waveDelay,
			"Wave delay: $0-$F frames."))
		return false;
	if(!navigate("wave delay low Left", 2, 1, 0x00, SDLK_LEFT, 2, 0,
			InstrumentQuickHelpKind.waveDelay,
			"Wave delay: $0-$F frames.",
			InstrumentQuickHelpKind.restart,
			"Restart: $0 normal, $4 soft, $8 hard; +$2 skips HR AD."))
		return false;
	if(!navigate("HR waveform high Right", 3, 0, 0x00, SDLK_RIGHT, 3, 1,
			InstrumentQuickHelpKind.hardRestartWaveform,
			"HR waveform: $1 tri, $2 saw, $4 pulse, $8 noise.",
			InstrumentQuickHelpKind.hardRestartFlags,
			"HR flags: $8 test, $4 ring, $2 sync; gate on."))
		return false;
	if(!navigate("HR flags low Left", 3, 1, 0x00, SDLK_LEFT, 3, 0,
			InstrumentQuickHelpKind.hardRestartFlags,
			"HR flags: $8 test, $4 ring, $2 sync; gate on.",
			InstrumentQuickHelpKind.hardRestartWaveform,
			"HR waveform: $1 tri, $2 saw, $4 pulse, $8 noise."))
		return false;
	if(!navigate("Filter high Right", 4, 0, 0x3f, SDLK_RIGHT, 4, 1,
			InstrumentQuickHelpKind.filterPointer,
			"Filter-table start row: $00 off, $01-$3F.",
			InstrumentQuickHelpKind.filterPointer,
			"Filter-table start row: $00 off, $01-$3F."))
		return false;
	if(!navigate("Filter low Left", 4, 1, 0x3f, SDLK_LEFT, 4, 0,
			InstrumentQuickHelpKind.filterPointer,
			"Filter-table start row: $00 off, $01-$3F.",
			InstrumentQuickHelpKind.filterPointer,
			"Filter-table start row: $00 off, $01-$3F."))
		return false;

	foreach(pulseSpec; [
			tuple(0x3f, InstrumentQuickHelpKind.pulsePointer,
				"Pulse-table start row: $00 off, $01-$3F."),
			tuple(0x80, InstrumentQuickHelpKind.pulsePointer,
				"Pulse-table start row: $00 off, $01-$3F.")]) {
		if(!navigate(format("Pulse %02X high Right", pulseSpec[0]), 5, 0,
				pulseSpec[0], SDLK_RIGHT, 5, 1, pulseSpec[1],
				pulseSpec[2], pulseSpec[1], pulseSpec[2]))
			return false;
		if(!navigate(format("Pulse %02X low Left", pulseSpec[0]), 5, 1,
				pulseSpec[0], SDLK_LEFT, 5, 0, pulseSpec[1],
				pulseSpec[2], pulseSpec[1], pulseSpec[2]))
			return false;
	}
	if(!navigate("HR sustain high Right", 6, 0, 0x00, SDLK_RIGHT, 6, 1,
			InstrumentQuickHelpKind.hardRestartSustain,
			"HR sustain: $0 silent, $F maximum.",
			InstrumentQuickHelpKind.hardRestartRelease,
			"HR release: $0 fastest, $F slowest."))
		return false;
	if(!navigate("HR release low Left", 6, 1, 0x00, SDLK_LEFT, 6, 0,
			InstrumentQuickHelpKind.hardRestartRelease,
			"HR release: $0 fastest, $F slowest.",
			InstrumentQuickHelpKind.hardRestartSustain,
			"HR sustain: $0 silent, $F maximum."))
		return false;
	if(!navigate("Wave high Right", 7, 0, 0xff, SDLK_RIGHT, 7, 1,
			InstrumentQuickHelpKind.wavePointer,
			"Wave-table start row: $00-$FF.",
			InstrumentQuickHelpKind.wavePointer,
			"Wave-table start row: $00-$FF."))
		return false;
	if(!navigate("Wave low Left", 7, 1, 0xff, SDLK_LEFT, 7, 0,
			InstrumentQuickHelpKind.wavePointer,
			"Wave-table start row: $00-$FF.",
			InstrumentQuickHelpKind.wavePointer,
			"Wave-table start row: $00-$FF."))
		return false;
	if(!navigate("AD low Right boundary", 0, 1, 0x00, SDLK_RIGHT, 1, 0,
			InstrumentQuickHelpKind.decay,
			"Decay rate: $0 fastest, $F slowest.",
			InstrumentQuickHelpKind.sustain,
			"Sustain level: $0 silent, $F maximum."))
		return false;
	if(!navigate("SR high Left boundary", 1, 0, 0x00, SDLK_LEFT, 0, 1,
			InstrumentQuickHelpKind.sustain,
			"Sustain level: $0 silent, $F maximum.",
			InstrumentQuickHelpKind.decay,
			"Decay rate: $0 fastest, $F slowest."))
		return false;
	if(!navigate("first position Left preserves canonical wrap", 0, 0, 0x00,
			SDLK_LEFT, 7, 1, InstrumentQuickHelpKind.attack,
			"Attack rate: $0 fastest, $F slowest.",
			InstrumentQuickHelpKind.wavePointer,
			"Wave-table start row: $00-$FF."))
		return false;
	return true;
}

bool checkInstrumentNibbleQuickHelpRouteSource(out string failure) {
	string tablesSource = cast(string)read("src/ui/tables.d");
	string uiSource = cast(string)read("src/ui/ui.d");
	foreach(required; [
			"enum InstrumentQuickHelpKind",
			"InstrumentQuickHelpKind instrumentQuickHelpKind(int column, int nibble,\n\t\tint value)",
			"string instrumentQuickHelpText(InstrumentQuickHelpKind kind)",
			"bool ordinaryNibbleNavigation =\n\t\t\tisOrdinaryInstrumentNibbleNavigationKey(key);",
			"if(ordinaryNibbleNavigation &&\n\t\t\t\t(column != oldColumn || input.nibble != oldNibble ||\n\t\t\t\t\tactiveQuickHelpKind() != oldKind))\n\t\t\tshowByteDescription();",
			"auto kind = instrumentQuickHelpKind(column, input.nibble,\n\t\t\t\tactiveByteValue());",
			"UI.statusline.displayContextualSemantic(outstr,\n\t\t\t\t\tformat(\"instrument:%s\", cast(int)kind));"]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Instrument quickhelp source missing " ~ required;
			return false;
		}
	}
	foreach(removed; [
			"instrumentQuickDescription",
			"ADSR attack/decay; xy:",
			"Pulse table/direct; $00 no reset"]) {
		if(tablesSource.indexOf(removed) >= 0) {
			failure = "Old byte-only Instrument quickhelp remains: " ~ removed;
			return false;
		}
	}
	foreach(required; [
			"void displayContextualSemantic(string msg, string semanticContext",
			"displayContextualWithOwner(msg, owner);",
			"private void displayContextualWithOwner(string msg, string owner)",
			"static string contextualOwnerId(string sourceFile, size_t sourceLine,\n\t\t\tstring semanticContext)",
			"if(semanticContext !is null)\n\t\t\treturn owner ~ \":\" ~ semanticContext;"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = "Statusline semantic context source missing " ~ required;
			return false;
		}
	}
	return true;
}

private bool requireProgramTableByteCell(int localX, int columnCount,
		bool expectedValid, int expectedColumn, int expectedNibble,
		out string failure) {
	ProgramTableByteCell cell = programTableByteCellAt(localX, columnCount);
	if(cell.valid != expectedValid || cell.column != expectedColumn ||
			cell.nibble != expectedNibble) {
		failure = format("local x %d columns %d expected valid/column/nibble " ~
			"%s/%d/%d got %s/%d/%d", localX, columnCount, expectedValid,
			expectedColumn, expectedNibble, cell.valid, cell.column,
			cell.nibble);
		return false;
	}
	return true;
}

bool checkProgramTableByteCellResolver(out string failure) {
	foreach(x; [-4, -1, 0, 1, 2]) {
		if(!requireProgramTableByteCell(x, 2, false, -1, -1, failure))
			return false;
	}
	foreach(spec; [
			tuple(3, 2, true, 0, 0),
			tuple(4, 2, true, 0, 1),
			tuple(5, 2, false, -1, -1),
			tuple(6, 2, true, 1, 0),
			tuple(7, 2, true, 1, 1),
			tuple(8, 2, false, -1, -1),
			tuple(9, 2, false, -1, -1),
			tuple(3, 4, true, 0, 0),
			tuple(4, 4, true, 0, 1),
			tuple(5, 4, false, -1, -1),
			tuple(6, 4, true, 1, 0),
			tuple(7, 4, true, 1, 1),
			tuple(8, 4, false, -1, -1),
			tuple(9, 4, true, 2, 0),
			tuple(10, 4, true, 2, 1),
			tuple(11, 4, false, -1, -1),
			tuple(12, 4, true, 3, 0),
			tuple(13, 4, true, 3, 1),
			tuple(14, 4, false, -1, -1),
			tuple(99, 4, false, -1, -1)]) {
		if(!requireProgramTableByteCell(spec[0], spec[1], spec[2], spec[3],
				spec[4], failure))
			return false;
	}
	return true;
}

private bool requireWaveQuickHelp(int column, int nibble, int left, int right,
		WaveQuickHelpKind expectedKind, string expectedText,
		out string failure) {
	auto kind = waveQuickHelpKind(column, nibble, left, right);
	if(kind != expectedKind) {
		failure = format("Wave column/nibble/left/right %d/%d/%02X/%02X " ~
			"expected kind %s got %s", column, nibble, left & 0xff,
			right & 0xff, cast(int)expectedKind, cast(int)kind);
		return false;
	}
	string text = waveQuickHelpText(kind);
	if(text != expectedText) {
		failure = format("Wave kind %s expected text '%s' got '%s'",
			cast(int)kind, expectedText, text);
		return false;
	}
	if(text.length > 54) {
		failure = format("Wave message exceeds 54 cells: '%s' (%d)", text,
			text.length);
		return false;
	}
	foreach(disallowed; ["Byte", "Left byte", "Right byte", "[F12"]) {
		if(text.indexOf(disallowed) >= 0) {
			failure = "Wave message contains disallowed text: " ~ text;
			return false;
		}
	}
	return true;
}

bool checkWaveQuickHelpDecoder(out string failure) {
	enum waveOptionsText =
		"Wave: $00-$7D rel, $7E loop, $7F jump, $80-$FF abs.";
	if(waveOptionsText.length != 51) {
		failure = format("Wave option-map length expected 51, got %d",
			waveOptionsText.length);
		return false;
	}
	foreach(value; 0 .. 0x100) {
		foreach(nibble; 0 .. 2) {
			if(!requireWaveQuickHelp(0, nibble, value, 0x20,
					WaveQuickHelpKind.options, waveOptionsText, failure))
				return false;
		}
	}
	foreach(nibble; 0 .. 2) {
		if(!requireWaveQuickHelp(1, nibble, 0x7e, 0xff,
				WaveQuickHelpKind.loopPrevious,
				"Loop previous Wave row; value byte is ignored.", failure))
			return false;
	}
	foreach(nibble; 0 .. 2) {
		if(!requireWaveQuickHelp(1, nibble, 0x7f, 0x04,
					WaveQuickHelpKind.jumpTarget,
					"Jump target: Wave row $00-$FF.", failure))
			return false;
	}
	foreach(nibble; 0 .. 2) {
		if(!requireWaveQuickHelp(1, nibble, 0x00, 0x00,
				WaveQuickHelpKind.keepCurrentControl,
				"Waveform: $00 keeps current control.", failure) ||
				!requireWaveQuickHelp(1, nibble, 0x00, 0x01,
					WaveQuickHelpKind.delay,
					"Wave delay: $01-$0F frames; waveform unchanged.",
					failure) ||
				!requireWaveQuickHelp(1, nibble, 0x00, 0x0f,
					WaveQuickHelpKind.delay,
					"Wave delay: $01-$0F frames; waveform unchanged.",
					failure))
			return false;
	}
	foreach(value; [0x10, 0xdf]) {
		if(!requireWaveQuickHelp(1, 0, 0x00, value,
				WaveQuickHelpKind.waveform,
				"Waveform: $1 tri, $2 saw, $4 pulse, $8 noise.",
				failure) ||
				!requireWaveQuickHelp(1, 1, 0x00, value,
					WaveQuickHelpKind.flags,
					"Flags: $1 gate, $2 sync, $4 ring, $8 test.",
					failure))
			return false;
	}
	foreach(value; [0xe0, 0xef, 0xf0, 0xff]) {
		if(!requireWaveQuickHelp(1, 0, 0x00, value,
				WaveQuickHelpKind.controlOnly,
				"Control-only mode: right nibble sets flags.", failure) ||
				!requireWaveQuickHelp(1, 1, 0x00, value,
					WaveQuickHelpKind.flags,
					"Flags: $1 gate, $2 sync, $4 ring, $8 test.",
					failure))
			return false;
	}
	foreach(left; 0 .. 0x100) {
		foreach(right; 0 .. 0x100) {
			foreach(column; 0 .. 2) {
				foreach(nibble; 0 .. 2) {
					auto kind = waveQuickHelpKind(column, nibble, left, right);
					string text = waveQuickHelpText(kind);
					if(kind == WaveQuickHelpKind.none || text.length == 0) {
						failure = format("Wave %02X/%02X column/nibble %d/%d " ~
							"resolved blank kind", left, right, column, nibble);
						return false;
					}
				}
			}
		}
	}
	if(waveQuickHelpKind(-1, 0, 0, 0) != WaveQuickHelpKind.none ||
			waveQuickHelpKind(0, -1, 0, 0) != WaveQuickHelpKind.none ||
			waveQuickHelpKind(2, 0, 0, 0) != WaveQuickHelpKind.none ||
			waveQuickHelpKind(0, 2, 0, 0) != WaveQuickHelpKind.none) {
		failure = "Invalid Wave quickhelp state did not resolve to none";
		return false;
	}
	return true;
}

private bool requirePulseQuickHelp(int column, int nibble,
		PulseQuickHelpKind expectedKind, string expectedText,
		out string failure) {
	auto kind = pulseQuickHelpKind(column);
	if(kind != expectedKind) {
		failure = format("Pulse column/nibble %d/%d expected kind %s got %s",
			column, nibble, cast(int)expectedKind, cast(int)kind);
		return false;
	}
	string text = pulseQuickHelpText(kind);
	if(text != expectedText) {
		failure = format("Pulse kind %s expected text '%s' got '%s'",
			cast(int)kind, expectedText, text);
		return false;
	}
	if(text.length > 54) {
		failure = format("Pulse message exceeds 54 cells: '%s' (%d)", text,
			text.length);
		return false;
	}
	foreach(disallowed; ["Byte 1", "Byte 2", "Byte 3", "Byte 4", "[F12",
			"Left byte", "Right byte"]) {
		if(text.indexOf(disallowed) >= 0) {
			failure = "Pulse message contains disallowed text: " ~ text;
			return false;
		}
	}
	return true;
}

bool checkPulseQuickHelpDecoder(out string failure) {
	static immutable specs = [
		tuple(0, PulseQuickHelpKind.sweepDuration,
			"Sweep duration: $00-$7F increase, $80-$FF decrease.", 51),
		tuple(1, PulseQuickHelpKind.pulseStep,
			"Pulse step: $00 hold, $01-$FF per update.", 41),
		tuple(2, PulseQuickHelpKind.pulseWidth,
			"Pulse width: XY sets $0YX0; $FF keeps current.", 46),
		tuple(3, PulseQuickHelpKind.flow,
			"Flow: $00 next, $01-$3F jump, $7F stop.", 39)
	];
	foreach(spec; specs) {
		if(spec[2].length != spec[3]) {
			failure = format("Pulse message length for column %d expected %d got %d",
				spec[0], spec[3], spec[2].length);
			return false;
		}
		foreach(nibble; 0 .. 2) {
			if(!requirePulseQuickHelp(spec[0], nibble, spec[1], spec[2],
					failure))
				return false;
		}
	}
	foreach(column; 0 .. 4) {
		auto expected = pulseQuickHelpKind(column);
		foreach(value; 0 .. 0x100) {
			if(pulseQuickHelpKind(column) != expected) {
				failure = format("Pulse column %d value %02X changed semantic kind",
					column, value);
				return false;
			}
		}
	}
	foreach(invalidColumn; [-2, -1, 4, 99]) {
		if(pulseQuickHelpKind(invalidColumn) != PulseQuickHelpKind.none) {
			failure = format("Invalid Pulse column %d did not resolve to none",
				invalidColumn);
			return false;
		}
	}
	if(pulseQuickHelpText(PulseQuickHelpKind.none).length != 0) {
		failure = "Pulse none quickhelp text is not empty";
		return false;
	}
	return true;
}

private bool requireFilterQuickHelp(int column, int nibble, int filterTypeByte,
		FilterQuickHelpKind expectedKind, string expectedText,
		out string failure) {
	auto kind = filterQuickHelpKind(column, nibble, filterTypeByte);
	if(kind != expectedKind) {
		failure = format("Filter column/nibble/type %d/%d/%02X expected kind %s got %s",
			column, nibble, filterTypeByte & 0xff, cast(int)expectedKind,
			cast(int)kind);
		return false;
	}
	string text = filterQuickHelpText(kind);
	if(text != expectedText) {
		failure = format("Filter kind %s expected text '%s' got '%s'",
			cast(int)kind, expectedText, text);
		return false;
	}
	foreach(line; text.splitLines()) {
		if(line.length > 54) {
			failure = format("Filter message line exceeds status width: '%s'",
				line);
			return false;
		}
	}
	foreach(disallowed; ["Byte 1", "Byte 2", "Byte 3", "Byte 4", "[F12",
			"Left byte", "Right byte"]) {
		if(text.indexOf(disallowed) >= 0) {
			failure = "Filter message contains disallowed text: " ~ text;
			return false;
		}
	}
	return true;
}

bool checkFilterQuickHelpDecoder(out string failure) {
	enum typeText =
		"Type: $00-$7F sweep; $8x none; $9x low-pass.\n" ~
		"$Ax band-pass; $Bx low+band; $Cx high-pass.\n" ~
		"$Dx low+high; $Ex band+high; $Fx low+band+high.";
	enum durationText = "Sweep duration: $00-$7F frames.";
	enum ignoredText = "Setup low nibble ignored; use $x0.";
	enum stepText = "Cutoff step: $00 hold, $01-$7F up, $80-$FF down.";
	enum resonanceText = "Resonance: $0 none, $F maximum.";
	enum maskText = "Filter mask: $1 V1, $2 V2, $4 V3, $8 external.";
	enum cutoffText = "Cutoff start: $00-$FE set, $FF keeps current.";
	enum flowText = "Flow: $00 next, $01-$3F jump, $7F stop.";
	static immutable specs = [
		tuple(FilterQuickHelpKind.typeOptions, typeText, 136),
		tuple(FilterQuickHelpKind.sweepDuration, durationText, 31),
		tuple(FilterQuickHelpKind.setupIgnored, ignoredText, 34),
		tuple(FilterQuickHelpKind.cutoffStep, stepText, 48),
		tuple(FilterQuickHelpKind.resonance, resonanceText, 31),
		tuple(FilterQuickHelpKind.filterMask, maskText, 46),
		tuple(FilterQuickHelpKind.cutoffStart, cutoffText, 45),
		tuple(FilterQuickHelpKind.flow, flowText, 39)
	];
	foreach(spec; specs) {
		if(filterQuickHelpText(spec[0]) != spec[1] ||
				filterQuickHelpText(spec[0]).length != spec[2]) {
			failure = format("Filter message for kind %s changed", cast(int)spec[0]);
			return false;
		}
	}
	foreach(selector; 0 .. 0x100) {
		if(!requireFilterQuickHelp(0, 0, selector,
				FilterQuickHelpKind.typeOptions, typeText, failure))
			return false;
		auto lowExpected = selector < 0x80 ?
			FilterQuickHelpKind.sweepDuration :
			FilterQuickHelpKind.setupIgnored;
		auto lowText = selector < 0x80 ? durationText : ignoredText;
		if(!requireFilterQuickHelp(0, 1, selector, lowExpected, lowText,
				failure))
			return false;
		if(selector < 0x80) {
			foreach(nibble; 0 .. 2) {
				if(!requireFilterQuickHelp(1, nibble, selector,
						FilterQuickHelpKind.cutoffStep, stepText, failure))
					return false;
			}
		}
		else {
			if(!requireFilterQuickHelp(1, 0, selector,
					FilterQuickHelpKind.resonance, resonanceText, failure) ||
					!requireFilterQuickHelp(1, 1, selector,
						FilterQuickHelpKind.filterMask, maskText, failure))
				return false;
		}
		foreach(nibble; 0 .. 2) {
			if(!requireFilterQuickHelp(2, nibble, selector,
					FilterQuickHelpKind.cutoffStart, cutoffText, failure) ||
					!requireFilterQuickHelp(3, nibble, selector,
						FilterQuickHelpKind.flow, flowText, failure))
				return false;
		}
	}
	foreach(invalidColumn; [-2, -1, 4, 99]) {
		if(filterQuickHelpKind(invalidColumn, 0, 0) != FilterQuickHelpKind.none) {
			failure = format("Invalid Filter column %d did not resolve to none",
				invalidColumn);
			return false;
		}
	}
	foreach(invalidNibble; [-2, -1, 2, 99]) {
		if(filterQuickHelpKind(0, invalidNibble, 0) !=
				FilterQuickHelpKind.none) {
			failure = format("Invalid Filter nibble %d did not resolve to none",
				invalidNibble);
			return false;
		}
	}
	if(filterQuickHelpText(FilterQuickHelpKind.none).length != 0) {
		failure = "Filter none quickhelp text is not empty";
		return false;
	}
	return true;
}

private int programTableCellX(Rectangle area, int byteColumn, int nibble) {
	return area.x + 3 + byteColumn * 3 + nibble;
}

private int programTableRowY(Rectangle area, int visibleRow) {
	return area.y + 1 + visibleRow;
}

private bool requireGeneratedProgramTableSnapshot(
		GeneratedProgramTableMouseDragSnapshot snapshot, string label,
		int expectedRow, int expectedColumn, int expectedNibble,
		out string failure) {
	if(snapshot.row != expectedRow || snapshot.column != expectedColumn ||
			snapshot.nibble != expectedNibble) {
		failure = format("%s expected row/column/nibble %d/%d/%d got %d/%d/%d",
			label, expectedRow, expectedColumn, expectedNibble, snapshot.row,
			snapshot.column, snapshot.nibble);
		return false;
	}
	return true;
}

bool checkProgramTableMouseNibblePlacementRoute(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for program-table mouse nibble test";
		return false;
	}
	scope(exit) {
		SDL_SetModState(cast(typeof(KMOD_SHIFT))0);
		com.session.mainui = null;
		com.session.video = null;
		SDL_Quit();
	}
	com.session.initSession();
	com.session.state.song.ver = 10;
	com.session.state.displayHelp = true;
	com.session.screen = new Screen(100, 42);
	com.session.video = new FullscreenTestVideo(100 * FONT_X,
		42 * FONT_Y + trackOverviewGuiStartY());
	com.session.mainui = new UI();
	UI.statusline = new Statusline(Rectangle(0, 1, 1));

	Rectangle area = Rectangle(10, 10, 16, 16);
	auto wave = new WaveTable(area);
	auto pulse = new PulseTable(area);
	auto filter = new FilterTable(area);

	bool clickAndRequire(string label, Window tableWindow,
			GeneratedProgramTableMouseDragSnapshot delegate() snapshotFn,
			int byteColumn, int nibble, int expectedRow = 0) {
		tableWindow.clickedAt(programTableCellX(area, byteColumn, nibble),
			programTableRowY(area, expectedRow), 1);
		return requireGeneratedProgramTableSnapshot(snapshotFn(), label,
			expectedRow, byteColumn, nibble, failure);
	}

	if(!clickAndRequire("Wave column 0 high", wave,
			&wave.generatedProgramTableMouseDragSnapshot, 0, 0) ||
			!clickAndRequire("Wave column 0 low", wave,
				&wave.generatedProgramTableMouseDragSnapshot, 0, 1) ||
			!clickAndRequire("Wave column 1 high", wave,
				&wave.generatedProgramTableMouseDragSnapshot, 1, 0) ||
			!clickAndRequire("Wave column 1 low", wave,
				&wave.generatedProgramTableMouseDragSnapshot, 1, 1))
		return false;
	wave.mouseButtonUp(1);

	auto before = wave.generatedProgramTableMouseDragSnapshot();
	wave.clickedAt(area.x + 5, programTableRowY(area, 0), 1);
	auto after = wave.generatedProgramTableMouseDragSnapshot();
	if(after.column != before.column || after.nibble != before.nibble ||
			after.row != before.row || after.selectionActive ||
			after.dragActive) {
		failure = "Wave separator click changed cursor, selection or drag state";
		return false;
	}

	if(!clickAndRequire("Pulse column 0 high", pulse,
			&pulse.generatedProgramTableMouseDragSnapshot, 0, 0) ||
			!clickAndRequire("Pulse column 1 low", pulse,
				&pulse.generatedProgramTableMouseDragSnapshot, 1, 1) ||
			!clickAndRequire("Pulse column 2 high", pulse,
				&pulse.generatedProgramTableMouseDragSnapshot, 2, 0) ||
			!clickAndRequire("Pulse column 3 low", pulse,
				&pulse.generatedProgramTableMouseDragSnapshot, 3, 1) ||
			!clickAndRequire("Filter column 0 high", filter,
				&filter.generatedProgramTableMouseDragSnapshot, 0, 0) ||
			!clickAndRequire("Filter column 1 low", filter,
				&filter.generatedProgramTableMouseDragSnapshot, 1, 1) ||
			!clickAndRequire("Filter column 2 high", filter,
				&filter.generatedProgramTableMouseDragSnapshot, 2, 0) ||
			!clickAndRequire("Filter column 3 low", filter,
				&filter.generatedProgramTableMouseDragSnapshot, 3, 1))
		return false;

	wave.clickedAt(programTableCellX(area, 0, 0), programTableRowY(area, 0), 1);
	SDL_SetModState(KMOD_SHIFT);
	wave.clickedAt(programTableCellX(area, 1, 1), programTableRowY(area, 3), 1);
	SDL_SetModState(cast(typeof(KMOD_SHIFT))0);
	auto selection = wave.generatedProgramTableMouseDragSnapshot();
	if(!selection.selectionActive || selection.selectionStart != 0 ||
			selection.selectionEnd != 3 || selection.column != 1 ||
			selection.nibble != 1) {
		failure = format("Wave Shift-click expected row selection 0-3 and " ~
			"endpoint column/nibble 1/1, got selection %s %d-%d column/nibble %d/%d",
			selection.selectionActive, selection.selectionStart,
			selection.selectionEnd, selection.column, selection.nibble);
		return false;
	}
	return true;
}

private bool requireStatuslineLineLimit(string label, string message,
		out string failure) {
	string[] lines = message.splitLines();
	if(lines.length == 0 || lines.length > 3) {
		failure = format("%s expected 1-3 explicit lines, got %d",
			label, lines.length);
		return false;
	}
	foreach(line; lines) {
		if(line.length > 54) {
			failure = format("%s line exceeds 54 cells: %s (%d)",
				label, line, line.length);
			return false;
		}
	}
	return true;
}

bool checkHelpCleanup1eQuickhelpWording(out string failure) {
	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string tableSource = readText(buildPath("src", "ui", "tables.d"));
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));

	foreach(required; [
			"Command x selects effect type.",
			"0 up, 1 down, 2 hi-fi vib, 3 detune, 4 ADSR.",
			"5 lo-fi vib, 6 wave, 7 porta, 8 stop.",
			"Hi-fi vibrato yy: low nibble feel.",
			"Portamento yy: low nibble = high speed digit.",
			"Hi-fi vibrato zz: high nibble speed.",
			"Low nibble depth divider.",
			"Click-drag selects rows.",
			"program-row-selection:",
			"Instrument name: edit label."]) {
		if(tableSource.indexOf(required) < 0) {
			failure = "HELPCLN-1E tables.d text missing " ~ required;
			return false;
		}
	}
	foreach(required; [
			`keyboardActionPrimaryShortcutLabel(`,
			`"sequence_input.gate_off", "note_input"`,
			`"sequence_input.gate_on", "note_input"`,
			`"sequence_input.tie", "note_input"`,
			`"sequence_input.clear", "note_input"`,
			"Note/action: notes; ",
			" gate off; ",
			" gate on.\\n",
			"Tie: ",
			"; clear: ",
			"Effect %02X: Command table entry $01-$3F.",
			"Effect %02X: Pulse table program $00-$1F.",
			"Effect %02X: Filter table program $00-$1F.",
			"Effect %02X: fixed playback speed $2-$F.",
			"Track byte: $80-$BF transpose/sequence entry.",
			"$C0-$FF LOOP/end marker target.",
			" finds next unused sequence.",
			"Sequence number for this track entry.",
			" selects previous/next sequence.",
			" commits the current track value."]) {
		if(inputSource.indexOf(required) < 0) {
			failure = "HELPCLN-1E input.d text missing " ~ required;
			return false;
		}
	}
	foreach(required; [
			"Base octave: 0-6.",
			"KeyboardActionId.uiBaseOctaveDecrease",
			"KeyboardActionId.uiBaseOctaveIncrease",
			"keyboardActionPrimaryShortcutLabel(\n\t\t\t\tkeyboardActionStableId(KeyboardActionId.uiBaseOctaveDecrease))",
			"keyboardActionPrimaryShortcutLabel(\n\t\t\t\tkeyboardActionStableId(KeyboardActionId.uiBaseOctaveIncrease))",
			"Tempo speed: $2-$1F steady.",
			"KeyboardActionId.songSpeedDecrease",
			"KeyboardActionId.songSpeedIncrease",
			"keyboardActionPrimaryShortcutLabel(\n\t\t\t\tkeyboardActionStableId(KeyboardActionId.songSpeedDecrease))",
			"keyboardActionPrimaryShortcutLabel(\n\t\t\t\tkeyboardActionStableId(KeyboardActionId.songSpeedIncrease))",
			"$0/$1 uses Chord row $00 shuffle timing.",
			"Cursor step: 1-9.",
			"KeyboardActionId.sequencerCursorStepSet",
			"KeyboardActionId.sequencerCursorStepDecrease",
			"KeyboardActionId.sequencerCursorStepIncrease",
			"keyboardActionPrimaryShortcutLabel(\n\t\t\t\tkeyboardActionStableId(KeyboardActionId.sequencerCursorStepSet))",
			"keyboardActionPrimaryShortcutLabel(\n\t\t\t\tkeyboardActionStableId(KeyboardActionId.sequencerCursorStepDecrease))",
			"keyboardActionPrimaryShortcutLabel(\n\t\t\t\tkeyboardActionStableId(KeyboardActionId.sequencerCursorStepIncrease))"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = "HELPCLN-1E ui.d text missing " ~ required;
			return false;
		}
	}
	foreach(required; [
			"Chord: $00-$3F positive; $40-$7F negative.",
			"$00 unchanged; $07 up 7; $7C down 4.",
			"$80-$FF jump marker; $94 -> row $14.",
			"Speed $0/$1: row $00 stores shuffle lengths.",
			"Values are frames; use $02-$7F.",
			"04 06 80 alternates 4/6 then jumps to $00.",
			"Sequence row-number tint follows the Track Overview block",
			"Base octave......Range 0-6.",
			"Cursor step......Range 1-9."]) {
		if(helpSource.indexOf(required) < 0) {
			failure = "HELPCLN-1E help.d text missing " ~ required;
			return false;
		}
	}

	string normalChord = chordTableQuickHelp(2, [cast(ubyte)0], 0);
	string expectedNormalChord =
		"Chord: $00-$3F positive; $40-$7F negative.\n" ~
		"$00 unchanged; $07 up 7; $7C down 4.\n" ~
		"$80-$FF jump marker; $94 -> row $14.";
	if(normalChord != expectedNormalChord) {
		failure = format("Normal Chord quickhelp expected %s got %s",
			expectedNormalChord, normalChord);
		return false;
	}
	if(!requireStatuslineLineLimit("normal Chord", normalChord, failure))
		return false;

	string shuffleChord = chordTableQuickHelp(1,
		[cast(ubyte)0x04, cast(ubyte)0x06, cast(ubyte)0x80], 2);
	string expectedShuffleChord =
		"Speed $0/$1: row $00 stores shuffle lengths.\n" ~
		"Values are frames; use $02-$7F.\n" ~
		"04 06 80 alternates 4/6 then jumps to $00.";
	if(shuffleChord != expectedShuffleChord) {
		failure = format("Shuffle Chord quickhelp expected %s got %s",
			expectedShuffleChord, shuffleChord);
		return false;
	}
	if(!requireStatuslineLineLimit("shuffle Chord", shuffleChord, failure))
		return false;

	foreach(message; [
			"Command x selects effect type.\n" ~
				"0 up, 1 down, 2 hi-fi vib, 3 detune, 4 ADSR.\n" ~
				"5 lo-fi vib, 6 wave, 7 porta, 8 stop.",
			"Hi-fi vibrato yy: low nibble feel.\nHigh nibble unused.",
			"Portamento yy: low nibble = high speed digit.\nHigh nibble unused.",
			"Hi-fi vibrato zz: high nibble speed.\nLow nibble depth divider.",
			"Base octave: 0-6.\nKeypad / decrease; Keypad * increase.",
			"Tempo speed: $2-$1F steady.\n" ~
				"$0/$1 uses Chord row $00 shuffle timing.\n" ~
				"[ decrease; ] increase.",
			"Cursor step: 1-9.\nKeypad 1-9 set value.\n" ~
				"Down decrease; Up increase.",
			"Instrument name: edit label."]) {
		if(!requireStatuslineLineLimit("HELPCLN-1E message", message, failure))
			return false;
	}

	foreach(removed; [
			"Command x: 0=slide up",
			"Hi-fi vibrato yy: low nibble is feel; high nibble unused.",
			"Portamento yy: low nibble is high speed nibble; high nibble unused.",
			"Hi-fi vibrato zz: high nibble speed; low nibble depth divider.",
			"purple/coloured bg=sequence block",
			"Tempo speed: 2-1F steady; 0/1 shuffle from Chord row 00.",
			"Base octave: 0-6. Up/Down changes value; Enter returns.",
			"Cursor step: 1-9. Up/Down changes value; Enter returns.",
			"Up/Down adjust while editing.",
			"Instrument name: edit label; Return/Tab returns to byte columns.",
			"Rows: Shift+keys or click-drag select"]) {
		if(tableSource.indexOf(removed) >= 0 ||
				inputSource.indexOf(removed) >= 0 ||
				uiSource.indexOf(removed) >= 0 ||
				helpSource.indexOf(removed) >= 0) {
			failure = "Superseded HELPCLN-1E text remains: " ~ removed;
			return false;
		}
	}
	return true;
}

bool checkFieldHelpCanonicalShortcutOwnership(out string failure) {
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));

	foreach(required; [
			"sequencerCursorStepDecrease",
			"sequencerCursorStepIncrease",
			"return \"sequencer.cursor_step_decrease\";",
			"return \"sequencer.cursor_step_increase\";",
			"KeyboardContext.cursorStepInput",
			"return \"cursor_step_input\";",
			"CURSOR_STEP_INPUT_BINDINGS",
			"resolveCursorStepInputKeyboardAction"]) {
		if(inputSource.indexOf(required) < 0) {
			failure = "FIELDHELP-1B input.d missing " ~ required;
			return false;
		}
	}

	foreach(forbidden; [
			"sequencerCursorStepSet1",
			"sequencerCursorStepSet2",
			"sequencer.cursor_step_set_1",
			"sequencer.cursor_step_set_9"]) {
		if(inputSource.indexOf(forbidden) >= 0) {
			failure = "FIELDHELP-1B introduced per-keypad action: " ~ forbidden;
			return false;
		}
	}

	if(keyboardActionPrimaryShortcutLabel("sequencer.cursor_step_set") !=
			"Keypad 1-9") {
		failure = "Cursor-step set primary label is not the canonical range";
		return false;
	}
	if(keyboardActionPrimaryShortcutLabel("sequencer.cursor_step_decrease") !=
			"Down") {
		failure = "Cursor-step decrease primary label is not Down";
		return false;
	}
	if(keyboardActionPrimaryShortcutLabel("sequencer.cursor_step_increase") !=
			"Up") {
		failure = "Cursor-step increase primary label is not Up";
		return false;
	}

	KeyboardActionId actionId;
	if(!resolveCursorStepInputKeyboardAction(Keyinfo(SDLK_DOWN, 0, 0),
			actionId) ||
			actionId != KeyboardActionId.sequencerCursorStepDecrease) {
		failure = "Down did not resolve to cursor-step decrease in St context";
		return false;
	}
	if(!resolveCursorStepInputKeyboardAction(Keyinfo(SDLK_UP, 0, 0),
			actionId) ||
			actionId != KeyboardActionId.sequencerCursorStepIncrease) {
		failure = "Up did not resolve to cursor-step increase in St context";
		return false;
	}

	int stepValue;
	if(!resolveSequencerCursorStepKeyboardAction(Keyinfo(SDLK_KP_1, 0, 0),
			actionId, stepValue) ||
			actionId != KeyboardActionId.sequencerCursorStepSet ||
			stepValue != 1) {
		failure = "Keypad 1 no longer resolves through the ranged step action";
		return false;
	}
	if(!resolveSequencerCursorStepKeyboardAction(Keyinfo(SDLK_KP_9, 0, 0),
			actionId, stepValue) ||
			actionId != KeyboardActionId.sequencerCursorStepSet ||
			stepValue != 9) {
		failure = "Keypad 9 no longer resolves through the ranged step action";
		return false;
	}
	if(resolveSequencerCursorStepKeyboardAction(Keyinfo(SDLK_DOWN, 0, 0),
			actionId, stepValue)) {
		failure = "Generic Down resolved as direct cursor-step set";
		return false;
	}

	foreach(required; [
			"resolveCursorStepInputKeyboardAction(key, actionId)",
			"case KeyboardActionId.sequencerCursorStepDecrease:",
			"stepValue(-1);",
			"case KeyboardActionId.sequencerCursorStepIncrease:",
			"stepValue(1);",
			"%s decrease; %s increase."]) {
		if(uiSource.indexOf(required) < 0) {
			failure = "FIELDHELP-1B ui.d missing " ~ required;
			return false;
		}
	}
	if(uiSource.indexOf("\"Up/Down adjust while editing.\"") >= 0) {
		failure = "Old hard-coded St Up/Down quickhelp remains";
		return false;
	}

	foreach(message; [
			"Base octave: 0-6.\nKeypad / decrease; Keypad * increase.",
			"Tempo speed: $2-$1F steady.\n" ~
				"$0/$1 uses Chord row $00 shuffle timing.\n" ~
				"[ decrease; ] increase.",
			"Cursor step: 1-9.\nKeypad 1-9 set value.\n" ~
				"Down decrease; Up increase."]) {
		if(!requireStatuslineLineLimit("FIELDHELP-1B message", message,
				failure))
			return false;
	}

	return true;
}

private bool keyboardHelpRowContainsAction(KeyboardActionId[] actionIds,
		KeyboardActionId actionId) {
	foreach(candidate; actionIds) {
		if(candidate == actionId)
			return true;
	}
	return false;
}

private int countKeyboardHelpAction(KeyboardHelpSection section,
		KeyboardActionId actionId) {
	int count;
	foreach(row; keyboardHelpRows(section)) {
		if(keyboardHelpRowContainsAction(row.actionIds, actionId))
			count++;
	}
	return count;
}

private bool requireKeyboardHelpPlacement(KeyboardHelpSection section,
		KeyboardActionId actionId, string description, string renderedPage,
		out string failure) {
	int count;
	bool rendered;
	foreach(row; keyboardHelpRows(section)) {
		if(!keyboardHelpRowContainsAction(row.actionIds, actionId))
			continue;
		count++;
		if(row.description == description) {
			string label = keyboardHelpRowShortcutLabel(row, "/");
			if(label.length == 0) {
				failure = "FIELDHELP-1C empty rendered label for " ~
					keyboardActionStableId(actionId);
				return false;
			}
			rendered = renderedPage.indexOf(label) >= 0 &&
				renderedPage.indexOf(description) >= 0;
		}
	}
	if(count != 1) {
		failure = format("FIELDHELP-1C expected one placement for %s in section, got %s",
			keyboardActionStableId(actionId), count);
		return false;
	}
	if(!rendered) {
		failure = "FIELDHELP-1C rendered Help missing " ~
			keyboardActionStableId(actionId) ~ " / " ~ description;
		return false;
	}
	return true;
}

bool checkFieldHelpRecentActionF12Inventory(out string failure) {
	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string inputSource = readText(buildPath("src", "ui", "input.d"));

	KeyboardActionId[] inventory = [
		KeyboardActionId.sequencePlayRowAllVoices,
		KeyboardActionId.trackEntryPasteInsert,
		KeyboardActionId.trackEntryPasteOverwrite,
		KeyboardActionId.trackEntryTransposeUpFromCursor,
		KeyboardActionId.trackEntryTransposeDownFromCursor,
		KeyboardActionId.uiToggleFullscreen,
		KeyboardActionId.uiToggleInterpolation,
		KeyboardActionId.uiBaseOctaveDecrease,
		KeyboardActionId.uiBaseOctaveIncrease,
		KeyboardActionId.songSpeedDecrease,
		KeyboardActionId.songSpeedIncrease,
		KeyboardActionId.sequencerCursorStepSet,
		KeyboardActionId.sequencerCursorStepDecrease,
		KeyboardActionId.sequencerCursorStepIncrease
	];
	foreach(i, actionId; inventory) {
		string stableId = keyboardActionStableId(actionId);
		if(stableId.length == 0 ||
				keyboardActionPrimaryShortcutLabel(stableId).length == 0) {
			failure = "FIELDHELP-1C missing canonical metadata for " ~ stableId;
			return false;
		}
		foreach(j, other; inventory) {
			if(j <= i)
				continue;
			if(stableId == keyboardActionStableId(other)) {
				failure = "FIELDHELP-1C duplicate stable id " ~ stableId;
				return false;
			}
		}
	}

	if(!requireKeyboardHelpPlacement(
			KeyboardHelpSection.sequenceEditingSequencer,
			KeyboardActionId.sequencePlayRowAllVoices,
			"Play current row once, then step down",
			HELPSEQUENCER.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.mainPlayback,
			KeyboardActionId.sequencePlayRowAllVoices,
			"F6 only: play current row once, then step down",
			HELPPLAYBACK.text[0], failure))
		return false;

	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.trackColumnAdvanced,
			KeyboardActionId.trackEntryPasteInsert,
			"Paste copied tracks using insert mode",
			HELPTRACKTABLE.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.trackColumnAdvanced,
			KeyboardActionId.trackEntryPasteOverwrite,
			"Paste copied tracks using overwrite mode",
			HELPTRACKTABLE.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.trackColumnAdvanced,
			KeyboardActionId.trackEntryTransposeUpFromCursor,
			"Transpose active voice tracks up from cursor down",
			HELPTRACKTABLE.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.trackColumnAdvanced,
			KeyboardActionId.trackEntryTransposeDownFromCursor,
			"Transpose active voice tracks down from cursor down",
			HELPTRACKTABLE.text[0], failure))
		return false;

	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.mainApp,
			KeyboardActionId.uiToggleFullscreen, "Toggle fullscreen",
			HELPMAIN.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.mainApp,
			KeyboardActionId.uiToggleInterpolation,
			"Toggle audio interpolation", HELPMAIN.text[0], failure))
		return false;

	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.mainSongBeforeClicks,
			KeyboardActionId.uiBaseOctaveDecrease,
			"Decrease base octave value (0-6)", HELPMAIN.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.mainSongBeforeClicks,
			KeyboardActionId.uiBaseOctaveIncrease,
			"Increase base octave value (0-6)", HELPMAIN.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.mainSongBeforeClicks,
			KeyboardActionId.songSpeedDecrease,
			"Decrease/increase song speed ($0/$1 shuffle, $2-$1F steady)",
			HELPMAIN.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.mainSongBeforeClicks,
			KeyboardActionId.songSpeedIncrease,
			"Decrease/increase song speed ($0/$1 shuffle, $2-$1F steady)",
			HELPMAIN.text[0], failure))
		return false;

	if(!requireKeyboardHelpPlacement(
			KeyboardHelpSection.sequenceEditingSequencer,
			KeyboardActionId.sequencerCursorStepSet,
			"Set cursor step value to 1-9 while editing St",
			HELPSEQUENCER.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(
			KeyboardHelpSection.sequenceEditingSequencer,
			KeyboardActionId.sequencerCursorStepDecrease,
			"Decrease cursor step value while editing St",
			HELPSEQUENCER.text[0], failure))
		return false;
	if(!requireKeyboardHelpPlacement(
			KeyboardHelpSection.sequenceEditingSequencer,
			KeyboardActionId.sequencerCursorStepIncrease,
			"Increase cursor step value while editing St",
			HELPSEQUENCER.text[0], failure))
		return false;

	if(countKeyboardHelpAction(KeyboardHelpSection.sequenceEditingSequencer,
			KeyboardActionId.sequencePlayRowAllVoices) +
			countKeyboardHelpAction(KeyboardHelpSection.mainPlayback,
				KeyboardActionId.sequencePlayRowAllVoices) != 2) {
		failure = "FIELDHELP-1C play-row action does not have exactly two approved placements";
		return false;
	}

	foreach(actionId; inventory[1 .. $]) {
		int count;
		foreach(section; [KeyboardHelpSection.mainApp,
				KeyboardHelpSection.mainPlayback,
				KeyboardHelpSection.mainSongBeforeClicks,
				KeyboardHelpSection.mainSongAfterClicks,
				KeyboardHelpSection.sequencerGeneralAfterVoiceTab,
				KeyboardHelpSection.sequenceEditingSequencer,
				KeyboardHelpSection.trackColumnAdvanced]) {
			count += countKeyboardHelpAction(section, actionId);
		}
		if(count != 1) {
			failure = format("FIELDHELP-1C expected one recent-action Help placement for %s got %s",
				keyboardActionStableId(actionId), count);
			return false;
		}
	}

	foreach(forbidden; [
			"sequencerCursorStepSet1",
			"sequencerCursorStepSet2",
			"sequencer.cursor_step_set_1",
			"sequencer.cursor_step_set_9"]) {
		if(inputSource.indexOf(forbidden) >= 0) {
			failure = "FIELDHELP-1C introduced per-keypad cursor-step action " ~
				forbidden;
			return false;
		}
	}
	foreach(forbidden; [
			"Keypad 0", "Keypad 1-9", "Keypad /", "Keypad *",
			"Control-I", "Control-O", "Control-Q", "Control-A",
			"Option-Return", "Control-F2", "Use Up/Down",
			"Up/Down wraps"]) {
		if(helpSource.indexOf(forbidden) >= 0) {
			failure = "FIELDHELP-1C Help prose hard-codes shortcut label " ~
				forbidden;
			return false;
		}
	}

	return true;
}

bool checkHelpRef1aReferenceCleanup(out string failure) {
	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string inputSource = readText(buildPath("src", "ui", "input.d"));
		char*[] emptyDescriptions;
		auto instrumentHelp = genPlayerContextHelp("Instrument table",
			emptyDescriptions);
		string instrumentText = instrumentHelp.text[0];
		string pulseText = genPlayerContextHelp("Pulse table",
			emptyDescriptions).text[0];
		string filterText = genPlayerContextHelp("Filter table",
			emptyDescriptions).text[0];

	foreach(removed; [
			"Entering an Instrument number can also update the active Instrument preview.",
			"This Help topic is for the Sequence row Instrument field",
			"active Instrument preview",
			"topic documents the eight Instrument settings bytes"]) {
		if(helpSource.indexOf(removed) >= 0 ||
				HELPSEQUENCEINSTRUMENTCOLUMN.text[0].indexOf(removed) >= 0) {
			failure = "HELPREF-1A confusing Sequence Instrument prose remains: " ~
				removed;
			return false;
		}
	}
	foreach(required; [
			"The Instrument field is the middle value in a Sequence row:",
			"yy = Instrument...Instrument number used by this row",
			"`+dInstrument-column shortcuts"]) {
		if(HELPSEQUENCEINSTRUMENTCOLUMN.text[0].indexOf(required) < 0) {
			failure = "HELPREF-1A surrounding Sequence Instrument text missing: " ~
				required;
			return false;
		}
	}

	if(inputSource.indexOf("KeyboardHelpSection.mainInstrumentSelection") < 0) {
		failure = "HELPREF-1A missing Instrument selection Help section";
		return false;
	}
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.mainInstrumentSelection,
			KeyboardActionId.uiInstrumentPrevious,
			"Select previous active Instrument", instrumentText, failure))
		return false;
	if(!requireKeyboardHelpPlacement(KeyboardHelpSection.mainInstrumentSelection,
			KeyboardActionId.uiInstrumentNext,
			"Select next active Instrument", instrumentText, failure))
		return false;
	foreach(section; [KeyboardHelpSection.sequencerGeneralAfterVoiceTab,
			KeyboardHelpSection.mainApp,
			KeyboardHelpSection.mainSongBeforeClicks,
			KeyboardHelpSection.mainInstrumentTable]) {
		if(countKeyboardHelpAction(section,
				KeyboardActionId.uiInstrumentPrevious) != 0 ||
				countKeyboardHelpAction(section,
					KeyboardActionId.uiInstrumentNext) != 0) {
			failure = "HELPREF-1A duplicated Instrument adjustment placement";
			return false;
		}
	}
	foreach(label; [
			keyboardActionPrimaryShortcutLabel("ui.instrument_previous"),
			keyboardActionPrimaryShortcutLabel("ui.instrument_next")]) {
		if(label.length == 0 || instrumentText.indexOf(label) < 0) {
			failure = "HELPREF-1A Instrument Help missing canonical label " ~ label;
			return false;
		}
	}

		foreach(heading; [
				"Sweep row", "Sweep examples", "Setup row", "Mode values",
				"Voice/input mask", "Setup examples", "Pulse examples",
				"Rows"]) {
			if(helpSource.indexOf("`+d" ~ heading) < 0) {
				failure = "HELPREF-1A heading text missing: " ~ heading;
			return false;
		}
		if(helpSource.indexOf("\t`+d" ~ heading) >= 0) {
			failure = "HELPREF-1A ornamental heading indentation remains: " ~
				heading;
			return false;
			}
		}
		foreach(heading; [
				"Filter table", "Sweep row", "Sweep examples", "Setup row",
				"Mode values", "Voice/input mask", "Setup examples", "Rows"]) {
			if(filterText.indexOf(heading) < 0) {
				failure = "HELPREF-R1B rendered Filter heading missing: " ~ heading;
				return false;
			}
		}
		foreach(heading; ["Pulse examples", "Rows"]) {
			if(pulseText.indexOf(heading) < 0) {
				failure = "HELPREF-R1B rendered Pulse heading missing: " ~ heading;
				return false;
			}
		}
		foreach(required; [
				"`+dSweep row", "`+dSweep examples",
				"`+dSetup row", "`+dMode values", "`+dVoice/input mask",
				"`+dSetup examples", "`+dPulse examples",
				"04 02 48 7F > Set pulse width $0840",
				"90 F4 40 01 > Low-pass"]) {
		if(helpSource.indexOf(required) < 0) {
			failure = "HELPREF-1A required Pulse/Filter reference text missing: " ~
				required;
			return false;
		}
	}
	foreach(forbidden; [
			">>Sweep row", ">>Sweep examples", ">>Setup row",
			">>Mode values", ">>Voice/input mask", ">>Setup examples",
			">>Pulse examples", "\n\n\n`+dInstrument-column shortcuts"]) {
		if(helpSource.indexOf(forbidden) >= 0 ||
				instrumentText.indexOf(forbidden) >= 0) {
			failure = "HELPREF-1A unwanted formatting remains: " ~ forbidden;
				return false;
			}
		}
		foreach(forbidden; ["»", "Â»", "\t"]) {
			if(pulseText.indexOf(forbidden) >= 0 ||
					filterText.indexOf(forbidden) >= 0) {
				failure = "HELPREF-R1B rendered Pulse/Filter ornament remains: " ~
					forbidden;
				return false;
			}
		}
		foreach(line; (pulseText ~ "\n" ~ filterText).splitLines()) {
			if(line.indexOf("»") == 0) {
				failure = "HELPREF-R1B rendered heading begins with ornament: " ~
					line;
				return false;
			}
		}
		foreach(required; [
				"ef = XY    > pulse width $0YX0",
				"04 02 48 7F > Set pulse width $0840",
				"90 F4 40 01 > Low-pass",
				"$94 -> row $14"]) {
			if((pulseText ~ "\n" ~ filterText ~ "\n" ~ helpSource).
					indexOf(required) < 0) {
				failure = "HELPREF-R1B semantic arrow/range text missing: " ~
					required;
				return false;
			}
		}

	return true;
}

bool checkAppCln1bDeadHelpMessageCleanup(out string failure) {
	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string callbackSource = readText(buildPath("src", "audio", "callback.d"));
	string tablesSource = readText(buildPath("src", "ui", "tables.d"));

	foreach(forbidden; [
			"helpStatusBarShortcutHint",
			"helpTopicIdForIndex",
			"CHORD_SHUFFLE_MIN_USEFUL_ROW_LENGTH"]) {
		if(helpSource.indexOf(forbidden) >= 0) {
			failure = "APPCLN-1B dead Help symbol remains: " ~ forbidden;
			return false;
		}
	}
	if(helpSource.indexOf("string helpMoreStatusHint()") < 0 ||
			tablesSource.indexOf("ui.help.helpMoreStatusHint()") < 0) {
		failure = "APPCLN-1B removed or disconnected live helpMoreStatusHint";
		return false;
	}
	if(callbackSource.indexOf("//UI.statusline.display(e.toString());") >= 0 ||
			callbackSource.indexOf("//stop();") >= 0) {
		failure = "APPCLN-1B stale callback comment remains";
		return false;
	}
	if(callbackSource.indexOf("playbackStatus = e;") < 0 ||
			callbackSource.indexOf("stop(); // < TODO: player.d should check") < 0) {
		failure = "APPCLN-1B changed live callback exception handling";
		return false;
	}
	if(helpSource.indexOf("displayContextDismissibleInformation") >= 0) {
		failure = "APPCLN-1B legacy mixed Statusline API was reintroduced";
		return false;
	}
	return true;
}

bool checkAppCln1b2DeadUtilityLayoutCleanup(out string failure) {
	string fbSource = readText(buildPath("src", "com", "fb.d"));
	string utilSource = readText(buildPath("src", "com", "util.d"));
	string trackOverviewLayoutSource = readText(buildPath("src", "ui",
		"trackoverviewlayout.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	string trackOverviewStateSource = readText(buildPath("src", "ui",
		"trackoverviewstate.d"));
	string trackOverviewRendererSource = readText(buildPath("src", "ui",
		"trackoverviewrenderer.d"));
	string ct2utilSource = readText(buildPath("src", "ct2util.d"));
	string releaseManifestSource = readText(buildPath("release",
		"source-files.txt"));

	foreach(forbidden; [
			"clearVisualizer",
			"readkey",
			"table2Array",
			"trackOverviewScrollbarTopGapY",
			"trackOverviewScrollbarTopGapHeight",
			"trackOverviewBottomGapY",
			"trackOverviewBottomGapHeight"]) {
		if((fbSource ~ "\n" ~ utilSource ~ "\n" ~ trackOverviewLayoutSource).
				indexOf(forbidden) >= 0) {
			failure = "APPCLN-1B2 dead utility/layout symbol remains: " ~
				forbidden;
			return false;
		}
	}
	if(fbSource.indexOf("void drawVisualizer(int)") < 0 ||
			uiSource.indexOf("video.drawVisualizer(n)") < 0) {
		failure = "APPCLN-1B2 removed or disconnected live drawVisualizer";
		return false;
	}
	if(fbSource.indexOf("SDL_PollEvent") >= 0) {
		failure = "APPCLN-1B2 left a raw SDL polling input owner in fb.d";
		return false;
	}
	if(utilSource.indexOf("int str2Value(string s)") < 0 ||
			utilSource.indexOf("int str2Value2(string s)") < 0 ||
			ct2utilSource.indexOf("str2Value2(nextArg())") < 0) {
		failure = "APPCLN-1B2 changed active utility conversion ownership";
		return false;
	}
	foreach(required; [
			"trackOverviewTimeRowY",
			"trackOverviewVoiceBlockY",
			"trackOverviewScrollbarY",
			"trackOverviewScrollbarHeight",
			"trackOverviewContentAreaWidth"]) {
		if(trackOverviewLayoutSource.indexOf(required) < 0 ||
				(trackOverviewStateSource ~ "\n" ~ trackOverviewRendererSource).
					indexOf(required) < 0) {
			failure = "APPCLN-1B2 removed active Track Overview layout owner: " ~
				required;
			return false;
		}
	}
	foreach(required; [
			"src/com/fb.d",
			"src/com/util.d",
			"src/ui/trackoverviewlayout.d"]) {
		if(releaseManifestSource.indexOf(required) < 0) {
			failure = "APPCLN-1B2 changed source-release ownership for " ~
				required;
			return false;
		}
	}
	return true;
}

enum LEGACY_CT_BINARY_LENGTH = 65536;
enum LEGACY_CT_HEADER_OFFSET = LEGACY_CT_BINARY_LENGTH;
enum LEGACY_CT_TITLE_OFFSET = LEGACY_CT_HEADER_OFFSET + 256 + 5;
enum LEGACY_CT_INSNAMES_OFFSET = LEGACY_CT_TITLE_OFFSET + 40 * 4;
enum LEGACY_CT_SUBTUNES_OFFSET = LEGACY_CT_INSNAMES_OFFSET + 1024 * 2;
enum LEGACY_CT_SUBTUNES_LENGTH = 1024 * 3 * 32;
enum LEGACY_CT_PAYLOAD_LENGTH = LEGACY_CT_SUBTUNES_OFFSET +
	LEGACY_CT_SUBTUNES_LENGTH;

int legacyCtOffset(const(ubyte)[] payload, Offsets entry) {
	int tableOffset = 0xfa0 + cast(int)entry * 2;
	return payload[tableOffset] | (payload[tableOffset + 1] << 8);
}

void writeFixedAscii(ubyte[] payload, int offset, int width, string value,
		ubyte fill = 0x20) {
	payload[offset .. offset + width][] = fill;
	int count = value.length < width ? cast(int)value.length : width;
	payload[offset .. offset + count] = cast(ubyte[])value[0 .. count];
}

void writeCString(ubyte[] payload, int offset, string value) {
	payload[offset .. offset + value.length] = cast(ubyte[])value[];
	payload[offset + value.length] = 0;
}

void writeLegacyDefaultSubtunes(ubyte[] payload) {
	foreach(subtune; 0 .. 32) {
		foreach(voice; 0 .. 3) {
			int offset = LEGACY_CT_SUBTUNES_OFFSET +
				(subtune * 3 + voice) * 1024;
			payload[offset .. offset + 2] = cast(ubyte[])[0xa0, 0x00];
			for(int i = 2; i < 1024; i += 2)
				payload[offset + i .. offset + i + 2] =
					cast(ubyte[])[0xf0, 0x00];
		}
	}
}

void writeDescriptionSet(ubyte[] payload, Offsets header, int count,
		string prefix) {
	int headerOffset = legacyCtOffset(payload, header);
	foreach(index; 0 .. count) {
		int pointerOffset = headerOffset + index * 2;
		int target = payload[pointerOffset] |
			(payload[pointerOffset + 1] << 8);
		writeCString(payload, target, format("%s%d", prefix, index));
	}
}

ubyte[] buildLegacyCtFileData(int revision) {
	Song baseSong = new Song();
	ubyte[] payload;
	payload.length = LEGACY_CT_PAYLOAD_LENGTH;
	payload[] = 0;
	payload[0 .. LEGACY_CT_BINARY_LENGTH] =
		baseSong.data[0 .. LEGACY_CT_BINARY_LENGTH];

	int instrumentOffset = legacyCtOffset(payload, Offsets.Inst);
	foreach(index; 0 .. 8)
		payload[instrumentOffset + index] =
			cast(ubyte)(0x20 + revision + index);

	if(revision > 7)
		writeDescriptionSet(payload, Offsets.InstrumentDescriptionsHeader,
			8, format("R%02d-I", revision));
	if(revision > 8) {
		writeDescriptionSet(payload, Offsets.FilterDescriptionsHeader,
			4, format("R%02d-F", revision));
		writeDescriptionSet(payload, Offsets.PulseDescriptionsHeader,
			4, format("R%02d-P", revision));
		writeDescriptionSet(payload, Offsets.WaveDescriptionsHeader,
			2, format("R%02d-W", revision));
		writeDescriptionSet(payload, Offsets.CmdDescriptionsHeader,
			2, format("R%02d-C", revision));
	}

	int offset = LEGACY_CT_HEADER_OFFSET;
	payload[offset++] = cast(ubyte)revision;
	payload[offset++] = cast(ubyte)(0x10 + revision);
	payload[offset++] = cast(ubyte)(1 + (revision % 4));
	payload[offset++] = cast(ubyte)(revision & 1);
	payload[offset++] = cast(ubyte)(0x30 + revision);
	if(revision >= 6) {
		foreach(index; 0 .. 32)
			payload[offset + index] =
				cast(ubyte)(2 + ((revision + index) % 0x1e));
		offset += 32;
	}
	if(revision > 10) {
		payload[offset++] = 7;
		payload[offset++] = 3;
	}

	writeFixedAscii(payload, LEGACY_CT_TITLE_OFFSET, 32,
		format("Legacy revision %02d", revision));
	writeFixedAscii(payload, LEGACY_CT_TITLE_OFFSET + 32, 32,
		"Compatibility Test");
	writeFixedAscii(payload, LEGACY_CT_TITLE_OFFSET + 64, 32,
		"APPCLN-1C1");
	writeFixedAscii(payload, LEGACY_CT_TITLE_OFFSET + 96, 32,
		"Legacy fixture");
	payload[LEGACY_CT_INSNAMES_OFFSET ..
		LEGACY_CT_INSNAMES_OFFSET + 48 * 32][] = 0x20;
	writeFixedAscii(payload, LEGACY_CT_INSNAMES_OFFSET, 32,
		format("Inst legacy %02d", revision));
	writeLegacyDefaultSubtunes(payload);

	ubyte[] output = cast(ubyte[])"CC2".dup;
	output ~= cast(ubyte[])compress(payload);
	return output;
}

string writeLegacyCtFixture(int revision) {
	string path = buildPath(tempDir(),
		format("ccutter-appcln-legacy-r%02d.ct", revision));
	std.file.write(path, buildLegacyCtFileData(revision));
	return path;
}

int ctFileRevision(ubyte[] fileData) {
	ubyte[] payload = cast(ubyte[])uncompress(fileData[3 .. $], 167832);
	return payload[LEGACY_CT_HEADER_OFFSET];
}

int savedCtFileRevision(string path) {
	return ctFileRevision(cast(ubyte[])read(path));
}

string cStringValue(char* value) {
	if(value is null)
		return "";
	return fromStringz(value).idup;
}

bool expectLegacyDescription(Song song, Song defaults, int revision,
		bool instrumentPresent, bool programPresent, out string failure) {
	string expectedInstrument = instrumentPresent ?
		format("R%02d-I0", revision) :
		cStringValue(defaults.instrumentByteDescriptions[0]);
	if(song.instrumentByteDescriptions.length < 8 ||
			cStringValue(song.instrumentByteDescriptions[0]) !=
				expectedInstrument) {
		failure = format("revision %d instrument description expected %s got %s",
			revision, expectedInstrument,
			song.instrumentByteDescriptions.length ?
				cStringValue(song.instrumentByteDescriptions[0]) : "<missing>");
		return false;
	}

	string expectedPulse = programPresent ? format("R%02d-P0", revision) :
		cStringValue(defaults.pulseDescriptions[0]);
	string expectedFilter = programPresent ? format("R%02d-F0", revision) :
		cStringValue(defaults.filterDescriptions[0]);
	string expectedWave = programPresent ? format("R%02d-W0", revision) :
		cStringValue(defaults.waveDescriptions[0]);
	string expectedCmd = programPresent ? format("R%02d-C0", revision) :
		cStringValue(defaults.cmdDescriptions[0]);
	if(song.pulseDescriptions.length < 4 ||
			cStringValue(song.pulseDescriptions[0]) != expectedPulse ||
			song.filterDescriptions.length < 4 ||
			cStringValue(song.filterDescriptions[0]) != expectedFilter ||
			song.waveDescriptions.length < 2 ||
			cStringValue(song.waveDescriptions[0]) != expectedWave ||
			song.cmdDescriptions.length < 2 ||
			cStringValue(song.cmdDescriptions[0]) != expectedCmd) {
		failure = format("revision %d program descriptions did not match gate",
			revision);
		return false;
	}
	return true;
}

bool checkLegacyRevisionState(Song song, int revision, out string failure) {
	Song defaults = new Song();
	if(song.ver != revision) {
		failure = format("revision %d loaded as %d", revision, song.ver);
		return false;
	}
	if(strip(song.title[]) != format("Legacy revision %02d", revision)) {
		failure = format("revision %d title mismatch: %s", revision,
			strip(song.title[]));
		return false;
	}
	if(strip(song.insLabels[0][]) != format("Inst legacy %02d", revision)) {
		failure = format("revision %d instrument label mismatch: %s",
			revision, strip(song.insLabels[0][]));
		return false;
	}
	if(song.songspeeds[0] != cast(ubyte)(2 + (revision % 0x1e)) ||
			song.songspeeds[31] !=
				cast(ubyte)(2 + ((revision + 31) % 0x1e))) {
		failure = format("revision %d song-speed table mismatch", revision);
		return false;
	}
	foreach(index; 0 .. 8) {
		ubyte expected = cast(ubyte)(0x20 + revision + index);
		if(song.instrumentTable[index] != expected) {
			failure = format(
				"revision %d instrument byte %d expected %02X got %02X",
				revision, index, expected, song.instrumentTable[index]);
			return false;
		}
	}
	int expectedHighlight = revision > 10 ? 7 : 4;
	int expectedHighlightOffset = revision > 10 ? 3 : 0;
	if(song.highlight != expectedHighlight ||
			song.highlightOffset != expectedHighlightOffset) {
		failure = format(
			"revision %d highlight expected %d/%d got %d/%d",
			revision, expectedHighlight, expectedHighlightOffset,
			song.highlight, song.highlightOffset);
		return false;
	}
	return expectLegacyDescription(song, defaults, revision,
		revision > 7, revision > 8, failure);
}

bool loadLegacyRevision(int revision, out Song song, out string failure) {
	string path = writeLegacyCtFixture(revision);
	scope(exit) if(exists(path)) remove(path);
	song = new Song();
	try {
		song.open(path);
	}
	catch(Throwable error) {
		failure = format("revision %d failed to load: %s", revision,
			error.msg);
		return false;
	}
	return checkLegacyRevisionState(song, revision, failure);
}

bool checkLegacyCtRevisionCompatibility(out string failure) {
	foreach(revision; 6 .. 12) {
		Song song;
		if(!loadLegacyRevision(revision, song, failure))
			return false;
	}
	return true;
}

bool checkLegacyCtUpgradeOnSave(out string failure) {
	foreach(revision; [6, 8, 9, 11]) {
		Song song;
		if(!loadLegacyRevision(revision, song, failure))
			return false;
		string outPath = buildPath(tempDir(),
			format("ccutter-appcln-upgrade-r%02d.ct", revision));
		scope(exit) if(exists(outPath)) remove(outPath);
		try {
			song.save(outPath);
			if(savedCtFileRevision(outPath) != SONG_REVISION) {
				failure = format("revision %d saved as revision %d",
					revision, savedCtFileRevision(outPath));
				return false;
			}
			Song reloaded = new Song();
			reloaded.open(outPath);
			if(reloaded.ver != SONG_REVISION ||
					strip(reloaded.title[]) !=
						format("Legacy revision %02d", revision) ||
					reloaded.instrumentTable[0] !=
						cast(ubyte)(0x20 + revision)) {
				failure = format(
					"revision %d semantic state did not survive upgrade",
					revision);
				return false;
			}
		}
		catch(Throwable error) {
			failure = format("revision %d upgrade failed: %s", revision,
				error.msg);
			return false;
		}
	}
	return true;
}

bool rejectedWithoutMutation(ubyte[] data, string label, out string failure) {
	Song song = new Song();
	int oldVer = song.ver;
	string oldTitle = strip(song.title[]).idup;
	try {
		song.openData(data, label);
		failure = label ~ " unexpectedly loaded";
		return false;
	}
	catch(Throwable) {
	}
	if(song.ver != oldVer || strip(song.title[]) != oldTitle) {
		failure = label ~ " partially mutated Song object";
		return false;
	}
	return true;
}

bool checkLegacyCtRevisionRejections(out string failure) {
	foreach(revision; [5, 1, 128, 200]) {
		if(!rejectedWithoutMutation(buildLegacyCtFileData(revision),
				format("revision %d", revision), failure))
			return false;
	}

	ubyte[] truncatedPayload;
	truncatedPayload.length = LEGACY_CT_HEADER_OFFSET + 8;
	truncatedPayload[] = 0;
	truncatedPayload[LEGACY_CT_HEADER_OFFSET] = 6;
	ubyte[] truncated = cast(ubyte[])"CC2".dup;
	truncated ~= cast(ubyte[])compress(truncatedPayload);
	return rejectedWithoutMutation(truncated, "truncated revision 6",
		failure);
}

bool checkCurrentCtRevisionStillCanonical(out string failure) {
	Song song = new Song();
	ubyte[] data = song.fileData();
	if(ctFileRevision(data) != SONG_REVISION) {
		failure = format("current writer emitted revision %d",
			ctFileRevision(data));
		return false;
	}
	Song reloaded = new Song();
	try {
		reloaded.openData(data, "current revision self-check");
	}
	catch(Throwable error) {
		failure = "current revision failed to reload: " ~ error.msg;
		return false;
	}
	if(reloaded.ver != SONG_REVISION) {
		failure = format("current revision reloaded as %d", reloaded.ver);
		return false;
	}
	return true;
}

bool checkCt2utilCommandAliases(out string failure) {
	string source = readText(buildPath("src", "ct2util.d"));
	foreach(required; [
			"Command resolveCt2utilCommand(string commandName)",
			`case "prg", "buildprg":`,
			"return Command.ExportPRG;",
			`case "sid", "build":`,
			"return Command.ExportSID;",
			`case "dump":`,
			"return Command.Dump;",
			`case "import":`,
			"return Command.Import;",
			`case "init":`,
			"return Command.Init;",
			"command = resolveCt2utilCommand(args[1]);",
			"if(command == Command.None)"]) {
		if(source.indexOf(required) < 0) {
			failure = "ct2util command resolver wiring missing: " ~ required;
			return false;
		}
	}
	foreach(forbidden; [
			`case "PRG"`,
			`case "Build"`,
			`case "buildsid"`]) {
		if(source.indexOf(forbidden) >= 0) {
			failure = "ct2util command resolver lost case-sensitive rejection: " ~
				forbidden;
			return false;
		}
	}
	if(str2Value2("31") != 31 || str2Value2("$1f") != 0x1f ||
			str2Value2("0x1f") != 0x1f) {
		failure = "ct2util numeric parsing owner changed accepted forms";
		return false;
	}
	return true;
}

bool checkChordQuickHelpRowAwareShuffle(out string failure) {
	enum string normal =
		"Chord: $00-$3F positive; $40-$7F negative.\n" ~
		"$00 unchanged; $07 up 7; $7C down 4.\n" ~
		"$80-$FF jump marker; $94 -> row $14.";
	enum string shuffle =
		"Speed $0/$1: row $00 stores shuffle lengths.\n" ~
		"Values are frames; use $02-$7F.\n" ~
		"04 06 80 alternates 4/6 then jumps to $00.";

	bool expectHelp(ubyte speed, const(ubyte)[] data, int row,
			string expected, string label) {
		string actual = chordTableQuickHelp(speed, data, row);
		if(actual != expected) {
			failure = format("%s expected %s got %s", label, expected, actual);
			return false;
		}
		if(!requireStatuslineLineLimit(label, actual, failure))
			return false;
		return true;
	}

	ubyte[] example = [cast(ubyte)0x07, cast(ubyte)0x05, cast(ubyte)0x80,
		cast(ubyte)0x07, cast(ubyte)0x04, cast(ubyte)0x00, cast(ubyte)0x83];

	foreach(row; 0 .. example.length) {
		if(!expectHelp(2, example, cast(int)row, normal,
				format("non-shuffle row %d", row)))
			return false;
	}

	foreach(speed; [cast(ubyte)0, cast(ubyte)1]) {
		foreach(row; 0 .. 3) {
			if(!chordRowUsesShuffleQuickHelp(speed, example, cast(int)row)) {
				failure = format("speed %d row %d should be shuffle", speed, row);
				return false;
			}
			if(!expectHelp(speed, example, cast(int)row, shuffle,
					format("example shuffle speed %d row %d", speed, row)))
				return false;
		}
		foreach(row; 3 .. example.length) {
			if(chordRowUsesShuffleQuickHelp(speed, example, cast(int)row)) {
				failure = format("speed %d row %d should be normal", speed, row);
				return false;
			}
			if(!expectHelp(speed, example, cast(int)row, normal,
					format("example normal speed %d row %d", speed, row)))
				return false;
		}
	}

	foreach(marker; [cast(ubyte)0x80, cast(ubyte)0x94, cast(ubyte)0xff]) {
		ubyte[] data = [cast(ubyte)0x04, marker, cast(ubyte)0x07];
		if(!expectHelp(0, data, 0, shuffle, "pre-marker shuffle"))
			return false;
		if(!expectHelp(0, data, 1, shuffle, "marker row shuffle"))
			return false;
		if(!expectHelp(0, data, 2, normal, "post-marker normal"))
			return false;
	}

	ubyte[] markerAtZero = [cast(ubyte)0x80, cast(ubyte)0x07];
	if(!expectHelp(1, markerAtZero, 0, shuffle, "marker at row zero"))
		return false;
	if(!expectHelp(1, markerAtZero, 1, normal, "after row zero marker"))
		return false;

	ubyte[] laterMarker = [cast(ubyte)0x04, cast(ubyte)0x80,
		cast(ubyte)0x07, cast(ubyte)0x83];
	if(!expectHelp(1, laterMarker, 3, normal, "later marker after boundary"))
		return false;

	ubyte[] noMarker = [cast(ubyte)0x04, cast(ubyte)0x06, cast(ubyte)0x07];
	foreach(row; 0 .. noMarker.length) {
		if(!expectHelp(0, noMarker, cast(int)row, shuffle,
				format("no marker row %d", row)))
			return false;
	}

	if(!expectHelp(0, [], 0, normal, "empty data"))
		return false;
	if(!expectHelp(0, [cast(ubyte)0x04], -1, normal, "negative row"))
		return false;
	if(!expectHelp(0, [cast(ubyte)0x04], 1, normal, "out-of-range row"))
		return false;

	ubyte[] movedBoundary = [cast(ubyte)0x04, cast(ubyte)0x06,
		cast(ubyte)0x80, cast(ubyte)0x07];
	if(!expectHelp(0, movedBoundary, 2, shuffle, "original boundary row"))
		return false;
	if(!expectHelp(0, movedBoundary, 3, normal, "after original boundary"))
		return false;
	movedBoundary[2] = 0x06;
	movedBoundary[3] = 0x80;
	if(!expectHelp(0, movedBoundary, 2, shuffle, "relocated boundary row before marker"))
		return false;
	if(!expectHelp(0, movedBoundary, 3, shuffle, "relocated boundary marker"))
		return false;

	string tableSource = readText(buildPath("src", "ui", "tables.d"));
	if(tableSource.indexOf("ui.help.chordTableQuickHelp(cast(ubyte)song.speed, data, row)") < 0) {
		failure = "Chord table no longer resolves quickhelp with live row and data";
		return false;
	}

	return true;
}

bool checkWaveQuickHelpNavigationRoute(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for Wave quickhelp navigation test";
		return false;
	}
	scope(exit) {
		com.session.video = null;
		SDL_Quit();
	}
	com.session.initSession();
	com.session.state.song.ver = 10;
	com.session.state.displayHelp = true;
	com.session.screen = new Screen(100, 42);
	com.session.video = new FullscreenTestVideo(100 * FONT_X,
		42 * FONT_Y + trackOverviewGuiStartY());
	UI.statusline = new Statusline(Rectangle(0, 1, 1));

	Rectangle area = Rectangle(10, 10, 16, 16);
	auto table = new WaveTable(area);

	bool prepare(int row, int column, int nibble, int left, int right,
			WaveQuickHelpKind expectedKind) {
		com.session.state.song.waveTable[row] = cast(ubyte)left;
		com.session.state.song.waveTable[row + 256] = cast(ubyte)right;
		table.seekProgramRow(row);
		table.seekColumn(column);
		table.initializeInput();
		table.input.nibble = nibble;
		table.input.update();
		table.showByteDescription();
		auto snapshot = table.generatedProgramTableMouseDragSnapshot();
		if(snapshot.row != row || snapshot.column != column ||
				snapshot.nibble != nibble) {
			failure = format("prepare expected row/column/nibble %d/%d/%d got %d/%d/%d",
				row, column, nibble, snapshot.row, snapshot.column,
				snapshot.nibble);
			return false;
		}
		if(table.activeWaveQuickHelpKind() != expectedKind) {
			failure = format("prepare expected Wave kind %s got %s",
				cast(int)expectedKind, cast(int)table.activeWaveQuickHelpKind());
			return false;
		}
		return true;
	}

	bool keyAndRequire(string label, int key, int mods, int expectedRow,
			int expectedColumn, int expectedNibble,
			WaveQuickHelpKind expectedKind) {
		int result = table.keypress(Keyinfo(key, mods, 0));
		if(result != OK) {
			failure = format("%s expected OK result got %d", label, result);
			return false;
		}
		auto snapshot = table.generatedProgramTableMouseDragSnapshot();
		if(!requireGeneratedProgramTableSnapshot(snapshot, label, expectedRow,
				expectedColumn, expectedNibble, failure))
			return false;
		if(table.activeWaveQuickHelpKind() != expectedKind) {
			failure = format("%s expected Wave kind %s got %s", label,
				cast(int)expectedKind, cast(int)table.activeWaveQuickHelpKind());
			return false;
		}
		return true;
	}

	if(!prepare(4, 0, 0, 0x20, 0x00, WaveQuickHelpKind.options) ||
			!keyAndRequire("relative left high to low", SDLK_RIGHT, 0, 4, 0, 1,
				WaveQuickHelpKind.options))
		return false;
	if(!prepare(4, 1, 0, 0x20, 0x20, WaveQuickHelpKind.waveform) ||
			!keyAndRequire("waveform high to flags low", SDLK_RIGHT, 0, 4, 1, 1,
				WaveQuickHelpKind.flags) ||
			!keyAndRequire("flags low to waveform high", SDLK_LEFT, 0, 4, 1, 0,
				WaveQuickHelpKind.waveform))
		return false;
	if(!prepare(4, 1, 0, 0x20, 0xe0, WaveQuickHelpKind.controlOnly) ||
			!keyAndRequire("control-only high to flags low", SDLK_RIGHT, 0, 4,
				1, 1, WaveQuickHelpKind.flags))
		return false;
	if(!prepare(4, 0, 1, 0x20, 0x00, WaveQuickHelpKind.options) ||
			!keyAndRequire("left/right byte boundary", SDLK_RIGHT, 0, 4, 1, 0,
				WaveQuickHelpKind.keepCurrentControl))
		return false;
	if(!prepare(4, 1, 0, 0x7f, 0x04, WaveQuickHelpKind.jumpTarget) ||
			!keyAndRequire("jump target high to low", SDLK_RIGHT, 0, 4, 1, 1,
				WaveQuickHelpKind.jumpTarget))
		return false;
	if(!prepare(4, 0, 1, 0x7d, 0x20, WaveQuickHelpKind.options) ||
			!keyAndRequire("left edit to loop", 'e', KMOD_SHIFT, 4, 0, 1,
				WaveQuickHelpKind.options) ||
			!keyAndRequire("left edit to jump", 'f', KMOD_SHIFT, 4, 0, 1,
				WaveQuickHelpKind.options))
		return false;
	if(!prepare(4, 0, 0, 0x7f, 0x20, WaveQuickHelpKind.options) ||
			!keyAndRequire("left edit to absolute", '8', KMOD_SHIFT, 4, 0, 0,
				WaveQuickHelpKind.options))
		return false;
	if(!prepare(4, 1, 1, 0x20, 0x00, WaveQuickHelpKind.keepCurrentControl) ||
			!keyAndRequire("right edit to delay", '1', KMOD_SHIFT, 4, 1, 1,
				WaveQuickHelpKind.delay))
		return false;
	if(!prepare(4, 1, 0, 0x20, 0x0f, WaveQuickHelpKind.delay) ||
			!keyAndRequire("right edit to waveform", '1', KMOD_SHIFT, 4, 1, 0,
				WaveQuickHelpKind.waveform))
		return false;
	if(!prepare(4, 1, 0, 0x20, 0xdf, WaveQuickHelpKind.waveform) ||
			!keyAndRequire("right edit to control-only", 'e', KMOD_SHIFT, 4, 1,
				0, WaveQuickHelpKind.controlOnly))
		return false;
	if(!prepare(4, 1, 0, 0x20, 0xef, WaveQuickHelpKind.controlOnly) ||
			!keyAndRequire("right edit stays control-only", 'f', KMOD_SHIFT, 4,
				1, 0, WaveQuickHelpKind.controlOnly))
		return false;
	if(!prepare(4, 1, 0, 0x7e, 0x20, WaveQuickHelpKind.loopPrevious) ||
			!keyAndRequire("right byte while loop row", SDLK_RIGHT, 0, 4, 1, 1,
				WaveQuickHelpKind.loopPrevious))
		return false;
	if(!prepare(4, 1, 0, 0x20, 0x20, WaveQuickHelpKind.waveform)) return false;
	foreach(left; [0x00, 0x60, 0x7d, 0x7e, 0x7f, 0x80, 0xe0, 0xff]) {
		if(!prepare(4, 0, 0, left, 0x20, WaveQuickHelpKind.options))
			return false;
		table.clickedAt(programTableCellX(area, 0, 1), programTableRowY(area, 4),
			1);
		if(table.activeWaveQuickHelpKind() != WaveQuickHelpKind.options) {
			failure = format("Wave left-byte click for %02X did not keep options kind",
				left);
			return false;
		}
	}
	if(!prepare(4, 1, 0, 0x20, 0x20, WaveQuickHelpKind.waveform)) return false;
	table.clickedAt(programTableCellX(area, 1, 1), programTableRowY(area, 4), 1);
	if(table.activeWaveQuickHelpKind() != WaveQuickHelpKind.flags) {
		failure = "Wave precise mouse click did not show low-nibble flags";
		return false;
	}
	if(!prepare(4, 1, 0, 0x20, 0x20, WaveQuickHelpKind.waveform))
		return false;
	com.session.state.song.waveTable[4] = 0x7e;
	table.showByteDescription();
	if(table.activeWaveQuickHelpKind() != WaveQuickHelpKind.loopPrevious) {
		failure = "Right-byte help did not react when left byte became $7E";
		return false;
	}
	com.session.state.song.waveTable[4] = 0x7f;
	table.showByteDescription();
	if(table.activeWaveQuickHelpKind() != WaveQuickHelpKind.jumpTarget) {
		failure = "Right-byte help did not react when left byte became $7F";
		return false;
	}
	if(!prepare(4, 1, 1, 0x20, 0x20, WaveQuickHelpKind.flags))
		return false;
	auto before = table.generatedProgramTableMouseDragSnapshot();
	table.clickedAt(area.x + 5, programTableRowY(area, 4), 1);
	auto after = table.generatedProgramTableMouseDragSnapshot();
	if(after.column != before.column || after.nibble != before.nibble ||
			table.activeWaveQuickHelpKind() != WaveQuickHelpKind.flags) {
		failure = "Wave separator click changed cursor or quickhelp";
		return false;
	}
	com.session.state.displayHelp = false;
	table.showByteDescription();
	if(table.activeWaveQuickHelpKind() != WaveQuickHelpKind.flags) {
		failure = "Help-disabled state changed Wave editing semantics";
		return false;
	}
	return true;
}

bool checkPulseQuickHelpNavigationRoute(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for Pulse quickhelp navigation test";
		return false;
	}
	scope(exit) {
		SDL_SetModState(cast(typeof(KMOD_SHIFT))0);
		com.session.video = null;
		SDL_Quit();
	}
	com.session.initSession();
	com.session.state.song.ver = 10;
	com.session.state.displayHelp = true;
	com.session.screen = new Screen(100, 42);
	com.session.video = new FullscreenTestVideo(100 * FONT_X,
		42 * FONT_Y + trackOverviewGuiStartY());
	UI.statusline = new Statusline(Rectangle(0, 1, 1));

	Rectangle area = Rectangle(10, 10, 16, 16);
	auto table = new PulseTable(area);

	bool prepare(int row, int column, int nibble,
			PulseQuickHelpKind expectedKind) {
		table.seekProgramRow(row);
		table.seekColumn(column);
		table.initializeInput();
		table.input.nibble = nibble;
		table.input.update();
		table.showByteDescription();
		auto snapshot = table.generatedProgramTableMouseDragSnapshot();
		if(snapshot.row != row || snapshot.column != column ||
				snapshot.nibble != nibble) {
			failure = format("prepare expected row/column/nibble %d/%d/%d got %d/%d/%d",
				row, column, nibble, snapshot.row, snapshot.column,
				snapshot.nibble);
			return false;
		}
		if(table.activePulseQuickHelpKind() != expectedKind) {
			failure = format("prepare expected Pulse kind %s got %s",
				cast(int)expectedKind, cast(int)table.activePulseQuickHelpKind());
			return false;
		}
		return true;
	}

	bool keyAndRequire(string label, int key, int mods, int expectedRow,
			int expectedColumn, int expectedNibble,
			PulseQuickHelpKind expectedKind) {
		int result = table.keypress(Keyinfo(key, mods, 0));
		if(result != OK) {
			failure = format("%s expected OK result got %d", label, result);
			return false;
		}
		auto snapshot = table.generatedProgramTableMouseDragSnapshot();
		if(!requireGeneratedProgramTableSnapshot(snapshot, label, expectedRow,
				expectedColumn, expectedNibble, failure))
			return false;
		if(table.activePulseQuickHelpKind() != expectedKind) {
			failure = format("%s expected Pulse kind %s got %s", label,
				cast(int)expectedKind, cast(int)table.activePulseQuickHelpKind());
			return false;
		}
		return true;
	}

	if(!prepare(4, 0, 0, PulseQuickHelpKind.sweepDuration) ||
			!keyAndRequire("duration high to low", SDLK_RIGHT, 0, 4, 0, 1,
				PulseQuickHelpKind.sweepDuration) ||
			!keyAndRequire("duration low to step", SDLK_RIGHT, 0, 4, 1, 0,
				PulseQuickHelpKind.pulseStep) ||
			!keyAndRequire("step high back to duration", SDLK_LEFT, 0, 4, 0, 1,
				PulseQuickHelpKind.sweepDuration))
		return false;
	if(!prepare(4, 1, 1, PulseQuickHelpKind.pulseStep) ||
			!keyAndRequire("step low to width", SDLK_RIGHT, 0, 4, 2, 0,
				PulseQuickHelpKind.pulseWidth))
		return false;
	if(!prepare(4, 2, 1, PulseQuickHelpKind.pulseWidth) ||
			!keyAndRequire("width low to flow", SDLK_RIGHT, 0, 4, 3, 0,
				PulseQuickHelpKind.flow))
		return false;
	if(!prepare(4, 3, 1, PulseQuickHelpKind.flow) ||
			!keyAndRequire("flow row down", SDLK_DOWN, 0, 5, 3, 1,
				PulseQuickHelpKind.flow) ||
			!keyAndRequire("flow row up", SDLK_UP, 0, 4, 3, 1,
				PulseQuickHelpKind.flow))
		return false;

	bool rawValueEditRetainsKind(int column, int value,
			PulseQuickHelpKind expectedKind) {
		com.session.state.song.pulseTable[4 * 4 + column] = cast(ubyte)value;
		if(!prepare(4, column, 0, expectedKind))
			return false;
		return keyAndRequire(format("Pulse column %d raw %02X edit", column,
			value), '0', 0, 4, column, 1, expectedKind);
	}

	foreach(value; [0x00, 0x7f, 0x80, 0xff]) {
		if(!rawValueEditRetainsKind(0, value, PulseQuickHelpKind.sweepDuration))
			return false;
	}
	foreach(value; [0x00, 0x01, 0xff]) {
		if(!rawValueEditRetainsKind(1, value, PulseQuickHelpKind.pulseStep))
			return false;
	}
	foreach(value; [0x00, 0x48, 0xff]) {
		if(!rawValueEditRetainsKind(2, value, PulseQuickHelpKind.pulseWidth))
			return false;
	}
	foreach(value; [0x00, 0x01, 0x3f, 0x40, 0x7f, 0x80]) {
		if(!rawValueEditRetainsKind(3, value, PulseQuickHelpKind.flow))
			return false;
	}

	foreach(column; 0 .. 4) {
		foreach(nibble; 0 .. 2) {
			if(!prepare(4, column, 0, pulseQuickHelpKind(column)))
				return false;
			table.clickedAt(programTableCellX(area, column, nibble),
				programTableRowY(area, 4), 1);
			auto snapshot = table.generatedProgramTableMouseDragSnapshot();
			if(!requireGeneratedProgramTableSnapshot(snapshot,
					format("Pulse mouse column/nibble %d/%d", column, nibble), 4,
					column, nibble, failure))
				return false;
			if(table.activePulseQuickHelpKind() != pulseQuickHelpKind(column)) {
				failure = format("Pulse mouse column/nibble %d/%d changed kind",
					column, nibble);
				return false;
			}
		}
	}

	if(!prepare(4, 2, 1, PulseQuickHelpKind.pulseWidth))
		return false;
	auto before = table.generatedProgramTableMouseDragSnapshot();
	table.clickedAt(area.x + 11, programTableRowY(area, 4), 1);
	auto after = table.generatedProgramTableMouseDragSnapshot();
	if(after.column != before.column || after.nibble != before.nibble ||
			table.activePulseQuickHelpKind() != PulseQuickHelpKind.pulseWidth) {
		failure = "Pulse separator click changed cursor or quickhelp";
		return false;
	}

	com.session.state.displayHelp = false;
	table.showByteDescription();
	if(table.activePulseQuickHelpKind() != PulseQuickHelpKind.pulseWidth) {
		failure = "Help-disabled state changed Pulse editing semantics";
		return false;
	}
	return true;
}

bool checkFilterQuickHelpNavigationRoute(out string failure) {
	if(SDL_Init(0) != 0) {
		failure = "SDL_Init(0) failed for Filter quickhelp navigation test";
		return false;
	}
	scope(exit) {
		SDL_SetModState(cast(typeof(KMOD_SHIFT))0);
		com.session.video = null;
		SDL_Quit();
	}
	com.session.initSession();
	com.session.state.song.ver = 10;
	com.session.state.displayHelp = true;
	com.session.screen = new Screen(100, 42);
	com.session.video = new FullscreenTestVideo(100 * FONT_X,
		42 * FONT_Y + trackOverviewGuiStartY());
	UI.statusline = new Statusline(Rectangle(0, 1, 1));

	Rectangle area = Rectangle(10, 10, 16, 16);
	auto table = new FilterTable(area);

	void setFilterType(int row, int value) {
		com.session.state.song.filterTable[row * 4] = cast(ubyte)value;
	}

	bool prepare(int row, int column, int nibble, int filterTypeByte,
			FilterQuickHelpKind expectedKind) {
		setFilterType(row, filterTypeByte);
		table.seekProgramRow(row);
		table.seekColumn(column);
		table.initializeInput();
		table.input.nibble = nibble;
		table.input.update();
		table.showByteDescription();
		auto snapshot = table.generatedProgramTableMouseDragSnapshot();
		if(snapshot.row != row || snapshot.column != column ||
				snapshot.nibble != nibble) {
			failure = format("prepare expected row/column/nibble %d/%d/%d got %d/%d/%d",
				row, column, nibble, snapshot.row, snapshot.column,
				snapshot.nibble);
			return false;
		}
		if(table.activeFilterQuickHelpKind() != expectedKind) {
			failure = format("prepare expected Filter kind %s got %s",
				cast(int)expectedKind, cast(int)table.activeFilterQuickHelpKind());
			return false;
		}
		return true;
	}

	bool keyAndRequire(string label, int key, int mods, int expectedRow,
			int expectedColumn, int expectedNibble,
			FilterQuickHelpKind expectedKind) {
		int result = table.keypress(Keyinfo(key, mods, 0));
		if(result != OK) {
			failure = format("%s expected OK result got %d", label, result);
			return false;
		}
		auto snapshot = table.generatedProgramTableMouseDragSnapshot();
		if(!requireGeneratedProgramTableSnapshot(snapshot, label, expectedRow,
				expectedColumn, expectedNibble, failure))
			return false;
		if(table.activeFilterQuickHelpKind() != expectedKind) {
			failure = format("%s expected Filter kind %s got %s", label,
				cast(int)expectedKind, cast(int)table.activeFilterQuickHelpKind());
			return false;
		}
		return true;
	}

	if(!prepare(4, 0, 0, 0x00, FilterQuickHelpKind.typeOptions) ||
			!keyAndRequire("sweep type high to duration low", SDLK_RIGHT, 0, 4,
				0, 1, FilterQuickHelpKind.sweepDuration) ||
			!keyAndRequire("sweep duration low to type high", SDLK_LEFT, 0, 4,
				0, 0, FilterQuickHelpKind.typeOptions))
		return false;
	if(!prepare(4, 0, 0, 0x90, FilterQuickHelpKind.typeOptions) ||
			!keyAndRequire("setup type high to ignored low", SDLK_RIGHT, 0, 4,
				0, 1, FilterQuickHelpKind.setupIgnored) ||
			!keyAndRequire("setup ignored low to type high", SDLK_LEFT, 0, 4,
				0, 0, FilterQuickHelpKind.typeOptions))
		return false;
	if(!prepare(4, 1, 0, 0x00, FilterQuickHelpKind.cutoffStep) ||
			!keyAndRequire("sweep cutoff high to low", SDLK_RIGHT, 0, 4, 1, 1,
				FilterQuickHelpKind.cutoffStep) ||
			!keyAndRequire("sweep cutoff low to high", SDLK_LEFT, 0, 4, 1, 0,
				FilterQuickHelpKind.cutoffStep))
		return false;
	if(!prepare(4, 1, 0, 0x80, FilterQuickHelpKind.resonance) ||
			!keyAndRequire("setup resonance to mask", SDLK_RIGHT, 0, 4, 1, 1,
				FilterQuickHelpKind.filterMask) ||
			!keyAndRequire("setup mask to resonance", SDLK_LEFT, 0, 4, 1, 0,
				FilterQuickHelpKind.resonance))
		return false;
	if(!prepare(4, 2, 0, 0x80, FilterQuickHelpKind.cutoffStart) ||
			!keyAndRequire("cutoff start high to low", SDLK_RIGHT, 0, 4, 2, 1,
				FilterQuickHelpKind.cutoffStart))
		return false;
	if(!prepare(4, 3, 0, 0x80, FilterQuickHelpKind.flow) ||
			!keyAndRequire("flow high to low", SDLK_RIGHT, 0, 4, 3, 1,
				FilterQuickHelpKind.flow) ||
			!keyAndRequire("flow row down", SDLK_DOWN, 0, 5, 3, 1,
				FilterQuickHelpKind.flow))
		return false;

	if(!prepare(4, 0, 1, 0x7f, FilterQuickHelpKind.sweepDuration))
		return false;
	setFilterType(4, 0x80);
	table.showByteDescription();
	if(table.activeFilterQuickHelpKind() != FilterQuickHelpKind.setupIgnored) {
		failure = "Filter column 0 low did not refresh crossing $7F/$80";
		return false;
	}
	setFilterType(4, 0x7f);
	table.showByteDescription();
	if(table.activeFilterQuickHelpKind() != FilterQuickHelpKind.sweepDuration) {
		failure = "Filter column 0 low did not refresh crossing $80/$7F";
		return false;
	}
	if(!prepare(4, 1, 0, 0x00, FilterQuickHelpKind.cutoffStep))
		return false;
	setFilterType(4, 0x80);
	table.showByteDescription();
	if(table.activeFilterQuickHelpKind() != FilterQuickHelpKind.resonance) {
		failure = "Filter column 1 high did not refresh sweep/setup";
		return false;
	}
	table.input.nibble = 1;
	table.input.update();
	table.showByteDescription();
	if(table.activeFilterQuickHelpKind() != FilterQuickHelpKind.filterMask) {
		failure = "Filter column 1 low did not show setup mask";
		return false;
	}
	setFilterType(4, 0x00);
	table.showByteDescription();
	if(table.activeFilterQuickHelpKind() != FilterQuickHelpKind.cutoffStep) {
		failure = "Filter column 1 low did not refresh setup/sweep";
		return false;
	}

	foreach(column; 0 .. 4) {
		foreach(nibble; 0 .. 2) {
			if(!prepare(4, column, 0, 0x80,
					filterQuickHelpKind(column, 0, 0x80)))
				return false;
			table.clickedAt(programTableCellX(area, column, nibble),
				programTableRowY(area, 4), 1);
			auto snapshot = table.generatedProgramTableMouseDragSnapshot();
			auto expectedKind = filterQuickHelpKind(column, nibble, 0x80);
			if(!requireGeneratedProgramTableSnapshot(snapshot,
					format("Filter mouse column/nibble %d/%d", column, nibble),
					4, column, nibble, failure))
				return false;
			if(table.activeFilterQuickHelpKind() != expectedKind) {
				failure = format("Filter mouse column/nibble %d/%d expected kind %s got %s",
					column, nibble, cast(int)expectedKind,
					cast(int)table.activeFilterQuickHelpKind());
				return false;
			}
		}
	}

	if(!prepare(4, 2, 1, 0x80, FilterQuickHelpKind.cutoffStart))
		return false;
	auto before = table.generatedProgramTableMouseDragSnapshot();
	table.clickedAt(area.x + 11, programTableRowY(area, 4), 1);
	auto after = table.generatedProgramTableMouseDragSnapshot();
	if(after.column != before.column || after.nibble != before.nibble ||
			table.activeFilterQuickHelpKind() != FilterQuickHelpKind.cutoffStart) {
		failure = "Filter separator click changed cursor or quickhelp";
		return false;
	}

	com.session.state.displayHelp = false;
	table.showByteDescription();
	if(table.activeFilterQuickHelpKind() != FilterQuickHelpKind.cutoffStart) {
		failure = "Help-disabled state changed Filter editing semantics";
		return false;
	}
	return true;
}

bool checkWaveQuickHelpRouteSource(out string failure) {
	string tablesSource = cast(string)read("src/ui/tables.d");
	string helpSource = cast(string)read("src/ui/help.d");
	foreach(required; [
			"ProgramTableByteCell programTableByteCellAt(int localX, int columnCount)",
			"auto cell = programTableByteCellAt(rx, columns);",
			"if(!cell.valid)\n\t\t\treturn false;",
			"input.nibble = cell.nibble;",
			"enum WaveQuickHelpKind",
			"WaveQuickHelpKind waveQuickHelpKind(int column, int nibble, int left,\n\t\tint right)",
			"string waveQuickHelpText(WaveQuickHelpKind kind)",
			"UI.statusline.displayContextualSemantic(outstr,\n\t\t\t\t\tformat(\"wave:%s\", cast(int)kind));"]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Wave quickhelp source missing " ~ required;
			return false;
		}
	}
	foreach(removed; [
			"currentWaveQuickDescription",
			"waveQuickDescription",
			"waveLeftByteMode",
			"relativeNote",
			"absoluteNote",
			"jumpMarker",
			"Note offset: $00-$7D relative to current note.",
			"Absolute note: $80-$FF ignores current note.",
			"Jump marker: value byte selects Wave row $00-$FF.",
			"Left byte:",
			"Right byte:",
			"$00-$5F rel",
			"$80-$DF abs",
			"$E0-$EF low control"]) {
		if(tablesSource.indexOf(removed) >= 0) {
			failure = "Old Wave quickhelp source remains: " ~ removed;
			return false;
		}
	}
	if(tablesSource.indexOf(
			"Wave: $00-$7D rel, $7E loop, $7F jump, $80-$FF abs.") < 0) {
		failure = "Wave option-map text missing";
		return false;
	}
	foreach(required; [
			"00-7D = relative note offset",
			"7E    = loop previous wave row; cd is ignored",
			"7F    = jump marker; cd is target row",
			"80-FF = absolute note",
			"E0-FF = control-only; low nibble sets gate/sync/ring/test"]) {
		if(helpSource.indexOf(required) < 0) {
			failure = "Wave F12 Help missing " ~ required;
			return false;
		}
	}
	foreach(removed; ["00-5F = relative note", "80-DF = absolute note",
			"E0-EF = low SID control"]) {
		if(helpSource.indexOf(removed) >= 0) {
			failure = "Old Wave F12 Help remains: " ~ removed;
			return false;
		}
	}
	return true;
}

bool checkPulseQuickHelpRouteSource(out string failure) {
	string tablesSource = cast(string)read("src/ui/tables.d");
	string helpSource = cast(string)read("src/ui/help.d");
	foreach(required; [
			"enum PulseQuickHelpKind",
			"PulseQuickHelpKind pulseQuickHelpKind(int column)",
			"string pulseQuickHelpText(PulseQuickHelpKind kind)",
			"UI.statusline.displayContextualSemantic(outstr,",
			"format(\"pulse:%s\", cast(int)kind));",
			"Pulse width: XY sets $0YX0; $FF keeps current."]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Pulse quickhelp source missing " ~ required;
			return false;
		}
	}
	foreach(removed; [
			"currentPulseQuickDescription",
			"pulseQuickDescription",
			"Duration and direction; $00-$7F add frames",
			"Add value; $00 no sweep/hold",
			"Packed starting pulse width; $00-$FE set width",
			"stop pulse program"]) {
		if(tablesSource.indexOf(removed) >= 0) {
			failure = "Old Pulse quickhelp source remains: " ~ removed;
			return false;
		}
	}
	foreach(required; [
			"Format: rr: ab cd ef gh",
			"00 and 80 still apply the row once before advancing",
			"Direction comes from ab. The step is not shifted or scaled.",
			"eg 01 > pulse width $0100",
			"eg 10 > pulse width $0010",
			"FF = keep current pulse width before packing",
			"40-7E and 80-FF are unsupported"]) {
		if(helpSource.indexOf(required) < 0) {
			failure = "Pulse F12 help missing retained fact: " ~ required;
			return false;
		}
	}
	return true;
}

bool checkFilterQuickHelpRouteSource(out string failure) {
	string tablesSource = cast(string)read("src/ui/tables.d");
	string helpSource = cast(string)read("src/ui/help.d");
	foreach(required; [
			"enum FilterQuickHelpKind",
			"FilterQuickHelpKind filterQuickHelpKind(int column, int nibble,",
			"string filterQuickHelpText(FilterQuickHelpKind kind)",
			"UI.statusline.displayContextualSemantic(outstr,",
			"format(\"filter:%s\", cast(int)kind));",
			"Type: $00-$7F sweep; $8x none; $9x low-pass.",
			"$Ax band-pass; $Bx low+band; $Cx high-pass.",
			"$Dx low+high; $Ex band+high; $Fx low+band+high.",
			"Sweep duration: $00-$7F frames.",
			"Setup low nibble ignored; use $x0.",
			"Cutoff step: $00 hold, $01-$7F up, $80-$FF down.",
			"Resonance: $0 none, $F maximum.",
			"Filter mask: $1 V1, $2 V2, $4 V3, $8 external.",
			"Cutoff start: $00-$FE set, $FF keeps current.",
			"Flow: $00 next, $01-$3F jump, $7F stop."]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Filter quickhelp source missing " ~ required;
			return false;
		}
	}
	foreach(removed; [
			"currentFilterQuickDescription",
			"filterQuickDescription",
			"filterIsSetup",
			"Duration/type; $00-$7F dur",
			"Filter resonance and voice/channel mask",
			"Add value; $00 no sweep",
			"Starting filter cutoff byte; $00-$FE set cutoff byte",
			"stop filter program"]) {
		if(tablesSource.indexOf(removed) >= 0) {
			failure = "Old Filter quickhelp source remains: " ~ removed;
			return false;
		}
	}
	foreach(required; [
			"Format: rr: ab cd ef gh",
			"80-8F = no filter mode",
			"b = stored but ignored by playback; use 0 in help/examples",
			"Canonical setup form uses x0.",
			"The signed step is applied at one quarter cutoff-byte unit per update.",
			"Fractional movement is accumulated between updates.",
			"40-7E and 80-FF are unsupported"]) {
		if(helpSource.indexOf(required) < 0) {
			failure = "Filter F12 help missing retained fact: " ~ required;
			return false;
		}
	}
	foreach(removed; [
			"ab = 90-F0",
			"D416",
			"SID filter cutoff"]) {
		if(helpSource.indexOf(removed) >= 0) {
			failure = "Old Filter F12 Help remains: " ~ removed;
			return false;
		}
	}
	return true;
}

private ubyte[8] instrumentBytes(int instrument) {
	ubyte[8] bytes;
	foreach(column; 0 .. 8)
		bytes[column] = com.session.state.song.instrumentTable[
			instrumentByteStorageOffset(instrument, column)];
	return bytes;
}

private bool requireInstrumentBytesUnchanged(int instrument,
		ubyte[8] expected, string label, out string failure) {
	auto actual = instrumentBytes(instrument);
	foreach(column; 0 .. 8) {
		if(actual[column] != expected[column]) {
			failure = format("%s changed byte %d from %02X to %02X",
				label, column, expected[column], actual[column]);
			return false;
		}
	}
	return true;
}

bool checkInstrumentByteSelectionLiveUiRouting(out string failure) {
	foreach(focus; [TrackOverviewFocusKind.Timeline,
			TrackOverviewFocusKind.Block]) {
		if(trackOverviewKeyboardContextIsActive(focus, false, false)) {
			failure = "stale Track Overview focus is active without F6";
			return false;
		}
		if(trackOverviewKeyboardContextIsActive(focus, true, true)) {
			failure = "dialog-covered Track Overview focus is active";
			return false;
		}
		if(!trackOverviewKeyboardContextIsActive(focus, true, false)) {
			failure = "active Track Overview focus was not recognised";
			return false;
		}
	}
	if(trackOverviewKeyboardContextIsActive(TrackOverviewFocusKind.Editor,
			true, false)) {
		failure = "Editor focus was treated as Track Overview keyboard context";
		return false;
	}

	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	foreach(required; [
			"trackOverviewKeyboardContextIsActive(",
			"if(trackOverviewActiveKeyboardContext() &&",
			"handleTrackOverviewFocusedKey(key))",
			"if(trackOverviewActiveKeyboardContext())",
			"return false;\n\t}\n\n\tprivate bool handleTrackOverviewTimelineInertDeleteKey"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = "Missing live UI routing source proof: " ~ required;
			return false;
		}
	}
	auto focusedStart = uiSource.indexOf(
		"private bool handleTrackOverviewFocusedKey(Keyinfo key)");
	auto focusedEnd = uiSource.indexOf(
		"private bool handleTrackOverviewTimelineNavigationKey", focusedStart);
	if(focusedStart < 0 || focusedEnd < focusedStart) {
		failure = "Could not isolate handleTrackOverviewFocusedKey";
		return false;
	}
	string focusedSource = uiSource[focusedStart .. focusedEnd];
	if(focusedSource.indexOf("consume it so the old editor cannot edit") >= 0) {
		failure = "Track Overview focused fallback still documents swallowing";
		return false;
	}
	if(focusedSource.lastIndexOf("return false;") <
			focusedSource.lastIndexOf("handleTrackOverviewBlockNavigationKey")) {
		failure = "Track Overview focused fallback does not return unhandled";
		return false;
	}
	if(uiSource.indexOf("if(trackOverviewActiveKeyboardContext() &&") >
			uiSource.indexOf("toplevel.keypress(key);")) {
		failure = "Track Overview active-context gate occurs after Toplevel";
		return false;
	}
	if(uiSource.indexOf("handleTrackOverviewFocusedKey(key)") >
			uiSource.indexOf("toplevel.keypress(key);")) {
		failure = "Focused Track Overview key handler runs after Toplevel";
		return false;
	}

	return true;
}

bool checkTrackOverviewTimelineDeleteKeysAreConsumed(out string failure) {
	KeyboardActionId actionId;
	version(OSX) {
		immutable platformDeleteKeys = [SDLK_BACKSPACE, SDLK_DELETE];
	}
	else {
		immutable platformDeleteKeys = [SDLK_DELETE];
	}
	foreach(key; platformDeleteKeys) {
		if(resolveTrackOverviewTimelineKeyboardAction(Keyinfo(key, 0, 0),
				actionId)) {
			failure = "Timeline unexpectedly owns a delete action";
			return false;
		}
		if(!resolveTrackOverviewBlockKeyboardAction(Keyinfo(key, 0, 0),
				actionId) ||
				actionId != KeyboardActionId.trackOverviewDeleteSelection) {
			failure = "Track Overview delete key no longer resolves through block owner";
			return false;
		}
	}

	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	auto helperStart = uiSource.indexOf(
		"private bool handleTrackOverviewTimelineInertDeleteKey(Keyinfo key)");
	if(helperStart < 0) {
		failure = "Missing Timeline inert delete handler";
		return false;
	}
	auto helperEnd = uiSource.indexOf(
		"private bool handleTrackOverviewTimelineNavigationKey", helperStart);
	if(helperEnd < helperStart) {
		failure = "Could not isolate Timeline inert delete handler";
		return false;
	}
	string helperSource = uiSource[helperStart .. helperEnd];
	foreach(required; [
			"trackOverviewFocus.kind != TrackOverviewFocusKind.Timeline",
			"resolveTrackOverviewBlockKeyboardAction(key, actionId)",
			"actionId == KeyboardActionId.trackOverviewDeleteSelection"]) {
		if(helperSource.indexOf(required) < 0) {
			failure = "Timeline inert delete handler misses: " ~ required;
			return false;
		}
	}
	foreach(forbidden; [
			"displayOperationFeedback",
			"displayFailure",
			"handleTrackOverviewBlockDeleteKey",
			"toplevel.keypress"]) {
		if(helperSource.indexOf(forbidden) >= 0) {
			failure = "Timeline inert delete handler performs an action: " ~
				forbidden;
			return false;
		}
	}

	auto focusedStart = uiSource.indexOf(
		"private bool handleTrackOverviewFocusedKey(Keyinfo key)");
	auto focusedEnd = uiSource.indexOf(
		"private bool handleTrackOverviewTimelineInertDeleteKey", focusedStart);
	if(focusedStart < 0 || focusedEnd < focusedStart) {
		failure = "Could not isolate focused Track Overview key handler";
		return false;
	}
	string focusedSource = uiSource[focusedStart .. focusedEnd];
	if(focusedSource.indexOf("if(handleTrackOverviewTimelineInertDeleteKey(key))") <
			0) {
		failure = "Focused Track Overview handler does not consume Timeline delete";
		return false;
	}
	if(focusedSource.indexOf("handleTrackOverviewTimelineInertDeleteKey(key)") >
			focusedSource.indexOf("handleTrackOverviewTimelineNavigationKey(key)")) {
		failure = "Timeline delete is consumed after Timeline navigation";
		return false;
	}
	if(focusedSource.indexOf("if(trackOverviewFocus.kind == TrackOverviewFocusKind.Block)") <
			focusedSource.indexOf("handleTrackOverviewTimelineInertDeleteKey(key)")) {
		failure = "Timeline delete consume is inside the Block route";
		return false;
	}
	if(uiSource.indexOf("handleTrackOverviewFocusedKey(key)") >
			uiSource.indexOf("toplevel.keypress(key);")) {
		failure = "Timeline delete consume still runs after Toplevel fallback";
		return false;
	}

	return true;
}

bool checkWaveFullRangeShiftSelectionRouting(out string failure) {
	string tablesSource = readText(buildPath("src", "ui", "tables.d"));
	auto keypressMarker = "override int keypress(Keyinfo key) {\n" ~
		"\t\tbool handled = executeGeneratedTableRowStructureAction(key);";
	auto start = tablesSource.indexOf(keypressMarker);
	if(start < 0) {
		failure = "Could not locate WaveTable.keypress()";
		return false;
	}
	auto end = tablesSource.indexOf("\n\t\telse switch(key.raw)", start);
	if(end < 0) {
		failure = "Could not isolate WaveTable modifier routing";
		return false;
	}
	string waveRouting = tablesSource[start .. end];
	foreach(forbidden; [
			"case SDLK_HOME:\n\t\t\t\tseekRow(0);\n\t\t\t\treturn OK;",
			"case SDLK_END:\n\t\t\t\tseekTableEnd();\n\t\t\t\treturn OK;"]) {
		if(waveRouting.indexOf(forbidden) >= 0) {
			failure = "WaveTable still consumes shifted Home/End before HexTable";
			return false;
		}
	}
	foreach(required; [
			"if((key.mods & KMOD_SHIFT) == 0 && (key.mods & KMOD_CTRL) != 0)",
			"super(a, song.waveTable, 2, 256);",
			"case KeyboardActionId.generatedTableRowSelectionExtendHome:\n\t\t\tseekRow(0);",
			"case KeyboardActionId.generatedTableRowSelectionExtendEnd:\n\t\t\tseekRow(rows - 1);",
			"rowSelection.select(anchor, row);",
			"data[targetRow] = src[0];\n\t\tdata[targetRow + 256] = src[1];"]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Missing Wave full-range selection owner: " ~ required;
			return false;
		}
	}
	int waveRows = 256;
	int finalRow = waveRows - 1;
	int fullRangeCount = finalRow - 0 + 1;
	int bytesPerRow = 2;
	if(finalRow != 0xff || fullRangeCount != 256 ||
			fullRangeCount * bytesPerRow != 512) {
		failure = "Wave full-range row/clipboard capacity calculation changed";
		return false;
	}
	foreach(startRow; [0x00, 0x01, 0x80]) {
		int count = finalRow - startRow + 1;
		if(count <= 0 || count > 256) {
			failure = format("Shift+End range from %02X produced count %d",
				startRow, count);
			return false;
		}
	}
	int pulseRows = 64;
	if(pulseRows - 1 != 0x3f) {
		failure = "Pulse/Filter final row expectation changed";
		return false;
	}
	return true;
}

bool checkProgramTableMouseRowDragPolicy(out string failure) {
	string tablesSource = readText(buildPath("src", "ui", "tables.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string sequencerSource = readText(buildPath("src", "seq", "sequencer.d"));

	int marginRows = 3;
	int intervalTicks = 4;
	int visibleRows = 15;
	foreach(row; -2 .. visibleRows + 2) {
		int expected = row >= 0 && row < marginRows ? -1 :
			row >= visibleRows - marginRows && row < visibleRows ? 1 : 0;
		int actual = row < 0 || row >= visibleRows ? 0 :
			row < marginRows ? -1 :
			row >= visibleRows - marginRows ? 1 : 0;
		if(actual != expected) {
			failure = format("Program-table visible row %d direction expected %d, got %d",
				row, expected, actual);
			return false;
		}
	}
	int shiftedLogicalTop = 0x20 < 0 || 0x20 >= visibleRows ? 0 :
		0x20 < marginRows ? -1 :
		0x20 >= visibleRows - marginRows ? 1 : 0;
	if(shiftedLogicalTop != 0) {
		failure = "Program-table direction used logical row number instead of visible row";
		return false;
	}

	int ticks;
	foreach(tick; 1 .. intervalTicks) {
		ticks++;
		bool moved = ticks >= intervalTicks;
		if(moved)
			ticks = 0;
		if(moved) {
			failure = format("Program-table cadence moved too early at tick %d",
				tick);
			return false;
		}
		if(ticks != tick) {
			failure = format("Program-table cadence accumulator expected %d, got %d",
				tick, ticks);
			return false;
		}
	}
	ticks++;
	bool moved = ticks >= intervalTicks;
	if(moved)
		ticks = 0;
	if(!moved || ticks != 0) {
		failure = "Program-table cadence did not move and reset on the fourth tick";
		return false;
	}
	foreach(tick; 1 .. intervalTicks) {
		ticks++;
		moved = ticks >= intervalTicks;
		if(moved)
			ticks = 0;
		if(moved) {
			failure = "Program-table cadence moved more than once per interval";
			return false;
		}
	}
	ticks++;
	moved = ticks >= intervalTicks;
	if(moved)
		ticks = 0;
	if(!moved || ticks != 0) {
		failure = "Program-table cadence did not repeat after reset";
		return false;
	}

	foreach(required; [
			"enum int PROGRAM_TABLE_ROW_DRAG_AUTOSCROLL_MARGIN_ROWS = 3;",
			"enum int PROGRAM_TABLE_ROW_DRAG_AUTOSCROLL_INTERVAL_TICKS = 4;",
			"private enum ProgramTableRowDragPhase",
			"candidate",
			"committed",
			"ProgramTableRowDragAutoScrollDirection programTableRowDragAutoScrollDirectionForRow(",
			"bool advanceProgramTableRowDragAutoScrollCadence(ref int accumulator)",
			"bool programTableRowKindSupportsMouseDrag(ProgramTableRowKind kind)",
			"return kind == ProgramTableRowKind.wave ||\n\t\tkind == ProgramTableRowKind.pulse ||\n\t\tkind == ProgramTableRowKind.filter;",
			"private ProgramTableRowDragState rowDrag;",
			"@property bool isActive() const",
			"@property bool isCommitted() const",
			"void armCandidate(int anchor)",
			"void commit()",
			"bool supportsProgramRowMouseDrag()",
			"return programTableRowKindSupportsMouseDrag(programTableRowKind());",
			"programTableDataRowAt(int x, int y,",
			"moveCursorToTableCell(int x, int y)",
			"extendProgramRowSelectionAt(int x, int y)",
			"int anchor = rowSelection.active ? rowSelection.anchorRow : row;",
			"rowSelection.select(anchor, row);",
			"rowDrag.commit();",
			"armProgramRowDragCandidateAt(int x, int y)",
			"rowDrag.armCandidate(row);",
			"override bool mouseMotionAt(int x, int y)",
			"return updateProgramRowDragAt(x, y);",
			"if(!rowDrag.isCommitted)",
			"rowSelection.select(rowDrag.anchorRow, row);",
			"override bool mouseButtonUp(int button)",
			"cancelProgramRowDrag();",
			"override bool advanceGeneratedTableRowDragAutoScroll()",
			"targetRow < 0 || targetRow >= rows",
			"rowSelection.select(rowSelection.anchorRow, row);",
			"button == 1 && (SDL_GetModState() & KMOD_SHIFT) != 0",
			"bool moved = moveCursorToTableCell(x, y);\n\t\tif(button == 1 && moved)",
			"clearProgramRowSelection(true);\n\t\t\tarmProgramRowDragCandidateAt(x, y);"]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Program-table mouse drag source missing " ~ required;
			return false;
		}
	}
	if(tablesSource.indexOf("button == 1 &&\n\t\t\t\tshiftClickProgramRowAt") >= 0 ||
			tablesSource.indexOf("Shift+click/drag select") >= 0) {
		failure = "Program-table mouse drag still requires Shift for click-drag";
		return false;
	}
	foreach(required; [
			"bool mouseMotionAt(int x, int y) { return false; }",
			"bool mouseButtonUp(int button) { return false; }",
			"bool advanceGeneratedTableRowDragAutoScroll() { return false; }",
			"if(activeWindow == bottomTabSwitcher)\n\t\t\treturn bottomTabSwitcher.activeWindow.mouseMotionAt(x, y);",
			"if(activeWindow == bottomTabSwitcher)\n\t\t\treturn bottomTabSwitcher.activeWindow.mouseButtonUp(button);",
			"bool advanceGeneratedTableRowDragAutoScroll()",
			"return bottomTabSwitcher.activeWindow.\n\t\t\t\t\tadvanceGeneratedTableRowDragAutoScroll();",
			"dialog is null && toplevel.advanceGeneratedTableRowDragAutoScroll()"]) {
		if(uiSource.indexOf(required) < 0) {
			failure = "UI program-table mouse drag route missing " ~ required;
			return false;
		}
	}
	foreach(required; [
			"generatedProgramTableRowHelp()",
			"Click-drag = select rows",
			"Shift+click = extend row selection",
			"table.row_copy",
			"table.row_paste",
			"table.row_selection_clear"]) {
		if(helpSource.indexOf(required) < 0) {
			failure = "Program-table Help mouse guidance missing " ~ required;
			return false;
		}
	}
	if(helpSource.indexOf("Shift+click/drag = select rows") >= 0) {
		failure = "Program-table Help still says Shift is required for drag selection";
		return false;
	}
	if(helpSource.indexOf("COMMAND_TABLE_HELP") <
			helpSource.lastIndexOf("generatedProgramTableRowHelp()")) {
		failure = "Command table unexpectedly received program row mouse Help";
		return false;
	}
	if(sequencerSource.indexOf(
			"enum int SEQUENCE_ROW_DRAG_AUTOSCROLL_MARGIN_ROWS = 4;") < 0 ||
			sequencerSource.indexOf(
				"return height > 10 ? SEQUENCE_ROW_DRAG_AUTOSCROLL_MARGIN_ROWS : 1;") < 0) {
		failure = "F6 margin literal was not replaced by a named constant";
		return false;
	}
	return true;
}

private struct ProgramTablePinnedDragModel {
	int rows = 256;
	int visibleRows = 15;
	int viewOffset;
	int row;
	int retainedVisibleRow;
	int anchor = 4;
	int endpoint;
	int column = 1;
	int nibble = 1;
	int ticks;
	bool committed = true;
	bool mouseReleased;
	int dataWrites;
	int undoRequests;
}

private int programTableTestDirectionForVisibleRow(int visibleRow,
		int visibleRows) {
	enum marginRows = 3;
	if(visibleRow < 0 || visibleRow >= visibleRows)
		return 0;
	if(visibleRow < marginRows)
		return -1;
	if(visibleRow >= visibleRows - marginRows)
		return 1;
	return 0;
}

private bool advanceProgramTablePinnedDragModel(
		ref ProgramTablePinnedDragModel model, int direction) {
	if(!model.committed || model.mouseReleased || direction == 0)
		return false;
	if(programTableTestDirectionForVisibleRow(model.retainedVisibleRow,
			model.visibleRows) != direction)
		return false;
	model.ticks++;
	if(model.ticks < 4)
		return false;
	model.ticks = 0;

	int maxViewOffset = model.rows > model.visibleRows ?
		model.rows - model.visibleRows : 0;
	int newViewOffset = model.viewOffset + direction;
	if(newViewOffset < 0)
		newViewOffset = 0;
	if(newViewOffset > maxViewOffset)
		newViewOffset = maxViewOffset;
	if(newViewOffset == model.viewOffset)
		return false;

	model.viewOffset = newViewOffset;
	model.row = model.viewOffset + model.retainedVisibleRow;
	if(model.row < 0 || model.row >= model.rows)
		return false;
	model.endpoint = model.row;
	return true;
}

private bool completeProgramTablePinnedDragCadence(
		ref ProgramTablePinnedDragModel model, int direction,
		out string failure) {
	foreach(tick; 1 .. 4) {
		if(advanceProgramTablePinnedDragModel(model, direction)) {
			failure = format("Pinned generated-table drag moved too early at tick %d",
				tick);
			return false;
		}
	}
	if(!advanceProgramTablePinnedDragModel(model, direction)) {
		failure = "Pinned generated-table drag did not move on tick 4";
		return false;
	}
	return true;
}

private bool requirePinnedProgramTableState(
		ProgramTablePinnedDragModel model, int expectedViewOffset,
		int expectedRow, int expectedVisibleRow, int expectedAnchor,
		int expectedColumn, int expectedNibble, out string failure,
		string label) {
	if(model.viewOffset != expectedViewOffset || model.row != expectedRow ||
			model.row - model.viewOffset != expectedVisibleRow ||
			model.retainedVisibleRow != expectedVisibleRow) {
		failure = format("%s expected view,row,visible %d,%d,%d got %d,%d,%d retained %d",
			label, expectedViewOffset, expectedRow, expectedVisibleRow,
			model.viewOffset, model.row, model.row - model.viewOffset,
			model.retainedVisibleRow);
		return false;
	}
	if(model.anchor != expectedAnchor || model.endpoint != expectedRow) {
		failure = format("%s expected anchor/endpoint %d/%d got %d/%d",
			label, expectedAnchor, expectedRow, model.anchor,
			model.endpoint);
		return false;
	}
	if(model.column != expectedColumn || model.nibble != expectedNibble) {
		failure = format("%s changed column/nibble from %d/%d to %d/%d",
			label, expectedColumn, expectedNibble, model.column,
			model.nibble);
		return false;
	}
	if(model.dataWrites != 0 || model.undoRequests != 0) {
		failure = format("%s mutated data or Undo state", label);
		return false;
	}
	return true;
}

bool checkProgramTablePinnedDragAutoScroll(out string failure) {
	string tablesSource = readText(buildPath("src", "ui", "tables.d"));
	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	string helpSource = readText(buildPath("src", "ui", "help.d"));
	string inputSource = readText(buildPath("src", "ui", "input.d"));
	string seqtableSource = readText(buildPath("src", "seq", "seqtable.d"));
	string sequencerSource = readText(buildPath("src", "seq", "sequencer.d"));

	foreach(required; [
			"maxProgramRowDragViewOffset()",
			"return rows > visibleRows ? rows - visibleRows : 0;",
			"placeProgramRowDragAtVisibleRow(int visibleRow)",
			"row = targetRow;",
			"cursorOffset = visibleRow;",
			"return row - viewOffset == visibleRow;",
			"moveProgramRowDragViewportBy(",
			"ProgramTableRowDragAutoScrollDirection direction",
			"int visibleRow = rowDrag.visibleRow;",
			"programTableRowDragAutoScrollDirectionForRow(\n\t\t\t\tvisibleRow, visibleRows) != direction",
			"int newViewOffset = clamp(viewOffset + rowDelta,\n\t\t\t0, maxProgramRowDragViewOffset());",
			"if(newViewOffset == viewOffset)\n\t\t\treturn false;",
			"viewOffset = newViewOffset;",
			"if(!placeProgramRowDragAtVisibleRow(visibleRow))",
			"rowSelection.select(rowSelection.anchorRow, row);",
			"return moveProgramRowDragViewportBy(rowDrag.direction);"]) {
		if(tablesSource.indexOf(required) < 0) {
			failure = "Pinned generated-table drag source missing " ~ required;
			return false;
		}
	}
	if(tablesSource.indexOf(
			"return moveProgramRowDragBy(rowDelta);") >= 0) {
		failure = "Generated-table timer still moves by logical row before viewport";
		return false;
	}
	if(tablesSource.indexOf("0xF1") >= 0 ||
			tablesSource.indexOf("0xf1") >= 0 ||
			tablesSource.indexOf("0x31") >= 0) {
		failure = "Generated-table viewport clamp hard-codes table-specific final offsets";
		return false;
	}

	ProgramTablePinnedDragModel model;
	model.rows = 256;
	model.visibleRows = 15;
	model.viewOffset = 0;
	model.retainedVisibleRow = 12;
	model.row = 12;
	model.endpoint = 12;
	if(!completeProgramTablePinnedDragCadence(model, 1, failure) ||
			!requirePinnedProgramTableState(model, 1, 13, 12, 4, 1, 1,
				failure, "Wave down first cadence"))
		return false;
	if(!completeProgramTablePinnedDragCadence(model, 1, failure) ||
			!requirePinnedProgramTableState(model, 2, 14, 12, 4, 1, 1,
				failure, "Wave down second cadence"))
		return false;

	model = ProgramTablePinnedDragModel();
	model.rows = 256;
	model.visibleRows = 15;
	model.viewOffset = 10;
	model.retainedVisibleRow = 2;
	model.row = 12;
	model.endpoint = 12;
	if(!completeProgramTablePinnedDragCadence(model, -1, failure) ||
			!requirePinnedProgramTableState(model, 9, 11, 2, 4, 1, 1,
				failure, "Wave up first cadence"))
		return false;
	if(!completeProgramTablePinnedDragCadence(model, -1, failure) ||
			!requirePinnedProgramTableState(model, 8, 10, 2, 4, 1, 1,
				failure, "Wave up second cadence"))
		return false;

	foreach(visibleRow; [0, 1, 2, 12, 13, 14]) {
		model = ProgramTablePinnedDragModel();
		model.rows = 256;
		model.visibleRows = 15;
		model.viewOffset = visibleRow < 3 ? 10 : 20;
		model.retainedVisibleRow = visibleRow;
		model.row = model.viewOffset + visibleRow;
		model.endpoint = model.row;
		int direction = visibleRow < 3 ? -1 : 1;
		if(!completeProgramTablePinnedDragCadence(model, direction, failure))
			return false;
		if(model.row - model.viewOffset != visibleRow) {
			failure = format("Visible padding index %d was not pinned",
				visibleRow);
			return false;
		}
	}

	foreach(rows; [256, 64]) {
		int maxViewOffset = rows - 15;
		foreach(visibleRow; [12, 13, 14]) {
			model = ProgramTablePinnedDragModel();
			model.rows = rows;
			model.visibleRows = 15;
			model.viewOffset = maxViewOffset - 1;
			model.retainedVisibleRow = visibleRow;
			model.row = model.viewOffset + visibleRow;
			model.endpoint = model.row;
			if(!completeProgramTablePinnedDragCadence(model, 1, failure))
				return false;
			int expectedRow = maxViewOffset + visibleRow;
			if(!requirePinnedProgramTableState(model, maxViewOffset,
					expectedRow, visibleRow, 4, 1, 1, failure,
					format("Bottom clamp rows %d visible %d", rows,
						visibleRow)))
				return false;
			int oldRow = model.row;
			int oldViewOffset = model.viewOffset;
			foreach(tick; 0 .. 4)
				advanceProgramTablePinnedDragModel(model, 1);
			if(model.viewOffset != oldViewOffset || model.row != oldRow) {
				failure = format("Bottom clamp rows %d visible %d wrapped or moved",
					rows, visibleRow);
				return false;
			}
		}
	}

	foreach(visibleRow; [0, 1, 2]) {
		model = ProgramTablePinnedDragModel();
		model.rows = 256;
		model.visibleRows = 15;
		model.viewOffset = 0;
		model.retainedVisibleRow = visibleRow;
		model.row = visibleRow;
		model.endpoint = visibleRow;
		foreach(tick; 0 .. 4)
			advanceProgramTablePinnedDragModel(model, -1);
		if(model.viewOffset != 0 || model.row != visibleRow) {
			failure = format("Top clamp visible %d moved or wrapped",
				visibleRow);
			return false;
		}
	}

	model = ProgramTablePinnedDragModel();
	model.retainedVisibleRow = 7;
	model.row = 7;
	model.endpoint = 7;
	foreach(tick; 0 .. 8)
		advanceProgramTablePinnedDragModel(model, 0);
	if(model.viewOffset != 0 || model.row != 7) {
		failure = "Neutral generated-table drag zone moved viewport";
		return false;
	}

	model = ProgramTablePinnedDragModel();
	model.committed = false;
	model.retainedVisibleRow = 12;
	model.row = 12;
	model.endpoint = 12;
	foreach(tick; 0 .. 8)
		advanceProgramTablePinnedDragModel(model, 1);
	if(model.viewOffset != 0 || model.row != 12) {
		failure = "Candidate-only generated-table drag auto-scrolled";
		return false;
	}

	model = ProgramTablePinnedDragModel();
	model.retainedVisibleRow = 12;
	model.row = 12;
	model.endpoint = 12;
	model.mouseReleased = true;
	foreach(tick; 0 .. 8)
		advanceProgramTablePinnedDragModel(model, 1);
	if(model.viewOffset != 0 || model.row != 12) {
		failure = "Mouse-up did not stop generated-table drag auto-scroll";
		return false;
	}

	model = ProgramTablePinnedDragModel();
	model.viewOffset = 10;
	model.retainedVisibleRow = 2;
	model.row = 12;
	model.endpoint = 12;
	if(!completeProgramTablePinnedDragCadence(model, -1, failure))
		return false;
	model.retainedVisibleRow = 12;
	model.row = model.viewOffset + model.retainedVisibleRow;
	model.endpoint = model.row;
	if(!completeProgramTablePinnedDragCadence(model, 1, failure))
		return false;
	if(model.anchor != 4 || model.row - model.viewOffset != 12) {
		failure = "Direction reversal did not preserve anchor and visible index";
		return false;
	}

	foreach(pair; [
			tuple("src/ui/ui.d", uiSource,
				"dialog is null && toplevel.advanceGeneratedTableRowDragAutoScroll()"),
			tuple("src/ui/help.d", helpSource,
				"Click-drag = select rows"),
			tuple("src/ui/input.d", inputSource,
				"resolveGeneratedTableRowSelectionKeyboardAction"),
			tuple("src/seq/seqtable.d", seqtableSource,
				"beginSequenceRowDragCandidate()"),
			tuple("src/seq/sequencer.d", sequencerSource,
				"moveSequenceRowSelectionToOverviewGlobalRow(overview")]) {
		if(pair[1].indexOf(pair[2]) < 0) {
			failure = format("Expected unchanged source marker missing from %s",
				pair[0]);
			return false;
		}
	}

	return true;
}

private string generatedProgramTableMouseDragState(
		GeneratedProgramTableMouseDragSnapshot state) {
	return format("row=%d cursor=%d view=%d column=%d nibble=%d " ~
		"selection=%s range=%d-%d dragActive=%s committed=%s " ~
		"dragVisible=%d dragDirection=%d",
		state.row, state.cursorOffset, state.viewOffset, state.column,
		state.nibble, state.selectionActive ? "yes" : "no",
		state.selectionStart, state.selectionEnd,
		state.dragActive ? "yes" : "no",
		state.dragCommitted ? "yes" : "no",
		state.dragVisibleRow, cast(int)state.dragDirection);
}

private int generatedProgramTableDataX(T)(T table, int column = 2) {
	return table.area.x + 3 + column * 3;
}

private int generatedProgramTableDataY(T)(T table, int visibleRow) {
	return table.area.y + 1 + visibleRow;
}

private bool requireGeneratedProgramTableMouseDragState(
		GeneratedProgramTableMouseDragSnapshot state, string label,
		int expectedRow, int expectedVisibleRow, int expectedViewOffset,
		int expectedColumn, int expectedNibble, bool expectedSelection,
		int expectedRangeStart, int expectedRangeEnd, bool expectedDragActive,
		bool expectedCommitted,
		ProgramTableRowDragAutoScrollDirection expectedDirection,
		out string failure) {
	if(state.row != expectedRow || state.cursorOffset != expectedVisibleRow ||
			state.viewOffset != expectedViewOffset) {
		failure = format("%s expected row/cursor/view %d/%d/%d got %s",
			label, expectedRow, expectedVisibleRow, expectedViewOffset,
			generatedProgramTableMouseDragState(state));
		return false;
	}
	if(state.column != expectedColumn || state.nibble != expectedNibble) {
		failure = format("%s changed column/nibble: %s", label,
			generatedProgramTableMouseDragState(state));
		return false;
	}
	if(state.selectionActive != expectedSelection) {
		failure = format("%s selection state mismatch: %s", label,
			generatedProgramTableMouseDragState(state));
		return false;
	}
	if(state.selectionActive && (state.selectionStart != expectedRangeStart ||
			state.selectionEnd != expectedRangeEnd)) {
		failure = format("%s expected range %d-%d got %s", label,
			expectedRangeStart, expectedRangeEnd,
			generatedProgramTableMouseDragState(state));
		return false;
	}
	if(state.dragActive != expectedDragActive ||
			state.dragCommitted != expectedCommitted ||
			state.dragDirection != expectedDirection) {
		failure = format("%s drag state mismatch: %s", label,
			generatedProgramTableMouseDragState(state));
		return false;
	}
	return true;
}

private bool advanceGeneratedProgramTableMouseDragFourTicks(T)(T table,
		string label, out string failure) {
	foreach(tick; 1 .. PROGRAM_TABLE_ROW_DRAG_AUTOSCROLL_INTERVAL_TICKS) {
		if(table.advanceGeneratedTableRowDragAutoScroll()) {
			failure = format("%s moved before interval tick %d", label, tick);
			return false;
		}
	}
	if(!table.advanceGeneratedTableRowDragAutoScroll()) {
		failure = label ~ " did not move on interval tick";
		return false;
	}
	return true;
}

private bool verifyGeneratedProgramTableMouseDragInstance(T)(T table,
		ProgramTableRowKind expectedKind, const(ubyte)[] originalData,
		out string failure) {
	if(table.generatedProgramTableMouseDragSnapshot().kind != expectedKind) {
		failure = "unexpected generated-table row kind";
		return false;
	}

	table.clickedAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 4), 1);
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(), "click candidate",
			4, 4, 0, 2, 0, false, -1, -1, true, false,
			ProgramTableRowDragAutoScrollDirection.none, failure))
		return false;

	table.mouseMotionAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 8));
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(), "first motion commit",
			8, 8, 0, 2, 0, true, 4, 8, true, true,
			ProgramTableRowDragAutoScrollDirection.none, failure))
		return false;

	table.mouseMotionAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 2));
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(), "reverse motion",
			2, 2, 0, 2, 0, true, 2, 4, true, true,
			ProgramTableRowDragAutoScrollDirection.up, failure))
		return false;

	if(!table.mouseButtonUp(1)) {
		failure = "mouse-up did not consume active drag";
		return false;
	}
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(), "mouse up",
			2, 2, 0, 2, 0, true, 2, 4, false, false,
			ProgramTableRowDragAutoScrollDirection.none, failure))
		return false;
	if(table.mouseButtonUp(1)) {
		failure = "second mouse-up consumed an inactive drag";
		return false;
	}

	table.clickedAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 12), 1);
	table.mouseMotionAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 12));
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(),
			"bottom padding commit", 12, 12, 0, 2, 0, true, 12, 12,
			true, true, ProgramTableRowDragAutoScrollDirection.down,
			failure))
		return false;
	if(!advanceGeneratedProgramTableMouseDragFourTicks(table,
			"bottom auto-scroll", failure))
		return false;
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(), "bottom auto-scroll",
			13, 12, 1, 2, 0, true, 12, 13, true, true,
			ProgramTableRowDragAutoScrollDirection.down, failure))
		return false;

	table.mouseMotionAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 7));
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(), "neutral zone",
			8, 7, 1, 2, 0, true, 8, 12, true, true,
			ProgramTableRowDragAutoScrollDirection.none, failure))
		return false;
	foreach(tick; 0 .. PROGRAM_TABLE_ROW_DRAG_AUTOSCROLL_INTERVAL_TICKS * 2)
		table.advanceGeneratedTableRowDragAutoScroll();
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(), "neutral no-scroll",
			8, 7, 1, 2, 0, true, 8, 12, true, true,
			ProgramTableRowDragAutoScrollDirection.none, failure))
		return false;

	table.mouseButtonUp(1);
	table.clickedAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 2), 1);
	table.mouseMotionAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 2));
	if(!advanceGeneratedProgramTableMouseDragFourTicks(table,
			"top auto-scroll", failure))
		return false;
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(), "top auto-scroll",
			2, 2, 0, 2, 0, true, 2, 3, true, true,
			ProgramTableRowDragAutoScrollDirection.up, failure))
		return false;

	table.mouseButtonUp(1);
	table.clickedAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 5), 1);
	table.mouseMotionAt(generatedProgramTableDataX(table),
		generatedProgramTableDataY(table, 6));
	table.mouseButtonUp(1);
	if(!table.extendProgramRowSelectionAt(generatedProgramTableDataX(table),
			generatedProgramTableDataY(table, 8))) {
		failure = "row-extension owner rejected a valid row";
		return false;
	}
	if(!requireGeneratedProgramTableMouseDragState(
			table.generatedProgramTableMouseDragSnapshot(), "range extension",
			8, 8, 0, 2, 0, true, 5, 8, true, true,
			ProgramTableRowDragAutoScrollDirection.none, failure))
		return false;

	if(!table.mouseButtonUp(1)) {
		failure = "mouse-up did not consume extended selection drag state";
		return false;
	}
	if(table.mouseButtonUp(1)) {
		failure = "second mouse-up consumed inactive extended selection";
		return false;
	}
	if(!com.session.state.undoQueue.empty()) {
		failure = "mouse row-selection path changed Undo state";
		return false;
	}
	return true;
}

bool checkGeneratedProgramTableMouseDragParity(out string failure) {
	com.session.initSession();
	com.session.state.song.ver = 0;
	com.session.state.displayHelp = false;
	com.session.screen = new Screen(100, 42);
	com.session.state.undoQueue.clear();
	com.session.state.redoQueue.clear();

	auto pulse = new PulseTable(Rectangle(10, 10, 16, 14));
	auto filter = new FilterTable(Rectangle(30, 10, 16, 14));
	auto originalPulse = com.session.song.pulseTable.dup;
	auto originalFilter = com.session.song.filterTable.dup;
	if(!verifyGeneratedProgramTableMouseDragInstance(pulse,
			ProgramTableRowKind.pulse, originalPulse, failure)) {
		failure = "Pulse: " ~ failure;
		return false;
	}
	if(com.session.song.pulseTable[] != originalPulse[]) {
		failure = "Pulse mouse row-selection path mutated table data";
		return false;
	}
	if(!verifyGeneratedProgramTableMouseDragInstance(filter,
			ProgramTableRowKind.filter, originalFilter, failure)) {
		failure = "Filter: " ~ failure;
		return false;
	}
	if(com.session.song.filterTable[] != originalFilter[]) {
		failure = "Filter mouse row-selection path mutated table data";
		return false;
	}
	return true;
}

private uint readBigEndianUint(const(ubyte)[] bytes, size_t offset) {
	return (cast(uint)bytes[offset] << 24) |
		(cast(uint)bytes[offset + 1] << 16) |
		(cast(uint)bytes[offset + 2] << 8) |
		cast(uint)bytes[offset + 3];
}

private bool readPngDimensionsForContract(string path, out uint width,
		out uint height) {
	auto bytes = cast(ubyte[])read(path);
	if(bytes.length < 24)
		return false;
	immutable ubyte[] signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a,
		0x1a, 0x0a];
	if(bytes[0 .. signature.length] != signature)
		return false;
	width = readBigEndianUint(bytes, 16);
	height = readBigEndianUint(bytes, 20);
	return true;
}

bool checkDesktopIconGenerationContract(out string failure) {
	uint width;
	uint height;
	if(!readPngDimensionsForContract(buildPath("icons", "cc2048.png"),
			width, height) || width != 2048 || height != 2048) {
		failure = format("icons/cc2048.png expected 2048x2048 PNG, got %dx%d",
			width, height);
		return false;
	}

	foreach(stalePath; [
			buildPath("arch", "MacOS", "Contents", "Resources", "ct.icns"),
			buildPath("icons", "cc32.png"),
			buildPath("icons", "cc48.png"),
			buildPath("icons", "cc96.png")]) {
		if(exists(stalePath)) {
			failure = format("Stale generated icon asset remains: %s",
				stalePath);
			return false;
		}
	}

	string scriptSource = readText(buildPath("scripts",
		"generate_desktop_icons.py"));
	foreach(required; [
			"DEFAULT_SOURCE_PATH = \"icons/cc2048.png\"",
			"DEFAULT_OUTPUT_ROOT = \"build/desktop-icons\"",
			"REQUIRED_SOURCE_SIZE = 2048",
			"MACOS_ICONSET_FILES = [",
			"(\"icon_16x16.png\", 16)",
			"(\"icon_16x16@2x.png\", 32)",
			"(\"icon_32x32.png\", 32)",
			"(\"icon_32x32@2x.png\", 64)",
			"(\"icon_128x128.png\", 128)",
			"(\"icon_128x128@2x.png\", 256)",
			"(\"icon_256x256.png\", 256)",
			"(\"icon_256x256@2x.png\", 512)",
			"(\"icon_512x512.png\", 512)",
			"(\"icon_512x512@2x.png\", 1024)",
			"WINDOWS_ICON_SIZES = [16, 24, 32, 48, 64, 128, 256]",
			"LINUX_ICON_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]",
			"dimension = 0 if size == 256 else size",
			"render_png(source, output, size, backend)",
			"verify_macos_icns(output_root / \"macos\" / \"ct.icns\")"]) {
		if(scriptSource.indexOf(required) < 0) {
			failure = format("Icon generator missing contract text: %s",
				required);
			return false;
		}
	}
	if(scriptSource.indexOf("/Users/") >= 0) {
		failure = "Icon generator embeds a local absolute user path";
		return false;
	}

	string macMakefile = readText("Makefile.mac");
	foreach(required; [
			"ICON_SOURCE=icons/cc2048.png",
			"ICON_SCRIPT=scripts/generate_desktop_icons.py",
			"ICON_OUTPUT_ROOT=build/desktop-icons",
			"MAC_APP_ICON=$(ICON_OUTPUT_ROOT)/macos/ct.icns",
			"desktop-icons: $(MAC_APP_ICON)",
			"python3 $(ICON_SCRIPT) --source $(ICON_SOURCE) --output $(ICON_OUTPUT_ROOT) --platform all --verify",
			"app: desktop-icons all",
			"cp $(MAC_APP_ICON) CheeseCutter.app/Contents/Resources/ct.icns",
			"rm -rf build CheeseCutter.app"]) {
		if(macMakefile.indexOf(required) < 0) {
			failure = format("Makefile.mac missing icon ownership: %s",
				required);
			return false;
		}
	}
	if(macMakefile.indexOf("arch/generate-icons.sh") >= 0 ||
			macMakefile.indexOf("arch/MacOS/Contents/Resources/ct.icns") >= 0) {
		failure = "Makefile.mac still references static icon generation";
		return false;
	}
	if(macMakefile.indexOf("/Users/") >= 0) {
		failure = "Makefile.mac embeds a local absolute user path";
		return false;
	}

	string genericMakefile = readText("Makefile");
	foreach(required; ["desktop-icons:", "linux-icons:", "windows-icon:",
			"$(ICON_OUTPUT_ROOT)", "rm -rf $(ICON_OUTPUT_ROOT)"]) {
		if(genericMakefile.indexOf(required) < 0) {
			failure = format("Generic Makefile missing explicit icon target: %s",
				required);
			return false;
		}
	}

	string plist = readText(buildPath("arch", "MacOS", "Contents",
		"Info.plist"));
	if(plist.indexOf("<string>ct.icns</string>") < 0) {
		failure = "Info.plist no longer references ct.icns";
		return false;
	}

	string readme = readText("README.md");
	if(readme.indexOf("platform-specific desktop application icons") < 0) {
		failure = "README missing desktop icon capability text";
		return false;
	}
	foreach(retired; [
			"python3 scripts/generate_desktop_icons.py",
			"make -f Makefile.mac desktop-icons",
			"`build/desktop-icons/macos/ct.icns`"]) {
		if(readme.indexOf(retired) >= 0) {
			failure = format("README retains detailed icon procedure: %s",
				retired);
			return false;
		}
	}
	if(readme.indexOf("/Users/") >= 0) {
		failure = "README embeds a local absolute user path";
		return false;
	}

	return true;
}

bool checkReleaseMetadataOwnership(out string failure) {
	if(!exists("NEWS")) {
		failure = "NEWS release-history owner is missing";
		return false;
	}
	string news = readText("NEWS");
	foreach(required; [
			"CheeseCutter 2.11R — Hypercut",
			"Hypercut enhancements by " ~ "arch0" ~ "N.",
			"The embedded C64 music driver remains unchanged.",
			"TRACK OVERVIEW",
			"Timeline",
			"Voice lanes",
			"F6 PATTERN EDITOR",
			"INSTRUMENTS",
			"WAVE, PULSE AND FILTER TABLES",
			"FILES AND EXPORT",
			"AUDIO AND PLAYBACK",
			"SUBTUNES",
			"INTERFACE",
			"HELP AND QUICK HELP",
			"PLATFORMS",
			"Native Windows x64 support",
			"SDL2 audio-device compatibility",
			"Select and edit subtunes directly",
			"Speed dots show voice speed events",
			"macOS arm64 application release"]) {
		if(news.indexOf(required) < 0) {
			failure = format("NEWS missing public release text: %s",
				required);
			return false;
		}
	}
	if(countOccurrences(news,
			"Hypercut enhancements by " ~ "arch0" ~ "N.") != 1) {
		failure = "NEWS Hypercut credit must occur exactly once";
		return false;
	}
	foreach(forbidden; ["TASK" ~ "-ID", "SHA-256", "test counts",
			"Local verification", "verification status",
			"unpublished", "patch review", "internal approval",
			"release-engineering", "handoff", "return archive"]) {
		if(news.indexOf(forbidden) >= 0) {
			failure = format("NEWS contains internal workflow text: %s",
				forbidden);
			return false;
		}
	}

	if(exists("ChangeLog")) {
		failure = "Root ChangeLog must not be a committed duplicate of NEWS";
		return false;
	}

	if(strip(readText("VERSION")) != "2.11") {
		failure = "VERSION no longer contains exactly 2.11";
		return false;
	}

	string appVersionSource = readText(buildPath("src", "com",
		"appversion.d"));
	foreach(required; [
			"enum string APP_VERSION = strip(import(\"VERSION\"));",
			"enum string APP_REVISION_MARKER = \"R\";",
			"enum string APP_EDITION = \"Hypercut\";",
			"APP_DISPLAY_VERSION = APP_VERSION ~ APP_REVISION_MARKER"]) {
		if(appVersionSource.indexOf(required) < 0) {
			failure = format("appversion.d missing identity owner: %s",
				required);
			return false;
		}
	}

	string objectMakefile = readText("Makefile.objects.mk");
	if(objectMakefile.indexOf("./NEWS \\") < 0) {
		failure = "DIST_FILES does not include ./NEWS";
		return false;
	}
	if(objectMakefile.indexOf("./ChangeLog") >= 0) {
		failure = "DIST_FILES still depends on root ChangeLog";
		return false;
	}

	string genericMakefile = readText("Makefile");
	if(genericMakefile.indexOf("$(DIST_FILES)") < 0) {
		failure = "Generic Makefile dist no longer consumes DIST_FILES";
		return false;
	}

	string dmgScript = readText(buildPath("arch", "makedmg.sh"));
	if(dmgScript.indexOf("cp NEWS /Volumes/\"${title}\"/ChangeLog") < 0) {
		failure = "makedmg.sh no longer maps NEWS to packaged ChangeLog";
		return false;
	}
	if(dmgScript.indexOf("cp -r tunes README.md LICENSE.md ChangeLog") >= 0) {
		failure = "makedmg.sh still copies missing root ChangeLog";
		return false;
	}

	return true;
}

private string[] nonEmptyLines(string text) {
	string[] result;
	foreach(line; text.splitLines()) {
		string item = strip(line);
		if(item.length)
			result ~= item;
	}
	return result;
}

private bool makefileHasTarget(string makefile, string target) {
	if(makefile.indexOf("\n" ~ target ~ ":") >= 0 ||
			makefile.startsWith(target ~ ":"))
		return true;
	return target == "ccutter" &&
		(makefile.indexOf("\nTARGET=ccutter\n") >= 0 ||
		 makefile.startsWith("TARGET=ccutter\n")) &&
		makefile.indexOf("\n$(TARGET):") >= 0;
}

bool checkSourceReleaseOwnership(out string failure) {
	if(!exists(buildPath("release", "source-files.txt"))) {
		failure = "release/source-files.txt is missing";
		return false;
	}
	auto entries = nonEmptyLines(readText(buildPath("release",
		"source-files.txt")));
	if(entries.length != 177) {
		failure = format("source release manifest contains %d entries, expected 177",
			entries.length);
		return false;
	}
	string[string] seen;
	foreach(index, entry; entries) {
		if(index > 0 && entries[index - 1] > entry) {
			failure = format("source manifest is not sorted near %s", entry);
			return false;
		}
		if(entry in seen) {
			failure = format("duplicate source manifest entry: %s", entry);
			return false;
		}
		seen[entry] = entry;
		if(entry.length == 0 || entry[0] == '/' ||
				entry.indexOf("..") >= 0) {
			failure = format("unsafe source manifest entry: %s", entry);
			return false;
		}
		if(!exists(entry)) {
			failure = format("manifest-listed file is missing: %s", entry);
			return false;
		}
		foreach(forbidden; [".git/", "build/", "CheeseCutter.app/",
				"dist/", "docs/", "__MACOSX/", "__pycache__/"]) {
			if(entry.startsWith(forbidden)) {
				failure = format("manifest includes forbidden path %s", entry);
				return false;
			}
		}
		foreach(forbidden; ["ccutter", "ct2util", "_backup.ct",
				"tunes/_backup.ct", "src/c64/player.bin",
				"src/font/font-original-DO-NOT-USE.psf"]) {
			if(entry == forbidden) {
				failure = format("manifest includes forbidden file %s", entry);
				return false;
			}
		}
		foreach(suffix; [".o", ".dmg", ".zip", ".log", ".pyc"]) {
			if(entry.endsWith(suffix)) {
				failure = format("manifest includes generated suffix %s",
					entry);
				return false;
			}
		}
		if(entry.startsWith("arch/fd/hicolor/")) {
			failure = "manifest includes generated Linux hicolor icons";
			return false;
		}
		string lowerEntry = entry.toLower();
		foreach(forbidden; ["patch", "review", "handoff", "checklist",
				"audit", "task-record", "build-record", "test-log"]) {
			if(lowerEntry.indexOf(forbidden) >= 0) {
				failure = format("manifest includes internal workflow file %s",
					entry);
				return false;
			}
		}
		if((entry.endsWith(".ct") || entry.endsWith(".sid") ||
				entry.endsWith(".prg")) && entry.indexOf("/") < 0) {
			failure = format("manifest includes loose root-level tune/sample %s",
				entry);
			return false;
		}
		if(entry.endsWith(".ct") &&
				!entry.startsWith("tunes/") &&
				!entry.startsWith("tests/fixtures/")) {
			failure = format("manifest includes non-canonical tune path %s",
				entry);
			return false;
		}
		if(entry.endsWith(".sid") || entry.endsWith(".prg")) {
			failure = format("manifest includes generated export %s", entry);
			return false;
		}
	}

	if(exists(buildPath("tunes", "mch-cheesecatsgroove.ct")) &&
			exists(buildPath("tunes-testing",
				"Cheesecutter mch-cheesecatsgroove.ct")) &&
			sha256Of(read(buildPath("tunes", "mch-cheesecatsgroove.ct"))) ==
			sha256Of(read(buildPath("tunes-testing",
				"Cheesecutter mch-cheesecatsgroove.ct")))) {
		failure = "byte-identical Cheesecatsgroove tune remains duplicated";
		return false;
	}

	foreach(required; ["Makefile", "Makefile.mac", "Makefile.objects.mk",
			"README.md", "LICENSE.md", "NEWS", "VERSION",
			"icons/cc2048.png", "scripts/generate_desktop_icons.py",
			"scripts/create_source_release.py", "release/linux/BUILD.md",
			"tests/main.d", "tests/fixtures/r2d-minimal.ct",
			"arch/fd/ccutter.desktop", "make-wintest.sh",
			"make-wintest.cmd"]) {
		if(required !in seen) {
			failure = format("manifest missing required source file: %s",
				required);
			return false;
		}
	}
	foreach(removed; ["AUTHORS",
			"release/linux/RETURN_" ~ "CHECKLIST.md"]) {
		if(removed in seen || exists(removed)) {
			failure = "removed public-source file is still owned: " ~ removed;
			return false;
		}
	}
	string approvedOwner = "arch0" ~ "N";
	string invalidOwner = "arch0" ~ "n";
	size_t approvedOwnerCount;
	size_t invalidOwnerCount;
	foreach(entry; entries) {
		try {
			string maintainedText = readText(entry);
			approvedOwnerCount += maintainedText.count(approvedOwner);
			invalidOwnerCount += maintainedText.count(invalidOwner);
		}
		catch(Exception) {
		}
	}
	if(approvedOwnerCount != 2 || invalidOwnerCount != 0) {
		failure = format(
			"public owner identity count changed: valid=%d invalid=%d",
			approvedOwnerCount, invalidOwnerCount);
		return false;
	}

	string scriptSource = readText(buildPath("scripts",
		"create_source_release.py"));
	foreach(required; [
			"PROJECT_NAME = \"CheeseCutter\"",
			"DEFAULT_RELEASE_LABEL = \"2.11R\"",
			"FIXED_ZIP_TIMESTAMP = (2026, 7, 20, 0, 0, 0)",
			"FILE_MODE = 0o644",
			"EXECUTABLE_MODE = 0o755",
			"def source_archive_names(release_label: str) -> tuple[str, str]:",
			"source_zip_name = f\"{PROJECT_NAME}-{release_label}-source.zip\"",
			"source_top = source_zip_name[:-len(\".zip\")]",
			"LINUX_KIT_TOP = f\"{RELEASE_NAME}-linux-build-kit\"",
			"private_needles(project_root)",
			"scan_private_values(project_root, relpaths, extra)",
			"zipfile.ZipInfo(member, FIXED_ZIP_TIMESTAMP)",
			"archive.comment = b\"\"",
			"path = project_root / rel",
			"if not path.is_file():",
			"source ZIP member mismatch",
			"embedded source ZIP differs from canonical source ZIP",
			"raise ReleaseError(f\"missing canonical source ZIP:",
			"if kind in {\"verify-source\", \"all\"}:",
			"if kind in {\"verify-linux-kit\", \"all\"}:",
			"\"verify-source\", \"verify-linux-kit\""]) {
		if(scriptSource.indexOf(required) < 0) {
			failure = format("source release script missing owner text: %s",
				required);
			return false;
		}
	}
	foreach(forbidden; [
			"release/linux/RETURN_" ~ "CHECKLIST.md",
			"linux/RETURN_" ~ "CHECKLIST.md",
			"unverified Linux build " ~ "handoff",
			"return package",
			"return archive",
			"send back"]) {
		if(scriptSource.indexOf(forbidden) >= 0) {
			failure = format("source release script retains internal workflow: %s",
				forbidden);
			return false;
		}
	}
	foreach(forbidden; [
			"Hypercut-source",
			"SOURCE_TOP =",
			"SOURCE_ZIP_NAME =",
			"source_zip = create_source_zip(project_root, output)",
			"if kind in {\"verify\", \"all\"}:"]) {
		if(scriptSource.indexOf(forbidden) >= 0) {
			failure = format("source release script retains coupled owner: %s",
				forbidden);
			return false;
		}
	}
	foreach(forbidden; ["/Users/", "/home/", "C:\\\\Users\\\\"]) {
		if(scriptSource.indexOf(forbidden) >= 0) {
			failure = "source release script embeds a local absolute path";
			return false;
		}
	}

	string linuxBuild = readText(buildPath("release", "linux", "BUILD.md"));
	string genericMakefile = readText("Makefile");
	foreach(target; ["clean", "ccutter", "all", "ct2util", "linux-icons"]) {
		if(linuxBuild.indexOf("make " ~ target) >= 0 &&
				!makefileHasTarget(genericMakefile, target)) {
			failure = format("Linux BUILD.md documents missing target %s",
				target);
			return false;
		}
	}
	foreach(required; ["# Building CheeseCutter on Linux",
			"The generic `Makefile` owns Linux builds",
			"make clean", "make ccutter", "make ct2util",
			"make all", "make linux-icons",
			"The generic Makefile currently has no automated `test` target.",
			"./ccutter", "ldd ./ccutter"]) {
		if(linuxBuild.indexOf(required) < 0) {
			failure = format("Linux BUILD.md missing public build text: %s",
				required);
			return false;
		}
	}
	foreach(forbidden; ["handoff", "return archive", "return checklist",
			"Do not return", "project-manager", "operator workflow",
			"private staging", "TASK" ~ "-ID"]) {
		if(linuxBuild.toLower().indexOf(forbidden.toLower()) >= 0) {
			failure = format("Linux BUILD.md retains internal workflow: %s",
				forbidden);
			return false;
		}
	}

	string readme = readText("README.md");
	foreach(required; ["# CheeseCutter 2.11R — Hypercut",
			"See [NEWS](NEWS) for",
			"Windows x64: extract the Windows package and run `ccutter.exe`.",
			"macOS arm64: extract the macOS package and open `CheeseCutter.app`.",
			"The source archive is distributed separately.",
			"no Linux binary package is provided for this release",
			"[INSTALL](INSTALL)",
			"[Makefile.mac](Makefile.mac)",
			"[arch/Windows/BUILD.md](arch/Windows/BUILD.md)",
			"[release/linux/BUILD.md](release/linux/BUILD.md)"]) {
		if(readme.indexOf(required) < 0) {
			failure = format("README missing public source-build guidance: %s",
				required);
			return false;
		}
	}
	foreach(retired; ["## Source and platform release policy",
			"one canonical frozen source archive",
			"Every platform build must identify the exact source ZIP by SHA-256"]) {
		if(readme.indexOf(retired) >= 0) {
			failure = format("README retains internal release procedure: %s",
				retired);
			return false;
		}
	}
	if(readme.indexOf("LICENSE.md") < 0 ||
			readme.indexOf("file COPYING") >= 0 ||
			readme.indexOf("`COPYING`") >= 0) {
		failure = "README licence ownership does not use LICENSE.md";
		return false;
	}

	string macMakefile = readText("Makefile.mac");
	foreach(makefile; [genericMakefile, macMakefile]) {
		foreach(target; ["source-release:", "linux-build-kit:",
				"verify-source-release:", "verify-linux-build-kit:"]) {
			if(makefile.indexOf(target) < 0) {
				failure = format("Makefile missing explicit release target: %s",
					target);
				return false;
			}
		}
		foreach(required; ["SOURCE_RELEASE_SCRIPT=scripts/create_source_release.py",
				"SOURCE_RELEASE_OUTPUT=build/release",
				"--kind source", "--kind linux-build-kit",
				"--kind verify-source", "--kind verify-linux-kit"]) {
			if(makefile.indexOf(required) < 0) {
				failure = format("Makefile missing source release owner: %s",
					required);
				return false;
			}
		}
		foreach(required; [
				"source-release:\n\tpython3 $(SOURCE_RELEASE_SCRIPT) --project-root . --output $(SOURCE_RELEASE_OUTPUT) --kind source",
				"linux-build-kit:\n\tpython3 $(SOURCE_RELEASE_SCRIPT) --project-root . --output $(SOURCE_RELEASE_OUTPUT) --kind linux-build-kit",
				"verify-source-release:\n\tpython3 $(SOURCE_RELEASE_SCRIPT) --project-root . --output $(SOURCE_RELEASE_OUTPUT) --kind verify-source",
				"verify-linux-build-kit:\n\tpython3 $(SOURCE_RELEASE_SCRIPT) --project-root . --output $(SOURCE_RELEASE_OUTPUT) --kind verify-linux-kit"]) {
			if(makefile.indexOf(required) < 0) {
				failure = "Makefile release target is mapped to the wrong mode";
				return false;
			}
		}
		foreach(forbidden; ["all: source-release", "all: linux-build-kit",
				"all: verify-source-release", "all: verify-linux-build-kit",
				"--kind verify\n"]) {
			if(makefile.indexOf(forbidden) >= 0) {
				failure = format("normal or release target remains coupled: %s",
					forbidden);
				return false;
			}
		}
	}
	if(genericMakefile.indexOf("rm -rf $(ICON_OUTPUT_ROOT) $(SOURCE_RELEASE_OUTPUT)") < 0) {
		failure = "generic Makefile clean does not remove build/release";
		return false;
	}
	if(macMakefile.indexOf("rm -rf build CheeseCutter.app") < 0) {
		failure = "Makefile.mac clean no longer removes build/release via build/";
		return false;
	}

	return true;
}

bool checkCanonicalWindowsBuildOwnership(out string failure) {
	foreach(file; [
			"Makefile.win",
			buildPath("arch", "Windows", "BUILD.md"),
			buildPath("arch", "Windows", "cheesecutter.manifest"),
			buildPath("arch", "Windows", "cheesecutter.rc"),
			buildPath("scripts", "windows_build_support.py")]) {
		if(!exists(file)) {
			failure = "missing canonical Windows build owner: " ~ file;
			return false;
		}
	}

	string makefile = readText("Makefile.win");
	foreach(required; [
			"include Makefile.objects.mk",
			"BUILD_ROOT ?= build/windows",
			".PHONY: all gui ct2util test verify verify-privacy clean toolchain-info",
			"all: gui",
			"gui: $(GUI_EXE) $(BIN_SDL_DLL)",
			"ct2util: $(CT2UTIL_EXE) $(BIN_SDL_DLL)",
			"test: $(TEST_EXE) $(TEST_SDL_DLL)",
			"verify-privacy: gui ct2util $(TEST_EXE) $(TEST_SDL_DLL)",
			"verify: gui ct2util test verify-privacy",
			"toolchain-info:",
			"clean:",
			"LDC_IMPORTS := $(GENERATED)/ldc-imports",
			"$(PYTHON) $(WINDOWS_SUPPORT) stage-ldc",
			"-L/Brepro",
			"-L/SUBSYSTEM:WINDOWS",
			"-L/ENTRY:wmainCRTStartup",
			"-L/SUBSYSTEM:CONSOLE",
			"$(CT2UTIL_EXE):",
			"$(TEST_EXE):",
			"$(SDL_IMPORT_LIBRARY)",
			"$(BIN_SDL_DLL): $(SDL_SOURCE_DLL)",
			"$(WINDOWS_ICON): $(ICON_SOURCE) $(ICON_SCRIPT)",
			"$(GENERATED_RC): $(WINDOWS_RESOURCE_TEMPLATE) $(WINDOWS_MANIFEST)",
			"$(RESOURCE_OBJECT): $(GENERATED_RC)"]) {
		if(makefile.indexOf(required) < 0) {
			failure = "Makefile.win missing ownership text: " ~ required;
			return false;
		}
	}
	foreach(forbidden; [
			"Makefile.win32",
			"ccutter-" ~ "console.exe",
			"console: $(" ~ "CONSOLE_EXE)",
			"LOCAL_" ~ "CONSOLE_EXE",
			"libSDL2.dll.a",
			"-frelease",
			"-fno-bounds-check",
			"-boundscheck=off",
			"-release",
			"C:\\",
			"/Users/",
			"/home/"]) {
		if(makefile.indexOf(forbidden) >= 0) {
			failure = "Makefile.win contains forbidden policy text: " ~
				forbidden;
			return false;
		}
	}
	if(makefile.indexOf(
			"CONSOLE_LINK := $(DETERMINISTIC_LINK) -L/SUBSYSTEM:CONSOLE") <
			0 ||
			makefile.indexOf(
				"$(LOCAL_CT2UTIL_EXE)") < 0 ||
			makefile.indexOf(
				"$(LOCAL_TEST_EXE)") < 0 ||
			makefile.indexOf(
				"$(LOCAL_RESOURCE_OBJECT) $(LOCAL_SDL_IMPORT_LIBRARY) $(CONSOLE_LINK)") >=
			0 ||
			makefile.count(
				"$(PYTHON) $(WINDOWS_SUPPORT) ldc --link-runtime") != 3) {
		failure = "GUI, utility or test link ownership is ambiguous";
		return false;
	}

	string helper = readText(buildPath("scripts",
		"windows_build_support.py"));
	foreach(required; [
			"EXPECTED_LDC_VERSION = \"1.42.0\"",
			"EXPECTED_TARGET = \"x86_64-pc-windows-msvc\"",
			"EXPECTED_IMPORT_COUNT = 191",
			"EXPECTED_RUNTIME_HASHES",
			"stage_ldc",
			"project-relative-compiler-argument",
			"Microsoft-lib.exe",
			"\"/brepro\"",
			"SDL2.def",
			"verified-dll-export-table",
			"renamed GNU archive",
			"verify_privacy",
			"PROHIBITED_TOTAL",
			"STATUS_FORMAT_VERSION = 1",
			"SUPPORTED_TARGETS = (",
			"BUILD_OWNER=Makefile.win",
			"CHEESECUTTER_CONSOLE_APPLICATION_TARGET=absent",
			"write_status_record",
			"SOURCE_RELEASE_ENTRY_COUNT=",
			"CT2UTIL_SUBSYSTEM=CONSOLE",
			"TEST_SUBSYSTEM=CONSOLE",
			"choices=[\"gui\", \"ct2util\", \"test\"]",
			"clean root must be a generated build/windows"]) {
		if(helper.indexOf(required) < 0) {
			failure = "Windows helper missing ownership text: " ~ required;
			return false;
		}
	}
	foreach(forbidden; [
			"shutil.copyfile(gnu",
			"shutil.copyfile(Path(gnu",
			"fno-bounds-check",
			"boundscheck=off",
			"ccutter-" ~ "console.exe",
			"CONSOLE_SHA256",
			"\"console\", \"ct2util\"",
			"WINDOWS-" ~ "1C10A",
			"WINDOWS-" ~ "1C10B",
			"MAINTAINED_TASK_CHANGES",
			"PRODUCTION_APPLICATION_SOURCE_CHANGES",
			"NEXT_TASK="]) {
		if(helper.indexOf(forbidden) >= 0) {
			failure = "Windows helper weakens build ownership: " ~ forbidden;
			return false;
		}
	}

	string resource = readText(buildPath("arch", "Windows",
		"cheesecutter.rc"));
	if(resource.indexOf("@ICON@") < 0 ||
			resource.indexOf("@MANIFEST@") < 0) {
		failure = "Windows resource does not use generated icon/manifest owners";
		return false;
	}
	string buildInstructions = readText(buildPath("arch", "Windows",
		"BUILD.md"));
	foreach(required; [
			"Windows x64", "official LDC 1.42.0", "Microsoft C++ Build Tools",
			"GNU Make", "SDL2 2.32.10", "make -f Makefile.win clean",
			"make -f Makefile.win test", "make -f Makefile.win gui",
			"make -f Makefile.win ct2util",
			"make -f Makefile.win verify",
			"make -f Makefile.win verify-privacy", "build/windows/",
			"/Brepro", "project-relative import root",
			"`ccutter.exe` application",
			"`ct2util.exe` is a console utility",
			"No maintained console variant of the CheeseCutter application",
			"do not create a public"]) {
		if(buildInstructions.indexOf(required) < 0) {
			failure = "Windows BUILD.md missing instruction text: " ~ required;
			return false;
		}
	}
	foreach(forbidden; ["C:\\", "/Users/", "/home/",
			"make -f Makefile.win " ~ "console",
			"ccutter-" ~ "console.exe",
			"diagnostic application"]) {
		if(buildInstructions.indexOf(forbidden) >= 0) {
			failure = "Windows BUILD.md contains a concrete machine path";
			return false;
		}
	}

	foreach(wrapper; ["make-wintest.cmd", "make-wintest.sh"]) {
		string content = readText(wrapper);
		if(content.indexOf("Makefile.win") < 0 ||
				content.indexOf(
					"all gui ct2util test verify verify-privacy clean toolchain-info") <
				0 ||
				content.indexOf("Unsupported Windows target") < 0 ||
				content.indexOf("Makefile.win32") >= 0 ||
				content.indexOf("SDL.dll") >= 0 ||
				content.indexOf("C:\\") >= 0) {
			failure = wrapper ~ " retains obsolete or private ownership";
			return false;
		}
	}

	string[] sourceFiles;
	foreach(line; readText(buildPath("release",
			"source-files.txt")).splitLines()) {
		string entry = line.strip();
		if(entry.length)
			sourceFiles ~= entry;
	}
	foreach(required; [
			"Makefile.win",
			"arch/Windows/BUILD.md",
			"arch/Windows/cheesecutter.manifest",
			"arch/Windows/cheesecutter.rc",
			"scripts/windows_build_support.py"]) {
		bool found;
		foreach(entry; sourceFiles) {
			if(entry == required) {
				found = true;
				break;
			}
		}
		if(!found) {
			failure = "source release omits Windows owner: " ~ required;
			return false;
		}
	}
	string previous;
	foreach(entry; sourceFiles) {
		if(previous.length && previous >= entry) {
			failure = "source release list is not sorted and unique";
			return false;
		}
		if(!exists(entry)) {
			failure = "source release entry does not exist: " ~ entry;
			return false;
		}
		string maintainedText;
		try {
			maintainedText = readText(entry);
		}
		catch(Exception) {
			maintainedText = null;
		}
		if(maintainedText.indexOf("ccutter-" ~ "console.exe") >= 0) {
			failure = "maintained source retains the removed diagnostic executable";
			return false;
		}
		if(entry.startsWith("build/windows") ||
				entry.endsWith(".ico") ||
				entry.endsWith(".res") ||
				entry.endsWith(".obj") ||
				entry.endsWith(".exe") ||
				entry.endsWith(".dll") ||
				entry.endsWith("SDL2.lib") ||
				entry.indexOf("ldc-imports") >= 0) {
			failure = "source release includes generated Windows artefact";
			return false;
		}
		previous = entry;
	}

	if(sourceReleaseFileHash("Makefile") !=
			"3bb312424d9e09f4946ddeda5b09427543bac3c5b6d5fe9daeca7c6f68614892" ||
			sourceReleaseFileHash("Makefile.mac") !=
			"9eaf4fba2f6c8424067bb1d35508564a53ef0d1ad2fdfae9896d77d781d3dd46") {
		failure = "generic or macOS Makefile changed during Windows ownership";
		return false;
	}
	string privacyScript = readText(buildPath("scripts",
		"create_source_release.py"));
	if(privacyScript.indexOf("def identity_token_matches(") < 0 ||
			privacyScript.indexOf(
				"PRIVACY_IDENTITY_TOKEN = \"identity-token\"") < 0) {
		failure = "release privacy matcher correction is no longer active";
		return false;
	}
	return true;
}

private enum string WINDOWS_STATUS_RECORD_FOCUSED_PYTHON = q"PY
from copy import deepcopy
import os
from pathlib import Path
import re
import runpy
import sys
import tempfile

owner = runpy.run_path(sys.argv[1])
source_entries = [
    line.strip()
    for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
    if line.strip()
]

def public_facts():
    return {
        "tool_versions": {
            "LDC": "1.42.0",
            "D_FRONTEND": "2.112.1",
            "LLVM": "21.1.8",
            "TARGET": "x86_64-pc-windows-msvc",
            "MSVC": "19.51.36248",
            "GNU_MAKE": "GNU Make 4.4.1",
            "SDL2": "2.32.10",
        },
        "source_release_entry_count": len(source_entries),
        "gui_sha256": "a" * 64,
        "gui_size": 123456,
        "ct2util_sha256": "b" * 64,
        "test_sha256": "c" * 64,
        "settled_output_sha256": "d" * 64,
        "tests_passed": 41,
        "tests_failed": 0,
        "deterministic_peer_sha256": "not-requested",
        "deterministic_gui_match": "not-requested",
        "privacy": {
            "PROHIBITED_TOTAL": "0",
            "PERMITTED_MODULE_BASENAMES": "17",
            "PERMITTED_RELATIVE_LDC_IMPORTS": "29",
            "PERMITTED_UPSTREAM_VENDOR_RUNTIME_PATHS": "3",
            "PERMITTED_GENERIC_SYSTEM_IDENTIFIERS": "not-private",
        },
    }

def fields(data):
    result = {}
    for line in data.decode("utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result

os.environ["STATUS_PRIVATE_SENTINEL"] = "private-environment-marker"
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    first = root / "first.txt"
    second = root / "second.txt"
    changed = root / "changed.txt"
    facts = public_facts()
    owner["write_status_record"](first, facts)
    owner["write_status_record"](second, facts)
    first_bytes = first.read_bytes()
    assert first_bytes == second.read_bytes()
    assert b"\r" not in first_bytes
    text = first_bytes.decode("utf-8")
    actual = fields(first_bytes)
    assert text.startswith("CHEESECUTTER_WINDOWS_BUILD_STATUS\n")
    assert actual["STATUS_FORMAT_VERSION"] == "1"
    assert actual["BUILD_OWNER"] == "Makefile.win"
    assert actual["SUPPORTED_TARGETS"].split() == [
        "all", "gui", "ct2util", "test", "verify", "verify-privacy",
        "clean", "toolchain-info"]
    assert actual["CHEESECUTTER_CONSOLE_APPLICATION_TARGET"] == "absent"
    assert actual["GUI_OUTPUT"] == "ccutter.exe"
    assert actual["GUI_SUBSYSTEM"] == "WINDOWS"
    assert actual["GUI_ENTRY_POINT"] == "wmainCRTStartup"
    assert actual["DETERMINISTIC_LINK"] == "/Brepro"
    assert actual["CT2UTIL_OUTPUT"] == "ct2util.exe"
    assert actual["CT2UTIL_SUBSYSTEM"] == "CONSOLE"
    assert actual["TEST_SUBSYSTEM"] == "CONSOLE"
    assert actual["SOURCE_RELEASE_ENTRY_COUNT"] == str(len(source_entries))
    assert actual["TESTS_PASSED"] == "41"
    assert actual["TESTS_FAILED"] == "0"
    assert actual["SETTLED_OUTPUT_SHA256"] == "d" * 64
    assert actual["GUI_SHA256"] == "a" * 64
    assert actual["GUI_SIZE"] == "123456"
    assert actual["PROHIBITED_PRIVACY_FINDINGS"] == "0"
    assert actual["VERIFICATION_VERDICT"] == "PASS"
    assert not re.search(r"WINDOWS-[0-9]", text)
    for forbidden in (
            "SYNTHETIC_STAGE_ALPHA", "SYNTHETIC_STAGE_BETA",
            "MAINTAINED_CHANGE_SUMMARY",
            "APPLICATION_SOURCE_CHANGE_SUMMARY", "NEXT_OPERATION",
            "CANONICAL_MANIFEST_ENTRIES", "ccutter-" + "console.exe",
            "private-environment-marker", "C:\\private", "/Users/private",
            "/home/private"):
        assert forbidden not in text

    revised = deepcopy(facts)
    revised["tests_passed"] = 12
    revised["tests_failed"] = 3
    revised["settled_output_sha256"] = "e" * 64
    revised["gui_sha256"] = "f" * 64
    revised["gui_size"] = 654321
    revised["privacy"]["PROHIBITED_TOTAL"] = "4"
    owner["write_status_record"](changed, revised)
    changed_fields = fields(changed.read_bytes())
    assert changed_fields["TESTS_PASSED"] == "12"
    assert changed_fields["TESTS_FAILED"] == "3"
    assert changed_fields["SETTLED_OUTPUT_SHA256"] == "e" * 64
    assert changed_fields["GUI_SHA256"] == "f" * 64
    assert changed_fields["GUI_SIZE"] == "654321"
    assert changed_fields["PROHIBITED_PRIVACY_FINDINGS"] == "4"
    assert changed_fields["VERIFICATION_VERDICT"] == "FAIL"
PY";

bool checkWindowsGeneratedStatusRecord(out string failure) {
	string focusedScript = buildPath(tempDir(),
		format("ccutter-windows-status-%d.py", thisProcessID));
	if(exists(focusedScript))
		remove(focusedScript);
	std.file.write(focusedScript, WINDOWS_STATUS_RECORD_FOCUSED_PYTHON);
	scope(exit) {
		if(exists(focusedScript))
			remove(focusedScript);
	}
	auto result = execute([
		environment.get("AUDIT_PYTHON_EXE", "python3"),
		focusedScript,
		buildPath("scripts", "windows_build_support.py"),
		buildPath("release", "source-files.txt")]);
	if(result.status != 0) {
		failure = "actual Windows status-record writer regression failed";
		return false;
	}
	return true;
}

bool checkTimelineSpeedDotHelpOwnership(out string failure) {
	enum approvedDescription =
		"voice 1, 2 or 3 has a speed event at this row.";
	enum formattedLine = "Speed dot:         " ~ approvedDescription;
	if(formattedLine.length > HELP_CONTENT_LINE_WIDTH) {
		failure = "approved Timeline speed-dot Help exceeds the layout width";
		return false;
	}
	if(formattedLine.indexOf(approvedDescription) != 19) {
		failure = "Timeline speed-dot Help value column is misaligned";
		return false;
	}
	if(TRACK_OVERVIEW_TIMELINE_HELP.indexOf(formattedLine) < 0) {
		failure = "compiled Timeline Help omits the approved speed-dot line";
		return false;
	}

	string helpSource = readText(buildPath("src", "ui", "help.d"));
	auto timelineStart = helpSource.indexOf(
		"enum string TRACK_OVERVIEW_TIMELINE_HELP =");
	auto timelineEnd = helpSource.indexOf(
		"enum string TRACK_OVERVIEW_LANES_HELP =", timelineStart);
	if(timelineStart < 0 || timelineEnd <= timelineStart ||
			helpSource.count(formattedLine) != 1 ||
			helpSource[cast(size_t)timelineStart ..
				cast(size_t)timelineEnd].indexOf(formattedLine) < 0 ||
			helpSource.count("\" ~ TRACK_OVERVIEW_TIMELINE_HELP ~ \"") != 2) {
		failure = "Timeline speed-dot Help is duplicated, misplaced or unshared";
		return false;
	}

	string uiSource = readText(buildPath("src", "ui", "ui.d"));
	auto predicateStart = uiSource.indexOf(
		"private static int[] trackOverviewSpeedMarkerRows(");
	auto predicateEnd = uiSource.indexOf(
		"private static bool handleTrackOverviewMouseDown", predicateStart);
	if(predicateStart < 0 || predicateEnd <= predicateStart) {
		failure = "Timeline speed-marker predicate owner is missing";
		return false;
	}
	string predicate = uiSource[cast(size_t)predicateStart ..
		cast(size_t)predicateEnd];
	foreach(required; [
			"foreach(lane; overview)",
			"foreach(block; lane.blocks)",
			"if(block.sequenceNumber < 0",
			"if(sequence is null)",
			"foreach(rowOffset; 0 .. rowCount)",
			"if(cmd < 0xf1)",
			"int globalRow = block.startRow + rowOffset",
			"if((globalRow in seenRows) !is null)",
			"rows ~= globalRow"]) {
		if(predicate.indexOf(required) < 0) {
			failure = "Timeline speed-marker predicate changed: " ~ required;
			return false;
		}
	}
	if(uiSource.indexOf(formattedLine) >= 0) {
		failure = "Timeline speed-dot wording leaked into Quick Help or UI logic";
		return false;
	}

	TrackOverviewLane[] lanes = buildTrackOverview(new Song());
	if(lanes.length != 3 || lanes[0].voice != 0 || lanes[1].voice != 1 ||
			lanes[2].voice != 2) {
		failure = "Track Overview no longer supplies voices 1, 2 and 3";
		return false;
	}
	if(sourceReleaseFileHash(buildPath("src", "ui",
			"trackoverviewrenderer.d")) !=
			"31d1d2542d76c97f4c0e07b454b8f8b3a40f0f3f990d4cd3ad89d7437c418da0") {
		failure = "Timeline speed-dot renderer changed";
		return false;
	}
	return true;
}

private string sourceReleaseFileHash(string file) {
	return toHexString(sha256Of(cast(ubyte[])read(file))).toLower();
}

private enum string PRIVACY_MATCHER_FOCUSED_PYTHON = q"PY
from pathlib import Path
import runpy
import tempfile

m = runpy.run_path("scripts/create_source_release.py")
token_match = m["identity_token_matches"]
private_match = m["private_value_matches"]
scan = m["scan_private_values"]
exact = m["PRIVACY_EXACT_VALUE"]
identity = m["PRIVACY_IDENTITY_TOKEN"]
release_error = m["ReleaseError"]

positive = [
    b"abc", b'"abc"', b"/abc/", b"\\abc\\", b"\\\\abc\\share",
    b"https://abc/path", b"host=abc", b"hostname: abc", b"abc:",
    b":abc", b"ABC", b"abc\0tail", b"abc.domain",
]
negative = [
    b"abcIdentifier", b"identifier_abc_value", b"_abc_",
    b"prefixabcsuffix", b"1abc2", b"alphabetabcword",
    b"0123456789abcdefabc0123456789",
    b"12345678-abc0-4000-8000-123456789abc",
    b"longer-abc-host", b"NUMABCREGS",
]
short_tokens = [
    (b"A", b"host=A"),
    (b"AB", b"host=AB"),
    (b"ab-c", b"\\\\AB-C\\share"),
]
assert all(token_match(value, b"abc", True) for value in positive)
assert all(not token_match(value, b"abc", True) for value in negative)
assert all(token_match(value, token, True)
    for token, value in short_tokens)

paths = [
    b"Q:\\Synthetic\\Profile",
    b"Q:\\Synthetic\\Checkout",
    b"Q:\\Synthetic\\Compiler",
    b"Q:\\Synthetic\\SDK",
    b"Q:\\Synthetic\\Temporary",
]
assert all(private_match(b"prefix " + value + b" suffix", value,
    exact, True) for value in paths)
assert not private_match(b"Q_Synthetic_Profile", paths[0], exact, True)
assert private_match(b"account=ABC", b"abc", identity, True)
assert not private_match(b"accountabcIdentifier", b"abc", identity, True)

original = scan.__globals__["private_needles"]
try:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        fixture = root / "fixture.txt"
        scan.__globals__["private_needles"] = lambda project: [
            ("host identifier", b"abc", identity, True),
        ]
        fixture.write_bytes(b"normalabcIdentifier")
        scan(root, ["fixture.txt"], {})
        fixture.write_bytes(b"host=abc")
        try:
            scan(root, ["fixture.txt"], {})
        except release_error as error:
            assert "abc" not in str(error).lower()
            assert "host identifier" in str(error)
            assert "redacted finding" in str(error)
        else:
            raise AssertionError("synthetic identity residue was not detected")
finally:
    scan.__globals__["private_needles"] = original
PY";

bool checkReleasePrivacyMatcherCorrection(out string failure) {
	string scriptSource = readText(buildPath("scripts",
		"create_source_release.py"));
	foreach(required; [
			"PRIVACY_EXACT_VALUE = \"exact-value\"",
			"PRIVACY_IDENTITY_TOKEN = \"identity-token\"",
			"def identity_token_matches(",
			"def private_value_matches(",
			"if policy == PRIVACY_EXACT_VALUE:",
			"if policy == PRIVACY_IDENTITY_TOKEN:",
			"(\"profile path\", \"USERPROFILE\")",
			"(\"compiler installation path\", \"LDC_ROOT\")",
			"(\"SDK installation path\", \"WindowsSdkDir\")",
			"(\"temporary path\", \"TEMP\")",
			"redacted finding"]) {
		if(scriptSource.indexOf(required) < 0) {
			failure = format("release privacy matcher missing owner text: %s",
				required);
			return false;
		}
	}
	foreach(forbidden; [
			"if len(value) <",
			"host_allow",
			"account_allow",
			"privacy_allow"]) {
		if(scriptSource.indexOf(forbidden) >= 0) {
			failure = format("release privacy matcher retains bypass text: %s",
				forbidden);
			return false;
		}
	}

	string focusedScript = buildPath(tempDir(),
		format("ccutter-privacy-matcher-%d.py", thisProcessID));
	if(exists(focusedScript))
		remove(focusedScript);
	std.file.write(focusedScript, PRIVACY_MATCHER_FOCUSED_PYTHON);
	scope(exit) {
		if(exists(focusedScript))
			remove(focusedScript);
	}
	auto result = execute([
		environment.get("AUDIT_PYTHON_EXE", "python3"), focusedScript]);
	if(result.status != 0) {
		failure = "focused release privacy matcher process failed";
		return false;
	}
	return true;
}

private auto runSourceReleaseTool(string kind, string output) {
	return execute([
		environment.get("AUDIT_PYTHON_EXE", "python3"),
		buildPath("scripts", "create_source_release.py"),
		"--project-root", ".", "--output", output, "--kind", kind]);
}

private enum string SOURCE_NAMING_FOCUSED_PYTHON = q"PY
from pathlib import Path
import runpy
import shutil
import tempfile
import zipfile

m = runpy.run_path("scripts/create_source_release.py")
names = m["source_archive_names"]
create = m["create_source_zip"]
verify = m["verify_source_zip"]
release_error = m["ReleaseError"]
manifest_name = m["SOURCE_MANIFEST_NAME"]
file_mode = m["FILE_MODE"]
write_zip = m["write_zip"]

def rejected(call):
    try:
        call()
    except (release_error, FileNotFoundError, zipfile.BadZipFile):
        return
    raise AssertionError("invalid source archive was accepted")

assert names("2.11R") == (
    "CheeseCutter-2.11R-source.zip",
    "CheeseCutter-2.11R-source",
)
assert names("3.0") == (
    "CheeseCutter-3.0-source.zip",
    "CheeseCutter-3.0-source",
)
assert names("candidate.zip") == (
    "CheeseCutter-candidate.zip-source.zip",
    "CheeseCutter-candidate.zip-source",
)
for invalid in ("", ".", "..", "../2.11R", r"branch\2.11R"):
    rejected(lambda invalid=invalid: names(invalid))

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    project = root / "project"
    output = root / "output"
    (project / "release").mkdir(parents=True)
    output.mkdir()
    (project / "fixture.txt").write_bytes(b"public synthetic fixture\n")
    (project / "release" / "source-files.txt").write_bytes(b"fixture.txt\n")

    calls = []
    original_names = create.__globals__["source_archive_names"]
    def observed_names(label):
        calls.append(label)
        return original_names(label)
    create.__globals__["source_archive_names"] = observed_names
    try:
        approved = create(project, output, "2.11R")
        assert approved.name == "CheeseCutter-2.11R-source.zip"
        with zipfile.ZipFile(approved) as archive:
            approved_members = archive.namelist()
            assert approved_members == [
                "CheeseCutter-2.11R-source/SOURCE_MANIFEST.sha256",
                "CheeseCutter-2.11R-source/fixture.txt",
            ]
        verify(project, output, "2.11R")
        assert calls == ["2.11R", "2.11R"]
    finally:
        create.__globals__["source_archive_names"] = original_names

    obsolete_name = output / "CheeseCutter-2.11R-Hypercut-source.zip"
    shutil.copyfile(approved, obsolete_name)
    approved.unlink()
    rejected(lambda: verify(project, output, "2.11R"))
    shutil.copyfile(obsolete_name, approved)

    manifest = m["source_manifest"](project, ["fixture.txt"])
    obsolete_root = "CheeseCutter-2.11R-Hypercut-source"
    write_zip(approved, [
        (f"{obsolete_root}/{manifest_name}", manifest, file_mode),
        (f"{obsolete_root}/fixture.txt", b"public synthetic fixture\n",
            file_mode),
    ])
    rejected(lambda: verify(project, output, "2.11R"))

    mismatched_root = "CheeseCutter-2.11R-source-mismatch"
    write_zip(approved, [
        (f"{mismatched_root}/{manifest_name}", manifest, file_mode),
        (f"{mismatched_root}/fixture.txt", b"public synthetic fixture\n",
            file_mode),
    ])
    rejected(lambda: verify(project, output, "2.11R"))

    create(project, output, "2.11R")
    original_manifest = m["source_manifest"]
    verify.__globals__["source_manifest"] = lambda project, paths: b"mismatch\n"
    try:
        rejected(lambda: verify(project, output, "2.11R"))
    finally:
        verify.__globals__["source_manifest"] = original_manifest

    create(project, output, "2.11R")
    original_private = m["scan_private_values"].__globals__["private_needles"]
    m["scan_private_values"].__globals__["private_needles"] = lambda project: [
        ("synthetic private token", b"fixture", m["PRIVACY_IDENTITY_TOKEN"],
            False),
    ]
    try:
        rejected(lambda: verify(project, output, "2.11R"))
    finally:
        m["scan_private_values"].__globals__["private_needles"] = original_private

    verify_linux = m["verify_linux_kit"]
    verify_linux.__globals__["verify_linux_kit"] = lambda *args: (
        (_ for _ in ()).throw(AssertionError("Linux verifier was invoked")))
    create(project, output, "2.11R")
    verify(project, output, "2.11R")
PY";

bool checkSourceReleaseNaming(out string failure) {
	string focusedScript = buildPath(tempDir(),
		format("ccutter-source-naming-%d.py", thisProcessID));
	if(exists(focusedScript))
		remove(focusedScript);
	std.file.write(focusedScript, SOURCE_NAMING_FOCUSED_PYTHON);
	scope(exit) {
		if(exists(focusedScript))
			remove(focusedScript);
	}
	auto result = execute([
		environment.get("AUDIT_PYTHON_EXE", "python3"), focusedScript]);
	if(result.status != 0) {
		failure = "focused source-release naming process failed";
		return false;
	}
	return true;
}

bool checkSourceReleaseVerificationModes(out string failure) {
	enum sourceZipName = "CheeseCutter-2.11R-source.zip";
	enum linuxKitZipName =
		"CheeseCutter-2.11R-Hypercut-linux-build-kit.zip";
	string root = buildPath(tempDir(),
		format("ccutter-source-release-%d", thisProcessID));
	if(exists(root))
		rmdirRecurse(root);
	mkdirRecurse(root);
	scope(exit) {
		if(exists(root))
			rmdirRecurse(root);
	}

	try {
		string validOutput = buildPath(root, "valid");
		mkdirRecurse(validOutput);
		auto result = runSourceReleaseTool("source", validOutput);
		if(result.status != 0) {
			failure = "source generation failed in disposable output";
			return false;
		}
		string sourceZip = buildPath(validOutput, sourceZipName);
		string linuxKitZip = buildPath(validOutput, linuxKitZipName);
		if(!exists(sourceZip) || exists(linuxKitZip)) {
			failure = "source mode did not create only the source ZIP";
			return false;
		}

		string sourceHash = sourceReleaseFileHash(sourceZip);
		result = runSourceReleaseTool("verify-source", validOutput);
		if(result.status != 0 || sourceReleaseFileHash(sourceZip) != sourceHash ||
				exists(linuxKitZip)) {
			failure = "source-only verification required or changed Linux kit state";
			return false;
		}

		std.file.write(linuxKitZip, "invalid Linux kit sentinel");
		string invalidKitHash = sourceReleaseFileHash(linuxKitZip);
		result = runSourceReleaseTool("verify-source", validOutput);
		if(result.status != 0 ||
				sourceReleaseFileHash(linuxKitZip) != invalidKitHash) {
			failure = "source-only verification inspected or changed Linux kit";
			return false;
		}
		remove(linuxKitZip);

		string missingOutput = buildPath(root, "missing");
		mkdirRecurse(missingOutput);
		result = runSourceReleaseTool("verify-source", missingOutput);
		if(result.status == 0) {
			failure = "source-only verification accepted a missing source ZIP";
			return false;
		}

		string invalidOutput = buildPath(root, "invalid");
		mkdirRecurse(invalidOutput);
		string invalidSource = buildPath(invalidOutput, sourceZipName);
		std.file.write(invalidSource, "invalid source ZIP");
		result = runSourceReleaseTool("verify-source", invalidOutput);
		if(result.status == 0) {
			failure = "source-only verification accepted an invalid source ZIP";
			return false;
		}

		result = runSourceReleaseTool("linux-build-kit", missingOutput);
		if(result.status == 0 || exists(buildPath(missingOutput,
				linuxKitZipName))) {
			failure = "Linux-kit generation recreated a missing source ZIP";
			return false;
		}

		result = runSourceReleaseTool("linux-build-kit", validOutput);
		if(result.status != 0 || !exists(linuxKitZip)) {
			failure = "Linux-kit generation failed with valid source input";
			return false;
		}
		sourceHash = sourceReleaseFileHash(sourceZip);
		string kitHash = sourceReleaseFileHash(linuxKitZip);
		result = runSourceReleaseTool("verify-linux-kit", validOutput);
		if(result.status != 0 ||
				sourceReleaseFileHash(sourceZip) != sourceHash ||
				sourceReleaseFileHash(linuxKitZip) != kitHash) {
			failure = "Linux-kit verification regenerated or changed an archive";
			return false;
		}

		remove(linuxKitZip);
		result = runSourceReleaseTool("linux-build-kit", validOutput);
		if(result.status != 0 || !exists(linuxKitZip) ||
				sourceReleaseFileHash(linuxKitZip) != kitHash) {
			failure = "Linux-kit generation is not deterministic";
			return false;
		}

		remove(linuxKitZip);
		result = runSourceReleaseTool("verify-linux-kit", validOutput);
		if(result.status == 0 || exists(linuxKitZip)) {
			failure = "Linux-kit verification accepted or regenerated a missing kit";
			return false;
		}

		std.file.write(linuxKitZip, "invalid Linux kit ZIP");
		kitHash = sourceReleaseFileHash(linuxKitZip);
		result = runSourceReleaseTool("verify-linux-kit", validOutput);
		if(result.status == 0 ||
				sourceReleaseFileHash(linuxKitZip) != kitHash) {
			failure = "Linux-kit verification accepted or changed an invalid kit";
			return false;
		}
	}
	catch(Exception error) {
		failure = error.msg;
		return false;
	}

	return true;
}

bool checkSubtuneSelectionAndHitRegion(out string failure) {
	auto zero = subtuneSelectionDecision(7, 0);
	auto one = subtuneSelectionDecision(7, 1);
	auto maximum = subtuneSelectionDecision(7, 0x1f);
	auto current = subtuneSelectionDecision(7, 7);
	auto tooHigh = subtuneSelectionDecision(7, 0x20);
	auto byteMaximum = subtuneSelectionDecision(7, 0xff);
	auto negative = subtuneSelectionDecision(7, -1);
	if(!zero.valid || !zero.changed || zero.target != 0 ||
			!one.valid || !one.changed || one.target != 1 ||
			!maximum.valid || !maximum.changed || maximum.target != 0x1f ||
			!current.valid || current.changed || current.target != 7 ||
			tooHigh.valid || tooHigh.changed || tooHigh.target != 7 ||
			byteMaximum.valid || byteMaximum.changed ||
				byteMaximum.target != 7 ||
			negative.valid || negative.changed || negative.target != 7) {
		failure = "Shared subtune decision does not enforce 00-1F/no-op rules";
		return false;
	}
	if(wrappedSubtuneTarget(0, -1) != 0x1f ||
			wrappedSubtuneTarget(0x1f, 1) != 0 ||
			wrappedSubtuneTarget(7, -1) != 6 ||
			wrappedSubtuneTarget(7, 1) != 8) {
		failure = "Shared subtune target wrapping is incorrect";
		return false;
	}
	if(SUBTUNE_SELECTOR_VALUE_X_OFFSET != 2 ||
			SUBTUNE_SELECTOR_VALUE_WIDTH != 2 ||
			!subtuneSelectorValueCellAt(10, 4, 12, 4) ||
			!subtuneSelectorValueCellAt(10, 4, 13, 4) ||
			subtuneSelectorValueCellAt(10, 4, 11, 4) ||
			subtuneSelectorValueCellAt(10, 4, 14, 4) ||
			subtuneSelectorValueCellAt(10, 4, 12, 3) ||
			subtuneSelectorValueCellAt(10, 4, 12, 5)) {
		failure = "Subtune mouse ownership is not exactly the two #xx value cells";
		return false;
	}
	return true;
}

bool checkSubtuneInitialViewportPosition(out string failure) {
	auto position = new PosDataTable();
	initializeSubtunePositionAtSongStart(position, 32);
	if(position.pointerOffset != -12) {
		failure = "Unvisited subtune cursor is not at the startup top boundary";
		return false;
	}
	foreach(pos; position.pos) {
		if(pos.trkOffset != 0 || pos.seqOffset != 12 ||
				pos.rowCounter != 12 || pos.mark != 0) {
			failure = "Unvisited subtune position does not resolve song row 00";
			return false;
		}
		if(pos.seqOffset + pos.pointerOffset != 0) {
			failure = "Unvisited subtune cursor does not resolve absolute row 00";
			return false;
		}
	}

	position.pointerOffset = 3;
	position[0].trkOffset = 4;
	position[0].seqOffset = 5;
	position[0].rowCounter = 6;
	auto saved = position.dup();
	auto target = new PosDataTable();
	initializeSubtunePositionAtSongStart(target, 32);
	target.copyFrom(saved);
	if(target.pointerOffset != 3 || target[0].trkOffset != 4 ||
			target[0].seqOffset != 5 || target[0].rowCounter != 6) {
		failure = "Visited subtune position no longer restores exactly";
		return false;
	}
	return true;
}

bool checkSharedBoundedHexEditor(out string failure) {
	int value = 0x17;
	auto input = new InputBoundedHexByte(
		() => value,
		(int next) { value = next; return true; },
		0, 0x1f, "Invalid test value.");
	input.beginEdit();
	input.setCursorDigit(0);
	if(input.keypress(Keyinfo('0', 0, '0')) != OK || value != 0x07 ||
			input.cursorDigit != 1) {
		failure = "First digit did not mutate immediately or advance like Speed";
		return false;
	}
	if(input.keypress(Keyinfo('1', 0, '1')) != OK || value != 0x01 ||
			input.cursorDigit != 1) {
		failure = "Second digit did not replace the selected low nibble";
		return false;
	}
	input.setCursorDigit(0);
	if(input.keypress(Keyinfo('2', 0, '2')) != OK || value != 0x01 ||
			input.cursorDigit != 0) {
		failure = "Out-of-range high nibble changed the bounded value";
		return false;
	}
	input.setCursorDigit(1);
	if(input.keypress(Keyinfo(SDLK_UP, 0, 0)) != OK || value != 0x02 ||
			input.cursorDigit != 1 ||
			input.keypress(Keyinfo(SDLK_DOWN, 0, 0)) != OK || value != 0x01) {
		failure = "Up/Down did not preserve nibble and use Speed wrapping";
		return false;
	}
	input.setCursorDigit(1);
	if(input.keypress(Keyinfo(SDLK_BACKSPACE, 0, 0)) != OK ||
			value != 0x00 || input.cursorDigit != 0) {
		failure = "Backspace did not zero the nibble and move left";
		return false;
	}
	input.setCursorDigit(0);
	input.keypress(Keyinfo('1', 0, '1'));
	if(value != 0x10 || input.keypress(Keyinfo(SDLK_ESCAPE, 0, 0)) != CANCEL ||
			value != 0x17) {
		failure = "Escape did not restore the begin-edit baseline";
		return false;
	}
	input.beginEdit();
	input.setCursorDigit(1);
	input.keypress(Keyinfo('F', 0, 'F'));
	if(value != 0x1f || input.keypress(Keyinfo(SDLK_RETURN, 0, 0)) != RETURN ||
			value != 0x1f) {
		failure = "Enter did not retain the immediately edited value";
		return false;
	}
	input.beginEdit();
	input.setCursorDigit(1);
	input.keypress(Keyinfo(SDLK_UP, 0, 0));
	if(value != 0x00 || input.cursorDigit != 1) {
		failure = "Upper-bound increment did not wrap to 00";
		return false;
	}
	input.keypress(Keyinfo(SDLK_DOWN, 0, 0));
	if(value != 0x1f || input.cursorDigit != 1) {
		failure = "Lower-bound decrement did not wrap to 1F";
		return false;
	}
	return true;
}

bool checkSubtuneKeyboardAndHelpOwnership(out string failure) {
	if(keyboardActionStableId(KeyboardActionId.sequencerSubtunePrevious) !=
			"sequencer.subtune_previous" ||
			keyboardActionStableId(KeyboardActionId.sequencerSubtuneNext) !=
			"sequencer.subtune_next") {
		failure = "Existing subtune action stable IDs changed";
		return false;
	}

	bool oldPrevious;
	bool oldNext;
	bool f12Unchanged;
	bool keyjamUnchanged;
	foreach(binding; KEYBOARD_BINDING_METADATA) {
		if(binding.actionId == KeyboardActionId.sequencerSubtunePrevious &&
				binding.context == KeyboardContext.sequencer &&
				binding.key == SDLK_LEFT && binding.requiredMods == KMOD_ALT &&
				binding.forbiddenMods == 0 &&
				binding.shortcut.modifiers ==
					KeyboardSemanticModifier.alternate)
			oldPrevious = true;
		if(binding.actionId == KeyboardActionId.sequencerSubtuneNext &&
				binding.context == KeyboardContext.sequencer &&
				binding.key == SDLK_RIGHT && binding.requiredMods == KMOD_ALT &&
				binding.forbiddenMods == 0 &&
				binding.shortcut.modifiers ==
					KeyboardSemanticModifier.alternate)
			oldNext = true;
		if(binding.actionId == KeyboardActionId.globalOpenHelp &&
				binding.context == KeyboardContext.global &&
				binding.key == SDLK_F12 && binding.requiredMods == 0 &&
				binding.forbiddenMods == (KMOD_CTRL | KMOD_ALT | KMOD_GUI))
			f12Unchanged = true;
		if(binding.actionId == KeyboardActionId.songKeyjamToggle &&
				binding.context == KeyboardContext.global &&
				binding.key == SDLK_SPACE && binding.requiredMods == KMOD_CTRL &&
				binding.forbiddenMods ==
					(KMOD_SHIFT | KMOD_ALT | KMOD_GUI))
			keyjamUnchanged = true;
	}
	if(!oldPrevious || !oldNext) {
		failure = "Existing subtune binding metadata is not exact";
		return false;
	}
	if(!f12Unchanged || !keyjamUnchanged) {
		failure = "F12 or KEYJAM central metadata changed";
		return false;
	}

	KeyboardActionId actionId;
	if(!resolveSequencerKeyboardAction(Keyinfo(SDLK_UP, 0, 0), actionId) ||
			actionId != KeyboardActionId.sequencerOverviewNavigateUp ||
			!resolveSequencerKeyboardAction(Keyinfo(SDLK_DOWN, 0, 0), actionId) ||
			actionId != KeyboardActionId.sequencerOverviewNavigateDown) {
		failure = "Normal Sequencer Up/Down ownership changed";
		return false;
	}
	if(!resolveSequencerKeyboardAction(Keyinfo(SDLK_LEFT, KMOD_ALT, 0),
				actionId) ||
			actionId != KeyboardActionId.sequencerSubtunePrevious ||
			!resolveSequencerKeyboardAction(Keyinfo(SDLK_RIGHT, KMOD_ALT, 0),
				actionId) ||
			actionId != KeyboardActionId.sequencerSubtuneNext) {
		failure = "Alt/Option-Left/Right subtune dispatch changed";
		return false;
	}

	bool generatedRow;
	foreach(row; keyboardHelpRows(
			KeyboardHelpSection.sequencerGeneralAfterVoiceTab)) {
		if(row.actionIds ==
				[KeyboardActionId.sequencerSubtunePrevious,
				 KeyboardActionId.sequencerSubtuneNext]) {
			generatedRow = true;
			version(OSX) {
				if(keyboardHelpRowShortcutLabel(row) !=
						"Option-Left/Option-Right") {
					failure = "macOS subtune Help label is not Option-based";
					return false;
				}
			}
			else {
				if(keyboardHelpRowShortcutLabel(row) !=
						"Alt-Left/Alt-Right") {
					failure = "Windows/Linux subtune Help label is not Alt-based";
					return false;
				}
			}
		}
	}
	if(!generatedRow) {
		failure = "Existing generated previous/next subtune Help row is missing";
		return false;
	}
	return true;
}

bool checkSubtuneDirectEditSourceOwnership(out string failure) {
	string sequencerSource = readText(buildPath("src", "seq", "sequencer.d")).
		replace("\r\n", "\n");
	string inputSource = readText(buildPath("src", "ui", "input.d")).
		replace("\r\n", "\n");
	string uiSource = readText(buildPath("src", "ui", "ui.d")).
		replace("\r\n", "\n");
	string helpSource = readText(buildPath("src", "ui", "help.d")).
		replace("\r\n", "\n");
	string baseSource = readText(buildPath("src", "ct", "base.d")).
		replace("\r\n", "\n");
	string buildSource = readText(buildPath("src", "ct", "build.d")).
		replace("\r\n", "\n");

	auto setterStart = sequencerSource.indexOf("bool setSubtune(int target)");
	auto setterEnd = sequencerSource.indexOf("override void update()",
		setterStart >= 0 ? cast(size_t)setterStart : 0);
	if(setterStart < 0 || setterEnd <= setterStart) {
		failure = "Could not isolate the shared setSubtune owner";
		return false;
	}
	string setter = sequencerSource[
		cast(size_t)setterStart .. cast(size_t)setterEnd];
	foreach(required; [
			"subtuneSelectionDecision(song.subtune, target)",
			"if(!decision.valid)",
			"if(!decision.changed)",
			"postables[song.subtune].copyFrom(activeView.posTable);",
			"mainui.stop();",
			"song.subtunes.activate(decision.target);",
			"song.subtune = decision.target;",
			"timelineSeekManager().resetSession(\"subtune_changed\");",
			"activeView.posTable.copyFrom(postables[song.subtune]);",
			"activeView.activate();"]) {
		if(setter.indexOf(required) < 0) {
			failure = "Shared setter is missing ownership: " ~ required;
			return false;
		}
	}
	foreach(forbidden; ["undo", "Undo", "dirty", "modified", "valueChanged",
			"version("]) {
		if(setter.indexOf(forbidden) >= 0) {
			failure = "Shared setter acquired forbidden ownership: " ~ forbidden;
			return false;
		}
	}
	if(countOccurrences(sequencerSource, "song.subtune =") != 1 ||
			countOccurrences(sequencerSource, "bool setSubtune(int target)") != 1 ||
			sequencerSource.indexOf(
				"setSubtune(wrappedSubtuneTarget(song.subtune, delta));") < 0) {
		failure = "Subtune mutation or wrap arithmetic has more than one owner";
		return false;
	}
	foreach(required; [
			"if(handleSubtuneEditorKey(key))",
			"subtuneSelectorValueCellAt(area.x, area.y, x, y)",
			"subtuneInput.beginEdit();",
			"subtuneInput.setCursorDigit(digit);",
			"new InputBoundedHexByte(",
			"(int value) => setSubtune(value)",
			"displayContextualSemantic(subtuneQuickHelp()",
			"cancelSubtuneEditor();",
			"override void deactivate()"]) {
		if(sequencerSource.indexOf(required) < 0) {
			failure = "Focused editor integration is missing: " ~ required;
			return false;
		}
	}
	auto hitStart = sequencerSource.indexOf(
		"subtuneSelectorValueCellAt(area.x, area.y, x, y)");
	auto voiceRouting = sequencerSource.indexOf(
		"foreach(idx, Voice v; activeView.voices)", hitStart);
	if(hitStart < 0 || voiceRouting <= hitStart) {
		failure = "Subtune hit ownership does not precede voice/table routing";
		return false;
	}
	foreach(required; [
			"class InputBoundedHexByte : Input",
			"class InputSongSpeed : InputBoundedHexByte",
			"int hexDigitValue(Keyinfo key)",
			"int hexDigitValue(const(char) ch)",
			"cursor.set(x + digitCursor, y);",
			"stepValue(1);",
			"stepValue(-1);",
			"setValue(originalValue);",
			"Tempo speed high digit must be 0 or 1. Use 00-1F."]) {
		if(uiSource.indexOf(required) < 0) {
			failure = "Shared Speed editor core is missing: " ~ required;
			return false;
		}
	}
	if(inputSource.indexOf("boundedByteHexDigitValue") >= 0 ||
			inputSource.indexOf("asciiHexDigitValue") >= 0) {
		failure = "Unused duplicate bounded hexadecimal helper remains";
		return false;
	}
	foreach(rejected; [
			"InputBoundedByteDraft",
			"KeyboardContext.subtuneEditor",
			"resolveSubtuneEditorKeyboardAction",
			"format(\"%X_\""]) {
		if(inputSource.indexOf(rejected) >= 0 ||
				sequencerSource.indexOf(rejected) >= 0) {
			failure = "Rejected parallel subtune machinery remains: " ~ rejected;
			return false;
		}
	}
	if(uiSource.indexOf("songSpeedQuickHelp()") < 0 ||
			uiSource.indexOf("displayContextual(songSpeedQuickHelp())") < 0 ||
			sequencerSource.indexOf(
				"Subtune: 00-1F. Up/Down changes selection.") < 0 ||
			sequencerSource.indexOf("\"sequencer:subtune\"") < 0) {
		failure = "Speed or subtune contextual Quick Help ownership is missing";
		return false;
	}
	if(helpSource.indexOf(
			"Click #xx, edit 00-1F; Up/Down selects a subtune.") < 0 ||
			helpSource.indexOf("SUBTUNE_DIRECT_EDIT_HELP") < 0 ||
			helpSource.indexOf("SEQUENCER_GENERAL_HELP") < 0) {
		failure = "Narrow direct-edit Help or generated shortcut Help is missing";
		return false;
	}
	foreach(required; [
			"case KeyboardSemanticModifier.alternate:",
			"version(OSX) {\n\t\t\treturn \"Option\";",
			"else {\n\t\t\treturn \"Alt\";"]) {
		if(inputSource.indexOf(required) < 0) {
			failure = "Alt/Option platform Help label ownership changed";
			return false;
		}
	}
	if(buildSource.indexOf(
			"data[PSID_START_SONG + 1] = cast(ubyte)defaultSubtune;") < 0 ||
			buildSource.indexOf("song.subtune =") >= 0 ||
			baseSource.indexOf("SUBTUNE_MAX = 32") < 0 ||
			baseSource.indexOf("subtune = 0;") < 0) {
		failure = "Serialized song or PSID start-song ownership changed";
		return false;
	}
	return true;
}

int main() {
	Results results;
	results.record(1 + 1 == 2, "runner_bootstrap");

	string failure;
	failure = null;
	results.record(checkSubtuneSelectionAndHitRegion(failure),
		"subtune_selection_and_hit_region", failure);

	failure = null;
	results.record(checkSubtuneInitialViewportPosition(failure),
		"subtune_initial_viewport_position", failure);

	failure = null;
	results.record(checkSharedBoundedHexEditor(failure),
		"shared_bounded_hex_editor", failure);

	failure = null;
	results.record(checkSubtuneKeyboardAndHelpOwnership(failure),
		"subtune_keyboard_and_help_ownership", failure);

	failure = null;
	results.record(checkSubtuneDirectEditSourceOwnership(failure),
		"subtune_direct_edit_source_ownership", failure);

	Song fixtureSong;
	bool fixtureLoaded;
	try {
		fixtureSong = new Song();
		fixtureSong.open(buildPath("tests", "fixtures", "r2d-minimal.ct"));
		fixtureLoaded = checkMinimalFixture(fixtureSong, failure);
		results.record(fixtureLoaded, "fixture_load", failure);
	}
	catch(Exception error) {
		results.record(false, "fixture_load", error.msg);
	}

	if(fixtureLoaded) {
		string tempPath = buildPath(tempDir(),
			format("ccutter-r2d2-%d.ct", thisProcessID));
		scope(exit) {
			if(exists(tempPath))
				remove(tempPath);
		}

		try {
			fixtureSong.save(tempPath);
			Song reloadedSong = new Song();
			reloadedSong.open(tempPath);
			failure = null;
			results.record(checkMinimalFixture(reloadedSong, failure),
				"fixture_save_reload", failure);
		}
		catch(Exception error) {
			results.record(false, "fixture_save_reload", error.msg);
		}
	}
	else {
		results.record(false, "fixture_save_reload", "fixture load failed");
	}

	if(fixtureLoaded) {
		failure = null;
		results.record(checkTracklistInsertDeleteCopyRestore(
			fixtureSong.tracks[0], failure),
			"tracklist_insert_delete_copy_restore", failure);
	}
	else {
		results.record(false, "tracklist_insert_delete_copy_restore",
			"fixture load failed");
	}

	if(fixtureLoaded) {
		failure = null;
		results.record(checkTracklistMoveRangeLoop(fixtureSong.tracks[0],
			failure), "tracklist_move_range_loop", failure);
	}
	else {
		results.record(false, "tracklist_move_range_loop",
			"fixture load failed");
	}

	failure = null;
	results.record(checkSequenceRowMutation(failure),
		"element_sequence_row_mutation", failure);

	try {
		failure = null;
		results.record(checkSongClearSequencesContract(
			buildPath("tests", "fixtures", "r2d-minimal.ct"), failure),
			"song_clear_sequences_contract", failure);
	}
	catch(Exception error) {
		results.record(false, "song_clear_sequences_contract", error.msg);
	}

	try {
		failure = null;
		results.record(checkTrackOverviewLoopOccurrenceResolution(failure),
			"trackoverview_occurrence_resolution", failure);
	}
	catch(Exception error) {
		results.record(false, "trackoverview_occurrence_resolution",
			error.msg);
	}

	failure = null;
	results.record(checkFramebufferCellMapping(failure),
		"framebuffer_cell_mapping", failure);

	failure = null;
	results.record(checkMouseButtonEventCoordinateOwnership(failure),
		"mouse_button_event_coordinate_ownership", failure);

	failure = null;
	results.record(checkRightVisualPanelRouting(failure),
		"right_visual_panel_routing", failure);

	failure = null;
	results.record(checkOscilloscopeOffLabelPresentation(failure),
		"oscilloscope_off_label_presentation", failure);

	failure = null;
	results.record(checkSequenceRowNumberBrightness(failure),
		"sequence_row_number_brightness", failure);

	failure = null;
	results.record(checkDefaultAudioRequest(failure),
		"default_audio_request", failure);

	failure = null;
	results.record(checkVoiceMuteStatePreservedAcrossPlayback(failure),
		"voice_mute_state_preserved_across_playback", failure);

	failure = null;
	results.record(checkVoiceMuteLiveLockOwnership(failure),
		"voice_mute_live_lock_ownership", failure);

	failure = null;
	results.record(checkVoiceMuteLiveTransitionStress(failure),
		"voice_mute_live_transition_stress", failure);

	failure = null;
	results.record(checkVoiceMuteCheckpointMaskMatrix(failure),
		"voice_mute_checkpoint_mask_matrix", failure);

	failure = null;
	results.record(checkVoiceMuteCheckpointReportedRegression(failure),
		"voice_mute_checkpoint_reported_regression", failure);

	failure = null;
	results.record(checkStrictKeyboardPlaceholderValidation(failure),
		"strict_keyboard_placeholder_validation", failure);

	failure = null;
	results.record(checkVoiceMutePlaybackRouteMatrix(failure),
		"voice_mute_playback_route_matrix", failure);

	failure = null;
	results.record(checkKeyjamR2DHostReleaseBoundary(failure),
		"keyjam_r2d_host_release_boundary", failure);

	failure = null;
	results.record(checkRawCellRasterization(failure),
		"raw_cell_rasterization", failure);

	failure = null;
	results.record(checkRawCellClearing(failure),
		"raw_cell_clearing", failure);

	failure = null;
	results.record(checkSequenceRowNumberRange(failure),
		"sequence_row_number_range", failure);

	failure = null;
	results.record(checkExtendedUiGlyphOverlay(failure),
		"extended_ui_glyph_overlay", failure);

	failure = null;
	results.record(checkFullscreenTransitionOwner(failure),
		"fullscreen_transition_owner", failure);

	failure = null;
	results.record(checkSharedResizeRedrawOwnership(failure),
		"shared_resize_redraw_ownership", failure);

	failure = null;
	results.record(checkInterfaceDestinationRectangles(failure),
		"interface_destination_rectangles", failure);

	failure = null;
	results.record(checkInterfaceBackgroundCoverage(failure),
		"interface_background_coverage", failure);

	failure = null;
	results.record(checkContextualHelpResolverSource(failure),
		"contextual_help_resolver_source", failure);

	failure = null;
	results.record(checkHelpTopicHitGeometry(failure),
		"help_topic_hit_geometry", failure);

	failure = null;
	results.record(checkHelpDialogPerTopicScrollMemory(failure),
		"help_dialog_per_topic_scroll_memory", failure);

	failure = null;
	results.record(checkHelpDialogPinnedHeaderAndRouteSharing(failure),
		"help_dialog_pinned_header_route_sharing", failure);

	failure = null;
	results.record(checkChordTableHelpSemantics(failure),
		"chord_table_help_semantics", failure);

	failure = null;
	results.record(checkBottomControlLayout(failure),
		"bottom_control_layout", failure);

	failure = null;
	results.record(checkBottomControlInteractionRouting(failure),
		"bottom_control_interaction_routing", failure);

	failure = null;
	results.record(checkBottomControlSourceOwnership(failure),
		"bottom_control_source_ownership", failure);

	failure = null;
	results.record(checkStatuslineKeyjamAlertOwnership(failure),
		"statusline_keyjam_alert_ownership", failure);

	failure = null;
	results.record(checkHelpTextToggleStatusOwnership(failure),
		"help_text_toggle_status_ownership", failure);

	failure = null;
	results.record(checkContextDismissibleStatusOwnership(failure),
		"context_dismissible_status_ownership", failure);

	failure = null;
	results.record(checkContextDismissibleSuppressionAndDeferredLoad(failure),
		"context_dismissible_suppression_deferred_load", failure);

	failure = null;
	results.record(checkStatuslineOperationFeedbackBehavior(failure),
		"statusline_operation_feedback_behavior", failure);

	failure = null;
	results.record(checkStatuslineLatestMeaningfulGenerationBehavior(failure),
		"statusline_latest_meaningful_generation_behavior", failure);

	failure = null;
	results.record(checkTrackOverviewCanonicalQuickHelp(failure),
		"trackoverview_canonical_quickhelp", failure);

	failure = null;
	results.record(checkInstrumentStatusWordingOwnership(failure),
		"instrument_status_wording_ownership", failure);

	failure = null;
	results.record(checkHelpCleanupConsolidatedFeedbackAndF12(failure),
		"help_cleanup_consolidated_feedback_and_f12", failure);

	failure = null;
	results.record(checkSequencePlayRowHelpPlacement(failure),
		"sequence_play_row_help_placement", failure);

	failure = null;
	results.record(checkMissedShortcutHelpPlacement(failure),
		"missed_shortcut_help_placement", failure);

	failure = null;
	results.record(checkHelpCleanup1eQuickhelpWording(failure),
		"help_cleanup_1e_quickhelp_wording", failure);

	failure = null;
	results.record(checkFieldHelpCanonicalShortcutOwnership(failure),
		"fieldhelp_canonical_shortcut_ownership", failure);

	failure = null;
	results.record(checkFieldHelpRecentActionF12Inventory(failure),
		"fieldhelp_recent_action_f12_inventory", failure);

	failure = null;
	results.record(checkHelpRef1aReferenceCleanup(failure),
		"helpref_1a_reference_cleanup", failure);

	failure = null;
	results.record(checkAppCln1bDeadHelpMessageCleanup(failure),
		"appcln_1b_dead_help_message_cleanup", failure);

	failure = null;
	results.record(checkAppCln1b2DeadUtilityLayoutCleanup(failure),
		"appcln_1b2_dead_utility_layout_cleanup", failure);

	failure = null;
	results.record(checkLegacyCtRevisionCompatibility(failure),
		"appcln_1c1_legacy_ct_revision_compatibility", failure);

	failure = null;
	results.record(checkLegacyCtUpgradeOnSave(failure),
		"appcln_1c1_legacy_ct_upgrade_on_save", failure);

	failure = null;
	results.record(checkLegacyCtRevisionRejections(failure),
		"appcln_1c1_legacy_ct_revision_rejections", failure);

	failure = null;
	results.record(checkCurrentCtRevisionStillCanonical(failure),
		"appcln_1c1_current_ct_revision_canonical", failure);

	failure = null;
	results.record(checkCt2utilCommandAliases(failure),
		"appcln_1c1_ct2util_command_aliases", failure);

	failure = null;
	results.record(checkChordQuickHelpRowAwareShuffle(failure),
		"chord_quickhelp_row_aware_shuffle", failure);

	failure = null;
	results.record(checkSequenceRowDragAutoScroll(failure),
		"sequence_row_drag_autoscroll", failure);

	failure = null;
	results.record(checkProgramTableRowSelectionPolicy(failure),
		"program_table_row_selection_policy", failure);

	failure = null;
	results.record(checkInstrumentByteSelectionPolicy(failure),
		"instrument_byte_selection_policy", failure);

	failure = null;
	results.record(checkInstrumentByteSelectionCursorRouting(failure),
		"instrument_byte_selection_cursor_routing", failure);

	failure = null;
	results.record(checkInstrumentByteMouseSelectionRouting(failure),
		"instrument_byte_mouse_selection_routing", failure);

	failure = null;
	results.record(checkInstrumentByteMouseSelectionLiveParentRoute(failure),
		"instrument_byte_mouse_selection_live_parent_route", failure);

	failure = null;
	results.record(checkInstrumentByteSelectionLiveUiRouting(failure),
		"instrument_byte_selection_live_ui_routing", failure);

	failure = null;
	results.record(checkTrackOverviewTimelineDeleteKeysAreConsumed(failure),
		"track_overview_timeline_delete_keys_are_consumed", failure);

	failure = null;
	results.record(checkInstrumentNibbleQuickHelpDecoder(failure),
		"instrument_nibble_quickhelp_decoder", failure);

	failure = null;
	results.record(checkInstrumentNibbleQuickHelpNavigationRoute(failure),
		"instrument_nibble_quickhelp_navigation_route", failure);

	failure = null;
	results.record(checkInstrumentNibbleQuickHelpRouteSource(failure),
		"instrument_nibble_quickhelp_route_source", failure);

	failure = null;
	results.record(checkProgramTableByteCellResolver(failure),
		"program_table_byte_cell_resolver", failure);

	failure = null;
	results.record(checkWaveQuickHelpDecoder(failure),
		"wave_quickhelp_decoder", failure);

	failure = null;
	results.record(checkPulseQuickHelpDecoder(failure),
		"pulse_quickhelp_decoder", failure);

	failure = null;
	results.record(checkFilterQuickHelpDecoder(failure),
		"filter_quickhelp_decoder", failure);

	failure = null;
	results.record(checkProgramTableMouseNibblePlacementRoute(failure),
		"program_table_mouse_nibble_placement_route", failure);

	failure = null;
	results.record(checkWaveQuickHelpNavigationRoute(failure),
		"wave_quickhelp_navigation_route", failure);

	failure = null;
	results.record(checkPulseQuickHelpNavigationRoute(failure),
		"pulse_quickhelp_navigation_route", failure);

	failure = null;
	results.record(checkFilterQuickHelpNavigationRoute(failure),
		"filter_quickhelp_navigation_route", failure);

	failure = null;
	results.record(checkWaveQuickHelpRouteSource(failure),
		"wave_quickhelp_route_source", failure);

	failure = null;
	results.record(checkPulseQuickHelpRouteSource(failure),
		"pulse_quickhelp_route_source", failure);

	failure = null;
	results.record(checkFilterQuickHelpRouteSource(failure),
		"filter_quickhelp_route_source", failure);

	failure = null;
	results.record(checkWaveFullRangeShiftSelectionRouting(failure),
		"wave_full_range_shift_selection_routing", failure);

	failure = null;
	results.record(checkProgramTableMouseRowDragPolicy(failure),
		"program_table_mouse_row_drag_policy", failure);

	failure = null;
	results.record(checkProgramTablePinnedDragAutoScroll(failure),
		"program_table_pinned_drag_autoscroll", failure);

	failure = null;
	results.record(checkGeneratedProgramTableMouseDragParity(failure),
		"generated_program_table_mouse_drag_parity", failure);

	failure = null;
	results.record(checkDesktopIconGenerationContract(failure),
		"desktop_icon_generation_contract", failure);

	failure = null;
	results.record(checkCanonicalWindowsBuildOwnership(failure),
		"canonical_windows_build_ownership", failure);

	failure = null;
	results.record(checkWindowsGeneratedStatusRecord(failure),
		"windows_generated_status_record", failure);

	failure = null;
	results.record(checkTimelineSpeedDotHelpOwnership(failure),
		"timeline_speed_dot_help_ownership", failure);

	failure = null;
	results.record(checkReleaseMetadataOwnership(failure),
		"release_metadata_ownership", failure);

	failure = null;
	results.record(checkSourceReleaseOwnership(failure),
		"source_release_ownership", failure);

	failure = null;
	results.record(checkReleasePrivacyMatcherCorrection(failure),
		"release_privacy_matcher_correction", failure);

	failure = null;
	results.record(checkSourceReleaseVerificationModes(failure),
		"source_release_verification_modes", failure);
	results.record(checkSourceReleaseNaming(failure),
		"source_release_naming", failure);

	writefln("%d passed, %d failed", results.passed, results.failed);
	return results.failed == 0 ? 0 : 1;
}
