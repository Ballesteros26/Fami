// The pattern editor, drawn character by character like the original:
// 97 columns per row, a blank separator line before each section marker and
// before the song end, the view centered on the cursor row.
#include <cstdio>
#include <string>

#include "app.h"
#include "imgui.h"
#include "song.h"
#include "theme.h"
#include "widgets.h"

namespace gss {

namespace {

const char* const NOTE_NAMES[12] = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"};

constexpr int ROW_CHARS = 1 + 4 + 1 + 2 + 1 + 11 * 8;  // 97

// Screen character column -> editor column, -1 for the gaps.
const int COLUMN_AT[ROW_CHARS] = {
	-1, 0, 0, 0, 0,
	-1, 1, 1,
	-1, 2, 2, 2, 3, 3, 4, 4, 5, 6, 6,
	-1, 7, 7, 7, 8, 8, 9, 9, 10, 11, 11,
	-1, 12, 12, 12, 13, 13, 14, 14, 15, 16, 16,
	-1, 17, 17, 17, 18, 18, 19, 19, 20, 21, 21,
	-1, 22, 22, 22, 23, 23, 24, 24, 25, 26, 26,
	-1, 27, 27, 27, 28, 28, 29, 29, 30, 31, 31,
	-1, 32, 32, 32, 33, 33, 34, 34, 35, 36, 36,
	-1, 37, 37, 37, 38, 38, 39, 39, 40, 41, 41,
	-1,
};

// Background a selected field: one step lighter than its row.
ImU32 selected_bg(ImU32 bg)
{
	const int r = (int)(bg & 255), g = (int)((bg >> 8) & 255), b = (int)((bg >> 16) & 255);
	return theme::rgb(r + (0x2c - r) * 3 / 4 + 8, g + (0x3a - g) * 3 / 4 + 8, b + (0x52 - b) * 3 / 4 + 8);
}

}  // namespace

int App::pattern_top_row2x() const
{
	const Song& s = editor_->song();
	const int phgt = pattern_lines_;
	int rcnt = phgt / 2;
	int row = editor_->row_view * 2;

	while (rcnt > 0) {
		row -= 2;
		if (row < 0) break;
		if (s.row(row / 2).marker || row / 2 == s.length) --rcnt;
		--rcnt;
	}

	if (rcnt < 0) ++row;
	if (s.row(editor_->row_cur).marker) row += 2;
	if (row < 0) row = 0;
	if (row / 2 + phgt + 1 >= MAX_ROWS) row = (MAX_ROWS - phgt + 1) * 2;

	return row;
}

int App::pattern_screen_to_row(int srow) const
{
	const Song& s = editor_->song();
	int row = pattern_top_row2x();

	while (srow > 0) {
		row += 2;
		if (row / 2 >= MAX_ROWS) break;
		if (s.row(row / 2).marker || row / 2 == s.length) --srow;
		--srow;
	}

	return row / 2;
}

// A vertical scrollbar for the pattern. The range is the part of the song in
// use (its last note, its end marker, the cursor) plus a few rows, not all
// MAX_ROWS rows. Scrolling moves the view only, like the original's drag
// auto-scroll; the next cursor move brings the view back to the cursor.
void App::draw_pattern_scrollbar(ImVec2 pos, ImVec2 size)
{
	SongEditor& ed = *editor_;
	const Song& s = ed.song();
	const float sc = ui_scale_;
	if (size.y < 20 * sc) return;

	const int lines = pattern_lines_ - 1 > 1 ? pattern_lines_ - 1 : 1;  // rows on screen, without the header
	const int half = lines / 2;
	int used = song_find_last_row(s);
	if (s.length < MAX_ROWS - 1 && s.length > used) used = s.length;
	if (ed.row_cur > used) used = ed.row_cur;  // not row_view: dragging would then grow its own range
	int total = used + 1 + 4;  // scrolled to the bottom, the last row sits just above the view's bottom edge
	if (total < lines) total = lines;
	if (total > MAX_ROWS) total = MAX_ROWS;

	int top = ed.row_view - half;  // the view is centered on row_view
	if (top > total - lines) top = total - lines;
	if (top < 0) top = 0;

	const float pad = 2 * sc;
	const float track_y = pos.y + pad, track_h = size.y - pad * 2;
	float thumb_h = track_h * (float)lines / (float)total;
	if (thumb_h < 24 * sc) thumb_h = 24 * sc;
	if (thumb_h > track_h) thumb_h = track_h;
	const float travel = track_h - thumb_h;
	const int range = total - lines > 0 ? total - lines : 0;
	const float thumb_y = track_y + (range ? travel * (float)top / (float)range : 0);

	ImGui::SetCursorScreenPos(pos);
	ImGui::InvisibleButton("pattern_scroll", size);
	const bool hovered = ImGui::IsItemHovered(), active = ImGui::IsItemActive();
	const float my = ImGui::GetMousePos().y;

	if (ImGui::IsItemActivated()) {  // grab the thumb where clicked, or jump so it centers on the click
		scroll_grab_ = (my >= thumb_y && my < thumb_y + thumb_h) ? my - thumb_y : thumb_h / 2;
	}
	if (active && travel > 0 && range > 0) {
		float t = (my - scroll_grab_ - track_y) / travel;
		if (t < 0) t = 0;
		if (t > 1) t = 1;
		int row = (int)(t * range + 0.5f) + half;
		if (row > MAX_ROWS - 1) row = MAX_ROWS - 1;
		ed.row_view = row;
	}

	ImDrawList* dl = ImGui::GetWindowDrawList();
	const float x0 = pos.x + 3 * sc, x1 = pos.x + size.x - 3 * sc;
	dl->AddRectFilled(ImVec2(x0, track_y), ImVec2(x1, track_y + track_h), theme::rgb(0x16, 0x1a, 0x22), 4 * sc);
	const ImU32 thumb = active ? theme::rgb(0x4a, 0x55, 0x6c) : hovered ? theme::rgb(0x3a, 0x44, 0x58) : theme::CONTROL;
	dl->AddRectFilled(ImVec2(x0, thumb_y), ImVec2(x1, thumb_y + thumb_h), thumb, 4 * sc);
	if (hovered || active) ImGui::SetTooltip("Rows %d-%d of %d", top, top + lines - 1, used + 1);
}

void App::draw_song_view()
{
	SongEditor& ed = *editor_;
	const Song& s = ed.song();

	// song properties: number, name and the sound effect flag
	{
		Song& song = ed.song();
		ImGui::AlignTextToFramePadding();
		ImGui::TextColored(theme::v4(theme::FAINT), "%02d", ed.song_cur + 1);
		ImGui::SameLine();
		char name[256];
		std::snprintf(name, sizeof(name), "%s", song.name.c_str());
		ImGui::SetNextItemWidth(320);
		if (ImGui::InputTextWithHint("##songname", "song name", name, sizeof(name))) song.name = name;
		ImGui::SameLine(0, 16);
		bool effect = song.effect;
		if (ImGui::Checkbox("Sound effect", &effect)) {
			std::string error;
			if (effect && !effect_channel_check(song, &error)) message(error);  // refused, stays music
			else song.effect = effect;
			ed.clamp_cursor();
			mark_dirty();
		}
		hover_tip("Mark the song as a sound effect\n\nSound effects use channel 1 only.");

		if (song.effect && !effect_channel_check(song))  // flagged before this rule, e.g. an older project
			ImGui::TextColored(theme::v4(theme::MUTED), "Channels 2-8 are locked for sound effects. Untick Sound effect to edit them.");
	}

	ImGui::PushFont(pattern_font_, pattern_font_size_);
	char_w_ = ImGui::CalcTextSize("1").x;
	char_h_ = ImGui::GetTextLineHeight();

	ImGui::BeginChild("pattern", ImVec2(0, 0), ImGuiChildFlags_None, ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);

	const ImVec2 origin = ImGui::GetCursorScreenPos();
	const ImVec2 avail = ImGui::GetContentRegionAvail();
	ImDrawList* dl = ImGui::GetWindowDrawList();
	pattern_lines_ = (int)(avail.y / char_h_);
	if (pattern_lines_ < 2) pattern_lines_ = 2;

	dl->AddRectFilled(origin, ImVec2(origin.x + avail.x, origin.y + avail.y), theme::BG);
	dl->AddRectFilled(origin, ImVec2(origin.x + avail.x, origin.y + char_h_), theme::BAR);

	auto cell = [&](int x, int y, const char* text, ImU32 fg, ImU32 bg) {
		const float px = origin.x + x * char_w_, py = origin.y + y * char_h_;
		int n = 0;
		while (text[n]) ++n;
		dl->AddRectFilled(ImVec2(px, py), ImVec2(px + n * char_w_, py + char_h_), bg);
		dl->AddText(ImVec2(px, py), fg, text);
	};

	// colors for one field: each field type has its own color, empty fields
	// and rows past the song end are dimmed, the cursor is inverted
	auto colors = [&](int row, int col, ImU32 bg, ImU32 field, bool empty, ImU32& fg_out, ImU32& bg_out) {
		if (ed.row_cur != row || ed.col_cur != col) {
			fg_out = (empty || row >= s.length) ? theme::EMPTY : field;
			bg_out = ed.in_selection(row, col) ? selected_bg(bg) : bg;
		} else {
			fg_out = theme::ON_AMBER;
			bg_out = theme::AMBER;
		}
	};

	// header
	cell(0, 0, " RowN Sp ", theme::FAINT, theme::BAR);
	for (int chn = 0; chn < CHANNELS; ++chn) {
		char h[16];
		std::snprintf(h, sizeof(h), ed.channel_mute[chn] ? " CH%d  mute " : " CHANNEL%d ", chn + 1);
		const bool locked = s.effect && chn > 0;  // sound effects use channel 1 only
		cell(9 + chn * 11, 0, h, (ed.channel_mute[chn] || locked) ? theme::EMPTY : theme::TEXT_SOFT, theme::BAR);
	}

	int row2x = pattern_top_row2x();
	const int measure = s.measure > 0 ? s.measure : 1;  // a zero measure crashed the original
	int rowhl = 0;
	for (int row = 0; row < row2x / 2; ++row) {
		if (s.row(row).marker) rowhl = 0;
		++rowhl;
	}

	for (int y = 1; y < pattern_lines_;) {
		const int row = row2x / 2;
		if (row >= MAX_ROWS) break;

		if (!(row2x & 1)) {
			if (row && (s.row(row).marker || (s.length < MAX_ROWS - 1 && row == s.length))) {  // separator line
				// a divider labelled with the section name, or the song end
				const bool end = !s.row(row).marker;
				const std::string& label = end ? std::string("SONG END") : s.row(row).name;
				const float py = origin.y + y * char_h_ + char_h_ / 2;
				const float lx = origin.x + char_w_ * 10;
				float tx = lx;
				if (!label.empty()) {
					dl->AddText(ImVec2(lx, origin.y + y * char_h_), end ? theme::FAINT : theme::LILAC, label.c_str());
					tx += ImGui::CalcTextSize(label.c_str()).x + char_w_;
				}
				dl->AddLine(ImVec2(tx, py), ImVec2(origin.x + ROW_CHARS * char_w_, py), end ? theme::BORDER : theme::rgb(0x2f, 0x2a, 0x4a));
				++y;
			}
		} else {
			const Row& r = s.row(row);
			if (r.marker) rowhl = 0;

			ImU32 bg = !(rowhl % (measure * 4)) ? theme::ROW_BAR : !(rowhl % measure) ? theme::ROW_BEAT : theme::BG;
			if (row == ed.row_cur) bg = theme::ROW_CURSOR;

			ImU32 fg, b;
			char buf[16];
			int x = 0;

			colors(row, -1, bg, theme::CYAN, false, fg, b);
			cell(x, y, row == s.loop_start ? "L" : " ", fg, b);
			x += 1;

			colors(row, 0, bg, theme::FAINT, false, fg, b);
			std::snprintf(buf, sizeof(buf), "%04d", row);
			cell(x, y, buf, fg, b);
			x += 4;

			colors(row, -1, bg, theme::CYAN, false, fg, b);
			cell(x, y, row == s.length ? "E" : " ", fg, b);
			x += 1;

			colors(row, 1, bg, theme::LILAC, !r.speed, fg, b);
			if (r.speed) std::snprintf(buf, sizeof(buf), "%02d", r.speed % 100);
			else std::snprintf(buf, sizeof(buf), "..");
			cell(x, y, buf, fg, b);
			x += 2;

			colors(row, -1, bg, theme::TEXT, false, fg, b);
			cell(x, y, " ", fg, b);
			x += 1;

			for (int chn = 0; chn < CHANNELS; ++chn) {
				const NoteField& n = r.chn[chn];
				const int base = chn * 5 + 2;
				const bool locked = s.effect && chn > 0;
				const ImU32 cbg = locked ? theme::BG : bg;
				auto field = [&](ImU32 c) { return locked ? theme::EMPTY : c; };

				colors(row, base, cbg, field(theme::TEXT), n.note == 0, fg, b);
				if (n.note == 0) std::snprintf(buf, sizeof(buf), "...");
				else if (n.note == 1) std::snprintf(buf, sizeof(buf), "---");
				else std::snprintf(buf, sizeof(buf), "%s%d", NOTE_NAMES[(n.note - 2) % 12], ((n.note - 2) / 12) % 10);
				cell(x, y, buf, fg, b);
				x += 3;

				colors(row, base + 1, cbg, field(theme::AMBER), !n.instrument, fg, b);
				if (n.instrument) std::snprintf(buf, sizeof(buf), "%02d", n.instrument % 100);
				else std::snprintf(buf, sizeof(buf), "..");
				cell(x, y, buf, fg, b);
				x += 2;

				colors(row, base + 2, cbg, field(theme::GREEN), n.volume == 255, fg, b);
				if (n.volume != 255) std::snprintf(buf, sizeof(buf), "%02d", n.volume % 100);
				else std::snprintf(buf, sizeof(buf), "..");
				cell(x, y, buf, fg, b);
				x += 2;

				colors(row, base + 3, cbg, field(theme::CYAN), !n.effect, fg, b);
				buf[0] = n.effect ? (char)n.effect : '.';
				buf[1] = 0;
				cell(x, y, buf, fg, b);
				x += 1;

				colors(row, base + 4, cbg, field(theme::CYAN), n.value == 255, fg, b);
				if (n.value != 255) std::snprintf(buf, sizeof(buf), "%02d", n.value % 100);
				else std::snprintf(buf, sizeof(buf), "..");
				cell(x, y, buf, fg, b);
				x += 2;

				colors(row, -1, cbg, theme::TEXT, false, fg, b);
				cell(x, y, " ", fg, b);
				x += 1;
			}

			if (!row && !r.name.empty()) cell(x + 1, y, r.name.c_str(), theme::LILAC, theme::BG);  // later names label their divider

			++y;
			++rowhl;
		}

		++row2x;
	}

	// --- mouse ---
	const float sb_w = 12 * ui_scale_;  // the scrollbar's strip on the right
	const float area_w = avail.x - sb_w > 1 ? avail.x - sb_w : 1;
	ImGui::SetCursorScreenPos(origin);
	ImGui::InvisibleButton("pattern_area", ImVec2(area_w, avail.y > 1 ? avail.y : 1),
	                       ImGuiButtonFlags_MouseButtonLeft | ImGuiButtonFlags_MouseButtonRight);

	const ImVec2 mouse = ImGui::GetMousePos();
	const int mcol = (int)((mouse.x - origin.x) / char_w_);
	const int mline = (int)((mouse.y - origin.y) / char_h_);
	const bool hovered = ImGui::IsItemHovered();
	const bool shift = ImGui::GetIO().KeyShift;

	if (hovered && (ImGui::IsMouseClicked(ImGuiMouseButton_Left) || ImGui::IsMouseClicked(ImGuiMouseButton_Right))) {
		const bool left = ImGui::IsMouseClicked(ImGuiMouseButton_Left);
		if (mcol >= 0 && mcol < ROW_CHARS) {
			if (mline == 0) {  // header: left click mutes, right click solos
				if (mcol >= 9) ed.toggle_mute((mcol - 9) / 11, !left);
			} else if (left) {
				const int col = COLUMN_AT[mcol];
				const int row = pattern_screen_to_row(mline - 1);
				if (col >= 0 && row >= 0 && row < MAX_ROWS && !ed.column_locked(col)) {
					if (col >= 1) ed.start_selection(col, row);
					ed.move_cursor(row, col, false);
					ed.col_cur_prev = -1;
					dragging_ = true;
				}
			}
		}
		if (left && ImGui::IsMouseDoubleClicked(ImGuiMouseButton_Left)) double_click_pending_ = true;
	}

	if (dragging_ && ImGui::IsMouseDown(ImGuiMouseButton_Left)) {
		// auto-scroll near the edges, throttled like the original's 25 ms timer
		const Uint64 now = SDL_GetTicks();
		if (now >= scroll_delay_until_) {
			if (mline < 3 && ed.row_view > 0) {
				--ed.row_view;
				scroll_delay_until_ = now + 25;
			}
			if (mline >= pattern_lines_ - 2 && ed.row_view < MAX_ROWS - 1) {
				++ed.row_view;
				scroll_delay_until_ = now + 25;
			}
		}
		if (mcol >= 0 && mcol < ROW_CHARS && mline > 0) {
			const int col = COLUMN_AT[mcol];
			const int row = pattern_screen_to_row(mline - 1);
			if (col >= 1 && row >= 0 && row < MAX_ROWS && !ed.column_locked(col)) {
				ed.sel_col_e = col;
				ed.sel_row_e = row;
				ed.update_selection();
			}
		}
	}

	if (ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
		dragging_ = false;
		if (double_click_pending_) {  // double click selects the section in this channel, Shift the whole song
			if (mline >= 1) ed.set_channel_selection(true, !shift);
			double_click_pending_ = false;
		}
	}

	if (hovered && ImGui::GetIO().MouseWheel != 0.0f) ed.move_row(-(int)ImGui::GetIO().MouseWheel);

	draw_pattern_scrollbar(ImVec2(origin.x + avail.x - sb_w, origin.y + char_h_), ImVec2(sb_w, avail.y - char_h_));

	ImGui::EndChild();
	ImGui::PopFont();
}

}  // namespace gss
