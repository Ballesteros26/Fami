// The editor's colors: a dark "night tracker" palette. Pattern fields each
// get a color so a dense pattern reads at a glance.
#pragma once

#include "imgui.h"

namespace gss::theme {

constexpr ImU32 rgb(int r, int g, int b) { return IM_COL32(r, g, b, 255); }

// surfaces
const ImU32 BG = rgb(0x0f, 0x11, 0x17);        // pattern and wells
const ImU32 PANEL = rgb(0x13, 0x16, 0x1d);     // side panels
const ImU32 BAR = rgb(0x16, 0x1a, 0x22);       // transport and status bars, headers
const ImU32 CONTROL = rgb(0x23, 0x2b, 0x3a);   // buttons, unselected chips
const ImU32 BORDER = rgb(0x23, 0x2a, 0x37);

// text
const ImU32 TEXT = rgb(0xee, 0xf0, 0xf5);
const ImU32 TEXT_SOFT = rgb(0xc9, 0xcd, 0xd8);
const ImU32 MUTED = rgb(0xa3, 0xaa, 0xbb);
const ImU32 FAINT = rgb(0x8b, 0x93, 0xa7);
const ImU32 EMPTY = rgb(0x5f, 0x67, 0x79);     // empty pattern fields, unused slots

// accents
const ImU32 AMBER = rgb(0xf2, 0xb2, 0x5c);     // instruments, primary action, cursor
const ImU32 GREEN = rgb(0x7f, 0xd3, 0x9a);     // volume, levels, sound effects
const ImU32 CYAN = rgb(0x67, 0xc7, 0xe6);      // effects
const ImU32 LILAC = rgb(0xb8, 0xa6, 0xf7);     // speed, sections, music
const ImU32 BLUE = rgb(0x5b, 0x7b, 0xd6);      // driver code
const ImU32 ON_AMBER = rgb(0x11, 0x13, 0x18);

// pattern rows
const ImU32 ROW_BEAT = rgb(0x13, 0x18, 0x22);
const ImU32 ROW_BAR = rgb(0x18, 0x20, 0x2d);
const ImU32 ROW_CURSOR = rgb(0x1d, 0x31, 0x50);
const ImU32 SELECTED = rgb(0x1d, 0x31, 0x50);  // selected list items

inline ImVec4 v4(ImU32 c) { return ImGui::ColorConvertU32ToFloat4(c); }

// Applies the palette to Dear ImGui's widgets.
void apply(ImGuiStyle& style);

}  // namespace gss::theme
