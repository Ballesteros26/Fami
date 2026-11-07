/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.sequencecolors;

import ct.base : Song;
import seq.trackoverview : TrackOverviewLane, buildTrackOverview;

enum SEQUENCE_COLOR_HUE_START = 0;
enum SEQUENCE_COLOR_HUE_RANGE = 360;
enum SEQUENCE_COLOR_SATURATION = 50;
enum SEQUENCE_COLOR_BRIGHTNESS_A = 40;
enum SEQUENCE_COLOR_BRIGHTNESS_B = 30;
enum SEQUENCE_COLOR_DARK_TINT_BRIGHTNESS = 15;
enum SEQUENCE_COLOR_NOTE_PREVIEW_BRIGHTNESS = 85;
enum SEQUENCE_COLOR_FALLBACK_ARGB = 0xff666666u;
enum SEQUENCE_COLOR_BAR_FALLBACK_BG = 0;
enum SEQUENCE_COLOR_BAR_FOREGROUND = 1;
enum SEQUENCE_ROW_BACKGROUND_BRIGHTNESS = 20;
enum SEQUENCE_ROW_DIGIT_BRIGHTNESS_NORMAL = 60;
enum SEQUENCE_ROW_DIGIT_BRIGHTNESS_ACCENT = 95;
enum SEQUENCE_ROW_NUMBER_CELL_COUNT = 3;

struct SequenceColorLookup {
	int[] sequenceNumbers;
	uint[] argbColors;
}

struct SequenceRowNumberColors {
	uint backgroundArgb;
	uint foregroundArgb;
}

SequenceColorLookup buildSequenceColorLookupFromSong(Song sng) {
	return buildSequenceColorLookupFromOverview(buildTrackOverview(sng));
}

SequenceColorLookup buildSequenceColorLookupFromOverview(
		const(TrackOverviewLane)[] lanes) {
	SequenceColorLookup lookup;
	foreach(lane; lanes) {
		foreach(block; lane.blocks) {
			if(block.rowLength <= 0 || !isValidSequenceNumber(block.sequenceNumber))
				continue;
			addUniqueSequenceNumber(lookup.sequenceNumbers, block.sequenceNumber);
		}
	}

	sortSequenceNumbers(lookup.sequenceNumbers);
	lookup.argbColors.length = lookup.sequenceNumbers.length;
	foreach(index, sequenceNumber; lookup.sequenceNumbers) {
		lookup.argbColors[index] = sequenceArgbColorForSortedIndex(
			cast(int)index, cast(int)lookup.sequenceNumbers.length);
	}
	return lookup;
}

uint sequenceArgbColor(const SequenceColorLookup lookup, int sequenceNumber) {
	int index = sequenceColorIndex(lookup, sequenceNumber);
	if(index >= 0)
		return lookup.argbColors[index];
	return SEQUENCE_COLOR_FALLBACK_ARGB;
}

uint sequenceDarkTintArgbColor(const SequenceColorLookup lookup,
		int sequenceNumber) {
	int index = sequenceColorIndex(lookup, sequenceNumber);
	if(index < 0)
		return sequenceTintArgbColor(SEQUENCE_COLOR_FALLBACK_ARGB,
			SEQUENCE_COLOR_DARK_TINT_BRIGHTNESS);
	return sequenceArgbColorForSortedIndex(index,
		cast(int)lookup.sequenceNumbers.length,
		SEQUENCE_COLOR_DARK_TINT_BRIGHTNESS);
}

void setSequenceBarBackground(ScreenType)(ScreenType screen,
		int x, int y, int width,
		const SequenceColorLookup lookup, int sequenceNumber,
		int fallbackBg = SEQUENCE_COLOR_BAR_FALLBACK_BG) {
	setRawBarBackground(screen, x, y, width,
		sequenceArgbColor(lookup, sequenceNumber), fallbackBg);
}

void setSequenceDarkTintBarBackground(ScreenType)(ScreenType screen,
		int x, int y, int width,
		const SequenceColorLookup lookup, int sequenceNumber,
		int fallbackBg = SEQUENCE_COLOR_BAR_FALLBACK_BG) {
	setRawBarBackground(screen, x, y, width,
		sequenceDarkTintArgbColor(lookup, sequenceNumber), fallbackBg);
}

uint sequenceArgbColorForSortedIndex(int index, int count) {
	if(count <= 0)
		return SEQUENCE_COLOR_FALLBACK_ARGB;

	double brightness = (index & 1) == 0 ?
		SEQUENCE_COLOR_BRIGHTNESS_A :
		SEQUENCE_COLOR_BRIGHTNESS_B;
	return sequenceArgbColorForSortedIndex(index, count, brightness);
}

uint sequenceTintArgbColor(uint argb, double brightnessPercent) {
	double r = cast(double)((argb >> 16) & 0xff) / 255.0;
	double g = cast(double)((argb >> 8) & 0xff) / 255.0;
	double b = cast(double)(argb & 0xff) / 255.0;
	double maxChannel = r;
	if(g > maxChannel)
		maxChannel = g;
	if(b > maxChannel)
		maxChannel = b;
	if(maxChannel <= 0.0)
		return hsbToArgb(0, 0, brightnessPercent);
	double factor = clampUnit(brightnessPercent / 100.0) / maxChannel;
	return (255u << 24) |
		(channelToByte(r * factor) << 16) |
		(channelToByte(g * factor) << 8) |
		channelToByte(b * factor);
}

private int sequenceColorIndex(const SequenceColorLookup lookup,
		int sequenceNumber) {
	foreach(index, storedSequenceNumber; lookup.sequenceNumbers) {
		if(storedSequenceNumber == sequenceNumber)
			return cast(int)index;
	}
	return -1;
}

private void setRawBarBackground(ScreenType)(ScreenType screen,
		int x, int y, int width,
		uint color, int fallbackBg) {
	if(screen is null || width <= 0 || y < 0 || y >= screen.height)
		return;

	int x0 = x;
	int x1 = x + width;
	if(x0 < 0)
		x0 = 0;
	if(x1 > screen.width)
		x1 = screen.width;
	if(x0 >= x1)
		return;

	for(int xpos = x0; xpos < x1; xpos++)
		screen.setbgRaw(xpos, y, color, fallbackBg,
			SEQUENCE_COLOR_BAR_FOREGROUND);
}

private uint sequenceArgbColorForSortedIndex(int index, int count,
		double brightness) {
	if(count <= 0)
		return SEQUENCE_COLOR_FALLBACK_ARGB;

	double hue = SEQUENCE_COLOR_HUE_START;
	if(count > 1)
		hue += cast(double)SEQUENCE_COLOR_HUE_RANGE *
			cast(double)index / cast(double)count;
	return hsbToArgb(hue, SEQUENCE_COLOR_SATURATION, brightness);
}

private bool isValidSequenceNumber(int sequenceNumber) {
	return sequenceNumber >= 0;
}

private void addUniqueSequenceNumber(ref int[] sequenceNumbers,
		int sequenceNumber) {
	foreach(existingSequenceNumber; sequenceNumbers) {
		if(existingSequenceNumber == sequenceNumber)
			return;
	}
	sequenceNumbers ~= sequenceNumber;
}

private void sortSequenceNumbers(ref int[] sequenceNumbers) {
	for(size_t index = 1; index < sequenceNumbers.length; index++) {
		int value = sequenceNumbers[index];
		size_t insertAt = index;
		while(insertAt > 0 && sequenceNumbers[insertAt - 1] > value) {
			sequenceNumbers[insertAt] = sequenceNumbers[insertAt - 1];
			insertAt--;
		}
		sequenceNumbers[insertAt] = value;
	}
}

private uint hsbToArgb(double hueDegrees, double saturationPercent,
		double brightnessPercent) {
	double hue = wrapHueDegrees(hueDegrees);

	double saturation = clampUnit(saturationPercent / 100.0);
	double brightness = clampUnit(brightnessPercent / 100.0);

	double h = hue / 60.0;
	int sector = cast(int)h;
	double fraction = h - sector;
	double p = brightness * (1.0 - saturation);
	double q = brightness * (1.0 - saturation * fraction);
	double t = brightness * (1.0 - saturation * (1.0 - fraction));
	double r, g, b;

	switch(sector) {
	case 0:
		r = brightness;
		g = t;
		b = p;
		break;
	case 1:
		r = q;
		g = brightness;
		b = p;
		break;
	case 2:
		r = p;
		g = brightness;
		b = t;
		break;
	case 3:
		r = p;
		g = q;
		b = brightness;
		break;
	case 4:
		r = t;
		g = p;
		b = brightness;
		break;
	default:
		r = brightness;
		g = p;
		b = q;
		break;
	}

	return (255u << 24) |
		(channelToByte(r) << 16) |
		(channelToByte(g) << 8) |
		channelToByte(b);
}

SequenceRowNumberColors sequenceRowNumberColors(uint canonicalArgb,
		bool accentRow) {
	SequenceRowNumberColors colors;
	colors.backgroundArgb = sequenceTintArgbColor(canonicalArgb,
		SEQUENCE_ROW_BACKGROUND_BRIGHTNESS);
	colors.foregroundArgb = sequenceTintArgbColor(canonicalArgb, accentRow ?
		SEQUENCE_ROW_DIGIT_BRIGHTNESS_ACCENT :
		SEQUENCE_ROW_DIGIT_BRIGHTNESS_NORMAL);
	return colors;
}

private double wrapHueDegrees(double hue) {
	while(hue < 0)
		hue += 360;
	while(hue >= 360)
		hue -= 360;
	return hue;
}

private double clampUnit(double value) {
	if(value < 0.0)
		return 0.0;
	if(value > 1.0)
		return 1.0;
	return value;
}

private uint channelToByte(double value) {
	value = clampUnit(value);
	return cast(uint)(value * 255.0 + 0.5);
}
