/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module main;
import derelict.sdl2.sdl;
import com.fb;
import com.appversion : APP_DISPLAY_NAME;
import com.session;
import com.kbd;
import com.util;
import ct.base;
import ui.ui;
import ui.input;
import audio.player;
import audio.resid.filter;
import audio.audio, audio.timer;
import ui.trackoverviewlayout : trackOverviewGuiStartY;
debug import ui.trackoverviewstate : runTrackOverviewSelfChecks;
import std.stdio;
import std.string;
import std.conv;
import std.file;

private enum UI_FRAME_RATE_HZ = 60;

version(linux) {
	const DIR_SEPARATOR = '/';
}

version(FreeBSD) {
	const DIR_SEPARATOR = '/';
}

version(OSX) {
	const DIR_SEPARATOR = '/';
}

version(Windows) {
	const DIR_SEPARATOR = '\\';
}

bool initVideo() {
	int mx = 800, my = 600;

	if( SDL_Init(SDL_INIT_VIDEO) < 0) return false;
	SDL_EventState(SDL_DROPFILE, SDL_ENABLE);

	int width = mx / FONT_X;
	int height = my / FONT_Y;
	int overviewGuiStartY = trackOverviewGuiStartY();
	screen = new Screen(width, height);
	video = new Video(mx, my + overviewGuiStartY, screen, 0,
		overviewGuiStartY);
	  return video.init();
}

private int shiftedDigit(int key) {
	switch(key) {
	case SDLK_0: return ')';
	case SDLK_1: return '!';
	case SDLK_2: return '@';
	case SDLK_3: return '#';
	case SDLK_4: return '$';
	case SDLK_5: return '%';
	case SDLK_6: return '^';
	case SDLK_7: return '&';
	case SDLK_8: return '*';
	case SDLK_9: return '(';
	default: return 0;
	}
}

private int printableKey(int key, int mods) {
	bool shift = (mods & KMOD_SHIFT) != 0;
	if(key >= SDLK_a && key <= SDLK_z)
		return shift ? key - ('a' - 'A') : key;
	if(key >= SDLK_0 && key <= SDLK_9)
		return shift ? shiftedDigit(key) : key;

	switch(key) {
	case SDLK_SPACE: return ' ';
	case SDLK_MINUS: return shift ? '_' : '-';
	case SDLK_EQUALS: return shift ? '+' : '=';
	case SDLK_LEFTBRACKET: return shift ? '{' : '[';
	case SDLK_RIGHTBRACKET: return shift ? '}' : ']';
	case SDLK_BACKSLASH: return shift ? '|' : '\\';
	case SDLK_SEMICOLON: return shift ? ':' : ';';
	case SDLK_QUOTE: return shift ? '"' : '\'';
	case SDLK_COMMA: return shift ? '<' : ',';
	case SDLK_PERIOD: return shift ? '>' : '.';
	case SDLK_SLASH: return shift ? '?' : '/';
	case SDLK_BACKQUOTE: return shift ? '~' : '`';
	default: return 0;
	}
}

private int keyUnicode(int key, int mods, int unicode) {
	int printable = printableKey(key, mods);
	if(printable)
		return printable;
	switch(key) {
	case SDLK_RETURN, SDLK_ESCAPE, SDLK_BACKSPACE, SDLK_TAB, SDLK_DELETE:
		return key;
	default:
		return unicode >= 0x20 && unicode <= 0x7e ? unicode : 0;
	}
}

private const(char)[] sdlEventText(const(char)* text) {
	if(text is null)
		return "";
	return fromStringz(text);
}

void mainloop() {
	int mods, key, unicode;
	bool quit = false;
	bool middleScrollActive = false;
	int middleScrollRemainder = 0;
	enum int MOUSE_BUTTON_MIDDLE = 2;
	enum uint MOUSE_BUTTON_MIDDLE_MASK = 1 << (MOUSE_BUTTON_MIDDLE - 1);
	enum int MOUSE_WHEEL_SCROLL_ROWS = 4;
	enum int MIDDLE_SCROLL_STEP_PIXELS = FONT_Y;

	bool scrollByRows(int rows) {
		bool scrolled = false;
		while(rows > 0) {
			mainui.keypress(Keyinfo(SDLK_DOWN, 0, 0));
			rows--;
			scrolled = true;
		}
		while(rows < 0) {
			mainui.keypress(Keyinfo(SDLK_UP, 0, 0));
			rows++;
			scrolled = true;
		}
		return scrolled;
	}

	bool scrollByPixels(int pixels) {
		bool scrolled = false;
		middleScrollRemainder += pixels;
		while(middleScrollRemainder >= MIDDLE_SCROLL_STEP_PIXELS) {
			scrollByRows(1);
			middleScrollRemainder -= MIDDLE_SCROLL_STEP_PIXELS;
			scrolled = true;
		}
		while(middleScrollRemainder <= -MIDDLE_SCROLL_STEP_PIXELS) {
			scrollByRows(-1);
			middleScrollRemainder += MIDDLE_SCROLL_STEP_PIXELS;
			scrolled = true;
		}
		return scrolled;
	}

	bool framebufferToCellPosition(ref int x, ref int y) {
		return framebufferPixelToCell(x, y, trackOverviewGuiStartY(),
			FONT_X, FONT_Y, screen.width, screen.height);
	}

	void updateAndPresent() {
		mainui.update();
		video.updateFrame();
	}

	void routeKeyinfo(Keyinfo keyinfo) {
		if(mainui.activeInput !is null) {
			Cursor cursor = mainui.activeInput.cursor;
			if(cursor !is null) cursor.reset();
		}
		mainui.keypress(keyinfo);
		if(mainui.exitRequested)
			quit = true;
		mainui.update();
	}

	void resetTextComposition() {
		bool textInputWasActive = SDL_IsTextInputActive() == SDL_TRUE;
		SDL_StopTextInput();
		if(textInputWasActive)
			SDL_StartTextInput();
	}

	bool suppressNextOptionIDeadKeyTextInput = false;
	bool suppressNextCommandWindowSdlQuit = false;
	ulong performanceFrequency = SDL_GetPerformanceFrequency();
	ulong framePeriod = performanceFrequency / UI_FRAME_RATE_HZ;
	if(framePeriod == 0)
		framePeriod = 1;
	ulong nextFrameDeadline = SDL_GetPerformanceCounter() + framePeriod;

	SDL_Event evt;
	while(!quit) {
		bool f6DragRedrawPending = false;
		int ticks = audio.timer.readTick();
		mainui.timerEvent(ticks);
		while(SDL_PollEvent(&evt)) {
			switch(evt.type) {
			case SDL_QUIT:
				if(suppressNextCommandWindowSdlQuit) {
					suppressNextCommandWindowSdlQuit = false;
					break;
				}
				mainui.mouseButtonUp(1);
				quit = true;
				break;
			case SDL_DROPFILE:
				if(evt.drop.file !is null) {
					openFile(evt.drop.file);
					SDL_free(evt.drop.file);
					mainui.update();
				}
				break;
			case SDL_KEYDOWN:
				mods = evt.key.keysym.mod;
				key = evt.key.keysym.sym;
				mods &= ~KMOD_NUM;
				unicode = keyUnicode(key, mods, evt.key.keysym.unicode);
				auto keyinfo = Keyinfo(key, mods, unicode,
					evt.key.keysym.scancode);
				com.kbd.translate(keyinfo);
				version(OSX) {
					if ((key == SDLK_q || key == SDLK_w) &&
							evt.key.keysym.mod & KMOD_GUI) {
						KeyboardActionId actionId;
						if(resolveQuitConfirmKeyboardAction(keyinfo, actionId))
							mainui.handleQuitConfirmAction(actionId);
						mainui.update();
						suppressNextCommandWindowSdlQuit = true;
						break;
					}
				}

				routeKeyinfo(keyinfo);
				break;
			case SDL_KEYUP:
				mods = evt.key.keysym.mod;
				key = evt.key.keysym.sym;
				mods &= ~KMOD_NUM;
				unicode = keyUnicode(key, mods, evt.key.keysym.unicode);
				Keyinfo keyinfo = Keyinfo(key, mods, unicode,
					evt.key.keysym.scancode);
				mainui.keyrelease(keyinfo);
				break;
			case SDL_TEXTINPUT:
				mods = SDL_GetModState();
				mods &= ~KMOD_NUM;
				auto textInputText = sdlEventText(
					cast(const(char)*)evt.text.text.ptr);
				Keyinfo textInputKeyinfo;
				if(workspaceNavigationKeyinfoFromTextComposition(
						textInputText, mods, textInputKeyinfo)) {
					if(suppressNextOptionIDeadKeyTextInput) {
						suppressNextOptionIDeadKeyTextInput = false;
						resetTextComposition();
						break;
					}
					routeKeyinfo(textInputKeyinfo);
					resetTextComposition();
				}
				else
					suppressNextOptionIDeadKeyTextInput = false;
				break;
			case SDL_TEXTEDITING:
				mods = SDL_GetModState();
				mods &= ~KMOD_NUM;
				auto textEditingText = sdlEventText(
					cast(const(char)*)evt.edit.text.ptr);
				Keyinfo textEditingKeyinfo;
				if(workspaceNavigationKeyinfoFromTextComposition(
						textEditingText, mods, textEditingKeyinfo)) {
					routeKeyinfo(textEditingKeyinfo);
					suppressNextOptionIDeadKeyTextInput = true;
					resetTextComposition();
				}
				else
					suppressNextOptionIDeadKeyTextInput = false;
				break;
			case SDL_MOUSEBUTTONDOWN:
				switch(evt.button.button) {
				case 1, 3:
					auto eventPosition = mouseButtonEventPosition(
						evt.button.x, evt.button.y);
					int x = eventPosition.x;
					int y = eventPosition.y;
					if(!video.scalePosition(x, y))
						break;
					if(mainui.clickedAtPixel(x, y, evt.button.button,
							evt.button.clicks))
						break;
					if(!framebufferToCellPosition(x, y))
						break;
					if(mainui.fileDialogClickedAt(x, y, evt.button.button,
							evt.button.clicks))
						break;
					mainui.clickedAt(x, y, evt.button.button);
					break;
				case 5:
					scrollByRows(MOUSE_WHEEL_SCROLL_ROWS);
					break;
				case 4:
					scrollByRows(-MOUSE_WHEEL_SCROLL_ROWS);
					break;
				case MOUSE_BUTTON_MIDDLE:
					middleScrollActive = true;
					middleScrollRemainder = 0;
					break;
				default:
					break;
				}
				updateAndPresent();
				break;
			case SDL_MOUSEBUTTONUP:
				if(mainui.mouseButtonUpPixel(evt.button.button))
					updateAndPresent();
				else if(mainui.mouseButtonUp(evt.button.button))
					updateAndPresent();
				if(evt.button.button == MOUSE_BUTTON_MIDDLE) {
					middleScrollActive = false;
					middleScrollRemainder = 0;
				}
				break;
			case SDL_MOUSEWHEEL:
				int wheelX = evt.wheel.x;
				if(evt.wheel.direction == SDL_MOUSEWHEEL_FLIPPED)
					wheelX = -wheelX;
				if(wheelX != 0) {
					int x, y;
					SDL_GetMouseState(&x, &y);
					if(video.scalePosition(x, y) &&
							mainui.mouseWheelPixel(x, y, wheelX)) {
						updateAndPresent();
						break;
					}
				}

				int wheelRows = evt.wheel.y;
				if(evt.wheel.direction == SDL_MOUSEWHEEL_FLIPPED)
					wheelRows = -wheelRows;
				if(wheelRows != 0) {
					int x, y;
					SDL_GetMouseState(&x, &y);
					if(video.scalePosition(x, y) &&
							framebufferToCellPosition(x, y) &&
							mainui.fileDialogMouseWheelAt(x, y,
								-wheelRows * MOUSE_WHEEL_SCROLL_ROWS)) {
						updateAndPresent();
						break;
					}
				}
				if(wheelRows > 0 && scrollByRows(-wheelRows * MOUSE_WHEEL_SCROLL_ROWS))
					updateAndPresent();
				else if(wheelRows < 0 && scrollByRows(-wheelRows * MOUSE_WHEEL_SCROLL_ROWS))
					updateAndPresent();
				break;
			case SDL_MOUSEMOTION:
				int x, y;
				x = evt.motion.x;
				y = evt.motion.y;
				if(video.scalePosition(x, y)) {
					if(mainui.mouseMotionPixel(x, y))
						updateAndPresent();
					else if(framebufferToCellPosition(x, y) &&
							mainui.mouseMotionAt(x, y))
						f6DragRedrawPending = true;
				}
				if(middleScrollActive) {
					if((evt.motion.state & MOUSE_BUTTON_MIDDLE_MASK) == 0) {
						middleScrollActive = false;
						middleScrollRemainder = 0;
					}
					else if(scrollByPixels(evt.motion.yrel))
						updateAndPresent();
				}
				break;
      case SDL_WINDOWEVENT:
        if (evt.window.event == SDL_WINDOWEVENT_RESIZED ||
            evt.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
          video.resizeEvent(evt.window.data1, evt.window.data2);
          mainui.update();
        }
				else if(evt.window.event == SDL_WINDOWEVENT_FOCUS_LOST) {
					audio.player.cancelF6AuditionRelease();
					mainui.mouseButtonUp(1);
				}
        break;
			default:
				break;
			}
		}
		audio.player.serviceF6AuditionRelease();
		if(f6DragRedrawPending)
			mainui.update();
		if(mainui.activeInput !is null) {
			mainui.activeInput.update();
			Cursor cursor = mainui.activeInput.cursor;
			if(cursor !is null) cursor.blink();
		}
			video.updateFrame();

			ulong now = SDL_GetPerformanceCounter();
			if(now < nextFrameDeadline) {
				ulong remaining = nextFrameDeadline - now;
				uint waitMilliseconds = cast(uint)(
					(remaining * 1000 + performanceFrequency - 1) /
					performanceFrequency);
				if(waitMilliseconds > 0)
					SDL_Delay(waitMilliseconds);
				now = SDL_GetPerformanceCounter();
			}

			if(now > nextFrameDeadline &&
					now - nextFrameDeadline > framePeriod)
				nextFrameDeadline = now;
			nextFrameDeadline += framePeriod;
		}
	}

void printheader() {
	stderr.writefln("%s (C) 2009-15 Abaddon", APP_DISPLAY_NAME);
	stderr.writefln("Released under GNU GPL.");
	stderr.writef("\n");
	stderr.writefln("Usage: ccutter [OPTION]... [FILE]");
	stderr.writef("\n");
	stderr.writefln("Options:");
	stderr.writefln("  -b [value]       Set playback buffer size (def=%d)",
		audio.audio.DEFAULT_AUDIO_REQUEST.bufferSamples);
	stderr.writefln("  -nofp            Do not use resid-fp emulation");
	stderr.writefln("  -fpr [x]         Specify filter preset. x = 0..16 for 6581 and 0..1 for 8580");
	stderr.writefln("  -i               Disable resid interpolation (use fast mode instead)");
	stderr.writefln("  -m [0|1]         Specify SID model for reSID (6581/8580) (def=0)");
	stderr.writefln("  -n               Enable NTSC mode");
	stderr.writefln("  -r [value]       Set playback frequency (def=%d)",
		audio.audio.DEFAULT_AUDIO_REQUEST.sampleRate);
	stderr.writef("\n");
}

int main(char[][] args) {
	int i;
	string filename;
	bool fnDefined = false;
	auto requestedAudio = audio.audio.DEFAULT_AUDIO_REQUEST;
	
	scope(exit) {
		SDL_Quit();
	}
	
	scope(failure) {
		if(song !is null) {
			stderr.writefln("Crashed! Saving backup...");
			song.save("_backup.ct");
		}
	}

	try {
		i = 1;
		while(i < args.length) {
			switch(args[i])
			{
			case "-h", "-help", "--help", "-?":
				printheader();
				return 0;
			case "-m":
				sidtype = to!int(args[i+1]);
				if(sidtype != 0 && sidtype != 1 && sidtype != 6581 && sidtype != 8580)
					throw new UserException("Incorrect SID type; specify 0 for 6581 or 1 for 8580");
				i++;
				break;
        	case "-fpr":
				int fprarg = to!int(args[i+1]);

				sidtype ? (audio.player.curfp8580 = cast(int)(fprarg % FP8580.length)) :
					(audio.player.curfp6581 = cast(int)(fprarg % FP6581.length));
				i++;
				break;
			case "-i":
				audio.player.interpolate = 0;
				break;
			case "-l":
				audio.player.badline = 1;
				break;
			case "-n":
				audio.player.ntsc = 1;
				break;
			case "-r":
				requestedAudio.sampleRate = to!int(args[i+1]);
				i++;
				break;
			case "-b":
				requestedAudio.bufferSamples = to!int(args[i+1]);
				i++;
				break;
			case "-nofp":
				audio.player.usefp = 0;
				break;
			default:
				version (OSX) {
					if (args[i].length > 3 && args[i][0..4] == "-psn"){
						break;
					}
				}
				if(args[i][0] == '-')
					throw new UserException(format("Unrecognized option %s", args[i]));
				if(fnDefined)
					throw new UserException("Filename already defined.");
				filename = cast(string)args[i].dup;
				if(std.file.exists(filename) == 0 || std.file.isDir(filename)) {
					throw new UserException("File not found!");
				}		
				fnDefined = true;
		
				break;
			}
			i++;
		}
	}
	catch(UserException e) {
		std.stdio.stderr.writeln(e);
		return -1;
	}
	audio.audio.configureStartupAudioRequest(requestedAudio);
	
	debug {
		assert(quickExpandSequenceSelfCheck());
		runTrackOverviewSelfChecks();
	}

	audio.player.init();
		if (!initVideo()) {
	    writeln("Video init failed: ", SDL_GetError().fromStringz);
	    SDL_Quit();
	    return -1;
	  }
		initSession();
	mainui = new UI();
	loadFile(filename);
	video.updateFrame();
		
	SDL_PauseAudio(0);
	mainloop();
	mainui.releaseInputOwnership();
	audio.player.stop();
	audio.audio.audio_close();
	return 0;   
}

void openFile(char* filename){
	string str = to!(string)(filename);
	loadFile(str);

}

void loadFile(string filename){
	if(filename && mainui) {
		mainui.loadCallback(filename);
		mainui.update();
	}
}
