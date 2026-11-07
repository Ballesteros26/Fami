// Song queries shared by the compiler, file I/O and the editor.
#pragma once

#include <string>
#include <vector>

#include "model.h"

namespace gss {

bool row_is_empty(const Song& s, int row, bool marker);
bool song_is_empty(const Song& s);  // rows 0..length-1, markers count
// A song slot in use: it has notes, a name of its own, or is a sound effect.
// (song_is_empty() only looks at notes, so a renamed song still counts as
// empty for export.)
bool song_used(const Song& s);
// The slot after the last song in use, where an import adds its songs;
// MAX_SONGS if there is none.
int song_append_slot(const Module& m);
// The song in use with this name, which an import of the same thing
// replaces; -1 if there is none, or the name is blank or "untitled".
int song_named(const Module& m, const std::string& name);
bool channel_is_empty(const Song& s, int chn);  // no notes in 0..length-1
int song_find_last_row(const Song& s);  // markers ignored, 0 if empty
void song_clean_up(Song& s);  // drop repeated instrument/volume values
int song_duration_seconds(const Song& s);
// A song's timeline as the compiler lays it out from start_row, in driver
// ticks (1/160 s): each row lasts its speed (the last set at or above it),
// and after the end it loops (with the default markers, on the empty row
// after the last).
class SongTiming {
public:
	SongTiming() = default;
	SongTiming(const Song& s, int start_row);

	bool valid() const { return start_row_ >= 0 && start_row_ < length_; }
	int start_row() const { return start_row_; }

	// The row playing ticks after the start, and how far into it; before
	// the start (ticks < 0), the start row and the negative ticks.
	void locate(double ticks, int& row, double& into) const;
	// When row, plus into ticks, plays: on the first pass that reaches it.
	double time_of(int row, double into) const;
	int speed(int row) const { return row >= 0 && row < length_ ? speed_[(size_t)row] : DEFAULT_SPEED; }

private:
	int start_row_ = 0, length_ = 0, loop_start_ = 0;
	std::vector<int> speed_;
	std::vector<double> at_;  // ticks from row 0 to each row, one pass
	double first_pass_ = 0;   // start_row to the end
	double loop_ = 0;         // one pass of the loop
};

// The row playing ticks driver ticks after playback started at start_row.
int song_play_row(const Song& s, int start_row, double ticks);

// Removes song i: the songs after it move up one slot and the last slot
// becomes an empty song.
void delete_song(Module& m, int i);

// Sound effects play from one channel: whether s may be marked as one, which
// needs every note in channel 1. On failure *error says why.
bool effect_channel_check(const Song& s, std::string* error = nullptr);

// Instrument slot moves. Every note in every song is renumbered so it keeps
// playing the same instrument. Slots are 0-based.
void swap_instruments(Module& m, int a, int b);
void move_instrument(Module& m, int from, int to);  // the slots in between shift

// How many notes, in every song, use instrument slot.
int instrument_uses(const Module& m, int slot);

// Removes instrument slot: the slots after it move up one and every note is
// renumbered to match; notes that used the removed instrument lose their
// instrument number. The last slot becomes empty.
void delete_instrument(Module& m, int slot);

}  // namespace gss
