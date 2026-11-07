// The single-window workspace: transport bar, project sidebar, a center
// panel (pattern, instrument editor or memory detail; F1, F3, F4) and a
// status bar with the SPC700 memory meter.
#include <algorithm>
#include <cstdio>
#include <string>
#include <utility>
#include <vector>

#include "app.h"
#include "brr.h"
#include "imgui.h"
#include "song.h"
#include "theme.h"

namespace gss {

namespace {

enum class Icon { PLAY, PLAY_FROM_CURSOR, STOP };

// A square-ish button with a drawn transport icon.
bool icon_button(const char* id, Icon icon, bool primary, const char* tip, float s)
{
	if (primary) {
		ImGui::PushStyleColor(ImGuiCol_Button, theme::v4(theme::AMBER));
		ImGui::PushStyleColor(ImGuiCol_ButtonHovered, theme::v4(theme::rgb(0xf7, 0xc2, 0x7a)));
		ImGui::PushStyleColor(ImGuiCol_ButtonActive, theme::v4(theme::rgb(0xe0, 0x9c, 0x42)));
	}
	const bool pressed = ImGui::Button(id, ImVec2(44 * s, 34 * s));
	if (primary) ImGui::PopStyleColor(3);

	const ImVec2 a = ImGui::GetItemRectMin(), b = ImGui::GetItemRectMax();
	const ImVec2 c((a.x + b.x) / 2, (a.y + b.y) / 2);
	const ImU32 col = primary ? theme::ON_AMBER : theme::TEXT;
	ImDrawList* dl = ImGui::GetWindowDrawList();
	const float r = 6 * s;
	switch (icon) {
	case Icon::PLAY:
		dl->AddTriangleFilled(ImVec2(c.x - r * 0.7f, c.y - r), ImVec2(c.x - r * 0.7f, c.y + r), ImVec2(c.x + r, c.y), col);
		break;
	case Icon::PLAY_FROM_CURSOR:
		dl->AddLine(ImVec2(c.x - r * 1.2f, c.y - r), ImVec2(c.x - r * 1.2f, c.y + r), col, 1.6f * s);
		dl->AddTriangleFilled(ImVec2(c.x - r * 0.5f, c.y - r), ImVec2(c.x - r * 0.5f, c.y + r), ImVec2(c.x + r * 1.1f, c.y), col);
		break;
	case Icon::STOP:
		dl->AddRectFilled(ImVec2(c.x - r * 0.85f, c.y - r * 0.85f), ImVec2(c.x + r * 0.85f, c.y + r * 0.85f), col, 1.5f * s);
		break;
	}
	if (ImGui::IsItemHovered()) ImGui::SetTooltip("%s", tip);
	return pressed;
}

// "Label  [-] value [+]"
void stepper(const char* label, const char* id, int& value, int lo, int hi, float s)
{
	ImGui::AlignTextToFramePadding();
	ImGui::TextColored(theme::v4(theme::MUTED), "%s", label);
	ImGui::SameLine();
	ImGui::PushID(id);
	ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(4 * s, 0));
	if (ImGui::Button("-", ImVec2(28 * s, 0)) && value > lo) --value;
	ImGui::SameLine();
	char buf[8];
	std::snprintf(buf, sizeof(buf), "%d", value);
	ImGui::PushStyleColor(ImGuiCol_Button, theme::v4(theme::BG));
	ImGui::PushStyleColor(ImGuiCol_ButtonHovered, theme::v4(theme::BG));
	ImGui::PushStyleColor(ImGuiCol_ButtonActive, theme::v4(theme::BG));
	ImGui::Button(buf, ImVec2(30 * s, 0));  // the value, as a flat label
	ImGui::PopStyleColor(3);
	ImGui::SameLine();
	if (ImGui::Button("+", ImVec2(28 * s, 0)) && value < hi) ++value;
	ImGui::PopStyleVar();
	ImGui::PopID();
}

void section_heading(const char* text)
{
	ImGui::PushStyleColor(ImGuiCol_Text, theme::v4(theme::MUTED));
	ImGui::TextUnformatted(text);
	ImGui::PopStyleColor();
}

// The song list shows every slot up to the last one in use (or the current
// song), so song numbers never shift, then one slot to start a new song.
int song_list_end(const Module& m, int song_cur)
{
	int last = song_cur;
	for (int i = MAX_SONGS - 1; i > last; --i)
		if (song_used(m.songs[i])) {
			last = i;
			break;
		}
	return last + 1 < MAX_SONGS ? last + 1 : MAX_SONGS - 1;  // index of the "new song" slot
}

}  // namespace

void App::mark_dirty()
{
	stats_dirty_ = true;
	dirty_at_ = SDL_GetTicks();
	live_.dirty = true;  // a playing song picks the change up
}

void App::refresh_stats()
{
	// What the original's Info page did on entry: sizes of every song, then
	// the current song with the sound effects, as exported.
	compiler_.compile_all_songs(*module_);
	compiler_.spc_compile(*module_, editor_->song(), 0, false, true, -1);
	stats_dirty_ = false;
}

void App::clear_song_at(int i)
{
	char text[160];
	std::snprintf(text, sizeof(text), "Clear song %02d \"%s\"? Its notes, name and settings will be lost.", i + 1,
	              module_->songs[i].name.c_str());
	confirm(text, [this, i] {
		stop();
		if (i == editor_->song_cur) editor_->clear_song(i);  // also resets the cursor and undo
		else module_->songs[i] = Song();
		mark_dirty();
	});
}

void App::delete_song_at(int i)
{
	char text[200];
	std::snprintf(text, sizeof(text), "Delete song %02d \"%s\"? The songs after it move up one place.", i + 1,
	              module_->songs[i].name.c_str());
	confirm(text, [this, i] {
		stop();
		delete_song(*module_, i);
		int cur = editor_->song_cur;
		if (cur > i) --cur;  // the current song keeps its data, one slot up
		editor_->change_song(cur);
		if (cur == i) editor_->reset_view();  // the current song was the one deleted
		mark_dirty();
	});
}

void App::clear_instrument_at(int i)
{
	char text[160];
	std::snprintf(text, sizeof(text), "Clear instrument %02d \"%s\"? Its sample and settings will be lost.", i + 1,
	              module_->instruments[i].name.c_str());
	confirm(text, [this, i] {
		stop();
		clear_instrument(i);
	});
}

void App::delete_instrument_at(int i)
{
	const int uses = instrument_uses(*module_, i);
	char text[320];
	int n = std::snprintf(text, sizeof(text), "Delete instrument %02d \"%s\"? The instruments after it move up one place.",
	                      i + 1, module_->instruments[i].name.c_str());
	if (uses > 0 && n > 0 && n < (int)sizeof(text))
		std::snprintf(text + n, sizeof(text) - n, "\n%d note%s using it will lose their instrument number.", uses,
		              uses == 1 ? "" : "s");
	confirm(text, [this, i] {
		stop();
		delete_instrument(*module_, i);
		if (editor_->ins_cur > i) --editor_->ins_cur;  // the selected instrument keeps its data, one slot up
		editor_->reset_undo();  // the undo copy still has the old numbers
		samples_changed();
	});
}

void App::draw_transport()
{
	SongEditor& ed = *editor_;
	const float s = ui_scale_;

	if (icon_button("##play", Icon::PLAY, true, "Play from start (F5)", s)) play_current_song(0);
	ImGui::SameLine();
	if (icon_button("##playcur", Icon::PLAY_FROM_CURSOR, false, "Play from cursor (F7, or hold Enter)", s))
		play_current_song(ed.row_cur);
	ImGui::SameLine();
	if (icon_button("##stop", Icon::STOP, false, "Stop (F8)", s)) stop();

	ImGui::SameLine(0, 14 * s);
	ImGui::AlignTextToFramePadding();
	const int d = song_duration_seconds(ed.song());
	ImGui::TextColored(theme::v4(player_->playing() ? theme::GREEN : theme::FAINT), "%s", player_->playing() ? "Playing" : "Stopped");
	ImGui::SameLine();
	ImGui::TextColored(theme::v4(theme::MUTED), "%dm%02ds", d / 60, d % 60);

	ImGui::SameLine(0, 22 * s);
	stepper("Octave", "octave", ed.octave, 1, 8, s);
	ImGui::SameLine(0, 16 * s);
	stepper("Step", "step", ed.auto_step, 0, 16, s);
	ImGui::SameLine(0, 16 * s);
	int measure = ed.song().measure;
	stepper("Measure", "measure", measure, 2, 16, s);
	if (measure != ed.song().measure) ed.song().measure = measure;

	// right-aligned: the output monitor (levels), Memory, then Export. The
	// monitor takes the room left, up to its full width, and gives way to
	// the controls when there's too little (a narrow window, a big zoom).
	const float button_w = 90 * s, gap = ImGui::GetStyle().ItemSpacing.x;
	ImGui::SameLine(0, 16 * s);
	const float left_end = ImGui::GetCursorPosX();
	const float buttons_x = ImGui::GetWindowContentRegionMax().x - button_w * 2 - gap;
	const float monitor_w = std::min(180 * s, buttons_x - gap - 12 * s - left_end);
	if (monitor_w >= 60 * s) {
		ImGui::SameLine(buttons_x - gap - 12 * s - monitor_w);
		draw_output_monitor(monitor_w, 34 * s);
		ImGui::SameLine(0, gap + 12 * s);
	} else {
		ImGui::SameLine(std::max(left_end, buttons_x));
	}
	const bool memory_shown = tab_ == TAB_INFO;
	if (memory_shown) ImGui::PushStyleColor(ImGuiCol_Text, theme::v4(theme::AMBER));
	if (ImGui::Button("Memory", ImVec2(button_w, 34 * s))) select_tab(TAB_INFO);
	if (memory_shown) ImGui::PopStyleColor();
	if (ImGui::IsItemHovered()) ImGui::SetTooltip("SPC700 memory use (F4)");
	ImGui::SameLine();
	if (ImGui::Button("Export", ImVec2(button_w, 34 * s))) show_file_dialog(FileDialog::EXPORT_DIR);
}

void App::draw_sidebar()
{
	SongEditor& ed = *editor_;
	const float s = ui_scale_;
	const float avail = ImGui::GetContentRegionAvail().y;

	// --- songs ---
	section_heading("SONGS");
	// every slot up to the last song in use, then one slot for a new song
	const int new_song = song_list_end(*module_, ed.song_cur);

	int move_from = -1, move_to = -1;  // a drag and drop, applied after the list is drawn

	ImGui::BeginChild("songs", ImVec2(0, avail * 0.36f), ImGuiChildFlags_None);
	for (int i = 0; i <= new_song; ++i) {
		const Song& song = module_->songs[i];
		const bool empty = !song_used(song) && i != ed.song_cur;
		const bool is_new = i == new_song && i != ed.song_cur && !song_used(song);
		char id[32];
		std::snprintf(id, sizeof(id), "##song%d", i);
		ImGui::PushStyleColor(ImGuiCol_Text, theme::v4(empty ? theme::EMPTY : theme::TEXT));
		const bool clicked = ImGui::Selectable(id, i == ed.song_cur, ImGuiSelectableFlags_AllowDoubleClick, ImVec2(0, 24 * s));
		ImGui::PopStyleColor();
		const ImVec2 a = ImGui::GetItemRectMin(), b = ImGui::GetItemRectMax();
		ImDrawList* dl = ImGui::GetWindowDrawList();
		const float ty = a.y + (b.y - a.y - ImGui::GetTextLineHeight()) / 2;
		char num[16];
		std::snprintf(num, sizeof(num), "%02d", i + 1);
		dl->AddText(ImVec2(a.x + 6 * s, ty), theme::FAINT, num);
		dl->AddText(ImVec2(a.x + 32 * s, ty), empty ? theme::EMPTY : theme::TEXT, is_new ? "+ new song" : song.name.c_str());
		float right = b.x - 6 * s;
		if (song.compiled_size > 1) {
			char size[16];
			std::snprintf(size, sizeof(size), "%d", song.compiled_size);
			right -= ImGui::CalcTextSize(size).x;
			dl->AddText(ImVec2(right, ty), theme::FAINT, size);
			right -= 8 * s;
		}
		if (song.effect) {
			const float w = ImGui::CalcTextSize("SFX").x + 10 * s;
			dl->AddRectFilled(ImVec2(right - w, ty - 1), ImVec2(right, ty + ImGui::GetTextLineHeight() + 1), theme::rgb(0x1f, 0x3a, 0x2b), 4 * s);
			dl->AddText(ImVec2(right - w + 5 * s, ty), theme::GREEN, "SFX");
		}
		// right click: Clear or Delete
		if (!is_new && ImGui::BeginPopupContextItem()) {
			ImGui::TextDisabled("%02d  %s", i + 1, song.name.c_str());
			ImGui::Separator();
			if (ImGui::MenuItem("Clear")) clear_song_at(i);
			if (ImGui::MenuItem("Delete")) delete_song_at(i);
			ImGui::EndPopup();
		}

		// drag a song onto another position to move it there
		if (!is_new && ImGui::BeginDragDropSource()) {
			ImGui::SetDragDropPayload("GSS_SONG", &i, sizeof(i));
			ImGui::Text("%02d  %s", i + 1, song.name.c_str());
			ImGui::EndDragDropSource();
		}
		if (ImGui::BeginDragDropTarget()) {
			const ImGuiPayload* p = ImGui::AcceptDragDropPayload("GSS_SONG", ImGuiDragDropFlags_AcceptBeforeDelivery | ImGuiDragDropFlags_AcceptNoDrawDefaultRect);
			if (p) {
				const int from = *(const int*)p->Data;
				if (from != i) {  // a line where the song will land: above when moving up, below when moving down
					const float y = from > i ? a.y : b.y;
					dl->AddLine(ImVec2(a.x, y), ImVec2(b.x, y), theme::AMBER, 2 * s);
				}
				if (p->IsDelivery()) {
					move_from = from;
					move_to = i;
				}
			}
			ImGui::EndDragDropTarget();
		}

		if (clicked) {
			if (i != ed.song_cur) {
				stop();
				ed.change_song(i);
			}
			select_tab(TAB_SONG);  // show the song in the pattern view
			if (ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) play_current_song(0, false);
		}
	}
	ImGui::EndChild();

	if (move_from >= 0 && move_to >= 0 && move_from != move_to) {
		// move, shifting the songs in between, and keep the moved song selected
		stop();
		Song* songs = module_->songs;
		if (move_from < move_to) std::rotate(songs + move_from, songs + move_from + 1, songs + move_to + 1);
		else std::rotate(songs + move_to, songs + move_from, songs + move_from + 1);
		ed.change_song(move_to);
		select_tab(TAB_SONG);
		mark_dirty();
	}

	ImGui::Spacing();
	ImGui::Separator();
	ImGui::Spacing();

	// --- instruments ---
	section_heading("INSTRUMENTS");

	int total = 0;
	for (const Instrument& ins : module_->instruments) total += brr_size_estimate(ins, false);

	// Like the song list: every slot up to the last instrument with a sample
	// (or the current slot), so slot numbers never shift, then one free slot.
	// Clicking the free slot selects it, which adds the next free slot below.
	int free_slot = ed.ins_cur;
	for (int i = MAX_INSTRUMENTS - 1; i > free_slot; --i)
		if (module_->instruments[i].has_source()) {
			free_slot = i;
			break;
		}
	if (free_slot + 1 < MAX_INSTRUMENTS) ++free_slot;

	int ins_from = -1, ins_to = -1;  // a drag and drop, applied after the list is drawn

	ImGui::BeginChild("instruments", ImVec2(0, 0), ImGuiChildFlags_None);
	for (int i = 0; i <= free_slot; ++i) {
		const Instrument& ins = module_->instruments[i];
		const bool has = ins.has_source();
		const bool is_free = i == free_slot && i != ed.ins_cur && !has;
		char id[32];
		std::snprintf(id, sizeof(id), "##ins%d", i);
		const bool clicked = ImGui::Selectable(id, i == ed.ins_cur, ImGuiSelectableFlags_AllowDoubleClick, ImVec2(0, (has ? 32 : 24) * s));
		const ImVec2 a = ImGui::GetItemRectMin(), b = ImGui::GetItemRectMax();
		ImDrawList* dl = ImGui::GetWindowDrawList();
		const float ty = a.y + 4 * s;
		char num[16];
		std::snprintf(num, sizeof(num), "%02d", i + 1);
		const bool lit = has || i == ed.ins_cur;  // empty slots are dimmed unless selected
		dl->AddText(ImVec2(a.x + 6 * s, ty), has ? theme::AMBER : lit ? theme::FAINT : theme::EMPTY, num);
		dl->AddText(ImVec2(a.x + 32 * s, ty), lit ? theme::TEXT : theme::EMPTY, is_free ? "+ free slot" : ins.name.c_str());
		if (has && total > 0) {  // share of all sample data
			const float y = b.y - 7 * s;
			const float x0 = a.x + 32 * s, x1 = b.x - 8 * s;
			dl->AddRectFilled(ImVec2(x0, y), ImVec2(x1, y + 3 * s), theme::CONTROL, 2 * s);
			const float share = (float)brr_size_estimate(ins, false) / (float)total;
			dl->AddRectFilled(ImVec2(x0, y), ImVec2(x0 + (x1 - x0) * share, y + 3 * s), theme::AMBER, 2 * s);
		}
		// right click: Clear or Delete
		if (!is_free && ImGui::BeginPopupContextItem()) {
			ImGui::TextDisabled("%02d  %s", i + 1, ins.name.c_str());
			ImGui::Separator();
			if (ImGui::MenuItem("Clear")) clear_instrument_at(i);
			if (ImGui::MenuItem("Delete")) delete_instrument_at(i);
			ImGui::EndPopup();
		}

		// drag an instrument onto another slot to move it there
		if (has && ImGui::BeginDragDropSource()) {
			ImGui::SetDragDropPayload("GSS_INSTRUMENT", &i, sizeof(i));
			ImGui::Text("%02d  %s", i + 1, ins.name.c_str());
			ImGui::EndDragDropSource();
		}
		if (ImGui::BeginDragDropTarget()) {
			const ImGuiPayload* p = ImGui::AcceptDragDropPayload("GSS_INSTRUMENT", ImGuiDragDropFlags_AcceptBeforeDelivery | ImGuiDragDropFlags_AcceptNoDrawDefaultRect);
			if (p) {
				const int from = *(const int*)p->Data;
				if (from != i) {
					const float y = from > i ? a.y : b.y;
					dl->AddLine(ImVec2(a.x, y), ImVec2(b.x, y), theme::AMBER, 2 * s);
				}
				if (p->IsDelivery()) {
					ins_from = from;
					ins_to = i;
				}
			}
			ImGui::EndDragDropTarget();
		}

		if (clicked) {
			ed.ins_cur = i;
			select_tab(TAB_INSTRUMENTS);  // show the instrument in the instrument editor
			if (ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) play_note(2 + 12 * 5, i);
		}
	}
	ImGui::EndChild();

	if (ins_from >= 0 && ins_to >= 0 && ins_from != ins_to) {
		stop();
		move_instrument(ins_from, ins_to);
		select_tab(TAB_INSTRUMENTS);
	}
}

void App::update_output_monitor()
{
	// every 25 ms, like the original's monitor timer
	const Uint64 now = SDL_GetTicks();
	if (now < monitor_tick_ + 25) return;
	monitor_tick_ = now;

	out_l_ = player_->peak_left();
	out_r_ = player_->peak_right();
	peak_l_ = out_l_ > peak_l_ ? out_l_ : (peak_l_ > 512 ? peak_l_ - 512 : 0);
	peak_r_ = out_r_ > peak_r_ ? out_r_ : (peak_r_ > 512 ? peak_r_ - 512 : 0);
}

void App::draw_output_monitor(float width, float height)
{
	const float s = ui_scale_;
	const ImVec2 p = ImGui::GetCursorScreenPos();
	ImGui::Dummy(ImVec2(width, height));
	if (ImGui::IsItemHovered()) ImGui::SetTooltip("Output monitor: left and right levels");

	ImDrawList* dl = ImGui::GetWindowDrawList();
	dl->AddRectFilled(p, ImVec2(p.x + width, p.y + height), theme::BG, 6 * s);

	// two level bars with peak markers, as the original drew them
	const float pad = 6 * s, label_w = 12 * s;
	const float bar_x = p.x + pad + label_w, bar_w = width - pad * 2 - label_w;
	const float bar_h = (height - pad * 2 - 4 * s) / 2;
	auto bar = [&](float y, const char* label, int out, int peak) {
		dl->AddText(ImVec2(p.x + pad, y + (bar_h - ImGui::GetTextLineHeight()) / 2), theme::FAINT, label);
		dl->AddRectFilled(ImVec2(bar_x, y), ImVec2(bar_x + bar_w, y + bar_h), theme::rgb(0x1c, 0x22, 0x2e), 2 * s);
		const float w = bar_w * (float)out / 32768.0f;
		dl->AddRectFilled(ImVec2(bar_x, y), ImVec2(bar_x + w, y + bar_h), theme::GREEN, 2 * s);
		float px = bar_x + bar_w * (float)peak / 32768.0f;
		if (px < bar_x + 1) px = bar_x + 1;
		if (px > bar_x + bar_w - 2) px = bar_x + bar_w - 2;
		if (peak > 0) dl->AddRectFilled(ImVec2(px - 1 * s, y), ImVec2(px + 1 * s, y + bar_h), theme::AMBER);
	};
	bar(p.y + pad, "L", out_l_, peak_l_);
	bar(p.y + pad + bar_h + 4 * s, "R", out_r_, peak_r_);
}

void App::draw_status_bar()
{
	const CompileStats& st = compiler_.stats();
	const float s = ui_scale_;
	const int stream = BRR_STREAM_BUFFER_SIZE;
	const int free = 65536 - 512 - st.driver_size - st.instruments_size - st.music_size - st.effects_size - stream;

	ImGui::AlignTextToFramePadding();
	section_heading("SPC700 RAM");
	ImGui::SameLine();

	// the meter
	char free_text[48];
	std::snprintf(free_text, sizeof(free_text), "%d B free", free);
	const float legend_w = 620 * s;
	const float meter_w = ImGui::GetContentRegionAvail().x - legend_w - ImGui::CalcTextSize(free_text).x - 24 * s;
	const ImVec2 p = ImGui::GetCursorScreenPos();
	const float h = 14 * s;
	const float y = p.y + (ImGui::GetFrameHeight() - h) / 2;
	ImDrawList* dl = ImGui::GetWindowDrawList();
	if (meter_w > 40) {
		dl->AddRectFilled(ImVec2(p.x, y), ImVec2(p.x + meter_w, y + h), theme::rgb(0x1a, 0x1f, 0x2a), 4 * s);
		const std::pair<ImU32, int> parts[] = {
			{theme::rgb(0x3b, 0x45, 0x58), 512}, {theme::BLUE, st.driver_size}, {theme::AMBER, st.instruments_size},
			{theme::GREEN, st.effects_size}, {theme::LILAC, st.music_size}};
		float x = p.x;
		for (const auto& part : parts) {
			const float w = meter_w * (float)part.second / 65536.0f;
			dl->AddRectFilled(ImVec2(x, y), ImVec2(x + w, y + h), part.first);
			x += w;
		}
		const float sw = meter_w * (float)stream / 65536.0f;
		dl->AddRectFilled(ImVec2(p.x + meter_w - sw, y), ImVec2(p.x + meter_w, y + h), theme::rgb(0x4a, 0x52, 0x66));
		ImGui::Dummy(ImVec2(meter_w, ImGui::GetFrameHeight()));
		if (ImGui::IsItemHovered()) ImGui::SetTooltip("Memory detail: F4");
		ImGui::SameLine(0, 16 * s);
	}

	auto legend = [&](ImU32 c, const char* text) {
		const ImVec2 q = ImGui::GetCursorScreenPos();
		const float b = 8 * s;
		const float by = q.y + (ImGui::GetFrameHeight() - b) / 2;
		dl->AddRectFilled(ImVec2(q.x, by), ImVec2(q.x + b, by + b), c, 2 * s);
		ImGui::Dummy(ImVec2(b + 4 * s, ImGui::GetFrameHeight()));
		ImGui::SameLine(0, 0);
		ImGui::TextColored(theme::v4(theme::MUTED), "%s", text);
		ImGui::SameLine(0, 14 * s);
	};
	char t[64];
	std::snprintf(t, sizeof(t), "Driver %d", st.driver_size);
	legend(theme::BLUE, t);
	std::snprintf(t, sizeof(t), "Samples %d", st.instruments_size);
	legend(theme::AMBER, t);
	std::snprintf(t, sizeof(t), "Effects %d", st.effects_size);
	legend(theme::GREEN, t);
	std::snprintf(t, sizeof(t), "Music %d (largest %d)", st.music_size, st.music_largest);
	legend(theme::LILAC, t);

	ImGui::TextColored(theme::v4(free < 0 ? theme::rgb(0xff, 0x7a, 0x6e) : theme::TEXT), "%s", free_text);
}

void App::draw_workspace()
{
	const float s = ui_scale_;
	const ImGuiViewport* vp = ImGui::GetMainViewport();
	ImGui::SetNextWindowPos(vp->WorkPos);
	ImGui::SetNextWindowSize(vp->WorkSize);
	ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
	ImGui::Begin("workspace", nullptr,
	             ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings |
	                 ImGuiWindowFlags_NoBringToFrontOnFocus);
	// Tab moves between channels in the pattern, so it must not also move
	// keyboard focus into a text field (which would then take the note keys)
	ImGui::PushItemFlag(ImGuiItemFlags_NoTabStop, true);
	ImGui::PopStyleVar();

	const ImVec2 origin = ImGui::GetCursorScreenPos();
	const ImVec2 size = ImGui::GetContentRegionAvail();
	const float transport_h = 54 * s, status_h = 40 * s;
	const float side_w = 270 * s;
	const float body_h = size.y - transport_h - status_h;
	const float center_w = size.x - side_w;

	auto region = [&](const char* id, ImVec2 pos, ImVec2 sz, ImU32 bg, ImVec2 padding) {
		ImGui::SetCursorScreenPos(pos);
		ImGui::PushStyleColor(ImGuiCol_ChildBg, theme::v4(bg));
		ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, padding);
		ImGui::PushStyleVar(ImGuiStyleVar_ChildRounding, 0);
		ImGui::BeginChild(id, sz, ImGuiChildFlags_AlwaysUseWindowPadding);
		ImGui::PopStyleVar(2);
		ImGui::PopStyleColor();
	};

	region("transport", origin, ImVec2(size.x, transport_h), theme::BAR, ImVec2(14 * s, 10 * s));
	draw_transport();
	ImGui::EndChild();

	const float body_y = origin.y + transport_h;
	region("sidebar", ImVec2(origin.x, body_y), ImVec2(side_w, body_h), theme::PANEL, ImVec2(12 * s, 12 * s));
	draw_sidebar();
	ImGui::EndChild();

	if (center_w > 100) {
		region("center", ImVec2(origin.x + side_w, body_y), ImVec2(center_w, body_h), theme::BG, ImVec2(12 * s, 8 * s));
		draw_center();
		ImGui::EndChild();
	}

	region("status", ImVec2(origin.x, origin.y + size.y - status_h), ImVec2(size.x, status_h), theme::BAR, ImVec2(14 * s, 6 * s));
	draw_status_bar();
	ImGui::EndChild();

	// dividers between the regions
	ImDrawList* dl = ImGui::GetWindowDrawList();
	dl->AddLine(ImVec2(origin.x, body_y), ImVec2(origin.x + size.x, body_y), theme::BORDER);
	dl->AddLine(ImVec2(origin.x, body_y + body_h), ImVec2(origin.x + size.x, body_y + body_h), theme::BORDER);
	dl->AddLine(ImVec2(origin.x + side_w, body_y), ImVec2(origin.x + side_w, body_y + body_h), theme::BORDER);

	ImGui::PopItemFlag();
	ImGui::End();
}

void App::draw_center()
{
	// one view at a time, chosen by the sidebar, the Memory button or F1, F3, F4
	if (tab_requested_) {
		if (tab_ != tab_request_) mark_dirty();
		tab_ = tab_request_;
		tab_requested_ = false;
	}

	switch (tab_) {
	case TAB_SONG: draw_song_view(); break;
	case TAB_INSTRUMENTS: draw_instruments(); break;
	case TAB_INFO: draw_info(); break;
	}
}

}  // namespace gss
