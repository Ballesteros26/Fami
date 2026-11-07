// SongEditor tests: expected values follow the original editor's code.
#include <cstdio>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "gsm_io.h"
#include "song.h"
#include "song_editor.h"

static int failures = 0;
#define CHECK(c)                                                         \
	do {                                                                 \
		if (!(c)) {                                                      \
			std::printf("%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #c); \
			++failures;                                                  \
		}                                                                \
	} while (0)

using namespace gss;

// Every note's instrument, as (name, sample data), so a renumbering can be
// checked to keep each note on the same instrument.
static std::vector<std::pair<std::string, std::vector<int16_t>>> note_instruments(const Module& m)
{
	std::vector<std::pair<std::string, std::vector<int16_t>>> out;
	for (const Song& s : m.songs) {
		if (!s.allocated()) continue;
		for (int r = 0; r < MAX_ROWS; ++r)
			for (const NoteField& n : s.row(r).chn) {
				if (n.instrument < 1 || n.instrument > MAX_INSTRUMENTS) continue;
				const Instrument& ins = m.instruments[n.instrument - 1];
				out.push_back({ins.name, ins.source});
			}
	}
	return out;
}

static void test_instrument_moves(const char* project)
{
	auto m = std::make_unique<Module>();
	CHECK(load_module(project, *m));
	const auto before = note_instruments(*m);
	CHECK(before.size() > 10);

	const std::string tuba = m->instruments[4].name;
	move_instrument(*m, 4, 0);  // up: slots 0..3 shift down one
	CHECK(m->instruments[0].name == tuba);
	CHECK(note_instruments(*m) == before);

	const std::string first = m->instruments[0].name;
	move_instrument(*m, 0, 9);  // down: slots 1..9 shift up one
	CHECK(m->instruments[9].name == first);
	CHECK(note_instruments(*m) == before);

	swap_instruments(*m, 1, 13);
	CHECK(note_instruments(*m) == before);

	int sources = 0;
	for (const Instrument& ins : m->instruments)
		if (ins.has_source()) ++sources;
	CHECK(sources == 7);  // test_features has seven samples; none lost or duplicated
}

static void test_sound_effect_channels()
{
	auto m = std::make_unique<Module>();
	SongEditor ed(*m);
	Song& s = m->songs[0];
	std::string error;

	CHECK(effect_channel_check(s, &error));  // empty
	s.row_mut(3).chn[0].note = 50;
	CHECK(effect_channel_check(s, &error));  // channel 1 only
	s.row_mut(5).chn[1].note = 50;
	CHECK(!effect_channel_check(s, &error));  // channels 1 and 2
	CHECK(error.find("2 channels") != std::string::npos);
	s.row_mut(3).chn[0].note = 0;
	CHECK(!effect_channel_check(s, &error));  // channel 2 only
	CHECK(error.find("channel 2") != std::string::npos);
	s.row_mut(5).chn[1].note = 0;

	// an effect song: only channel 1's columns (1..6) are open
	s.effect = true;
	ed.move_cursor(0, 6, false);
	ed.move_col(1);
	CHECK(ed.col_cur == 1);  // wraps within channel 1
	ed.move_col(-1);
	CHECK(ed.col_cur == 6);
	ed.move_cursor(0, 3, false);
	ed.move_channel(1);
	CHECK(ed.col_cur == 3);  // Tab stays in channel 1
	ed.move_cursor(0, 20, false);
	CHECK(ed.col_cur == 6);  // clamped
	ed.select_all_or_section();
	CHECK(ed.sel_col_s == 1 && ed.sel_col_e == 6);

	// a two-channel block pasted into an effect stops at channel 1
	s.effect = false;
	s.row_mut(0).chn[0].note = 30;
	s.row_mut(0).chn[1].note = 40;
	ed.move_cursor(0, 2, false);
	ed.shift_down = true;
	ed.move_cursor(0, 7, false);
	ed.shift_down = false;
	ed.copy_cut(true, false, false);
	m->songs[1].effect = true;
	ed.change_song(1);
	ed.move_cursor(0, 2, false);
	ed.paste(false, false);
	CHECK(m->songs[1].row(0).chn[0].note == 30);
	CHECK(m->songs[1].row(0).chn[1].note == 0);

	// unticking unlocks the channels
	m->songs[1].effect = false;
	ed.move_cursor(0, 20, false);
	CHECK(ed.col_cur == 20);
}

static void test_delete_song()
{
	auto m = std::make_unique<Module>();
	m->songs[0].name = "a";
	m->songs[1].name = "b";
	m->songs[2].name = "c";
	m->songs[2].row_mut(4).chn[0].note = 50;
	m->songs[MAX_SONGS - 1].name = "last";

	delete_song(*m, 1);
	CHECK(m->songs[0].name == "a");
	CHECK(m->songs[1].name == "c" && m->songs[1].row(4).chn[0].note == 50);  // moved up with its notes
	CHECK(m->songs[MAX_SONGS - 2].name == "last");
	CHECK(m->songs[MAX_SONGS - 1].name == "untitled" && song_is_empty(m->songs[MAX_SONGS - 1]));
}

static void test_delete_instrument(const char* project)
{
	auto m = std::make_unique<Module>();
	CHECK(load_module(project, *m));

	// every note's instrument name before, "" for none
	auto names = [](const Module& mod) {
		std::vector<std::string> out;
		for (const Song& s : mod.songs) {
			if (!s.allocated()) continue;
			for (int r = 0; r < MAX_ROWS; ++r)
				for (const NoteField& n : s.row(r).chn)
					out.push_back(n.instrument >= 1 && n.instrument <= MAX_INSTRUMENTS ? mod.instruments[n.instrument - 1].name : "");
		}
		return out;
	};

	const std::string snare = m->instruments[1].name;
	const int uses = instrument_uses(*m, 1);
	CHECK(uses > 0);
	const auto before = names(*m);

	delete_instrument(*m, 1);
	const auto after = names(*m);
	CHECK(before.size() == after.size());
	int cleared = 0;
	for (size_t k = 0; k < before.size() && k < after.size(); ++k) {
		if (before[k] == snare) {
			CHECK(after[k].empty());  // lost its instrument number
			++cleared;
		} else {
			CHECK(after[k] == before[k]);  // still the same instrument
		}
	}
	CHECK(cleared == uses);
	CHECK(!m->instruments[MAX_INSTRUMENTS - 1].has_source());
}

static void test_song_append_slot()
{
	auto m = std::make_unique<Module>();
	CHECK(song_append_slot(*m) == 0);  // a new module: its untitled song 1
	m->songs[0].row_mut(0).chn[0].note = 50;
	CHECK(song_append_slot(*m) == 1);
	m->songs[4].name = "named";  // a gap stays: imports go after the last in use
	CHECK(song_append_slot(*m) == 5);
	m->songs[4].name = "untitled";
	m->songs[4].effect = true;
	CHECK(song_append_slot(*m) == 5);
	m->songs[MAX_SONGS - 1].row_mut(0).chn[0].note = 50;
	CHECK(song_append_slot(*m) == MAX_SONGS);  // none free

	// song_named: the song in use with a name, for an import to replace
	m->songs[4].name = "named";
	CHECK(song_named(*m, "named") == 4);
	CHECK(song_named(*m, "other") == -1);
	CHECK(song_named(*m, "untitled") == -1);  // never matched
	CHECK(song_named(*m, "") == -1);
	m->songs[7].name = "unused";  // a name alone makes it in use
	CHECK(song_named(*m, "unused") == 7);
}

static void test_song_play_row()
{
	auto m = std::make_unique<Module>();
	Song& s = m->songs[0];
	for (int row = 0; row < 10; ++row) s.row_mut(row).chn[0].note = 50;
	s.row_mut(4).speed = 10;  // rows 0-3 last 20 ticks (the default), 4 on 10

	// default markers: it ends on the empty row after the last, looping there
	CHECK(song_play_row(s, 0, -5) == 0);
	CHECK(song_play_row(s, 0, 0) == 0);
	CHECK(song_play_row(s, 0, 19.9) == 0);
	CHECK(song_play_row(s, 0, 20) == 1);
	CHECK(song_play_row(s, 0, 89) == 4);
	CHECK(song_play_row(s, 0, 90) == 5);
	CHECK(song_play_row(s, 0, 140) == 10);
	CHECK(song_play_row(s, 0, 1e6) == 10);
	CHECK(song_play_row(s, 5, 0) == 5);
	CHECK(song_play_row(s, 5, 10) == 6);
	CHECK(song_play_row(s, 2, 45) == 4);  // the speed set above the start still counts

	// a loop: rows 2-7 again and again, 80 ticks a time
	s.length = 8;
	s.loop_start = 2;
	CHECK(song_play_row(s, 0, 119) == 7);
	CHECK(song_play_row(s, 0, 120) == 2);
	CHECK(song_play_row(s, 0, 160) == 4);
	CHECK(song_play_row(s, 0, 120 + 80 * 5 + 45) == 4);
	CHECK(song_play_row(s, 6, 20 + 80 * 3) == 2);
	CHECK(song_play_row(s, 9, 0) == 9);  // past the end: nothing plays
}

int main(int argc, char** argv)
{
	if (argc > 1) test_delete_instrument(argv[1]);
	test_delete_song();
	test_song_play_row();
	test_song_append_slot();
	test_sound_effect_channels();
	if (argc > 1) test_instrument_moves(argv[1]);

	auto m = std::make_unique<Module>();
	SongEditor ed(*m);
	Song& s = m->songs[0];

	// note entry: octave 4, Q-row semitone 12 is C-5 (note 2+5*12)
	ed.octave = 4;
	CHECK(ed.note_for_key(12) == 2 + 60);
	CHECK(ed.note_for_key(-1) == 1);
	ed.octave = 8;
	CHECK(ed.note_for_key(28) == 97);  // clamped to B-7
	ed.octave = 4;

	ed.move_cursor(0, 2, false);
	ed.enter_note(ed.note_for_key(0));  // C-4
	CHECK(s.row(0).chn[0].note == 2 + 48);
	CHECK(ed.undo_available());

	// two digit volume entry
	ed.move_cursor(0, 4, false);
	ed.type_digit(4);
	ed.type_digit(2);
	CHECK(s.row(0).chn[0].volume == 42);

	// instrument digits roll and select the instrument
	ed.move_cursor(0, 3, false);
	ed.type_digit(1);
	ed.type_digit(2);
	CHECK(s.row(0).chn[0].instrument == 12);
	CHECK(ed.ins_cur == 11);

	// effect letter sets a 0 value
	ed.move_cursor(0, 5, false);
	CHECK(ed.type_effect('V'));
	CHECK(s.row(0).chn[0].effect == 'V' && s.row(0).chn[0].value == 0);

	// transpose the block, clamped to the note range
	ed.move_cursor(0, 2, false);
	ed.transpose(12, true, false, false, 0);
	CHECK(s.row(0).chn[0].note == 2 + 60);
	ed.transpose(96, true, false, false, 0);
	CHECK(s.row(0).chn[0].note == 97);

	// undo swaps with the previous state, so it also redoes
	ed.undo();
	CHECK(s.row(0).chn[0].note == 2 + 60);
	ed.undo();
	CHECK(s.row(0).chn[0].note == 97);

	// insert and delete shift the whole channel
	ed.move_cursor(0, 2, false);
	ed.insert_shift();
	CHECK(s.row(0).chn[0].note == 0 && s.row(1).chn[0].note == 97 && s.row(1).chn[0].volume == 42);
	ed.move_cursor(1, 2, false);
	ed.delete_shift();
	CHECK(s.row(0).chn[0].note == 97 && s.row(1).chn[0].note == 0);
	CHECK(ed.row_cur == 0);

	// copy a 2x1 block (note + instrument) and paste it on channel 2
	ed.move_cursor(0, 2, false);
	ed.shift_down = true;
	ed.move_cursor(0, 3, false);
	ed.shift_down = false;
	CHECK(ed.sel_width == 2 && ed.sel_height == 1);
	ed.copy_cut(true, false, false);
	ed.move_cursor(5, 7, false);
	ed.paste(false, false);
	CHECK(s.row(5).chn[1].note == 97 && s.row(5).chn[1].instrument == 12);

	// mix paste only fills empty fields
	s.row_mut(6).chn[1].note = 30;
	ed.move_cursor(6, 7, false);
	ed.paste(false, true);
	CHECK(s.row(6).chn[1].note == 30 && s.row(6).chn[1].instrument == 12);

	// sections
	ed.move_cursor(8, 2, false);
	ed.toggle_marker();
	ed.set_section_name(10, "chorus");
	CHECK(s.row(8).name == "chorus");
	CHECK(ed.section_name(12) == "chorus");
	CHECK(ed.section_list().size() == 1 && ed.section_list()[0].label == "0008: chorus");

	// solo, then solo again unmutes all
	ed.toggle_mute(2, true);
	CHECK(!ed.channel_mute[2] && ed.channel_mute[0] && ed.channel_mute[7]);
	ed.toggle_mute(2, true);
	CHECK(!ed.channel_mute[0] && !ed.channel_mute[2]);

	// the row preview is a 2-row song carrying the last instrument and volume
	Song p = ed.preview_row(5);
	CHECK(p.length == 2 && p.loop_start == 1 && p.row(0).speed == 99);
	CHECK(p.row(0).chn[1].note == 97 && p.row(0).chn[1].instrument == 12 && p.row(0).chn[1].volume == 99);

	if (failures) {
		std::printf("editor_test: %d failure(s)\n", failures);
		return 1;
	}
	std::printf("editor_test: all checks passed\n");
	return 0;
}
