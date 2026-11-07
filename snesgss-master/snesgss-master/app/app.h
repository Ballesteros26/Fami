// The SNES GSS editor front end: SDL3 window, Dear ImGui interface, audio.
#pragma once

#include <SDL3/SDL.h>

#include <atomic>

#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "compiler.h"
#include "config.h"
#include "model.h"
#include "live.h"
#include "song.h"
#include "song_editor.h"
#include "spc_player.h"

struct ImFont;
struct ImVec2;

namespace gss {

class App {
public:
	App();
	~App();

	bool init(SDL_Window* window, SDL_Renderer* renderer, int argc, char** argv);
	void frame();  // builds and renders one frame
	void event(const SDL_Event& e);
	bool quit_requested() const { return quit_; }

private:
	enum Tab { TAB_SONG, TAB_INSTRUMENTS, TAB_INFO };

	// --- playback (app.cpp) ---
	bool play_song(Song& s, int start_row, bool mute, int one_sample);
	// Plays the current song, moves the cursor with it (follow_*) and keeps
	// it up to date with edits as it plays (live_).
	void play_current_song(int start_row, bool mute = true);
	void update_follow();  // once a frame
	void update_live();    // once a frame
	void play_row(int row);
	void play_note(int note, int ins);
	void stop();

	// --- project (app.cpp) ---
	void new_module();
	bool open_module(const std::string& path);
	bool save_module(const std::string& path);
	bool export_to(const std::string& dir);
	void samples_changed()
	{
		compiler_.invalidate_samples();
		mark_dirty();
	}
	void update_title();

	// --- file dialogs: SDL calls back on any thread, results run in frame() ---
	enum class FileDialog { OPEN, SAVE, SAVE_AND_EXPORT, EXPORT_DIR, EXPORT_SPC, IMPORT_WAV, LOAD_INSTRUMENT,
		SAVE_INSTRUMENT, EXTRACT_WAV, IMPORT_XM_SONG, IMPORT_XM_EFFECTS, IMPORT_MIDI, IMPORT_FTM, IMPORT_BANK };
	void show_file_dialog(FileDialog kind);
	void file_dialog_done(FileDialog kind, std::vector<std::string> paths);
	static void SDLCALL file_dialog_callback(void* userdata, const char* const* filelist, int filter);
	void run_pending();

	// --- views ---
	void draw_menu();
	void draw_workspace();       // workspace.cpp: the layout of everything below
	void draw_transport();
	void draw_sidebar();
	void draw_center();          // pattern, instrument editor or memory (F1, F3, F4)
	void draw_status_bar();
	void draw_output_monitor(float width, float height);  // the toolbar's output levels
	void update_output_monitor();
	void draw_song_view();       // song_view.cpp
	void draw_pattern_scrollbar(ImVec2 pos, ImVec2 size);
	void draw_instruments();     // instrument_view.cpp
	void draw_info();            // info_view.cpp
	void draw_dialogs();         // dialogs.cpp
	void select_tab(Tab t);

	// --- keyboard (keys.cpp) ---
	void key_down(const SDL_KeyboardEvent& k);
	void key_up(const SDL_KeyboardEvent& k);
	bool all_note_keys_up() const;
	static int note_key_semitone(SDL_Scancode sc);  // -1 key off, -2 not a note key

	// --- pattern view geometry (song_view.cpp) ---
	int pattern_top_row2x() const;
	int pattern_screen_to_row(int srow) const;

	// --- dialogs (dialogs.cpp) ---
	void confirm(const std::string& text, std::function<void()> on_yes);
	void message(const std::string& text);
	void open_transpose_dialog(bool scale_volume);
	void open_replace_dialog();
	void open_section_list();
	void open_section_name();
	void open_subsong_dialog(std::string ftm_data, std::string file_stem);
	// Where a MIDI or FamiTracker import goes: over the song in use with its
	// name (*replacing set), so importing it again replaces it, else after
	// the last song in use. -1 (after a message) if there is no slot.
	int import_song_slot(const std::string& name, bool* replacing);
	// After the import: names the song if the import left anything in it,
	// reports it, and selects it.
	void finish_song_import(int slot, const std::string& name, bool replacing);
	void show_imported_song(int slot);  // selects it, if the import left anything there

	// --- instrument operations (instrument_view.cpp) ---
	void clear_instrument(int ins);
	// Moves slot from to slot to, shifting the slots in between; every note in
	// every song is renumbered so it keeps playing the same instrument.
	void move_instrument(int from, int to);
	void cleanup_instruments();

	// --- song and instrument operations (workspace.cpp), all ask first ---
	void clear_song_at(int i);
	void delete_song_at(int i);
	void clear_instrument_at(int i);
	void delete_instrument_at(int i);

	SDL_Window* window_ = nullptr;
	SDL_Renderer* renderer_ = nullptr;
	SDL_AudioStream* audio_ = nullptr;
	double audio_latency_ = 0;  // seconds of the device's buffer

	// following the playing song with the cursor
	bool following_ = false;
	int follow_song_ = 0;
	int follow_start_ = 0;
	int follow_row_ = 0;  // the row last set; another means the user moved
	double follow_offset_ = 0;  // ticks: the song's time moves when an edit lands

	// Live updates: after an edit the playing song is recompiled and the
	// driver moved onto it (live.h), by the audio thread at a frame boundary.
	struct LiveJob {
		std::shared_ptr<const LiveSong> to;
		bool mute[CHANNELS] = {};  // what it was compiled with
		bool moved = false;        // set by the audio thread, then done
		double tick = 0;
		long long frames = 0;
		std::atomic<bool> done{false};
	};
	struct Live {
		bool on = false;
		int song = 0, start_row = 0;
		bool use_mute = true;
		std::shared_ptr<const LiveSong> playing;  // what the driver plays
		bool mute[CHANNELS] = {};                 // what it was compiled with
		bool dirty = false;                       // an edit not compiled yet
		Uint64 next_compile = 0;                  // at most every 50 ms
		std::shared_ptr<LiveJob> job;             // queued with the player
	} live_;
	// Compiles s for playing, with every channel (Compiler::all_channels) so
	// it can be moved onto a later compile; the result as a LiveSong.
	bool compile_preview(Song& s, int start_row, bool mute, int one_sample, std::string* error);
	std::shared_ptr<const LiveSong> live_song(const Song& s, int start_row) const;
	DriverIdle idle_;  // where the driver waits for its next frame
	ImFont* ui_font_ = nullptr;
	ImFont* pattern_font_ = nullptr;
	float pattern_font_size_ = 16.0f;
	float ui_scale_ = 1.0f;  // the display's content scale times the zoom

	// --- interface scale (app.cpp) ---
	void apply_scale();           // from the display and the zoom; between frames
	void zoom_step(int direction);
	void set_zoom(int percent);   // remembered in editor.cfg
	float content_scale_ = 1.0f;  // the display's, as SDL reports it
	int zoom_ = 100;              // percent
	bool rescale_ = false;        // apply_scale() before the next frame
	std::string settings_path_;   // editor.cfg in the user's settings folder

	AppConfig config_;
	std::unique_ptr<Module> module_;
	Compiler compiler_;
	std::unique_ptr<SongEditor> editor_;
	std::unique_ptr<SpcPlayer> player_;

	// output monitor, as the original's: levels with falling peak markers
	int out_l_ = 0, out_r_ = 0, peak_l_ = 0, peak_r_ = 0;  // 0..32768
	Uint64 monitor_tick_ = 0;  // the original updated every 25 ms

	std::string module_path_;
	std::string module_name_ = "untitled.gsm";

	Tab tab_ = TAB_SONG;
	Tab tab_request_ = TAB_SONG;
	bool tab_requested_ = true;
	bool quit_ = false;
	bool xm_samples_ = true;  // Import from XM also brings in the samples

	// memory statistics, recompiled shortly after the last change
	void mark_dirty();
	void refresh_stats();
	bool stats_dirty_ = true;
	Uint64 dirty_at_ = 0;

	// pattern view state
	float char_w_ = 8, char_h_ = 16;
	int pattern_lines_ = 1;  // visible lines including the header
	bool dragging_ = false;
	Uint64 scroll_delay_until_ = 0;
	bool double_click_pending_ = false;
	float scroll_grab_ = 0;  // where the scrollbar thumb was grabbed

	// instrument view state
	float ins_cards_h_ = 220;  // height of the settings cards last frame, to size the preview
	float ins_card_h_ = 200;   // the tallest card's content last frame; all three cards use it

	// dialogs
	struct Modal;
	std::vector<std::unique_ptr<Modal>> modals_;  // front is showing
	void push_modal(std::unique_ptr<Modal> m);
	std::string title_;

	std::mutex pending_mutex_;
	std::vector<std::function<void()>> pending_;
};

}  // namespace gss
