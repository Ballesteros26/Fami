// Small widget helpers shared by the views.
#pragma once

#include "imgui.h"
#include "theme.h"

namespace gss {

// A hover hint for the last item, like the original editor's control hints:
// shown after the usual tooltip delay, long text wrapped.
inline void hover_tip(const char* text)
{
	if (!ImGui::IsItemHovered(ImGuiHoveredFlags_ForTooltip)) return;
	ImGui::BeginTooltip();
	ImGui::PushTextWrapPos(ImGui::GetFontSize() * 28.0f);
	ImGui::TextUnformatted(text);
	ImGui::PopTextWrapPos();
	ImGui::EndTooltip();
}

// A row of mutually exclusive buttons filling width. tips may be null, or
// hold a hover hint (or null) per choice. Returns true when the choice changed.
inline bool segmented(const char* id, int& value, const char* const* labels, const char* const* tips, int count, float width)
{
	bool changed = false;
	ImGui::PushID(id);
	ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(2, ImGui::GetStyle().ItemSpacing.y));  // tight row, normal gap below
	const float w = (width - 2.0f * (count - 1)) / count;
	for (int i = 0; i < count; ++i) {
		if (i) ImGui::SameLine();
		const bool on = value == i;
		ImGui::PushStyleColor(ImGuiCol_Button, theme::v4(on ? theme::SELECTED : theme::BG));
		ImGui::PushStyleColor(ImGuiCol_Text, theme::v4(on ? theme::TEXT : theme::MUTED));
		if (ImGui::Button(labels[i], ImVec2(w, 0)) && !on) {
			value = i;
			changed = true;
		}
		ImGui::PopStyleColor(2);
		if (tips && tips[i]) hover_tip(tips[i]);
	}
	ImGui::PopStyleVar();
	ImGui::PopID();
	return changed;
}

}  // namespace gss
