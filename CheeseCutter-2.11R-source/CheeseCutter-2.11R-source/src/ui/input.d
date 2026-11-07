/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.input;
import derelict.sdl2.sdl;
import com.fb;
import com.session;
import com.util;
import ct.base;
import seq.sequencer;
import audio.player;
import ui.ui;
import std.string;
import std.utf;
import std.stdio : stderr;
import std.conv;
import std.traits : EnumMembers;

enum { RETURN = -1, CANCEL = -2, OK = 0, WRAP = 1, WRAPR, WRAPL, EXIT, IllegalValue }

alias ValueChangedCallback = void delegate();

mixin template ValueChangedHandler() {
	private ValueChangedCallback valueChangedCallback = null;
	private void valueChanged() {
		if(valueChangedCallback !is null)
			valueChangedCallback();
	}

	void setValueChangedCallback(ValueChangedCallback cb) {
		this.valueChangedCallback = cb;
	}
}


struct Keyinfo {
	int key, mods, unicode, scancode;
	alias key raw;

	this(int key, int mods, int unicode) {
		this(key, mods, unicode, 0);
	}

	this(int key, int mods, int unicode, int scancode) {
		this.key = key;
		this.mods = mods;
		this.unicode = unicode;
		this.scancode = scancode;
	}
}

// Canonical keyboard registry ownership:
// - add binding facts and short Help placement here;
// - connect the action to the behavior-owning consumer;
// - use ui.help only for rendering, long prose, diagrams, or mouse guidance.

// Registry model and stable action identity.

enum KeyboardActionId {
	globalOpenHelp,
	playbackPlayFromMark,
	playbackPlayFromMarkTracking,
	playbackPlayFromStart,
	playbackPlayFromStartTracking,
	playbackPlayFromCursor,
	playbackStop,
	editorUndo,
	editorRedo,
	voiceToggleMute1,
	voiceToggleMute2,
	voiceToggleMute3,
	helpClose,
	helpScrollUp,
	helpScrollDown,
	helpPageUp,
	helpPageDown,
	helpTop,
	helpBottom,
	helpTopicPrevious,
	helpTopicNext,
	saveExportFormatCt,
	saveExportFormatPrg,
	saveExportFormatSid,
	saveExportNextField,
	sequencerViewTrackTable,
	sequencerViewTrackTableWithTrackList,
	sequencerViewSequenceEditor,
	sequencerViewTrackMap,
	sequencerViewToggleTrackSequence,
	sequencerNavigateVoicePrevious,
	sequencerNavigateVoiceNext,
	sequencerCursorStepSet,
	sequencerCursorStepDecrease,
	sequencerCursorStepIncrease,
	sequencerSubtunePrevious,
	sequencerSubtuneNext,
	sequencerOverviewNavigateUp,
	sequencerOverviewNavigateDown,
	sequencerOverviewNavigatePageUp,
	sequencerOverviewNavigatePageDown,
	sequencerOverviewNavigateHome,
	sequencerOverviewNavigateEnd,
	sequencerViewNavigateUp,
	sequencerViewNavigateDown,
	sequencerViewNavigatePageUp,
	sequencerViewNavigatePageDown,
	sequencerViewScrollUp,
	sequencerViewScrollDown,
	sequencerViewNavigateLargePageUp,
	sequencerViewNavigateLargePageDown,
	sequencerViewNavigateSongStart,
	sequencerViewNavigateSongEnd,
	sequencerDebugSequenceDialog,
	sequenceRowSelectionExtendUp,
	sequenceRowSelectionExtendDown,
	sequenceRowSelectionExtendPageUp,
	sequenceRowSelectionExtendPageDown,
	sequenceRowSelectionExtendHome,
	sequenceRowSelectionExtendEnd,
	sequenceRowSelectionClear,
	sequenceRowSelectPattern,
	sequenceRowQuickExpand,
	sequenceTransposeSemitoneUp,
	sequenceTransposeSemitoneDown,
	sequenceTransposeOctaveUp,
	sequenceTransposeOctaveDown,
	sequenceRowDeleteSameLength,
	sequenceRowInsertSameLength,
	sequenceRowDeleteShrink,
	sequenceRowInsertGrow,
	sequenceRowExpandSequence,
	sequenceRowShrinkSequence,
	sequencePlayRowAllVoices,
	sequenceRowCopy,
	sequenceRowPaste,
	sequenceSplit,
	sequenceInputOctaveDecrease,
	sequenceInputOctaveIncrease,
	sequenceInputToggleInstrumentAutoinsert,
	sequenceInputClear,
	sequenceInputReuseValue,
	sequenceInputGateOff,
	sequenceInputGateOn,
	sequenceInputTie,
	sequenceInputGrabInstrument,
	trackInputFindUnusedSequence,
	trackInputPreviousSequence,
	trackInputNextSequence,
	trackInputCommitValue,
	trackOverviewLoopAllVoices,
	trackOverviewLoopActiveVoice,
	trackOverviewScrollLeft,
	trackOverviewScrollRight,
	trackOverviewTimelineStepLeft,
	trackOverviewTimelineStepRight,
	trackOverviewTimelinePageUp,
	trackOverviewTimelinePageDown,
	trackOverviewTimelineLargePageUp,
	trackOverviewTimelineLargePageDown,
	trackOverviewTimelineHome,
	trackOverviewTimelineEnd,
	trackOverviewCopyEntries,
	trackOverviewPasteEntries,
	trackOverviewFindUnusedSequence,
	trackOverviewInsertEntry,
	trackOverviewInsertCopyEntry,
	trackOverviewDeleteSelection,
	trackOverviewOpenActiveBlockInSequenceEditor,
	trackOverviewNavigatePreviousBlock,
	trackOverviewNavigateNextBlock,
	trackOverviewUndo,
	trackOverviewRedo,
	trackEntryInsert,
	trackEntryInsertCopy,
	trackEntryDelete,
	trackEntryInsertToEnd,
	trackEntryDeleteToEnd,
	trackEntryInsertAllVoices,
	trackEntryDeleteAllVoices,
	trackEntryCopyPrompt,
	trackEntryPastePrompt,
	trackEntryPasteInsert,
	trackEntryPasteOverwrite,
	trackEntryLoopSetAllVoices,
	trackEntryLoopSetActiveVoice,
	trackEntryTransposeUpFromCursor,
	trackEntryTransposeDownFromCursor,
	trackEntrySwapWithVoice1,
	trackEntrySwapWithVoice2,
	trackEntrySwapWithVoice3,
	trackEntryNavigateStart,
	trackEntryNavigateEnd,
	generatedTableRowDelete,
	generatedTableRowInsert,
	generatedTableRowSelectionExtendUp,
	generatedTableRowSelectionExtendDown,
	generatedTableRowSelectionExtendPageUp,
	generatedTableRowSelectionExtendPageDown,
	generatedTableRowSelectionExtendHome,
	generatedTableRowSelectionExtendEnd,
	generatedTableRowSelectionClear,
	generatedTableRowCopy,
	generatedTableRowPaste,
	workspaceActivateSequencer,
	workspaceActivateVoice1,
	workspaceActivateVoice2,
	workspaceActivateVoice3,
	workspaceActivateInstrument,
	workspaceActivateWave,
	workspaceActivatePulse,
	workspaceActivateFilter,
	workspaceActivateCommand,
	workspaceActivateChord,
	workspaceActivateTitle,
	workspaceActivateSpeed,
	appAbout,
	appAudioSettings,
	fileLoadDialog,
	fileSaveExportDialog,
	fileQuickSave,
	fileDialogConfirm,
	appQuitConfirm,
	sequenceOpenAppendDialog,
	sequenceOpenCopyDialog,
	songSpeedDecrease,
	songSpeedIncrease,
	songMultispeedDecrease,
	songMultispeedIncrease,
	songKeyjamToggle,
	uiToggleHelpText,
	songClearSequencesConfirm,
	songOptimizeConfirm,
	sequencerHighlightIncrease,
	sequencerHighlightDecrease,
	sequencerRowCountersToggle,
	sequencerRelativeNotesToggle,
	sequencerHighlightOffsetSet,
	sequencerPlaybackMarkSet,
	sequencerPlaybackMarkSetActiveVoice,
	sequencerPlaybackMarkJump,
	sequencerPlaybackMarkCenter,
	instrumentCopy,
	instrumentPaste,
	instrumentByteSelectionExtendLeft,
	instrumentByteSelectionExtendRight,
	waveSeekCurrentInstrumentWave,
	instrumentDeleteConfirm,
	instrumentSaveDialog,
	instrumentLoadDialog,
	songSidModelToggle,
	songSidFilterPresetNext,
	songSidFilterPresetPrevious,
	uiVisualModeToggle,
	uiSubwindowPrevious,
	uiSubwindowNext,
	uiMainWindowPrevious,
	uiMainWindowNext,
	uiBaseOctaveDecrease,
	uiBaseOctaveIncrease,
	uiInstrumentPrevious,
	uiInstrumentNext,
	uiFollowInstrumentPointer,
	uiToggleFullscreen,
	uiToggleInterpolation,
	playbackTrackingToggle,
	playbackFastForward,
	playbackFastForwardLarge
}

enum KeyboardContext {
	global,
	editor,
	helpDialog,
	fileDialog,
	saveExportDialog,
	sequencer,
	sequenceEditor,
	sequenceInput,
	sequenceValueInput,
	cursorStepInput,
	noteInput,
	trackInput,
	trackOverview,
	trackOverviewBlock,
	trackOverviewTimeline,
	trackEntry,
	generatedTable,
	instrumentTable,
	waveTable,
	workspaceNavigation,
	uiWindowSwitcher,
	uiTopLevel,
	uiGlobal
}

enum KeyboardBindingKeyModel {
	translatedKeyinfo,
	translatedUnicode,
	physicalLabelOnly
}

// Short Help placement is registry data. ui.help converts these structured
// rows into display rows and owns all wrapping and page composition.

enum KeyboardHelpSection {
	trackOverviewNavigation,
	trackOverviewEdit,
	trackOverviewDisplay,
	mainApp,
	mainPlayback,
	mainSongBeforeClicks,
	mainSongAfterClicks,
	mainTableNavigation,
	sequencerGeneralBeforeVoiceTab,
	sequencerGeneralAfterVoiceTab,
	sequencerViews,
	sequencerNavigation,
	sequenceEditingSequencer,
	sequenceDialogs,
	trackTableView,
	trackMapView,
	trackLoop,
	globalUndoRedo,
	sequencePlaybackMarkStart,
	helpDialog,
	sequenceRowClipboard,
	mainInstrumentTable,
	mainInstrumentSelection,
	saveExport,
	sequenceTranspose,
	sequenceEditingInput,
	noteColumn,
	trackColumn,
	trackColumnAdvanced,
	sequenceRowPlatformEdit,
	trackColumnPlatform,
	waveTableHelp
}

struct KeyboardHelpPlacement {
	KeyboardHelpSection section;
	int order;
	string description;
}

struct KeyboardHelpRow {
	int order;
	string description;
	KeyboardActionId[] actionIds;
	string contextStableId;
}

private struct KeyboardHelpGroup {
	KeyboardHelpSection section;
	int order;
	KeyboardActionId[] actionIds;
	string description;
	string contextStableId;
}

enum KeyboardSemanticModifier {
	none = 0,
	primary = 1 << 0,
	alternate = 1 << 1,
	shift = 1 << 2,
	physicalControl = 1 << 3
}

private enum int KEYBOARD_SAME_SEMANTIC_MODIFIERS = -1;

struct KeyboardShortcutSemantics {
	int modifiers;
	int macOSModifiersOverride;
	string keyLabelOverride;
	string macOSKeyLabelOverride;

	this(int modifiers,
		 int macOSModifiersOverride = KEYBOARD_SAME_SEMANTIC_MODIFIERS,
		 string keyLabelOverride = "",
		 string macOSKeyLabelOverride = "") {
		this.modifiers = modifiers;
		this.macOSModifiersOverride = macOSModifiersOverride;
		this.keyLabelOverride = keyLabelOverride;
		this.macOSKeyLabelOverride = macOSKeyLabelOverride;
	}
}

struct KeyboardBinding {
	KeyboardActionId actionId;
	KeyboardContext context;
	KeyboardBindingKeyModel keyModel;
	int key;
	int requiredMods;
	int forbiddenMods;
	KeyboardShortcutSemantics shortcut;
	string description;
	bool implemented;
	string notes;
	KeyboardHelpPlacement[] help;
}

private KeyboardBinding keyboardBindingWithHelp(KeyboardBinding binding,
		KeyboardHelpPlacement[] help) {
	binding.help = help;
	return binding;
}

// Compile-time registry validation reports structured issues before the final
// static assertion below.

struct KeyboardMetadataAuditIssue {
	string code;
	string message;
}

string keyboardActionStableId(KeyboardActionId actionId) {
	final switch(actionId) {
	case KeyboardActionId.globalOpenHelp:
		return "global.open_help";
	case KeyboardActionId.appAbout:
		return "app.about";
	case KeyboardActionId.appAudioSettings:
		return "app.audio_settings";
	case KeyboardActionId.fileLoadDialog:
		return "file.load_dialog";
	case KeyboardActionId.fileSaveExportDialog:
		return "file.save_export_dialog";
	case KeyboardActionId.fileQuickSave:
		return "file.quick_save";
	case KeyboardActionId.fileDialogConfirm:
		return "file.dialog_confirm";
	case KeyboardActionId.appQuitConfirm:
		return "app.quit_confirm";
	case KeyboardActionId.sequenceOpenAppendDialog:
		return "sequence.open_append_dialog";
	case KeyboardActionId.sequenceOpenCopyDialog:
		return "sequence.open_copy_dialog";
	case KeyboardActionId.songSpeedDecrease:
		return "song.speed_decrease";
	case KeyboardActionId.songSpeedIncrease:
		return "song.speed_increase";
	case KeyboardActionId.songMultispeedDecrease:
		return "song.multispeed_decrease";
	case KeyboardActionId.songMultispeedIncrease:
		return "song.multispeed_increase";
	case KeyboardActionId.songKeyjamToggle:
		return "song.keyjam_toggle";
	case KeyboardActionId.uiToggleHelpText:
		return "ui.toggle_help_text";
	case KeyboardActionId.songClearSequencesConfirm:
		return "song.clear_sequences_confirm";
	case KeyboardActionId.songOptimizeConfirm:
		return "song.optimize_confirm";
	case KeyboardActionId.sequencerHighlightIncrease:
		return "sequencer.highlight_increase";
	case KeyboardActionId.sequencerHighlightDecrease:
		return "sequencer.highlight_decrease";
	case KeyboardActionId.sequencerRowCountersToggle:
		return "sequencer.row_counters_toggle";
	case KeyboardActionId.sequencerRelativeNotesToggle:
		return "sequencer.relative_notes_toggle";
	case KeyboardActionId.sequencerHighlightOffsetSet:
		return "sequencer.highlight_offset_set";
	case KeyboardActionId.sequencerPlaybackMarkSet:
		return "sequencer.playback_mark_set";
	case KeyboardActionId.sequencerPlaybackMarkSetActiveVoice:
		return "sequencer.playback_mark_set_active_voice";
	case KeyboardActionId.sequencerPlaybackMarkJump:
		return "sequencer.playback_mark_jump";
	case KeyboardActionId.sequencerPlaybackMarkCenter:
		return "sequencer.playback_mark_center";
	case KeyboardActionId.instrumentCopy:
		return "instrument.copy";
	case KeyboardActionId.instrumentPaste:
		return "instrument.paste";
	case KeyboardActionId.instrumentByteSelectionExtendLeft:
		return "instrument.byte_selection_extend_left";
	case KeyboardActionId.instrumentByteSelectionExtendRight:
		return "instrument.byte_selection_extend_right";
	case KeyboardActionId.waveSeekCurrentInstrumentWave:
		return "wave.seek_current_instrument_wave";
	case KeyboardActionId.instrumentDeleteConfirm:
		return "instrument.delete_confirm";
	case KeyboardActionId.instrumentSaveDialog:
		return "instrument.save_dialog";
	case KeyboardActionId.instrumentLoadDialog:
		return "instrument.load_dialog";
	case KeyboardActionId.songSidModelToggle:
		return "song.sid_model_toggle";
	case KeyboardActionId.songSidFilterPresetNext:
		return "song.sid_filter_preset_next";
	case KeyboardActionId.songSidFilterPresetPrevious:
		return "song.sid_filter_preset_previous";
	case KeyboardActionId.uiVisualModeToggle:
		return "ui.visual_mode_toggle";
	case KeyboardActionId.uiSubwindowPrevious:
		return "ui.subwindow_previous";
	case KeyboardActionId.uiSubwindowNext:
		return "ui.subwindow_next";
	case KeyboardActionId.uiMainWindowPrevious:
		return "ui.main_window_previous";
	case KeyboardActionId.uiMainWindowNext:
		return "ui.main_window_next";
	case KeyboardActionId.uiBaseOctaveDecrease:
		return "ui.base_octave_decrease";
	case KeyboardActionId.uiBaseOctaveIncrease:
		return "ui.base_octave_increase";
	case KeyboardActionId.uiInstrumentPrevious:
		return "ui.instrument_previous";
	case KeyboardActionId.uiInstrumentNext:
		return "ui.instrument_next";
	case KeyboardActionId.uiFollowInstrumentPointer:
		return "ui.follow_instrument_pointer";
	case KeyboardActionId.uiToggleFullscreen:
		return "ui.toggle_fullscreen";
	case KeyboardActionId.uiToggleInterpolation:
		return "ui.toggle_interpolation";
	case KeyboardActionId.playbackTrackingToggle:
		return "playback.tracking_toggle";
	case KeyboardActionId.playbackFastForward:
		return "playback.fast_forward";
	case KeyboardActionId.playbackFastForwardLarge:
		return "playback.fast_forward_large";
	case KeyboardActionId.playbackPlayFromMark:
		return "playback.play_from_mark";
	case KeyboardActionId.playbackPlayFromMarkTracking:
		return "playback.play_from_mark_tracking";
	case KeyboardActionId.playbackPlayFromStart:
		return "playback.play_from_start";
	case KeyboardActionId.playbackPlayFromStartTracking:
		return "playback.play_from_start_tracking";
	case KeyboardActionId.playbackPlayFromCursor:
		return "playback.play_from_cursor";
	case KeyboardActionId.playbackStop:
		return "playback.stop";
	case KeyboardActionId.editorUndo:
		return "editor.undo";
	case KeyboardActionId.editorRedo:
		return "editor.redo";
	case KeyboardActionId.voiceToggleMute1:
		return "voice.toggle_mute_1";
	case KeyboardActionId.voiceToggleMute2:
		return "voice.toggle_mute_2";
	case KeyboardActionId.voiceToggleMute3:
		return "voice.toggle_mute_3";
	case KeyboardActionId.helpClose:
		return "help.close";
	case KeyboardActionId.helpScrollUp:
		return "help.scroll_up";
	case KeyboardActionId.helpScrollDown:
		return "help.scroll_down";
	case KeyboardActionId.helpPageUp:
		return "help.page_up";
	case KeyboardActionId.helpPageDown:
		return "help.page_down";
	case KeyboardActionId.helpTop:
		return "help.top";
	case KeyboardActionId.helpBottom:
		return "help.bottom";
	case KeyboardActionId.helpTopicPrevious:
		return "help.topic_previous";
	case KeyboardActionId.helpTopicNext:
		return "help.topic_next";
	case KeyboardActionId.saveExportFormatCt:
		return "save_export.format_ct";
	case KeyboardActionId.saveExportFormatPrg:
		return "save_export.format_prg";
	case KeyboardActionId.saveExportFormatSid:
		return "save_export.format_sid";
	case KeyboardActionId.saveExportNextField:
		return "save_export.next_field";
	case KeyboardActionId.sequencerViewTrackTable:
		return "sequencer.view_track_table";
	case KeyboardActionId.sequencerViewTrackTableWithTrackList:
		return "sequencer.view_track_table_with_track_list";
	case KeyboardActionId.sequencerViewSequenceEditor:
		return "sequencer.view_sequence_editor";
	case KeyboardActionId.sequencerViewTrackMap:
		return "sequencer.view_track_map";
	case KeyboardActionId.sequencerViewToggleTrackSequence:
		return "sequencer.view_toggle_track_sequence";
	case KeyboardActionId.sequencerNavigateVoicePrevious:
		return "sequencer.navigate_voice_previous";
	case KeyboardActionId.sequencerNavigateVoiceNext:
		return "sequencer.navigate_voice_next";
	case KeyboardActionId.sequencerCursorStepSet:
		return "sequencer.cursor_step_set";
	case KeyboardActionId.sequencerCursorStepDecrease:
		return "sequencer.cursor_step_decrease";
	case KeyboardActionId.sequencerCursorStepIncrease:
		return "sequencer.cursor_step_increase";
	case KeyboardActionId.sequencerSubtunePrevious:
		return "sequencer.subtune_previous";
	case KeyboardActionId.sequencerSubtuneNext:
		return "sequencer.subtune_next";
	case KeyboardActionId.sequencerOverviewNavigateUp:
		return "sequencer.overview_navigate_up";
	case KeyboardActionId.sequencerOverviewNavigateDown:
		return "sequencer.overview_navigate_down";
	case KeyboardActionId.sequencerOverviewNavigatePageUp:
		return "sequencer.overview_navigate_page_up";
	case KeyboardActionId.sequencerOverviewNavigatePageDown:
		return "sequencer.overview_navigate_page_down";
	case KeyboardActionId.sequencerOverviewNavigateHome:
		return "sequencer.overview_navigate_home";
	case KeyboardActionId.sequencerOverviewNavigateEnd:
		return "sequencer.overview_navigate_end";
	case KeyboardActionId.sequencerViewNavigateUp:
		return "sequencer.view_navigate_up";
	case KeyboardActionId.sequencerViewNavigateDown:
		return "sequencer.view_navigate_down";
	case KeyboardActionId.sequencerViewNavigatePageUp:
		return "sequencer.view_navigate_page_up";
	case KeyboardActionId.sequencerViewNavigatePageDown:
		return "sequencer.view_navigate_page_down";
	case KeyboardActionId.sequencerViewScrollUp:
		return "sequencer.view_scroll_up";
	case KeyboardActionId.sequencerViewScrollDown:
		return "sequencer.view_scroll_down";
	case KeyboardActionId.sequencerViewNavigateLargePageUp:
		return "sequencer.view_navigate_large_page_up";
	case KeyboardActionId.sequencerViewNavigateLargePageDown:
		return "sequencer.view_navigate_large_page_down";
	case KeyboardActionId.sequencerViewNavigateSongStart:
		return "sequencer.view_navigate_song_start";
	case KeyboardActionId.sequencerViewNavigateSongEnd:
		return "sequencer.view_navigate_song_end";
	case KeyboardActionId.sequencerDebugSequenceDialog:
		return "sequencer.debug_sequence_dialog";
	case KeyboardActionId.sequenceRowSelectionExtendUp:
		return "sequence.row_selection_extend_up";
	case KeyboardActionId.sequenceRowSelectionExtendDown:
		return "sequence.row_selection_extend_down";
	case KeyboardActionId.sequenceRowSelectionExtendPageUp:
		return "sequence.row_selection_extend_page_up";
	case KeyboardActionId.sequenceRowSelectionExtendPageDown:
		return "sequence.row_selection_extend_page_down";
	case KeyboardActionId.sequenceRowSelectionExtendHome:
		return "sequence.row_selection_extend_home";
	case KeyboardActionId.sequenceRowSelectionExtendEnd:
		return "sequence.row_selection_extend_end";
	case KeyboardActionId.sequenceRowSelectionClear:
		return "sequence.row_selection_clear";
	case KeyboardActionId.sequenceRowSelectPattern:
		return "sequence.row_select_pattern";
	case KeyboardActionId.sequenceRowQuickExpand:
		return "sequence.row_quick_expand";
	case KeyboardActionId.sequenceTransposeSemitoneUp:
		return "sequence.transpose_semitone_up";
	case KeyboardActionId.sequenceTransposeSemitoneDown:
		return "sequence.transpose_semitone_down";
	case KeyboardActionId.sequenceTransposeOctaveUp:
		return "sequence.transpose_octave_up";
	case KeyboardActionId.sequenceTransposeOctaveDown:
		return "sequence.transpose_octave_down";
	case KeyboardActionId.sequenceRowDeleteSameLength:
		return "sequence.row.delete_same_length";
	case KeyboardActionId.sequenceRowInsertSameLength:
		return "sequence.row.insert_same_length";
	case KeyboardActionId.sequenceRowDeleteShrink:
		return "sequence.row.delete_shrink";
	case KeyboardActionId.sequenceRowInsertGrow:
		return "sequence.row.insert_grow";
	case KeyboardActionId.sequenceRowExpandSequence:
		return "sequence.row.expand_sequence";
	case KeyboardActionId.sequenceRowShrinkSequence:
		return "sequence.row.shrink_sequence";
	case KeyboardActionId.sequencePlayRowAllVoices:
		return "sequence.play_row_all_voices";
	case KeyboardActionId.sequenceRowCopy:
		return "sequence.row_copy";
	case KeyboardActionId.sequenceRowPaste:
		return "sequence.row_paste";
	case KeyboardActionId.sequenceSplit:
		return "sequence.split";
	case KeyboardActionId.sequenceInputOctaveDecrease:
		return "sequence_input.octave_decrease";
	case KeyboardActionId.sequenceInputOctaveIncrease:
		return "sequence_input.octave_increase";
	case KeyboardActionId.sequenceInputToggleInstrumentAutoinsert:
		return "sequence_input.toggle_instrument_autoinsert";
	case KeyboardActionId.sequenceInputClear:
		return "sequence_input.clear";
	case KeyboardActionId.sequenceInputReuseValue:
		return "sequence_input.reuse_value";
	case KeyboardActionId.sequenceInputGateOff:
		return "sequence_input.gate_off";
	case KeyboardActionId.sequenceInputGateOn:
		return "sequence_input.gate_on";
	case KeyboardActionId.sequenceInputTie:
		return "sequence_input.tie";
	case KeyboardActionId.sequenceInputGrabInstrument:
		return "sequence_input.grab_instrument";
	case KeyboardActionId.trackInputFindUnusedSequence:
		return "track_input.find_unused_sequence";
	case KeyboardActionId.trackInputPreviousSequence:
		return "track_input.previous_sequence";
	case KeyboardActionId.trackInputNextSequence:
		return "track_input.next_sequence";
	case KeyboardActionId.trackInputCommitValue:
		return "track_input.commit_value";
	case KeyboardActionId.trackOverviewLoopAllVoices:
		return "track_overview.loop_all_voices";
	case KeyboardActionId.trackOverviewLoopActiveVoice:
		return "track_overview.loop_active_voice";
	case KeyboardActionId.trackOverviewScrollLeft:
		return "track_overview.scroll_left";
	case KeyboardActionId.trackOverviewScrollRight:
		return "track_overview.scroll_right";
	case KeyboardActionId.trackOverviewTimelineStepLeft:
		return "track_overview.timeline_step_left";
	case KeyboardActionId.trackOverviewTimelineStepRight:
		return "track_overview.timeline_step_right";
	case KeyboardActionId.trackOverviewTimelinePageUp:
		return "track_overview.timeline_page_up";
	case KeyboardActionId.trackOverviewTimelinePageDown:
		return "track_overview.timeline_page_down";
	case KeyboardActionId.trackOverviewTimelineLargePageUp:
		return "track_overview.timeline_large_page_up";
	case KeyboardActionId.trackOverviewTimelineLargePageDown:
		return "track_overview.timeline_large_page_down";
	case KeyboardActionId.trackOverviewTimelineHome:
		return "track_overview.timeline_home";
	case KeyboardActionId.trackOverviewTimelineEnd:
		return "track_overview.timeline_end";
	case KeyboardActionId.trackOverviewCopyEntries:
		return "track_overview.copy_entries";
	case KeyboardActionId.trackOverviewPasteEntries:
		return "track_overview.paste_entries";
	case KeyboardActionId.trackOverviewFindUnusedSequence:
		return "track_overview.find_unused_sequence";
	case KeyboardActionId.trackOverviewInsertEntry:
		return "track_overview.insert_entry";
	case KeyboardActionId.trackOverviewInsertCopyEntry:
		return "track_overview.insert_copy_entry";
	case KeyboardActionId.trackOverviewDeleteSelection:
		return "track_overview.delete_selection";
	case KeyboardActionId.trackOverviewOpenActiveBlockInSequenceEditor:
		return "track_overview.open_active_block_in_sequence_editor";
	case KeyboardActionId.trackOverviewNavigatePreviousBlock:
		return "track_overview.navigate_previous_block";
	case KeyboardActionId.trackOverviewNavigateNextBlock:
		return "track_overview.navigate_next_block";
	case KeyboardActionId.trackOverviewUndo:
		return "track_overview.undo";
	case KeyboardActionId.trackOverviewRedo:
		return "track_overview.redo";
	case KeyboardActionId.trackEntryInsert:
		return "track_entry.insert";
	case KeyboardActionId.trackEntryInsertCopy:
		return "track_entry.insert_copy";
	case KeyboardActionId.trackEntryDelete:
		return "track_entry.delete";
	case KeyboardActionId.trackEntryInsertToEnd:
		return "track_entry.insert_to_end";
	case KeyboardActionId.trackEntryDeleteToEnd:
		return "track_entry.delete_to_end";
	case KeyboardActionId.trackEntryInsertAllVoices:
		return "track_entry.insert_all_voices";
	case KeyboardActionId.trackEntryDeleteAllVoices:
		return "track_entry.delete_all_voices";
	case KeyboardActionId.trackEntryCopyPrompt:
		return "track_entry.copy_prompt";
	case KeyboardActionId.trackEntryPastePrompt:
		return "track_entry.paste_prompt";
	case KeyboardActionId.trackEntryPasteInsert:
		return "track_entry.paste_insert";
	case KeyboardActionId.trackEntryPasteOverwrite:
		return "track_entry.paste_overwrite";
	case KeyboardActionId.trackEntryLoopSetAllVoices:
		return "track_entry.loop_set_all_voices";
	case KeyboardActionId.trackEntryLoopSetActiveVoice:
		return "track_entry.loop_set_active_voice";
	case KeyboardActionId.trackEntryTransposeUpFromCursor:
		return "track_entry.transpose_up_from_cursor";
	case KeyboardActionId.trackEntryTransposeDownFromCursor:
		return "track_entry.transpose_down_from_cursor";
	case KeyboardActionId.trackEntrySwapWithVoice1:
		return "track_entry.swap_with_voice_1";
	case KeyboardActionId.trackEntrySwapWithVoice2:
		return "track_entry.swap_with_voice_2";
	case KeyboardActionId.trackEntrySwapWithVoice3:
		return "track_entry.swap_with_voice_3";
	case KeyboardActionId.trackEntryNavigateStart:
		return "track_entry.navigate_start";
	case KeyboardActionId.trackEntryNavigateEnd:
		return "track_entry.navigate_end";
	case KeyboardActionId.generatedTableRowDelete:
		return "table.row_delete";
	case KeyboardActionId.generatedTableRowInsert:
		return "table.row_insert";
	case KeyboardActionId.generatedTableRowSelectionExtendUp:
		return "table.row_selection_extend_up";
	case KeyboardActionId.generatedTableRowSelectionExtendDown:
		return "table.row_selection_extend_down";
	case KeyboardActionId.generatedTableRowSelectionExtendPageUp:
		return "table.row_selection_extend_page_up";
	case KeyboardActionId.generatedTableRowSelectionExtendPageDown:
		return "table.row_selection_extend_page_down";
	case KeyboardActionId.generatedTableRowSelectionExtendHome:
		return "table.row_selection_extend_home";
	case KeyboardActionId.generatedTableRowSelectionExtendEnd:
		return "table.row_selection_extend_end";
	case KeyboardActionId.generatedTableRowSelectionClear:
		return "table.row_selection_clear";
	case KeyboardActionId.generatedTableRowCopy:
		return "table.row_copy";
	case KeyboardActionId.generatedTableRowPaste:
		return "table.row_paste";
	case KeyboardActionId.workspaceActivateSequencer:
		return "workspace.activate_sequencer";
	case KeyboardActionId.workspaceActivateVoice1:
		return "workspace.activate_voice_1";
	case KeyboardActionId.workspaceActivateVoice2:
		return "workspace.activate_voice_2";
	case KeyboardActionId.workspaceActivateVoice3:
		return "workspace.activate_voice_3";
	case KeyboardActionId.workspaceActivateInstrument:
		return "workspace.activate_instrument";
	case KeyboardActionId.workspaceActivateWave:
		return "workspace.activate_wave";
	case KeyboardActionId.workspaceActivatePulse:
		return "workspace.activate_pulse";
	case KeyboardActionId.workspaceActivateFilter:
		return "workspace.activate_filter";
	case KeyboardActionId.workspaceActivateCommand:
		return "workspace.activate_command";
	case KeyboardActionId.workspaceActivateChord:
		return "workspace.activate_chord";
	case KeyboardActionId.workspaceActivateTitle:
		return "workspace.activate_title";
	case KeyboardActionId.workspaceActivateSpeed:
		return "workspace.activate_speed";
	}
}

private KeyboardActionId[] keyboardActionIdsInRegistry() {
	return [EnumMembers!KeyboardActionId];
}

string[] keyboardActionStableIdsInRegistry() {
	string[] ids;
	foreach(actionId; keyboardActionIdsInRegistry())
		ids ~= keyboardActionStableId(actionId);
	return ids;
}

bool keyboardActionStableIdExists(string stableId) {
	foreach(actionId; keyboardActionIdsInRegistry()) {
		if(keyboardActionStableId(actionId) == stableId)
			return true;
	}
	return false;
}

string keyboardContextStableId(KeyboardContext context) {
	final switch(context) {
	case KeyboardContext.global:
		return "global";
	case KeyboardContext.editor:
		return "editor";
	case KeyboardContext.helpDialog:
		return "help_dialog";
	case KeyboardContext.fileDialog:
		return "file_dialog";
	case KeyboardContext.saveExportDialog:
		return "save_export_dialog";
	case KeyboardContext.sequencer:
		return "sequencer";
	case KeyboardContext.sequenceEditor:
		return "sequence_editor";
	case KeyboardContext.sequenceInput:
		return "sequence_input";
	case KeyboardContext.sequenceValueInput:
		return "sequence_value_input";
	case KeyboardContext.cursorStepInput:
		return "cursor_step_input";
	case KeyboardContext.noteInput:
		return "note_input";
	case KeyboardContext.trackInput:
		return "track_input";
	case KeyboardContext.trackOverview:
		return "track_overview";
	case KeyboardContext.trackOverviewBlock:
		return "track_overview_block";
	case KeyboardContext.trackOverviewTimeline:
		return "track_overview_timeline";
	case KeyboardContext.trackEntry:
		return "track_entry";
	case KeyboardContext.generatedTable:
		return "generated_table";
	case KeyboardContext.instrumentTable:
		return "instrument_table";
	case KeyboardContext.waveTable:
		return "wave_table";
	case KeyboardContext.workspaceNavigation:
		return "workspace_navigation";
	case KeyboardContext.uiWindowSwitcher:
		return "ui_window_switcher";
	case KeyboardContext.uiTopLevel:
		return "ui_top_level";
	case KeyboardContext.uiGlobal:
		return "ui_global";
	}
}

		version(OSX) {
		private enum KeyboardBinding[] SEQUENCE_EDITOR_COMMAND_BINDINGS = [
			KeyboardBinding(
				KeyboardActionId.sequenceRowQuickExpand,
				KeyboardContext.sequenceEditor,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_RETURN,
				KMOD_SHIFT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.primary, "Enter"),
				"Quick expand sequence to the next 4*highlight boundary",
				true,
				"Preserves the old translated Shift-Return matcher used by F6 Quick Expand.")
		];
		}
		else {
		private enum KeyboardBinding[] SEQUENCE_EDITOR_COMMAND_BINDINGS = [
			KeyboardBinding(
				KeyboardActionId.sequenceRowQuickExpand,
				KeyboardContext.sequenceEditor,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_RETURN,
				KMOD_SHIFT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.primary, "Enter"),
				"Quick expand sequence to the next 4*highlight boundary",
				true,
				"Preserves the old Shift-Return matcher used by F6 Quick Expand.")
		];
		}

	version(OSX) {
	private enum KeyboardBinding[] SEQUENCE_TRANSPOSE_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceTransposeSemitoneUp,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_q,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Transpose sequence rows up one semitone from cursor down",
			true,
			"Physical Command-Q is reserved for app quit; F6 transpose uses physical Control-Q on macOS."),
		KeyboardBinding(
			KeyboardActionId.sequenceTransposeSemitoneDown,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_a,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Transpose sequence rows down one semitone from cursor down",
			true,
			"F6 transpose uses physical Control-A on macOS, not Command-A."),
		KeyboardBinding(
			KeyboardActionId.sequenceTransposeOctaveUp,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_w,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Transpose sequence rows up one octave from cursor down",
			true,
			"F6 transpose uses physical Control-W on macOS, not Command-W."),
		KeyboardBinding(
			KeyboardActionId.sequenceTransposeOctaveDown,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_s,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Transpose sequence rows down one octave from cursor down",
			true,
			"F6 transpose uses physical Control-S on macOS, not Command-S.")
	];
	}
	else {
	private enum KeyboardBinding[] SEQUENCE_TRANSPOSE_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceTransposeSemitoneUp,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_q,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Transpose sequence rows up one semitone from cursor down",
			true,
			"Preserves the existing F6 Ctrl-Q transpose route; extra modifiers keep the old Ctrl-branch tolerance."),
		KeyboardBinding(
			KeyboardActionId.sequenceTransposeSemitoneDown,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_a,
			KMOD_CTRL | KMOD_SHIFT,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.shift),
			"Transpose sequence rows down one semitone from cursor down",
			true,
			"Default/PC Ctrl-Shift-A is the approved F6 transpose-down shortcut; Ctrl-A is Select All."),
		KeyboardBinding(
			KeyboardActionId.sequenceTransposeOctaveUp,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_w,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Transpose sequence rows up one octave from cursor down",
			true,
			"Preserves the existing F6 Ctrl-W transpose route; extra modifiers keep the old Ctrl-branch tolerance."),
		KeyboardBinding(
			KeyboardActionId.sequenceTransposeOctaveDown,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_s,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Transpose sequence rows down one octave from cursor down",
			true,
			"Preserves the existing F6 Ctrl-S transpose route; extra modifiers keep the old Ctrl-branch tolerance.")
	];
	}

	version(OSX) {
	private enum KeyboardBinding[] SEQUENCE_ROW_STRUCTURE_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceRowDeleteSameLength,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Delete row and shift pattern contents up, same length",
			true,
			"Preserves the documented macOS F6 Delete route; hidden Insert alias is intentionally not registered."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowInsertSameLength,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Insert blank row and shift contents down, same length",
			true,
			"Preserves the documented macOS F6 Shift-Delete route; hidden Shift-Insert alias is intentionally not registered."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowDeleteShrink,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Delete row and shrink pattern length by one",
			true,
			"Preserves the documented macOS F6 Backspace shrink route."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowInsertGrow,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Insert blank row and grow pattern length by one",
			true,
			"Preserves the documented macOS F6 Shift-Backspace grow route.")
	];
	}
	else {
	private enum KeyboardBinding[] SEQUENCE_ROW_STRUCTURE_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceRowDeleteSameLength,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Delete row and shift pattern contents up, same length",
			true,
			"Preserves the documented default F6 Delete route."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowInsertSameLength,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Insert blank row and shift contents down, same length",
			true,
			"Preserves the documented default F6 Insert route."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowDeleteShrink,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Delete row and shrink pattern length by one",
			true,
			"Preserves the documented default F6 Shift-Delete shrink route."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowInsertGrow,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Insert blank row and grow pattern length by one",
			true,
			"Preserves the documented default F6 Shift-Insert grow route.")
	];
		}

	version(OSX) {
	private enum KeyboardBinding[] SEQUENCE_EXPAND_SHRINK_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceRowExpandSequence,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Expand sequence by one row at the end",
			true,
			"Preserves the documented macOS F6 Control-Insert sequence expand route."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowShrinkSequence,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Shrink sequence by one row from the end",
			true,
			"Preserves the documented macOS F6 Control-Delete sequence shrink route.")
	];
	}
	else {
	private enum KeyboardBinding[] SEQUENCE_EXPAND_SHRINK_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceRowExpandSequence,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Expand sequence by one row at the end",
			true,
			"Preserves the documented F6 Ctrl-Insert sequence expand route."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowShrinkSequence,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Shrink sequence by one row from the end",
			true,
			"Preserves the documented F6 Ctrl-Delete sequence shrink route.")
	];
	}

	private enum KeyboardBinding[] SEQUENCE_PLAY_ROW_BINDINGS = [
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.sequencePlayRowAllVoices,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_0,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Play notes for all voices in current row",
			true,
			"F6-only play-row audition; top-row 0 remains normal editor input."),
			[KeyboardHelpPlacement(KeyboardHelpSection.sequenceEditingSequencer,
				5, "Play current row once, then step down"),
			 KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback, 10,
				"F6 only: play current row once, then step down")])
	];

	private enum KeyboardBinding[] SEQUENCE_DIALOG_BINDINGS = [
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.sequenceOpenAppendDialog,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_a,
			KMOD_ALT,
			KMOD_SHIFT | KMOD_CTRL | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Open sequence append/insert dialog",
			true,
			"Sequencer owns the existing QueryDialog execution path."), [
				KeyboardHelpPlacement(KeyboardHelpSection.sequenceDialogs, 1,
					"Ask for a SEQ number and insert contents to cursor pos")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.sequenceOpenCopyDialog,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_ALT,
			KMOD_SHIFT | KMOD_CTRL | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Open sequence copy dialog",
			true,
			"Sequencer owns the existing QueryDialog execution path."), [
				KeyboardHelpPlacement(KeyboardHelpSection.sequenceDialogs, 0,
					"Ask for a SEQ number and copy contents over current SEQ")])
	];

	version(OSX) {
	private enum KeyboardBinding[] SEQUENCE_ROW_CLIPBOARD_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendUp,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection upward",
			true,
			"Replaces the old F6 Shift-Up large-jump route inside the sequence editor."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendDown,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection downward",
			true,
			"Replaces the old F6 Shift-Down large-jump route inside the sequence editor."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendPageUp,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEUP,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection one page upward",
			true,
			"Uses the F6 PageUp movement but keeps a valid row selection anchored."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendPageDown,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEDOWN,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection one page downward",
			true,
			"Uses the F6 PageDown movement but keeps a valid row selection anchored."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendHome,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_HOME,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection to the F6 Home target",
			true,
			"Uses the F6 Home movement but clears if it leaves the current pattern."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendEnd,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_END,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection to the F6 End target",
			true,
			"Uses the F6 End movement but clears if it leaves the current pattern."),
				KeyboardBinding(
					KeyboardActionId.sequenceRowSelectionClear,
				KeyboardContext.sequenceEditor,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_ESCAPE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
					"Clear sequence row selection",
					true,
					"Only consumed by SequenceTable when a row selection is active."),
				KeyboardBinding(
					KeyboardActionId.sequenceRowSelectPattern,
					KeyboardContext.sequenceEditor,
					KeyboardBindingKeyModel.translatedKeyinfo,
					SDLK_a,
					KMOD_CTRL | KMOD_SHIFT,
					KMOD_ALT | KMOD_GUI,
					KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.primary),
					"Select all rows in the current sequence",
					true,
					"Physical Command-A translates to Ctrl-Shift-A before F6 resolves the shortcut."),
				KeyboardBinding(
					KeyboardActionId.sequenceRowCopy,
				KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Copy selected sequence rows",
			true,
			"Matches the existing macOS copy predicate; Shift remains allowed."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowCopy,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_GUI,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Copy selected sequence rows",
			true,
			"Preserves the old raw GUI-modifier copy fallback."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowPaste,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_v,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Paste selected sequence rows",
			true,
			"Matches the existing macOS paste predicate; Shift remains allowed."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowPaste,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_v,
			KMOD_GUI,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Paste selected sequence rows",
			true,
			"Preserves the old raw GUI-modifier paste fallback.")
	];
	}
	else {
	private enum KeyboardBinding[] SEQUENCE_ROW_CLIPBOARD_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendUp,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection upward",
			true,
			"Replaces the old F6 Shift-Up large-jump route inside the sequence editor."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendDown,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection downward",
			true,
			"Replaces the old F6 Shift-Down large-jump route inside the sequence editor."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendPageUp,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEUP,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection one page upward",
			true,
			"Uses the F6 PageUp movement but keeps a valid row selection anchored."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendPageDown,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEDOWN,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection one page downward",
			true,
			"Uses the F6 PageDown movement but keeps a valid row selection anchored."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendHome,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_HOME,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection to the F6 Home target",
			true,
			"Uses the F6 Home movement but clears if it leaves the current pattern."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowSelectionExtendEnd,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_END,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend sequence row selection to the F6 End target",
			true,
			"Uses the F6 End movement but clears if it leaves the current pattern."),
				KeyboardBinding(
					KeyboardActionId.sequenceRowSelectionClear,
				KeyboardContext.sequenceEditor,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_ESCAPE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
					"Clear sequence row selection",
					true,
					"Only consumed by SequenceTable when a row selection is active."),
				KeyboardBinding(
					KeyboardActionId.sequenceRowSelectPattern,
					KeyboardContext.sequenceEditor,
					KeyboardBindingKeyModel.translatedKeyinfo,
					SDLK_a,
					KMOD_CTRL,
					KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
					KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
					"Select all rows in the current sequence",
					true,
					"Default/PC Ctrl-A is exact; Ctrl-Shift-A remains available for transpose down."),
				KeyboardBinding(
					KeyboardActionId.sequenceRowCopy,
				KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_c,
				KMOD_CTRL,
				KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
				"Copy selected sequence rows",
				true,
				"Shift remains allowed while an F6 row selection is active."),
		KeyboardBinding(
			KeyboardActionId.sequenceRowPaste,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_v,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Paste selected sequence rows",
			true,
			"Preserves the existing default Ctrl-V predicate.")
		];
		}

	version(OSX) {
	private enum KeyboardBinding[] TRACK_ENTRY_STRUCTURAL_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertAllVoices,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			KMOD_CTRL | KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.shift),
			"Insert an empty track entry for all voices",
			true,
			"Preserves the shared F5/F7 Ctrl-Shift-Insert route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertAllVoices,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			KMOD_CTRL | KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.shift, "Enter"),
			"Insert an empty track entry for all voices",
			true,
			"Preserves the shared F5/F7 Ctrl-Shift-Enter route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertToEnd,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			KMOD_CTRL,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Insert an empty track entry to the end of the active voice",
			true,
			"Preserves the shared F5/F7 Ctrl-Insert route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertToEnd,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			KMOD_CTRL,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl, "Enter"),
			"Insert an empty track entry to the end of the active voice",
			true,
			"Preserves the shared F5/F7 Ctrl-Enter route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryDeleteAllVoices,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_CTRL | KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.shift),
			"Delete the current track entry for all voices",
			true,
			"Preserves the shared F5/F7 Ctrl-Shift-Delete route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryDeleteToEnd,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_CTRL,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Delete track entries to the end of the active voice",
			true,
			"Preserves the shared F5/F7 Ctrl-Delete route."),
			KeyboardBinding(
				KeyboardActionId.trackEntryInsert,
				KeyboardContext.trackEntry,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_RETURN,
				KMOD_SHIFT,
				KMOD_CTRL | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
				"Insert an empty track entry",
				true,
				"Explicit canonical F5/F7 blank insert route; keypad Enter remains separate."),
			KeyboardBinding(
				KeyboardActionId.trackEntryInsert,
				KeyboardContext.trackEntry,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_INSERT,
				KMOD_SHIFT,
				KMOD_CTRL | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Insert an empty track entry",
			true,
			"Preserves the macOS shared F5/F7 insert route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryInsert,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Insert an empty track entry",
			true,
			"Preserves the macOS shared F5/F7 insert route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertCopy,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Insert a copy of the current track entry",
			true,
			"Preserves the macOS shared F5/F7 insert-copy route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryDelete,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Delete the current track entry",
			true,
			"Preserves the macOS shared F5/F7 delete route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryDelete,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Delete the current track entry",
			true,
			"Preserves the macOS shared F5/F7 delete route.")
	];
	}
	else {
	private enum KeyboardBinding[] TRACK_ENTRY_STRUCTURAL_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertAllVoices,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			KMOD_CTRL | KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.shift),
			"Insert an empty track entry for all voices",
			true,
			"Preserves the shared F5/F7 Ctrl-Shift-Insert route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertAllVoices,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			KMOD_CTRL | KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.shift, "Enter"),
			"Insert an empty track entry for all voices",
			true,
			"Preserves the shared F5/F7 Ctrl-Shift-Enter route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertToEnd,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			KMOD_CTRL,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Insert an empty track entry to the end of the active voice",
			true,
			"Preserves the shared F5/F7 Ctrl-Insert route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertToEnd,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			KMOD_CTRL,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl, "Enter"),
			"Insert an empty track entry to the end of the active voice",
			true,
			"Preserves the shared F5/F7 Ctrl-Enter route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryDeleteAllVoices,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_CTRL | KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.shift),
			"Delete the current track entry for all voices",
			true,
			"Preserves the shared F5/F7 Ctrl-Shift-Delete route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryDeleteToEnd,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_CTRL,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Delete track entries to the end of the active voice",
			true,
			"Preserves the shared F5/F7 Ctrl-Delete route."),
			KeyboardBinding(
				KeyboardActionId.trackEntryInsert,
				KeyboardContext.trackEntry,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_RETURN,
				KMOD_SHIFT,
				KMOD_CTRL | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
				"Insert an empty track entry",
				true,
				"Explicit canonical F5/F7 blank insert route; keypad Enter remains separate."),
			KeyboardBinding(
				KeyboardActionId.trackEntryInsert,
				KeyboardContext.trackEntry,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_INSERT,
				0,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Insert an empty track entry",
			true,
			"Preserves the default shared F5/F7 insert route, including legacy modifier tolerance."),
		KeyboardBinding(
			KeyboardActionId.trackEntryInsertCopy,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.physicalLabelOnly,
			0,
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift, KEYBOARD_SAME_SEMANTIC_MODIFIERS, "Backspace"),
			"Insert a copy of the current track entry",
			false,
			"No default-platform legacy binding; macOS-only route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryDelete,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Delete the current track entry",
			true,
			"Preserves the default shared F5/F7 delete route, including legacy modifier tolerance.")
		];
		}

	private enum KeyboardBinding[] TRACK_ENTRY_CLIPBOARD_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.trackEntryCopyPrompt,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Open the track-entry copy-count prompt",
			true,
			"Preserves the shared F5/F7 Ctrl-C route; extra modifiers keep the old Ctrl-branch tolerance."),
		KeyboardBinding(
			KeyboardActionId.trackEntryPastePrompt,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_v,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Open the track-entry paste insert/overwrite prompt",
			true,
			"Preserves the shared F5/F7 Ctrl-V route; extra modifiers keep the old Ctrl-branch tolerance."),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackEntryPasteInsert,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_i,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Paste track-entry clipboard using insert mode",
			true,
			"Preserves the shared F5/F7 Ctrl-I direct paste route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackColumnAdvanced, 4,
					"Paste copied tracks using insert mode")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackEntryPasteOverwrite,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_o,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Paste track-entry clipboard using overwrite mode",
			true,
			"Preserves the shared F5/F7 Ctrl-O direct paste route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackColumnAdvanced, 5,
					"Paste copied tracks using overwrite mode")])
	];

	version(OSX) {
	private enum KeyboardBinding[] TRACK_ENTRY_LOOP_BINDINGS = [
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackEntryLoopSetAllVoices,
				KeyboardContext.trackEntry,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_l,
				KMOD_GUI | KMOD_ALT,
				KMOD_SHIFT | KMOD_CTRL,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate),
				"Set track LOOP target for all voices",
				true,
				"Primary all-voice LOOP route; Shift version targets active voice."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackLoop, 0,
						"Set LOOP target for all voices")]),
			KeyboardBinding(
				KeyboardActionId.trackEntryLoopSetAllVoices,
				KeyboardContext.trackEntry,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_BACKSPACE,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Set track LOOP target for all voices",
				true,
				"Preserves the macOS F5/F7 Ctrl-Backspace all-voice LOOP route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryLoopSetAllVoices,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Set track LOOP target for all voices",
			true,
			"Preserves the macOS F5/F7 Ctrl-Delete all-voice LOOP route."),
		KeyboardBinding(
			KeyboardActionId.trackEntryLoopSetAllVoices,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			KMOD_CTRL | KMOD_SHIFT,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Set track LOOP target for all voices",
			true,
			"Preserves the macOS translated Command-Backspace all-voice LOOP route."),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackEntryLoopSetActiveVoice,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_l,
				KMOD_GUI | KMOD_SHIFT | KMOD_ALT,
				KMOD_CTRL,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate | KeyboardSemanticModifier.shift),
				"Set track LOOP target for the active voice",
				true,
				"Shift distinguishes active-voice LOOP from all-voice LOOP."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackLoop, 1,
						"Set LOOP target for active voice")])
	];
	}
	else {
	private enum KeyboardBinding[] TRACK_ENTRY_LOOP_BINDINGS = [
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackEntryLoopSetAllVoices,
				KeyboardContext.trackEntry,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_l,
				KMOD_CTRL | KMOD_ALT,
				KMOD_SHIFT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate),
				"Set track LOOP target for all voices",
				true,
				"Primary all-voice LOOP route; Shift version targets active voice."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackLoop, 0,
						"Set LOOP target for all voices")]),
			KeyboardBinding(
				KeyboardActionId.trackEntryLoopSetAllVoices,
				KeyboardContext.trackEntry,
				KeyboardBindingKeyModel.physicalLabelOnly,
				0,
				0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KEYBOARD_SAME_SEMANTIC_MODIFIERS, "Backspace"),
			"Set track LOOP target for all voices",
			false,
			"No default-platform legacy binding in source; macOS-only route."),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackEntryLoopSetActiveVoice,
			KeyboardContext.trackEntry,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_l,
				KMOD_CTRL | KMOD_SHIFT | KMOD_ALT,
				KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate | KeyboardSemanticModifier.shift),
				"Set track LOOP target for the active voice",
				true,
				"Shift distinguishes active-voice LOOP from all-voice LOOP."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackLoop, 1,
						"Set LOOP target for active voice")])
	];
	}

	private enum KeyboardBinding[] TRACK_ENTRY_TRANSPOSE_BINDINGS = [
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackEntryTransposeUpFromCursor,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_q,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Transpose active voice tracks up from cursor down",
			true,
			"Preserves the shared F5/F7 Ctrl-Q route; extra modifiers keep the old Ctrl-branch tolerance."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackColumnAdvanced, 6,
					"Transpose active voice tracks up from cursor down")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackEntryTransposeDownFromCursor,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_a,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Transpose active voice tracks down from cursor down",
			true,
			"Preserves the shared F5/F7 Ctrl-A route; extra modifiers keep the old Ctrl-branch tolerance."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackColumnAdvanced, 7,
					"Transpose active voice tracks down from cursor down")])
	];

	private enum KeyboardBinding[] TRACK_ENTRY_SWAP_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.trackEntrySwapWithVoice1,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_1,
			KMOD_CTRL | KMOD_ALT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.alternate),
			"Swap current voice track data with voice 1 from cursor down",
			true,
			"Preserves the shared F5/F7 Ctrl-Alt-1 route and old modifier tolerance."),
		KeyboardBinding(
			KeyboardActionId.trackEntrySwapWithVoice2,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_2,
			KMOD_CTRL | KMOD_ALT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.alternate),
			"Swap current voice track data with voice 2 from cursor down",
			true,
			"Preserves the shared F5/F7 Ctrl-Alt-2 route and old modifier tolerance."),
		KeyboardBinding(
			KeyboardActionId.trackEntrySwapWithVoice3,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_3,
			KMOD_CTRL | KMOD_ALT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.alternate),
			"Swap current voice track data with voice 3 from cursor down",
			true,
			"Preserves the shared F5/F7 Ctrl-Alt-3 route and old modifier tolerance.")
	];

	private enum KeyboardBinding[] TRACK_ENTRY_NAVIGATION_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.trackEntryNavigateStart,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_HOME,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Jump to the beginning of the track list",
			true,
			"Preserves the plain F5/F7 Home route; modified Home remains local table navigation."),
		KeyboardBinding(
			KeyboardActionId.trackEntryNavigateEnd,
			KeyboardContext.trackEntry,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_END,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Jump to the end of the track list",
			true,
			"Preserves the plain F5/F7 End route; modified End remains local table navigation.")
	];

	private enum KeyboardBinding[] GENERATED_TABLE_ROW_STRUCTURE_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.generatedTableRowDelete,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Delete the current generated-table row",
			true,
			"Wave/Pulse/Filter/Chord only; Command and Instrument tables do not execute this action."),
		KeyboardBinding(
			KeyboardActionId.generatedTableRowDelete,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none, KEYBOARD_SAME_SEMANTIC_MODIFIERS, "", "Delete"),
			"Delete the current generated-table row",
			true,
			"Mac labelled Delete commonly arrives as Backspace; scoped to generated row-structure tables only."),
			KeyboardBinding(
				KeyboardActionId.generatedTableRowInsert,
				KeyboardContext.generatedTable,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_RETURN,
				KMOD_SHIFT,
				KMOD_CTRL | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
				"Insert a generated-table row",
				true,
				"Explicit canonical generated-table insert route; keypad Enter remains separate."),
			KeyboardBinding(
				KeyboardActionId.generatedTableRowInsert,
				KeyboardContext.generatedTable,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_DELETE,
				KMOD_SHIFT,
				KMOD_CTRL | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Insert a generated-table row",
			true,
			"Mac-friendly row insert for Wave/Pulse/Filter/Chord only."),
		KeyboardBinding(
			KeyboardActionId.generatedTableRowInsert,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift, KEYBOARD_SAME_SEMANTIC_MODIFIERS, "", "Delete"),
			"Insert a generated-table row",
			true,
			"Mac labelled Shift-Delete commonly arrives as Shift-Backspace; scoped to generated row-structure tables only."),
		KeyboardBinding(
			KeyboardActionId.generatedTableRowInsert,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Insert a generated-table row",
			true,
			"Preserves existing external Insert-key compatibility in valid generated tables.")
	];

	private enum KeyboardBinding[] GENERATED_TABLE_ROW_SELECTION_BINDINGS = [
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.generatedTableRowSelectionExtendUp,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend generated-table row selection upward",
			true,
			"Wave/Pulse/Filter only; Command and Chord tables do not execute this action."), [
				KeyboardHelpPlacement(KeyboardHelpSection.waveTableHelp, 1,
					"Extend row selection")]),
		KeyboardBinding(
			KeyboardActionId.generatedTableRowSelectionExtendDown,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend generated-table row selection downward",
			true,
			"Wave/Pulse/Filter only; Command and Chord tables do not execute this action."),
		KeyboardBinding(
			KeyboardActionId.generatedTableRowSelectionExtendPageUp,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEUP,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend generated-table row selection up by one page",
			true,
			"Wave/Pulse/Filter only; Command and Chord tables do not execute this action."),
		KeyboardBinding(
			KeyboardActionId.generatedTableRowSelectionExtendPageDown,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEDOWN,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend generated-table row selection down by one page",
			true,
			"Wave/Pulse/Filter only; Command and Chord tables do not execute this action."),
		KeyboardBinding(
			KeyboardActionId.generatedTableRowSelectionExtendHome,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_HOME,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend generated-table row selection to the first row",
			true,
			"Wave/Pulse/Filter only; Command and Chord tables do not execute this action."),
		KeyboardBinding(
			KeyboardActionId.generatedTableRowSelectionExtendEnd,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_END,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Extend generated-table row selection to the final row",
			true,
			"Wave/Pulse/Filter only; Command and Chord tables do not execute this action."),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.generatedTableRowSelectionClear,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_ESCAPE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Clear generated-table row selection",
			true,
			"Wave/Pulse/Filter only; Command and Chord tables do not execute this action."), [
				KeyboardHelpPlacement(KeyboardHelpSection.waveTableHelp, 2,
					"Clear row selection")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.generatedTableRowCopy,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary,
				KeyboardSemanticModifier.physicalControl),
			"Copy selected generated-table rows",
			true,
			"Wave/Pulse/Filter only; copied rows remain table-local."), [
				KeyboardHelpPlacement(KeyboardHelpSection.waveTableHelp, 3,
					"Copy selected rows")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.generatedTableRowPaste,
			KeyboardContext.generatedTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_v,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary,
				KeyboardSemanticModifier.physicalControl),
			"Paste copied generated-table rows",
			true,
				"Wave/Pulse/Filter only; paste is rejected across table types."), [
				KeyboardHelpPlacement(KeyboardHelpSection.waveTableHelp, 4,
					"Paste selected rows")])
	];

	private enum KeyboardBinding[] INSTRUMENT_BYTE_SELECTION_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.instrumentByteSelectionExtendLeft,
			KeyboardContext.instrumentTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_LEFT,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Start or extend Instrument byte selection left",
			true,
			"Instrument byte editor only; selection moves by whole displayed byte columns."),
		KeyboardBinding(
			KeyboardActionId.instrumentByteSelectionExtendRight,
			KeyboardContext.instrumentTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RIGHT,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Start or extend Instrument byte selection right",
			true,
			"Instrument byte editor only; selection moves by whole displayed byte columns.")
	];

	version(OSX) {
		private enum KeyboardBinding[] TRACK_OVERVIEW_BLOCK_BINDINGS = [
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewLoopAllVoices,
				KeyboardContext.trackOverviewBlock,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_BACKSPACE,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
				"Set Track overview LOOP target for all voices",
				true,
				"Canonical compact Track overview all-voice LOOP display; Command-Option-L remains an alias."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewNavigation, 0,
						"Set LOOP target for all voices")]),
			KeyboardBinding(
				KeyboardActionId.trackOverviewLoopAllVoices,
				KeyboardContext.trackOverviewBlock,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_l,
				KMOD_GUI | KMOD_ALT,
				KMOD_SHIFT | KMOD_CTRL,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate),
				"Set Track overview LOOP target for all voices",
				true,
				"Uses selected overview block row to resolve each voice LOOP target."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewLoopActiveVoice,
				KeyboardContext.trackOverviewBlock,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_l,
				KMOD_GUI | KMOD_SHIFT | KMOD_ALT,
				KMOD_CTRL,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate | KeyboardSemanticModifier.shift),
				"Set Track overview LOOP target for selected/active voice",
				true,
				"Shift distinguishes active-voice LOOP from all-voice LOOP."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewNavigation, 1,
						"Set LOOP target for selected/active voice")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackOverviewCopyEntries,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Copy selected Track overview entries",
			true,
			"Matches the existing macOS copy predicate; Shift remains allowed."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 0,
					"Copy selected block/range")]),
		KeyboardBinding(
			KeyboardActionId.trackOverviewCopyEntries,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_GUI,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Copy selected Track overview entries",
			true,
			"Preserves the old raw GUI-modifier copy fallback."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewPasteEntries,
				KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_v,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Paste copied Track overview entries",
				true,
				"Matches the existing macOS paste predicate; Shift remains allowed."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 1,
						"Paste copied track entries")]),
		KeyboardBinding(
			KeyboardActionId.trackOverviewPasteEntries,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_v,
			KMOD_GUI,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Paste copied Track overview entries",
				true,
				"Preserves the old raw GUI-modifier paste fallback."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewFindUnusedSequence,
				KeyboardContext.trackOverviewBlock,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_f,
				KMOD_CTRL,
				KMOD_ALT,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Change selected Track overview block to the next unused sequence",
				true,
				"Matches the F5/F7 next-unused sequence action for a selected overview block."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 2,
						"Change selected block to next unused sequence")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewInsertEntry,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none, KeyboardSemanticModifier.shift),
			"Insert selected Track overview entry",
			true,
			"Preserves the existing macOS Shift-Insert insert route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 4,
					"Insert selected track entry")]),
		KeyboardBinding(
			KeyboardActionId.trackOverviewInsertEntry,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none, KeyboardSemanticModifier.shift, "Insert", "Delete"),
			"Insert selected Track overview entry",
			true,
			"Preserves the existing macOS Shift-Delete insert route."),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackOverviewInsertCopyEntry,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Insert copy of selected Track overview entry",
			true,
			"Preserves the existing Track overview insert-copy route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 5,
					"Insert copy of selected track entry")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackOverviewDeleteSelection,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none, KEYBOARD_SAME_SEMANTIC_MODIFIERS, "Delete", "Backspace"),
			"Delete selected Track overview entry/range",
			true,
			"Preserves the existing macOS Backspace delete route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 6,
					"Delete selected block/range")]),
		KeyboardBinding(
			KeyboardActionId.trackOverviewDeleteSelection,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Delete selected Track overview entry/range",
			true,
			"Preserves the existing macOS Delete route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewOpenActiveBlockInSequenceEditor,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Open the active Track overview block in F6",
			true,
			"Block focus only; Return and Tab share one canonical action."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewOpenActiveBlockInSequenceEditor,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_TAB,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Open the active Track overview block in F6",
			true,
			"Plain Tab aliases Return only while Track overview block focus owns input."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewNavigatePreviousBlock,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_LEFT,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Select previous Track overview block",
			true,
			"Preserves plain Left block navigation."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewNavigateNextBlock,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RIGHT,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Select next Track overview block",
			true,
			"Preserves plain Right block navigation.")
	];
	}
	else {
		private enum KeyboardBinding[] TRACK_OVERVIEW_BLOCK_BINDINGS = [
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewLoopAllVoices,
				KeyboardContext.trackOverviewBlock,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_BACKSPACE,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
				"Set Track overview LOOP target for all voices",
				true,
				"Canonical compact Track overview all-voice LOOP display; Ctrl-Alt-L remains an alias."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewNavigation, 0,
						"Set LOOP target for all voices")]),
			KeyboardBinding(
				KeyboardActionId.trackOverviewLoopAllVoices,
				KeyboardContext.trackOverviewBlock,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_l,
				KMOD_CTRL | KMOD_ALT,
				KMOD_SHIFT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate),
				"Set Track overview LOOP target for all voices",
				true,
				"Uses selected overview block row to resolve each voice LOOP target."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewLoopActiveVoice,
				KeyboardContext.trackOverviewBlock,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_l,
				KMOD_CTRL | KMOD_SHIFT | KMOD_ALT,
				KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate | KeyboardSemanticModifier.shift),
				"Set Track overview LOOP target for selected/active voice",
				true,
				"Shift distinguishes active-voice LOOP from all-voice LOOP."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewNavigation, 1,
						"Set LOOP target for selected/active voice")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackOverviewCopyEntries,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Copy selected Track overview entries",
			true,
			"Preserves the existing default Ctrl-C predicate."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 0,
					"Copy selected block/range")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewPasteEntries,
				KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_v,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
				"Paste copied Track overview entries",
				true,
				"Preserves the existing default Ctrl-V predicate."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 1,
						"Paste copied track entries")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewFindUnusedSequence,
				KeyboardContext.trackOverviewBlock,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_f,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Change selected Track overview block to the next unused sequence",
				true,
				"Matches the F5/F7 next-unused sequence action for a selected overview block."), [
					KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 2,
						"Change selected block to next unused sequence")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.trackOverviewInsertEntry,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_INSERT,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none, KeyboardSemanticModifier.shift, "", "Delete"),
			"Insert selected Track overview entry",
			true,
			"Preserves the existing default Insert route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 4,
					"Insert selected track entry")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackOverviewInsertCopyEntry,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Insert copy of selected Track overview entry",
			true,
			"Preserves the existing Track overview insert-copy route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 5,
					"Insert copy of selected track entry")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.trackOverviewDeleteSelection,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DELETE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none, KEYBOARD_SAME_SEMANTIC_MODIFIERS, "", "Backspace/Delete"),
			"Delete selected Track overview entry/range",
			true,
			"Preserves the existing default Delete route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 6,
					"Delete selected block/range")]),
		KeyboardBinding(
			KeyboardActionId.trackOverviewOpenActiveBlockInSequenceEditor,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Open the active Track overview block in F6",
			true,
			"Block focus only; Return and Tab share one canonical action."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewOpenActiveBlockInSequenceEditor,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_TAB,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Open the active Track overview block in F6",
			true,
			"Plain Tab aliases Return only while Track overview block focus owns input."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewNavigatePreviousBlock,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_LEFT,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Select previous Track overview block",
			true,
			"Preserves plain Left block navigation."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewNavigateNextBlock,
			KeyboardContext.trackOverviewBlock,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RIGHT,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Select next Track overview block",
			true,
			"Preserves plain Right block navigation.")
		];
		}

	private enum KeyboardBinding[] EDITOR_UNDO_REDO_BINDINGS = [
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.editorUndo,
			KeyboardContext.editor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_z,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Undo the last editor mutation",
			true,
			"Preserves the existing normal editor Ctrl-Z route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.globalUndoRedo, 0,
					"Undo")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.editorRedo,
			KeyboardContext.editor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_r,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Redo the last editor mutation",
			true,
			"Preserves the existing normal editor Ctrl-R route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.globalUndoRedo, 1,
					"Redo")])
	];

	private enum KeyboardBinding[] TRACK_OVERVIEW_FOCUSED_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.trackOverviewScrollLeft,
			KeyboardContext.trackOverview,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_LEFT,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Scroll Track overview strip left",
			true,
			"Preserves the existing keyboard horizontal-scroll route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewScrollRight,
			KeyboardContext.trackOverview,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RIGHT,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
				"Scroll Track overview strip right",
				true,
				"Preserves the existing keyboard horizontal-scroll route."),
			KeyboardBinding(
				KeyboardActionId.trackOverviewUndo,
				KeyboardContext.trackOverview,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_z,
				KMOD_CTRL,
				KMOD_ALT,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
				"Undo the last Track overview mutation",
				true,
				"Preserves the existing Track overview focused Ctrl-Z route."),
			KeyboardBinding(
				KeyboardActionId.trackOverviewRedo,
				KeyboardContext.trackOverview,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_r,
				KMOD_CTRL,
				KMOD_ALT,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
				"Redo the last Track overview mutation",
				true,
				"Preserves the existing Track overview focused Ctrl-R route.")
		];

	private enum KeyboardBinding[] TRACK_OVERVIEW_TIMELINE_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelineStepLeft,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_LEFT,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move Track overview timeline one row left",
			true,
			"Shift-Left remains reserved for horizontal strip scrolling."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelineStepRight,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RIGHT,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move Track overview timeline one row right",
			true,
			"Shift-Right remains reserved for horizontal strip scrolling."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelinePageUp,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move Track overview timeline upward by one page step",
			true,
			"Matches the Timeline focus Up/PageUp route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelinePageUp,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEUP,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move Track overview timeline upward by one page step",
			true,
			"Matches the Timeline focus Up/PageUp route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelinePageDown,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move Track overview timeline downward by one page step",
			true,
			"Matches the Timeline focus Down/PageDown route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelinePageDown,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEDOWN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move Track overview timeline downward by one page step",
			true,
			"Matches the Timeline focus Down/PageDown route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelineLargePageUp,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move Track overview timeline upward by a large page step",
			true,
			"Matches the Timeline focus Shift-Up/Shift-PageUp route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelineLargePageUp,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEUP,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move Track overview timeline upward by a large page step",
			true,
			"Matches the Timeline focus Shift-Up/Shift-PageUp route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelineLargePageDown,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move Track overview timeline downward by a large page step",
			true,
			"Matches the Timeline focus Shift-Down/Shift-PageDown route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelineLargePageDown,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEDOWN,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move Track overview timeline downward by a large page step",
			true,
			"Matches the Timeline focus Shift-Down/Shift-PageDown route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelineHome,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_HOME,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move Track overview timeline to the start",
			true,
			"Preserves the existing Timeline focus Home route."),
		KeyboardBinding(
			KeyboardActionId.trackOverviewTimelineEnd,
			KeyboardContext.trackOverviewTimeline,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_END,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move Track overview timeline to the end",
			true,
			"Preserves the existing Timeline focus End route.")
		];

		private enum KeyboardBinding[] WORKSPACE_NAVIGATION_BINDINGS = [
			KeyboardBinding(
				KeyboardActionId.sequencerViewTrackTable,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_F5,
				0,
				KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
				"Switch to Track Table/order list view",
				true,
				"Top-level non-modal route; Sequencer keeps ownership when already focused."),
			KeyboardBinding(
				KeyboardActionId.sequencerViewSequenceEditor,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_F6,
				0,
				KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
				"Switch to Sequence/pattern editor view",
				true,
				"Top-level non-modal route; Sequencer keeps ownership when already focused."),
			KeyboardBinding(
				KeyboardActionId.sequencerViewTrackMap,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_F7,
				0,
				KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
				"Switch to Track Map view",
				true,
				"Top-level non-modal route; Sequencer keeps ownership when already focused."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.workspaceActivateSequencer,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_v,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Sequencer",
				true,
				"Preserves the old top-level Option/Alt route before non-modal editors consume it."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainTableNavigation, 2,
						"Jump to Sequencer")]),
			KeyboardBinding(
				KeyboardActionId.workspaceActivateVoice1,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_1,
				KMOD_ALT,
				KMOD_CTRL | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to voice 1",
				true,
				"Ctrl remains excluded to preserve Ctrl-1 voice mute priority."),
			KeyboardBinding(
				KeyboardActionId.workspaceActivateVoice2,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_2,
				KMOD_ALT,
				KMOD_CTRL | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to voice 2",
				true,
				"Ctrl remains excluded to preserve Ctrl-2 voice mute priority."),
			KeyboardBinding(
				KeyboardActionId.workspaceActivateVoice3,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_3,
				KMOD_ALT,
				KMOD_CTRL | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to voice 3",
				true,
				"Ctrl remains excluded to preserve Ctrl-3 voice mute priority."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.workspaceActivateInstrument,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_4,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Instrument table",
				true,
				"Numeric alias preserved from the old top-level route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainTableNavigation, 3,
						"Jump to Instrument table")]),
			KeyboardBinding(
				KeyboardActionId.workspaceActivateInstrument,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_i,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Instrument table",
				true,
				"Letter alias preserved from the old top-level route."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.workspaceActivateWave,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_5,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Wave table",
				true,
				"Numeric alias preserved from the old top-level route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainTableNavigation, 4,
						"Jump to Wave table")]),
			KeyboardBinding(
				KeyboardActionId.workspaceActivateWave,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_w,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Wave table",
				true,
				"Letter alias preserved from the old top-level route."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.workspaceActivatePulse,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_6,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Pulse table",
				true,
				"Numeric alias preserved from the old top-level route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainTableNavigation, 5,
						"Jump to Pulse table")]),
			KeyboardBinding(
				KeyboardActionId.workspaceActivatePulse,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_p,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Pulse table",
				true,
				"Letter alias preserved from the old top-level route."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.workspaceActivateFilter,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_7,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Filter table",
				true,
				"Numeric alias preserved from the old top-level route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainTableNavigation, 6,
						"Jump to Filter table")]),
			KeyboardBinding(
				KeyboardActionId.workspaceActivateFilter,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_f,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Filter table",
				true,
				"Letter alias preserved from the old top-level route."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.workspaceActivateCommand,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_8,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Command table",
				true,
				"Numeric alias preserved from the old top-level route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainTableNavigation, 7,
						"Jump to Command table")]),
			KeyboardBinding(
				KeyboardActionId.workspaceActivateCommand,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_m,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Command table",
				true,
				"Letter alias preserved from the old top-level route."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.workspaceActivateChord,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_9,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Chord table",
				true,
				"Numeric alias preserved from the old top-level route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainTableNavigation, 8,
						"Jump to Chord table")]),
			KeyboardBinding(
				KeyboardActionId.workspaceActivateChord,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_d,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Jump to Chord table",
				true,
				"Letter alias preserved from the old top-level route."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.workspaceActivateTitle,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_t,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Edit title / author / release info",
				true,
				"Preserves the old top-level song-info route before non-modal editors consume it."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainSongAfterClicks, 6,
						"Edit title / author / release info")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.workspaceActivateSpeed,
				KeyboardContext.workspaceNavigation,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_s,
				KMOD_ALT,
				0,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
				"Edit song speed",
				true,
				"Top-level non-modal route to the inline Speed editor."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainSongAfterClicks, 0,
						"Jump to/edit song speed"),
					KeyboardHelpPlacement(KeyboardHelpSection.mainTableNavigation, 10,
						"Jump to/edit song speed")])
			];

	private enum KeyboardBinding[] UI_WINDOW_SWITCHER_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.uiSubwindowPrevious,
			KeyboardContext.uiWindowSwitcher,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_TAB,
			KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move to the previous subwindow",
			true,
			"WindowSwitcher retains activation and wrapping policy."),
		KeyboardBinding(
			KeyboardActionId.uiSubwindowNext,
			KeyboardContext.uiWindowSwitcher,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_TAB,
			0,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move to the next subwindow",
			true,
			"WindowSwitcher retains activation and wrapping policy.")
	];

	private enum KeyboardBinding[] UI_TOP_LEVEL_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.uiMainWindowPrevious,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_TAB,
			KMOD_CTRL | KMOD_SHIFT,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl |
				KeyboardSemanticModifier.shift),
			"Move to the previous main window",
			true,
			"Toplevel retains activation and wrapping policy."),
		KeyboardBinding(
			KeyboardActionId.uiMainWindowNext,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_TAB,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Move to the next main window",
			true,
			"Toplevel retains activation and wrapping policy."),
		KeyboardBinding(
			KeyboardActionId.uiBaseOctaveDecrease,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_DIVIDE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Decrease base octave",
			true,
			"Toplevel retains octave bounds and key forwarding."),
		KeyboardBinding(
			KeyboardActionId.uiBaseOctaveIncrease,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_MULTIPLY,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Increase base octave",
			true,
			"Toplevel retains octave bounds and key forwarding."),
		KeyboardBinding(
			KeyboardActionId.uiInstrumentPrevious,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_MINUS,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Select the previous instrument",
			true,
			"Toplevel retains allowInstabNavigation and key forwarding."),
		KeyboardBinding(
			KeyboardActionId.uiInstrumentPrevious,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_MINUS,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Select the previous instrument",
			true,
			"Keypad alias."),
		KeyboardBinding(
			KeyboardActionId.uiInstrumentNext,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PLUS,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Select the next instrument",
			true,
			"Toplevel retains allowInstabNavigation and key forwarding."),
		KeyboardBinding(
			KeyboardActionId.uiInstrumentNext,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_PLUS,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Select the next instrument",
			true,
			"Keypad alias."),
		KeyboardBinding(
			KeyboardActionId.uiFollowInstrumentPointer,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Follow or return from an instrument table pointer",
			true,
			"Toplevel retains pointer validation and destination policy."),
		KeyboardBinding(
			KeyboardActionId.uiFollowInstrumentPointer,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_ENTER,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Follow or return from an instrument table pointer",
			true,
			"Keypad Enter alias."),
		KeyboardBinding(
			KeyboardActionId.uiFollowInstrumentPointer,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_RETURN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "Enter"),
			"Follow or return from an instrument table pointer",
			true,
			"Preserves the legacy unicode Return fallback.")
	];

	version(OSX) {
	private enum KeyboardBinding[] UI_TOP_LEVEL_PLATFORM_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.uiInstrumentNext,
			KeyboardContext.uiTopLevel,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_EQUALS,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Select the next instrument",
			true,
			"Preserves the existing macOS Shift-Equals plus-key alias.")
	];
	}
	else {
	private enum KeyboardBinding[] UI_TOP_LEVEL_PLATFORM_BINDINGS = [];
	}

	private enum KeyboardBinding[] CURSOR_STEP_INPUT_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequencerCursorStepDecrease,
			KeyboardContext.cursorStepInput,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Decrease cursor step value while editing St",
			true,
			"InputStepValue owns wrapping and mutation; metadata owns the displayed label."),
		KeyboardBinding(
			KeyboardActionId.sequencerCursorStepIncrease,
			KeyboardContext.cursorStepInput,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Increase cursor step value while editing St",
			true,
			"InputStepValue owns wrapping and mutation; metadata owns the displayed label.")
	];

	private enum KeyboardBinding[] UI_GLOBAL_BINDINGS = [
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.uiToggleFullscreen,
			KeyboardContext.uiGlobal,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			KMOD_ALT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Toggle fullscreen",
			true,
			"UI retains video mode policy."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 7,
					"Toggle fullscreen")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.uiToggleInterpolation,
			KeyboardContext.uiGlobal,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F2,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Toggle audio interpolation",
			true,
			"UI retains player reinitialisation."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 8,
					"Toggle audio interpolation")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.playbackTrackingToggle,
			KeyboardContext.uiGlobal,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_SCROLLLOCK,
			0,
			KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Start or stop playback tracking",
			true,
			"UI retains the playing-only gate and Fplay position transfer."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback, 7,
					"Start/stop tracking (works only when playing)")]),
		KeyboardBinding(
			KeyboardActionId.playbackFastForwardLarge,
			KeyboardContext.uiGlobal,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F8,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Fast forward by the large step",
			true,
			"UI retains the 25-unit fast-forward amount."),
		KeyboardBinding(
			KeyboardActionId.playbackFastForward,
			KeyboardContext.uiGlobal,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F8,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Fast forward",
			true,
			"UI retains the 5-unit fast-forward amount."),
		KeyboardBinding(
			KeyboardActionId.songSpeedDecrease,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedUnicode,
			'[',
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "["),
			"Decrease default song speed",
			true,
			"AltGr-friendly unicode alias."),
		KeyboardBinding(
			KeyboardActionId.songSpeedIncrease,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedUnicode,
			']',
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "]"),
			"Increase default song speed",
			true,
			"AltGr-friendly unicode alias."),
		KeyboardBinding(
			KeyboardActionId.songSpeedIncrease,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_EQUALS,
			KMOD_CTRL | KMOD_SHIFT,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary |
				KeyboardSemanticModifier.shift,
				KeyboardSemanticModifier.physicalControl |
				KeyboardSemanticModifier.shift),
			"Increase default song speed",
			true,
			"Top-row Shift-Equals compatibility alias."),
		KeyboardBinding(
			KeyboardActionId.songMultispeedDecrease,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedUnicode,
			'{',
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "{"),
			"Decrease multispeed framecall counter",
			true,
			"AltGr-friendly unicode alias."),
		KeyboardBinding(
			KeyboardActionId.songMultispeedIncrease,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedUnicode,
			'}',
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "}"),
			"Increase multispeed framecall counter",
			true,
			"AltGr-friendly unicode alias.")
	];

	version(OSX) {
	private enum KeyboardBinding[] SEQUENCE_SPLIT_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceSplit,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_p,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Split current sequence at the cursor",
			true,
			"Preserves the exact physical Control-P F6 split route on macOS.")
	];
	}
	else {
	private enum KeyboardBinding[] SEQUENCE_SPLIT_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceSplit,
			KeyboardContext.sequenceEditor,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_p,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Split current sequence at the cursor",
			true,
			"Preserves the existing default Ctrl-P modifier tolerance.")
	];
	}

	private enum KeyboardBinding[] SEQUENCE_INPUT_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceInputOctaveDecrease,
			KeyboardContext.sequenceInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_LESS,
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "<"),
			"Decrease the sequence input base octave",
			true,
			"Preserves the existing InputSeq unicode route."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputOctaveIncrease,
			KeyboardContext.sequenceInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_GREATER,
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, ">"),
			"Increase the sequence input base octave",
			true,
			"Preserves the existing InputSeq unicode route."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputToggleInstrumentAutoinsert,
			KeyboardContext.sequenceInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_SEMICOLON,
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, ";"),
			"Toggle automatic instrument insertion",
			true,
			"Preserves the existing InputSeq unicode route.")
	];

	private enum KeyboardBinding[] SEQUENCE_VALUE_INPUT_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceInputReuseValue,
			KeyboardContext.sequenceValueInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_SPACE,
			0,
			KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Reuse the previously entered value",
			true,
			"ExtendedInput owns the existing remembered-value route."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputClear,
			KeyboardContext.sequenceValueInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_PERIOD,
			0,
			KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "."),
			"Clear the current sequence value",
			true,
			"ExtendedInput owns the existing clear route.")
	];

	private enum KeyboardBinding[] NOTE_INPUT_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.sequenceInputGateOff,
			KeyboardContext.noteInput,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_1,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Enter a gate off",
			true,
			"Preserves the plain 1 note-table entry."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputGateOn,
			KeyboardContext.noteInput,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_a,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Enter a gate on",
			true,
			"Preserves the A note-table entry."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputGateOn,
			KeyboardContext.noteInput,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_1,
			KMOD_SHIFT,
			KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "!"),
			"Enter a gate on",
			true,
			"Preserves the Shift-1 exclamation alias."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputClear,
			KeyboardContext.noteInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_SPACE,
			0,
			KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Clear the current note row",
			true,
			"InputNote owns the existing full-row clear route."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputClear,
			KeyboardContext.noteInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_PERIOD,
			0,
			KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "."),
			"Clear the current note row",
			true,
			"InputNote owns the existing full-row clear route."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputTie,
			KeyboardContext.noteInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_COMMA,
			0,
			KMOD_CTRL | KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, ","),
			"Toggle tie on the current note",
			true,
			"Preserves the existing InputNote comma route."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputGrabInstrument,
			KeyboardContext.noteInput,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_g,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Grab the current row instrument",
			true,
			"Preserves the existing Control-G InputNote route."),
		KeyboardBinding(
			KeyboardActionId.sequenceInputGrabInstrument,
			KeyboardContext.noteInput,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_g,
			KMOD_ALT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Grab the current row instrument",
			true,
			"Preserves the existing Alt/Option-G InputNote alias.")
	];

	private enum KeyboardBinding[] TRACK_INPUT_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.trackInputFindUnusedSequence,
			KeyboardContext.trackInput,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_f,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Find the next unused sequence",
			true,
			"Preserves the explicit InputTrack Control-F route."),
		KeyboardBinding(
			KeyboardActionId.trackInputFindUnusedSequence,
			KeyboardContext.trackInput,
			KeyboardBindingKeyModel.translatedUnicode,
			6,
			0,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "F"),
			"Find the next unused sequence",
			true,
			"Preserves the legacy control-character InputTrack report."),
		KeyboardBinding(
			KeyboardActionId.trackInputPreviousSequence,
			KeyboardContext.trackInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_LESS,
			0,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "<"),
			"Select the previous sequence",
			true,
			"Preserves the existing InputTrack unicode route."),
		KeyboardBinding(
			KeyboardActionId.trackInputNextSequence,
			KeyboardContext.trackInput,
			KeyboardBindingKeyModel.translatedUnicode,
			SDLK_GREATER,
			0,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, ">"),
			"Select the next sequence",
			true,
			"Preserves the existing InputTrack unicode route."),
		KeyboardBinding(
			KeyboardActionId.trackInputCommitValue,
			KeyboardContext.trackInput,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_SPACE,
			0,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Commit the current track value",
			true,
			"InputTrack Space flushes its current edit buffer; it does not write a cached sequence.")
	];

	private enum KeyboardBinding[] SAVE_EXPORT_PLAIN_KEYPAD_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.saveExportFormatCt,
			KeyboardContext.saveExportDialog,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_1,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Set Save/export format to .ct",
			true,
			"Replaces the old plain-keypad dialog fallback."),
		KeyboardBinding(
			KeyboardActionId.saveExportFormatPrg,
			KeyboardContext.saveExportDialog,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_2,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Set Save/export format to .prg",
			true,
			"Replaces the old plain-keypad dialog fallback."),
		KeyboardBinding(
			KeyboardActionId.saveExportFormatSid,
			KeyboardContext.saveExportDialog,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_3,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Set Save/export format to .sid",
			true,
			"Replaces the old plain-keypad dialog fallback.")
	];

	private enum KeyboardBinding[] FILE_DIALOG_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.fileDialogConfirm,
			KeyboardContext.fileDialog,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Confirm the selected file-browser entry",
			true,
			"FileSelectorDialog retains directory, filename and workflow policy."),
		KeyboardBinding(
			KeyboardActionId.fileDialogConfirm,
			KeyboardContext.fileDialog,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_ENTER,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Confirm the selected file-browser entry",
			true,
			"Keypad Enter alias limited to the canonical file-browser context.")
	];

	version(OSX) {
	private enum KeyboardHelpGroup[] PLATFORM_KEYBOARD_HELP_GROUPS = [
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 0,
			[KeyboardActionId.sequenceRowDeleteSameLength],
			"Clear selected rows; otherwise delete row and keep length"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 1,
			[KeyboardActionId.sequenceRowInsertSameLength],
			"Insert blank row and shift contents down, same length"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 2,
			[KeyboardActionId.sequenceRowDeleteShrink],
			"Clear selected rows; otherwise delete row and shrink"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 3,
			[KeyboardActionId.sequenceRowInsertGrow],
			"Insert blank row and grow pattern length by one"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 4,
			[KeyboardActionId.sequenceRowExpandSequence],
			"Expand sequence by one row at the end"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 5,
			[KeyboardActionId.sequenceRowShrinkSequence],
			"Shrink sequence by one row from the end"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 6,
			[KeyboardActionId.sequenceRowQuickExpand],
			"Quick expand sequence to next 4*highlight boundary"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumnPlatform, 0,
			[KeyboardActionId.trackEntryInsertCopy],
			"Insert copy of track position")
	];
	}
	else {
	private enum KeyboardHelpGroup[] PLATFORM_KEYBOARD_HELP_GROUPS = [
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 0,
			[KeyboardActionId.sequenceRowDeleteSameLength,
			 KeyboardActionId.sequenceRowInsertSameLength,
			 KeyboardActionId.sequenceRowDeleteShrink,
			 KeyboardActionId.sequenceRowInsertGrow],
			"Insert/delete a row (Shift=w/ sequence expand/shrink)"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 1,
			[KeyboardActionId.sequenceRowExpandSequence],
			"Expand sequence by one row at the end"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 2,
			[KeyboardActionId.sequenceRowShrinkSequence],
			"Shrink sequence by one row from the end"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowPlatformEdit, 3,
			[KeyboardActionId.sequenceRowQuickExpand],
			"Quick expand sequence to next 4*highlight boundary")
	];
	}

	private enum KeyboardHelpGroup[] KEYBOARD_HELP_GROUPS = [
		KeyboardHelpGroup(
			KeyboardHelpSection.trackOverviewNavigation,
			2,
			[KeyboardActionId.trackOverviewNavigatePreviousBlock,
			 KeyboardActionId.trackOverviewNavigateNextBlock],
			"Select previous/next block when block-focused"),
		KeyboardHelpGroup(
			KeyboardHelpSection.trackOverviewNavigation,
			3,
			[KeyboardActionId.trackOverviewScrollLeft,
			 KeyboardActionId.trackOverviewScrollRight],
			"Scroll strip horizontally"),
		KeyboardHelpGroup(
			KeyboardHelpSection.trackOverviewNavigation,
			5,
			[KeyboardActionId.voiceToggleMute1,
			 KeyboardActionId.voiceToggleMute2,
			 KeyboardActionId.voiceToggleMute3],
			"Mute/unmute voices; muted lanes are dimmed"),
		KeyboardHelpGroup(
			KeyboardHelpSection.trackOverviewDisplay,
			0,
			[KeyboardActionId.playbackPlayFromMark,
			 KeyboardActionId.playbackPlayFromStart,
			 KeyboardActionId.playbackPlayFromCursor,
			 KeyboardActionId.playbackStop],
			"Playback controls"),
		KeyboardHelpGroup(
			KeyboardHelpSection.mainPlayback,
			6,
			[KeyboardActionId.playbackFastForward,
			 KeyboardActionId.playbackFastForwardLarge],
			"Fast forward (w/ Shift = Fast forward more)"),
		KeyboardHelpGroup(
			KeyboardHelpSection.mainPlayback,
			8,
			[KeyboardActionId.voiceToggleMute1,
			 KeyboardActionId.voiceToggleMute2,
			 KeyboardActionId.voiceToggleMute3],
			"Toggle voices on/off"),
		KeyboardHelpGroup(
			KeyboardHelpSection.mainSongBeforeClicks,
			0,
			[KeyboardActionId.songSpeedDecrease,
			 KeyboardActionId.songSpeedIncrease],
			"Decrease/increase song speed ($0/$1 shuffle, $2-$1F steady)"),
		KeyboardHelpGroup(
			KeyboardHelpSection.mainSongBeforeClicks,
			1,
			[KeyboardActionId.uiBaseOctaveDecrease],
			"Decrease base octave value (0-6)"),
		KeyboardHelpGroup(
			KeyboardHelpSection.mainSongBeforeClicks,
			2,
			[KeyboardActionId.uiBaseOctaveIncrease],
			"Increase base octave value (0-6)"),
		KeyboardHelpGroup(
			KeyboardHelpSection.mainSongAfterClicks,
			1,
			[KeyboardActionId.songMultispeedDecrease,
			 KeyboardActionId.songMultispeedIncrease],
			"Decrease/increase multispeed framecall counter"),
		KeyboardHelpGroup(
			KeyboardHelpSection.mainTableNavigation,
			0,
			[KeyboardActionId.uiSubwindowPrevious,
			 KeyboardActionId.uiSubwindowNext],
			"Move cursor between subwindows"),
		KeyboardHelpGroup(
			KeyboardHelpSection.mainTableNavigation,
			1,
			[KeyboardActionId.uiMainWindowPrevious,
			 KeyboardActionId.uiMainWindowNext],
			"Move cursor between main windows\n"
				~ "                          (sequencer, instrument table, subtables)"),
		KeyboardHelpGroup(
			KeyboardHelpSection.mainTableNavigation,
			9,
			[KeyboardActionId.workspaceActivateVoice1,
			 KeyboardActionId.workspaceActivateVoice2,
			 KeyboardActionId.workspaceActivateVoice3],
			"Jump to voice 1, 2 or 3"),
		KeyboardHelpGroup(
			KeyboardHelpSection.sequencerGeneralBeforeVoiceTab,
			0,
			[KeyboardActionId.workspaceActivateVoice1,
			 KeyboardActionId.workspaceActivateVoice2,
			 KeyboardActionId.workspaceActivateVoice3],
			"Jump to voice 1, 2 or 3"),
		KeyboardHelpGroup(
			KeyboardHelpSection.sequencerGeneralBeforeVoiceTab,
			1,
			[KeyboardActionId.sequencerNavigateVoicePrevious,
			 KeyboardActionId.sequencerNavigateVoiceNext],
			"Move cursor to the previous/next voice"),
		KeyboardHelpGroup(
			KeyboardHelpSection.sequencerGeneralAfterVoiceTab,
			4,
			[KeyboardActionId.sequencerSubtunePrevious,
			 KeyboardActionId.sequencerSubtuneNext],
			"Activate previous/next subtune",
			"sequencer"),
		KeyboardHelpGroup(
			KeyboardHelpSection.sequencerNavigation,
			0,
			[KeyboardActionId.sequencerOverviewNavigateHome,
			 KeyboardActionId.sequencerOverviewNavigateEnd],
			"Move cursor to SEQ start/end OR screen top/bottom"),
		KeyboardHelpGroup(
			KeyboardHelpSection.sequencerNavigation,
			1,
			[KeyboardActionId.sequencerViewNavigateSongStart,
			 KeyboardActionId.sequencerViewNavigateSongEnd],
			"Move cursor to song start/end"),
		KeyboardHelpGroup(
			KeyboardHelpSection.sequenceEditingSequencer,
			0,
			[KeyboardActionId.sequencerHighlightIncrease,
			 KeyboardActionId.sequencerHighlightDecrease],
			"Increase/decrease row highlight value"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceEditingSequencer, 4,
			[KeyboardActionId.sequenceSplit],
			"Split current sequence into two from cursor pos.\n"
				~ "                        `+dUse with caution."),
		KeyboardHelpGroup(
			KeyboardHelpSection.sequenceEditingSequencer,
			6,
			[KeyboardActionId.sequencerCursorStepSet],
			"Set cursor step value to 1-9 while editing St"),
		KeyboardHelpGroup(
			KeyboardHelpSection.sequenceEditingSequencer,
			7,
			[KeyboardActionId.sequencerCursorStepDecrease],
			"Decrease cursor step value while editing St"),
		KeyboardHelpGroup(
			KeyboardHelpSection.sequenceEditingSequencer,
			8,
			[KeyboardActionId.sequencerCursorStepIncrease],
			"Increase cursor step value while editing St"),
		KeyboardHelpGroup(KeyboardHelpSection.helpDialog, 0,
			[KeyboardActionId.helpClose], "Close help"),
		KeyboardHelpGroup(KeyboardHelpSection.helpDialog, 1,
			[KeyboardActionId.helpScrollUp, KeyboardActionId.helpScrollDown],
			"Scroll help up/down"),
		KeyboardHelpGroup(KeyboardHelpSection.helpDialog, 2,
			[KeyboardActionId.helpPageUp, KeyboardActionId.helpPageDown],
			"Page help up/down"),
		KeyboardHelpGroup(KeyboardHelpSection.helpDialog, 3,
			[KeyboardActionId.helpTop, KeyboardActionId.helpBottom],
			"Jump help to top/bottom"),
		KeyboardHelpGroup(KeyboardHelpSection.helpDialog, 4,
			[KeyboardActionId.helpTopicPrevious, KeyboardActionId.helpTopicNext],
			"Previous/next help topic"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 0,
			[KeyboardActionId.sequenceRowSelectionExtendUp],
			"Start/extend row selection up"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 1,
			[KeyboardActionId.sequenceRowSelectionExtendDown],
			"Start/extend row selection down"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 2,
			[KeyboardActionId.sequenceRowSelectionExtendPageUp],
			"Extend row selection one page up"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 3,
			[KeyboardActionId.sequenceRowSelectionExtendPageDown],
			"Extend row selection one page down"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 4,
			[KeyboardActionId.sequenceRowSelectionExtendHome],
			"Extend row selection to Home target"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 5,
			[KeyboardActionId.sequenceRowSelectionExtendEnd],
			"Extend row selection to End target"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 6,
			[KeyboardActionId.sequenceRowSelectionClear],
			"Clear row selection"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 7,
			[KeyboardActionId.sequenceRowSelectPattern],
			"Select all rows in current sequence"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 8,
			[KeyboardActionId.sequenceRowCopy], "Copy selected rows"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceRowClipboard, 9,
			[KeyboardActionId.sequenceRowPaste], "Paste rows at cursor"),
		KeyboardHelpGroup(KeyboardHelpSection.mainInstrumentTable, 0,
			[KeyboardActionId.instrumentLoadDialog],
			"Load current instrument from disk (no undo)"),
		KeyboardHelpGroup(KeyboardHelpSection.mainInstrumentTable, 1,
			[KeyboardActionId.instrumentSaveDialog],
			"Save current instrument to disk"),
		KeyboardHelpGroup(KeyboardHelpSection.mainInstrumentTable, 2,
			[KeyboardActionId.instrumentDeleteConfirm],
			"Delete current instrument (no undo)"),
		KeyboardHelpGroup(KeyboardHelpSection.mainInstrumentTable, 3,
			[KeyboardActionId.instrumentCopy],
			"Copy selected bytes, or whole Instrument with no byte selection"),
		KeyboardHelpGroup(KeyboardHelpSection.mainInstrumentTable, 4,
			[KeyboardActionId.instrumentPaste],
			"Paste most recently copied Instrument data"),
		KeyboardHelpGroup(KeyboardHelpSection.mainInstrumentTable, 5,
			[KeyboardActionId.instrumentByteSelectionExtendLeft,
				KeyboardActionId.instrumentByteSelectionExtendRight],
			"Select whole Instrument bytes left/right"),
		KeyboardHelpGroup(KeyboardHelpSection.mainInstrumentSelection, 0,
			[KeyboardActionId.uiInstrumentPrevious],
			"Select previous active Instrument"),
		KeyboardHelpGroup(KeyboardHelpSection.mainInstrumentSelection, 1,
			[KeyboardActionId.uiInstrumentNext],
			"Select next active Instrument"),
		KeyboardHelpGroup(KeyboardHelpSection.saveExport, 0,
			[KeyboardActionId.fileSaveExportDialog],
			"Open the Save/export menu"),
		KeyboardHelpGroup(KeyboardHelpSection.saveExport, 1,
			[KeyboardActionId.saveExportFormatCt,
			 KeyboardActionId.saveExportFormatPrg,
			 KeyboardActionId.saveExportFormatSid],
			"Set Fmt to .ct / .prg / .sid"),
		KeyboardHelpGroup(KeyboardHelpSection.saveExport, 2,
			[KeyboardActionId.saveExportNextField],
			"Move through filename and export option fields"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceTranspose, 0,
			[KeyboardActionId.sequenceTransposeSemitoneUp,
			 KeyboardActionId.sequenceTransposeSemitoneDown],
			"Transpose semitone up/down from cursor down"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceTranspose, 1,
			[KeyboardActionId.sequenceTransposeOctaveUp,
			 KeyboardActionId.sequenceTransposeOctaveDown],
			"Transpose octave up/down from cursor down"),
		KeyboardHelpGroup(KeyboardHelpSection.sequenceEditingInput, 0,
			[KeyboardActionId.sequencePlayRowAllVoices],
			"Play notes for all voices in current row"),
		KeyboardHelpGroup(KeyboardHelpSection.noteColumn, 0,
			[KeyboardActionId.sequenceInputGateOff],
			"Enter a gate off (===)"),
		KeyboardHelpGroup(KeyboardHelpSection.noteColumn, 1,
			[KeyboardActionId.sequenceInputGateOn],
			"Enter a gate on (+++)"),
		KeyboardHelpGroup(KeyboardHelpSection.noteColumn, 2,
			[KeyboardActionId.sequenceInputClear], "Clear"),
		KeyboardHelpGroup(KeyboardHelpSection.noteColumn, 3,
			[KeyboardActionId.sequenceInputReuseValue],
			"Insert previously entered instrument/command value\n"
				~ "                          (in instrument/command column only)"),
		KeyboardHelpGroup(KeyboardHelpSection.noteColumn, 4,
			[KeyboardActionId.sequenceInputOctaveDecrease,
			 KeyboardActionId.sequenceInputOctaveIncrease],
			"Decrease/increase base octave"),
		KeyboardHelpGroup(KeyboardHelpSection.noteColumn, 5,
			[KeyboardActionId.sequenceInputToggleInstrumentAutoinsert],
			"Toggle insert instrument value automatically-mode"),
		KeyboardHelpGroup(KeyboardHelpSection.noteColumn, 6,
			[KeyboardActionId.sequenceInputTie],
			"Change the note in current row to a tie note"),
		KeyboardHelpGroup(KeyboardHelpSection.noteColumn, 7,
			[KeyboardActionId.sequencerViewToggleTrackSequence],
			"Switch to the track column (F5)"),
		KeyboardHelpGroup(KeyboardHelpSection.noteColumn, 8,
			[KeyboardActionId.sequenceInputGrabInstrument],
			"Grab the instrument value in the current row"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumn, 0,
			[KeyboardActionId.sequencerViewToggleTrackSequence],
			"Switch to the note column (F6)"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumn, 1,
			[KeyboardActionId.trackInputFindUnusedSequence],
			"Find next unused sequence after current value"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumn, 2,
			[KeyboardActionId.trackInputPreviousSequence,
			 KeyboardActionId.trackInputNextSequence],
			"Select previous/next sequence"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumn, 3,
			[KeyboardActionId.trackEntryCopyPrompt],
			"Ask for a number and copy the N of tracks into clipboard"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumn, 4,
			[KeyboardActionId.trackEntryPastePrompt],
			"Paste copied tracks from the clipboard"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumn, 5,
			[KeyboardActionId.trackInputCommitValue],
			"Commit the current track value"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumn, 6,
			[KeyboardActionId.trackEntryInsert,
			 KeyboardActionId.trackEntryDelete],
			"Insert empty track (A000) or delete track from cursor\n"
				~ "                          pos down"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumn, 7,
			[KeyboardActionId.trackEntryInsertToEnd,
			 KeyboardActionId.trackEntryDeleteToEnd],
			"Insert/delete track to end of voice and move cursor there"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumnAdvanced, 0,
			[KeyboardActionId.trackEntryInsertAllVoices,
			 KeyboardActionId.trackEntryDeleteAllVoices],
			"Insert/delete a track for all voices"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumnAdvanced, 1,
			[KeyboardActionId.trackEntrySwapWithVoice1],
			"Swap voice's track with voice 1's tracks from crsr down"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumnAdvanced, 2,
			[KeyboardActionId.trackEntrySwapWithVoice2],
			"Swap voice's track with voice 2's tracks from crsr down"),
		KeyboardHelpGroup(KeyboardHelpSection.trackColumnAdvanced, 3,
			[KeyboardActionId.trackEntrySwapWithVoice3],
			"Swap voice's track with voice 3's tracks from crsr down"),
		KeyboardHelpGroup(KeyboardHelpSection.waveTableHelp, 0,
			[KeyboardActionId.waveSeekCurrentInstrumentWave],
			"Seek to the current instrument's wave program row")
	] ~ PLATFORM_KEYBOARD_HELP_GROUPS;

	private KeyboardBinding sequencerCursorStepBinding(int key,
			KeyboardHelpPlacement[] help = []) {
		return keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.sequencerCursorStepSet,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			key,
			0,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, "Keypad 1-9"),
			"Set cursor step value",
			true,
			"Input resolution returns the selected 1-9 value; Sequencer owns stepValue."),
			help);
	}

	// Canonical binding definitions. `translatedKeyinfo` keys and modifiers use
	// the Keyinfo model after com.kbd.translate(...), not physical SDL events.
	// Binding facts and short Help placement live here; consumers own behavior.
	version(OSX) {
	private enum KeyboardBinding[] APP_QUIT_COMMAND_BINDINGS = [
		KeyboardBinding(
			KeyboardActionId.appQuitConfirm,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_q,
			KMOD_CTRL | KMOD_SHIFT,
			KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Confirm app exit",
			true,
			"Main loop retains SDL quit suppression while dispatching the translated action."),
		KeyboardBinding(
			KeyboardActionId.appQuitConfirm,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_w,
			KMOD_CTRL | KMOD_SHIFT,
			KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
			"Confirm app exit",
			true,
			"Main loop retains SDL quit suppression while dispatching the translated action.")
	];
	}
	else {
	private enum KeyboardBinding[] APP_QUIT_COMMAND_BINDINGS = [];
	}

	version(OSX) {
	private enum KeyboardBinding[] APP_AUDIO_SETTINGS_BINDINGS = [
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.appAudioSettings,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_COMMA,
			KMOD_CTRL | KMOD_SHIFT,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(
				KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift,
				KeyboardSemanticModifier.primary, ",", ","),
			"Open Audio Settings",
			true,
			"Physical Command-comma translates to Ctrl-Shift-comma before global resolution."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 6,
					"Open Audio Settings")])
	];
	}
	else {
	private enum KeyboardBinding[] APP_AUDIO_SETTINGS_BINDINGS = [
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.appAudioSettings,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_COMMA,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary,
				KEYBOARD_SAME_SEMANTIC_MODIFIERS, ",", ","),
			"Open Audio Settings",
			true,
			"Default platforms use Ctrl-comma; plain comma remains F6 note tie."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 6,
					"Open Audio Settings")])
	];
	}

	enum KeyboardBinding[] KEYBOARD_BINDING_METADATA = [
		KeyboardBinding(
			KeyboardActionId.globalOpenHelp,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F12,
		0,
		KMOD_CTRL | KMOD_ALT | KMOD_GUI,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Open contextual help",
			true,
			"F12 opens help with or without Shift; Ctrl-F12 has another existing meaning."),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.appAbout,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F9,
			0,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Open the About dialog",
			true,
			"Preserves the existing plain F9 app dialog route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 3,
					"Open the About dialog")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.fileLoadDialog,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F10,
			0,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Open the Load Song dialog",
			true,
			"Preserves the existing plain F10 file dialog route."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 1,
					"Open the Load song dialog")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.fileSaveExportDialog,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F11,
			0,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Open the Save/export dialog",
			true,
			"UI preserves the existing flush and skip-immediate-keypress behaviour."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 2,
					"Open the Save/export menu")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.fileQuickSave,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F11,
			KMOD_CTRL,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Quick save song",
			true,
			"UI preserves the existing flush, filename sync, and failure status behaviour."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 4,
					"Quick save song (doesn't ask a filename)")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.appQuitConfirm,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_ESCAPE,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none, KEYBOARD_SAME_SEMANTIC_MODIFIERS, "Esc Esc"),
			"Confirm app exit",
			true,
			"UI owns the double-Esc gate before executing this canonical action."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 0,
					"Quit program")]),
			KeyboardBinding(
				KeyboardActionId.songSpeedDecrease,
				KeyboardContext.global,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_KP_MINUS,
			KMOD_CTRL,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Decrease default song speed",
				true,
				"Unicode `[` is handled by resolveSongSpeedKeyboardAction to preserve the legacy AltGr-friendly route."),
			KeyboardBinding(
				KeyboardActionId.songSpeedDecrease,
				KeyboardContext.global,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_MINUS,
				KMOD_CTRL,
				KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Decrease default song speed",
				true,
				"Top-row compatibility alias; execution remains in Toplevel."),
			KeyboardBinding(
				KeyboardActionId.songSpeedIncrease,
				KeyboardContext.global,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_KP_PLUS,
			KMOD_CTRL,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Increase default song speed",
				true,
				"Unicode `]` is handled by resolveSongSpeedKeyboardAction to preserve the legacy AltGr-friendly route."),
			KeyboardBinding(
				KeyboardActionId.songSpeedIncrease,
				KeyboardContext.global,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_PLUS,
				KMOD_CTRL,
				KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Increase default song speed",
				true,
				"Top-row compatibility alias; Shift-Equals layouts are handled by resolveSongSpeedKeyboardAction."),
		KeyboardBinding(
			KeyboardActionId.songMultispeedDecrease,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_MINUS,
			KMOD_ALT,
			KMOD_CTRL | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Decrease multispeed framecall counter",
			true,
			"Unicode `{` is handled by resolveSongMultispeedKeyboardAction to preserve the legacy AltGr-friendly route."),
		KeyboardBinding(
			KeyboardActionId.songMultispeedIncrease,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_PLUS,
			KMOD_ALT,
			KMOD_CTRL | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Increase multispeed framecall counter",
			true,
			"Unicode `}` is handled by resolveSongMultispeedKeyboardAction to preserve the legacy AltGr-friendly route."),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.songKeyjamToggle,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_SPACE,
			KMOD_CTRL,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Toggle keyjam mode",
			true,
			"UI preserves the existing song version gate and status message."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainSongAfterClicks, 2,
					"Toggle keyjam mode")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.uiToggleHelpText,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_h,
			KMOD_ALT,
			KMOD_SHIFT | KMOD_CTRL | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Toggle inline help/status texts",
			true,
			"Toplevel preserves the existing displayHelp toggle and status message."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainApp, 5,
					"Toggle help/status texts")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.songClearSequencesConfirm,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_0,
			KMOD_ALT,
			KMOD_SHIFT | KMOD_CTRL | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Clear sequences with confirmation",
			true,
			"Toplevel opens the existing modal ConfirmationDialog before clearing."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainSongAfterClicks, 7,
					"Clear sequences")]),
		KeyboardBinding(
			KeyboardActionId.songClearSequencesConfirm,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_CTRL | KMOD_ALT,
			KMOD_SHIFT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.alternate),
			"Clear sequences with confirmation",
			true,
			"Toplevel opens the existing modal ConfirmationDialog before clearing."),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.songOptimizeConfirm,
			KeyboardContext.global,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_PERIOD,
			KMOD_ALT,
			KMOD_SHIFT | KMOD_CTRL | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Optimise/purge unused song data with confirmation",
			true,
			"Toplevel opens the existing modal ConfirmationDialog before purge."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainSongAfterClicks, 8,
					"Optimise/purge unused song data")]),
			KeyboardBinding(
				KeyboardActionId.songOptimizeConfirm,
				KeyboardContext.global,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_o,
			KMOD_CTRL | KMOD_ALT,
			KMOD_SHIFT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.alternate, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.alternate),
				"Optimise/purge unused song data with confirmation",
				true,
				"Toplevel opens the existing modal ConfirmationDialog before purge."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.songSidModelToggle,
				KeyboardContext.global,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_F3,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Toggle SID type (6581/8580)",
				true,
				"UI preserves the existing song SID model mutation and player update."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainSongAfterClicks, 3,
						"Toggle SID type (6581/8580)")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.songSidFilterPresetNext,
				KeyboardContext.global,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_F8,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Select next SID filter preset",
				true,
				"UI preserves the existing audio.player.nextFP route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainSongAfterClicks, 4,
						"Select next SID filter preset")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.songSidFilterPresetPrevious,
				KeyboardContext.global,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_F8,
				KMOD_CTRL | KMOD_SHIFT,
				KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary | KeyboardSemanticModifier.shift, KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.shift),
				"Select previous SID filter preset",
				true,
				"UI preserves the existing audio.player.prevFP route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainSongAfterClicks, 5,
						"Select previous SID filter preset")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.uiVisualModeToggle,
				KeyboardContext.global,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_F9,
				KMOD_CTRL,
				KMOD_ALT,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary),
				"Toggle Oscilloscope / SID register panel",
				true,
				"UI preserves the existing loose Ctrl route and Mac Command-F9 help label while excluding Alt/Option."), [
					KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback, 9,
						"Toggle Oscilloscope / SID register panel")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.playbackPlayFromMark,
			KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_F1,
		0,
		KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Play from playback mark",
			true,
			"Plain F1 route; Shift-F1 has its own tracking action."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback, 0,
					"Play from playback mark")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.playbackPlayFromMarkTracking,
		KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_F1,
		KMOD_SHIFT,
		KMOD_CTRL | KMOD_ALT | KMOD_GUI,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
		"Play/resume from mark with tracking",
			true,
			"Uses the existing F1orF2 Shift path; no playback logic is moved."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback, 1,
					"Play / resume from mark with tracking"),
				KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewNavigation, 4,
					"Play with tracking and centre-follow")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.playbackPlayFromStart,
		KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_F2,
		0,
		KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Play from song start",
			true,
			"Plain F2 route; Shift-F2 has its own tracking action."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback, 2,
					"Play from the start")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.playbackPlayFromStartTracking,
		KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_F2,
		KMOD_SHIFT,
		KMOD_CTRL | KMOD_ALT | KMOD_GUI,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
		"Play/resume from song start with tracking",
			true,
			"Uses the existing F1orF2 Shift path; no playback logic is moved."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback, 3,
					"Play / resume from the start with tracking")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.playbackPlayFromCursor,
		KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_F3,
		0,
		KMOD_CTRL | KMOD_ALT | KMOD_GUI,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Play from current editor position",
			true,
			"Shift remains allowed because the existing source route did not distinguish Shift-F3."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback, 4,
					"Play from cursor position")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.playbackStop,
		KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_F4,
		0,
		KMOD_CTRL | KMOD_ALT | KMOD_GUI,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Stop playback",
			true,
			"Shift remains allowed because the existing source route did not distinguish Shift-F4."), [
				KeyboardHelpPlacement(KeyboardHelpSection.mainPlayback, 5,
					"Stop playback")]),
	KeyboardBinding(
		KeyboardActionId.voiceToggleMute1,
		KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_1,
		KMOD_CTRL,
		KMOD_ALT,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
		"Toggle voice 1 mute",
		true,
		"Matches the existing Ctrl branch; Shift remains allowed and Alt keeps its old priority."),
	KeyboardBinding(
		KeyboardActionId.voiceToggleMute2,
		KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_2,
		KMOD_CTRL,
		KMOD_ALT,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
		"Toggle voice 2 mute",
		true,
		"Matches the existing Ctrl branch; Shift remains allowed and Alt keeps its old priority."),
	KeyboardBinding(
		KeyboardActionId.voiceToggleMute3,
		KeyboardContext.global,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_3,
		KMOD_CTRL,
		KMOD_ALT,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
		"Toggle voice 3 mute",
		true,
		"Matches the existing Ctrl branch; Shift remains allowed and Alt keeps its old priority."),
	KeyboardBinding(
		KeyboardActionId.helpClose,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_ESCAPE,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Close help",
		true,
		"HelpDialog currently closes from the unicode field."),
	KeyboardBinding(
		KeyboardActionId.helpClose,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_RETURN,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Close help",
		true,
		"HelpDialog currently closes from the unicode field."),
	KeyboardBinding(
		KeyboardActionId.helpScrollUp,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_UP,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Scroll help up",
		true,
		"HelpDialog navigation currently ignores non-Alt modifiers."),
	KeyboardBinding(
		KeyboardActionId.helpScrollDown,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_DOWN,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Scroll help down",
		true,
		"HelpDialog navigation currently ignores non-Alt modifiers."),
	KeyboardBinding(
		KeyboardActionId.helpPageUp,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_PAGEUP,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Page help up",
		true,
		"HelpDialog navigation currently ignores non-Alt modifiers."),
	KeyboardBinding(
		KeyboardActionId.helpPageDown,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_PAGEDOWN,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Page help down",
		true,
		"Also bound to Space and + in the current HelpDialog."),
	KeyboardBinding(
		KeyboardActionId.helpPageDown,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_SPACE,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Page help down",
		true,
		"Also bound to PgDn and + in the current HelpDialog."),
	KeyboardBinding(
		KeyboardActionId.helpPageDown,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_PLUS,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Page help down",
		true,
		"Also bound to PgDn and Space in the current HelpDialog."),
	KeyboardBinding(
		KeyboardActionId.helpTop,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_HOME,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Jump help to top",
		true,
		"HelpDialog navigation currently ignores non-Alt modifiers."),
	KeyboardBinding(
		KeyboardActionId.helpBottom,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_END,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Jump help to bottom",
		true,
		"HelpDialog navigation currently ignores non-Alt modifiers."),
	KeyboardBinding(
		KeyboardActionId.helpTopicPrevious,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_LEFT,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Previous help topic",
		true,
		"Only switches topics when topic switching is enabled."),
	KeyboardBinding(
		KeyboardActionId.helpTopicNext,
		KeyboardContext.helpDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_RIGHT,
		0,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
		"Next help topic",
		true,
		"If topic switching is disabled, Right pages down instead."),
	KeyboardBinding(
		KeyboardActionId.saveExportFormatCt,
		KeyboardContext.saveExportDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_1,
		KMOD_CTRL,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
		"Set Save/export format to .ct",
		true,
		"Matches the existing translated Keyinfo check; extra modifiers are preserved."),
	KeyboardBinding(
		KeyboardActionId.saveExportFormatPrg,
		KeyboardContext.saveExportDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_2,
		KMOD_CTRL,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
		"Set Save/export format to .prg",
		true,
		"Matches the existing translated Keyinfo check; extra modifiers are preserved."),
		KeyboardBinding(
			KeyboardActionId.saveExportFormatSid,
			KeyboardContext.saveExportDialog,
			KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_3,
		KMOD_CTRL,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
		"Set Save/export format to .sid",
		true,
		"Matches the existing translated Keyinfo check; extra modifiers are preserved."),
	KeyboardBinding(
		KeyboardActionId.saveExportFormatCt,
		KeyboardContext.saveExportDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_KP_1,
		KMOD_CTRL,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl, "1"),
		"Set Save/export format to .ct",
		true,
		"Preserves the old Ctrl-keypad format shortcut path."),
	KeyboardBinding(
		KeyboardActionId.saveExportFormatPrg,
		KeyboardContext.saveExportDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
		SDLK_KP_2,
		KMOD_CTRL,
		0,
		KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl, "2"),
		"Set Save/export format to .prg",
		true,
		"Preserves the old Ctrl-keypad format shortcut path."),
	KeyboardBinding(
		KeyboardActionId.saveExportFormatSid,
		KeyboardContext.saveExportDialog,
		KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_KP_3,
			KMOD_CTRL,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl, "3"),
			"Set Save/export format to .sid",
			true,
			"Preserves the old Ctrl-keypad format shortcut path."),
		KeyboardBinding(
			KeyboardActionId.saveExportNextField,
			KeyboardContext.saveExportDialog,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_TAB,
			0,
			KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move through Save/export fields",
			true,
			"Shift remains allowed so the existing WindowSwitcher direction logic is preserved."),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.sequencerViewTrackTableWithTrackList,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F5,
			KMOD_SHIFT,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Switch to Track Table and display track lists",
			true,
			"Distinct action preserves the existing Shift-F5 displayTracklist policy; Ctrl remains tolerated."), [
				KeyboardHelpPlacement(KeyboardHelpSection.sequencerViews, 1,
					"Display tracks alongside the sequences")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.sequencerViewTrackTable,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F5,
			0,
			KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Switch to Track Table/order list view",
			true,
			"Ctrl is tolerated for physical function-key reports; Shift has its own action."), [
				KeyboardHelpPlacement(KeyboardHelpSection.sequencerViews, 0,
					"Enter to the track column"),
				KeyboardHelpPlacement(KeyboardHelpSection.trackTableView, 0,
					"Enter to the track column")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.sequencerViewSequenceEditor,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F6,
			0,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Switch to Sequence/pattern editor view",
			true,
			"Ctrl is tolerated for physical function-key reports; Alt/GUI remain excluded."), [
				KeyboardHelpPlacement(KeyboardHelpSection.sequencerViews, 2,
					"Enter to the note column")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.sequencerViewTrackMap,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F7,
			0,
			KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Switch to Track Map view",
			true,
			"Ctrl is tolerated for physical function-key reports; Alt/GUI remain excluded."), [
				KeyboardHelpPlacement(KeyboardHelpSection.sequencerViews, 3,
					"Display tracks only ('overview mode')"),
				KeyboardHelpPlacement(KeyboardHelpSection.trackMapView, 0,
					"Display tracks only ('overview mode')")]),
		keyboardBindingWithHelp(KeyboardBinding(
			KeyboardActionId.sequencerViewToggleTrackSequence,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RETURN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Toggle F5/F6; follow complete Instrument/effect references in F6",
			true,
			"Sequencer preserves the saved F6 position when toggling through F5."), [
				KeyboardHelpPlacement(KeyboardHelpSection.sequencerViews, 4,
					"Toggle F5/F6; follow complete Instrument/effect references in F6")]),
		KeyboardBinding(
			KeyboardActionId.sequencerNavigateVoicePrevious,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_TAB,
			KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move cursor to the previous voice",
			true,
			"Shift wins even when other modifiers are present, matching VoiceTable."),
		KeyboardBinding(
			KeyboardActionId.sequencerNavigateVoiceNext,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_TAB,
			0,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move cursor to the next voice",
			true,
			"Non-Shift modifiers remain tolerated, matching VoiceTable."),
		sequencerCursorStepBinding(SDLK_KP_1),
		sequencerCursorStepBinding(SDLK_KP_2),
		sequencerCursorStepBinding(SDLK_KP_3),
		sequencerCursorStepBinding(SDLK_KP_4),
		sequencerCursorStepBinding(SDLK_KP_5),
		sequencerCursorStepBinding(SDLK_KP_6),
		sequencerCursorStepBinding(SDLK_KP_7),
		sequencerCursorStepBinding(SDLK_KP_8),
		sequencerCursorStepBinding(SDLK_KP_9),
		KeyboardBinding(
			KeyboardActionId.sequencerSubtunePrevious,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_LEFT,
			KMOD_ALT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Activate previous subtune",
			true,
			"Extra modifiers remain tolerated, matching the former Alt branch."),
		KeyboardBinding(
			KeyboardActionId.sequencerSubtuneNext,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_RIGHT,
			KMOD_ALT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.alternate),
			"Activate next subtune",
			true,
			"Extra modifiers remain tolerated, matching the former Alt branch."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigateSongStart,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_HOME,
			KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move cursor to song start",
			true,
			"Shift wins over other modifiers, matching VoiceTable."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigateSongEnd,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_END,
			KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move cursor to song end",
			true,
			"Shift wins over other modifiers, matching VoiceTable."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigateLargePageUp,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEUP,
			KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move upward by the existing large PageUp amount",
			true,
			"VoiceTable retains the accepted two-step Shift-PageUp result."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigateLargePageDown,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEDOWN,
			KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move downward by the existing large PageDown amount",
			true,
			"VoiceTable retains the accepted two-step Shift-PageDown result."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigatePageUp,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move upward by one view page",
			true,
			"Preserves the former Shift-Up goto PageUp route."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigatePageDown,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			KMOD_SHIFT,
			0,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.shift),
			"Move downward by one view page",
			true,
			"Preserves the former Shift-Down goto PageDown route."),
		KeyboardBinding(
			KeyboardActionId.sequencerOverviewNavigateHome,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_HOME,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move to the active overview block start",
			true,
			"Sequencer retains the accepted F5/F6/F7 owner-specific Home policy."),
		KeyboardBinding(
			KeyboardActionId.sequencerOverviewNavigateEnd,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_END,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move to the active overview block end",
			true,
			"Sequencer retains the accepted F5/F6/F7 owner-specific End policy."),
		KeyboardBinding(
			KeyboardActionId.sequencerOverviewNavigateUp,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move upward through the overview-owned editor position",
			true,
			"Preserves accepted unmodified F5/F6/F7 global-row navigation."),
		KeyboardBinding(
			KeyboardActionId.sequencerOverviewNavigateDown,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move downward through the overview-owned editor position",
			true,
			"Preserves accepted unmodified F5/F6/F7 global-row navigation."),
		KeyboardBinding(
			KeyboardActionId.sequencerOverviewNavigatePageUp,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEUP,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move upward by the overview-owned page amount",
			true,
			"Preserves accepted unmodified F5/F6/F7 page navigation."),
		KeyboardBinding(
			KeyboardActionId.sequencerOverviewNavigatePageDown,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEDOWN,
			0,
			KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move downward by the overview-owned page amount",
			true,
			"Preserves accepted unmodified F5/F6/F7 page navigation."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewScrollUp,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			KMOD_CTRL,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Scroll the view upward while retaining the cursor row",
			true,
			"Preserves the former Ctrl-Up scroll(-1), step(1) route."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewScrollDown,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			KMOD_CTRL,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Scroll the view downward while retaining the cursor row",
			true,
			"Preserves the former Ctrl-Down scroll(1), step(-1) route."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigateUp,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_UP,
			0,
			KMOD_SHIFT | KMOD_CTRL,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move the active view upward by one row",
			true,
			"Fallback for tolerated Alt/GUI modifiers; plain Up is resolved earlier."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigateDown,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_DOWN,
			0,
			KMOD_SHIFT | KMOD_CTRL,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move the active view downward by one row",
			true,
			"Fallback for tolerated Alt/GUI modifiers; plain Down is resolved earlier."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigatePageUp,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEUP,
			0,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move the active view upward by one page",
			true,
			"Fallback for modified PageUp; plain PageUp is resolved earlier."),
		KeyboardBinding(
			KeyboardActionId.sequencerViewNavigatePageDown,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PAGEDOWN,
			0,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Move the active view downward by one page",
			true,
			"Fallback for modified PageDown; plain PageDown is resolved earlier."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.sequencerPlaybackMarkSet,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_F1,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
				"Set playback mark at current track position",
				true,
				"Canonical compact playback-marker display; Backspace and Plus remain aliases."), [
					KeyboardHelpPlacement(KeyboardHelpSection.sequencePlaybackMarkStart, 0,
						"Set playback start marks for all voices")]),
		KeyboardBinding(
			KeyboardActionId.sequencerPlaybackMarkSet,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			0,
			KMOD_SHIFT | KMOD_CTRL,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Set playback mark at current track position",
			true,
			"Preserves the former non-Shift/non-Ctrl Backspace alias."),
		KeyboardBinding(
			KeyboardActionId.sequencerPlaybackMarkSet,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_PLUS,
			0,
			KMOD_SHIFT | KMOD_CTRL,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
			"Set playback mark at current track position",
			true,
			"Preserves the former non-Shift/non-Ctrl Plus alias."),
		KeyboardBinding(
			KeyboardActionId.trackEntryLoopSetAllVoices,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_BACKSPACE,
			KMOD_CTRL,
			KMOD_SHIFT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Set track LOOP target for all voices",
			true,
			"Preserves VoiceTable Ctrl-Backspace after TrackTable-specific routing."),
		KeyboardBinding(
			KeyboardActionId.sequencerDebugSequenceDialog,
			KeyboardContext.sequencer,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_F12,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl),
			"Open the sequence debug dialog",
			true,
			"Hidden developer route; Alt retains its former precedence."),
			KeyboardBinding(
				KeyboardActionId.sequencerHighlightIncrease,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_m,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Increase row highlight value",
				true,
				"VoiceTable preserves the existing max-16 bound."),
			KeyboardBinding(
				KeyboardActionId.sequencerHighlightDecrease,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_n,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Decrease row highlight value",
				true,
				"VoiceTable preserves the existing min-1 bound."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.sequencerRowCountersToggle,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_e,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Show/hide sequence row counters",
				true,
				"VoiceTable preserves the existing display toggle."), [
					KeyboardHelpPlacement(KeyboardHelpSection.sequenceEditingSequencer,
						2, "Show/hide row counters for sequences")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.sequencerRelativeNotesToggle,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_t,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Toggle relative note display",
				true,
				"VoiceTable preserves the existing status message."), [
					KeyboardHelpPlacement(KeyboardHelpSection.sequenceEditingSequencer,
						3, "Toggle notes relative to current transpose")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.sequencerHighlightOffsetSet,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_0,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Set row highlight offset to current cursor row",
				true,
				"Top-row zero only; Keypad 0 remains F6 play-row."), [
					KeyboardHelpPlacement(KeyboardHelpSection.sequenceEditingSequencer,
						1, "Reset highlighting to current row")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.sequencerPlaybackMarkSetActiveVoice,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_F1,
				KMOD_CTRL | KMOD_SHIFT,
				KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.physicalControl | KeyboardSemanticModifier.shift),
				"Set active voice playback mark",
				true,
				"Sets only the active editor voice mark."), [
					KeyboardHelpPlacement(KeyboardHelpSection.sequencePlaybackMarkStart, 1,
						"Set playback start mark for active voice"),
					KeyboardHelpPlacement(KeyboardHelpSection.trackOverviewEdit, 3,
						"Set active voice playback mark")]),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.sequencerPlaybackMarkJump,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_h,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Jump to playback mark and realign voices",
				true,
				"VoiceTable preserves the existing Jump.toMark route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.sequencePlaybackMarkStart,
						2, "Jump to playback mark position (also realigns the voices)")]),
			KeyboardBinding(
				KeyboardActionId.sequencerPlaybackMarkJump,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_HOME,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Jump to playback mark and realign voices",
				true,
				"VoiceTable preserves the existing Ctrl-Home Jump.toMark route."),
			keyboardBindingWithHelp(KeyboardBinding(
				KeyboardActionId.sequencerPlaybackMarkCenter,
				KeyboardContext.sequencer,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_l,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Centre/realign voices around the active row",
				true,
				"VoiceTable preserves the existing centralize route."), [
					KeyboardHelpPlacement(KeyboardHelpSection.sequencePlaybackMarkStart,
						3, "Centre/realign voices around the active row")]),
			KeyboardBinding(
				KeyboardActionId.instrumentCopy,
				KeyboardContext.instrumentTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_c,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Copy current instrument to the internal instrument buffer",
			true,
			"Instrument table only; allows the macOS translated Command-C shape and does not use the OS clipboard."),
			KeyboardBinding(
				KeyboardActionId.instrumentPaste,
				KeyboardContext.instrumentTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_v,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Paste current instrument from the internal instrument buffer",
			true,
			"Instrument table only; allows the macOS translated Command-V shape and does not use the OS clipboard."),
			KeyboardBinding(
				KeyboardActionId.instrumentDeleteConfirm,
				KeyboardContext.instrumentTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_d,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Delete current instrument after no-undo confirmation",
			true,
			"Instrument table only; allows the macOS translated Command-D shape and keeps deletion in InsValueTable."),
			KeyboardBinding(
				KeyboardActionId.instrumentSaveDialog,
				KeyboardContext.instrumentTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_s,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Open the current instrument save filename dialog",
			true,
			"Instrument table only; allows the macOS translated Command-S shape and keeps .cti saving in InsValueTable."),
			KeyboardBinding(
				KeyboardActionId.instrumentLoadDialog,
				KeyboardContext.instrumentTable,
			KeyboardBindingKeyModel.translatedKeyinfo,
			SDLK_l,
			KMOD_CTRL,
			KMOD_ALT,
			KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
			"Open the current instrument load dialog",
			true,
			"Instrument table only; allows the macOS translated Command-L shape and keeps .cti loading in InsValueTable."),
			KeyboardBinding(
				KeyboardActionId.waveSeekCurrentInstrumentWave,
				KeyboardContext.waveTable,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_g,
				0,
				KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.none),
				"Seek to the current instrument's wave program row",
				true,
				"Wave table only; separate from F6 note-column Ctrl-G."),
			KeyboardBinding(
				KeyboardActionId.waveSeekCurrentInstrumentWave,
				KeyboardContext.waveTable,
				KeyboardBindingKeyModel.translatedKeyinfo,
				SDLK_g,
				KMOD_CTRL,
				KMOD_SHIFT | KMOD_ALT | KMOD_GUI,
				KeyboardShortcutSemantics(KeyboardSemanticModifier.primary, KeyboardSemanticModifier.physicalControl),
				"Seek to the current instrument's wave program row",
				true,
				"Wave table only; separate from F6 note-column Ctrl-G.")
	] ~ APP_QUIT_COMMAND_BINDINGS ~
		APP_AUDIO_SETTINGS_BINDINGS ~
		FILE_DIALOG_BINDINGS ~
		SAVE_EXPORT_PLAIN_KEYPAD_BINDINGS ~
		WORKSPACE_NAVIGATION_BINDINGS ~
		EDITOR_UNDO_REDO_BINDINGS ~
		SEQUENCE_EDITOR_COMMAND_BINDINGS ~
		SEQUENCE_TRANSPOSE_BINDINGS ~
		SEQUENCE_SPLIT_BINDINGS ~
		SEQUENCE_INPUT_BINDINGS ~
		SEQUENCE_VALUE_INPUT_BINDINGS ~
		NOTE_INPUT_BINDINGS ~
		TRACK_INPUT_BINDINGS ~
		SEQUENCE_ROW_STRUCTURE_BINDINGS ~
		SEQUENCE_EXPAND_SHRINK_BINDINGS ~
		SEQUENCE_PLAY_ROW_BINDINGS ~
		SEQUENCE_DIALOG_BINDINGS ~
		SEQUENCE_ROW_CLIPBOARD_BINDINGS ~
		TRACK_ENTRY_LOOP_BINDINGS ~
		TRACK_ENTRY_STRUCTURAL_BINDINGS ~
		TRACK_ENTRY_CLIPBOARD_BINDINGS ~
		TRACK_ENTRY_TRANSPOSE_BINDINGS ~
		TRACK_ENTRY_SWAP_BINDINGS ~
		TRACK_ENTRY_NAVIGATION_BINDINGS ~
		GENERATED_TABLE_ROW_STRUCTURE_BINDINGS ~
		GENERATED_TABLE_ROW_SELECTION_BINDINGS ~
		INSTRUMENT_BYTE_SELECTION_BINDINGS ~
		TRACK_OVERVIEW_FOCUSED_BINDINGS ~
		TRACK_OVERVIEW_TIMELINE_BINDINGS ~
		TRACK_OVERVIEW_BLOCK_BINDINGS ~
		UI_WINDOW_SWITCHER_BINDINGS ~
		UI_TOP_LEVEL_BINDINGS ~
		UI_TOP_LEVEL_PLATFORM_BINDINGS ~
		CURSOR_STEP_INPUT_BINDINGS ~
		UI_GLOBAL_BINDINGS;

// Binding lookup and action resolution. For compact contextual display, the
// first implemented binding for an action is the canonical primary binding;
// later implemented bindings are aliases retained for input and detailed Help.

KeyboardBinding[] keyboardBindingMetadataInDisplayOrder() {
	KeyboardBinding[] bindings;
	foreach(binding; KEYBOARD_BINDING_METADATA)
		bindings ~= binding;
	return bindings;
}

private bool keyboardBindingMatchesKeyinfo(const KeyboardBinding binding,
										   Keyinfo key) {
	if(!keyboardRequiredModifiersMatch(key.mods, binding.requiredMods))
		return false;
	if((key.mods & binding.forbiddenMods) != 0)
		return false;

	final switch(binding.keyModel) {
		case KeyboardBindingKeyModel.translatedKeyinfo:
			if(binding.context == KeyboardContext.helpDialog &&
			   binding.actionId == KeyboardActionId.helpClose)
				return key.unicode == binding.key;
			if(key.key == binding.key)
				return true;
			return binding.context == KeyboardContext.workspaceNavigation &&
				keyboardWorkspaceNavigationPhysicalKeyMatches(binding, key);
		case KeyboardBindingKeyModel.translatedUnicode:
			return key.unicode == binding.key;
		case KeyboardBindingKeyModel.physicalLabelOnly:
			return false;
		}
	}

private bool keyboardWorkspaceNavigationPhysicalKeyMatches(
		const KeyboardBinding binding, Keyinfo key) {
	if(binding.context != KeyboardContext.workspaceNavigation)
		return false;
	if(key.scancode == 0)
		return false;
	int scancode = keyboardPhysicalScancodeForShortcutKey(binding.key);
	return scancode != 0 && key.scancode == scancode;
}

private int keyboardPhysicalScancodeForShortcutKey(int key) {
	switch(key) {
	case SDLK_1:
		return SDL_SCANCODE_1;
	case SDLK_2:
		return SDL_SCANCODE_2;
	case SDLK_3:
		return SDL_SCANCODE_3;
	case SDLK_4:
		return SDL_SCANCODE_4;
	case SDLK_5:
		return SDL_SCANCODE_5;
	case SDLK_6:
		return SDL_SCANCODE_6;
	case SDLK_7:
		return SDL_SCANCODE_7;
	case SDLK_8:
		return SDL_SCANCODE_8;
	case SDLK_9:
		return SDL_SCANCODE_9;
	case SDLK_d:
		return SDL_SCANCODE_D;
	case SDLK_f:
		return SDL_SCANCODE_F;
	case SDLK_i:
		return SDL_SCANCODE_I;
	case SDLK_m:
		return SDL_SCANCODE_M;
	case SDLK_p:
		return SDL_SCANCODE_P;
	case SDLK_s:
		return SDL_SCANCODE_S;
	case SDLK_t:
		return SDL_SCANCODE_T;
	case SDLK_v:
		return SDL_SCANCODE_V;
	case SDLK_w:
		return SDL_SCANCODE_W;
	default:
		return 0;
	}
}

private bool keyboardRequiredModifierGroupMatches(ref int remainingRequired,
											 int actualMods,
											 int groupMask) {
	if((remainingRequired & groupMask) != groupMask)
		return true;
	remainingRequired &= ~groupMask;
	return (actualMods & groupMask) != 0;
}

private bool keyboardRequiredModifiersMatch(int actualMods, int requiredMods) {
	int remainingRequired = requiredMods;
	if(!keyboardRequiredModifierGroupMatches(remainingRequired, actualMods,
			KMOD_CTRL))
		return false;
	if(!keyboardRequiredModifierGroupMatches(remainingRequired, actualMods,
			KMOD_SHIFT))
		return false;
	if(!keyboardRequiredModifierGroupMatches(remainingRequired, actualMods,
			KMOD_ALT))
		return false;
	if(!keyboardRequiredModifierGroupMatches(remainingRequired, actualMods,
			KMOD_GUI))
		return false;
	return (actualMods & remainingRequired) == remainingRequired;
}

bool resolveKeyboardAction(KeyboardContext context,
						   Keyinfo key,
						   out KeyboardActionId actionId) {
	foreach(binding; KEYBOARD_BINDING_METADATA) {
		if(!binding.implemented)
			continue;
		if(binding.context != context)
			continue;
		if(!keyboardBindingMatchesKeyinfo(binding, key))
			continue;
		actionId = binding.actionId;
		return true;
	}
	return false;
}

bool resolveGlobalKeyboardAction(Keyinfo key,
								 out KeyboardActionId actionId) {
	return resolveKeyboardAction(KeyboardContext.global, key, actionId);
}

bool resolveAppFileDialogKeyboardAction(Keyinfo key,
										out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	switch(actionId) {
	case KeyboardActionId.appAbout:
	case KeyboardActionId.appAudioSettings:
	case KeyboardActionId.fileLoadDialog:
	case KeyboardActionId.fileSaveExportDialog:
	case KeyboardActionId.fileQuickSave:
		return true;
	default:
		return false;
	}
}

bool resolveFileDialogKeyboardAction(Keyinfo key,
									 out KeyboardActionId actionId) {
	return resolveKeyboardAction(KeyboardContext.fileDialog, key, actionId);
}

bool resolveQuitConfirmKeyboardAction(Keyinfo key,
									  out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	return actionId == KeyboardActionId.appQuitConfirm;
}

bool resolveSongSpeedKeyboardAction(Keyinfo key,
									out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	switch(actionId) {
	case KeyboardActionId.songSpeedDecrease:
	case KeyboardActionId.songSpeedIncrease:
		return true;
	default:
		return false;
	}
}

bool resolveSongMultispeedKeyboardAction(Keyinfo key,
										 out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	switch(actionId) {
	case KeyboardActionId.songMultispeedDecrease:
	case KeyboardActionId.songMultispeedIncrease:
		return true;
	default:
		return false;
	}
}

bool resolveUiWindowSwitcherKeyboardAction(Keyinfo key,
		out KeyboardActionId actionId) {
	return resolveKeyboardAction(KeyboardContext.uiWindowSwitcher, key, actionId);
}

bool resolveUiTopLevelKeyboardAction(Keyinfo key,
		out KeyboardActionId actionId) {
	return resolveKeyboardAction(KeyboardContext.uiTopLevel, key, actionId);
}

bool resolveUiGlobalKeyboardAction(Keyinfo key,
		out KeyboardActionId actionId) {
	return resolveKeyboardAction(KeyboardContext.uiGlobal, key, actionId);
}

bool resolveCursorStepInputKeyboardAction(Keyinfo key,
		out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.cursorStepInput, key, actionId))
		return false;
	switch(actionId) {
	case KeyboardActionId.sequencerCursorStepDecrease:
	case KeyboardActionId.sequencerCursorStepIncrease:
		return true;
	default:
		return false;
	}
}

bool resolveDocumentedMaintenanceKeyboardAction(Keyinfo key,
											 out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	switch(actionId) {
	case KeyboardActionId.songSidModelToggle:
	case KeyboardActionId.songSidFilterPresetNext:
	case KeyboardActionId.songSidFilterPresetPrevious:
	case KeyboardActionId.uiVisualModeToggle:
		return true;
	default:
		return false;
	}
}

bool resolveSongKeyjamToggleKeyboardAction(Keyinfo key,
										   out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	return actionId == KeyboardActionId.songKeyjamToggle;
}

bool resolveUiHelpTextToggleKeyboardAction(Keyinfo key,
										   out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	return actionId == KeyboardActionId.uiToggleHelpText;
}

bool resolveSongClearSequencesKeyboardAction(Keyinfo key,
											 out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	return actionId == KeyboardActionId.songClearSequencesConfirm;
}

bool resolveSongOptimizeKeyboardAction(Keyinfo key,
									   out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	return actionId == KeyboardActionId.songOptimizeConfirm;
}

bool resolvePlaybackTransportKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	switch(actionId) {
	case KeyboardActionId.playbackPlayFromMark:
	case KeyboardActionId.playbackPlayFromMarkTracking:
	case KeyboardActionId.playbackPlayFromStart:
	case KeyboardActionId.playbackPlayFromStartTracking:
	case KeyboardActionId.playbackPlayFromCursor:
	case KeyboardActionId.playbackStop:
		return true;
	default:
		return false;
	}
}

bool resolveVoiceMuteKeyboardAction(Keyinfo key,
									out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.global, key, actionId))
		return false;
	switch(actionId) {
	case KeyboardActionId.voiceToggleMute1:
	case KeyboardActionId.voiceToggleMute2:
	case KeyboardActionId.voiceToggleMute3:
		return true;
	default:
		return false;
	}
}

bool resolveEditorUndoRedoKeyboardAction(Keyinfo key,
									 out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.editor, key, actionId))
		return false;
	switch(actionId) {
	case KeyboardActionId.editorUndo:
	case KeyboardActionId.editorRedo:
		return true;
	default:
		return false;
	}
}

bool resolveHelpDialogKeyboardAction(Keyinfo key,
									 out KeyboardActionId actionId) {
	return resolveKeyboardAction(KeyboardContext.helpDialog, key, actionId);
}

bool resolveSaveExportDialogKeyboardAction(Keyinfo key,
										   out KeyboardActionId actionId) {
	return resolveKeyboardAction(KeyboardContext.saveExportDialog, key, actionId);
}

bool workspaceNavigationKeyinfoFromTextComposition(const(char)[] text,
		int mods, out Keyinfo keyinfo) {
	if((mods & (KMOD_ALT | KMOD_MODE)) == 0)
		return false;
	if((mods & (KMOD_CTRL | KMOD_SHIFT | KMOD_GUI)) != 0)
		return false;
	if(text.length != 2)
		return false;
	if(cast(ubyte)text[0] != 0xCB || cast(ubyte)text[1] != 0x86)
		return false;
	keyinfo = Keyinfo(SDLK_i, KMOD_ALT, 'i', SDL_SCANCODE_I);
	return true;
}

bool resolveWorkspaceNavigationKeyboardAction(Keyinfo key,
											  out KeyboardActionId actionId) {
	if(!resolveKeyboardAction(KeyboardContext.workspaceNavigation, key, actionId))
		return false;
	switch(actionId) {
	case KeyboardActionId.sequencerViewTrackTable:
	case KeyboardActionId.sequencerViewSequenceEditor:
	case KeyboardActionId.sequencerViewTrackMap:
	case KeyboardActionId.workspaceActivateSequencer:
	case KeyboardActionId.workspaceActivateVoice1:
	case KeyboardActionId.workspaceActivateVoice2:
	case KeyboardActionId.workspaceActivateVoice3:
	case KeyboardActionId.workspaceActivateInstrument:
	case KeyboardActionId.workspaceActivateWave:
	case KeyboardActionId.workspaceActivatePulse:
	case KeyboardActionId.workspaceActivateFilter:
	case KeyboardActionId.workspaceActivateCommand:
	case KeyboardActionId.workspaceActivateChord:
	case KeyboardActionId.workspaceActivateTitle:
	case KeyboardActionId.workspaceActivateSpeed:
		return true;
	default:
		return false;
	}
}

			bool resolveSequencerKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
				if(!resolveKeyboardAction(KeyboardContext.sequencer, key, actionId))
					return false;
				switch(actionId) {
				case KeyboardActionId.sequencerViewTrackTable:
				case KeyboardActionId.sequencerViewTrackTableWithTrackList:
				case KeyboardActionId.sequencerViewSequenceEditor:
				case KeyboardActionId.sequencerViewTrackMap:
				case KeyboardActionId.sequencerViewToggleTrackSequence:
				case KeyboardActionId.sequencerNavigateVoicePrevious:
				case KeyboardActionId.sequencerNavigateVoiceNext:
				case KeyboardActionId.sequencerCursorStepSet:
				case KeyboardActionId.sequencerSubtunePrevious:
				case KeyboardActionId.sequencerSubtuneNext:
				case KeyboardActionId.sequencerOverviewNavigateUp:
				case KeyboardActionId.sequencerOverviewNavigateDown:
				case KeyboardActionId.sequencerOverviewNavigatePageUp:
				case KeyboardActionId.sequencerOverviewNavigatePageDown:
				case KeyboardActionId.sequencerOverviewNavigateHome:
				case KeyboardActionId.sequencerOverviewNavigateEnd:
				case KeyboardActionId.sequencerViewNavigateUp:
				case KeyboardActionId.sequencerViewNavigateDown:
				case KeyboardActionId.sequencerViewNavigatePageUp:
				case KeyboardActionId.sequencerViewNavigatePageDown:
				case KeyboardActionId.sequencerViewScrollUp:
				case KeyboardActionId.sequencerViewScrollDown:
				case KeyboardActionId.sequencerViewNavigateLargePageUp:
				case KeyboardActionId.sequencerViewNavigateLargePageDown:
				case KeyboardActionId.sequencerViewNavigateSongStart:
				case KeyboardActionId.sequencerViewNavigateSongEnd:
				case KeyboardActionId.sequencerDebugSequenceDialog:
				case KeyboardActionId.sequencerHighlightIncrease:
				case KeyboardActionId.sequencerHighlightDecrease:
				case KeyboardActionId.sequencerRowCountersToggle:
				case KeyboardActionId.sequencerRelativeNotesToggle:
				case KeyboardActionId.sequencerHighlightOffsetSet:
				case KeyboardActionId.sequencerPlaybackMarkSet:
				case KeyboardActionId.sequencerPlaybackMarkSetActiveVoice:
				case KeyboardActionId.sequencerPlaybackMarkJump:
				case KeyboardActionId.sequencerPlaybackMarkCenter:
				case KeyboardActionId.trackEntryLoopSetAllVoices:
					return true;
				default:
					return false;
				}
			}

		bool resolveSequencerCursorStepKeyboardAction(Keyinfo key,
				out KeyboardActionId actionId, out int value) {
			value = 0;
			if(!resolveSequencerKeyboardAction(key, actionId) ||
					actionId != KeyboardActionId.sequencerCursorStepSet)
				return false;
			value = key.key - SDLK_KP_1 + 1;
			return value >= 1 && value <= 9;
		}

		bool resolveSequenceEditorCommandKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
			if(!resolveKeyboardAction(KeyboardContext.sequenceEditor, key, actionId))
				return false;
			return actionId == KeyboardActionId.sequenceRowQuickExpand;
		}

		bool resolveInstrumentTableCommandKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.instrumentTable, key, actionId))
			return false;
		return actionId == KeyboardActionId.instrumentCopy ||
			actionId == KeyboardActionId.instrumentPaste ||
			actionId == KeyboardActionId.instrumentDeleteConfirm ||
			actionId == KeyboardActionId.instrumentSaveDialog ||
			actionId == KeyboardActionId.instrumentLoadDialog;
	}

		bool resolveInstrumentByteSelectionKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.instrumentTable, key, actionId))
			return false;
		return actionId == KeyboardActionId.instrumentByteSelectionExtendLeft ||
			actionId == KeyboardActionId.instrumentByteSelectionExtendRight;
	}

		bool resolveWaveTableCommandKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
			if(!resolveKeyboardAction(KeyboardContext.waveTable, key, actionId))
				return false;
			return actionId == KeyboardActionId.waveSeekCurrentInstrumentWave;
		}

		bool resolveSequenceTransposeKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
			if(!resolveKeyboardAction(KeyboardContext.sequenceEditor, key, actionId))
				return false;
			switch(actionId) {
			case KeyboardActionId.sequenceTransposeSemitoneUp:
			case KeyboardActionId.sequenceTransposeSemitoneDown:
			case KeyboardActionId.sequenceTransposeOctaveUp:
			case KeyboardActionId.sequenceTransposeOctaveDown:
				return true;
			default:
				return false;
			}
		}

	bool resolveSequenceSplitKeyboardAction(Keyinfo key,
			out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.sequenceEditor, key, actionId))
			return false;
		return actionId == KeyboardActionId.sequenceSplit;
	}

	bool resolveSequenceInputKeyboardAction(Keyinfo key,
			out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.sequenceInput, key, actionId))
			return false;
		switch(actionId) {
		case KeyboardActionId.sequenceInputOctaveDecrease:
		case KeyboardActionId.sequenceInputOctaveIncrease:
		case KeyboardActionId.sequenceInputToggleInstrumentAutoinsert:
			return true;
		default:
			return false;
		}
	}

	bool resolveSequenceValueInputKeyboardAction(Keyinfo key,
			out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.sequenceValueInput, key, actionId))
			return false;
		return actionId == KeyboardActionId.sequenceInputClear ||
			actionId == KeyboardActionId.sequenceInputReuseValue;
	}

	bool resolveNoteInputKeyboardAction(Keyinfo key,
			out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.noteInput, key, actionId))
			return false;
		switch(actionId) {
		case KeyboardActionId.sequenceInputGateOff:
		case KeyboardActionId.sequenceInputGateOn:
		case KeyboardActionId.sequenceInputClear:
		case KeyboardActionId.sequenceInputTie:
		case KeyboardActionId.sequenceInputGrabInstrument:
			return true;
		default:
			return false;
		}
	}

	bool resolveTrackInputKeyboardAction(Keyinfo key,
			out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.trackInput, key, actionId))
			return false;
		switch(actionId) {
		case KeyboardActionId.trackInputFindUnusedSequence:
		case KeyboardActionId.trackInputPreviousSequence:
		case KeyboardActionId.trackInputNextSequence:
		case KeyboardActionId.trackInputCommitValue:
			return true;
		default:
			return false;
		}
	}

		bool resolveSequenceRowStructureKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
			if(!resolveKeyboardAction(KeyboardContext.sequenceEditor, key, actionId))
				return false;
			switch(actionId) {
			case KeyboardActionId.sequenceRowDeleteSameLength:
			case KeyboardActionId.sequenceRowInsertSameLength:
			case KeyboardActionId.sequenceRowDeleteShrink:
			case KeyboardActionId.sequenceRowInsertGrow:
				return true;
			default:
				return false;
			}
		}

			bool resolveSequenceExpandShrinkKeyboardAction(Keyinfo key,
												out KeyboardActionId actionId) {
				if(!resolveKeyboardAction(KeyboardContext.sequenceEditor, key, actionId))
					return false;
				switch(actionId) {
			case KeyboardActionId.sequenceRowExpandSequence:
			case KeyboardActionId.sequenceRowShrinkSequence:
				return true;
			default:
					return false;
				}
			}

				bool resolveSequencePlayRowKeyboardAction(Keyinfo key,
													out KeyboardActionId actionId) {
					if(!resolveKeyboardAction(KeyboardContext.sequenceEditor, key, actionId))
						return false;
					return actionId == KeyboardActionId.sequencePlayRowAllVoices;
				}

				bool resolveSequenceDialogKeyboardAction(Keyinfo key,
													out KeyboardActionId actionId) {
					if(!resolveKeyboardAction(KeyboardContext.sequenceEditor, key, actionId))
						return false;
					switch(actionId) {
					case KeyboardActionId.sequenceOpenAppendDialog:
					case KeyboardActionId.sequenceOpenCopyDialog:
						return true;
					default:
						return false;
					}
				}
		
				bool resolveSequenceRowClipboardKeyboardAction(Keyinfo key,
													out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.sequenceEditor, key, actionId))
			return false;
		switch(actionId) {
		case KeyboardActionId.sequenceRowSelectionExtendUp:
		case KeyboardActionId.sequenceRowSelectionExtendDown:
		case KeyboardActionId.sequenceRowSelectionExtendPageUp:
		case KeyboardActionId.sequenceRowSelectionExtendPageDown:
		case KeyboardActionId.sequenceRowSelectionExtendHome:
		case KeyboardActionId.sequenceRowSelectionExtendEnd:
		case KeyboardActionId.sequenceRowSelectionClear:
		case KeyboardActionId.sequenceRowSelectPattern:
		case KeyboardActionId.sequenceRowCopy:
		case KeyboardActionId.sequenceRowPaste:
			return true;
		default:
			return false;
			}
			}

		bool resolveTrackEntryStructuralKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
			if(!resolveKeyboardAction(KeyboardContext.trackEntry, key, actionId))
				return false;
			switch(actionId) {
			case KeyboardActionId.trackEntryInsert:
			case KeyboardActionId.trackEntryInsertCopy:
			case KeyboardActionId.trackEntryDelete:
			case KeyboardActionId.trackEntryInsertToEnd:
			case KeyboardActionId.trackEntryDeleteToEnd:
			case KeyboardActionId.trackEntryInsertAllVoices:
			case KeyboardActionId.trackEntryDeleteAllVoices:
				return true;
			default:
				return false;
				}
			}

		bool resolveTrackEntryClipboardKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
			if(!resolveKeyboardAction(KeyboardContext.trackEntry, key, actionId))
				return false;
			switch(actionId) {
			case KeyboardActionId.trackEntryCopyPrompt:
			case KeyboardActionId.trackEntryPastePrompt:
			case KeyboardActionId.trackEntryPasteInsert:
			case KeyboardActionId.trackEntryPasteOverwrite:
				return true;
			default:
				return false;
			}
		}

		bool resolveTrackEntryLoopSetAllVoicesKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
			if(!resolveKeyboardAction(KeyboardContext.trackEntry, key, actionId))
				return false;
			return actionId == KeyboardActionId.trackEntryLoopSetAllVoices;
		}

		bool resolveTrackEntryLoopSetActiveVoiceKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
			if(!resolveKeyboardAction(KeyboardContext.trackEntry, key, actionId))
				return false;
			return actionId == KeyboardActionId.trackEntryLoopSetActiveVoice;
		}

		bool resolveTrackEntryTransposeKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
			if(!resolveKeyboardAction(KeyboardContext.trackEntry, key, actionId))
				return false;
			switch(actionId) {
			case KeyboardActionId.trackEntryTransposeUpFromCursor:
			case KeyboardActionId.trackEntryTransposeDownFromCursor:
				return true;
			default:
				return false;
			}
		}

			bool resolveTrackEntrySwapKeyboardAction(Keyinfo key,
										out KeyboardActionId actionId) {
				if(!resolveKeyboardAction(KeyboardContext.trackEntry, key, actionId))
					return false;
				switch(actionId) {
			case KeyboardActionId.trackEntrySwapWithVoice1:
			case KeyboardActionId.trackEntrySwapWithVoice2:
			case KeyboardActionId.trackEntrySwapWithVoice3:
				return true;
			default:
					return false;
				}
			}

			bool resolveTrackEntryNavigationKeyboardAction(Keyinfo key,
											out KeyboardActionId actionId) {
				if(!resolveKeyboardAction(KeyboardContext.trackEntry, key, actionId))
					return false;
				switch(actionId) {
				case KeyboardActionId.trackEntryNavigateStart:
				case KeyboardActionId.trackEntryNavigateEnd:
					return true;
				default:
					return false;
				}
			}

			bool resolveGeneratedTableRowStructureKeyboardAction(Keyinfo key,
												out KeyboardActionId actionId) {
				if(!resolveKeyboardAction(KeyboardContext.generatedTable, key, actionId))
					return false;
				switch(actionId) {
				case KeyboardActionId.generatedTableRowDelete:
				case KeyboardActionId.generatedTableRowInsert:
					return true;
				default:
					return false;
				}
			}

			bool resolveGeneratedTableRowSelectionKeyboardAction(Keyinfo key,
												out KeyboardActionId actionId) {
				if(!resolveKeyboardAction(KeyboardContext.generatedTable, key, actionId))
					return false;
				switch(actionId) {
				case KeyboardActionId.generatedTableRowSelectionExtendUp:
				case KeyboardActionId.generatedTableRowSelectionExtendDown:
				case KeyboardActionId.generatedTableRowSelectionExtendPageUp:
				case KeyboardActionId.generatedTableRowSelectionExtendPageDown:
				case KeyboardActionId.generatedTableRowSelectionExtendHome:
				case KeyboardActionId.generatedTableRowSelectionExtendEnd:
				case KeyboardActionId.generatedTableRowSelectionClear:
				case KeyboardActionId.generatedTableRowCopy:
				case KeyboardActionId.generatedTableRowPaste:
					return true;
				default:
					return false;
				}
			}

					bool resolveTrackOverviewFocusedKeyboardAction(Keyinfo key,
												out KeyboardActionId actionId) {
				if(!resolveKeyboardAction(KeyboardContext.trackOverview, key, actionId))
					return false;
		switch(actionId) {
		case KeyboardActionId.trackOverviewScrollLeft:
		case KeyboardActionId.trackOverviewScrollRight:
		case KeyboardActionId.trackOverviewUndo:
		case KeyboardActionId.trackOverviewRedo:
			return true;
		default:
			return false;
		}
	}

	bool resolveTrackOverviewTimelineKeyboardAction(Keyinfo key,
										out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.trackOverviewTimeline, key,
				actionId))
			return false;
		switch(actionId) {
		case KeyboardActionId.trackOverviewTimelineStepLeft:
		case KeyboardActionId.trackOverviewTimelineStepRight:
		case KeyboardActionId.trackOverviewTimelinePageUp:
		case KeyboardActionId.trackOverviewTimelinePageDown:
		case KeyboardActionId.trackOverviewTimelineLargePageUp:
		case KeyboardActionId.trackOverviewTimelineLargePageDown:
		case KeyboardActionId.trackOverviewTimelineHome:
		case KeyboardActionId.trackOverviewTimelineEnd:
			return true;
		default:
			return false;
		}
	}

	bool resolveTrackOverviewBlockKeyboardAction(Keyinfo key,
										out KeyboardActionId actionId) {
		if(!resolveKeyboardAction(KeyboardContext.trackOverviewBlock, key,
				actionId))
			return false;
		switch(actionId) {
		case KeyboardActionId.trackOverviewLoopAllVoices:
		case KeyboardActionId.trackOverviewLoopActiveVoice:
			case KeyboardActionId.trackOverviewCopyEntries:
			case KeyboardActionId.trackOverviewPasteEntries:
			case KeyboardActionId.trackOverviewFindUnusedSequence:
			case KeyboardActionId.trackOverviewInsertEntry:
		case KeyboardActionId.trackOverviewInsertCopyEntry:
		case KeyboardActionId.trackOverviewDeleteSelection:
		case KeyboardActionId.trackOverviewOpenActiveBlockInSequenceEditor:
		case KeyboardActionId.trackOverviewNavigatePreviousBlock:
		case KeyboardActionId.trackOverviewNavigateNextBlock:
			return true;
		default:
			return false;
		}
	}

// Current-platform label generation and compile-time metadata validation.

private void addKeyboardMetadataAuditIssue(ref KeyboardMetadataAuditIssue[] issues,
										   string code,
										   string message) {
	issues ~= KeyboardMetadataAuditIssue(code, message);
}

private bool isKeyboardActionStableIdWellFormed(string stableId) {
	if(stableId.length == 0)
		return false;
	foreach(ch; stableId) {
		if((ch >= 'a' && ch <= 'z') ||
		   (ch >= '0' && ch <= '9') ||
		   ch == '_' ||
		   ch == '.')
			continue;
		return false;
	}
	return true;
}

private string keyboardBindingAuditSignature(const KeyboardBinding binding) {
	return keyboardContextStableId(binding.context) ~ "|" ~
		to!string(cast(int)binding.keyModel) ~ "|" ~
		to!string(binding.key) ~ "|" ~
		to!string(binding.requiredMods) ~ "|" ~
		to!string(binding.forbiddenMods);
}

// KeyboardBinding has no stored scancode, alternate-binding, text-route, or
// platform-runtime-override field. Those runtime routes are represented as
// separate bindings; shortcut overrides are display-only. A physical-label
// placeholder is therefore non-runtime only when every stored dispatch field
// is inert.
bool keyboardBindingIsStrictNonRuntimePlaceholder(
		const KeyboardBinding binding) pure nothrow @safe @nogc {
	return !binding.implemented &&
		binding.keyModel == KeyboardBindingKeyModel.physicalLabelOnly &&
		binding.key == 0 &&
		binding.requiredMods == 0 &&
		binding.forbiddenMods == 0;
}

KeyboardMetadataAuditIssue[] auditKeyboardBindingRuntimeEquivalence(
		const KeyboardBinding[] bindings) {
	KeyboardMetadataAuditIssue[] issues;

	foreach(i, binding; bindings) {
		bool placeholder =
			keyboardBindingIsStrictNonRuntimePlaceholder(binding);
		if(!binding.implemented && !placeholder) {
			addKeyboardMetadataAuditIssue(
				issues,
				"keyboard_binding_inactive_runtime_data",
				"Inactive binding retains runtime dispatch data: " ~
				keyboardActionStableId(binding.actionId));
		}
		if(placeholder)
			continue;

		string signature = keyboardBindingAuditSignature(binding);
		foreach(j, other; bindings) {
			if(j <= i ||
			   keyboardBindingIsStrictNonRuntimePlaceholder(other))
				continue;
			if(keyboardBindingAuditSignature(other) == signature) {
				addKeyboardMetadataAuditIssue(
					issues,
					"keyboard_binding_duplicate",
					"Duplicate binding in context " ~
					keyboardContextStableId(binding.context) ~
					": " ~ keyboardActionStableId(binding.actionId) ~
					" and " ~ keyboardActionStableId(other.actionId));
			}
		}
	}

	return issues;
}

bool keyboardActionHasBindingMetadata(string stableId) {
	foreach(binding; KEYBOARD_BINDING_METADATA) {
		if(keyboardActionStableId(binding.actionId) == stableId)
			return true;
	}
	return false;
}

bool keyboardActionHasImplementedBindingMetadata(string stableId) {
	foreach(binding; KEYBOARD_BINDING_METADATA) {
		if(keyboardActionStableId(binding.actionId) == stableId &&
		   binding.implemented)
			return true;
	}
	return false;
}

string keyboardModifierDisplayLabel(int modifier) {
	if(modifier == KMOD_ALT)
		return keyboardSemanticModifierDisplayLabel(
			KeyboardSemanticModifier.alternate);
	return "";
}

private string keyboardSemanticModifierDisplayLabel(
		KeyboardSemanticModifier modifier) {
	final switch(modifier) {
	case KeyboardSemanticModifier.none:
		return "";
	case KeyboardSemanticModifier.primary:
		version(OSX) {
			return "Command";
		}
		else {
			return "Ctrl";
		}
	case KeyboardSemanticModifier.alternate:
		version(OSX) {
			return "Option";
		}
		else {
			return "Alt";
		}
	case KeyboardSemanticModifier.shift:
		return "Shift";
	case KeyboardSemanticModifier.physicalControl:
		version(OSX) {
			return "Control";
		}
		else {
			return "Ctrl";
		}
	}
}

private int keyboardBindingSemanticModifiers(const KeyboardBinding binding) {
	version(OSX) {
		if(binding.shortcut.macOSModifiersOverride !=
		   KEYBOARD_SAME_SEMANTIC_MODIFIERS)
			return binding.shortcut.macOSModifiersOverride;
	}
	return binding.shortcut.modifiers;
	}

private string keyboardBindingKeyDisplayLabel(const KeyboardBinding binding) {
	version(OSX) {
		if(binding.shortcut.macOSKeyLabelOverride.length > 0)
			return binding.shortcut.macOSKeyLabelOverride;
	}
	if(binding.shortcut.keyLabelOverride.length > 0)
		return binding.shortcut.keyLabelOverride;
	return keyboardKeyDisplayLabel(binding.key);
}

private string keyboardKeyDisplayLabel(int key) {
	switch(key) {
	case SDLK_0: return "0";
	case SDLK_1: return "1";
	case SDLK_2: return "2";
	case SDLK_3: return "3";
	case SDLK_4: return "4";
	case SDLK_5: return "5";
	case SDLK_6: return "6";
	case SDLK_7: return "7";
	case SDLK_8: return "8";
	case SDLK_9: return "9";
	case SDLK_a: return "A";
	case SDLK_c: return "C";
	case SDLK_d: return "D";
	case SDLK_e: return "E";
	case SDLK_f: return "F";
	case SDLK_g: return "G";
	case SDLK_h: return "H";
	case SDLK_i: return "I";
	case SDLK_l: return "L";
	case SDLK_m: return "M";
	case SDLK_n: return "N";
	case SDLK_o: return "O";
	case SDLK_p: return "P";
	case SDLK_q: return "Q";
	case SDLK_r: return "R";
	case SDLK_s: return "S";
	case SDLK_t: return "T";
	case SDLK_v: return "V";
	case SDLK_w: return "W";
	case SDLK_z: return "Z";
	case SDLK_BACKSPACE: return "Backspace";
	case SDLK_DELETE: return "Delete";
	case SDLK_DOWN: return "Down";
	case SDLK_END: return "End";
	case SDLK_ESCAPE: return "Esc";
	case SDLK_F1: return "F1";
	case SDLK_F2: return "F2";
	case SDLK_F3: return "F3";
	case SDLK_F4: return "F4";
	case SDLK_F5: return "F5";
	case SDLK_F6: return "F6";
	case SDLK_F7: return "F7";
	case SDLK_F8: return "F8";
	case SDLK_F9: return "F9";
	case SDLK_F10: return "F10";
	case SDLK_F11: return "F11";
	case SDLK_F12: return "F12";
	case SDLK_HOME: return "Home";
	case SDLK_INSERT: return "Insert";
	case SDLK_KP_0: return "Keypad 0";
	case SDLK_KP_1: return "Keypad 1";
	case SDLK_KP_2: return "Keypad 2";
	case SDLK_KP_3: return "Keypad 3";
	case SDLK_KP_DIVIDE: return "Keypad /";
	case SDLK_KP_MINUS: return "Keypad -";
	case SDLK_KP_MULTIPLY: return "Keypad *";
	case SDLK_KP_PERIOD: return "Keypad .";
	case SDLK_KP_PLUS: return "Keypad +";
	case SDLK_KP_ENTER: return "Keypad Enter";
	case SDLK_LEFT: return "Left";
	case SDLK_MINUS: return "-";
	case SDLK_PAGEDOWN: return "PgDn";
	case SDLK_PAGEUP: return "PgUp";
	case SDLK_PLUS: return "+";
	case SDLK_RETURN: return "Return";
	case SDLK_RIGHT: return "Right";
	case SDLK_SCROLLLOCK: return "Scroll Lock";
	case SDLK_SPACE: return "Space";
	case SDLK_TAB: return "Tab";
	case SDLK_UP: return "Up";
	case SDLK_EQUALS: return "=";
	default: return "";
	}
}

private void appendKeyboardShortcutLabelPart(ref string label, string part) {
	if(part.length == 0)
		return;
	if(label.length > 0)
		label ~= "-";
	label ~= part;
}

private string keyboardBindingDisplayLabel(const KeyboardBinding binding) {
	int modifiers = keyboardBindingSemanticModifiers(binding);
	string label;
	if((modifiers & KeyboardSemanticModifier.primary) != 0)
		appendKeyboardShortcutLabelPart(label,
			keyboardSemanticModifierDisplayLabel(
				KeyboardSemanticModifier.primary));
	if((modifiers & KeyboardSemanticModifier.physicalControl) != 0)
		appendKeyboardShortcutLabelPart(label,
			keyboardSemanticModifierDisplayLabel(
				KeyboardSemanticModifier.physicalControl));
	if((modifiers & KeyboardSemanticModifier.alternate) != 0)
		appendKeyboardShortcutLabelPart(label,
			keyboardSemanticModifierDisplayLabel(
				KeyboardSemanticModifier.alternate));
	if((modifiers & KeyboardSemanticModifier.shift) != 0)
		appendKeyboardShortcutLabelPart(label,
			keyboardSemanticModifierDisplayLabel(
				KeyboardSemanticModifier.shift));
	appendKeyboardShortcutLabelPart(label,
		keyboardBindingKeyDisplayLabel(binding));
	return label;
}

private bool keyboardShortcutLabelExists(string[] labels, string label) {
	foreach(existing; labels)
		if(existing == label)
			return true;
	return false;
}

string[] keyboardActionShortcutLabels(string stableId,
		string contextStableId = "") {
	string[] labels;
	foreach(binding; KEYBOARD_BINDING_METADATA) {
		if(!binding.implemented)
			continue;
		if(keyboardActionStableId(binding.actionId) != stableId)
			continue;
		if(contextStableId.length > 0 &&
		   keyboardContextStableId(binding.context) != contextStableId)
			continue;
		string label = keyboardBindingDisplayLabel(binding);
		if(label.length == 0 || keyboardShortcutLabelExists(labels, label))
			continue;
		labels ~= label;
	}
	return labels;
}

string keyboardActionShortcutLabelList(string stableId,
		string separator = " or ", string contextStableId = "") {
	string[] labels = keyboardActionShortcutLabels(stableId, contextStableId);
	string text;
	foreach(idx, label; labels) {
		if(idx > 0)
			text ~= separator;
		text ~= label;
	}
	return text;
}

string keyboardActionPrimaryShortcutLabel(string stableId,
		string contextStableId) {
	string[] labels = keyboardActionShortcutLabels(stableId, contextStableId);
	return labels.length ? labels[0] : "";
}

KeyboardHelpRow[] keyboardHelpRows(KeyboardHelpSection section) {
	KeyboardHelpRow[] rows;
	foreach(binding; KEYBOARD_BINDING_METADATA) {
		foreach(placement; binding.help) {
			if(placement.section != section)
				continue;
			rows ~= KeyboardHelpRow(placement.order, placement.description,
				[binding.actionId],
				keyboardContextStableId(binding.context));
		}
	}
	foreach(group; KEYBOARD_HELP_GROUPS) {
		if(group.section != section)
			continue;
		rows ~= KeyboardHelpRow(group.order, group.description,
			group.actionIds, group.contextStableId);
	}

	for(size_t i = 1; i < rows.length; i++) {
		KeyboardHelpRow row = rows[i];
		size_t insertAt = i;
		while(insertAt > 0 && rows[insertAt - 1].order > row.order) {
			rows[insertAt] = rows[insertAt - 1];
			insertAt--;
		}
		rows[insertAt] = row;
	}
	return rows;
}

string keyboardHelpRowShortcutLabel(const KeyboardHelpRow row,
		string separator = "/") {
	string[] labels;
	foreach(actionId; row.actionIds) {
		foreach(label; keyboardActionShortcutLabels(
				keyboardActionStableId(actionId), row.contextStableId)) {
			if(!keyboardShortcutLabelExists(labels, label))
				labels ~= label;
		}
	}

	string text;
	foreach(index, label; labels) {
		if(index > 0)
			text ~= separator;
		text ~= label;
	}
	return text;
}

string keyboardActionPrimaryShortcutLabel(string stableId) {
	string[] labels = keyboardActionShortcutLabels(stableId);
	return labels.length ? labels[0] : "";
}

string trackNextUnusedSequenceUnavailableMessage() {
	return "No unused sequence after current value.";
}

string trackNextUnusedSequenceChangedMessage(int sequenceNumber) {
	return format("Track sequence set to next unused %02X.", sequenceNumber);
}

KeyboardMetadataAuditIssue[] auditKeyboardBindingMetadata() {
	KeyboardMetadataAuditIssue[] issues;

	foreach(stableId; keyboardActionStableIdsInRegistry()) {
		if(!isKeyboardActionStableIdWellFormed(stableId)) {
			addKeyboardMetadataAuditIssue(
				issues,
				"keyboard_action_id_format",
				"Keyboard action id is not lower-case dotted/underscored: " ~ stableId);
		}
		if(!keyboardActionHasBindingMetadata(stableId)) {
			addKeyboardMetadataAuditIssue(
				issues,
				"keyboard_action_missing_binding",
				"Keyboard action has no binding metadata: " ~ stableId);
		}
	}

	foreach(i, binding; KEYBOARD_BINDING_METADATA) {
		string stableId = keyboardActionStableId(binding.actionId);
		if(keyboardBindingDisplayLabel(binding).length == 0) {
			addKeyboardMetadataAuditIssue(
				issues,
				"keyboard_binding_missing_display_label",
				"Binding cannot generate a display label: " ~ stableId);
		}
		if(binding.description.length == 0) {
			addKeyboardMetadataAuditIssue(
				issues,
				"keyboard_binding_missing_description",
				"Binding is missing a description: " ~ stableId);
		}
	}

	issues ~= auditKeyboardBindingRuntimeEquivalence(
		KEYBOARD_BINDING_METADATA);

	foreach(group; KEYBOARD_HELP_GROUPS) {
		if(group.description.length == 0 || group.actionIds.length == 0) {
			addKeyboardMetadataAuditIssue(issues,
				"keyboard_help_group_incomplete",
				"Keyboard Help group is missing actions or description.");
		}
		foreach(actionId; group.actionIds) {
			string stableId = keyboardActionStableId(actionId);
			if(!keyboardActionHasBindingMetadata(stableId)) {
				addKeyboardMetadataAuditIssue(issues,
					"keyboard_help_group_missing_binding",
					"Keyboard Help group action has no binding: " ~ stableId);
			}
		}
	}

	foreach(section; [KeyboardHelpSection.trackOverviewNavigation,
			KeyboardHelpSection.trackOverviewEdit,
			KeyboardHelpSection.trackOverviewDisplay,
			KeyboardHelpSection.mainApp,
			KeyboardHelpSection.mainPlayback,
			KeyboardHelpSection.mainSongBeforeClicks,
			KeyboardHelpSection.mainSongAfterClicks,
			KeyboardHelpSection.mainTableNavigation,
			KeyboardHelpSection.sequencerGeneralBeforeVoiceTab,
			KeyboardHelpSection.sequencerGeneralAfterVoiceTab,
			KeyboardHelpSection.sequencerViews,
			KeyboardHelpSection.sequencerNavigation,
			KeyboardHelpSection.sequenceEditingSequencer,
			KeyboardHelpSection.sequenceDialogs,
			KeyboardHelpSection.trackTableView,
			KeyboardHelpSection.trackMapView,
			KeyboardHelpSection.trackLoop,
			KeyboardHelpSection.globalUndoRedo,
			KeyboardHelpSection.sequencePlaybackMarkStart,
			KeyboardHelpSection.helpDialog,
			KeyboardHelpSection.sequenceRowClipboard,
			KeyboardHelpSection.mainInstrumentTable,
			KeyboardHelpSection.mainInstrumentSelection,
			KeyboardHelpSection.saveExport,
			KeyboardHelpSection.sequenceTranspose,
			KeyboardHelpSection.sequenceEditingInput,
			KeyboardHelpSection.noteColumn,
			KeyboardHelpSection.trackColumn,
			KeyboardHelpSection.trackColumnAdvanced,
			KeyboardHelpSection.sequenceRowPlatformEdit,
			KeyboardHelpSection.trackColumnPlatform,
			KeyboardHelpSection.waveTableHelp]) {
		KeyboardHelpRow[] rows = keyboardHelpRows(section);
		foreach(i, row; rows) {
			if(row.description.length == 0 || row.actionIds.length == 0) {
				addKeyboardMetadataAuditIssue(issues,
					"keyboard_help_incomplete",
					"Keyboard Help row is missing actions or description.");
			}
			if(keyboardHelpRowShortcutLabel(row).length == 0) {
				addKeyboardMetadataAuditIssue(issues,
					"keyboard_help_missing_label",
					"Keyboard Help row cannot generate a shortcut label.");
			}
			foreach(j, other; rows) {
				if(j <= i || other.order != row.order)
					continue;
				addKeyboardMetadataAuditIssue(issues,
					"keyboard_help_duplicate_order",
					"Keyboard Help rows share section " ~
					to!string(cast(int)section) ~ " order " ~
					to!string(row.order) ~ ".");
			}
		}
	}

	return issues;
}

static assert(auditKeyboardBindingMetadata().length == 0,
	"Canonical keyboard metadata audit failed.");

private bool hasOnlyShift(Keyinfo key) {
	return (key.mods & KMOD_SHIFT) != 0 &&
		(key.mods & (KMOD_CTRL | KMOD_ALT | KMOD_GUI)) == 0;
}

private bool hasNoModifiers(Keyinfo key) {
	return (key.mods & (KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI)) == 0;
}

string activeVoiceLoopTargetShortcutLabel() {
	return keyboardActionPrimaryShortcutLabel("track_entry.loop_set_active_voice");
}

bool isTrackEntryInsertShortcut(Keyinfo key) {
	version(OSX) {
		return hasOnlyShift(key) &&
			(key.raw == SDLK_INSERT || key.raw == SDLK_DELETE);
	}
	else {
		return key.raw == SDLK_INSERT;
	}
}

bool isTrackEntryInsertCopyShortcut(Keyinfo key) {
	version(OSX) {
		return hasOnlyShift(key) && key.raw == SDLK_BACKSPACE;
	}
	else {
		return false;
	}
}

bool isTrackEntryDeleteShortcut(Keyinfo key) {
	version(OSX) {
		return hasNoModifiers(key) &&
			(key.raw == SDLK_BACKSPACE || key.raw == SDLK_DELETE);
	}
	else {
		return key.raw == SDLK_DELETE;
	}
}

string trackEntrySetLoopTargetShortcutLabel() {
	return keyboardActionPrimaryShortcutLabel("track_entry.loop_set_all_voices");
}

// Input widgets and text/note-entry behavior. They consume resolved actions;
// they do not define a second keyboard registry.

class Cursor {
	enum BLINK_HALF_PERIOD_MS = 320;
	int x = -1, y = -1;
	private {
		Uint32 nextBlinkTick;
		int bg2, fg2;
		int bg, fg;
	}
	
	void set() { set(x,y); }
	alias set refresh;
  
	void set(int nx, int ny) {
		if(nx < 0 || ny < 0) return;
		if(x != nx || y != ny) {
			x = nx; y = ny;
			ushort col = screen.getChar(x, y);
			scheduleBlink();
			bg = fg2 = (col >> 8) & 15;
			fg = bg2 = (col >> 12) & 15;
		}
		screen.setColor(x,y,bg2,fg2);
	}

	void reset() {
		scheduleBlink();
		bg2 = fg;
		fg2 = bg;
	}

	void blink() {
		Uint32 now = SDL_GetTicks();
		if(nextBlinkTick == 0)
			scheduleBlink(now);
		if(cast(int)(now - nextBlinkTick) < 0)
			return;

		Uint32 steps = (now - nextBlinkTick) / BLINK_HALF_PERIOD_MS + 1;
		nextBlinkTick += steps * BLINK_HALF_PERIOD_MS;
		if((steps & 1) == 0)
			return;

		int t = bg2;
		bg2 = fg2;
		fg2 = t;
	}

	private void scheduleBlink() {
		scheduleBlink(SDL_GetTicks());
	}

	private void scheduleBlink(Uint32 now) {
		nextBlinkTick = now + BLINK_HALF_PERIOD_MS;
	}
}

class Input {
	mixin ValueChangedHandler;

	Cursor cursor;
	const int width;
	int x, y, nibble;
	alias x pointerX;
	alias y pointerY;
	alias width inputLength;
	ubyte[] inarray, outarray; 

	this(ubyte[] p, int len) {
		this(len);
		setOutput(p);
	}
	this(int len) {
		cursor = new Cursor();
		width = len;
		inarray.length = len;
	}

	void setOutput(ubyte[] p) {
		outarray = p;
	}

	void setCoord(int nx, int ny) {
		if(nx) x = nx;
		if(ny) y = ny;
	}
	alias setCoord set;

	int keypress(Keyinfo key) { return 0 ;}
	
	int keyrelease(Keyinfo key) { return 0; }

	void deactivate() {}

	int setValue(int v) { assert(0); }

	int step(int st) {
        nibble += st;
        if(nibble < 0) {
			nibble = inputLength - 1;
			return WRAP; // should return WRAPL
        }
        else if(nibble >= inputLength) {
			nibble = 0;
			return WRAP; 
        }
        return OK;
	}

	void update() { assert(0); }

	void refresh() { assert(0); }
	
	int toInt() {
		return toInt(inarray);
	}

	@property int value() {
		return toInt(inarray);
	}
	
	int toInt(ubyte[] ar) {
		int v;
		for(int i = cast(int)(ar.length-1), sh; i >= 0; i--) {
			v |= ar[i] << sh;
			sh += 4;
		}
		return v;
	}
	
	int toIntRange(int b, int e) {
		return toInt(inarray[b..e]);
	}

private:

	int valueKeyReader(Keyinfo key, char[] keytab) {
        foreach(i, k; keytab) {
			if(key.raw == k)
                return cast(int)i;
        }
        return -1;
	}

	int keypressStepHandler(Keyinfo key, char[] keytab) {
		int v = valueKeyReader(key, keytab);
		if(v >= 0) {
			int r = setValue(v);
			// if 'setValue' returns > 0, don't step
			if(r) return r;
			// if shift is pressed, don't step
			if(key.mods & KMOD_SHIFT) return OK;
			return step(1);
		}
		return OK;
	}
}

class InputValue : Input {
	this(ubyte[] p, int len) {
		super(p, len);
	}

	override void setOutput(ubyte[] p) {
		super.setOutput(p);
		// initialize value
		for(int i=0; i < inputLength; i++) {
			int j = i / 2;
			int sh = (i & 1) ? 0 : 4;
			inarray[i] = (p[j] >> sh) & 15;
		}
	}
	
	override int keypress(Keyinfo key) {
		int v;
		if(key.mods & KMOD_CTRL) return 0;
		if(key.raw == SDLK_RETURN)
			return RETURN;
		else if(key.raw == SDLK_ESCAPE)
			return CANCEL;
		return keypressStepHandler(key, cast(char[])"0123456789abcdef");
	}

	override int setValue(int v) {
		valueChanged();
		inarray[nibble] = cast(ubyte)v;
		int c = toInt();
		for(int i = cast(int)(inputLength/2-1); i >= 0; i--) {
			outarray[i] = c & 255;
			c >>= 8;
		}
		return OK;
	}
	
	override void update() {
		string fmt = std.string.format("0%dX",inputLength);
        screen.cprint(x, y, 1, -1, format("%" ~ fmt,toInt()));
		cursor.set(x + nibble, y);
	}
}

class InputByte : InputValue {
	this(ubyte[] p) {
		super(p, 2);
	}
}

class InputBoundedByte : InputValue {
	this(ubyte[] p) {
		super(p, 2);
	}

	override int keypress(Keyinfo key) {
		int v;
		if(key.mods & KMOD_CTRL) return 0;
		if(key.raw == SDLK_RETURN)
			return RETURN;
		else if(key.raw == SDLK_ESCAPE)
			return CANCEL;
		switch(key.raw)
		{
		case SDLK_LEFT:
			return step(-1);
		case SDLK_BACKSPACE:
			step(-1);
			setValue(0);
			return OK;
		case SDLK_RIGHT:
			return step(1);
		default:
			if(nibble < 2)
				return keypressStepHandler(key, cast(char[])"0123456789abcdef");
			return OK;
		}
	}
	
	override int step(int st) {
        nibble += st;
        if(nibble < 0) 
			nibble = 0;
        else if(nibble > 2) 
			nibble = 2;
        return OK;
	}

	override void update() {
		screen.cprint(x, y, 1, -1, format("%02X ", toInt()));
		cursor.set(x + nibble, y);
	}
	
}

class InputSingleChar : InputValue {
	string keys;
	int defaultKey;
	this(ubyte[] p, string keys, int defaultKey) {
		super(p, 2);
		this.keys = keys;
		setValue(0);
		this.defaultKey = defaultKey;
	}

	override int keypress(Keyinfo key) {
		auto v = keys.indexOf(key.raw);
		if(key.mods & KMOD_CTRL) return 0;
		else if(key.raw == SDLK_ESCAPE) {
			return CANCEL;
		}
		else if(key.raw == SDLK_RETURN) {
			setValue(cast(ubyte)defaultKey);
			return RETURN;
		}
		else if(v >= 0) {
			setValue(cast(ubyte)(v));
			return RETURN;
		}
		return IllegalValue;
	}
	
	override int step(int st) {
		return OK;
	}

	override void update() {
		screen.cprint(x + nibble, y, 1, -1, std.conv.to!string(keys[defaultKey]));
		cursor.set(x + nibble, y);
	}
}


class InputWord : InputValue {
	this(ubyte[] p) {
		super(p, 4);
	}
}

class InputTrack : InputWord {
	Track trk;
	ubyte[2] buf;
	private int lastHelpField = -1;
	this(RowData s, ValueChangedCallback cb) {
		super(buf);
		init(s);
 		trk.setValue(buf[0], buf[1]);
		valueChangedCallback = cb;
	}
	
	void init(RowData s) {
		trk = s.trk;
		buf[] = valueCheck(trk.trans, trk.number);
		super.setOutput(buf);
	}
	
	alias init refresh;

	void flush() {
		if(trk.number != buf[1] ||
		   trk.trans != buf[0]) {
			valueChanged();
			trk.setValue(buf[0], buf[1]);
		}
	}
	
	override int setValue(int v) {
		super.setValue(v);
		buf[] = valueCheckNoWrap(buf[0], buf[1]);
		super.setOutput(buf);
		trk.setValue(buf[0], buf[1]);
		return OK;
	}

	override int keypress(Keyinfo key) {
		if(key.mods & KMOD_ALT) return OK;
		KeyboardActionId actionId;
		if(resolveTrackInputKeyboardAction(key, actionId)) {
			switch(actionId) {
			case KeyboardActionId.trackInputFindUnusedSequence:
				findNextUnusedSequence();
				return OK;
			case KeyboardActionId.trackInputPreviousSequence:
				int i = buf[1] - 1;
				buf[] = valueCheck(buf[0], i);
				setOutput(buf);
				flush();
				return OK;
			case KeyboardActionId.trackInputNextSequence:
				int i = buf[1] + 1;
				buf[] = valueCheck(buf[0], i);
				setOutput(buf);
				flush();
				return OK;
			case KeyboardActionId.trackInputCommitValue:
				flush();
				return OK;
			default:
				break;
			}
		}
		switch(key.raw)
		{
		case SDLK_LEFT:
			if(--nibble < 0) {
				nibble = inputLength - 1;
				return WRAPL;
			}
			return OK;
		case SDLK_RIGHT:
			if(++nibble >= inputLength) {
				nibble = 0;
				return WRAPR;
			}
			return OK;
		default:
			break;
		}
		if(buf[0] < 0xc0) {
			int r = super.keypress(key);
			return r;
		}
		return OK;
	}

	override void update() {
		super.update();
		showTrackHelp();
	}

private:

	void showTrackHelp() {
		if(!state.displayHelp || UI.statusline is null)
			return;

		int field = nibble < 2 ? 0 : 1;
		if(field == lastHelpField && UI.statusline.counter != 0)
			return;

		UI.statusline.displayContextual(trackHelpText(field));
		lastHelpField = field;
	}

	string trackHelpText(int field) {
		string findUnusedLabel = keyboardActionPrimaryShortcutLabel(
			"track_input.find_unused_sequence", "track_input");
		string previousLabel = keyboardActionPrimaryShortcutLabel(
			"track_input.previous_sequence", "track_input");
		string nextLabel = keyboardActionPrimaryShortcutLabel(
			"track_input.next_sequence", "track_input");
		string commitLabel = keyboardActionPrimaryShortcutLabel(
			"track_input.commit_value", "track_input");
		assert(findUnusedLabel.length && previousLabel.length &&
			nextLabel.length && commitLabel.length);
		if(field == 0)
			return "Track byte: $80-$BF transpose/sequence entry.\n" ~
				"$C0-$FF LOOP/end marker target.\n" ~
				findUnusedLabel ~ " finds next unused sequence.";
		return "Sequence number for this track entry.\n" ~
			previousLabel ~ "/" ~ nextLabel ~
			" selects previous/next sequence.\n" ~
			commitLabel ~ " commits the current track value.";
	}

	void findNextUnusedSequence() {
		int s = song.getFreeSequence(buf[1] + 1);
		if(s <= 0) {
			if(UI.statusline !is null)
				UI.statusline.displayOperationFeedback(
					trackNextUnusedSequenceUnavailableMessage());
			return;
		}

		buf[] = valueCheck(buf[0], s);
		setOutput(buf);
		flush();
		if(UI.statusline !is null)
			UI.statusline.displayOperationFeedback(
				trackNextUnusedSequenceChangedMessage(s));
	}
	
	ubyte[] valueCheck(int tr, int no) {
		if(tr < 0x80) tr = 0x80;
		if(no < 0) no = 0;
		if(no > 0x80) no = 0x00; 
		if(no >= MAX_SEQ_NUM) no = MAX_SEQ_NUM-1;
		return cast(ubyte[])[tr,no];
	}

	// don't allow wrapmark
	ubyte[] valueCheckNoWrap(int tr, int no) {
		ubyte[] b = valueCheck(tr, no);
		if(b[0] > 0xbf) b[0] = 0xbf;
		return b;
	}
}

class InputString : Input {
	char[] instring;
	this(string s) { this(s, 80); }
	this(string s, int len) {
		super(len);
		setOutput(s);
	}

	override void setOutput(ubyte[] p) {
		assert(0);
	}
	
	void setOutput(string s) {
		int tl = cast(int)s.length;
		char[] str2 = std.utf.toUTF8(s.dup).dup;
		str2.length = inputLength;
		if(tl >= inputLength) tl = inputLength;
		str2[tl .. $] = ' ';
		instring = str2;
		nibble = stringLength;
		if(nibble >= inputLength)
			nibble = inputLength - 1;
	}
	
	override string toString() {
		return toString(false);
	}

	string toString(bool pad) {
		if(!pad)
			return cast(string)(instring[0..stringLength].dup);
		return cast(string)(instring);
	}

	override void update() {
		screen.cprint(x, y, 1, 0, toString(true));
		cursor.set(x + nibble, y);
	}

	void setChar(dchar value) {
		instring[nibble] = cast(char)value;
	}

	override int keypress(Keyinfo key) {
		int i;

		switch(key.raw)
		{
		case SDLK_LEFT:
			if(step(-1))
				nibble = 0;
			break;
		case SDLK_RIGHT:
			if(step(1))
				nibble = inputLength-1;
			break;
		case SDLK_BACKSPACE:
			if(step(-1)) {
				nibble = 0;
				break;
			}
			goto case SDLK_DELETE;
		case SDLK_DELETE:
			instring[nibble .. $-1] = instring[nibble+1 .. $].dup;
			instring[$-1] = ' ';
			break;
		// slightly bugs when str.length == inputLength
		case SDLK_HOME:
			nibble = 0;
			break;
		case SDLK_END:
			nibble = stringLength;
			if(nibble >= inputLength)
				nibble = inputLength - 1;
			break;
		case SDLK_RETURN:
			return RETURN;
		case SDLK_ESCAPE:
			return CANCEL;
		default:
			void insert() {
				instring[nibble+1 .. $] = instring[nibble .. $-1].dup;
			}
			if(key.raw == SDLK_INSERT) {
				insert();
				setChar(' ');
			}
			else if(key.unicode && key.unicode != '`') {
				string old = cast(string)(instring.dup);
				insert();
				setChar(key.unicode);
				try {
					validate(instring);
				}
				catch(UTFException e) {
					stderr.writeln(e.toString);
					instring = old.dup;
					break;
				}
				if(step(1) == WRAP) nibble = inputLength - 1;
			}
			break;
		}
		return OK;
	}

	@property int stringLength() {
		for(int i = inputLength - 1; i >= 0; i--) {
			if(instring[i] != ' ') 
				return i+1;
		}
		return 0;
	}
}

abstract class ExtendedInput : Input {
	protected {
		int nibble, memvalue;
		Element element;
		bool navigationEntryIncomplete;
	}
	int invalue;
	bool changed;

	this(ValueChangedCallback cb) {
		this(1, cb);
	}
	
	this(int w, ValueChangedCallback cb) {
		this.valueChangedCallback = cb;
		super(w);
	}
	

	override int step(int st) {
		nibble += st;
		if(nibble >= width) {
			nibble = width - 1;
			return WRAPR;
		}
		else if(nibble < 0) {
			nibble = 0;
			return WRAPL;
		}
		return OK;
	}

	override int keypress(Keyinfo key) {
		return keypress(key, "0123456789abcdef");
	}

	int keypress(Keyinfo key, string keytab) {
		if(key.mods & KMOD_CTRL || key.mods & KMOD_ALT)
			return OK;
		KeyboardActionId actionId;
		if(resolveSequenceValueInputKeyboardAction(key, actionId)) {
			switch(actionId) {
			case KeyboardActionId.sequenceInputReuseValue:
			if(memvalue >= 0) {
				resetNavigationEntryProgress();
				changed = (invalue != memvalue);
				invalue = memvalue;
				valueChanged();
				setRowValue(memvalue);
				return WRAP;
			}
				goto case KeyboardActionId.sequenceInputClear;
			case KeyboardActionId.sequenceInputClear:
				resetNavigationEntryProgress();
				valueChanged();
				clearRow();
				return WRAP;
			default:
				break;
			}
		}
		{
			if(keytab == null) return WRAP;
			int value = valueKeyReader(key, keytab);
			if(value < 0) {
				changed = false;
				return OK;
			}
			return valuekeyHandler(value);
		}
		//not reached
	}

	final bool navigationValueIsComplete() const {
		return !navigationEntryIncomplete;
	}

	final void resetNavigationEntryProgress() {
		navigationEntryIncomplete = false;
	}

protected:
	
	int valuekeyHandler(int value) {
		if(width == 2)
			navigationEntryIncomplete = nibble == 0;
		if(width == 1) invalue = value;
		else {
			if(nibble == 0) {
				invalue &= 0x0f;
				invalue |= value << 4;
			}
			else {
				invalue &= 0xf0;
				invalue |= value & 255;
			}
		}

		valueChanged();
		
		setRowValue(invalue);

		memvalue = invalue;
		if(++nibble >= width) {
			resetNavigationEntryProgress();
			nibble = 0;
			invalue = 0;
			return WRAP;
		}

		return OK;
	}

	final void clearRememberedValue() {
		memvalue = -1;
	}

	void clearRow() {
		resetNavigationEntryProgress();
		clearRememberedValue();
	}

	void setRowValue(int value) {
	}

	void setElement(Element e) {
		element = e;
	}

	override void update() {
		assert(0);
	}
	
	static int valueKeyReader(Keyinfo key,  const char[] keytab) {
        foreach(i, k; keytab) {
			if(key.raw == k) {
				if(key.mods & KMOD_SHIFT)
					return cast(int)(i | 0x80);
				return cast(int)i;
			}
        }
        return -1;
	}
}

class InputOctave : ExtendedInput {
	this(ValueChangedCallback cb) {
		super(1, cb);
	}
	
	override int keypress(Keyinfo key) {
		return super.keypress(key,"012345678");
	}	

	override void setRowValue(int value) {
		if(element.note.value >= 3) {
			int note = ((element.note.value + element.transpose) % 12) 
				+ value * 12 - element.transpose;
			if(note >= 3 && note < 0x5f)
				element.note = cast(ubyte)note;
		}
	}
}

class InputInstrument : ExtendedInput {
	this(ValueChangedCallback cb) {
		super(2, cb);
	}
	
	override void clearRow() {
		super.clearRow();
		element.instr = 0xc0;
		invalue = 0x30;
	}

	override void setElement(Element e) {
		super.setElement(e);
		if(e.instr.value < 0x30)
			invalue = e.instr.value;
		else invalue = 0;
	}

	override int keypress(Keyinfo key) {
		switch(key.unicode) {
		case SDLK_RETURN:
			if(element.instr.value < 0x30)
				mainui.activateInstrumentTable(element.instr.value);
			break;
		default:
			break;
		}
		return super.keypress(key);
	}

	override void setRowValue(int v) {
		element.instr = cast(ubyte)v;
		UI.activateInstrument(v);
	}
}

class InputCmd : ExtendedInput {
	this(ValueChangedCallback cb) {
		super(2, cb);
	}
	
	override void clearRow() {
		super.clearRow();
		element.cmd = 0;
	}

	override void setElement(Element e) {
		super.setElement(e);
		invalue = e.cmd.rawValue;
	}

	override void setRowValue(int v) {
		element.cmd = cast(ubyte)v;
	}
}

class InputNote : ExtendedInput {
	InputKeyjam keyjam;
	private bool noteStarted = false;
	private int activeNoteUnicode = 0;
	private int activeNoteScancode = 0;
	private int activeNoteGeneration = 0;

	this(ValueChangedCallback cb) {
		super(1, cb);
		keyjam = new InputKeyjam();
	}

	override int keyrelease(Keyinfo key) {
		import audio.player;
		if(!activeNoteKeyMatches(key) ||
				audio.player.getPlaystatus() == Status.Play)
			return OK;
		int generation = activeNoteGeneration;
		clearActiveNoteOwnership();
		audio.player.requestF6AuditionRelease(generation);
		return OK;
	}
	
	override int keypress(Keyinfo key) {
		KeyboardActionId actionId;
		if(resolveNoteInputKeyboardAction(key, actionId)) {
			switch(actionId) {
			case KeyboardActionId.sequenceInputGrabInstrument:
				if(element.instr.value < 0x30)
					UI.activateInstrument(element.instr.value);
				return OK;
			case KeyboardActionId.sequenceInputTie:
				if(element.note.value >= 3 && element.note.value < 0x5f) {
					valueChanged();
					element.note.setTied(!element.note.isTied());
				}
				return WRAP;
			case KeyboardActionId.sequenceInputClear:
				valueChanged();
				clearRow();
				return WRAP;
			case KeyboardActionId.sequenceInputGateOff:
				return completeNoteEntry(key, valuekeyHandler(0));
			case KeyboardActionId.sequenceInputGateOn:
				return completeNoteEntry(key, valuekeyHandler(2));
			default:
				break;
			}
		}

		if(key.mods & KMOD_CTRL || key.mods & KMOD_ALT) {
			return OK;
		}

		switch(key.unicode) {
		case SDLK_RETURN:
			if(element.instr.value < 0x30)
				UI.activateInstrument(element.instr.value);
			break;
		default:
			break;
		}
		
		return completeNoteEntry(key,
			super.keypress(key,"1!azsxdcvgbhnjmq2w3er5t6y7ui9o0p"));
	}

	private int completeNoteEntry(Keyinfo key, int result) {
		// r will be > 0 (in 'wrap') if valid data was entered
		if(result) {
			keyjam.element.transpose = element.transpose;
			if(element.note.value >= 3) {
				audio.player.prepareF6AuditionNoteOn(
					seq.sequencer.activeVoiceNum);
			}
			scope(exit) audio.player.cancelPreparedF6AuditionNoteOn();
			keyjam.keypress(key);

			if(element.note.value >= 3)
				rememberActiveNoteKey(key);
			else
				clearActiveNoteOwnership();
		}
		// no cache for notecolumn
		memvalue = -1;
		return result;
	}

	private bool activeNoteKeyMatches(Keyinfo key) {
		if(!noteStarted)
			return false;
		if(activeNoteScancode != 0 && key.scancode != 0)
			return activeNoteScancode == key.scancode;
		return activeNoteUnicode != 0 && activeNoteUnicode == key.unicode;
	}

	private void rememberActiveNoteKey(Keyinfo key) {
		noteStarted = true;
		activeNoteUnicode = key.unicode;
		activeNoteScancode = key.scancode;
		activeNoteGeneration = audio.player.currentF6AuditionGeneration();
	}

	private void clearActiveNoteOwnership() {
		noteStarted = false;
		activeNoteUnicode = 0;
		activeNoteScancode = 0;
		activeNoteGeneration = 0;
	}

	override void deactivate() {
		clearActiveNoteOwnership();
		audio.player.cancelF6AuditionForInputLoss();
	}

	override void clearRow() {
		super.clearRow();
		element.clear();
	}

	override void setRowValue(int value) {
		if(value < 0) return;
		switch(value) {
		case 0:
			element.note = NOTE_KEYOFF;
			element.note.setTied(false);
			element.instr = 0x80;
			break;
		case 2:
		case 0x80:
			element.note = NOTE_KEYON;
			element.note.setTied(false);
			element.instr = 0x80;
			break;
		default:
			int note = ((value - 3) & 0x7f) + 12 * state.octave - element.transpose;
			if(note > 0x5e) break;
			element.note = cast(ubyte)note;
			if(state.autoinsertInstrument && value < 0x80) {
				if(state.activeInstrument >= 0)
					element.instr = cast(ubyte)(state.activeInstrument);
				else element.instr = 0x80;
			}
			if(value >= 0x80) {
				element.note.setTied(true);
			}
			else element.note.setTied(false);
			break;
		}
	}
	
	override int step(int st) {
		if(st >= 0) return WRAPR;
		return WRAPL;
	}
}

class InputKeyjam : ExtendedInput {
	ubyte[4] dummy;

	this() {
		element = Element(dummy);
		super(1, null);
	}

	override void setRowValue(int value) {
		if(value < 0) return;
		switch(value) {
		case 0:
			element.note = NOTE_KEYOFF;
			element.note.setTied(false);
			break;
		case 2:
		case 0x80:
			element.note = NOTE_KEYON;
			break;
		default:
			int note = ((value - 3) & 0x7f) + 12 * state.octave;
			if(note > 0x5e) return;
			element.note = cast(ubyte)note;
			if(value >= 0x80) {
				element.note.setTied(true);
			}
			else element.note.setTied(false);

			break;
		}
		if(state.activeInstrument >= 0)
			element.instr = cast(ubyte)(state.activeInstrument);
		audio.player.playNote(element);
	}
	
	override int keypress(Keyinfo key) {
		return super.keypress(key,"1!azsxdcvgbhnjmq2w3er5t6y7ui9o0p");
	}

	override int keyrelease(Keyinfo key) {
		return OK;
	}
}

	final class InputSeq : ExtendedInput, Undoable {
		Element element;
		private {
			ExtendedInput inputNote, inputInstrument, inputCmd, inputOctave;
			int lastHelpColumn = -1;
		}
		ExtendedInput[] inputters;
		ExtendedInput activeInput;
		int activeInputNo;
	alias activeInputNo activeColumn;
	enum noteColumn = 0;
	enum octaveColumn = 1;
	enum instrumentColumn = 2;
	enum commandColumn = 3;
	enum columns = 3;
	
	this() {
		super(1, null);
		inputNote = new InputNote(&valueChanged);
		inputInstrument = new InputInstrument(&valueChanged);
		inputCmd = new InputCmd(&valueChanged);
		inputOctave = new InputOctave(&valueChanged);
		activeInput = inputNote;
		inputters = [inputNote, inputOctave, inputInstrument, inputCmd];
	}

	void setPointer(int x, int y) {
		if(x >0)
			pointerX = x;
		if(y > 0)
			pointerY = y;
	}

	override void setCoord(int x, int y) {
		setPointer(x, y);
	}

	override void setElement(Element e) {
		bool elementChanged = element.data.ptr != e.data.ptr ||
			element.data.length != e.data.length;
		element = e;
		foreach(input; inputters)
			input.setElement(e);
		if(elementChanged)
			clearNavigationEntryProgress();
	}

	void clearSongLocalInputMemory() {
		inputInstrument.clearRememberedValue();
		inputCmd.clearRememberedValue();
		clearNavigationEntryProgress();
	}

	void clearNavigationEntryProgress() {
		inputInstrument.resetNavigationEntryProgress();
		inputCmd.resetNavigationEntryProgress();
	}

	@property int currentNavigationColumn() const {
		return activeInputNo;
	}

	bool currentNavigationValueIsComplete() const {
		if(activeInputNo == instrumentColumn)
			return inputInstrument.navigationValueIsComplete();
		if(activeInputNo == commandColumn)
			return inputCmd.navigationValueIsComplete();
		return true;
	}

	bool currentInstrumentNavigationValue(out int value) {
		value = 0;
		if(activeInputNo != instrumentColumn || !element.instr.hasValue)
			return false;
		value = element.instr.value;
		return true;
	}

	ubyte currentCommandNavigationValue() {
		return element.cmd.rawValue;
	}

	override int keyrelease(Keyinfo key) {
		return activeInput.keyrelease(key);
	}

	override void deactivate() {
		foreach(input; inputters)
			input.deactivate();
	}

	override int keypress(Keyinfo key) {
		KeyboardActionId actionId;
		if(resolveSequenceInputKeyboardAction(key, actionId)) {
			switch(actionId) {
		case KeyboardActionId.sequenceInputToggleInstrumentAutoinsert:
			state.autoinsertInstrument ^= 1;
			UI.statusline.displayOperationFeedback(
				state.autoinsertInstrument ?
					"Instrument autoinsert enabled." :
					"Instrument autoinsert disabled.");
			return OK;
		case KeyboardActionId.sequenceInputOctaveDecrease:
			state.octave = clamp(--state.octave, 0, 6);
			break;
		case KeyboardActionId.sequenceInputOctaveIncrease:
			state.octave = clamp(++state.octave, 0, 6);
			break;
		default:
			break;
			}
		}

		int r = activeInput.keypress(key); 

		return r;
	}

	void valueChanged() {
		UndoValue v;
		import std.typecons;
		v.array = UndoValue.Array(activeInput.element.data.dup,
								  element.data);

		com.session.insertUndo(this, v);
	}

	override protected final void undo(UndoValue entry) {
		ubyte[] data = entry.array.target;
		ubyte[] target = entry.array.source;
		target[] = data;
	}

	override protected final UndoValue createRedoState(UndoValue value) {
		value.array.target = value.array.source.dup;
		return value;
	}

	void columnReset(int foo) {
		clearNavigationEntryProgress();
		if(foo == 0) {
			inputInstrument.nibble = 0;
			inputCmd.nibble = 0;
			activeInputNo = 0;
			activeInput = inputNote;
		}
		else {
			inputInstrument.nibble = 1;
			inputCmd.nibble = 1;
			activeInputNo = 3;
			activeInput = inputCmd;
		}
	}

	// nibble arg is for END key
	void columnReset(int foo, int nibble) {
		clearNavigationEntryProgress();
		if(foo == 0) {
			inputInstrument.nibble = 0;
			inputCmd.nibble = 0;
			activeInputNo = 0;
			activeInput = inputNote;
		}
		else {
			inputInstrument.nibble = 1;
			inputCmd.nibble = nibble;
			activeInputNo = 3;
			activeInput = inputCmd;
		}
	}

	void clickAtDisplayOffset(int displayOffset) {
		clearNavigationEntryProgress();
		if(displayOffset < 0)
			displayOffset = 0;

		if(displayOffset <= 1) {
			activeInputNo = 0;
			activeInput = inputNote;
			inputNote.nibble = 0;
		}
		else if(displayOffset <= 3) {
			activeInputNo = 1;
			activeInput = inputOctave;
			inputOctave.nibble = 0;
		}
		else if(displayOffset <= 5) {
			activeInputNo = 2;
			activeInput = inputInstrument;
			inputInstrument.nibble = displayOffset <= 4 ? 0 : 1;
		}
		else {
			activeInputNo = 3;
			activeInput = inputCmd;
			inputCmd.nibble = displayOffset <= 7 ? 0 : 1;
		}

		activeInput.setElement(element);
	}

	override int step(int st) {
		clearNavigationEntryProgress();
		int r = activeInput.step(st);
		if(r == WRAPR) {
			foreach(inp; inputters) {
				inp.nibble = 0;
			}
			
			activeInputNo++;
			if(activeInputNo >= inputters.length) {
				activeInputNo = 0;
				activeInput = inputters[activeInputNo];
				return WRAPR;
			}
			activeInput = inputters[activeInputNo];
			activeInput.nibble = 0;
			
		}
		else if(r == WRAPL) {
			foreach(inp; inputters) {
				inp.nibble = inp.width - 1;
			}
			activeInputNo--;
			if(activeInputNo < 0) {
				activeInputNo = cast(int)(inputters.length - 1);
				activeInput = inputters[activeInputNo];

				return WRAPL;
			}
			activeInput.nibble = activeInput.width - 1;
			activeInput = inputters[activeInputNo];
		}
		return OK;
	}

			override void update() {
				screen.cprint(pointerX, pointerY, 1, -1, element.toPlainString());

				assert(activeInput == inputters[activeInputNo]);
				int xofs = [0, 2, 4, 7][activeInputNo];
				cursor.set(pointerX + xofs + activeInput.nibble, pointerY);
				showSequenceHelp();
			}

	private:

		void showSequenceHelp() {
			if(!state.displayHelp || UI.statusline is null)
				return;

			int column = sequenceHelpColumn();
			string help = sequenceHelpText(column);
			if(column == lastHelpColumn && UI.statusline.counter != 0 &&
			   UI.statusline.message == help)
				return;

			UI.statusline.displayContextual(help);
			lastHelpColumn = column;
		}

		int sequenceHelpColumn() {
			if(activeInputNo <= 1)
				return 0;
			if(activeInputNo == 2)
				return 1;
			return 2;
		}

		string sequenceHelpText(int column) {
			string noteClearLabel = keyboardActionPrimaryShortcutLabel(
				"sequence_input.clear", "note_input");
			string reuseLabel = keyboardActionShortcutLabelList(
				"sequence_input.reuse_value", "/");
			final switch(column) {
			case 0:
				string gateOffLabel = keyboardActionPrimaryShortcutLabel(
					"sequence_input.gate_off", "note_input");
				string gateOnLabel = keyboardActionPrimaryShortcutLabel(
					"sequence_input.gate_on", "note_input");
				string tieLabel = keyboardActionPrimaryShortcutLabel(
					"sequence_input.tie", "note_input");
				assert(gateOffLabel.length && gateOnLabel.length &&
					tieLabel.length && noteClearLabel.length);
				return "Note/action: notes; " ~ gateOffLabel ~
					" gate off; " ~ gateOnLabel ~ " gate on.\n" ~
					"Tie: " ~ tieLabel ~ "; clear: " ~ noteClearLabel ~ ".";
			case 1:
				return "Instrument: 00-2F; " ~ reuseLabel ~ " reuses; " ~
					keyboardActionShortcutLabelList(
						"sequence_input.clear", "/", "sequence_value_input") ~
					" clears.";
			case 2:
				return sequenceCommandHelpText(element.cmd.rawValue);
			}
		}

		string sequenceCommandHelpText(int cmd) {
			if(cmd == 0)
				return "Command/effect 00: no command; " ~
					keyboardActionShortcutLabelList(
						"sequence_input.reuse_value", "/") ~ " reuses; " ~
					keyboardActionShortcutLabelList(
						"sequence_input.clear", "/", "sequence_value_input") ~
					" clears.";
			auto reference = decodeSequenceCommandReference(cast(ubyte)cmd);
			final switch(reference.kind) {
			case SequenceCommandReferenceKind.none:
				break;
			case SequenceCommandReferenceKind.command:
				return format("Effect %02X: Command table entry $01-$3F.", cmd);
			case SequenceCommandReferenceKind.pulse:
				return format("Effect %02X: Pulse table program $00-$1F.", cmd);
			case SequenceCommandReferenceKind.filter:
				return format("Effect %02X: Filter table program $00-$1F.", cmd);
			case SequenceCommandReferenceKind.chord:
				return format("Effect %02X: Chord program $00-$1F.", cmd);
			}
			if(cmd < 0xb0)
				return format("Command/effect %02X: A0-AF = set attack 0-F.", cmd);
			if(cmd < 0xc0)
				return format("Command/effect %02X: B0-BF = set decay 0-F.", cmd);
			if(cmd < 0xd0)
				return format("Command/effect %02X: C0-CF = set sustain 0-F.", cmd);
			if(cmd < 0xe0)
				return format("Command/effect %02X: D0-DF = set release 0-F.", cmd);
			if(cmd < 0xf0)
				return format("Command/effect %02X: E0-EF = set SID master volume 0-F.", cmd);
			if(cmd == 0xf0)
				return "Command/effect F0: demo sync event marker.";
			if(cmd == 0xf1)
				return "Command/effect F1: use Chord row 00 shuffle timing.";
			return format("Effect %02X: fixed playback speed $2-$F.", cmd);
		}
	}

class InputSpecial : InputValue {
	this(ubyte[] p) {
		super(p, 5);
	}

	override void setOutput(ubyte[] p) {
	}
	
	override int setValue(int v) {
		valueChanged();
		inarray[nibble] = v & 15;
		return OK;
	}
	
	override void update() {
		static immutable offsets = [0, 2, 3, 5, 6];
        screen.cprint(x, y, 1, -1, format("%01X-%02X %02X",inarray[0],toInt(inarray[1..3]),toInt(inarray[3..5])));
		cursor.set(pointerX + offsets[nibble], pointerY);
	}
}
