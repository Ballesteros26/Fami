// Keyboard handling, ported from the original editor's AppMessage().
//
// Note keys and digits use scancodes (physical positions, like the original
// piano layout); effect letters and Ctrl shortcuts use the typed letter.
#include "app.h"
#include "imgui.h"
#include "modal.h"

namespace gss {

namespace {

struct NoteKey {
	SDL_Scancode sc;
	int semitone;  // -1 = key off
};

const NoteKey NOTE_KEYS[] = {
	{SDL_SCANCODE_1, -1}, {SDL_SCANCODE_A, -1},

	{SDL_SCANCODE_Z, 0}, {SDL_SCANCODE_S, 1}, {SDL_SCANCODE_X, 2}, {SDL_SCANCODE_D, 3}, {SDL_SCANCODE_C, 4},
	{SDL_SCANCODE_V, 5}, {SDL_SCANCODE_G, 6}, {SDL_SCANCODE_B, 7}, {SDL_SCANCODE_H, 8}, {SDL_SCANCODE_N, 9},
	{SDL_SCANCODE_J, 10}, {SDL_SCANCODE_M, 11}, {SDL_SCANCODE_COMMA, 12}, {SDL_SCANCODE_L, 13},
	{SDL_SCANCODE_PERIOD, 14}, {SDL_SCANCODE_SEMICOLON, 15}, {SDL_SCANCODE_SLASH, 16},

	{SDL_SCANCODE_Q, 12}, {SDL_SCANCODE_2, 13}, {SDL_SCANCODE_W, 14}, {SDL_SCANCODE_3, 15}, {SDL_SCANCODE_E, 16},
	{SDL_SCANCODE_R, 17}, {SDL_SCANCODE_5, 18}, {SDL_SCANCODE_T, 19}, {SDL_SCANCODE_6, 20}, {SDL_SCANCODE_Y, 21},
	{SDL_SCANCODE_7, 22}, {SDL_SCANCODE_U, 23}, {SDL_SCANCODE_I, 24}, {SDL_SCANCODE_9, 25}, {SDL_SCANCODE_O, 26},
	{SDL_SCANCODE_0, 27}, {SDL_SCANCODE_P, 28},
};

// Top row digits, by position.
int digit(SDL_Scancode sc)
{
	if (sc >= SDL_SCANCODE_1 && sc <= SDL_SCANCODE_9) return 1 + (sc - SDL_SCANCODE_1);
	if (sc == SDL_SCANCODE_0) return 0;
	return -1;
}

// A..Z as typed, or 0.
char letter(SDL_Keycode key)
{
	if (key >= SDLK_A && key <= SDLK_Z) return (char)('A' + (key - SDLK_A));
	return 0;
}

}  // namespace

int App::note_key_semitone(SDL_Scancode sc)
{
	for (const NoteKey& k : NOTE_KEYS)
		if (k.sc == sc) return k.semitone;
	return -2;
}

bool App::all_note_keys_up() const
{
	const bool* state = SDL_GetKeyboardState(nullptr);
	for (const NoteKey& k : NOTE_KEYS)
		if (state[k.sc]) return false;
	return true;
}

void App::key_up(const SDL_KeyboardEvent& k)
{
	editor_->shift_down = (k.mod & SDL_KMOD_SHIFT) != 0;

	if (k.key == SDLK_RETURN || k.key == SDLK_KP_ENTER) stop();
	// the end of a note's audition; a song playing live plays on
	if (note_key_semitone(k.scancode) != -2 && all_note_keys_up() && !live_.on) stop();
}

void App::key_down(const SDL_KeyboardEvent& k)
{
	SongEditor& ed = *editor_;
	const bool shift = (k.mod & SDL_KMOD_SHIFT) != 0;
	const bool ctrl = (k.mod & (SDL_KMOD_CTRL | SDL_KMOD_GUI)) != 0;
	const bool first = !k.repeat;

	ed.shift_down = shift;

	if (!modals_.empty()) return;  // dialogs take the keyboard

	// keys that work everywhere
	if (ctrl) {
		switch (k.key) {
		case SDLK_EQUALS:
		case SDLK_PLUS:
		case SDLK_KP_PLUS: zoom_step(1); return;
		case SDLK_MINUS:
		case SDLK_KP_MINUS: zoom_step(-1); return;
		default: break;
		}
	}
	if (!ctrl && !shift) {
		switch (k.key) {
		case SDLK_F1: select_tab(TAB_SONG); return;
		case SDLK_F3: select_tab(TAB_INSTRUMENTS); return;
		case SDLK_F4: select_tab(TAB_INFO); return;
		case SDLK_F5: play_current_song(0); return;
		case SDLK_F7: play_current_song(ed.row_cur); return;
		case SDLK_F8: stop(); return;
		case SDLK_KP_PLUS:
			if (ed.song_cur < MAX_SONGS - 1) ed.change_song(ed.song_cur + 1);
			return;
		case SDLK_KP_MINUS:
			if (ed.song_cur > 0) ed.change_song(ed.song_cur - 1);
			return;
		case SDLK_KP_DIVIDE: ed.change_octave(-1); return;
		case SDLK_KP_MULTIPLY: ed.change_octave(1); return;
		case SDLK_KP_1: case SDLK_KP_2: case SDLK_KP_3: case SDLK_KP_4:
		case SDLK_KP_5: case SDLK_KP_6: case SDLK_KP_7: case SDLK_KP_8:
			ed.octave = 1 + (int)(k.key - SDLK_KP_1);
			return;
		default: break;
		}
	}

	if (ImGui::GetIO().WantTextInput) return;  // typing into a text field

	const int semitone = note_key_semitone(k.scancode);

	if (tab_ == TAB_INSTRUMENTS) {
		if (semitone != -2 && first && !ctrl) play_note(ed.note_for_key(semitone), ed.ins_cur);
		return;
	}

	if (tab_ != TAB_SONG) return;

	if ((k.key == SDLK_RETURN || k.key == SDLK_KP_ENTER) && ed.col_cur && first) {
		play_song(ed.song(), ed.row_cur, true, -1);  // hold to play, released in key_up
		return;
	}

	if (shift && !ctrl) {
		switch (letter(k.key)) {
		case 'X':
			ed.set_undo();
			ed.copy_cut(true, true, true);
			return;
		case 'V':
			ed.set_undo();
			ed.paste(true, false);
			return;
		default: break;
		}
	}

	if (ctrl) {
		const int d = digit(k.scancode);
		if (d >= 1 && d <= 8) {
			ed.toggle_mute(d - 1, false);
			return;
		}
		if (d == 0) {
			ed.toggle_mute((ed.col_cur - 2) / 5, true);
			return;
		}

		switch (k.scancode) {
		case SDL_SCANCODE_LEFTBRACKET: ed.change_measure(-1); return;
		case SDL_SCANCODE_RIGHTBRACKET: ed.change_measure(1); return;
		case SDL_SCANCODE_HOME: ed.set_loop_start(); return;
		case SDL_SCANCODE_END: ed.set_length(); return;
		case SDL_SCANCODE_F1: ed.transpose(-1, true, false, false, 0); return;
		case SDL_SCANCODE_F2: ed.transpose(1, true, false, false, 0); return;
		case SDL_SCANCODE_F3: ed.transpose(-12, true, false, false, 0); return;
		case SDL_SCANCODE_F4: ed.transpose(12, true, false, false, 0); return;
		default: break;
		}

		switch (letter(k.key)) {
		case 'F': open_section_list(); return;
		case 'G': ed.goto_row_column(); return;
		case 'Z': ed.undo(); return;
		case 'C': ed.copy_cut(true, false, false); return;
		case 'X':
			ed.set_undo();
			ed.copy_cut(true, true, false);
			return;
		case 'V':
			ed.set_undo();
			ed.paste(false, false);
			return;
		case 'B':
			ed.set_undo();
			ed.paste(false, true);
			return;
		case 'E': ed.expand_selection(); return;
		case 'S': ed.shrink_selection(); return;
		case 'A': ed.select_all_or_section(); return;
		case 'L': ed.select_channel_or_section(); return;
		default: break;
		}
		return;
	}

	// keys without Ctrl
	if (k.key == SDLK_DELETE && (ed.sel_width > 1 || ed.sel_height > 1)) {
		ed.copy_cut(false, true, false);
		return;
	}

	const int num = digit(k.scancode);

	if (ed.col_cur >= 2) {
		switch ((ed.col_cur - 2) % 5) {
		case 0:  // note
			if (!shift) {
				if (k.key == SDLK_DELETE) {
					ed.delete_at_cursor();
					return;
				}
				if (semitone != -2 && first) {
					const int row = ed.row_cur;
					ed.enter_note(ed.note_for_key(semitone));
					if (!live_.on) play_row(row);  // a song playing live picks the note up instead
					ed.move_row(ed.auto_step);
					return;
				}
			}
			break;
		case 3:  // effect letter
			if (k.key == SDLK_DELETE) {
				ed.delete_at_cursor();
				return;
			}
			if (const char c = letter(k.key)) {
				ed.type_effect(c);
				return;
			}
			break;
		default:  // instrument, volume, effect value
			if (k.key == SDLK_DELETE) {
				ed.delete_at_cursor();
				return;
			}
			if (num >= 0) {
				ed.type_digit(num);
				return;
			}
			break;
		}
	} else if (ed.col_cur == 0) {  // row number
		if (num >= 0) {
			ed.type_digit(num);
			return;
		}
		if ((k.key == SDLK_RETURN || k.key == SDLK_KP_ENTER) && ed.col_cur_prev >= 0) {
			ed.return_from_row_column();
			return;
		}
	} else {  // speed
		if (k.key == SDLK_DELETE) {
			ed.delete_at_cursor();
			return;
		}
		if (num >= 0) {
			ed.type_digit(num);
			return;
		}
	}

	switch (k.scancode) {
	case SDL_SCANCODE_LEFT: ed.move_col(-1); return;
	case SDL_SCANCODE_RIGHT: ed.move_col(1); return;
	case SDL_SCANCODE_UP: ed.move_row(-1); return;
	case SDL_SCANCODE_DOWN: ed.move_row(1); return;
	case SDL_SCANCODE_PAGEUP: ed.move_row(-ed.page_step); return;
	case SDL_SCANCODE_PAGEDOWN: ed.move_row(ed.page_step); return;
	case SDL_SCANCODE_TAB: ed.move_channel(shift ? -1 : 1); return;
	case SDL_SCANCODE_BACKSPACE: ed.delete_shift(); return;
	case SDL_SCANCODE_INSERT: ed.insert_shift(); return;
	case SDL_SCANCODE_LEFTBRACKET: ed.change_auto_step(-1); return;
	case SDL_SCANCODE_RIGHTBRACKET: ed.change_auto_step(1); return;
	case SDL_SCANCODE_SPACE: ed.toggle_marker(); return;
	case SDL_SCANCODE_HOME: ed.prev_marker(); return;
	case SDL_SCANCODE_END: ed.next_marker(); return;
	case SDL_SCANCODE_GRAVE: open_section_name(); return;
	default: break;
	}
}

}  // namespace gss
