#include "song_editor.h"

#include <cstdio>
#include <cstdlib>

namespace gss {

SongEditor::SongEditor(Module& m) : m_(&m) { start_selection(col_cur, row_cur); }

bool SongEditor::in_selection(int row, int col) const
{
	if (!sel_width || !sel_height) return false;
	const int selx = sel_col_min(), sely = sel_row_min();
	return row >= sely && row < sely + sel_height && col >= selx && col < selx + sel_width;
}

// --- song switching -----------------------------------------------------------

void SongEditor::change_song(int s)
{
	if (s < 0 || s >= MAX_SONGS) return;
	song_cur = s;
	reset_undo();
	clamp_cursor();
}

void SongEditor::clamp_cursor()
{
	// a cursor in a locked channel goes to the same field of channel 1
	if (col_cur > last_column()) move_cursor(row_cur, 2 + (col_cur - 2) % 5, false);
	if (!has_selection()) return;
	if (sel_col_s > last_column()) sel_col_s = last_column();
	if (sel_col_e > last_column()) sel_col_e = last_column();
	update_selection();
}

void SongEditor::clear_song(int s)
{
	m_->songs[s] = Song();
	reset_view();
}

void SongEditor::reset_view()
{
	row_cur = 0;
	col_cur = 2;
	col_cur_prev = -1;
	reset_number = true;
	reset_undo();
	reset_selection();
	start_selection(col_cur, row_cur);
	sel_width = 0;
	sel_height = 0;
	center_view();
}

// --- cursor -------------------------------------------------------------------------

void SongEditor::move_cursor(int row, int col, bool relative)
{
	if (relative) {
		row_cur += row;
		col_cur += col;
	} else {
		row_cur = row;
		col_cur = col;
	}

	// The original clamped only after extending the selection, which could
	// leave it on row -1. Clamp first.
	if (row_cur < 0) row_cur = 0;
	if (row_cur > MAX_ROWS - 1) row_cur = MAX_ROWS - 1;
	if (col_cur > last_column()) col_cur = last_column();

	reset_number = true;

	if (shift_down) {
		sel_col_e = col_cur;
		sel_row_e = row_cur;
		update_selection();
	} else {
		reset_selection();
		start_selection(col_cur, row_cur);
	}

	center_view();
}

void SongEditor::move_row(int off) { move_cursor(off, 0, true); }

void SongEditor::move_col(int off)
{
	int col = col_cur + off;
	if (col < 1) col = last_column();
	if (col > last_column()) col = 1;
	move_cursor(row_cur, col, false);
}

void SongEditor::move_channel(int off)
{
	if (song().effect) {  // only channel 1 is open
		move_cursor(row_cur, col_cur < 2 ? 2 : col_cur, false);
		return;
	}
	if (col_cur < 2) {
		move_cursor(row_cur, off < 0 ? 2 + 5 * 8 - 5 : 2, false);
		return;
	}
	int col = col_cur + (off < 0 ? -5 : 5);
	if (col < 2) col += 5 * 8;
	if (col >= 2 + 5 * 8) col -= 5 * 8;
	move_cursor(row_cur, col, false);
}

void SongEditor::prev_marker()
{
	int row = row_cur;
	while (row) {
		--row;
		if (song().row(row).marker) break;
	}
	move_cursor(row, col_cur, false);
}

void SongEditor::next_marker()
{
	int row = row_cur;
	while (row < MAX_ROWS - 1) {
		++row;
		if (song().row(row).marker) break;
		if (row == song().length) break;
	}
	move_cursor(row, col_cur, false);
}

void SongEditor::center_view()
{
	if (row_cur < 0) row_cur = 0;
	if (row_cur >= MAX_ROWS) row_cur = MAX_ROWS - 1;
	row_view = row_cur;
}

void SongEditor::goto_row_column()
{
	col_cur_prev = col_cur;
	move_cursor(row_cur, 0, false);
}

void SongEditor::return_from_row_column()
{
	if (col_cur != 0 || col_cur_prev < 0) return;
	move_cursor(row_cur, col_cur_prev, false);
	col_cur_prev = -1;
}

// --- selection ----------------------------------------------------------------------

void SongEditor::reset_selection()
{
	sel_width = 0;
	sel_height = 0;
}

void SongEditor::start_selection(int col, int row)
{
	if (col < 1) return;
	if (col > last_column()) col = last_column();
	sel_col_s = sel_col_e = col;
	sel_row_s = sel_row_e = row;
	update_selection();
}

void SongEditor::update_selection()
{
	sel_width = std::abs(sel_col_s - sel_col_e) + 1;
	sel_height = std::abs(sel_row_s - sel_row_e) + 1;
}

void SongEditor::set_channel_selection(bool channel, bool section)
{
	int from, to;

	if (section) {
		from = row_cur;
		to = row_cur + 1;
		while (from > 0) {
			if (song().row(from).marker) break;
			--from;
		}
		while (to < MAX_ROWS) {
			if (song().row(to).marker) break;
			++to;
		}
	} else {
		from = 0;
		to = MAX_ROWS;
	}

	if (channel) {
		if (col_cur < 1) return;
		if (col_cur == 1) {
			sel_col_s = sel_col_e = 1;
		} else {
			const int col = 2 + (col_cur - 2) / 5 * 5;
			sel_col_s = col;
			sel_col_e = col + 4;
		}
	} else {
		sel_col_s = 1;
		sel_col_e = last_column();
	}

	sel_row_s = from;
	sel_row_e = to - 1;
	update_selection();
}

void SongEditor::select_all_or_section() { set_channel_selection(false, sel_height <= 1 || sel_height == MAX_ROWS); }

void SongEditor::select_channel_or_section() { set_channel_selection(true, sel_height <= 1 || sel_height == MAX_ROWS); }

// --- undo -----------------------------------------------------------------------------

void SongEditor::set_undo()
{
	undo_rows_ = song().rows();
	undo_row_ = row_cur;
	undo_col_ = col_cur;
	undo_available_ = true;
}

void SongEditor::undo()
{
	if (!undo_available_) return;

	song().rows().swap(undo_rows_);

	const int r = row_cur, c = col_cur;
	row_cur = undo_row_;
	col_cur = undo_col_;
	undo_row_ = r;
	undo_col_ = c;

	center_view();
}

// --- clipboard ------------------------------------------------------------------------

void SongEditor::copy_cut(bool copy, bool cut, bool shift)
{
	if (copy) {
		copy_width_ = sel_width;
		copy_height_ = sel_height;
	}

	int col = sel_col_min();
	if (col < 1) return;

	Song& s = song();
	bool oneshot = true;

	for (int colc = 0; colc < sel_width && col < COLUMNS; ++colc) {
		int row = sel_row_min();
		int chn = 0, chncol = 0;

		if (copy) copy_[colc].assign(MAX_ROWS, 0);

		if (col == 1) {
			if (copy) copy_type_[colc] = SPEED;
		} else {
			chn = (col - 2) / 5;
			chncol = (col - 2) % 5;
			if (copy) {
				static const int types[5] = {NOTE, INSTRUMENT, VALUE, EFFECT, VALUE};
				copy_type_[colc] = types[chncol];
			}
		}

		for (int rowc = 0; rowc < sel_height && row < MAX_ROWS; ++rowc, ++row) {
			Row& r = s.row_mut(row);
			if (col == 1) {
				if (copy) copy_[colc][rowc] = (uint8_t)r.speed;
				if (cut) r.speed = 0;
			} else {
				NoteField& n = r.chn[chn];
				switch (chncol) {
				case 0: if (copy) copy_[colc][rowc] = n.note; if (cut) n.note = 0; break;
				case 1: if (copy) copy_[colc][rowc] = n.instrument; if (cut) n.instrument = 0; break;
				case 2: if (copy) copy_[colc][rowc] = n.volume; if (cut) n.volume = 255; break;
				case 3: if (copy) copy_[colc][rowc] = n.effect; if (cut) n.effect = 0; break;
				case 4: if (copy) copy_[colc][rowc] = n.value; if (cut) n.value = 255; break;
				}
			}
		}

		if (cut && shift) {
			int rowd = sel_row_min();
			int rows = rowd + sel_height;

			if (oneshot) {
				if (s.loop_start >= rows) s.loop_start -= sel_height;
				if (s.length < MAX_ROWS) s.length -= sel_height;
			}

			for (; rowd < MAX_ROWS; ++rows, ++rowd) {
				Row& d = s.row_mut(rowd);

				if (oneshot) {
					if (rows < MAX_ROWS) {
						d.marker = s.row(rows).marker;
						d.name = s.row(rows).name;
					} else {
						d.marker = false;
						d.name.clear();
					}
				}

				if (col == 1) {
					d.speed = rows < MAX_ROWS ? s.row(rows).speed : 0;
				} else {
					NoteField& n = d.chn[chn];
					if (rows < MAX_ROWS) {
						const NoteField m = s.row(rows).chn[chn];
						switch (chncol) {
						case 0: n.note = m.note; break;
						case 1: n.instrument = m.instrument; break;
						// LEGACY BUG: the original shifts the volume column into
						// the effect value field (legacy/src/UnitMain.cpp:1133).
						case 2: n.value = m.volume; break;
						case 3: n.effect = m.effect; break;
						case 4: n.value = m.value; break;
						}
					} else {
						switch (chncol) {
						case 0: n.note = 0; break;
						case 1: n.instrument = 0; break;
						case 2: n.volume = 255; break;
						case 3: n.effect = 0; break;
						case 4: n.value = 255; break;
						}
					}
				}
			}
		}

		++col;
		oneshot = false;
	}

	reset_selection();
}

void SongEditor::paste(bool shift, bool mix)
{
	if (!copy_width_ || !copy_height_ || !col_cur) return;

	Song& s = song();
	int col = col_cur;

	for (int colc = 0; colc < copy_width_; ++colc) {
		int row = row_cur;
		int chn = 0, chncol = 0;

		if (col > 1) {
			chn = (col - 2) / 5;
			chncol = (col - 2) % 5;
		}

		if (shift) {
			int rows = sel_row_min();
			int rowd = rows + copy_height_;
			int len = MAX_ROWS - rowd - 1;
			rows += len;
			rowd += len;

			for (; len >= 0; --rows, --rowd, --len) {
				if (col == 1) {
					s.row_mut(rowd).speed = s.row(rows).speed;
				} else {
					NoteField& n = s.row_mut(rowd).chn[chn];
					const NoteField m = s.row(rows).chn[chn];
					switch (chncol) {
					case 0: n.note = m.note; break;
					case 1: n.instrument = m.instrument; break;
					case 2: n.volume = m.volume; break;
					case 3: n.effect = m.effect; break;
					case 4: n.value = m.value; break;
					}
				}
			}
		}

		for (int rowc = 0; rowc < copy_height_; ++rowc) {
			const uint8_t v = copy_[colc][rowc];
			const int type = copy_type_[colc];
			Row& r = s.row_mut(row);

			if (col == 1) {
				if (type == SPEED && (!mix || !r.speed)) r.speed = v;
			} else {
				NoteField& n = r.chn[chn];
				switch (chncol) {
				case 0: if (type == NOTE && (!mix || !n.note)) n.note = v; break;
				case 1: if (type == INSTRUMENT && (!mix || !n.instrument)) n.instrument = v; break;
				case 2: if (type == VALUE && (!mix || n.volume == 255)) n.volume = v; break;
				case 3: if (type == EFFECT && (!mix || !n.effect)) n.effect = v; break;
				case 4: if (type == VALUE && (!mix || n.value == 255)) n.value = v; break;
				}
			}

			++row;
			if (row >= MAX_ROWS) break;
		}

		++col;
		if (col > last_column()) break;  // never into locked channels
	}
}

// --- edits ------------------------------------------------------------------------------

int SongEditor::note_for_key(int semitone) const
{
	if (semitone < 0) return 1;  // key off
	int note = semitone + octave * 12 + 2;
	if (note >= 2 + 12 * 8) note = 2 + 12 * 8 - 1;
	return note;
}

void SongEditor::enter_note(int note)
{
	const int chn = (col_cur - 2) / 5;
	set_undo();
	NoteField& n = cell(row_cur, chn);
	n.note = (uint8_t)note;
	if (auto_number && note > 1) n.instrument = (uint8_t)(ins_cur + 1);
}

bool SongEditor::type_digit(int num)
{
	if (col_cur == 0) {  // row number
		if (reset_number) {
			row_cur = 0;
			reset_number = false;
		}
		row_cur = (row_cur * 10 + num) % MAX_ROWS;
		center_view();
		return true;
	}

	auto two_digits = [&](auto get, auto set) {
		if (reset_number) {
			set_undo();
			set(num * 10);
			reset_number = false;
		} else {
			set(get() + num % 10);
			reset_number = true;
		}
	};

	if (col_cur == 1) {
		Row& r = song().row_mut(row_cur);
		two_digits([&] { return r.speed; }, [&](int v) { r.speed = v; });
		return true;
	}

	NoteField& n = cell(row_cur, (col_cur - 2) / 5);

	switch ((col_cur - 2) % 5) {
	case 1:  // instrument: digits roll through the two places
		if (reset_number) {
			set_undo();
			n.instrument = 0;
			reset_number = false;
		}
		n.instrument = (uint8_t)((n.instrument * 10 + num) % 100);
		if (n.instrument > 0) ins_cur = n.instrument - 1;
		return true;
	case 2:
		two_digits([&] { return (int)n.volume; }, [&](int v) { n.volume = (uint8_t)v; });
		return true;
	case 4:
		two_digits([&] { return (int)n.value; }, [&](int v) { n.value = (uint8_t)v; });
		return true;
	}
	return false;
}

bool SongEditor::type_effect(char letter)
{
	if (col_cur < 2 || (col_cur - 2) % 5 != 3) return false;
	if (letter < 'A' || letter > 'Z') return false;
	set_undo();
	NoteField& n = cell(row_cur, (col_cur - 2) / 5);
	n.effect = (uint8_t)letter;
	if (n.value == 255) n.value = 0;
	return true;
}

bool SongEditor::delete_at_cursor()
{
	if (col_cur == 0) return false;

	set_undo();

	if (col_cur == 1) {
		song().row_mut(row_cur).speed = 0;
	} else {
		NoteField& n = cell(row_cur, (col_cur - 2) / 5);
		switch ((col_cur - 2) % 5) {
		case 0:
			n.note = 0;
			n.instrument = 0;  // also deletes the instrument number
			break;
		case 1: n.instrument = 0; break;
		case 2: n.volume = 255; break;
		case 3:
			n.effect = 0;
			n.value = 255;
			break;
		case 4: n.value = 255; break;
		}
	}

	move_row(auto_step);
	return true;
}

void SongEditor::delete_shift_column(int col, int row)
{
	if (row < 1 || !col) return;
	Song& s = song();

	if (col == 1) {
		for (int rowc = row; rowc < MAX_ROWS; ++rowc) s.row_mut(rowc - 1).speed = s.row(rowc).speed;
		s.row_mut(MAX_ROWS - 1).speed = 0;
		return;
	}

	const int chn = (col - 2) / 5;
	const int f = (col - 2) % 5;

	for (int rowc = row; rowc < MAX_ROWS; ++rowc) {
		NoteField& n = s.row_mut(rowc - 1).chn[chn];
		const NoteField& m = s.row(rowc).chn[chn];
		switch (f) {
		case 0: n.note = m.note; break;
		case 1: n.instrument = m.instrument; break;
		case 2: n.volume = m.volume; break;
		case 3: n.effect = m.effect; break;
		case 4: n.value = m.value; break;
		}
	}

	NoteField& n = s.row_mut(MAX_ROWS - 1).chn[chn];
	switch (f) {
	case 0: n.note = 0; break;
	case 1: n.instrument = 0; break;
	case 2: n.volume = 255; break;
	case 3: n.effect = 0; break;
	case 4: n.value = 255; break;
	}
}

void SongEditor::insert_shift_column(int col, int row)
{
	if (!col || row >= MAX_ROWS) return;
	Song& s = song();

	if (col == 1) {
		for (int rowc = MAX_ROWS - 1; rowc > row; --rowc) s.row_mut(rowc).speed = s.row(rowc - 1).speed;
		s.row_mut(row).speed = 0;
		return;
	}

	const int chn = (col - 2) / 5;
	const int f = (col - 2) % 5;

	for (int rowc = MAX_ROWS - 1; rowc > row; --rowc) {
		NoteField& n = s.row_mut(rowc).chn[chn];
		const NoteField& m = s.row(rowc - 1).chn[chn];
		switch (f) {
		case 0: n.note = m.note; break;
		case 1: n.instrument = m.instrument; break;
		case 2: n.volume = m.volume; break;
		case 3: n.effect = m.effect; break;
		case 4: n.value = m.value; break;
		}
	}

	NoteField& n = s.row_mut(row).chn[chn];
	switch (f) {
	case 0: n.note = 0; break;
	case 1: n.instrument = 0; break;
	case 2: n.volume = 255; break;
	case 3: n.effect = 0; break;
	case 4: n.value = 255; break;
	}
}

void SongEditor::delete_shift()
{
	if (!col_cur) return;
	set_undo();
	if (col_cur < 2) {
		delete_shift_column(col_cur, row_cur);
	} else {
		const int col = 2 + (col_cur - 2) / 5 * 5;
		for (int i = 0; i < 5; ++i) delete_shift_column(col + i, row_cur);
	}
	move_row(-1);
}

void SongEditor::insert_shift()
{
	if (!col_cur) return;
	set_undo();
	if (col_cur == 1) {
		insert_shift_column(col_cur, row_cur);
	} else {
		const int col = 2 + (col_cur - 2) / 5 * 5;
		for (int i = 0; i < 5; ++i) insert_shift_column(col + i, row_cur);
	}
}

void SongEditor::toggle_marker()
{
	Row& r = song().row_mut(row_cur);
	r.marker = !r.marker;
}

void SongEditor::change_measure(int delta)
{
	Song& s = song();
	if (delta < 0 && s.measure > 2) --s.measure;
	if (delta > 0 && s.measure < 16) ++s.measure;
}

void SongEditor::change_auto_step(int delta)
{
	auto_step += delta < 0 ? -1 : 1;
	if (auto_step < 0) auto_step = 16;
	if (auto_step > 16) auto_step = 0;
}

void SongEditor::change_octave(int delta)
{
	octave += delta < 0 ? -1 : 1;
	if (octave < 1) octave = 8;
	if (octave > 8) octave = 1;
}

void SongEditor::toggle_mute(int chn, bool solo)
{
	if (chn < 0 || chn >= CHANNELS) return;

	if (!solo) {
		channel_mute[chn] = !channel_mute[chn];
		return;
	}

	int cnt = 0;
	for (bool m : channel_mute)
		if (m) ++cnt;

	if (cnt < 7 || channel_mute[chn]) {
		for (int i = 0; i < CHANNELS; ++i) channel_mute[i] = (i != chn);
	} else {
		for (bool& m : channel_mute) m = false;
	}
}

// --- area operations -------------------------------------------------------------------

void SongEditor::block_area(int& chn, int& row, int& width) const
{
	row = sel_row_min();
	const int col = sel_col_min();
	chn = (col - 2) / 5;
	width = (col + sel_width - 2 + 4) / 5 - chn;
	if (chn < 0) chn = 0;
	if (chn + width > CHANNELS) width = CHANNELS - chn;
}

void SongEditor::transpose_area(int semitones, int song, int chn, int row, int width, int height, int ins)
{
	for (int songc = 0; songc < MAX_SONGS; ++songc) {
		if (song >= 0 && songc != song) continue;
		Song& s = m_->songs[songc];
		if (!s.allocated()) continue;

		for (int chnc = chn; chnc < chn + width; ++chnc) {
			int ins_cur_area = -1;
			for (int rowc = row; rowc < row + height && rowc < MAX_ROWS; ++rowc) {
				NoteField& n = s.row_mut(rowc).chn[chnc];
				if (n.instrument) ins_cur_area = n.instrument;
				if (n.note > 1 && (!ins || ins_cur_area == ins)) {
					int note = n.note + semitones;
					if (note < 2) note = 2;
					if (note > 2 + 95) note = 2 + 95;
					n.note = (uint8_t)note;
				}
			}
		}
	}
}

void SongEditor::transpose(int semitones, bool block, bool whole_song, bool channel, int ins)
{
	if (!semitones) return;
	if (whole_song || channel || block) set_undo();

	if (block) {
		int chn, row, wdt;
		block_area(chn, row, wdt);
		transpose_area(semitones, song_cur, chn, row, wdt, sel_height, ins);
	} else {
		if (channel) whole_song = true;
		transpose_area(semitones, whole_song ? song_cur : -1, channel ? (col_cur - 2) / 5 : 0, 0, channel ? 1 : 8, MAX_ROWS, ins);
	}
}

void SongEditor::scale_volume_area(int percent, int song, int chn, int row, int width, int height, int ins)
{
	for (int songc = 0; songc < MAX_SONGS; ++songc) {
		if (song >= 0 && songc != song) continue;
		Song& s = m_->songs[songc];
		if (!s.allocated()) continue;

		for (int chnc = chn; chnc < chn + width; ++chnc) {
			int ins_cur_area = -1;
			for (int rowc = row; rowc < row + height && rowc < MAX_ROWS; ++rowc) {
				NoteField& n = s.row_mut(rowc).chn[chnc];
				if (n.instrument) ins_cur_area = n.instrument;
				if (n.volume != 255 && (!ins || ins_cur_area == ins)) {
					int vol = n.volume * percent / 100;
					if (vol < 0) vol = 0;
					if (vol > 99) vol = 99;
					n.volume = (uint8_t)vol;
				}
			}
		}
	}
}

void SongEditor::scale_volume(int percent, bool block, bool whole_song, bool channel, int ins)
{
	if (!percent) return;
	if (whole_song || channel || block) set_undo();

	if (block) {
		int chn, row, wdt;
		block_area(chn, row, wdt);
		scale_volume_area(percent, song_cur, chn, row, wdt, sel_height, ins);
	} else {
		if (channel) whole_song = true;
		scale_volume_area(percent, whole_song ? song_cur : -1, channel ? (col_cur - 2) / 5 : 0, 0, channel ? 1 : 8, MAX_ROWS, ins);
	}
}

void SongEditor::replace_instrument_area(int song, int chn, int row, int width, int height, int from, int to)
{
	for (int songc = 0; songc < MAX_SONGS; ++songc) {
		if (song >= 0 && songc != song) continue;
		Song& s = m_->songs[songc];
		if (!s.allocated()) continue;

		for (int chnc = chn; chnc < chn + width; ++chnc)
			for (int rowc = row; rowc < row + height && rowc < MAX_ROWS; ++rowc) {
				NoteField& n = s.row_mut(rowc).chn[chnc];
				if (n.instrument == from) n.instrument = (uint8_t)to;
			}
	}
}

void SongEditor::replace_instrument(bool block, bool whole_song, bool channel, int from, int to)
{
	if (whole_song || channel || block) set_undo();

	if (block) {
		int chn, row, wdt;
		block_area(chn, row, wdt);
		replace_instrument_area(song_cur, chn, row, wdt, sel_height, from, to);
	} else {
		if (channel) whole_song = true;
		replace_instrument_area(whole_song ? song_cur : -1, channel ? (col_cur - 2) / 5 : 0, 0, channel ? 1 : 8, MAX_ROWS, from, to);
	}
}

void SongEditor::expand_selection()
{
	if (sel_height < 2) return;

	set_undo();

	Song& s = song();
	row_cur = sel_row_min() + 1;
	const int col = sel_col_min();
	int row = row_cur;

	for (int rowc = 0; rowc < sel_height; ++rowc) {
		for (int colc = 0; colc < sel_width; ++colc) insert_shift_column(col + colc, row_cur);
		row_cur += 2;
	}

	// shift markers and labels too when the selection is not inside one channel
	if (col < 2 || ((sel_col_s - 2) / 5) != ((sel_col_e - 2) / 5)) {
		for (int rowc = 0; rowc < sel_height; ++rowc) {
			if (row < MAX_ROWS) {
				for (int rowcc = MAX_ROWS - 1; rowcc > row; --rowcc) {
					Row& d = s.row_mut(rowcc);
					d.marker = s.row(rowcc - 1).marker;
					d.name = s.row(rowcc - 1).name;
				}
				s.row_mut(row).marker = false;
				s.row_mut(row).name.clear();
			}
			row += 2;
		}
	}

	--row_cur;
	center_view();
	reset_selection();
}

void SongEditor::shrink_selection()
{
	if (sel_height < 2) return;

	set_undo();

	Song& s = song();
	row_cur = sel_row_min() + 2;
	const int col = sel_col_min();
	int row = row_cur;

	for (int rowc = 0; rowc < sel_height / 2; ++rowc) {
		for (int colc = 0; colc < sel_width; ++colc) delete_shift_column(col + colc, row_cur);
		++row_cur;
	}

	if (col < 2 || ((sel_col_s - 2) / 5) != ((sel_col_e - 2) / 5)) {
		for (int rowc = 0; rowc < sel_height / 2; ++rowc) {
			if (row > 0) {
				for (int rowcc = row; rowcc < MAX_ROWS; ++rowcc) {
					Row& d = s.row_mut(rowcc - 1);
					d.marker = s.row(rowcc).marker;
					d.name = s.row(rowcc).name;
				}
				s.row_mut(MAX_ROWS - 1).marker = false;
				s.row_mut(MAX_ROWS - 1).name.clear();
			}
			++row;
		}
	}

	row_cur -= 2;
	if (row_cur < 0) row_cur = 0;
}

// --- sections -------------------------------------------------------------------------

std::string SongEditor::section_name(int row) const
{
	while (row) {
		if (song().row(row).marker) break;
		--row;
	}
	return song().row(row).name;
}

void SongEditor::set_section_name(int row, const std::string& name)
{
	while (row) {
		if (song().row(row).marker) break;
		--row;
	}
	song().row_mut(row).name = name;
}

std::vector<SongEditor::SectionEntry> SongEditor::section_list() const
{
	std::vector<SectionEntry> list;
	const Song& s = song();
	if (!s.allocated()) return list;
	for (int row = 0; row < MAX_ROWS; ++row) {
		const Row& r = s.row(row);
		if (!r.name.empty() || r.marker) {
			char num[16];
			std::snprintf(num, sizeof(num), "%4.4d", row);
			list.push_back({row, std::string(num) + ": " + r.name});
		}
	}
	return list;
}

// --- previews -------------------------------------------------------------------------

Song SongEditor::preview_row(int start_row) const
{
	Song t = Song::zeroed();
	t.length = 2;
	t.loop_start = 1;
	t.row_mut(0).speed = 99;

	const Song& s = song();

	for (int chn = 0; chn < CHANNELS; ++chn) {
		if (channel_mute[chn]) continue;

		NoteField& n = t.row_mut(0).chn[chn];
		n.note = s.row(start_row).chn[chn].note;

		int ins = 1, vol = 99;
		bool find_ins = true, find_vol = true;

		for (int row = start_row; row >= 0; --row) {
			if (!find_ins && !find_vol) break;
			const NoteField& m = s.row(row).chn[chn];
			if (find_ins && m.instrument) {
				ins = m.instrument;
				find_ins = false;
			}
			if (find_vol && m.volume != 255) {
				vol = m.volume;
				find_vol = false;
			}
		}

		if (n.note > 1) n.instrument = (uint8_t)ins;
		n.volume = (uint8_t)vol;

		NoteField& next = t.row_mut(1).chn[chn];
		next.value = 255;
		next.volume = 255;
	}

	return t;
}

Song SongEditor::preview_note(int note, int ins) const
{
	Song t = Song::zeroed();
	t.length = 2;
	t.loop_start = 1;
	t.row_mut(0).speed = 99;

	NoteField& n = t.row_mut(0).chn[0];
	n.note = (uint8_t)note;
	n.instrument = (uint8_t)(ins + 1);
	n.volume = 99;

	int chn = (col_cur - 2) / 5;
	if (chn < 0) chn = 0;
	const Song& s = song();

	for (int row = row_cur; row >= 0; --row) {
		if (s.row(row).chn[chn].volume != 255) {
			n.volume = s.row(row).chn[chn].volume;
			break;
		}
	}

	NoteField& next = t.row_mut(1).chn[0];
	next.value = 255;
	next.volume = 255;

	return t;
}

}  // namespace gss
