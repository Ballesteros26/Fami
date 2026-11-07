#include "song.h"

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace gss {

const Row& Song::blank_row()
{
	static const Row row;
	return row;
}

Song Song::zeroed()
{
	Song s;
	s.length = 0;
	s.loop_start = 0;
	s.measure = 0;
	s.effect = false;
	s.compiled_size = 0;
	s.name.clear();
	s.allocate();
	for (int r = 0; r < MAX_ROWS; ++r)
		for (NoteField& n : s.rows_[r].chn) n = NoteField{0, 0, 0, 0, 0};
	return s;
}

bool row_is_empty(const Song& s, int row, bool marker)
{
	const Row& r = s.row(row);
	int sum = r.speed;

	if (marker && r.marker) ++sum;

	for (const NoteField& n : r.chn) {
		sum += n.note;
		sum += n.instrument;
		sum += (n.volume == 255 ? 0 : 1);
		sum += n.effect;
		sum += (n.value == 255 ? 0 : 1);
	}

	return sum == 0;
}

bool song_is_empty(const Song& s)
{
	if (!s.allocated()) return true;
	for (int row = 0; row < s.length; ++row)
		if (!row_is_empty(s, row, true)) return false;
	return true;
}

bool channel_is_empty(const Song& s, int chn)
{
	if (!s.allocated()) return true;
	for (int row = 0; row < s.length; ++row)
		if (s.row(row).chn[chn].note) return false;
	return true;
}

int song_find_last_row(const Song& s)
{
	if (!s.allocated()) return 0;
	for (int row = MAX_ROWS - 1; row >= 0; --row)
		if (!row_is_empty(s, row, false)) return row;
	return 0;
}

void song_clean_up(Song& s)
{
	if (!s.allocated()) return;

	const int song_length = song_find_last_row(s);

	for (int chn = 0; chn < CHANNELS; ++chn) {
		int prev_ins = -1;
		int prev_vol = -1;

		for (int row = 0; row < song_length; ++row) {
			NoteField& n = s.row_mut(row).chn[chn];

			if (n.instrument) {
				if (n.instrument != prev_ins) prev_ins = n.instrument;
				else n.instrument = 0;
			}

			if (n.volume != prev_vol) {
				if (n.volume != 255) prev_vol = n.volume;
			} else {
				n.volume = 255;
			}

			// set instrument and volume at the loop point, just in case
			if (row == s.loop_start && s.loop_start > 0) {
				if (!n.instrument && prev_ins > 0) n.instrument = prev_ins;
				if (prev_vol >= 0) n.volume = prev_vol;
			}
		}
	}
}

bool song_used(const Song& s) { return !song_is_empty(s) || s.effect || s.name != "untitled"; }

int song_append_slot(const Module& m)
{
	for (int i = MAX_SONGS - 1; i >= 0; --i)
		if (song_used(m.songs[i])) return i + 1;
	return 0;
}

int song_named(const Module& m, const std::string& name)
{
	if (name.empty() || name == Song().name) return -1;
	for (int i = 0; i < MAX_SONGS; ++i)
		if (song_used(m.songs[i]) && m.songs[i].name == name) return i;
	return -1;
}

int song_duration_seconds(const Song& s)
{
	const int length = song_find_last_row(s);
	int duration = 0;
	int speed = DEFAULT_SPEED;

	for (int row = 0; row < length; ++row) {
		if (s.row(row).speed) speed = s.row(row).speed;
		duration += speed;
	}

	if (!duration) return 0;
	if (duration < UPDATE_RATE_HZ) return 1;
	return duration / UPDATE_RATE_HZ;
}

SongTiming::SongTiming(const Song& s, int start_row) : start_row_(start_row)
{
	// the length and loop as Compiler::channel_compile sets them
	length_ = s.length;
	loop_start_ = s.loop_start;
	if (!loop_start_ && length_ == MAX_ROWS - 1) {
		length_ = song_find_last_row(s) + 2;
		loop_start_ = length_ - 1;
	}
	if (length_ > MAX_ROWS) length_ = MAX_ROWS;
	if (loop_start_ < 0 || loop_start_ >= length_) loop_start_ = 0;
	if (!valid()) return;

	speed_.resize((size_t)length_);
	at_.resize((size_t)length_ + 1);
	int sp = DEFAULT_SPEED;
	for (int row = 0; row < length_; ++row) {
		if (s.row(row).speed) sp = s.row(row).speed;
		speed_[(size_t)row] = sp;
		at_[(size_t)row + 1] = at_[(size_t)row] + sp;
	}
	first_pass_ = at_[(size_t)length_] - at_[(size_t)start_row_];
	loop_ = at_[(size_t)length_] - at_[(size_t)loop_start_];
}

void SongTiming::locate(double ticks, int& row, double& into) const
{
	row = start_row_;
	into = ticks;
	if (!valid() || ticks < 0) return;

	double from = at_[(size_t)start_row_];  // where the pass searched starts, from row 0
	if (ticks >= first_pass_) {
		ticks = std::fmod(ticks - first_pass_, loop_);
		from = at_[(size_t)loop_start_];
	}
	// the last row starting at or before from + ticks
	const double t = from + ticks;
	const auto it = std::upper_bound(at_.begin(), at_.end() - 1, t);
	row = std::clamp((int)(it - at_.begin()) - 1, 0, length_ - 1);
	into = t - at_[(size_t)row];
}

double SongTiming::time_of(int row, double into) const
{
	if (!valid()) return into;
	if (row >= start_row_ && row < length_) return at_[(size_t)row] - at_[(size_t)start_row_] + into;
	if (row >= loop_start_ && row < start_row_) return first_pass_ + at_[(size_t)row] - at_[(size_t)loop_start_] + into;
	// a row the song no longer plays: where the loop starts
	return loop_start_ >= start_row_ ? at_[(size_t)loop_start_] - at_[(size_t)start_row_] : first_pass_;
}

int song_play_row(const Song& s, int start_row, double ticks)
{
	const SongTiming timing(s, start_row);
	int row;
	double into;
	timing.locate(ticks, row, into);
	return row;
}

void delete_song(Module& m, int i)
{
	if (i < 0 || i >= MAX_SONGS) return;
	std::rotate(m.songs + i, m.songs + i + 1, m.songs + MAX_SONGS);
	m.songs[MAX_SONGS - 1] = Song();
}

bool effect_channel_check(const Song& s, std::string* error)
{
	bool has_notes[CHANNELS] = {};
	if (s.allocated())
		for (int row = 0; row < MAX_ROWS; ++row)
			for (int chn = 0; chn < CHANNELS; ++chn)
				if (s.row(row).chn[chn].note) has_notes[chn] = true;

	int count = 0, only = -1;
	for (int chn = 0; chn < CHANNELS; ++chn)
		if (has_notes[chn]) {
			++count;
			only = chn;
		}

	if (count > 1) {
		if (error)
			*error = "A sound effect can use only one channel, and this song has notes in " + std::to_string(count) + " channels.";
		return false;
	}
	if (count == 1 && only > 0) {
		if (error)
			*error = "A sound effect plays from channel 1. Move the notes in channel " + std::to_string(only + 1) + " to channel 1 first.";
		return false;
	}
	return true;
}

namespace {

// Rewrites the instrument number of every note in every song through map,
// indexed by instrument number (0, no instrument, maps to itself).
void renumber_instruments(Module& m, const uint8_t (&map)[256])
{
	for (Song& s : m.songs) {
		if (!s.allocated()) continue;
		for (Row& r : s.rows())
			for (NoteField& n : r.chn) n.instrument = map[n.instrument];
	}
}

void identity(uint8_t (&map)[256])
{
	for (int i = 0; i < 256; ++i) map[i] = (uint8_t)i;
}

}  // namespace

void swap_instruments(Module& m, int a, int b)
{
	if (a == b || a < 0 || b < 0 || a >= MAX_INSTRUMENTS || b >= MAX_INSTRUMENTS) return;
	std::swap(m.instruments[a], m.instruments[b]);

	uint8_t map[256];
	identity(map);
	map[a + 1] = (uint8_t)(b + 1);
	map[b + 1] = (uint8_t)(a + 1);
	renumber_instruments(m, map);
}

void move_instrument(Module& m, int from, int to)
{
	if (from == to || from < 0 || to < 0 || from >= MAX_INSTRUMENTS || to >= MAX_INSTRUMENTS) return;

	Instrument* ins = m.instruments;
	uint8_t map[256];
	identity(map);

	// slots are 0-based, note instrument numbers 1-based
	if (from < to) {
		std::rotate(ins + from, ins + from + 1, ins + to + 1);
		for (int slot = from + 1; slot <= to; ++slot) map[slot + 1] = (uint8_t)slot;  // each moves up one slot
	} else {
		std::rotate(ins + to, ins + from, ins + from + 1);
		for (int slot = to; slot < from; ++slot) map[slot + 1] = (uint8_t)(slot + 2);  // each moves down one slot
	}
	map[from + 1] = (uint8_t)(to + 1);
	renumber_instruments(m, map);
}

int instrument_uses(const Module& m, int slot)
{
	int count = 0;
	for (const Song& s : m.songs) {
		if (!s.allocated()) continue;
		for (int r = 0; r < MAX_ROWS; ++r)
			for (const NoteField& n : s.row(r).chn)
				if (n.instrument == slot + 1) ++count;
	}
	return count;
}

void delete_instrument(Module& m, int slot)
{
	if (slot < 0 || slot >= MAX_INSTRUMENTS) return;

	Instrument* ins = m.instruments;
	std::rotate(ins + slot, ins + slot + 1, ins + MAX_INSTRUMENTS);
	ins[MAX_INSTRUMENTS - 1] = Instrument();

	uint8_t map[256];
	identity(map);
	map[slot + 1] = 0;  // the removed instrument
	for (int n = slot + 2; n <= MAX_INSTRUMENTS; ++n) map[n] = (uint8_t)(n - 1);
	renumber_instruments(m, map);
}

}  // namespace gss
