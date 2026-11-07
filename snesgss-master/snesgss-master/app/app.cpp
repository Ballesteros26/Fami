#include "app.h"

#include <algorithm>
#include <cstdio>
#include <filesystem>

#include "export.h"
#include "gsm_io.h"
#include "imgui.h"
#include "imgui_impl_sdl3.h"
#include "imgui_impl_sdlrenderer3.h"
#include "importers.h"
#include "live.h"
#include "modal.h"
#include "song.h"
#include "theme.h"

extern const unsigned char font_cousine_regular[];
extern const size_t font_cousine_regular_size;
extern const unsigned char font_roboto_medium[];
extern const size_t font_roboto_medium_size;

namespace gss {

namespace {

std::string file_name(const std::string& path) { return std::filesystem::u8path(path).filename().u8string(); }
std::string file_dir(const std::string& path) { return std::filesystem::u8path(path).parent_path().u8string(); }

constexpr int SPC_RATE = 32000;  // the SPC700 samples at 32 kHz

void SDLCALL audio_callback(void* userdata, SDL_AudioStream* stream, int additional, int)
{
	SpcPlayer* player = static_cast<SpcPlayer*>(userdata);
	int16_t buf[2048];
	int frames = additional / 4;
	while (frames > 0) {
		const int n = frames < 1024 ? frames : 1024;
		player->render(buf, n);
		SDL_PutAudioStreamData(stream, buf, n * 4);
		frames -= n;
	}
}

// "song 3", "songs 3, 5 to 7": 0-based slots, shown 1-based
std::string slot_list(const char* what, std::vector<int> slots)
{
	std::sort(slots.begin(), slots.end());
	std::string list;
	for (size_t i = 0; i < slots.size();) {
		size_t j = i;
		while (j + 1 < slots.size() && slots[j + 1] == slots[j] + 1) ++j;
		if (!list.empty()) list += ", ";
		list += std::to_string(slots[i] + 1);
		if (j > i) list += (j == i + 1 ? ", " : " to ") + std::to_string(slots[j] + 1);
		i = j + 1;
	}
	return std::string(what) + (slots.size() == 1 ? " " : "s ") + list;
}

}  // namespace

App::App() : module_(new Module) { editor_.reset(new SongEditor(*module_)); }

App::~App()
{
	if (audio_) SDL_DestroyAudioStream(audio_);
}

bool App::init(SDL_Window* window, SDL_Renderer* renderer, int argc, char** argv)
{
	window_ = window;
	renderer_ = renderer;

	// configuration: next to the executable, then in the user's settings folder
	Config cfg;
	const char* base = SDL_GetBasePath();
	if (!(base && cfg.load(std::string(base) + "snesgss.cfg"))) {
		if (char* pref = SDL_GetPrefPath("snesgss", "SNES GSS")) {
			cfg.load(std::string(pref) + "snesgss.cfg");
			SDL_free(pref);
		}
	}
	config_.read(cfg);

	// the editor's own settings, apart from the original's snesgss.cfg
	if (char* pref = SDL_GetPrefPath("snesgss", "SNES GSS")) {
		settings_path_ = std::string(pref) + "editor.cfg";
		SDL_free(pref);
		Config settings;
		if (settings.load(settings_path_)) zoom_ = std::clamp(settings.get_int("UiZoom", 100), 50, 300);
	}

	editor_->page_step = config_.page_step;
	editor_->auto_step = config_.auto_step;

	// audio
	// The SPC700's own rate: the emulator can then be stepped a sample at a
	// time to patch a playing song (live.h); SDL resamples for the device.
	player_.reset(new SpcPlayer(SPC_RATE));
	const SDL_AudioSpec spec = {SDL_AUDIO_S16, 2, SPC_RATE};
	audio_ = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_callback, player_.get());
	if (audio_) {
		SDL_ResumeAudioStreamDevice(audio_);
		driver_idle(idle_);
		SDL_AudioSpec dev;
		int frames = 0;
		if (SDL_GetAudioDeviceFormat(SDL_GetAudioStreamDevice(audio_), &dev, &frames) && dev.freq > 0)
			audio_latency_ = (double)frames / dev.freq;
	} else {
		SDL_Log("No audio output: %s", SDL_GetError());
	}

	// interface
	ImGuiIO& io = ImGui::GetIO();
	io.IniFilename = nullptr;  // nothing to persist yet
	apply_scale();
	if (zoom_ > 100) {  // a bigger interface starts in a bigger window, as far as the display allows
		int w = 0, h = 0;
		SDL_GetWindowSize(window_, &w, &h);
		w = w * zoom_ / 100;
		h = h * zoom_ / 100;
		SDL_Rect usable;
		if (SDL_GetDisplayUsableBounds(SDL_GetDisplayForWindow(window_), &usable)) {
			w = std::min(w, usable.w * 9 / 10);
			h = std::min(h, usable.h * 9 / 10);
		}
		SDL_SetWindowSize(window_, w, h);
		SDL_SetWindowPosition(window_, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
	}

	ImFontConfig fc;
	fc.FontDataOwnedByAtlas = false;
	ui_font_ = io.Fonts->AddFontFromMemoryTTF((void*)font_roboto_medium, (int)font_roboto_medium_size, 15.0f, &fc);

	// SongFontName may name a TTF file; anything else gets the bundled monospace font
	const std::string& fname = config_.font_name;
	if (fname.size() > 4 && (fname.compare(fname.size() - 4, 4, ".ttf") == 0 || fname.compare(fname.size() - 4, 4, ".TTF") == 0) &&
	    std::filesystem::exists(std::filesystem::u8path(fname)))
		pattern_font_ = io.Fonts->AddFontFromFileTTF(fname.c_str(), 16.0f);
	if (!pattern_font_)
		pattern_font_ = io.Fonts->AddFontFromMemoryTTF((void*)font_cousine_regular, (int)font_cousine_regular_size, 16.0f, &fc);
	pattern_font_size_ = config_.font_size * 96.0f / 72.0f;  // points to pixels

	ImGui_ImplSDL3_InitForSDLRenderer(window, renderer);
	ImGui_ImplSDLRenderer3_Init(renderer);

	new_module();
	if (argc > 1 && argv[1][0] != '-') open_module(argv[1]);

	update_title();
	return true;
}

// --- playback ---------------------------------------------------------------------

// The driver takes about 7 ticks from the start of an .spc to a channel's
// first row sounding (measured; startChannel alone waits 4).
constexpr double FOLLOW_START_TICKS = 7;

bool App::play_song(Song& s, int start_row, bool mute, int one_sample)
{
	following_ = false;
	live_.on = false;
	if (start_row >= s.length) return false;

	std::string error;
	if (!compile_preview(s, start_row, mute, one_sample, &error)) {
		message(error);
		return false;
	}
	return player_->play(compiler_.spc_image(), SPC_FILE_SIZE);
}

bool App::compile_preview(Song& s, int start_row, bool mute, int one_sample, std::string* error)
{
	std::copy(editor_->channel_mute, editor_->channel_mute + CHANNELS, compiler_.channel_mute);
	compiler_.all_channels = true;
	const bool ok = compiler_.spc_compile(*module_, s, start_row, mute, false, one_sample, error);
	compiler_.all_channels = false;
	return ok;
}

std::shared_ptr<const LiveSong> App::live_song(const Song& s, int start_row) const
{
	const CompileStats& st = compiler_.stats();
	return std::make_shared<const LiveSong>(compiler_.aram(), st.mem_top + st.music_size, SongTiming(s, start_row));
}

void App::play_current_song(int start_row, bool mute)
{
	SongEditor& ed = *editor_;
	if (!play_song(ed.song(), start_row, mute, -1)) return;
	following_ = true;
	follow_song_ = ed.song_cur;
	follow_start_ = start_row;
	follow_row_ = ed.row_cur;
	follow_offset_ = 0;

	live_.on = true;
	live_.song = ed.song_cur;
	live_.start_row = start_row;
	live_.use_mute = mute;
	live_.playing = live_song(ed.song(), start_row);
	std::copy(ed.channel_mute, ed.channel_mute + CHANNELS, live_.mute);
	live_.dirty = false;
	live_.job.reset();
}

void App::update_live()
{
	if (!live_.on) return;
	SongEditor& ed = *editor_;
	if (!player_->playing() || ed.song_cur != live_.song) {
		live_.on = false;  // stopped, or another song
		return;
	}

	// a patch the audio thread made: the driver plays its compile now
	if (live_.job) {
		if (!live_.job->done.load(std::memory_order_acquire)) return;  // the next waits for it
		const std::shared_ptr<LiveJob> job = std::move(live_.job);
		if (job->moved) {  // else its place wasn't found: it plays on as it was
			live_.playing = job->to;
			std::copy(job->mute, job->mute + CHANNELS, live_.mute);
			// the cursor follows the song's time in the new timing
			follow_offset_ = job->tick - ((double)job->frames / player_->sample_rate() * UPDATE_RATE_HZ - FOLLOW_START_TICKS);
		}
	}

	// recompile the edited song, at most every 50 ms (a slider drag edits every frame)
	if (live_.use_mute && !std::equal(live_.mute, live_.mute + CHANNELS, ed.channel_mute)) live_.dirty = true;
	if (!live_.dirty || SDL_GetTicks() < live_.next_compile) return;
	live_.dirty = false;
	live_.next_compile = SDL_GetTicks() + 50;
	std::string error;
	if (!compile_preview(ed.song(), live_.start_row, live_.use_mute, -1, &error)) return;  // too big: the last that fitted plays on

	auto job = std::make_shared<LiveJob>();
	job->to = live_song(ed.song(), live_.start_row);
	std::copy(ed.channel_mute, ed.channel_mute + CHANNELS, job->mute);
	if (job->to->same_as(*live_.playing)) {  // nothing to hear, as when a key only moved the cursor
		std::copy(job->mute, job->mute + CHANNELS, live_.mute);
		return;
	}

	// the audio thread moves the driver at its next frame boundary
	live_.job = job;
	const std::shared_ptr<const LiveSong> from = live_.playing;
	const DriverIdle idle = idle_;
	player_->queue_patch([job, from, idle](uint8_t* ram, int pc, long long frames) {
		if (!idle.contains(pc)) return false;  // mid-frame: try the next sample
		job->moved = live_patch(ram, *from, *job->to, &job->tick);
		job->frames = frames;
		job->done.store(true, std::memory_order_release);
		return true;
	});
}


void App::update_follow()
{
	if (!following_) return;
	SongEditor& ed = *editor_;
	if (!player_->playing() || ed.song_cur != follow_song_ || ed.row_cur != follow_row_) {
		following_ = false;  // stopped, another song, or the user moved the cursor
		return;
	}

	// what is being heard: rendered, less what is still queued for the device
	double seconds = (double)player_->frames_played() / player_->sample_rate() - audio_latency_;
	if (audio_) seconds -= (double)SDL_GetAudioStreamQueued(audio_) / 4 / player_->sample_rate();
	const int row = song_play_row(ed.song(), follow_start_, seconds * UPDATE_RATE_HZ - FOLLOW_START_TICKS + follow_offset_);
	if (row != ed.row_cur) {
		ed.row_cur = row;
		ed.center_view();
		follow_row_ = row;
	}
}

void App::play_row(int row)
{
	Song t = editor_->preview_row(row);
	play_song(t, 0, true, -1);
}

void App::play_note(int note, int ins)
{
	if (ins < 0 || ins >= MAX_INSTRUMENTS) return;
	Song t = editor_->preview_note(note, ins);
	play_song(t, 0, false, ins);
}

void App::stop()
{
	player_->stop();
	following_ = false;
	live_.on = false;
}

// --- project ----------------------------------------------------------------------

void App::new_module()
{
	stop();
	*module_ = Module();
	editor_->ins_cur = 0;
	editor_->octave = 4;
	for (bool& m : editor_->channel_mute) m = false;
	editor_->change_song(0);
	editor_->clear_song(0);
	module_path_.clear();
	module_name_ = "untitled.gsm";
	compile_after_open(*module_, compiler_);
	mark_dirty();
	update_title();
}

bool App::open_module(const std::string& path)
{
	Module m;
	if (!load_module(path, m)) {
		message("Can't open module");
		return false;
	}
	stop();
	*module_ = std::move(m);
	editor_->change_song(0);
	editor_->reset_view();
	module_path_ = path;
	module_name_ = file_name(path);
	compile_after_open(*module_, compiler_);
	mark_dirty();
	update_title();
	return true;
}

bool App::save_module(const std::string& path)
{
	if (!gss::save_module(path, *module_)) {
		message("Can't save " + path);
		return false;
	}
	module_path_ = path;
	module_name_ = file_name(path);
	update_title();
	return true;
}

bool App::export_to(const std::string& dir)
{
	stop();

	// Export from a fresh compiler, as the command line export does, so the
	// result does not depend on what was previewed earlier in the session.
	Module copy = *module_;
	Compiler c;
	compile_after_open(copy, c);

	std::vector<OutputFile> files;
	std::string error;
	if (!export_all(copy, c, files, &error) || !write_output_files(dir, files, &error)) {
		message("Some export error: " + error);
		return false;
	}
	return true;
}

void App::update_title()
{
	const Song& s = editor_->song();
	const int d = song_duration_seconds(s);
	char title[512];
	std::snprintf(title, sizeof(title), "%s [%s] [Song %d: %s] [%dm%02ds]", VERSION_STR, module_name_.c_str(),
	              editor_->song_cur + 1, s.name.c_str(), d / 60, d % 60);
	if (title_ != title) {
		title_ = title;
		SDL_SetWindowTitle(window_, title);
	}
}

// --- file dialogs -----------------------------------------------------------------

namespace {
struct DialogRequest {
	App* app;
	int kind;
};
}  // namespace

void SDLCALL App::file_dialog_callback(void* userdata, const char* const* filelist, int)
{
	std::unique_ptr<DialogRequest> req(static_cast<DialogRequest*>(userdata));
	if (!filelist || !filelist[0]) return;  // error or cancelled

	std::vector<std::string> paths;
	for (const char* const* f = filelist; *f; ++f) paths.emplace_back(*f);

	App* app = req->app;
	const FileDialog kind = (FileDialog)req->kind;
	std::lock_guard<std::mutex> lock(app->pending_mutex_);
	app->pending_.push_back([app, kind, paths]() mutable { app->file_dialog_done(kind, std::move(paths)); });
}

void App::show_file_dialog(FileDialog kind)
{
	static const SDL_DialogFileFilter gsm[] = {{"SNES GSS project", "gsm"}, {"All files", "*"}};
	static const SDL_DialogFileFilter gsi[] = {{"SNES GSS instrument", "gsi"}, {"All files", "*"}};
	static const SDL_DialogFileFilter wav[] = {{"Wave files", "wav"}, {"All files", "*"}};
	static const SDL_DialogFileFilter spc[] = {{"SPC files", "spc"}, {"All files", "*"}};
	static const SDL_DialogFileFilter xm[] = {{"XM modules", "xm"}, {"All files", "*"}};
	static const SDL_DialogFileFilter mid[] = {{"MIDI files", "mid;midi"}, {"All files", "*"}};
	static const SDL_DialogFileFilter txt[] = {{"Text files", "txt"}, {"All files", "*"}};
	static const SDL_DialogFileFilter bnk[] = {{"SPCBank files", "bnk"}, {"All files", "*"}};

	DialogRequest* req = new DialogRequest{this, (int)kind};
	const std::string dir = module_path_.empty() ? std::string() : file_dir(module_path_);
	const char* loc = dir.empty() ? nullptr : dir.c_str();

	switch (kind) {
	case FileDialog::OPEN: SDL_ShowOpenFileDialog(file_dialog_callback, req, window_, gsm, 2, loc, false); break;
	case FileDialog::SAVE:
	case FileDialog::SAVE_AND_EXPORT:
		SDL_ShowSaveFileDialog(file_dialog_callback, req, window_, gsm, 2, module_path_.empty() ? loc : module_path_.c_str());
		break;
	case FileDialog::EXPORT_DIR: SDL_ShowOpenFolderDialog(file_dialog_callback, req, window_, loc, false); break;
	case FileDialog::EXPORT_SPC: SDL_ShowSaveFileDialog(file_dialog_callback, req, window_, spc, 2, loc); break;
	case FileDialog::IMPORT_WAV: SDL_ShowOpenFileDialog(file_dialog_callback, req, window_, wav, 2, loc, false); break;
	case FileDialog::LOAD_INSTRUMENT: SDL_ShowOpenFileDialog(file_dialog_callback, req, window_, gsi, 2, loc, true); break;
	case FileDialog::SAVE_INSTRUMENT: SDL_ShowSaveFileDialog(file_dialog_callback, req, window_, gsi, 2, loc); break;
	case FileDialog::EXTRACT_WAV: SDL_ShowSaveFileDialog(file_dialog_callback, req, window_, wav, 2, loc); break;
	case FileDialog::IMPORT_XM_SONG:
	case FileDialog::IMPORT_XM_EFFECTS: SDL_ShowOpenFileDialog(file_dialog_callback, req, window_, xm, 2, loc, false); break;
	case FileDialog::IMPORT_MIDI: SDL_ShowOpenFileDialog(file_dialog_callback, req, window_, mid, 2, loc, false); break;
	case FileDialog::IMPORT_FTM: SDL_ShowOpenFileDialog(file_dialog_callback, req, window_, txt, 2, loc, false); break;
	case FileDialog::IMPORT_BANK: SDL_ShowOpenFileDialog(file_dialog_callback, req, window_, bnk, 2, loc, false); break;
	}
}

static std::string with_extension(std::string path, const char* ext)
{
	if (std::filesystem::u8path(path).extension().empty()) path += ext;
	return path;
}

void App::file_dialog_done(FileDialog kind, std::vector<std::string> paths)
{
	const std::string& path = paths.front();
	std::string data, error;

	switch (kind) {
	case FileDialog::OPEN:
		open_module(path);
		break;

	case FileDialog::SAVE:
		save_module(with_extension(path, ".gsm"));
		break;

	case FileDialog::SAVE_AND_EXPORT: {
		const std::string p = with_extension(path, ".gsm");
		if (save_module(p)) export_to(file_dir(p));
		break;
	}

	case FileDialog::EXPORT_DIR:
		export_to(path);
		break;

	case FileDialog::EXPORT_SPC: {
		Song& s = editor_->song();
		if (!compiler_.spc_compile(*module_, s, 0, false, false, -1, &error)) {
			message(error);
			break;
		}
		if (!write_file(with_extension(path, ".spc"), export_spc(compiler_, "").data)) message("Can't write " + path);
		break;
	}

	case FileDialog::IMPORT_WAV:
		if (!read_file(path, data)) {
			message("Can't open " + path);
			break;
		}
		if (!import_wav(data, path, module_->instruments[editor_->ins_cur], &error)) {
			message(error);
			break;
		}
		samples_changed();
		break;

	case FileDialog::LOAD_INSTRUMENT:
		for (size_t i = 0; i < paths.size(); ++i) {
			const int slot = editor_->ins_cur + (int)i;
			if (slot >= MAX_INSTRUMENTS) break;
			Instrument ins;
			if (load_instrument(paths[i], ins)) module_->instruments[slot] = std::move(ins);
		}
		samples_changed();
		break;

	case FileDialog::SAVE_INSTRUMENT:
		if (!save_instrument(with_extension(path, ".gsi"), module_->instruments[editor_->ins_cur]))
			message("Can't write " + path);
		break;

	case FileDialog::EXTRACT_WAV: {
		const Instrument& ins = module_->instruments[editor_->ins_cur];
		if (!ins.has_source()) break;
		if (!write_file(with_extension(path, ".wav"), export_source_wav(ins))) message("Can't write " + path);
		break;
	}

	case FileDialog::IMPORT_XM_SONG:
	case FileDialog::IMPORT_XM_EFFECTS:
		if (!read_file(path, data)) {
			message("Can't open " + path);
			break;
		}
	{
		// songs and instruments with the same names are replaced, the others added
		XmImportInfo info;
		if (!import_xm(data, *module_, song_append_slot(*module_), kind == FileDialog::IMPORT_XM_EFFECTS, xm_samples_,
		               &error, &info) ||
		    !error.empty()) {
			message(error);
		} else {
			if (!info.songs.empty()) show_imported_song(info.songs.front());
			std::vector<int> songs_added;
			for (int i : info.songs)
				if (std::find(info.songs_replaced.begin(), info.songs_replaced.end(), i) == info.songs_replaced.end())
					songs_added.push_back(i);
			std::string text;
			auto line = [&](const char* verb, const char* what, const std::vector<int>& slots, const char* why) {
				if (slots.empty()) return;
				if (!text.empty()) text += "\n";
				text += std::string(verb) + " " + slot_list(what, slots) + why + ".";
			};
			line("Imported", "song", songs_added, "");
			line("Replaced", "song", info.songs_replaced, ", with the same name");
			line("Imported", "instrument", info.instruments, "");
			line("Replaced", "instrument", info.instruments_replaced, ", with the same name");
			if (!info.instruments.empty() || !info.instruments_replaced.empty()) samples_changed();
			if (!info.not_converted.empty()) {  // one per line: "arpeggio (12), tremolo (3)"
				if (!text.empty()) text += "\n\n";
				text += "Not converted, the SNES driver has no equivalent:";
				size_t a = 0;
				while (a < info.not_converted.size()) {
					size_t b = info.not_converted.find(", ", a);
					if (b == std::string::npos) b = info.not_converted.size();
					text += "\n  " + info.not_converted.substr(a, b - a);
					a = b + 2;
				}
			}
			message(text);
		}
		editor_->reset_undo();
		compiler_.compile_all_songs(*module_);
		break;
	}

	case FileDialog::IMPORT_MIDI:
		if (!read_file(path, data)) {
			message("Can't open " + path);
			break;
		}
	{
		// named after the file, which a second import of it replaces
		const std::string name = std::filesystem::u8path(path).stem().u8string();
		bool replacing = false;
		const int target = import_song_slot(name, &replacing);
		if (target < 0) break;
		// on an error it keeps what was imported so far, shown all the same
		if (!import_midi(data, *module_, target, &error)) {
			if (!song_is_empty(module_->songs[target])) module_->songs[target].name = name;
			show_imported_song(target);
			message(error);
		} else {
			finish_song_import(target, name, replacing);
		}
		editor_->reset_undo();
		compiler_.compile_all_songs(*module_);
		break;
	}

	case FileDialog::IMPORT_FTM:
		if (!read_file(path, data)) {
			message("Can't open " + path);
			break;
		}
		open_subsong_dialog(std::move(data), std::filesystem::u8path(path).stem().u8string());
		break;

	case FileDialog::IMPORT_BANK:
		if (!read_file(path, data)) {
			message("Can't open " + path);
			break;
		}
		if (!import_spc_bank(data, *module_, &error)) message(error);
		samples_changed();
		break;
	}

	mark_dirty();
	update_title();
}

int App::import_song_slot(const std::string& name, bool* replacing)
{
	const int same = song_named(*module_, name);
	*replacing = same >= 0;
	if (same >= 0) return same;
	const int slot = song_append_slot(*module_);
	if (slot < MAX_SONGS) return slot;
	message("There is no free song slot after the last song in use.");
	return -1;
}

void App::finish_song_import(int slot, const std::string& name, bool replacing)
{
	if (!song_is_empty(module_->songs[slot])) module_->songs[slot].name = name;
	show_imported_song(slot);
	message((replacing ? "Replaced song " : "Imported song ") + std::to_string(slot + 1) +
	        (replacing ? ", with the same name." : "."));
}

void App::show_imported_song(int slot)
{
	if (!song_used(module_->songs[slot])) return;
	stop();
	editor_->change_song(slot);
	editor_->reset_view();
}

void App::run_pending()
{
	std::vector<std::function<void()>> jobs;
	{
		std::lock_guard<std::mutex> lock(pending_mutex_);
		jobs.swap(pending_);
	}
	for (auto& job : jobs) job();
}

// --- frame ------------------------------------------------------------------------

void App::select_tab(Tab t)
{
	tab_request_ = t;
	tab_requested_ = true;
}

void App::event(const SDL_Event& e)
{
	ImGui_ImplSDL3_ProcessEvent(&e);

	switch (e.type) {
	case SDL_EVENT_QUIT: quit_ = true; break;
	case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
		if (e.window.windowID == SDL_GetWindowID(window_)) quit_ = true;
		break;
	case SDL_EVENT_KEY_DOWN:
		key_down(e.key);
		mark_dirty();
		break;
	case SDL_EVENT_KEY_UP: key_up(e.key); break;
	case SDL_EVENT_MOUSE_BUTTON_UP: mark_dirty(); break;
	case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED: rescale_ = true; break;
	default: break;
	}
}

void App::draw_menu()
{
	if (!ImGui::BeginMainMenuBar()) return;

	if (ImGui::BeginMenu("File")) {
		if (ImGui::MenuItem("New"))
			confirm("All current data will be lost. Are you sure you want to start a new project?", [this] { new_module(); });
		ImGui::Separator();
		if (ImGui::MenuItem("Open...")) show_file_dialog(FileDialog::OPEN);
		if (ImGui::MenuItem("Save...")) show_file_dialog(FileDialog::SAVE);
		ImGui::Separator();
		if (ImGui::MenuItem("Export and Save...")) show_file_dialog(FileDialog::SAVE_AND_EXPORT);
		if (ImGui::MenuItem("Export...")) show_file_dialog(FileDialog::EXPORT_DIR);
		ImGui::Separator();
		if (ImGui::MenuItem("Exit")) quit_ = true;
		ImGui::EndMenu();
	}

	if (ImGui::BeginMenu("Song")) {
		if (ImGui::MenuItem("Clear"))
			confirm("Clear current song, are you sure?", [this] {
				stop();
				editor_->clear_song(editor_->song_cur);
			});
		ImGui::Separator();
		if (ImGui::MenuItem("Clean up song text")) {
			editor_->set_undo();
			song_clean_up(editor_->song());
		}
		if (ImGui::MenuItem("Advanced transpose...")) open_transpose_dialog(false);
		if (ImGui::MenuItem("Scale volume...")) open_transpose_dialog(true);
		ImGui::Separator();
		if (ImGui::BeginMenu("Import from XM")) {
			if (ImGui::MenuItem("One song for all patterns...")) show_file_dialog(FileDialog::IMPORT_XM_SONG);
			if (ImGui::MenuItem("Each pattern as a separate song...")) show_file_dialog(FileDialog::IMPORT_XM_EFFECTS);
			ImGui::Separator();
			ImGui::MenuItem("Include samples", nullptr, &xm_samples_);
			if (ImGui::IsItemHovered(ImGuiHoveredFlags_ForTooltip))
				ImGui::SetTooltip("Import the XM's instruments, retuned to play in tune, into the free slots after\n"
				                  "the last one in use. Untick for notes only (two octaves up, for samples\n"
				                  "prepared the SNES GSS way).");
			ImGui::EndMenu();
		}
		if (ImGui::MenuItem("Import notes from MIDI...")) show_file_dialog(FileDialog::IMPORT_MIDI);
		if (ImGui::MenuItem("Import FamiTracker text...")) show_file_dialog(FileDialog::IMPORT_FTM);
		ImGui::Separator();
		if (ImGui::MenuItem("Export SPC...")) show_file_dialog(FileDialog::EXPORT_SPC);
		ImGui::EndMenu();
	}

	if (ImGui::BeginMenu("View")) {
		if (ImGui::MenuItem("Zoom In", "Ctrl+=", false, zoom_ < 300)) zoom_step(1);
		if (ImGui::MenuItem("Zoom Out", "Ctrl+-", false, zoom_ > 50)) zoom_step(-1);
		if (ImGui::MenuItem("Actual Size", nullptr, false, zoom_ != 100)) set_zoom(100);
		ImGui::Separator();
		ImGui::TextDisabled("Zoom %d%%", zoom_);
		ImGui::EndMenu();
	}

	if (ImGui::BeginMenu("Instruments")) {
		if (ImGui::MenuItem("Import SPCBank...")) show_file_dialog(FileDialog::IMPORT_BANK);
		if (ImGui::MenuItem("Cleanup instruments"))
			confirm("Remove all unused instruments from the project?", [this] { cleanup_instruments(); });
		if (ImGui::MenuItem("Extract source wave...", nullptr, false, module_->instruments[editor_->ins_cur].has_source()))
			show_file_dialog(FileDialog::EXTRACT_WAV);
		ImGui::Separator();
		if (ImGui::MenuItem("Replace instrument number...")) open_replace_dialog();
		ImGui::Separator();
		ImGui::MenuItem("Auto insert instrument number", nullptr, &editor_->auto_number);
		ImGui::Separator();
		int count = 0;
		for (int i = 0; i < MAX_INSTRUMENTS; ++i) {
			const Instrument& ins = module_->instruments[i];
			if (!ins.has_source()) continue;
			++count;
			char label[64];
			std::snprintf(label, sizeof(label), "%02d: %s##ins%d", i + 1, ins.name.c_str(), i);
			if (ImGui::MenuItem(label, nullptr, editor_->ins_cur == i)) editor_->ins_cur = i;
		}
		if (!count) ImGui::MenuItem("no instruments", nullptr, false, false);
		ImGui::EndMenu();
	}


	ImGui::EndMainMenuBar();
}

// --- interface scale --------------------------------------------------------------

// Dear ImGui lays out in window coordinates, which on macOS and Wayland are
// already scaled for the display (the backend renders them at the pixel
// density), so the scale wanted is the display's content scale, not
// SDL_GetWindowDisplayScale (that is per pixel).
void App::apply_scale()
{
	const float content = SDL_GetDisplayContentScale(SDL_GetDisplayForWindow(window_));
	content_scale_ = content > 0 ? content : 1.0f;
	ui_scale_ = content_scale_ * zoom_ / 100.0f;

	ImGuiStyle style;  // ScaleAllSizes multiplies: start from an unscaled style
	theme::apply(style);
	style.ScaleAllSizes(ui_scale_);
	style.FontScaleDpi = ui_scale_;  // both fonts follow this
	ImGui::GetStyle() = style;
}

constexpr int ZOOM_STEPS[] = {50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300};

void App::zoom_step(int direction)
{
	int z = zoom_;
	if (direction > 0) {
		for (int s : ZOOM_STEPS)
			if (s > zoom_) {
				z = s;
				break;
			}
	} else {
		for (int s : ZOOM_STEPS)
			if (s < zoom_) z = s;
	}
	set_zoom(z);
}

void App::set_zoom(int percent)
{
	percent = std::clamp(percent, 50, 300);
	if (percent == zoom_) return;
	zoom_ = percent;
	rescale_ = true;
	if (!settings_path_.empty()) write_file(settings_path_, "UiZoom=" + std::to_string(zoom_) + "\n");
}

void App::frame()
{
	if (rescale_) {  // a zoom, or the window on a display with another scale
		rescale_ = false;
		apply_scale();
	}

	run_pending();

	if (stats_dirty_ && SDL_GetTicks() >= dirty_at_ + 300) refresh_stats();

	update_output_monitor();
	update_live();
	update_follow();

	ImGui_ImplSDLRenderer3_NewFrame();
	ImGui_ImplSDL3_NewFrame();
	ImGui::NewFrame();
	ImGui::PushFont(ui_font_, 0.0f);

	draw_menu();

	draw_workspace();

	draw_dialogs();

	ImGui::PopFont();
	ImGui::Render();

	update_title();

	SDL_SetRenderScale(renderer_, ImGui::GetIO().DisplayFramebufferScale.x, ImGui::GetIO().DisplayFramebufferScale.y);
	SDL_SetRenderDrawColor(renderer_, 0x0f, 0x11, 0x17, 255);
	SDL_RenderClear(renderer_);
	ImGui_ImplSDLRenderer3_RenderDrawData(ImGui::GetDrawData(), renderer_);
	SDL_RenderPresent(renderer_);
}

}  // namespace gss
