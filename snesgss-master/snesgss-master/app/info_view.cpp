// Info (F4): SPC700 memory map and about box, as RenderMemoryUse() drew them.
#include <cstdio>

#include "app.h"
#include "brr.h"
#include "imgui.h"
#include "theme.h"

namespace gss {

void App::draw_info()
{
	const CompileStats& st = compiler_.stats();
	const int stream = BRR_STREAM_BUFFER_SIZE;  // 64 of it is the IPL ROM
	const int free = 65536 - 512 - st.driver_size - st.instruments_size - st.music_size - st.effects_size - stream;

	ImGui::SeparatorText("Memory use");

	ImDrawList* dl = ImGui::GetWindowDrawList();
	const ImVec2 o = ImGui::GetCursorScreenPos();
	const float width = ImGui::GetContentRegionAvail().x;
	const float height = 40;
	const float ppb = width / 65536.0f;

	const ImU32 sky = theme::rgb(0x3b, 0x45, 0x58), blue = theme::BLUE, yellow = theme::AMBER, lime = theme::GREEN,
	            music_largest = theme::rgb(0x6b, 0x5d, 0xa8), music = theme::LILAC, face = theme::rgb(0x1a, 0x1f, 0x2a),
	            black = theme::rgb(0x3a, 0x42, 0x54);

	auto rect = [&](float x0, float x1, ImU32 fill) {
		dl->AddRectFilled(ImVec2(o.x + x0, o.y), ImVec2(o.x + x1, o.y + height), fill);
		dl->AddRect(ImVec2(o.x + x0, o.y), ImVec2(o.x + x1, o.y + height), black);
	};

	float x = 0, w;

	w = 0x200 * ppb;  // direct page and stack
	rect(x, x + w, sky);
	x += w - 1;

	w = st.driver_size * ppb;  // driver code
	rect(x, x + w, blue);
	x += w - 1;

	w = st.instruments_size * ppb;  // dir, adsr, samples
	rect(x, x + w, yellow);
	float len = 0;
	for (const Instrument& ins : module_->instruments) {
		if (!ins.has_source()) continue;
		dl->AddLine(ImVec2(o.x + x + len * ppb, o.y), ImVec2(o.x + x + len * ppb, o.y + height), black);
		len += brr_size_estimate(ins, false);
	}
	x += w - 1;

	w = st.effects_size * ppb;  // sound effects
	rect(x, x + w, lime);
	x += w - 1;

	rect(x, x + st.music_largest * ppb, music_largest);  // music: largest song, current song
	rect(x, x + st.music_size * ppb, music);
	x += st.music_largest * ppb - 1;

	w = stream * ppb;  // free, then the BRR streaming buffer, hatched
	rect(x, width - w, face);
	x = width - w - 1;
	rect(x, width, face);
	dl->PushClipRect(ImVec2(o.x + x, o.y), ImVec2(o.x + width, o.y + height), true);
	for (float hx = x - height; hx < width; hx += 6)
		dl->AddLine(ImVec2(o.x + hx, o.y + height), ImVec2(o.x + hx + height, o.y), black);
	dl->PopClipRect();

	// scale: a tick every 1K, a long one every 8K
	for (int i = 0; i < 65; ++i) {
		float tx = i * width / 64;
		if (tx > width - 2) tx = width - 2;
		dl->AddLine(ImVec2(o.x + tx, o.y + height), ImVec2(o.x + tx, o.y + height + ((i & 7) ? 5 : 10)), black,
		            (i & 7) ? 1.0f : 2.0f);
	}

	ImGui::Dummy(ImVec2(width, height + 16));

	auto legend = [&](ImU32 c, const char* text) {
		const ImVec2 p = ImGui::GetCursorScreenPos();
		const float s = ImGui::GetTextLineHeight();
		dl->AddRectFilled(p, ImVec2(p.x + s, p.y + s), c);
		dl->AddRect(p, ImVec2(p.x + s, p.y + s), black);
		ImGui::Dummy(ImVec2(s, s));
		ImGui::SameLine();
		ImGui::TextUnformatted(text);
	};

	char t[200];
	legend(sky, "Direct Page and Stack: 512 bytes");
	std::snprintf(t, sizeof(t), "Driver code: %d bytes", st.driver_size);
	legend(blue, t);
	std::snprintf(t, sizeof(t), "Instruments: %d bytes (Dir:%d, ADSR:%d, Samples:%d)", st.instruments_size,
	              4 * st.instruments_count, 2 * st.instruments_count, st.instruments_size - 6 * st.instruments_count);
	legend(yellow, t);
	std::snprintf(t, sizeof(t), "Sound effects: %d bytes", st.effects_size);
	legend(lime, t);
	std::snprintf(t, sizeof(t), "Music data: %d bytes (current), %d bytes (largest)", st.music_size, st.music_largest);
	legend(music, t);
	std::snprintf(t, sizeof(t), "BRR streaming buffer: %d bytes", stream);
	legend(face, t);
	std::snprintf(t, sizeof(t), "Free memory: %d bytes", free);
	legend(face, t);
	if (free < 0) ImGui::TextColored(ImVec4(0.8f, 0, 0, 1), "The data does not fit in the SPC700's 64K of RAM.");

	ImGui::SeparatorText("About");
	ImGui::Text("%s", VERSION_STR);
	ImGui::TextDisabled("Display scale %.3g, zoom %d%%", content_scale_, zoom_);
	ImGui::TextUnformatted("Copyright \xc2\xa9 Bubble Zap, LLC 2014-15");
	ImGui::TextUnformatted("Editor and SPC700 driver code by Shiru");
	ImGui::TextUnformatted("Uses SPC-related parts from Game_Music_Emu by Blargg");
	ImGui::TextUnformatted("Uses BRR encoder from BRRtools by Bregalad");
	ImGui::TextUnformatted("Uses 3 Band EQ code by Neil C");
	ImGui::TextUnformatted("Cross-platform editor built with SDL3 and Dear ImGui");
}

}  // namespace gss
