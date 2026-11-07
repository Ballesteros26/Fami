#include "theme.h"

namespace gss::theme {

void apply(ImGuiStyle& style)
{
	ImGui::StyleColorsDark(&style);

	style.WindowRounding = 0;
	style.ChildRounding = 8;
	style.FrameRounding = 6;
	style.PopupRounding = 8;
	style.GrabRounding = 2;
	style.GrabMinSize = 5;  // thin, so a slider's value text stays readable
	style.TabRounding = 6;
	style.ScrollbarRounding = 6;
	style.WindowBorderSize = 0;
	style.ChildBorderSize = 1;
	style.FrameBorderSize = 0;
	style.WindowPadding = ImVec2(12, 10);
	style.FramePadding = ImVec2(10, 6);
	style.ItemSpacing = ImVec2(8, 7);
	style.SeparatorTextBorderSize = 1;

	ImVec4* c = style.Colors;
	c[ImGuiCol_Text] = v4(TEXT);
	c[ImGuiCol_TextDisabled] = v4(FAINT);
	c[ImGuiCol_WindowBg] = v4(BG);
	c[ImGuiCol_ChildBg] = v4(PANEL);
	c[ImGuiCol_PopupBg] = v4(BAR);
	c[ImGuiCol_MenuBarBg] = v4(BAR);
	c[ImGuiCol_Border] = v4(BORDER);
	c[ImGuiCol_Separator] = v4(BORDER);
	c[ImGuiCol_FrameBg] = v4(rgb(0x1e, 0x25, 0x32));
	c[ImGuiCol_FrameBgHovered] = v4(rgb(0x26, 0x2f, 0x3f));
	c[ImGuiCol_FrameBgActive] = v4(rgb(0x2c, 0x36, 0x49));
	c[ImGuiCol_Button] = v4(CONTROL);
	c[ImGuiCol_ButtonHovered] = v4(rgb(0x2c, 0x36, 0x49));
	c[ImGuiCol_ButtonActive] = v4(rgb(0x35, 0x41, 0x57));
	c[ImGuiCol_Header] = v4(SELECTED);
	c[ImGuiCol_HeaderHovered] = v4(rgb(0x1c, 0x24, 0x32));
	c[ImGuiCol_HeaderActive] = v4(rgb(0x24, 0x38, 0x5a));
	c[ImGuiCol_Tab] = v4(BG);
	c[ImGuiCol_TabHovered] = v4(rgb(0x2c, 0x36, 0x49));
	c[ImGuiCol_TabSelected] = v4(CONTROL);
	c[ImGuiCol_TabSelectedOverline] = v4(AMBER);
	c[ImGuiCol_SliderGrab] = v4(AMBER);
	c[ImGuiCol_SliderGrabActive] = v4(rgb(0xf7, 0xc8, 0x84));
	c[ImGuiCol_CheckMark] = v4(CYAN);
	c[ImGuiCol_TitleBg] = v4(BAR);
	c[ImGuiCol_TitleBgActive] = v4(BAR);
	c[ImGuiCol_ScrollbarBg] = v4(PANEL);
	c[ImGuiCol_ScrollbarGrab] = v4(CONTROL);
	c[ImGuiCol_ModalWindowDimBg] = ImVec4(0, 0, 0, 0.55f);
}

}  // namespace gss::theme
