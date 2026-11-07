// Song editor state and operations, ported from the original editor's
// pattern editing code. Independent of any UI toolkit: the front end maps
// keys and mouse input onto these calls and draws from the public state.
//
// Columns: 0 = row number, 1 = speed, then for each channel c
// 2 + c*5 + {0 note, 1 instrument, 2 volume, 3 effect, 4 effect value}.
#pragma once

#include <string>
#include <vector>

#include "model.h"

namespace gss {

constexpr int COLUMNS = 2 + CHANNELS * 5;  // 42, last column is 41

class SongEditor {
public:
	explicit SongEditor(Module& m);

	Module& module() { return *m_; }
	Song& song() { return m_->songs[song_cur]; }
	const Song& song() const { return m_->songs[song_cur]; }

	// --- state the front end reads and sets ---------------------------------
	int song_cur = 0;
	int row_cur = 0;
	int col_cur = 2;
	int col_cur_prev = -1;  // column to return to after Ctrl+G
	int row_view = 0;       // row the view is centered on
	int octave = 4;         // 1..8
	int auto_step = 1;      // 0..16
	int page_step = 16;
	int ins_cur = 0;        // current instrument, 0-based
	bool auto_number = false;  // note entry also sets the current instrument
	bool shift_down = false;   // extends the selection while moving
	bool reset_number = true;  // next digit starts a new number
	bool channel_mute[CHANNELS] = {};

	int sel_col_s = 2, sel_row_s = 0, sel_col_e = 2, sel_row_e = 0;
	int sel_width = 0, sel_height = 0;

	// Sound effects use channel 1 only: the columns of channels 2-8 are locked.
	int last_column() const { return song().effect ? 6 : COLUMNS - 1; }
	bool column_locked(int col) const { return col > last_column(); }
	void clamp_cursor();  // after the song or its sound effect flag changes

	bool undo_available() const { return undo_available_; }
	bool has_selection() const { return sel_width && sel_height; }
	int sel_col_min() const { return sel_col_s < sel_col_e ? sel_col_s : sel_col_e; }
	int sel_row_min() const { return sel_row_s < sel_row_e ? sel_row_s : sel_row_e; }
	bool in_selection(int row, int col) const;

	// --- song switching -----------------------------------------------------
	void change_song(int song);  // resets undo
	void clear_song(int song);   // SongClear: blank song, cursor home
	void reset_view();           // cursor home, no selection, no undo

	// --- cursor ---------------------------------------------------------------
	void move_cursor(int row, int col, bool relative);
	void move_row(int off);
	void move_col(int off);       // wraps 1..41
	void move_channel(int off);   // Tab / Shift+Tab
	void prev_marker();
	void next_marker();
	void center_view();
	void goto_row_column();       // Ctrl+G
	void return_from_row_column();  // Enter on the row number column

	// --- selection ------------------------------------------------------------
	void reset_selection();
	void start_selection(int col, int row);
	void update_selection();
	void set_channel_selection(bool channel, bool section);  // Ctrl+L, Ctrl+A
	void select_all_or_section();      // Ctrl+A cycling
	void select_channel_or_section();  // Ctrl+L cycling

	// --- undo -------------------------------------------------------------------
	void reset_undo() { undo_available_ = false; }
	void set_undo();
	void undo();  // single level, swaps with the current state (so it also redoes)

	// --- clipboard --------------------------------------------------------------
	void copy_cut(bool copy, bool cut, bool shift);
	void paste(bool shift, bool mix);
	bool clipboard_empty() const { return !copy_width_ || !copy_height_; }

	// --- edits --------------------------------------------------------------------
	// Note keys: semitone 0..28 from the current octave, or -1 for key off.
	// Returns the note value entered.
	int note_for_key(int semitone) const;
	void enter_note(int note);  // the caller previews the row before the cursor moves
	bool type_digit(int digit);  // in the current column; false if it does nothing there
	bool type_effect(char letter);
	bool delete_at_cursor();  // Delete key on a single cell
	void delete_shift();      // Backspace
	void insert_shift();      // Insert
	void toggle_marker();
	void set_loop_start() { song().loop_start = row_cur; }
	void set_length() { song().length = row_cur; }
	void change_measure(int delta);
	void change_auto_step(int delta);
	void change_octave(int delta);
	void toggle_mute(int chn, bool solo);

	void transpose(int semitones, bool block, bool whole_song, bool channel, int ins);
	void scale_volume(int percent, bool block, bool whole_song, bool channel, int ins);
	void replace_instrument(bool block, bool whole_song, bool channel, int from, int to);
	void expand_selection();
	void shrink_selection();

	// --- sections -----------------------------------------------------------------
	std::string section_name(int row) const;
	void set_section_name(int row, const std::string& name);
	struct SectionEntry {
		int row;
		std::string label;  // "0012: name"
	};
	std::vector<SectionEntry> section_list() const;

	// The instrument number in effect at (row, chn) and the volume, as the
	// original's row preview found them.
	Song preview_row(int row) const;               // SPCPlayRow
	Song preview_note(int note, int ins) const;    // SPCPlayNote

private:
	void delete_shift_column(int col, int row);
	void insert_shift_column(int col, int row);
	void transpose_area(int semitones, int song, int chn, int row, int width, int height, int ins);
	void scale_volume_area(int percent, int song, int chn, int row, int width, int height, int ins);
	void replace_instrument_area(int song, int chn, int row, int width, int height, int from, int to);
	void block_area(int& chn, int& row, int& width) const;
	NoteField& cell(int row, int chn) { return song().row_mut(row).chn[chn]; }

	Module* m_;

	bool undo_available_ = false;
	std::vector<Row> undo_rows_;
	int undo_row_ = 0, undo_col_ = 0;

	enum ColumnType { SPEED, INSTRUMENT, NOTE, EFFECT, VALUE };
	std::vector<uint8_t> copy_[COLUMNS];
	int copy_type_[COLUMNS] = {};
	int copy_width_ = 0, copy_height_ = 0;
};

}  // namespace gss
