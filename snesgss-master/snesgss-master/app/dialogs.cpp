// Dialogs replacing the original's VCL forms (UnitTranspose, UnitReplace,
// UnitSectionList, UnitSectionName, UnitSubSong) and message boxes.
#include <cstdio>
#include <memory>

#include "app.h"
#include "imgui.h"
#include "importers.h"
#include "modal.h"
#include "song.h"

namespace gss {

namespace {

// Scope radio buttons shared by the transpose, scale volume and replace
// dialogs. Like the VCL forms, the choice persists between uses.
enum Scope { ALL_SONGS, CURRENT_SONG, CURRENT_CHANNEL, BLOCK };

void scope_radios(int& scope)
{
	ImGui::SeparatorText("Location");
	ImGui::RadioButton("All songs", &scope, ALL_SONGS);
	ImGui::RadioButton("Current song only", &scope, CURRENT_SONG);
	ImGui::RadioButton("Current channel only", &scope, CURRENT_CHANNEL);
	ImGui::RadioButton("Block selection only", &scope, BLOCK);
}

bool ok_cancel(const char* ok_label, bool& ok)
{
	ImGui::Spacing();
	if (ImGui::Button(ok_label, ImVec2(100, 0)) || ImGui::IsKeyPressed(ImGuiKey_Enter) ||
	    ImGui::IsKeyPressed(ImGuiKey_KeypadEnter)) {
		ok = true;
		return false;
	}
	ImGui::SameLine();
	if (ImGui::Button("Cancel", ImVec2(100, 0)) || ImGui::IsKeyPressed(ImGuiKey_Escape)) return false;
	return true;
}

}  // namespace

void App::push_modal(std::unique_ptr<Modal> m) { modals_.push_back(std::move(m)); }

void App::confirm(const std::string& text, std::function<void()> on_yes)
{
	auto m = std::make_unique<Modal>();
	m->title = "Confirm";
	m->body = [text, on_yes] {
		ImGui::TextUnformatted(text.c_str());
		ImGui::Spacing();
		if (ImGui::Button("Yes", ImVec2(100, 0)) || ImGui::IsKeyPressed(ImGuiKey_Enter)) {
			on_yes();
			return false;
		}
		ImGui::SameLine();
		return !(ImGui::Button("No", ImVec2(100, 0)) || ImGui::IsKeyPressed(ImGuiKey_Escape));
	};
	push_modal(std::move(m));
}

void App::message(const std::string& text)
{
	auto m = std::make_unique<Modal>();
	m->title = "SNES GSS";
	m->body = [text] {
		ImGui::TextUnformatted(text.c_str());
		ImGui::Spacing();
		return !(ImGui::Button("OK", ImVec2(100, 0)) || ImGui::IsKeyPressed(ImGuiKey_Enter) ||
		         ImGui::IsKeyPressed(ImGuiKey_Escape));
	};
	push_modal(std::move(m));
}

void App::open_transpose_dialog(bool scale_volume)
{
	static int scope = BLOCK;
	static int all_instruments = 1;

	auto value = std::make_shared<int>(scale_volume ? 100 : 0);
	auto m = std::make_unique<Modal>();
	m->title = scale_volume ? "Scale volume" : "Transpose";
	m->body = [this, scale_volume, value] {
		ImGui::SetNextItemWidth(120);
		ImGui::InputInt(scale_volume ? "Percents" : "Semitones", value.get());
		const int lo = scale_volume ? 0 : -96, hi = scale_volume ? 1000 : 96;
		if (*value < lo) *value = lo;
		if (*value > hi) *value = hi;

		scope_radios(scope);

		ImGui::SeparatorText("Instrument");
		ImGui::RadioButton("All instruments", &all_instruments, 1);
		char cur[64];
		std::snprintf(cur, sizeof(cur), "Current instrument (%d)", editor_->ins_cur + 1);
		ImGui::RadioButton(cur, &all_instruments, 0);

		bool ok = false;
		const bool open = ok_cancel("OK", ok);
		if (ok) {
			const int ins = all_instruments ? 0 : editor_->ins_cur + 1;
			if (scale_volume)
				editor_->scale_volume(*value, scope == BLOCK, scope == CURRENT_SONG, scope == CURRENT_CHANNEL, ins);
			else
				editor_->transpose(*value, scope == BLOCK, scope == CURRENT_SONG, scope == CURRENT_CHANNEL, ins);
		}
		return open;
	};
	push_modal(std::move(m));
}

void App::open_replace_dialog()
{
	static int scope = BLOCK;
	static int from = 1;

	auto to = std::make_shared<int>(editor_->ins_cur + 1);
	auto m = std::make_unique<Modal>();
	m->title = "Replace instrument";
	m->body = [this, to] {
		ImGui::SetNextItemWidth(120);
		ImGui::InputInt("From", &from);
		ImGui::SetNextItemWidth(120);
		ImGui::InputInt("To", to.get());
		if (from < 1) from = 1;
		if (from > 99) from = 99;
		if (*to < 1) *to = 1;
		if (*to > 99) *to = 99;

		scope_radios(scope);

		bool ok = false;
		const bool open = ok_cancel("Replace", ok);
		if (ok) editor_->replace_instrument(scope == BLOCK, scope == CURRENT_SONG, scope == CURRENT_CHANNEL, from, *to);
		return open;
	};
	push_modal(std::move(m));
}

void App::open_section_list()
{
	auto list = std::make_shared<std::vector<SongEditor::SectionEntry>>(editor_->section_list());
	auto selected = std::make_shared<int>(-1);
	for (size_t i = 0; i < list->size(); ++i)
		if ((*list)[i].row <= editor_->row_cur) *selected = (int)i;

	auto m = std::make_unique<Modal>();
	m->title = "Sections";
	m->body = [this, list, selected] {
		bool chosen = false;
		ImGui::PushFont(pattern_font_, pattern_font_size_);
		if (ImGui::BeginListBox("##sections", ImVec2(420, 360))) {
			for (size_t i = 0; i < list->size(); ++i) {
				const bool sel = (int)i == *selected;
				if (ImGui::Selectable((*list)[i].label.c_str(), sel, ImGuiSelectableFlags_AllowDoubleClick)) {
					*selected = (int)i;
					if (ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) chosen = true;
				}
				if (sel && ImGui::IsWindowAppearing()) ImGui::SetScrollHereY();
			}
			ImGui::EndListBox();
		}
		ImGui::PopFont();

		if (ImGui::IsKeyPressed(ImGuiKey_UpArrow) && *selected > 0) --*selected;
		if (ImGui::IsKeyPressed(ImGuiKey_DownArrow) && *selected + 1 < (int)list->size()) ++*selected;
		if (ImGui::IsKeyPressed(ImGuiKey_Enter) || ImGui::IsKeyPressed(ImGuiKey_KeypadEnter)) chosen = true;

		if (chosen && *selected >= 0) {
			editor_->move_cursor((*list)[*selected].row, 0, false);
			return false;
		}
		return !ImGui::IsKeyPressed(ImGuiKey_Escape);
	};
	push_modal(std::move(m));
}

void App::open_section_name()
{
	const int row = editor_->row_cur;
	auto name = std::make_shared<std::string>(editor_->section_name(row));
	name->resize(256);

	auto m = std::make_unique<Modal>();
	m->title = "Section name";
	m->body = [this, row, name] {
		if (ImGui::IsWindowAppearing()) ImGui::SetKeyboardFocusHere();
		ImGui::SetNextItemWidth(300);
		const bool enter = ImGui::InputText("##name", name->data(), name->size(), ImGuiInputTextFlags_EnterReturnsTrue);
		if (enter) {
			editor_->set_section_name(row, std::string(name->c_str()));
			return false;
		}
		return !ImGui::IsKeyPressed(ImGuiKey_Escape);
	};
	push_modal(std::move(m));
}

void App::open_subsong_dialog(std::string ftm_data, std::string file_stem)
{
	static int subsong = 1;

	auto data = std::make_shared<std::string>(std::move(ftm_data));
	auto m = std::make_unique<Modal>();
	m->title = "FamiTracker text import";
	m->body = [this, data, file_stem] {
		ImGui::SetNextItemWidth(120);
		ImGui::InputInt("Sub song number", &subsong);
		if (subsong < 1) subsong = 1;
		if (subsong > 255) subsong = 255;

		bool ok = false;
		const bool open = ok_cancel("Import", ok);
		if (ok) {
			// named after the file, and with several sub songs the track's
			// name (or number), which a second import of it replaces
			const std::vector<std::string> tracks = famitracker_track_names(*data);
			std::string name = file_stem;
			if (tracks.size() > 1) {
				const std::string track = subsong <= (int)tracks.size() ? tracks[(size_t)subsong - 1] : "";
				name += " - " + (track.empty() ? std::to_string(subsong) : track);
			}
			bool replacing = false;
			const int target = import_song_slot(name, &replacing);
			if (target >= 0) {
				std::string error;
				if (import_famitracker_text(*data, subsong, *module_, target, &error)) finish_song_import(target, name, replacing);
				else message(error);
				editor_->reset_undo();
				compiler_.compile_all_songs(*module_);
			}
		}
		return open;
	};
	push_modal(std::move(m));
}

void App::draw_dialogs()
{
	if (modals_.empty()) return;

	Modal& m = *modals_.front();
	const std::string id = m.title + "###modal";

	if (!m.opened) {
		ImGui::OpenPopup(id.c_str());
		m.opened = true;
	}

	ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
	bool keep = true;
	if (ImGui::BeginPopupModal(id.c_str(), nullptr, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoSavedSettings)) {
		keep = m.body();
		if (!keep) ImGui::CloseCurrentPopup();
		ImGui::EndPopup();
	} else {
		keep = false;
	}

	if (!keep) modals_.erase(modals_.begin());
}

}  // namespace gss
