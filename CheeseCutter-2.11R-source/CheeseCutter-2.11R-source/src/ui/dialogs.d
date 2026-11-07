/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.dialogs;
import derelict.sdl2.sdl;
import main;
import com.fb;
import com.util;
import com.session;
import audio.audio;
private import ct.base;
import ui.help;
import ui.ui;
import ui.input;
import std.algorithm;
import std.string;
import std.file;
import std.utf;
import std.array;
import std.stdio;
import std.path : baseName, buildPath, dirName;

KeyboardMetadataAuditIssue[] auditKeyboardMetadata() {
	return auditKeyboardBindingMetadata();
}

abstract class QueryDialogBase(T) : Window {
	string query;
	ubyte[1] byt;
	alias void delegate(T) Callback;
	Callback callback;
	protected int frameWidth;
	this(string s, Callback fp) {
		super(Rectangle(0, 0, 1));
		query = s;
		callback = fp;
		frameWidth = cast(int)query.length;
	}

	override void update() {
		int x = cast(int)(screen.width / 2 - (frameWidth + 6)/2);
		int y = cast(int)(screen.height / 2 - 11);
		drawFrame(Rectangle(x, y, 5, frameWidth + 9));
		screen.cprint(x + 4, y + 2, 15, 0, query);
		input.setCoord(cast(int)(x + 4 + query.length), cast(int)( y + 2));
	}

	override void activate() {
		return;
	}
}

class QueryDialog : QueryDialogBase!int {
	const int maxValue;
	this(string s,Callback fp, int m) {
		super(s, fp);
		input = new InputBoundedByte(byt);
		maxValue = m;
	}

	override int keypress(Keyinfo key) {
		if(key.mods & KMOD_ALT) return OK;
		int r = input.keypress(key);
		if(r == WRAP &&
		   (cast(InputBoundedByte)input).value >= maxValue) {
			input.setOutput(cast(ubyte[])[maxValue - 1]);
			return OK;
		}
		else if(r == RETURN) {
			input.nibble = 0;
			callback(input.toInt());
		}
		else if(r == CANCEL) { // no callback
		}
		else r = OK;
		if(input.value >= maxValue)
			input.setOutput(cast(ubyte[])[maxValue - 1]);
		return r;
	}
}

class ConfirmationDialog : QueryDialogBase!int {
	this(string title, Callback cb, string keys, int defaultkey) {
		super(title, cb);
		input = new InputSingleChar(byt, keys, defaultkey);
	}

	this(string title, Callback cb) {
		this(title, cb, "yn", 1);
	}
	
	override int keypress(Keyinfo key) {
		if(key.mods & KMOD_ALT) return OK;
		int r = input.keypress(key);
		if(r == CANCEL)
			return CANCEL; // just close dialog
		if(r == RETURN) { // received legal key
			callback(input.toInt);
			return RETURN;
		}
		return OK;
	}
}

class HelpDialog : Window {
	enum PAGE_SCROLL_LINES = 8;
	string[] headerLines;
	string[] bodyLines;
	string title;
	string topicId;
	bool topicSwitchingEnabled;
	int scrollOffset;
	int txt_x;
	HelpSessionState fallbackSessionState;
	HelpSessionState* sessionState;
	
	this(Rectangle a, ContextHelp ctx, HelpSessionState* helpSessionState = null) {
		super(a);
		sessionState = helpSessionState is null ?
			&fallbackSessionState : helpSessionState;
		txt_x = area.x +
			(area.width / 2 - HELP_CONTENT_LINE_WIDTH / 2);
		loadContext(ctx);
		restoreStoredOffset();
	}

	private void loadContext(ContextHelp ctx) {
		bodyLines.length = 0;
		bool previousBlank = true;
		foreach(pageText; ctx.text) {
			string[] sectionLines = std.string.splitLines(pageText);
			if(sectionLines.length == 0)
				continue;
			foreach(line; sectionLines) {
				bool blank = std.string.strip(line).length == 0;
				if(blank) {
					if(previousBlank)
						continue;
					bodyLines ~= "";
					previousBlank = true;
				}
				else {
					bodyLines ~= line;
					previousBlank = false;
				}
			}
		}
		title = ctx.title;
		topicId = helpTopicIdForContext(ctx);
		topicSwitchingEnabled = isSwitchableTopicId(topicId);
		headerLines = topicSwitchingEnabled ?
			std.string.splitLines(helpTopicHeaderText(topicId)) : [];
		removeScrollableHeaderFromBody();
		while(bodyLines.length > 0 &&
				std.string.strip(bodyLines[$ - 1]).length == 0)
			bodyLines.length = bodyLines.length - 1;
		if(bodyLines.length == 0)
			bodyLines ~= "";
		contextHelp = ctx;
	}

	override void update() {
		int ypos = area.y + 2;
		int footerY = area.y + area.height - 1;
		int blankY = footerY - 1;
		int bodyBottom = blankY;
		int visibleLines = visibleBodyLines();
		clampScrollOffset();
		drawFrame(area);
		screen.cprint(area.x + 2, area.y, 1, 0, format(" %s ", title));
		screen.cprint(area.x + 2, footerY, 1, 0,
			helpFooterText());

		for(int clearY = ypos; clearY < bodyBottom; clearY++) {
			screen.cprint(area.x + 1, clearY, 1, 0,
					  std.array.replicate(" ", area.width-3));
		}
		screen.cprint(area.x + 1, blankY, 1, 0,
				  std.array.replicate(" ", area.width-3));

		foreach(line; headerLines) {
			if(ypos >= bodyBottom)
				break;
			screen.fprint(txt_x, ypos, "`0f" ~ line);
			ypos++;
		}
		if(headerLines.length > 0 && ypos < bodyBottom)
			ypos++;

		for(int i = 0; i < visibleLines; i++) {
			int lineIndex = scrollOffset + i;
			if(lineIndex >= bodyLines.length)
				break;
			if(ypos >= bodyBottom)
				break;
			screen.fprint(txt_x, ypos, "`0f" ~ bodyLines[lineIndex]);
			ypos++;
		}
	}

	private string helpFooterText() {
		return " " ~ keyboardActionShortcutLabelList("help.scroll_up", "/") ~
			"/" ~ keyboardActionShortcutLabelList("help.scroll_down", "/") ~
			" Scroll  " ~ keyboardActionShortcutLabelList("help.page_up", "/") ~
			"/" ~ keyboardActionShortcutLabelList("help.page_down", "/") ~
			" Page  " ~ keyboardActionShortcutLabelList("help.top", "/") ~
			"/" ~ keyboardActionShortcutLabelList("help.bottom", "/") ~
			" Top/Bottom  " ~ keyboardActionShortcutLabelList("help.close", "/") ~
			" Close ";
	}

	override int keypress(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveHelpDialogKeyboardAction(key, actionId))
			return OK;

		switch(actionId) {
		case KeyboardActionId.helpScrollUp:
			scrollBy(-1);
			break;
		case KeyboardActionId.helpScrollDown:
			scrollBy(1);
			break;
		case KeyboardActionId.helpPageUp:
			scrollBy(-PAGE_SCROLL_LINES);
			break;
		case KeyboardActionId.helpPageDown:
			scrollBy(PAGE_SCROLL_LINES);
			break;
		case KeyboardActionId.helpTopicPrevious:
			if(topicSwitchingEnabled)
				switchTopicByDirection(-1);
			break;
		case KeyboardActionId.helpTopicNext:
			if(topicSwitchingEnabled)
				switchTopicByDirection(1);
			else
				scrollBy(visibleBodyLines());
			break;
		case KeyboardActionId.helpTop:
			scrollOffset = 0;
			saveActiveOffset();
			break;
		case KeyboardActionId.helpBottom:
			scrollOffset = maxScrollOffset();
			saveActiveOffset();
			break;
		case KeyboardActionId.helpClose:
			return RETURN;
		default:
			break;
		}
		return OK;
	}

	override void clickedAt(int x, int y, int button) {
		if(button != 1)
			return;
		HelpTopicHit hit = helpTopicAt(x, y, txt_x, area.y + 2, topicId);
		if(!hit.valid)
			return;
		switchToTopic(hit.topicId);
	}

	override void deactivate() {
		saveActiveOffset();
	}

	bool switchToContext(ContextHelp ctx) {
		string targetTopicId = helpTopicIdForContext(ctx);
		if(targetTopicId.length == 0)
			return false;
		return switchToTopic(targetTopicId);
	}

private:

	int visibleBodyLines() {
		int rows = area.height - 4 - cast(int)headerLines.length -
			(headerLines.length > 0 ? 1 : 0);
		return rows < 1 ? 1 : rows;
	}

	int maxScrollOffset() {
		int maxOffset = cast(int)bodyLines.length - visibleBodyLines();
		return maxOffset < 0 ? 0 : maxOffset;
	}

	void clampScrollOffset() {
		if(scrollOffset < 0)
			scrollOffset = 0;
		int maxOffset = maxScrollOffset();
		if(scrollOffset > maxOffset)
			scrollOffset = maxOffset;
	}

	void scrollBy(int rows) {
		scrollOffset += rows;
		clampScrollOffset();
		saveActiveOffset();
	}

	void switchTopicByDirection(int direction) {
		string nextTopicId = adjacentHelpTopicId(topicId, direction);
		switchToTopic(nextTopicId);
	}

	bool switchToTopic(string nextTopicId) {
		if(nextTopicId.length == 0)
			return false;
		if(nextTopicId == topicId)
			return true;
		ContextHelp nextContext;
		if(!helpContextForTopicId(nextTopicId, nextContext))
			return false;

		saveActiveOffset();
		loadContext(nextContext);
		restoreStoredOffset();
		update();
		return true;
	}

	bool isSwitchableTopicId(string candidateTopicId) {
		ContextHelp ignored;
		return helpContextForTopicId(candidateTopicId, ignored);
	}

	string[] selectableHelpTopicIdsInDisplayOrder() {
		string[] topicIds;
		foreach(topic; helpTopicMetadataInDisplayOrder()) {
			if(!topic.implemented)
				continue;
			if(!isSwitchableTopicId(topic.id))
				continue;
			topicIds ~= topic.id;
		}
		return topicIds;
	}

	string adjacentHelpTopicId(string currentTopicId, int direction) {
		string[] topicIds = selectableHelpTopicIdsInDisplayOrder();
		if(topicIds.length == 0)
			return "";

		int currentIndex = -1;
		foreach(i, candidateTopicId; topicIds) {
			if(candidateTopicId == currentTopicId) {
				currentIndex = cast(int)i;
				break;
			}
		}
		if(currentIndex < 0)
			return "";

		int nextIndex = currentIndex + (direction < 0 ? -1 : 1);
		if(nextIndex < 0)
			nextIndex = cast(int)topicIds.length - 1;
		else if(nextIndex >= cast(int)topicIds.length)
			nextIndex = 0;
		return topicIds[nextIndex];
	}

		bool helpContextForTopicId(string candidateTopicId, out ContextHelp ctx) {
			if(staticHelpContextForTopicId(candidateTopicId, ctx))
				return true;
			return generatedHelpContextForTopicId(candidateTopicId, ctx);
		}

		int topicIndex() {
			return helpTopicIndexForId(topicId);
		}

		void saveActiveOffset() {
			int index = topicIndex();
			if(index < 0 || sessionState is null)
				return;
			clampScrollOffset();
			sessionState.scrollOffsets[index] = scrollOffset;
		}

		void restoreStoredOffset() {
			int index = topicIndex();
			scrollOffset = 0;
			if(index >= 0 && sessionState !is null)
				scrollOffset = sessionState.scrollOffsets[index];
			clampScrollOffset();
			if(index >= 0 && sessionState !is null)
				sessionState.scrollOffsets[index] = scrollOffset;
		}

		void removeScrollableHeaderFromBody() {
			if(headerLines.length == 0 || bodyLines.length < headerLines.length)
				return;
			foreach(i, headerLine; headerLines) {
				if(bodyLines[i] != headerLine)
					return;
			}
			size_t removeCount = headerLines.length;
			if(bodyLines.length > removeCount &&
					std.string.strip(bodyLines[removeCount]).length == 0)
				removeCount++;
			bodyLines = bodyLines[removeCount .. $].dup;
		}

		bool generatedHelpContextForTopicId(string candidateTopicId, out ContextHelp ctx) {
		if(song is null)
			return false;

		if(candidateTopicId == "instrument_table" && song.ver > 8) {
			ctx = genPlayerContextHelp("Instrument table",
				song.instrumentByteDescriptions);
			return true;
		}
		if(candidateTopicId == "command_table" && song.ver > 9) {
			ctx = genPlayerContextHelp("Command table", song.cmdDescriptions);
			return true;
		}
		if(candidateTopicId == "wave_table" && song.ver > 9) {
			ctx = genPlayerContextHelp("Wave table", song.waveDescriptions);
			return true;
		}
		if(candidateTopicId == "pulse_table" && song.ver > 8) {
			ctx = genPlayerContextHelp("Pulse table", song.pulseDescriptions);
			return true;
		}
		if(candidateTopicId == "filter_table" && song.ver > 8) {
			ctx = genPlayerContextHelp("Filter table", song.filterDescriptions);
			return true;
		}
		return false;
	}
	}

class DebugDialog : Window {
	Sequence seq;
	
	this(Sequence s) {
		super(Rectangle(screen.width / 2 - 24,
				   screen.height / 2 - 10,
				   20, 55));
		seq = s;
	}
	
	this(Rectangle a) {
		super(a);
	}

	override void update() {
		assert(seq !is null);
		ubyte[] data = seq.compact();
		data.length = 256;
		int y,pos;
		string str;
		drawFrame(area);
		for(y=0;y<area.h-2;y++) {
			screen.fprint(area.x+1,area.y+1+y,
						  std.array.replicate(" ", area.width-2));
		}

		for(y=0; y<16; y++) {
			str = format("%02X:",y*16);
			for(int i = 0; i < 16 ; i++) {
				str ~= format("%02X ", data[pos++]);
			}
			screen.fprint(area.x+2,area.y+y+2,"`0f" ~ str);
		}
	}

	override int keypress(Keyinfo key) {
		switch(key.unicode) {
		case SDLK_SPACE:
			com.util.hexdump(seq.compact(),16);
			break;
		case 0:
			break;
		default:
			return RETURN;
		}
		return OK;
	}
}

class AboutDialog : Window {
	private enum int ABOUT_ART_WIDTH = 75;
	private enum string ABOUT_ART =
"`01          ___                                    ___   ___
`01   ______/  /____________________________________\\  \\__\\  \\_______________
`01  /  ___/     /  -__/  -__/__ --/  -__|  ___\\  \\  \\   __\\   __\\  -__\\    _\\
`01 /_____/__/__/_____/_____/_____/______|______\\_____\\_____\\_____\\_____\\___\\/
`01 \\_____\\__\\__\\_____\\_____\\_____\\______|`05__       ___  ______  __       `01___/
`05                                        /___\\__/___)/__ ___)(   (   \\__
`0f (C) 2009-17 Abaddon + contributors    `05/   / _/    (__ /  \\  \\___\\___)____
`0f reSID engine by Dag Lem                
`0f Released under GNU GPL                `05HYPERCUT`0f recut by arch0N, 2026

`01 https://github.com/theyamo/CheeseCutter
";

	this(Rectangle a) {
		super(a);
	}

	override void update() {
		string[] logo = std.string.splitLines(ABOUT_ART);
		int x = area.x + 1 + (area.width - 2 - ABOUT_ART_WIDTH) / 2;
		int y;

		drawFrame(area);
		y = area.y + 1;
		foreach(line; logo) {

			screen.cprint(area.x + 1, y, 1, 0, 
						  std.array.replicate(" ", area.width-2));

			screen.fprint(x, y, line);
			y++;
		}
	}
  
	override int keypress(Keyinfo key) {
		if(key.mods) return OK;
    auto k = key.key;
		if(k == SDLK_ESCAPE ||
			k == SDLK_SPACE ||
			k == SDLK_RETURN) return RETURN;
		return OK;
	}
}

class AudioSettingsDialog : Window {
	alias string delegate() ApplyCallback;
	private enum SAMPLE_RATE_FIELD = 0;
	private enum BUFFER_SIZE_FIELD = 1;
	private enum APPLY_BUTTON = 2;
	private enum CANCEL_BUTTON = 3;
	private int selectedField;
	private Rectangle[4] choiceAreas;
	private string resultMessage;
	private ApplyCallback applyCallback;

	this(Rectangle a, ApplyCallback callback) {
		super(a);
		applyCallback = callback;
	}

	override void activate() {
		beginPendingAudioConfiguration();
		selectedField = SAMPLE_RATE_FIELD;
		resultMessage = null;
	}

	override void update() {
		drawFrame(area);
		int x = area.x + 4;
		int y = area.y + 2;
		auto startup = startupAudioRequest();
		auto requested = currentAudioRequest();
		auto live = liveAudioConfiguration();
		auto pending = pendingAudioRequest();

		screen.cprint(x, y++, 13, 0, "Audio Settings");
		y++;
		screen.cprint(x, y++, 5, 0, "Startup requested");
		screen.cprint(x + 2, y++, 15, 0, format(
			"Sample rate: %d Hz    Buffer size: %d samples",
			startup.sampleRate, startup.bufferSamples));
		y++;
		screen.cprint(x, y++, 5, 0, "Current requested");
		screen.cprint(x + 2, y++, 15, 0, format(
			"Sample rate: %d Hz    Buffer size: %d samples",
			requested.sampleRate, requested.bufferSamples));
		y++;
		screen.cprint(x, y++, 5, 0, "Current live");
		if(live.available) {
			screen.cprint(x + 2, y++, 15, 0, format("Backend: %s    Device: %s",
				currentAudioBackendName(), currentAudioDeviceName()));
			screen.cprint(x + 2, y++, 15, 0, format(
				"Sample rate: %d Hz    Buffer size: %d samples",
				live.sampleRate, live.bufferSamples));
			screen.cprint(x + 2, y++, 15, 0, format(
				"Callback period: %.1f ms", audioCallbackDurationMilliseconds(
					AudioRequest(live.sampleRate, live.bufferSamples))));
			screen.cprint(x + 2, y++, 15, 0, format("Format: %s    Channels: %s",
				audioFormatName(live.format), audioChannelName(live.channels)));
		}
		else {
			screen.cprint(x + 2, y++, 12, 0, "Audio unavailable");
			y += 3;
		}

		y++;
		screen.cprint(x, y++, 5, 0, "New settings");
		drawChoice(x + 2, y++, SAMPLE_RATE_FIELD,
			format("Sample rate: < %d Hz >", pending.sampleRate));
		drawChoice(x + 2, y++, BUFFER_SIZE_FIELD,
			format("Buffer size: < %d samples >", pending.bufferSamples));
		screen.cprint(x + 2, y++, 15, 0, format("Callback period: %.1f ms",
			audioCallbackDurationMilliseconds(pending)));
		y++;
		drawChoice(x + 2, y, APPLY_BUTTON, "[Apply and Restart Audio]");
		drawChoice(x + 32, y++, CANCEL_BUTTON, "[Cancel]");
		if(resultMessage.length)
			screen.cprint(x + 2, y + 1, 12, 0,
				resultMessage[0 .. min(resultMessage.length,
					cast(size_t)area.width - 10)]);
	}

	override int keypress(Keyinfo key) {
		if(key.raw == SDLK_ESCAPE)
			return CANCEL;
		if(key.raw == SDLK_UP || (key.raw == SDLK_TAB &&
				(key.mods & KMOD_SHIFT))) {
			selectedField = selectedField == SAMPLE_RATE_FIELD ? CANCEL_BUTTON :
				selectedField - 1;
			return OK;
		}
		if(key.raw == SDLK_DOWN || key.raw == SDLK_TAB) {
			selectedField = selectedField == CANCEL_BUTTON ? SAMPLE_RATE_FIELD :
				selectedField + 1;
			return OK;
		}
		if(key.raw == SDLK_LEFT || key.raw == SDLK_RIGHT) {
			stepSelectedField(key.raw == SDLK_LEFT ? -1 : 1);
			return OK;
		}
		if(key.raw != SDLK_RETURN && key.raw != SDLK_KP_ENTER &&
				key.raw != SDLK_SPACE)
			return OK;

		switch(selectedField) {
		case SAMPLE_RATE_FIELD:
		case BUFFER_SIZE_FIELD:
			stepSelectedField(1);
			return OK;
		case APPLY_BUTTON:
			applyPending();
			return OK;
		case CANCEL_BUTTON:
			return CANCEL;
		default:
			return OK;
		}
	}

	override void clickedAt(int scrx, int scry, int button) {
		if(button != 1)
			return;
		foreach(field, controlArea; choiceAreas) {
			if(!controlArea.overlaps(scrx, scry))
				continue;
			selectedField = cast(int)field;
			if(field == APPLY_BUTTON)
				applyPending();
			else if(field == CANCEL_BUTTON)
				mainui.closeDialog();
			return;
		}
	}

private:
	void drawChoice(int x, int y, int field, string text) {
		choiceAreas[field] = Rectangle(x, y, 1, cast(int)text.length);
		screen.cprint(x, y, selectedField == field ? 1 : 15,
			selectedField == field ? 5 : 0, text);
	}

	void stepSelectedField(int direction) {
		if(selectedField == SAMPLE_RATE_FIELD)
			stepPendingSampleRate(direction);
		else if(selectedField == BUFFER_SIZE_FIELD)
			stepPendingBufferSize(direction);
		resultMessage = null;
	}

	void applyPending() {
		resultMessage = applyCallback();
	}
}

class FileSelector : Window {
	struct FileSelPos {
		int offset, pos;
		void reset() { offset = pos = 0; }
	}
	
	struct File {
		string name;
		int exists, isdir;
	}
	
	FileSelPos fpos;
	private File[] filelist;
	private const(int)[] visibleEntries;
	string directory;

	@property Rectangle contentArea() {
		return Rectangle(area.x + 5, area.y, area.height, area.width);
	}
	
	this(Rectangle a) {
		super(a);
		directory = getcwd();
		refresh();
	}

	private void displayDirectoryNotFoundFailure() {
		UI.statusline.displayFailure("Directory not found!");
	}

	override void activate() {
		// Dialog activation and directory changes own filesystem refreshes.
	}

	override void refresh() {
		if(!exists(directory)) {
			displayDirectoryNotFoundFailure();
		}
		else {
			visibleEntries = null;
			getdir(directory);
			if(fpos.pos >= visibleEntryCount)
				cursorEnd();
		}
	}

	void reset() {
		fpos.offset = fpos.pos = 0;
	}

	override void update() { 
		int y, i;
		auto content = contentArea;
		for(y = content.y, i = 0; i < content.height; y++,i++) {
			int viewIndex = fpos.offset + i;
			string fs = null;
			int col = 15;
			if(viewIndex < visibleEntryCount) {
				int canonicalIndex = canonicalIndexAt(viewIndex);
				File f = filelist[canonicalIndex];
				if(canonicalIndex < 2 || (f.exists && f.isdir)) {
					col = 13;
				}
				fs = fstr(format("  %s", entryName(f.name).leftJustify(content.width-2)));
			}
			screen.cprint(content.x,y,col,0,fs);
		}
	}

	void blink() {
		auto content = contentArea;
		int visibleRow = fpos.pos - fpos.offset;
		if(visibleRow < 0 || visibleRow >= content.height ||
				fpos.pos >= visibleEntryCount)
			return;
		int y = content.y + visibleRow;
		screen.fprint(content.x,y,fstr("`b1  " ~
			entryName(filelist[selectedCanonicalIndex].name)
				.leftJustify(content.width-3)) ~ "  ");
	}

	int canonicalEntryCount() {
		return cast(int)filelist.length;
	}

	string canonicalEntryName(int canonicalIndex) {
		return entryName(filelist[canonicalIndex].name);
	}

	bool canonicalEntryIsDirectory(int canonicalIndex) {
		File f = filelist[canonicalIndex];
		return f.exists && f.isdir;
	}

	int selectedCanonicalIndex() {
		if(visibleEntryCount == 0)
			return -1;
		return canonicalIndexAt(fpos.pos);
	}

	bool selectedIsDirectory() {
		int canonicalIndex = selectedCanonicalIndex;
		return canonicalIndex >= 0 &&
			canonicalEntryIsDirectory(canonicalIndex);
	}

	void setVisibleEntries(const(int)[] entries,
			int preferredCanonicalIndex) {
		visibleEntries = entries;
		int preferredViewIndex = viewIndexOf(preferredCanonicalIndex);
		fpos.pos = preferredViewIndex >= 0 ? preferredViewIndex : 0;
		clampViewport();
		ensureSelectionVisible();
	}

	bool selectAtScreenRow(int screenRow) {
		auto content = contentArea;
		if(screenRow < content.y || screenRow >= content.y + content.height)
			return false;
		int viewIndex = fpos.offset + screenRow - content.y;
		if(viewIndex < 0 || viewIndex >= visibleEntryCount)
			return false;
		fpos.pos = viewIndex;
		return true;
	}

	void scrollViewport(int rows) {
		fpos.offset += rows;
		clampViewport();
	}
	
	int fileHandler() {
		string path = selected;
		if(isDir(path)) {
			navigateToDirectory(path);
			return OK;
		}
		return RETURN;
	}

	bool navigateToDirectory(string path) {
		if(!exists(path) || !isDir(path)) {
			displayDirectoryNotFoundFailure();
			return false;
		}
		directory = cast(string)path.dup;
		reset();
		refresh();
		return true;
	}

	override int keypress(Keyinfo key) {
		switch(key.raw) 
		{
		case SDLK_UP:
			step(-1);
			return WRAP;
		case SDLK_DOWN:
			step(1);
			return WRAP;
		case SDLK_PAGEUP:
			step(-area.height);
			return WRAP;
		case SDLK_PAGEDOWN:
			step(area.height);
			return WRAP;
		case SDLK_HOME:
			reset();
			return WRAP;
		case SDLK_END:
			cursorEnd();
			return WRAP;
		default:
			break;
		}
		return OK;
	}
	
	char[][] listdir(string udir) {
		char[][] ret;
		auto app = appender(ret);
		foreach (DirEntry e; dirEntries(udir, SpanMode.shallow)){
			app.put( e.name.dup );	
		}

		return app.data;
	}

	void getdir(string udir) {
		char[][] dir;
		char[][] dirs, files;
		dir = listdir(udir);
		dirs.length = dir.length+2;
		files.length = dir.length;

		int idxd, idxf;

		foreach(i, d; dir) {
			char[] first = d[0..1];
			// skip hidden / temp files
			if(first == "." || first == "#")
				continue;
			try {
				if(d.isDir()) {
					dirs[idxd++] = d;
				} else {
					files[idxf++] = d;
				}
			}
			catch(FileException) {
				// may occur if entry "d" does not
				// exist or is a dangling symlink
				continue;
			}
		}

		dirs.length = idxd;
 		dirs.sort;
		
		files.length = idxf;
		files.sort;

		string[] all = cast(string[])(dirs ~ files);
		
		filelist.length = all.length + 2;
		filelist[0] = File(".", true, true);
                filelist[1] = File("..",true, true);
		for(int i = 0; i < all.length; i++) {
			filelist[i+2] = File(all[i], all[i].exists(), all[i].isDir());
		}
	}

	// move the cursor to last entry & set scroll window pos
	void cursorEnd() {
		if(visibleEntryCount == 0) {
			reset();
			return;
		}
		fpos.pos = visibleEntryCount - 1;
		ensureSelectionVisible();
	}

	void step(int st) {
		if(visibleEntryCount == 0)
			return;
		fpos.pos += st;
		if(fpos.pos < 0)
			fpos.pos = 0;
		else if(fpos.pos >= visibleEntryCount)
			fpos.pos = visibleEntryCount - 1;
		ensureSelectionVisible();
	}

	string fullPath(string filename) {
		if(filename.length == 0)
			return directory;
		return buildPath(directory, filename);
	}

	@property string selectedName() {
		return entryName(filelist[selectedCanonicalIndex].name);
	}

	@property string selected() {
		string name = selectedName;
		if(name == ".")
			return directory;
		if(name == "..")
			return dirName(directory);
		return fullPath(name);
	}
  
private:

	@property int visibleEntryCount() {
		return visibleEntries is null ? cast(int)filelist.length :
			cast(int)visibleEntries.length;
	}

	int canonicalIndexAt(int viewIndex) {
		return visibleEntries is null ? viewIndex : visibleEntries[viewIndex];
	}

	int viewIndexOf(int canonicalIndex) {
		if(canonicalIndex < 0)
			return -1;
		if(visibleEntries is null)
			return canonicalIndex < filelist.length ? canonicalIndex : -1;
		foreach(i, entryIndex; visibleEntries) {
			if(entryIndex == canonicalIndex)
				return cast(int)i;
		}
		return -1;
	}

	void clampViewport() {
		int maxOffset = visibleEntryCount > area.height ?
			visibleEntryCount - area.height : 0;
		if(fpos.offset < 0)
			fpos.offset = 0;
		else if(fpos.offset > maxOffset)
			fpos.offset = maxOffset;
	}

	void ensureSelectionVisible() {
		if(visibleEntryCount == 0) {
			reset();
			return;
		}
		if(fpos.pos < fpos.offset)
			fpos.offset = fpos.pos;
		else if(fpos.pos >= fpos.offset + area.height)
			fpos.offset = fpos.pos - area.height + 1;
		clampViewport();
	}

	string entryName(string path) {
		if(path == "." || path == "..")
			return path;
		return baseName(path);
	}

	string fstr(string fs) {
		if(fs.length > (area.width))
			fs.length = area.width;
		return fs;
	}
}

// wraps inputstring
class DialogString : Window {
	this(Rectangle a) {
		this(a, 50);
	}

	this(Rectangle a, int len) {
		input = new InputString("", len);
		input.setCoord(a.x, a.y);
		super(a);
	}

	override string toString() { return toString(false); }
	
	string toString(bool p) { return (cast(InputString)input).toString(p); }
	
	void setString(string s) {
		(cast(InputString)input).setOutput(s);
	}

	override void update() {
		input.update();
	}

	override int keypress(Keyinfo key) { input.keypress(key); return OK; }
}
		
class FileSelectorDialog : WindowSwitcher {
	alias void delegate(string) CB;
	const CB callback;
	private enum FILE_FIELD_WIDTH = 50;
	private DialogString sfile, sdir;
	FileSelector fsel;
	private string header;
	private string filterText;
	private int[] filteredEntryIndices;
	
	this(Rectangle a, string h, CB cb) {
		header = h;
		if(a == Rectangle.init) {
			int dialog_width = screen.width - 32;
			int dialog_height = screen.height - 10;
			int dialog_x = screen.width / 2 - dialog_width / 2;
			int dialog_y = screen.height / 2 - dialog_height / 2;
			a = Rectangle(dialog_x, dialog_y, dialog_height, dialog_width);
		}
		fsel = new FileSelector(Rectangle(a.x + 5, a.y + 2, a.height - 6, 
								a.width - 18));
		sfile = new DialogString(Rectangle(a.x+3+11, a.y+a.height-2,
			1, FILE_FIELD_WIDTH), FILE_FIELD_WIDTH);
		sdir = new DialogString(Rectangle(a.x+3+11, a.y+a.height-3,
			1, FILE_FIELD_WIDTH), FILE_FIELD_WIDTH);
		sdir.setString(fsel.directory);
		super(a, [cast(Window)fsel, sdir, sfile]);
		activateWindow(0);
		rebuildFilteredView(false);
		callback = cb;
	}

	void setFilename(string s) {
		sfile.setString(cast(string)s.dup);
	}

	void setDirectory(string s) {
		fsel.directory = cast(string)s.dup;
		sdir.setString(cast(string)s.dup);
	}

	@property string filename() {
		return sfile.toString();
	}

	@property string fullname() {
		return fsel.fullPath(sfile.toString());
	}

	@property string directory() {
		return fsel.directory;
	}
	
	override void activate() {
		filterText = null;
		fsel.refresh();
		rebuildFilteredView(false);
		update();
	}

	override void refresh() { 
		update();
	}
	
	override void update() {
		int x,y,i;

		for(y = area.y; y < area.y+area.height; y++) {
			screen.cprint(area.x, y, 1, 0, std.array.replicate(" ",area.width));
		}
		drawFrame(area);
		x = area.x + 3;
		y = area.y + 2;
		screen.cprint(x,area.y,1,0," " ~ header ~ " ");
		drawBrowserFilter();

		screen.fprint(x,area.y+area.height-3,format("`0fDirectory: `0d%s",sdir.toString()));
		
		string f = sfile.toString();
		int ind = cast(int) (1+f.lastIndexOf(DIR_SEPARATOR));
		screen.fprint(x,area.y+area.height-2,format("`0f Filename: `0d%s",f[ind..$]));
		
		activeWindow.update();
		if(activeWindow == fsel) {
			fsel.blink();
		} else {
			fsel.update();
		}
		input = activeWindow.input;
	}

	override int keypress(Keyinfo key) {
		KeyboardActionId actionId;
		if(resolveFileDialogKeyboardAction(key, actionId))
			return confirmBrowserSelection();

		if(activeWindow == fsel) {
			if(key.raw == SDLK_BACKSPACE) {
				if(filterText.length > 0) {
					filterText.length = filterText.length - 1;
					rebuildFilteredView();
					update();
				}
				return OK;
			}
			if(key.raw == SDLK_ESCAPE && filterText.length > 0) {
				clearFilter();
				return OK;
			}
			if((key.mods & (KMOD_CTRL | KMOD_ALT | KMOD_GUI)) == 0 &&
					key.unicode >= 0x20 && key.unicode <= 0x7e) {
				filterText ~= cast(char)key.unicode;
				rebuildFilteredView();
				update();
				return OK;
			}
		}

		switch(key.raw)
		{
		case SDLK_TAB:
			int result = super.keypress(key);
			if(activeWindow == fsel)
				rebuildFilteredView();
			return result;
		case SDLK_ESCAPE:
			return RETURN;
		default:
			int r = activeWindow.keypress(key);
			if(r == WRAP)
				syncFilenameFromBrowserSelection();
			break;
		}
		return OK;
	}

	protected bool selectedEntryUpdatesFilename() {
		return true;
	}

	protected int returnPressed(CB cb) {
		return completeSelection(cb);
	}

	private int confirmBrowserSelection() {
		if(activeWindow == fsel)
			syncFilenameFromBrowserSelection();
		return returnPressed(callback);
	}

	protected final int completeSelection(CB cb) {
		if(activeWindow == fsel) {
			int r = fsel.fileHandler();
			if(r == RETURN)
				cb(cast(string)(fsel.selected));
			else {
				filterText = null;
				rebuildFilteredView(false);
				clearLoadFilenameAfterDirectoryChange();
			}
			sdir.setString(fsel.directory);
			return r;
		}
		else if(activeWindow == sfile) { // pressed RETURN in file dialog
			cb(fullname);
			return RETURN;
		}
		else {
			if(!fsel.navigateToDirectory(sdir.toString()))
				return OK;
			sdir.setString(fsel.directory);
			filterText = null;
			rebuildFilteredView(false);
			clearLoadFilenameAfterDirectoryChange();
		}
		return OK;
	}

	override void clickedAt(int screenX, int screenY, int button) {
		if(button != 1)
			return;
		if(sdir.area.overlaps(screenX, screenY))
			activateWindow(1);
		else if(sfile.area.overlaps(screenX, screenY))
			activateWindow(2);
		else
			return;
		update();
	}

	int clickedFileListAt(int screenX, int screenY, int button, int clicks,
			out bool handled) {
		handled = button == 1 && fsel.contentArea.overlaps(screenX, screenY);
		if(!handled)
			return OK;
		if(activeWindow != fsel) {
			activateWindow(0);
			rebuildFilteredView();
		}
		if(!fsel.selectAtScreenRow(screenY)) {
			update();
			return OK;
		}
		syncFilenameFromBrowserSelection();
		update();
		return clicks >= 2 ? confirmBrowserSelection() : OK;
	}

	private void syncFilenameFromBrowserSelection() {
		if(!selectedEntryUpdatesFilename())
			return;
		sfile.setString(fsel.selectedIsDirectory ? "" : fsel.selectedName);
	}

	private void clearLoadFilenameAfterDirectoryChange() {
		if(selectedEntryUpdatesFilename())
			sfile.setString("");
	}

	bool scrollFileListAt(int screenX, int screenY, int rows) {
		if(rows == 0)
			return false;
		if(!fsel.contentArea.overlaps(screenX, screenY))
			return true;
		fsel.scrollViewport(rows);
		update();
		return true;
	}

	protected final void drawBrowserFilter() {
		int width = area.width - 6;
		string text = "Filter: " ~ filterText;
		if(text.length > width)
			text = text[0 .. width];
		screen.cprint(area.x + 3, area.y + 1, 15, 0,
			text.leftJustify(width));
	}

	private void clearFilter() {
		filterText = null;
		rebuildFilteredView();
		update();
	}

	private void rebuildFilteredView(bool preserveSelection = true) {
		int selectedCanonicalIndex = preserveSelection ?
			fsel.selectedCanonicalIndex : -1;
		filteredEntryIndices.length = 0;
		string needle = filterText.toLower();
		for(int canonicalIndex = 0;
				canonicalIndex < fsel.canonicalEntryCount;
				canonicalIndex++) {
			string name = fsel.canonicalEntryName(canonicalIndex);
			if(canonicalIndex < 2 || needle.length == 0 ||
					name.toLower().indexOf(needle) >= 0)
				filteredEntryIndices ~= canonicalIndex;
		}
		fsel.setVisibleEntries(filteredEntryIndices,
			selectedCanonicalIndex);
	}

	protected final int returnPressedWithOverwriteConfirmation(CB cb) {
		if(activeWindow == sdir)
			return completeSelection(cb);
		if(activeWindow == fsel && std.file.isDir(fsel.selected))
			return completeSelection(cb);

		string target = fullname;
		if(std.file.exists(target) && !std.file.isDir(target)) {
			void delegate(int) confirm = (int param) {
				if(param == 0)
					cb(target);
			};
			mainui.activateDialog(new ConfirmationDialog(
				"Overwrite destination file (y/N)? ", confirm));
			return OK;
		}
		cb(target);
		return RETURN;
	}
}

class InstrumentSaveFileDialog : FileSelectorDialog {
	this(Rectangle a, CB cb) {
		super(a, "Save Instrument", cb);
	}

	override protected bool selectedEntryUpdatesFilename() {
		return false;
	}

	override protected int returnPressed(CB cb) {
		if(activeWindow == sfile && filename.strip().length == 0)
			return OK;

		if(activeWindow == fsel && !std.file.isDir(fsel.selected)) {
			setFilename(fsel.selectedName);
			syncInstrumentExtension();
		}
		else if(activeWindow == sfile) {
			syncInstrumentExtension();
		}
		return returnPressedWithOverwriteConfirmation(cb);
	}

	private void syncInstrumentExtension() {
		string fn = filename.strip();
		if(fn.length < 4 || icmp(fn[$ - 4 .. $], ".cti") != 0)
			fn ~= ".cti";
		setFilename(fn);
	}
}

class LoadFileDialog : FileSelectorDialog {
	CB cbimport;
	
	this(Rectangle a, CB cbload, CB cbimp) {
		super(a, "Load Song", cbload);
		cbimport = cbimp;
	}

	override protected int returnPressed(CB cb) {
		if(activeWindow != fsel && activeWindow != sfile)
			return super.returnPressed(cb);

		string target = activeWindow == fsel ? fsel.selected : fullname;
		if(std.file.exists(target) && !std.file.isDir(target)
					     && shouldUpgrade(target)) {
			mainui.activateDialog(new ConfirmationDialog("Upgrade to latest player (Y/n)? ",
														 &confirmCallback, "yn", 0));
			return OK;
		}
		else return super.returnPressed(cb);
	}

	private bool shouldUpgrade(string fn) {
		try {
		    Song newsong = new Song();
		    newsong.open(fn);
		    return SONG_REVISION > newsong.ver;
		}
		catch(Exception e) { return false; }
		return true;
	}

	private void confirmCallback(int param) {
		auto cb = param ? callback : cbimport;

		if(activeWindow == fsel) {
			int r = fsel.fileHandler();
			if(r == RETURN)
				cb(cast(string)(fsel.selected));
			sdir.setString(fsel.directory);
		}
		else if(activeWindow == sfile) { // pressed RETURN in file dialog
			cb(fullname);
		}
	}
}

enum SaveFormat { CT, PRG, SID }

private int hexKeyValue(Keyinfo key) {
	foreach(i, char c; "0123456789abcdef") {
		if(key.raw == c) return cast(int)i;
	}
	foreach(i, char c; "ABCDEF") {
		if(key.raw == c) return cast(int)i + 10;
	}
	return -1;
}

private class SaveOptionField : Window {
	protected {
		Cursor cursor;
		string label;
		int valueX, valueWidth;
	}
	bool enabled = true;

	this(int x, int y, string label, int valueWidth) {
		super(Rectangle(x, y, 1, cast(int)(label.length + valueWidth)));
		this.label = label;
		this.valueWidth = valueWidth;
		this.valueX = x + cast(int)label.length;
		cursor = new Cursor();
	}

	string valueText() { return ""; }
	int cursorOffset() { return 0; }

	void draw(bool active) {
		screen.cprint(area.x, area.y, 15, 0, label);
		screen.cprint(valueX, area.y, enabled ? 13 : 11, 0,
					  valueText().leftJustify(valueWidth));
		if(active)
			cursor.set(valueX + cursorOffset(), area.y);
	}

	override void update() {
		draw(true);
	}

	override int keypress(Keyinfo key) {
		return OK;
	}
}

private class SaveFormatField : SaveOptionField {
	SaveFormat value = SaveFormat.CT;
	void delegate() changed;

	this(int x, int y) {
		super(x, y, "Fmt:", 5);
	}

	override string valueText() {
		final switch(value) {
		case SaveFormat.CT: return ".ct";
		case SaveFormat.PRG: return ".prg";
		case SaveFormat.SID: return ".sid";
		}
	}

	void setValue(SaveFormat v) {
		if(value == v) return;
		value = v;
		if(changed !is null) changed();
	}

	private void step(int delta) {
		int v = cast(int)value + delta;
		if(v < 0) v = 2;
		if(v > 2) v = 0;
		setValue(cast(SaveFormat)v);
	}

	override int keypress(Keyinfo key) {
		switch(key.raw) {
		case SDLK_LEFT, SDLK_UP:
			step(-1);
			break;
		case SDLK_RIGHT, SDLK_DOWN, SDLK_SPACE:
			step(1);
			break;
		default:
			if(key.raw == 'c') setValue(SaveFormat.CT);
			else if(key.raw == 'p') setValue(SaveFormat.PRG);
			else if(key.raw == 's') setValue(SaveFormat.SID);
			break;
		}
		return OK;
	}
}

private class SaveHexField : SaveOptionField {
	int value;
	int digits;
	int nibble;
	bool optionalZero;
	bool fixedLowByte;

	this(int x, int y, string label, int digits, int value, bool optionalZero = false, bool fixedLowByte = false) {
		super(x, y, label, digits + 1);
		this.digits = digits;
		this.value = value;
		this.optionalZero = optionalZero;
		this.fixedLowByte = fixedLowByte;
		if(fixedLowByte)
			this.value &= 0xff00;
	}

	override string valueText() {
		if(fixedLowByte)
			return format("$%02X00", (value >> 8) & 0xff);
		return digits == 4 ? format("$%04X", value & 0xffff) :
			format("$%02X", value & 0xff);
	}

	override int cursorOffset() {
		return 1 + nibble;
	}

	private void step(int delta) {
		int maxNibble = fixedLowByte ? 1 : digits - 1;
		nibble += delta;
		if(nibble < 0) nibble = 0;
		if(nibble > maxNibble) nibble = maxNibble;
	}

	override int keypress(Keyinfo key) {
		if(!enabled) return OK;
		switch(key.raw) {
		case SDLK_LEFT:
			step(-1);
			return OK;
		case SDLK_RIGHT:
			step(1);
			return OK;
		case SDLK_BACKSPACE:
			if(optionalZero) {
				value = 0;
				nibble = 0;
			}
			return OK;
		default:
			int v = hexKeyValue(key);
			if(v >= 0) {
				int shift = fixedLowByte ? 4 * (3 - nibble) :
					4 * (digits - 1 - nibble);
				value &= ~(0xf << shift);
				value |= v << shift;
				if(fixedLowByte)
					value &= 0xff00;
				step(1);
			}
			return OK;
		}
	}
}

private class SaveDecimalField : SaveOptionField {
	char[2] digitsBuf;
	int pos;
	int minValue, maxValue;
	bool optionalZero;

	this(int x, int y, string label, int value, int minValue, int maxValue, bool optionalZero = false) {
		super(x, y, label, 2);
		this.minValue = minValue;
		this.maxValue = maxValue;
		this.optionalZero = optionalZero;
		setValue(value);
	}

	@property int value() {
		return (digitsBuf[0] - '0') * 10 + (digitsBuf[1] - '0');
	}

	void setValue(int value) {
		if(value < 0) value = 0;
		if(value > 99) value = 99;
		digitsBuf[0] = cast(char)('0' + value / 10);
		digitsBuf[1] = cast(char)('0' + value % 10);
	}

	override string valueText() {
		return cast(string)digitsBuf[];
	}

	override int cursorOffset() {
		return pos;
	}

	private void step(int delta) {
		pos += delta;
		if(pos < 0) pos = 0;
		if(pos > 1) pos = 1;
	}

	private void increment(int delta) {
		int v = value + delta;
		if(optionalZero && v < minValue) v = 0;
		else if(v < minValue) v = maxValue;
		if(v > maxValue) v = optionalZero ? 0 : minValue;
		setValue(v);
	}

	override int keypress(Keyinfo key) {
		if(!enabled) return OK;
		switch(key.raw) {
		case SDLK_LEFT:
			step(-1);
			break;
		case SDLK_RIGHT:
			step(1);
			break;
		case SDLK_UP:
			increment(1);
			break;
		case SDLK_DOWN:
			increment(-1);
			break;
		case SDLK_BACKSPACE:
			digitsBuf[pos] = '0';
			break;
		default:
			if(key.raw >= '0' && key.raw <= '9') {
				digitsBuf[pos] = cast(char)key.raw;
				step(1);
			}
			break;
		}
		return OK;
	}
}

private class SaveBoolField : SaveOptionField {
	bool value;

	this(int x, int y, string label, bool value) {
		super(x, y, label, 3);
		this.value = value;
	}

	override string valueText() {
		return value ? "yes" : "no";
	}

	override int keypress(Keyinfo key) {
		if(!enabled) return OK;
		switch(key.raw) {
		case SDLK_LEFT, SDLK_RIGHT, SDLK_UP, SDLK_DOWN, SDLK_SPACE:
			value = !value;
			break;
		default:
			if(key.raw == 'y') value = true;
			else if(key.raw == 'n') value = false;
			break;
		}
		return OK;
	}
}

class SaveFileDialog : FileSelectorDialog {
	private {
		SaveFormatField formatField;
		SaveHexField addressField, zpField;
		SaveDecimalField singleSubtuneField, defaultSubtuneField;
		SaveBoolField purgeField;
	}

	this(Rectangle a, CB cb) {
		super(a, "Save Song", cb);
		help = ui.help.HELPSAVE;
		fsel.area.height = a.height - 10;
		int optionY = area.y + area.height - 4;
		int optionX = area.x + 3;
		formatField = new SaveFormatField(optionX, optionY);
		addressField = new SaveHexField(optionX + 10, optionY, "Load:", 4, 0x1000, false, true);
		zpField = new SaveHexField(optionX + 23, optionY, "ZP:", 2, 0xfb);
		singleSubtuneField = new SaveDecimalField(optionX + 31, optionY, "Sub:", 0, 1, SUBTUNE_MAX, true);
		defaultSubtuneField = new SaveDecimalField(optionX + 39, optionY, "Def:", 1, 1, SUBTUNE_MAX);
		purgeField = new SaveBoolField(optionX + 47, optionY, "Purge:", true);
		formatField.changed = &formatChanged;
		windows ~= [cast(Window)formatField, addressField, zpField,
					singleSubtuneField, defaultSubtuneField, purgeField];
		activateWindow(2);
	}

	@property SaveFormat saveFormat() {
		if(formatField is null)
			return SaveFormat.CT;
		return formatField.value;
	}

	@property int relocAddress() {
		return addressField.value;
	}

	@property int zpAddress() {
		return zpField.value;
	}

	@property int singleSubtune() {
		return singleSubtuneField.value;
	}

	@property int defaultSubtune() {
		return defaultSubtuneField.value;
	}

	@property bool purgeBeforeExport() {
		return purgeField.value;
	}

	@property string extension() {
		final switch(saveFormat) {
		case SaveFormat.CT: return ".ct";
		case SaveFormat.PRG: return ".prg";
		case SaveFormat.SID: return ".sid";
		}
	}

	private bool exportMode() {
		return saveFormat != SaveFormat.CT;
	}

	private void syncOptionState() {
		if(formatField is null)
			return;
		bool isExport = exportMode();
		addressField.enabled = isExport;
		zpField.enabled = isExport;
		singleSubtuneField.enabled = isExport;
		defaultSubtuneField.enabled = saveFormat == SaveFormat.SID && singleSubtune == 0;
		purgeField.enabled = isExport;
	}

	private void formatChanged() {
		syncFilenameToFormat();
		syncOptionState();
		auto activeOption = cast(SaveOptionField)activeWindow;
		if(activeOption !is null && !activeOption.enabled)
			focusOption(formatField);
	}

	private void focusOption(SaveOptionField field) {
		foreach(index, window; windows) {
			if(window is field) {
				activateWindow(index);
				return;
			}
		}
	}

	void syncFilenameToFormat() {
		string filename = sfile.toString().strip();
		if(filename.length == 0)
			return;
		int slash = cast(int)filename.lastIndexOf(DIR_SEPARATOR);
		int dot = cast(int)filename.lastIndexOf('.');
			if(dot > slash)
				filename = filename[0 .. dot];
		sfile.setString(filename ~ extension);
	}

	override ContextHelp contextHelp() {
		return ui.help.HELPSAVE;
	}

	override void activate() {
		syncFilenameToFormat();
		super.activate();
	}

	override protected bool selectedEntryUpdatesFilename() {
		return false;
	}

	private bool handleSaveExportKeyboardAction(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveSaveExportDialogKeyboardAction(key, actionId))
			return false;

		switch(actionId) {
		case KeyboardActionId.saveExportFormatCt:
			formatField.setValue(SaveFormat.CT);
			update();
			return true;
		case KeyboardActionId.saveExportFormatPrg:
			formatField.setValue(SaveFormat.PRG);
			update();
			return true;
		case KeyboardActionId.saveExportFormatSid:
			formatField.setValue(SaveFormat.SID);
			update();
			return true;
		case KeyboardActionId.saveExportNextField:
			super.keypress(key);
			return true;
		default:
			return false;
		}
	}

	final bool handleModalPriorityKey(Keyinfo key) {
		if(formatField !is null && handleSaveExportKeyboardAction(key))
			return true;
		return false;
	}

	override void update() {
		if(formatField is null) {
			super.update();
			return;
		}

		syncOptionState();

		for(int y = area.y; y < area.y+area.height; y++) {
			screen.cprint(area.x, y, 1, 0, std.array.replicate(" ",area.width));
		}
		drawFrame(area);
		int x = area.x + 3;
		screen.cprint(x, area.y, 1, 0, " Save Song ");
		drawBrowserFilter();

		screen.fprint(x, area.y+area.height-3, format("`0fDirectory: `0d%s", sdir.toString()));

		string f = sfile.toString();
		int ind = cast(int) (1+f.lastIndexOf(DIR_SEPARATOR));
		screen.fprint(x, area.y+area.height-2, format("`0f Filename: `0d%s", f[ind..$]));

		string optimizeShortcutLabels =
			keyboardActionShortcutLabelList("song.optimize_confirm");
		screen.fprint(x, area.y+area.height-7,
			"`0fTip: Open optimise/purge confirmation");
		if(optimizeShortcutLabels.length > 0) {
			screen.fprint(x, area.y+area.height-6,
				"`0fwith `0d" ~ optimizeShortcutLabels ~ "`0f.");
		}
		else {
			screen.fprint(x, area.y+area.height-6,
				"`0ffrom Song controls.");
		}

		formatField.draw(activeWindow == formatField);
		addressField.draw(activeWindow == addressField);
		zpField.draw(activeWindow == zpField);
		singleSubtuneField.draw(activeWindow == singleSubtuneField);
		defaultSubtuneField.draw(activeWindow == defaultSubtuneField);
		purgeField.draw(activeWindow == purgeField);

		if(activeWindow == fsel) {
			fsel.update();
			fsel.blink();
		}
		else {
			fsel.update();
			if(activeWindow == sdir || activeWindow == sfile)
				activeWindow.update();
		}
		input = activeWindow.input;
	}

	override int keypress(Keyinfo key) {
		if(handleModalPriorityKey(key))
			return OK;
		return super.keypress(key);
	}

	override void clickedAt(int screenX, int screenY, int button) {
		if(button == 1) {
			syncOptionState();
			foreach(window; windows) {
				auto field = cast(SaveOptionField)window;
				if(field !is null && field.enabled &&
						field.area.overlaps(screenX, screenY)) {
					focusOption(field);
					return;
				}
			}
		}
		super.clickedAt(screenX, screenY, button);
	}

	override protected int returnPressed(CB cb) {
		bool selectedDirectory = activeWindow == fsel &&
			std.file.isDir(fsel.selected);
		if(activeWindow == fsel && !selectedDirectory)
			setFilename(fsel.selectedName);
		if(activeWindow != sdir && !selectedDirectory)
			syncFilenameToFormat();
		return returnPressedWithOverwriteConfirmation(cb);
	}
}
