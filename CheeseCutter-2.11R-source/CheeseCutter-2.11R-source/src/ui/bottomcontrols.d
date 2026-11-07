/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.bottomcontrols;

import com.fb : INFOBAR_GLYPH_AUDIO_LEFT, INFOBAR_GLYPH_AUDIO_RIGHT,
	INFOBAR_GLYPH_FULLSCREEN_LEFT, INFOBAR_GLYPH_FULLSCREEN_RIGHT,
	INFOBAR_GLYPH_HELP_LEFT, INFOBAR_GLYPH_HELP_RIGHT,
	INFOBAR_GLYPH_KEYJAM_LEFT, INFOBAR_GLYPH_KEYJAM_RIGHT,
	INFOBAR_GLYPH_LOAD_LEFT, INFOBAR_GLYPH_LOAD_RIGHT,
	INFOBAR_GLYPH_SAVE_LEFT, INFOBAR_GLYPH_SAVE_RIGHT,
	INFOBAR_GLYPH_THEME_C64, INFOBAR_GLYPH_THEME_C64_MIDNIGHT,
	INFOBAR_GLYPH_THEME_CLASSIC, INFOBAR_GLYPH_THEME_NEON;

enum BottomControlRole {
	none,
	fullscreen,
	theme1,
	theme2,
	theme3,
	theme4,
	load,
	save,
	keyjam,
	audio,
	help
}

struct BottomControlDescriptor {
	BottomControlRole role;
	int[2] glyphs;
	int glyphCount;
	int gapAfter;
}

struct BottomControlRect {
	int x, y, width, height;

	bool contains(int cellX, int cellY) const {
		return cellX >= x && cellX < x + width &&
			cellY >= y && cellY < y + height;
	}
}

struct BottomControlPlacement {
	BottomControlRole role;
	int[2] glyphs;
	int glyphCount;
	BottomControlRect rect;
}

struct BottomControlLayout {
	bool valid;
	BottomControlPlacement[10] placements;
	size_t count;
}

struct BottomControlHit {
	bool matched;
	BottomControlRole role;
}

struct BottomControlInteraction {
	bool handled;
	BottomControlRole role;
	bool invokeAction;
	int themeIndex = -1;
}

enum BOTTOM_CONTROL_LEFT_PADDING = 2;
enum BOTTOM_CONTROL_RIGHT_PADDING = 2;

immutable BottomControlDescriptor[5] leftBottomControls = [
	BottomControlDescriptor(BottomControlRole.fullscreen,
		[INFOBAR_GLYPH_FULLSCREEN_LEFT, INFOBAR_GLYPH_FULLSCREEN_RIGHT], 2, 1),
	BottomControlDescriptor(BottomControlRole.theme1,
		[INFOBAR_GLYPH_THEME_CLASSIC, 0], 1, 1),
	BottomControlDescriptor(BottomControlRole.theme2,
		[INFOBAR_GLYPH_THEME_C64, 0], 1, 1),
	BottomControlDescriptor(BottomControlRole.theme3,
		[INFOBAR_GLYPH_THEME_C64_MIDNIGHT, 0], 1, 1),
	BottomControlDescriptor(BottomControlRole.theme4,
		[INFOBAR_GLYPH_THEME_NEON, 0], 1, 0)
];

immutable BottomControlDescriptor[5] rightBottomControls = [
	BottomControlDescriptor(BottomControlRole.load,
		[INFOBAR_GLYPH_SAVE_LEFT, INFOBAR_GLYPH_SAVE_RIGHT], 2, 1),
	BottomControlDescriptor(BottomControlRole.save,
		[INFOBAR_GLYPH_LOAD_LEFT, INFOBAR_GLYPH_LOAD_RIGHT], 2, 1),
	BottomControlDescriptor(BottomControlRole.keyjam,
		[INFOBAR_GLYPH_KEYJAM_LEFT, INFOBAR_GLYPH_KEYJAM_RIGHT], 2, 1),
	BottomControlDescriptor(BottomControlRole.audio,
		[INFOBAR_GLYPH_AUDIO_LEFT, INFOBAR_GLYPH_AUDIO_RIGHT], 2, 1),
	BottomControlDescriptor(BottomControlRole.help,
		[INFOBAR_GLYPH_HELP_LEFT, INFOBAR_GLYPH_HELP_RIGHT], 2, 0)
];

int bottomControlStripWidth(const(BottomControlDescriptor)[] controls) {
	int width;
	foreach(control; controls)
		width += control.glyphCount + control.gapAfter;
	return width;
}

int bottomControlRow(int screenHeight) {
	return screenHeight - 1;
}

BottomControlLayout bottomControlLayout(int screenWidth, int screenHeight) {
	BottomControlLayout layout;
	int leftWidth = bottomControlStripWidth(leftBottomControls[]);
	int rightWidth = bottomControlStripWidth(rightBottomControls[]);
	if(screenWidth < BOTTOM_CONTROL_LEFT_PADDING + leftWidth + rightWidth +
			BOTTOM_CONTROL_RIGHT_PADDING || screenHeight < 1)
		return layout;

	layout.valid = true;
	int row = bottomControlRow(screenHeight);
	appendControls(layout, leftBottomControls[], BOTTOM_CONTROL_LEFT_PADDING, row);
	appendControls(layout, rightBottomControls[],
		screenWidth - BOTTOM_CONTROL_RIGHT_PADDING - rightWidth, row);
	return layout;
}

BottomControlHit bottomControlAtCell(int screenWidth, int screenHeight,
		int cellX, int cellY) {
	BottomControlHit hit;
	auto layout = bottomControlLayout(screenWidth, screenHeight);
	if(!layout.valid)
		return hit;
	foreach(i; 0 .. layout.count) {
		auto placement = layout.placements[i];
		if(placement.rect.contains(cellX, cellY)) {
			hit.matched = true;
			hit.role = placement.role;
			return hit;
		}
	}
	return hit;
}

BottomControlInteraction bottomControlInteractionAtCell(int screenWidth,
		int screenHeight, int cellX, int cellY, int button,
		int currentThemeIndex) {
	BottomControlInteraction interaction;
	auto hit = bottomControlAtCell(screenWidth, screenHeight, cellX, cellY);
	if(!hit.matched)
		return interaction;

	interaction.handled = true;
	interaction.role = hit.role;
	interaction.themeIndex = bottomControlThemeIndex(hit.role);
	if(button != 1)
		return interaction;
	if(interaction.themeIndex >= 0 &&
			interaction.themeIndex == currentThemeIndex)
		return interaction;
	interaction.invokeAction = true;
	return interaction;
}

int bottomControlThemeIndex(BottomControlRole role) {
	final switch(role) {
	case BottomControlRole.theme1:
		return 0;
	case BottomControlRole.theme2:
		return 1;
	case BottomControlRole.theme3:
		return 2;
	case BottomControlRole.theme4:
		return 3;
	case BottomControlRole.none:
	case BottomControlRole.fullscreen:
	case BottomControlRole.load:
	case BottomControlRole.save:
	case BottomControlRole.keyjam:
	case BottomControlRole.audio:
	case BottomControlRole.help:
		return -1;
	}
}

private void appendControls(ref BottomControlLayout layout,
		const(BottomControlDescriptor)[] controls, int startX, int row) {
	int x = startX;
	foreach(control; controls) {
		layout.placements[layout.count++] = BottomControlPlacement(control.role,
			control.glyphs, control.glyphCount,
			BottomControlRect(x, row, control.glyphCount, 1));
		x += control.glyphCount + control.gapAfter;
	}
}
