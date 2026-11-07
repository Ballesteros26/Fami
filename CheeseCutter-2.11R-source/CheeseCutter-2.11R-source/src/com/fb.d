/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module com.fb;
import derelict.sdl2.sdl;
import std.stdio : stderr;
import std.string : fromStringz, indexOf, toStringz;
import com.appversion;
import com.util;

enum INTERFACE_THEME_COUNT = 4;
enum INTERFACE_PALETTE_COLOR_COUNT = 16;

immutable SDL_Color[INTERFACE_PALETTE_COLOR_COUNT][INTERFACE_THEME_COUNT]
		INTERFACE_PALETTE_PRESETS = [
	[
		{ 0, 0, 0 }, { 252, 252, 252 }, { 104, 52, 40 }, { 112, 164, 176 },
		{ 108, 60, 132 }, { 88, 140, 64 }, { 52, 40, 120 }, { 184, 196, 108 },
		{ 108, 76, 36 }, { 64, 56, 0 }, { 152, 100, 88 }, { 68, 68, 68 },
		{ 108, 108, 108 }, { 152, 208, 132 }, { 108, 92, 180 },
		{ 148, 148, 148 }
	],
	[
		{ 4, 9, 20 }, { 238, 246, 255 }, { 238, 82, 94 }, { 64, 210, 222 },
		{ 184, 112, 224 }, { 72, 196, 132 }, { 72, 116, 232 }, { 244, 210, 92 },
		{ 236, 138, 68 }, { 132, 92, 62 }, { 255, 146, 154 }, { 30, 42, 62 },
		{ 92, 111, 140 }, { 132, 228, 166 }, { 144, 184, 255 },
		{ 190, 207, 230 }
	],
	[
		{ 0, 18, 34 }, { 253, 246, 227 }, { 220, 50, 47 }, { 42, 161, 152 },
		{ 211, 54, 130 }, { 133, 153, 0 }, { 38, 139, 210 }, { 181, 137, 0 },
		{ 203, 75, 22 }, { 101, 82, 53 }, { 239, 118, 112 }, { 7, 54, 66 },
		{ 88, 110, 117 }, { 181, 205, 83 }, { 108, 163, 202 },
		{ 147, 161, 161 }
	],
	[
		{ 12, 12, 12 }, { 255, 255, 255 }, { 213, 94, 0 }, { 86, 180, 233 },
		{ 204, 121, 167 }, { 0, 158, 115 }, { 0, 128, 200 }, { 240, 228, 66 },
		{ 230, 159, 0 }, { 168, 102, 56 }, { 244, 153, 172 }, { 52, 52, 52 },
		{ 128, 128, 128 }, { 104, 210, 166 }, { 120, 190, 232 },
		{ 204, 204, 204 }
	]
];

static assert(INTERFACE_PALETTE_PRESETS.length == INTERFACE_THEME_COUNT);
static assert(INTERFACE_PALETTE_PRESETS[0].length ==
	INTERFACE_PALETTE_COLOR_COUNT);

__gshared SDL_Color[INTERFACE_PALETTE_COLOR_COUNT] PALETTE;
private __gshared int activeInterfaceThemeIndex;

int currentInterfaceTheme() {
	return activeInterfaceThemeIndex;
}

immutable FONT_X = 8, FONT_Y = 14;
__gshared ubyte[] font;
enum INFOBAR_GLYPH_HELP_LEFT = 493;
enum INFOBAR_GLYPH_HELP_RIGHT = 494;
enum INFOBAR_GLYPH_FULLSCREEN_LEFT = 497;
enum INFOBAR_GLYPH_FULLSCREEN_RIGHT = 498;
enum STATUSLINE_GLYPH_FAILURE = 499;
enum INFOBAR_GLYPH_AUDIO_LEFT = 500;
enum INFOBAR_GLYPH_AUDIO_RIGHT = 501;
enum INFOBAR_GLYPH_KEYJAM_LEFT = 502;
enum INFOBAR_GLYPH_KEYJAM_RIGHT = 503;
enum INFOBAR_GLYPH_SAVE_LEFT = 504;
enum INFOBAR_GLYPH_SAVE_RIGHT = 505;
enum INFOBAR_GLYPH_LOAD_LEFT = 506;
enum INFOBAR_GLYPH_LOAD_RIGHT = 507;
enum INFOBAR_GLYPH_THEME_CLASSIC = 508;
enum INFOBAR_GLYPH_THEME_C64 = 509;
enum INFOBAR_GLYPH_THEME_C64_MIDNIGHT = 510;
enum INFOBAR_GLYPH_THEME_NEON = 511;
private enum EXTENDED_UI_GLYPH_COUNT = 17;
private immutable int[EXTENDED_UI_GLYPH_COUNT] EXTENDED_UI_GLYPH_IDS = [
	INFOBAR_GLYPH_HELP_LEFT,
	INFOBAR_GLYPH_HELP_RIGHT,
	INFOBAR_GLYPH_FULLSCREEN_LEFT,
	INFOBAR_GLYPH_FULLSCREEN_RIGHT,
	STATUSLINE_GLYPH_FAILURE,
	INFOBAR_GLYPH_AUDIO_LEFT,
	INFOBAR_GLYPH_AUDIO_RIGHT,
	INFOBAR_GLYPH_KEYJAM_LEFT,
	INFOBAR_GLYPH_KEYJAM_RIGHT,
	INFOBAR_GLYPH_SAVE_LEFT,
	INFOBAR_GLYPH_SAVE_RIGHT,
	INFOBAR_GLYPH_LOAD_LEFT,
	INFOBAR_GLYPH_LOAD_RIGHT,
	INFOBAR_GLYPH_THEME_CLASSIC,
	INFOBAR_GLYPH_THEME_C64,
	INFOBAR_GLYPH_THEME_C64_MIDNIGHT,
	INFOBAR_GLYPH_THEME_NEON
];
private __gshared ubyte[EXTENDED_UI_GLYPH_COUNT * 16] extendedUiGlyphs;
immutable int mode, border = 1;
private bool isDirty = false;

// Development/screenshot-QA aid. Keep false for normal builds so SDL/window
// manager chooses the initial window position; set true locally when a stable
// top-left window origin is needed for repeatable screenshots.
enum DEVELOPMENT_FORCE_WINDOW_ORIGIN = false;
enum DEVELOPMENT_WINDOW_ORIGIN_X = 0;
enum DEVELOPMENT_WINDOW_ORIGIN_Y = 0;

immutable CHECKX = "assert(x >= 0 && x < width);";
immutable CHECKY = "assert(y >= 0 && y < height);";
immutable CHECKS = "assert(x + y >= 0 && x + y < width*height);";

private int extendedUiGlyphIndex(int glyph) pure nothrow @safe {
	foreach(index, supportedGlyph; EXTENDED_UI_GLYPH_IDS) {
		if(glyph == supportedGlyph)
			return cast(int)index;
	}
	return -1;
}

const(ubyte)[] uiGlyphBitmap(int glyph) {
	if(glyph >= 0 && glyph < 256)
		return font[glyph*16..glyph*16+FONT_Y];

	int index = extendedUiGlyphIndex(glyph);
	if(index < 0)
		return null;
	return extendedUiGlyphs[index*16..index*16+FONT_Y];
}

private void blitGlyphPixels(uint* pixel, const(ubyte)* glyph, int stride,
		Uint32 foreground, Uint32 background) {
	for(int row=0; row<FONT_Y; row++, glyph++) {
		int bits = *glyph;
		foreach(bit; 0 .. FONT_X)
			*(pixel++) = bits & (0x80 >> bit) ? foreground : background;
		pixel += stride - FONT_X;
	}
}

bool rasterizeUiGlyph(int glyph, uint[] pixels, int stride,
		Uint32 foreground, Uint32 background) {
	auto bitmap = uiGlyphBitmap(glyph);
	if(bitmap.length != FONT_Y || stride < FONT_X ||
			pixels.length < (FONT_Y - 1) * stride + FONT_X)
		return false;
	blitGlyphPixels(pixels.ptr, bitmap.ptr, stride, foreground, background);
	return true;
}

SDL_Rect interfaceDestinationRect(int availableWidth, int availableHeight,
		int sourceWidth, int sourceHeight) pure nothrow @safe {
	SDL_Rect rect;
	if(availableWidth <= 0 || availableHeight <= 0 ||
			sourceWidth <= 0 || sourceHeight <= 0)
		return rect;

	rect.h = availableHeight;
	rect.w = cast(int)(cast(long)sourceWidth * availableHeight / sourceHeight);
	if(rect.w <= availableWidth) {
		rect.x = (availableWidth - rect.w) / 2;
		rect.y = 0;
		return rect;
	}

	rect.w = availableWidth;
	rect.h = cast(int)(cast(long)sourceHeight * availableWidth / sourceWidth);
	rect.x = 0;
	rect.y = (availableHeight - rect.h) / 2;
	return rect;
}

SDL_Rect interfaceFramebufferTailRect(int framebufferWidth,
		int framebufferHeight, int screenOffsetY, int screenRows,
		int cellHeight) pure nothrow @safe {
	SDL_Rect rect;
	if(framebufferWidth <= 0 || framebufferHeight <= 0 ||
			screenOffsetY < 0 || screenRows < 0 || cellHeight <= 0)
		return rect;

	long paintedHeight = cast(long)screenOffsetY +
		cast(long)screenRows * cellHeight;
	if(paintedHeight < 0)
		paintedHeight = 0;
	else if(paintedHeight > framebufferHeight)
		paintedHeight = framebufferHeight;

	rect.x = 0;
	rect.y = cast(int)paintedHeight;
	rect.w = framebufferWidth;
	rect.h = framebufferHeight - rect.y;
	return rect;
}

bool fillInterfaceFramebufferTail(uint[] pixels, int framebufferWidth,
		int framebufferHeight, int screenOffsetY, int screenRows,
		int cellHeight, Uint32 background) nothrow @safe {
	auto rect = interfaceFramebufferTailRect(framebufferWidth,
		framebufferHeight, screenOffsetY, screenRows, cellHeight);
	long requiredPixels = cast(long)framebufferWidth * framebufferHeight;
	if(rect.w <= 0 || rect.h <= 0 || requiredPixels < 0 ||
			requiredPixels > pixels.length)
		return false;

	foreach(y; rect.y .. rect.y + rect.h) {
		size_t start = cast(size_t)y * framebufferWidth;
		pixels[start .. start + rect.w] = background;
	}
	return true;
}

SDL_Color activeInterfaceBackgroundColor() {
	return PALETTE[0];
}

static this() {
	void[] arr;
	PALETTE[] = INTERFACE_PALETTE_PRESETS[0][];
	font.length = 256*16;
	// realign font data
	immutable rawfont = import("font.psf");
	for(int i=0;i<256;i++) {
		font[i*16..i*16+14] = cast(ubyte[])rawfont[i*FONT_Y+4..i*FONT_Y+4+FONT_Y];
	}
	foreach(i, sourceGlyph; EXTENDED_UI_GLYPH_IDS) {
		extendedUiGlyphs[i*16..i*16+FONT_Y] = cast(ubyte[])
			rawfont[sourceGlyph*FONT_Y+4..sourceGlyph*FONT_Y+4+FONT_Y];
	}
}


class Video {
	private struct ExtendedUiGlyphCell {
		int x, y;
		ushort glyph;
		ubyte foreground, background;
		bool active;
	}

	protected {
    SDL_Window* window;
    SDL_Renderer* renderer;
    SDL_Texture* texture;
    uint[] framebuffer;
		bool useFullscreen;
		Screen screen;
		const int requestedWidth, requestedHeight, screenOffsetY;
    int correctedHeight, correctedWidth;
		int height, width; // resolution of window
		//int displayHeight, displayWidth; // resolution of the monitor
		SDL_Rect destRect;
	}
	private ExtendedUiGlyphCell[EXTENDED_UI_GLYPH_COUNT]
		extendedUiGlyphOverlay;

	this(int wx, int wy, Screen scr, int fs, int screenOffsetY = 0) {
		this.screen = scr;
		this.requestedHeight = wy;
		this.requestedWidth = wx;
		this.screenOffsetY = screenOffsetY;
    this.framebuffer = new uint[wx*wy];
		fillInterfaceFramebufferTail(framebuffer, wx, wy, screenOffsetY,
			scr.height, FONT_Y, getColor(0));
	}


	~this() {
		if(renderer !is null)
			SDL_DestroyRenderer(renderer);

    // if(texture !is null)
    //   SDL_DestroyTexture

    if(window !is null)
      SDL_DestroyWindow(window);

	}

	bool init() {
		width = requestedWidth;
		height = requestedHeight;
		useFullscreen = false;

    import std.string, std.stdio;

		int windowX = SDL_WINDOWPOS_UNDEFINED;
		int windowY = SDL_WINDOWPOS_UNDEFINED;
		bool forceWindowPosition = DEVELOPMENT_FORCE_WINDOW_ORIGIN;
		if(forceWindowPosition) {
			windowX = DEVELOPMENT_WINDOW_ORIGIN_X;
			windowY = DEVELOPMENT_WINDOW_ORIGIN_Y;
		}
		auto windowTitle = (com.appversion.APP_DISPLAY_NAME ~
		                    com.util.buildInfo()).toStringz;
		window = SDL_CreateWindow(windowTitle, windowX, windowY,
	                              requestedWidth, requestedHeight,
	                              windowCreationFlags());

	    if (window is null) {
	      return false;
	    }

			applyFixedWindowedSizeLimits();

			if(forceWindowPosition) {
				SDL_SetWindowPosition(window, windowX, windowY);
			}

    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);

    if (renderer is null) {
      return false;
    }

    texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                SDL_TEXTUREACCESS_TARGET, requestedWidth, requestedHeight);

    if (texture is null) {
      return false;
    }

    SDL_SetRenderTarget(renderer, null);

    calcAspect();
    screen.refresh();

	    return true;
		}

	bool applyInterfaceTheme(int themeIndex) {
		if(themeIndex < 0 || themeIndex >= INTERFACE_THEME_COUNT ||
				themeIndex == activeInterfaceThemeIndex)
			return false;

		PALETTE[] = INTERFACE_PALETTE_PRESETS[themeIndex][];
		activeInterfaceThemeIndex = themeIndex;
		screen.refresh();
		return true;
	}

  void drawVisualizer(int) {}

	void fillRect(int x, int y, int w, int h, int color) {
		fillRectRaw(x, y, w, h, paletteColor(color));
	}

	void drawVLine(int x, int y, int h, int color) {
		fillRect(x, y, 1, h, color);
	}

	void drawHLine(int x, int y, int w, int color) {
		fillRect(x, y, w, 1, color);
	}

	void fillRectRaw(int x, int y, int w, int h, Uint32 color) {
		if(!clipRect(x, y, w, h))
			return;

		uint* row = framebuffer.ptr + y * width + x;
		for(int py = 0; py < h; py++) {
			uint* pixel = row;
			for(int px = 0; px < w; px++) {
				*pixel++ = color;
			}
			row += width;
		}
		isDirty = true;
	}

	protected bool setWindowFullscreenFlags(Uint32 flags) {
		if(window is null)
			return false;
		if(SDL_SetWindowFullscreen(window, flags) != 0) {
			stderr.writefln("SDL_SetWindowFullscreen failed: %s",
				SDL_GetError().fromStringz);
			return false;
		}
		return true;
	}

	protected SDL_WindowFlags windowCreationFlags() {
		return cast(SDL_WindowFlags)SDL_WINDOW_SHOWN;
	}

	protected void setWindowSizeLimits(int minWidth, int minHeight,
			int maxWidth, int maxHeight) {
		SDL_SetWindowMinimumSize(window, minWidth, minHeight);
		SDL_SetWindowMaximumSize(window, maxWidth, maxHeight);
	}

	protected void setWindowSize(int width, int height) {
		SDL_SetWindowSize(window, width, height);
	}

	protected void getWindowSize(ref int width, ref int height) {
		SDL_GetWindowSize(window, &width, &height);
	}

	protected void applyFixedWindowedSizeLimits() {
		setWindowSizeLimits(requestedWidth, requestedHeight,
			requestedWidth, requestedHeight);
	}

	protected void relaxWindowSizeLimitsForFullscreen() {
		int displayWidth = requestedWidth;
		int displayHeight = requestedHeight;
		getWindowDisplaySize(displayWidth, displayHeight);
		setWindowSizeLimits(1, 1, displayWidth, displayHeight);
	}

	protected void getWindowDisplaySize(ref int width, ref int height) {
		if(window is null)
			return;

		int displayIndex = SDL_GetWindowDisplayIndex(window);
		if(displayIndex >= 0) {
			SDL_Rect bounds;
			if(SDL_GetDisplayBounds(displayIndex, &bounds) == 0 &&
					bounds.w > 0 && bounds.h > 0) {
				width = bounds.w;
				height = bounds.h;
				return;
			}

			SDL_DisplayMode mode;
			if(SDL_GetDesktopDisplayMode(displayIndex, &mode) == 0 &&
					mode.w > 0 && mode.h > 0) {
				width = mode.w;
				height = mode.h;
			}
		}
	}

	protected bool restoreFixedWindowedSizeIfNeeded() {
		int windowWidth, windowHeight;
		getWindowSize(windowWidth, windowHeight);
		if(windowWidth == requestedWidth && windowHeight == requestedHeight)
			return false;
		setWindowSize(requestedWidth, requestedHeight);
		return true;
	}

	protected bool enableFullscreen(bool fs) {
		Uint32 flags = fs ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0;
		if(fs)
			relaxWindowSizeLimitsForFullscreen();
		if(!setWindowFullscreenFlags(flags)) {
			if(fs) {
				applyFixedWindowedSizeLimits();
				restoreFixedWindowedSizeIfNeeded();
				calcAspect();
				screen.refresh();
			}
			return false;
		}
		if(!fs) {
			restoreFixedWindowedSizeIfNeeded();
			applyFixedWindowedSizeLimits();
		}
		calcAspect();
		screen.refresh();
		return true;
	}

	bool toggleFullscreen() {
		bool requestedFullscreen = !useFullscreen;
		if(!enableFullscreen(requestedFullscreen))
			return false;
		useFullscreen = requestedFullscreen;
		return true;
	}

	bool scalePosition(ref int x, ref int y) {
		if(destRect.w <= 0 || destRect.h <= 0)
			return false;
		if(x < destRect.x || y < destRect.y ||
				x >= destRect.x + destRect.w ||
				y >= destRect.y + destRect.h)
			return false;

		long localX = x - destRect.x;
		long localY = y - destRect.y;
		x = cast(int)(localX * requestedWidth / destRect.w);
		y = cast(int)(localY * requestedHeight / destRect.h);
		return x >= 0 && x < requestedWidth && y >= 0 && y < requestedHeight;
	}

	private void blitGlyph(uint* pixel, int glyph,
			Uint32 foreground, Uint32 background) {
		auto bitmap = uiGlyphBitmap(glyph);
		assert(bitmap.length == FONT_Y);
		blitGlyphPixels(pixel, bitmap.ptr, width, foreground, background);
	}

	private void submitExtendedUiGlyph(int x, int y, int glyph,
			int foreground, int background) {
		int index = extendedUiGlyphIndex(glyph);
		assert(index >= 0);
		assert(x >= 0 && x < screen.width && y >= 0 && y < screen.height);
		assert(foreground >= 0 && foreground < PALETTE.length);
		assert(background >= 0 && background < PALETTE.length);

		ExtendedUiGlyphCell next = ExtendedUiGlyphCell(x, y,
			cast(ushort)glyph,
			cast(ubyte)foreground, cast(ubyte)background, true);
		ExtendedUiGlyphCell current = extendedUiGlyphOverlay[index];
		if(current == next)
			return;

		if(current.active && (current.x != x || current.y != y))
			screen.invalidateRect(current.x, current.y, 1, 1);
		screen.invalidateRect(x, y, 1, 1);
		extendedUiGlyphOverlay[index] = next;
		isDirty = true;
	}

	private void clearExtendedUiGlyph(int glyph) {
		int index = extendedUiGlyphIndex(glyph);
		assert(index >= 0);
		ExtendedUiGlyphCell current = extendedUiGlyphOverlay[index];
		if(!current.active)
			return;
		screen.invalidateRect(current.x, current.y, 1, 1);
		extendedUiGlyphOverlay[index] = ExtendedUiGlyphCell.init;
		isDirty = true;
	}

	void submitInfobarExtendedGlyph(int x, int y, int glyph,
			int foreground, int background) {
		assert(glyph != STATUSLINE_GLYPH_FAILURE &&
			extendedUiGlyphIndex(glyph) >= 0);
		submitExtendedUiGlyph(x, y, glyph, foreground, background);
	}

	void submitStatuslineFailureGlyph(int x, int y,
			int foreground, int background) {
		submitExtendedUiGlyph(x, y, STATUSLINE_GLYPH_FAILURE,
			foreground, background);
	}

	void clearStatuslineFailureGlyph() {
		clearExtendedUiGlyph(STATUSLINE_GLYPH_FAILURE);
	}

	bool syncScreenToFramebuffer() {
		int x, y;
		int a;
		ushort* bptr = &screen.data[0];
		ushort* cptr = &screen.olddata[0];
    uint* sptr = framebuffer.ptr + screenOffsetY * width;
		uint* sp;
		ubyte ubg, ufg;

		if (!isDirty) return false;
		isDirty = false;

		for(y = 0;y < screen.height; y++) {
			for(x = 0; x < screen.width; x++) {
				if(*bptr != *cptr) {
					*cptr = *bptr;
					sp = sptr;
					a = *bptr & 255;
					ufg = (*bptr >> 8) & 15;
					ubg = (*bptr >> 12);
					auto fgcolor = screen.cellPixelColor(x, y, true,
						getColor(ufg), getColor(ubg));
					Uint32 bgcolor = screen.cellPixelColor(x, y, false,
						getColor(ufg), getColor(ubg));
					blitGlyph(sp, a, fgcolor, bgcolor);
				}
				sptr += 8;
				bptr++;
				cptr++;
			}
			sptr += width*13;
		}

		return true;
	}

	private void blitExtendedUiGlyphOverlay() {
		foreach(const ref cell; extendedUiGlyphOverlay) {
			if(!cell.active)
				continue;
			auto foreground = getColor(cell.foreground);
			auto background = getColor(cell.background);
			int pixelX = cell.x * FONT_X;
			int pixelY = screenOffsetY + cell.y * FONT_Y;
			uint* pixel = framebuffer.ptr + pixelY * width + pixelX;
			blitGlyph(pixel, cell.glyph, foreground, background);
		}
	}

	  void updateFrame() {
		if(!syncScreenToFramebuffer())
			return;
		fillInterfaceFramebufferTail(framebuffer, width, height, screenOffsetY,
			screen.height, FONT_Y, getColor(0));
		blitExtendedUiGlyphOverlay();

	    // Apparently this is fairly slow: https://wiki.libsdl.org/SDL3/SDL_UpdateTexture
    SDL_UpdateTexture(texture, null, framebuffer.ptr, cast(int)(width * uint.sizeof));
		auto background = activeInterfaceBackgroundColor();
    SDL_SetRenderDrawColor(renderer, background.r, background.g,
			background.b, 255);
    SDL_RenderClear(renderer);
    SDL_RenderCopy(renderer, texture, null, &destRect);
    SDL_RenderPresent(renderer);
	}

	void resizeEvent(int nw, int nh) {
		if(!useFullscreen) {
			restoreFixedWindowedSizeIfNeeded();
			applyFixedWindowedSizeLimits();
		}
    calcAspect();
		screen.refresh();
	}

	private void calcAspect() {
    int windowWidth, windowHeight;

    getWindowSize(windowWidth, windowHeight);

		destRect = interfaceDestinationRect(windowWidth, windowHeight,
			requestedWidth, requestedHeight);
		correctedWidth = destRect.w;
		correctedHeight = destRect.h;
	}

	private bool clipRect(ref int x, ref int y, ref int w, ref int h) {
		if(w <= 0 || h <= 0)
			return false;

		long x0 = x;
		long y0 = y;
		long x1 = cast(long)x + cast(long)w;
		long y1 = cast(long)y + cast(long)h;

		if(x1 <= 0 || y1 <= 0 || x0 >= width || y0 >= height)
			return false;

		if(x0 < 0) x0 = 0;
		if(y0 < 0) y0 = 0;
		if(x1 > width) x1 = width;
		if(y1 > height) y1 = height;
		if(x0 >= x1 || y0 >= y1)
			return false;

		x = cast(int)x0;
		y = cast(int)y0;
		w = cast(int)(x1 - x0);
		h = cast(int)(y1 - y0);
		return true;
	}

		private Uint32 paletteColor(int color) {
			if(color < 0)
				color = 0;
			else if(color >= PALETTE.length)
				color = cast(int)PALETTE.length - 1;
			return getColor(color);
		}
	}


class Screen {
	Uint16[] data;
	private Uint16[] olddata;
	private Uint32[] rawfg;
	private Uint32[] rawbg;
	private ubyte[] rawfgSet;
	private ubyte[] rawbgSet;
	immutable int width, height;
	alias width w;
	alias height h;

	this(int xchars, int ychars) {
		width = xchars;
		height = ychars;
		data.length = xchars * ychars;
		olddata.length = xchars * ychars;
		rawfg.length = xchars * ychars;
		rawbg.length = xchars * ychars;
		rawfgSet.length = xchars * ychars;
		rawbgSet.length = xchars * ychars;
		refresh();
	}

	Uint16 getChar(int x, int y) {
		mixin(CHECKS);
		return data[x + y * width];
	}

	void setChar(int x, int y, Uint16 c) {
		mixin(CHECKS);
		int idx = x + y * width;
		clearRawColors(idx);
		data[idx] = c;
		isDirty = true;
	}

	void setColor(int x, int y, int fg, int bg) {
		mixin(CHECKS);
		int idx = x + y * width;
		clearRawColors(idx);
		Uint16* s = &data[idx];
		*s &= 0xff;
		*s |= (fg << 8) | (bg << 12);
		isDirty = true;
	}

	int getbg(int x, int y) {
		return getChar(x, y) >> 12;
	}

	void setbg(int x, int y, int bg) {
		int idx = x + y * width;
		clearRawBg(idx);
		Uint16* s = &data[idx];
		*s &= 0xfff;
		*s |= (bg << 12);
		isDirty = true;
	}

	void setbgRaw(int x, int y, Uint32 color, int fallbackBg,
			int foreground = -1) {
		mixin(CHECKS);
		if(fallbackBg < 0)
			fallbackBg = 0;
		else if(fallbackBg > 15)
			fallbackBg = 15;
		int idx = x + y * width;
		Uint16* s = &data[idx];
		*s &= 0xfff;
		*s |= (fallbackBg << 12);
		if(foreground >= 0) {
			if(foreground > 15)
				foreground = 15;
			clearRawFg(idx);
			*s &= 0xf0ff;
			*s |= foreground << 8;
		}
		rawbg[idx] = color;
		rawbgSet[idx] = 1;
		olddata[idx] = 255;
		isDirty = true;
	}

	void setColorsRaw(int x, int y, Uint32 foreground, Uint32 background) {
		mixin(CHECKS);
		int idx = x + y * width;
		rawfg[idx] = foreground;
		rawbg[idx] = background;
		rawfgSet[idx] = 1;
		rawbgSet[idx] = 1;
		olddata[idx] = 255;
		isDirty = true;
	}

	Uint32 cellPixelColor(int x, int y, bool glyphPixel,
			Uint32 paletteForeground, Uint32 paletteBackground) const {
		mixin(CHECKS);
		int idx = x + y * width;
		if(glyphPixel)
			return rawfgSet[idx] ? rawfg[idx] : paletteForeground;
		return rawbgSet[idx] ? rawbg[idx] : paletteBackground;
	}

	void clearCells(int x, int y, int w, int h) {
		if(w <= 0 || h <= 0)
			return;
		assert(x >= 0 && y >= 0 && x + w <= width && y + h <= height);

		foreach(row; y .. y + h) {
			int start = x + row * width;
			int end = start + w;
			data[start .. end] = 0;
			olddata[start .. end] = 255;
			rawfg[start .. end] = 0;
			rawbg[start .. end] = 0;
			rawfgSet[start .. end] = 0;
			rawbgSet[start .. end] = 0;
		}
		isDirty = true;
	}

	void clrtoeol(int y, int bg) {
		clrtoeol(0, y, bg);
	}

	void clrtoeol(int x, int y, int bg) {
		mixin(CHECKY);
		int idx = x + y * width;
		Uint16* s = &data[idx];
		Uint16 v = cast(Uint16)(0x20 | (bg << 12));
		while(x++ < width) {
			clearRawColors(idx++);
			*s++ = v;
		}
		isDirty = true;
	}

	void clrscr() {
		data[] = 0x20;
		rawfg[] = 0;
		rawbg[] = 0;
		rawfgSet[] = 0;
		rawbgSet[] = 0;
		olddata[] = 255;
		isDirty = true;
	}

	void refresh() {
		olddata[] = 255;
		isDirty = true;
	}

	final void invalidateRect(int x, int y, int w, int h) {
		if(w <= 0 || h <= 0)
			return;
		int x0 = x;
		int y0 = y;
		int x1 = x + w;
		int y1 = y + h;
		if(x0 < 0) x0 = 0;
		if(y0 < 0) y0 = 0;
		if(x1 > width) x1 = width;
		if(y1 > height) y1 = height;
		if(x0 >= x1 || y0 >= y1)
			return;

		foreach(row; y0 .. y1) {
			int idx = x0 + row * width;
			foreach(col; 0 .. x1 - x0)
				olddata[idx + col] = 255;
		}
		isDirty = true;
	}

	void cprint(int x, int y, int fg, int bg, string txt) {
		mixin(CHECKS);
		bool skipbg, skipfg;
		if(bg < 0) { skipbg = true; bg = 0; }
		if(fg < 0) { skipfg = true; fg = 0; }
		int base = x + y * width;
		Uint16[] s = data[base .. base + txt.length];
		Uint16 col = cast(Uint16)((fg << 8) | (bg << 12));
		foreach(i, char c; txt) {
			int idx = base + cast(int)i;
			if(!skipbg)
				clearRawBg(idx);
			if(!skipfg)
				clearRawFg(idx);
			if(skipbg)
				col = cast(Uint16)((fg << 8) | (s[i] & 0xf000));
			if(skipfg)
				col = cast(Uint16)((bg << 12) | (s[i] & 0x0f00));

			s[i] = cast(Uint16)(c | col);
		}
		isDirty = true;
	}

	void fprint(int x, int y, string str) {
		mixin(CHECKS);
		assert(str.length < 256);
		int outIndex = x + y * width;
		Uint16[] outb = data[outIndex .. $];
		int bg = 0, fg = 0;
		int idx;
		while(idx < str.length) {
			int getcol(char c) {
				return cast(int)(c == '+' ? -1 : "0123456789abcdef".indexOf(c));
			}
			if(str[idx] == '`') {
				bg = getcol(str[idx + 1]);
				fg = getcol(str[idx + 2]);
				idx += 3;
				continue;
			}
			if(bg >= 0) {
				clearRawBg(outIndex);
				outb[0] &= 0x0fff;
				outb[0] |= bg << 12;
			}
			if(fg >= 0) {
				clearRawFg(outIndex);
				outb[0] &= 0xf0ff;
				outb[0] |= fg << 8;
			}
			outb[0] &= 0xff00;
			outb[0] |= str[idx] & 255;
			outb = outb[1 .. $];
			outIndex++;
			idx++;
		}
		isDirty = true;
	}

	private void clearRawBg(int idx) {
		if(idx < 0 || idx >= cast(int)rawbgSet.length)
			return;
		if(rawbgSet[idx]) {
			rawbgSet[idx] = 0;
			olddata[idx] = 255;
		}
	}

	private void clearRawFg(int idx) {
		if(idx < 0 || idx >= cast(int)rawfgSet.length)
			return;
		if(rawfgSet[idx]) {
			rawfgSet[idx] = 0;
			olddata[idx] = 255;
		}
	}

	private void clearRawColors(int idx) {
		clearRawFg(idx);
		clearRawBg(idx);
	}
}

void enableKeyRepeat() {
  //	SDL_EnableKeyRepeat(200, 10);
}

void disableKeyRepeat() {
	//SDL_EnableKeyRepeat(0, 0);
}

Uint32 getColor(int c) {
  return (255u << 24) | (cast(Uint32)PALETTE[c].r << 16) |
         (cast(Uint32)PALETTE[c].g << 8) | cast(Uint32)PALETTE[c].b;
}

auto getColor(SDL_Surface* s, int c) {
  return s is null ? getColor(c) :
    SDL_MapRGBA(s.format, PALETTE[c].r, PALETTE[c].g, PALETTE[c].b, 255);
}
