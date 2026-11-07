// Instrument editor (F3).
#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>

#include "app.h"
#include "brr.h"
#include "imgui.h"
#include "instrument_preview.h"
#include "modal.h"
#include "song.h"
#include "theme.h"
#include "widgets.h"

namespace gss {

void App::clear_instrument(int i)
{
	Instrument& ins = module_->instruments[i];
	// InstrumentClear() left the ramp and unroll flags as they were
	const bool ramp = ins.ramp_enable, unroll = ins.loop_unroll;
	ins = Instrument();
	ins.ramp_enable = ramp;
	ins.loop_unroll = unroll;
	samples_changed();
}

void App::move_instrument(int from, int to)
{
	gss::move_instrument(*module_, from, to);
	editor_->ins_cur = to;
	editor_->reset_undo();  // the undo copy still has the old numbers
	samples_changed();
}

void App::cleanup_instruments()
{
	bool use[MAX_INSTRUMENTS + 1] = {};

	for (const Song& s : module_->songs) {
		if (!s.allocated()) continue;
		for (int row = 0; row < s.length && row < MAX_ROWS; ++row)
			for (const NoteField& n : s.row(row).chn)
				if (n.instrument <= MAX_INSTRUMENTS) use[n.instrument] = true;
	}

	// LEGACY BUG: the original checked numbers 0..98 against slots -1..97, so
	// the last slot (99) is never removed. Slot -1 was never reached, since
	// number 0 (no instrument) is always "used".
	int cnt = 0;
	for (int num = 1; num < MAX_INSTRUMENTS; ++num) {
		if (!use[num] && module_->instruments[num - 1].has_source()) {
			clear_instrument(num - 1);
			++cnt;
		}
	}

	samples_changed();
	message(std::to_string(cnt) + " instrument(s) removed");
}

// Waveform and envelope preview, as RenderADSR() drew it: 400 pixels per
// second, grey marks every 1/4 s, the source amplitude in green with the loop
// start (red) and end (blue), and the ADSR curve in lime.
namespace {

// SPC700 envelope timings in milliseconds, as the original's preview used
// them: by AR, DR and SR value; sustain_time -1 means the sound never decays.
const float attack_time[16] = {4100, 2600, 1500, 1000, 640, 380, 260, 160, 96, 64, 40, 24, 16, 10, 6, 0};
const float decay_time[8] = {1200, 740, 440, 290, 180, 110, 74, 37};
const float sustain_level[8] = {1.0f / 8, 2.0f / 8, 3.0f / 8, 4.0f / 8, 5.0f / 8, 6.0f / 8, 7.0f / 8, 1.0f};
const float sustain_time[32] = {-1, 38000, 28000, 24000, 19000, 14000, 12000, 9400, 7100, 5900, 4700,
                                3500, 2900, 2400, 1800, 1500, 1200, 880, 740, 590, 440, 370, 290, 220,
                                180, 150, 110, 92, 74, 55, 37, 18};

// "37 ms", "1.2 s"
std::string duration(float ms)
{
	char buf[32];
	if (ms < 1000) std::snprintf(buf, sizeof(buf), "%d ms", (int)ms);
	else std::snprintf(buf, sizeof(buf), "%.1f s", ms / 1000.0f);
	return buf;
}

}  // namespace

void draw_instrument_preview(const Instrument& ins, ImVec2 size)
{
	const float pps = 400;

	ImDrawList* dl = ImGui::GetWindowDrawList();
	const ImVec2 o = ImGui::GetCursorScreenPos();
	ImGui::Dummy(size);
	dl->PushClipRect(o, ImVec2(o.x + size.x, o.y + size.y), true);
	struct PopClip {
		ImDrawList* dl;
		~PopClip() { dl->PopClipRect(); }
	} pop_clip{dl};

	float w = size.x, h = size.y;
	dl->AddRectFilled(o, ImVec2(o.x + w, o.y + h), IM_COL32(0, 0, 0, 255));

	auto at = [](int v, int n) { return v < 0 ? 0 : (v >= n ? n - 1 : v); };
	const float ax = pps * (attack_time[at(ins.env_ar, 16)] / 1000.0f);
	const float dx = ax + pps * (decay_time[at(ins.env_dr, 8)] / 1000.0f);
	const float sx_t = sustain_time[at(ins.env_sr, 32)];
	w -= 4;
	h -= 4;
	const float dy = (h - 1) - (h - 2) * sustain_level[at(ins.env_sl, 8)];
	const float sx = dx + pps * (sx_t / 1000.0f);

	auto line = [&](float x1, float y1, float x2, float y2, ImU32 c, float t = 1.0f) {
		dl->AddLine(ImVec2(o.x + x1, o.y + y1), ImVec2(o.x + x2, o.y + y2), c, t);
	};

	int cnt = 0;
	for (float x = 1; x < w - 1; x += pps / 4.0f, ++cnt)
		line(x + 2, 2, x + 2, h, !(cnt & 3) ? IM_COL32(192, 192, 192, 255) : IM_COL32(0x30, 0x30, 0x30, 255));

	if (ins.has_source()) {
		const float vol = volume_scale(ins.source_volume);
		const float step = (float)ins.source_rate / pps;
		float off = 0;
		bool loops = false, loope = false;

		for (float x = 1; x < w - 1; x += 1.0f) {
			float level = 0;
			if (ins.loop_enable || off < ins.length) {
				const int i = (int)off;
				const int smp = (i >= 0 && i < (int)ins.source.size()) ? ins.source[i] : 0;
				level = (h - 2) / 32768.0f * (float)std::abs(smp) * vol;
			}
			const float y = h / 2 - level / 2;
			off += step;

			line(x + 2, y + 2, x + 2, y + level + 2, IM_COL32(0, 128, 0, 255));

			if (off >= ins.loop_start && !loops && ins.loop_enable) {
				loops = true;
				line(x + 2, 2, x + 2, h, IM_COL32(255, 0, 0, 255));
			}

			if (off >= ins.length || off >= ins.source_length || (ins.loop_enable && off >= ins.loop_end)) {
				off = ins.loop_enable ? (float)ins.loop_start : (float)ins.length;
				if (!loope && ins.loop_enable) {
					loope = true;
					line(x + 2, 2, x + 2, h, IM_COL32(0, 0, 255, 255));
				}
			}
			if (step <= 0) break;
		}
	}

	const ImU32 lime = IM_COL32(0, 255, 0, 255);
	line(3, h - 1, ax + 2, 2, lime, 2);
	line(ax + 2, 2, dx + 2, dy + 2, lime, 2);
	if (sx_t >= 0) line(dx + 2, dy + 2, sx + 2, h - 1, lime, 2);
	else line(dx + 2, dy + 2, w - 1, dy + 2, lime, 2);
}

void instrument_info(const Instrument& ins, std::string& source, std::string& brr)
{
	char wav[160], b[160];
	if (!ins.has_source()) {
		std::snprintf(wav, sizeof(wav), "Source: ---");
		std::snprintf(b, sizeof(b), "BRR: ---");
	} else {
		const int div = ins.downsample_factor == 1 ? 2 : (ins.downsample_factor == 2 ? 4 : 1);
		const int len = brr_size_estimate(ins, false);
		std::snprintf(wav, sizeof(wav), "Source: %d Hz, %d samples", ins.source_rate, ins.source_length);
		int n = std::snprintf(b, sizeof(b), "BRR: %d Hz, %d bytes", ins.source_rate / div, len);
		if (ins.loop_enable) n += std::snprintf(b + n, sizeof(b) - n, " (%d looped)", brr_size_estimate(ins, true));
		std::snprintf(b + n, sizeof(b) - n, " ~%d%%", (int)(100.0f / 65536.0f * float(len)));
	}
	size_t wl = std::strlen(wav);
	if (ins.wav_loop_start >= 0 && (ins.wav_loop_start != 0 || ins.wav_loop_end != 0))
		std::snprintf(wav + wl, sizeof(wav) - wl, " (loop %d to %d)", ins.wav_loop_start, ins.wav_loop_end);
	else
		std::snprintf(wav + wl, sizeof(wav) - wl, " (no loop)");
	source = wav;
	brr = b;
}

void App::draw_instruments()
{
	SongEditor& ed = *editor_;
	Instrument& ins = module_->instruments[ed.ins_cur];
	const float s = ui_scale_;
	const ImGuiStyle& style = ImGui::GetStyle();
	bool changed = false;

	// --- header: which instrument, and what you do with it -------------------
	ImGui::AlignTextToFramePadding();
	ImGui::TextColored(theme::v4(theme::AMBER), "%02d", ed.ins_cur + 1);
	ImGui::SameLine();
	char name[64];
	std::snprintf(name, sizeof(name), "%s", ins.name.c_str());
	ImGui::SetNextItemWidth(320 * s);
	if (ImGui::InputTextWithHint("##name", "instrument name", name, 31)) ins.name = name;  // the original held 30 characters

	{
		const char* labels[] = {"Play C-5", "Import WAV...", "Load...", "Save..."};
		float total = 0;
		for (const char* l : labels) total += ImGui::CalcTextSize(l).x + style.FramePadding.x * 2;
		total += style.ItemSpacing.x * 3;
		ImGui::SameLine(ImGui::GetContentRegionMax().x - total);

		ImGui::BeginDisabled(!ins.has_source());
		if (ImGui::Button("Play C-5")) play_note(2 + 12 * 5, ed.ins_cur);
		ImGui::EndDisabled();
		hover_tip("Preview the instrument. Note keys play it too, in the current octave.");
		ImGui::SameLine();
		if (ImGui::Button("Import WAV...")) show_file_dialog(FileDialog::IMPORT_WAV);
		hover_tip("Load a wave from WAV file. The sound should be sampled at 8000, 16000, or 32000 Hz, and tuned to B +21 cent");
		ImGui::SameLine();
		if (ImGui::Button("Load...")) show_file_dialog(FileDialog::LOAD_INSTRUMENT);
		hover_tip("Load a saved instrument (.gsi) into this slot");
		ImGui::SameLine();
		ImGui::BeginDisabled(!ins.has_source());
		if (ImGui::Button("Save...")) show_file_dialog(FileDialog::SAVE_INSTRUMENT);
		ImGui::EndDisabled();
		hover_tip("Save this instrument to a file (.gsi)");
	}
	ImGui::Spacing();

	// --- an empty slot: say what to do instead of showing settings ------------
	if (!ins.has_source()) {
		ImGui::PushStyleColor(ImGuiCol_ChildBg, theme::v4(theme::PANEL));
		ImGui::BeginChild("empty", ImVec2(0, 150 * s), ImGuiChildFlags_Borders | ImGuiChildFlags_AlwaysUseWindowPadding);
		ImGui::Dummy(ImVec2(0, 20 * s));
		ImGui::TextUnformatted("This instrument slot is empty.");
		ImGui::TextColored(theme::v4(theme::MUTED), "Import a WAV file, or load an instrument saved from SNES GSS (.gsi).");
		ImGui::Spacing();
		if (ImGui::Button("Import WAV...")) show_file_dialog(FileDialog::IMPORT_WAV);
		ImGui::SameLine();
		if (ImGui::Button("Load instrument...")) show_file_dialog(FileDialog::LOAD_INSTRUMENT);
		ImGui::EndChild();
		ImGui::PopStyleColor();
		return;
	}

	// --- what it is: the waveform with loop and envelope, then the numbers ---
	// the preview takes the room the settings cards leave
	const float line = ImGui::GetTextLineHeightWithSpacing();
	float preview_h = ImGui::GetContentRegionAvail().y - ins_cards_h_ - line - style.ItemSpacing.y * 3;
	if (preview_h < 150 * s) preview_h = 150 * s;
	draw_instrument_preview(ins, ImVec2(ImGui::GetContentRegionAvail().x, preview_h));
	{
		std::string src, brr;
		instrument_info(ins, src, brr);
		ImGui::TextColored(theme::v4(theme::MUTED), "%s", src.c_str());
		ImGui::SameLine(0, 24 * s);
		ImGui::TextColored(theme::v4(theme::MUTED), "%s", brr.c_str());
	}
	ImGui::Spacing();

	// --- how it is made, in the order the encoder works -----------------------
	const float label_w = 96 * s;
	auto label = [&](const char* text) {
		ImGui::AlignTextToFramePadding();
		ImGui::TextColored(theme::v4(theme::MUTED), "%s", text);
		ImGui::SameLine(label_w);
	};
	auto heading = [&](const char* text) {
		ImGui::TextColored(theme::v4(theme::FAINT), "%s", text);
		ImGui::Spacing();
	};
	// The cards share one height: each measures what its content needs, and
	// the next frame draws all three at the tallest of those.
	float tallest = 0;
	auto card = [&](const char* id) {
		ImGui::PushStyleColor(ImGuiCol_ChildBg, theme::v4(theme::PANEL));
		ImGui::BeginChild(id, ImVec2(0, ins_card_h_), ImGuiChildFlags_Borders | ImGuiChildFlags_AlwaysUseWindowPadding,
		                  ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
		ImGui::PopStyleColor();
	};
	auto end_card = [&]() {
		const float needed = ImGui::GetCursorPosY() - style.ItemSpacing.y + style.WindowPadding.y;
		if (needed > tallest) tallest = needed;
		ImGui::EndChild();
	};

	const float cards_top = ImGui::GetCursorPosY();
	if (ImGui::BeginTable("cards", 3, ImGuiTableFlags_SizingStretchSame)) {
		// Sample: which part of the source plays, and where it loops
		ImGui::TableNextColumn();
		card("sample");
		heading("SAMPLE");
		label("Length");
		{
			const float max_w = ImGui::CalcTextSize("Max").x + style.FramePadding.x * 2;
			ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x - max_w - style.ItemSpacing.x);
			if (ImGui::InputInt("##length", &ins.length)) {
				if (ins.length > ins.source_length) ins.length = ins.source_length;
				if (ins.length < 0) ins.length = 0;
				changed = true;
			}
			ImGui::SameLine();
			if (ImGui::Button("Max")) {
				ins.length = ins.source_length;
				changed = true;
			}
			hover_tip("Set max possible sample length");
		}
		label("Loop");
		changed |= ImGui::Checkbox("##loop", &ins.loop_enable);
		hover_tip("Enable loop");
		ImGui::SameLine();
		ImGui::BeginDisabled(ins.wav_loop_start < 0);
		if (ImGui::Button("From WAV")) {
			ins.loop_start = ins.wav_loop_start;
			ins.loop_end = ins.wav_loop_end;
			changed = true;
		}
		ImGui::EndDisabled();
		hover_tip("Take the loop points from WAV file");

		ImGui::BeginDisabled(!ins.loop_enable);  // the loop points only matter with the loop on
		// dragged like the EQ: a full drag across covers about the whole sample
		const int last = ins.source_length > 0 ? ins.source_length - 1 : 0;
		const float speed = last > 500 ? last / 500.0f : 1.0f;
		auto loop_point = [&](const char* text, const char* id, int& value, const char* tip) {
			label(text);
			ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x);
			changed |= ImGui::DragInt(id, &value, speed, 0, last, "%d", ImGuiSliderFlags_AlwaysClamp);
			hover_tip(tip);
		};
		loop_point("Start", "##loopstart", ins.loop_start,
		           "Drag with left mouse button to change the loop start; double-click to type it");
		loop_point("End", "##loopend", ins.loop_end, "Drag with left mouse button to change the loop end; double-click to type it");
		ImGui::TextColored(theme::v4(theme::FAINT), "Loop of %d samples", ins.loop_end - ins.loop_start + 1);
		ImGui::EndDisabled();
		end_card();

		// Encoding: how the source becomes BRR
		ImGui::TableNextColumn();
		card("encoding");
		heading("ENCODING");
		label("EQ");
		{
			const float reset_w = ImGui::CalcTextSize("Reset").x + style.FramePadding.x * 2;
			const float w = (ImGui::GetContentRegionAvail().x - reset_w - style.ItemSpacing.x * 3) / 3;
			const char* eq_tip = "Drag with left mouse button to change EQ settings";
			ImGui::SetNextItemWidth(w);
			changed |= ImGui::DragInt("##low", &ins.eq_low, 0.5f, -64, 64, "Low %d");
			hover_tip(eq_tip);
			ImGui::SameLine();
			ImGui::SetNextItemWidth(w);
			changed |= ImGui::DragInt("##mid", &ins.eq_mid, 0.5f, -64, 64, "Mid %d");
			hover_tip(eq_tip);
			ImGui::SameLine();
			ImGui::SetNextItemWidth(w);
			changed |= ImGui::DragInt("##high", &ins.eq_high, 0.5f, -64, 64, "High %d");
			hover_tip(eq_tip);
			ImGui::SameLine();
			if (ImGui::Button("Reset")) {
				ins.eq_low = ins.eq_mid = ins.eq_high = 0;
				changed = true;
			}
			hover_tip("Reset EQ");
		}
		label("Downsample");
		{
			static const char* const factors[] = {"1x", "2x", "4x"};
			static const char* const tips[] = {"Don't downsample the source wave", "Downsample the source wave to be twice smaller",
			                                   "Downsample the source wave to be four times smaller"};
			changed |= segmented("down", ins.downsample_factor, factors, tips, 3, ImGui::GetContentRegionAvail().x);
		}
		label("Resample");
		{
			static const char* const kinds[] = {"Near", "Linear", "Cubic", "Sine", "Band"};
			static const char* const tips[] = {"Nearest neighbour", "Linear interpolation", "Cubic interpolation",
			                                   "Sine interpolation", "Band-limited interpolation"};
			changed |= segmented("resample", ins.resample_type, kinds, tips, 5, ImGui::GetContentRegionAvail().x);
		}
		label("Volume");
		ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x - 34 * s - style.ItemSpacing.x);
		changed |= ImGui::SliderInt("##vol", &ins.source_volume, 0, 255, "");  // value beside, where the grab can't cover it
		hover_tip("Change volume of the source wave");
		ImGui::SameLine();
		ImGui::AlignTextToFramePadding();
		ImGui::Text("%d", ins.source_volume);
		if (ins.source_volume > 128) {
			ImGui::PushStyleColor(ImGuiCol_Text, theme::v4(theme::AMBER));
			ImGui::TextWrapped("Above 128 boosts the sample and can click on hardware.");
			ImGui::PopStyleColor();
		}
		ImGui::BeginDisabled(!ins.loop_enable);  // these only apply to a loop
		label("Loop");
		changed |= ImGui::Checkbox("Ramp", &ins.ramp_enable);
		hover_tip("Smooth out the loop transition");
		ImGui::SameLine(0, 16 * s);
		changed |= ImGui::Checkbox("Unroll", &ins.loop_unroll);
		hover_tip("Unroll loop to closest 16x rather than resample. Best quality, but takes more memory");
		ImGui::EndDisabled();
		end_card();

		// Envelope: how a note plays, with the real times
		ImGui::TableNextColumn();
		card("envelope");
		heading("ENVELOPE");
		auto stage = [&](const char* text, const char* id, int& value, int max, const std::string& shown, const char* tip) {
			label(text);
			char both[48];
			std::snprintf(both, sizeof(both), "%2d  %s", value, shown.c_str());
			ImGui::SetNextItemWidth(ImGui::GetContentRegionAvail().x - 84 * s - style.ItemSpacing.x);
			changed |= ImGui::SliderInt(id, &value, 0, max, "");
			hover_tip(tip);
			ImGui::SameLine();
			ImGui::AlignTextToFramePadding();
			ImGui::TextUnformatted(both);
		};
		auto at = [](int v, int n) { return v < 0 ? 0 : (v >= n ? n - 1 : v); };
		stage("Attack", "##ar", ins.env_ar, 15, duration(attack_time[at(ins.env_ar, 16)]), "Attack rate, slowest to fastest");
		stage("Decay", "##dr", ins.env_dr, 7, duration(decay_time[at(ins.env_dr, 8)]),
		      "Decay rate, slowest to fastest, it decays to the Sustain Level");
		{
			char level[16];
			std::snprintf(level, sizeof(level), "%d/8", at(ins.env_sl, 8) + 1);
			stage("Sustain level", "##sl", ins.env_sl, 7, level,
			      "Sustain level, lowest to highest, the Decay phase ends with this level");
		}
		{
			const float t = sustain_time[at(ins.env_sr, 32)];
			stage("Sustain rate", "##sr", ins.env_sr, 31, t < 0 ? std::string("no decay") : duration(t),
			      "Sustain Rate, slowest to fastest, it is the speed with that a sound decays to zero after reaching Sustain Level");
		}
		end_card();

		ImGui::EndTable();
	}
	ins_cards_h_ = ImGui::GetCursorPosY() - cards_top;
	if (tallest > 0) ins_card_h_ = tallest;

	if (changed) samples_changed();
}

}  // namespace gss
