/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ui.tables;
import ui.ui;
import ui.dialogs;
import ui.input;
import ui.help;
import audio.seekmanager : timelineSeekManager;
import com.session;
import com.util;
import ct.purge;
import derelict.sdl2.sdl;
import std.string;
import std.stdio : stderr;
import std.file;
import std.path : baseName, buildPath, dirName;
import com.fb;
import std.conv, std.array;
import core.stdc.stdlib : getenv;

enum InstrumentPointerTarget {
	none = -1,
	wave = 0,
	pulse = 1,
	filter = 2
}

enum ProgramTableRowKind {
	none = 0,
	wave,
	pulse,
	filter
}

enum int PROGRAM_TABLE_ROW_DRAG_AUTOSCROLL_MARGIN_ROWS = 3;
enum int PROGRAM_TABLE_ROW_DRAG_AUTOSCROLL_INTERVAL_TICKS = 4;

enum ProgramTableRowDragAutoScrollDirection {
	none = 0,
	up = -1,
	down = 1
}

enum InstrumentClipboardKind {
	none = 0,
	wholeInstrument,
	byteRange
}

struct InstrumentByteSelectionState {
	bool active;
	int instrument;
	int anchorColumn;
	int endpointColumn;

	void clear() {
		active = false;
		instrument = 0;
		anchorColumn = 0;
		endpointColumn = 0;
	}

	void select(int selectedInstrument, int anchor, int endpoint) {
		active = true;
		instrument = selectedInstrument;
		anchorColumn = anchor;
		endpointColumn = endpoint;
	}
}

struct InstrumentByteRange {
	int instrument;
	int startColumn;
	int endColumn;

	@property int byteCount() const {
		return endColumn - startColumn + 1;
	}
}

struct InstrumentByteSelectionSnapshot {
	int instrument;
	int byteColumn;
	int nibble;
	InstrumentQuickHelpKind quickHelpKind;
	string quickHelpText;
	int inputCursorX = -1;
	int inputCursorY = -1;
	bool selectionActive;
	int selectionAnchor = -1;
	int selectionEndpoint = -1;
	bool dragCandidateActive;
	bool dragCommittedActive;
	int dragInstrument = -1;
	int dragAnchorColumn = -1;
}

struct ProgramTableByteCell {
	bool valid;
	int column = -1;
	int nibble = -1;
}

ProgramTableByteCell programTableByteCellAt(int localX, int columnCount) {
	ProgramTableByteCell cell;
	if(columnCount <= 0)
		return cell;
	int localColumnX = localX - 3;
	if(localColumnX < 0)
		return cell;
	int byteColumn = localColumnX / 3;
	int nibble = localColumnX - byteColumn * 3;
	if(byteColumn < 0 || byteColumn >= columnCount || nibble < 0 ||
			nibble > 1)
		return cell;
	cell.valid = true;
	cell.column = byteColumn;
	cell.nibble = nibble;
	return cell;
}

int instrumentByteStorageOffset(int instrument, int displayedByteColumn) {
	return instrument + displayedByteColumn * 48;
}

bool instrumentByteColumnIsValid(int column) {
	return column >= 0 && column < 8;
}

bool instrumentByteSelectionRange(InstrumentByteSelectionState selection,
		out InstrumentByteRange range) {
	if(!selection.active || selection.instrument < 0 ||
			selection.instrument >= 48 ||
			!instrumentByteColumnIsValid(selection.anchorColumn) ||
			!instrumentByteColumnIsValid(selection.endpointColumn))
		return false;
	range.instrument = selection.instrument;
	range.startColumn = selection.anchorColumn < selection.endpointColumn ?
		selection.anchorColumn : selection.endpointColumn;
	range.endColumn = selection.anchorColumn > selection.endpointColumn ?
		selection.anchorColumn : selection.endpointColumn;
	return true;
}

bool instrumentByteSelectionExtend(InstrumentByteSelectionState before,
		int currentInstrument, int currentColumn, int delta,
		out InstrumentByteSelectionState after, out int targetColumn) {
	after = before;
	targetColumn = currentColumn + delta;
	if(currentInstrument < 0 || currentInstrument >= 48 ||
			!instrumentByteColumnIsValid(currentColumn))
		return false;
	int anchor = before.active && before.instrument == currentInstrument ?
		before.anchorColumn : currentColumn;
	if(!instrumentByteColumnIsValid(anchor))
		anchor = currentColumn;
	if(!instrumentByteColumnIsValid(targetColumn))
		targetColumn = before.active && before.instrument == currentInstrument ?
			before.endpointColumn : currentColumn;
	if(!instrumentByteColumnIsValid(targetColumn))
		targetColumn = currentColumn;
	after.select(currentInstrument, anchor, targetColumn);
	return true;
}

bool instrumentByteRangePasteFits(int targetColumn, int byteCount) {
	return instrumentByteColumnIsValid(targetColumn) && byteCount > 0 &&
		targetColumn + byteCount <= 8;
}

bool copyInstrumentByteRangeData(const(ubyte)[] data,
		InstrumentByteRange range, ref ubyte[8] copiedBytes,
		ref int copiedByteCount) {
	if(range.instrument < 0 || range.instrument >= 48 ||
			range.startColumn < 0 || range.endColumn >= 8 ||
			range.startColumn > range.endColumn || data.length < 48 * 8)
		return false;
	int count = range.byteCount;
	foreach(i; 0 .. count) {
		copiedBytes[i] = data[instrumentByteStorageOffset(range.instrument,
			range.startColumn + i)];
	}
	copiedByteCount = count;
	return true;
}

bool writeInstrumentByteRangeData(ubyte[] data, int targetInstrument,
		int targetColumn, const(ubyte)[] copiedBytes, int copiedByteCount) {
	if(targetInstrument < 0 || targetInstrument >= 48 ||
			data.length < 48 * 8 ||
			copiedByteCount <= 0 || copiedByteCount > copiedBytes.length ||
			!instrumentByteRangePasteFits(targetColumn, copiedByteCount))
		return false;
	foreach(i; 0 .. copiedByteCount) {
		data[instrumentByteStorageOffset(targetInstrument, targetColumn + i)] =
			copiedBytes[i];
	}
	return true;
}

struct ProgramTableRowSelectionState {
	bool active;
	int anchorRow;
	int cursorRow;

	void clear() {
		active = false;
		anchorRow = 0;
		cursorRow = 0;
	}

	void select(int anchor, int cursor) {
		active = true;
		anchorRow = anchor;
		cursorRow = cursor;
	}
}

struct ProgramTableRowRange {
	int start;
	int end;

	@property int rowCount() const {
		return end - start + 1;
	}
}

int programTableRowBytesPerRow(ProgramTableRowKind kind) {
	final switch(kind) {
	case ProgramTableRowKind.none:
		return 0;
	case ProgramTableRowKind.wave:
		return 2;
	case ProgramTableRowKind.pulse:
	case ProgramTableRowKind.filter:
		return 4;
	}
}

bool programTableRowSelectionRange(ProgramTableRowSelectionState selection,
		out ProgramTableRowRange range) {
	if(!selection.active)
		return false;
	range.start = selection.anchorRow < selection.cursorRow ?
		selection.anchorRow : selection.cursorRow;
	range.end = selection.anchorRow > selection.cursorRow ?
		selection.anchorRow : selection.cursorRow;
	return true;
}

bool programTableRowPasteFits(int targetRow, int rowCount, int tableRows) {
	return rowCount > 0 && targetRow >= 0 && targetRow + rowCount <= tableRows;
}

bool programTableRowKindSupportsMouseDrag(ProgramTableRowKind kind) {
	return kind == ProgramTableRowKind.wave ||
		kind == ProgramTableRowKind.pulse ||
		kind == ProgramTableRowKind.filter;
}

ProgramTableRowDragAutoScrollDirection programTableRowDragAutoScrollDirectionForRow(
		int visibleRow, int visibleRows,
		int marginRows = PROGRAM_TABLE_ROW_DRAG_AUTOSCROLL_MARGIN_ROWS) {
	if(visibleRow < 0 || visibleRow >= visibleRows || marginRows <= 0)
		return ProgramTableRowDragAutoScrollDirection.none;
	if(visibleRow < marginRows)
		return ProgramTableRowDragAutoScrollDirection.up;
	if(visibleRow >= visibleRows - marginRows)
		return ProgramTableRowDragAutoScrollDirection.down;
	return ProgramTableRowDragAutoScrollDirection.none;
}

bool advanceProgramTableRowDragAutoScrollCadence(ref int accumulator) {
	accumulator++;
	if(accumulator < PROGRAM_TABLE_ROW_DRAG_AUTOSCROLL_INTERVAL_TICKS)
		return false;
	accumulator = 0;
	return true;
}

struct GeneratedProgramTableMouseDragSnapshot {
	ProgramTableRowKind kind;
	int row;
	int cursorOffset;
	int viewOffset;
	int column;
	int nibble;
	bool selectionActive;
	int selectionStart = -1;
	int selectionEnd = -1;
	bool dragActive;
	bool dragCommitted;
	int dragVisibleRow = -1;
	ProgramTableRowDragAutoScrollDirection dragDirection =
		ProgramTableRowDragAutoScrollDirection.none;
}

private struct ProgramTableRowClipboard {
	ProgramTableRowKind kind;
	int rowCount;
	int bytesPerRow;
	ubyte[] bytes;

	void clear() {
		kind = ProgramTableRowKind.none;
		rowCount = 0;
		bytesPerRow = 0;
		bytes.length = 0;
	}

	void store(ProgramTableRowKind k, int rows, int bpr, const(ubyte)[] src) {
		kind = k;
		rowCount = rows;
		bytesPerRow = bpr;
		bytes = src.dup;
	}

	bool hasRowsFor(ProgramTableRowKind k) const {
		return kind == k && rowCount > 0 && bytesPerRow > 0 &&
			bytes.length == rowCount * bytesPerRow;
	}
}

private ProgramTableRowClipboard programTableRowClipboard;

private enum ProgramTableRowDragPhase {
	none,
	candidate,
	committed
}

private struct ProgramTableRowDragState {
	ProgramTableRowDragPhase phase = ProgramTableRowDragPhase.none;
	int anchorRow;
	int visibleRow = -1;
	ProgramTableRowDragAutoScrollDirection direction =
		ProgramTableRowDragAutoScrollDirection.none;
	int ticks;

	@property bool isActive() const {
		return phase != ProgramTableRowDragPhase.none;
	}

	@property bool isCommitted() const {
		return phase == ProgramTableRowDragPhase.committed;
	}

	void armCandidate(int anchor) {
		clear();
		phase = ProgramTableRowDragPhase.candidate;
		anchorRow = anchor;
	}

	void commit() {
		phase = ProgramTableRowDragPhase.committed;
	}

	void clear() {
		phase = ProgramTableRowDragPhase.none;
		anchorRow = 0;
		visibleRow = -1;
		direction = ProgramTableRowDragAutoScrollDirection.none;
		ticks = 0;
	}
}

enum INSTRUMENT_FILTER_POINTER_COLUMN = 4;
enum INSTRUMENT_PULSE_POINTER_COLUMN = 5;
enum INSTRUMENT_WAVE_POINTER_COLUMN = 7;
private enum int PROGRAM_PREVIEW_ANCHOR_ROW = 0x02;

enum InstrumentQuickHelpKind {
	none = 0,
	attack,
	decay,
	sustain,
	release,
	restart,
	waveDelay,
	hardRestartWaveform,
	hardRestartFlags,
	filterPointer,
	pulsePointer,
	hardRestartSustain,
	hardRestartRelease,
	wavePointer
}

InstrumentQuickHelpKind instrumentQuickHelpKind(int column, int nibble,
		int value) {
	if(nibble < 0 || nibble > 1)
		return InstrumentQuickHelpKind.none;
	switch(column) {
	case 0:
		return nibble == 0 ? InstrumentQuickHelpKind.attack :
			InstrumentQuickHelpKind.decay;
	case 1:
		return nibble == 0 ? InstrumentQuickHelpKind.sustain :
			InstrumentQuickHelpKind.release;
	case 2:
		return nibble == 0 ? InstrumentQuickHelpKind.restart :
			InstrumentQuickHelpKind.waveDelay;
	case 3:
		return nibble == 0 ? InstrumentQuickHelpKind.hardRestartWaveform :
			InstrumentQuickHelpKind.hardRestartFlags;
	case INSTRUMENT_FILTER_POINTER_COLUMN:
		return InstrumentQuickHelpKind.filterPointer;
	case INSTRUMENT_PULSE_POINTER_COLUMN:
		return InstrumentQuickHelpKind.pulsePointer;
	case 6:
		return nibble == 0 ? InstrumentQuickHelpKind.hardRestartSustain :
			InstrumentQuickHelpKind.hardRestartRelease;
	case INSTRUMENT_WAVE_POINTER_COLUMN:
		return InstrumentQuickHelpKind.wavePointer;
	default:
		return InstrumentQuickHelpKind.none;
	}
}

string instrumentQuickHelpText(InstrumentQuickHelpKind kind) {
	final switch(kind) {
	case InstrumentQuickHelpKind.none:
		return "";
	case InstrumentQuickHelpKind.attack:
		return "Attack rate: $0 fastest, $F slowest.";
	case InstrumentQuickHelpKind.decay:
		return "Decay rate: $0 fastest, $F slowest.";
	case InstrumentQuickHelpKind.sustain:
		return "Sustain level: $0 silent, $F maximum.";
	case InstrumentQuickHelpKind.release:
		return "Release rate: $0 fastest, $F slowest.";
	case InstrumentQuickHelpKind.restart:
		return "Restart: $0 normal, $4 soft, $8 hard; +$2 skips HR AD.";
	case InstrumentQuickHelpKind.waveDelay:
		return "Wave delay: $0-$F frames.";
	case InstrumentQuickHelpKind.hardRestartWaveform:
		return "HR waveform: $1 tri, $2 saw, $4 pulse, $8 noise.";
	case InstrumentQuickHelpKind.hardRestartFlags:
		return "HR flags: $8 test, $4 ring, $2 sync; gate on.";
	case InstrumentQuickHelpKind.filterPointer:
		return "Filter-table start row: $00 off, $01-$3F.";
	case InstrumentQuickHelpKind.pulsePointer:
		return "Pulse-table start row: $00 off, $01-$3F.";
	case InstrumentQuickHelpKind.hardRestartSustain:
		return "HR sustain: $0 silent, $F maximum.";
	case InstrumentQuickHelpKind.hardRestartRelease:
		return "HR release: $0 fastest, $F slowest.";
	case InstrumentQuickHelpKind.wavePointer:
		return "Wave-table start row: $00-$FF.";
	}
}

private InstrumentPointerTarget instrumentPointerTargetForColumn(int column) {
	switch(column) {
	case INSTRUMENT_WAVE_POINTER_COLUMN:
		return InstrumentPointerTarget.wave;
	case INSTRUMENT_PULSE_POINTER_COLUMN:
		return InstrumentPointerTarget.pulse;
	case INSTRUMENT_FILTER_POINTER_COLUMN:
		return InstrumentPointerTarget.filter;
	default:
		return InstrumentPointerTarget.none;
	}
}

version(OSX) {
private enum TABLE_JUMP_MOD_LABEL = "Option";
}
else {
private enum TABLE_JUMP_MOD_LABEL = "Alt";
}

abstract class Table : Window {
	mixin ValueChangedHandler;
	const int columns, rows, visibleRows;
	protected {
		ubyte[] data;
		int column, row, cursorOffset, viewOffset;
	}
	
	this(Rectangle a, ubyte[] tbl, int c, int r) {
		super(a);
		columns = c;
		rows = r;
		data = tbl;
		input = new InputByte(tbl[0..1]);
		visibleRows = a.height - 1;
	}

	override void refresh() {
		update();
	}

	void resetSongPosition() {
		column = 0;
		row = 0;
		cursorOffset = 0;
		viewOffset = 0;
		input.nibble = 0;
	}

	void showByteDescription() {
	}

	void showByteDescription(PetString pet) {
		if(song.ver < 9 || !state.displayHelp) return;
		string[] s = com.util.petscii2D(pet).splitLines();
		string outstr = s[0];
		if(s.length > 1)
			outstr ~= " " ~ ui.help.helpMoreStatusHint();
		UI.statusline.displayContextual(format("Byte %d: %s", column + 1, outstr));
	}

protected:
	
	void adjustView();
}

private class HexTable : Table, Undoable {
	private ProgramTableRowSelectionState rowSelection;
	private ProgramTableRowDragState rowDrag;

	this(Rectangle a, ubyte[] tbl, int c, int r) {
		super(a,tbl,c,r);
		(cast(InputValue)input).setValueChangedCallback(&valueChangedCallback);
	}

	void valueChangedCallback() {
		saveState(false);
		valueWritePending();
	}

	protected void valueWritePending() {
	}
	
	override void activate() {
		initializeInput();
		showByteDescription();
	}

	override void refresh() {
		cancelProgramRowDrag();
		super.refresh();
	}

	override void deactivate() {
		clearProgramRowSelection(false);
	}

	override void resetSongPosition() {
		super.resetSongPosition();
		clearProgramRowSelection(false);
	}

	void initializeInput() {
		input.setCoord(area.x + 3 + column * 3, area.y + cursorOffset + 1);
	}
	alias initializeInput set;

	override protected void adjustView() {
		if(column >= columns) {
			column -= columns;
		}
		else if(column < 0) {
			column += columns;
		}
		if(row >= rows) {
			row = row - rows;
		}
		else if(row < 0) {
			row = rows + row;
		}
		assert(row >= 0);
		if(cursorOffset >= visibleRows) {
			int i = cursorOffset - visibleRows + 1;
			viewOffset += i;
			if(viewOffset >= rows) {
				viewOffset -= rows;
			}
			cursorOffset -= i;
		}
		if(cursorOffset < 0) {
			int i = -cursorOffset;
			viewOffset -= i;
			if(viewOffset < 0)
				viewOffset += rows;
			cursorOffset += i;
		}
		initializeInput();
	}

	void stepColumn(int n) {
		column += n;
		adjustView();
		showByteDescription();
	}

	void setColumn(int n) {
		column = n;
		adjustView();
	}

	void stepColumnWrap(int n) {
		column += n;
		if(column >= columns) {
			stepRow(1);
		}
		adjustView();
	}

	void stepRow(int n) {
		seekRow(n + row);
	}

	void setCursorOffset(int r) {
		row += r - cursorOffset;
		cursorOffset = r;
		adjustView();
	}

	void seekRow(int r) {
		cursorOffset += r - row;
		row = r;
		adjustView();
	}

	void placeCurrentRowAtProgramPreviewAnchor() {
		int maxViewOffset = rows > visibleRows ? rows - visibleRows : 0;
		viewOffset = clamp(row - PROGRAM_PREVIEW_ANCHOR_ROW,
			0, maxViewOffset);
		cursorOffset = row - viewOffset;
		initializeInput();
	}

	void seekTableEnd() {
	}

	void deleteRow() {
	}

	void insertRow() {
	}

	bool executeGeneratedTableRowStructureAction(Keyinfo key) {
		KeyboardActionId actionId;
		bool resolved = resolveGeneratedTableRowStructureKeyboardAction(key,
			actionId);
		if(!resolved)
			return false;
		clearProgramRowSelection(false);
		switch(actionId) {
		case KeyboardActionId.generatedTableRowDelete:
			deleteRow();
			return true;
		case KeyboardActionId.generatedTableRowInsert:
			insertRow();
			return true;
		default:
			return false;
		}
	}

	protected ProgramTableRowKind programTableRowKind() {
		return ProgramTableRowKind.none;
	}

	private bool supportsProgramRowSelection() {
		return programTableRowKind() != ProgramTableRowKind.none;
	}

	private bool supportsProgramRowMouseDrag() {
		return programTableRowKindSupportsMouseDrag(programTableRowKind());
	}

	GeneratedProgramTableMouseDragSnapshot
			generatedProgramTableMouseDragSnapshot() {
		GeneratedProgramTableMouseDragSnapshot snapshot;
		snapshot.kind = programTableRowKind();
		snapshot.row = row;
		snapshot.cursorOffset = cursorOffset;
		snapshot.viewOffset = viewOffset;
		snapshot.column = column;
		snapshot.nibble = input.nibble;
		ProgramTableRowRange range;
		if(programTableRowSelectionRange(rowSelection, range)) {
			snapshot.selectionActive = true;
			snapshot.selectionStart = range.start;
			snapshot.selectionEnd = range.end;
		}
		snapshot.dragActive = rowDrag.isActive;
		snapshot.dragCommitted = rowDrag.isCommitted;
		snapshot.dragVisibleRow = rowDrag.visibleRow;
		snapshot.dragDirection = rowDrag.direction;
		return snapshot;
	}

	protected string programTableRowLabel() {
		final switch(programTableRowKind()) {
		case ProgramTableRowKind.none:
			return "Program";
		case ProgramTableRowKind.wave:
			return "Wave";
		case ProgramTableRowKind.pulse:
			return "Pulse";
		case ProgramTableRowKind.filter:
			return "Filter";
		}
	}

	protected int programRowBytesPerRow() {
		return programTableRowBytesPerRow(programTableRowKind());
	}

	protected void readProgramRowBytes(int sourceRow, ubyte[] dest) {
		int bpr = programRowBytesPerRow();
		int offset = sourceRow * bpr;
		dest[0 .. bpr] = data[offset .. offset + bpr];
	}

	protected void writeProgramRowBytes(int targetRow, const(ubyte)[] src) {
		int bpr = programRowBytesPerRow();
		int offset = targetRow * bpr;
		data[offset .. offset + bpr] = src[0 .. bpr];
	}

	protected bool programRowIsSelected(int tableRow) {
		ProgramTableRowRange range;
		if(!programTableRowSelectionRange(rowSelection, range))
			return false;
		return tableRow >= range.start && tableRow <= range.end;
	}

	protected void drawProgramRowSelectionText(int screenY, string text) {
		screen.cprint(area.x + 3, screenY, 1, 6, text);
	}

	protected string programRowSelectionQuickHelpText() {
		string extendUp = keyboardActionPrimaryShortcutLabel(
			"table.row_selection_extend_up", "generated_table");
		string extendDown = keyboardActionPrimaryShortcutLabel(
			"table.row_selection_extend_down", "generated_table");
		string copy = keyboardActionPrimaryShortcutLabel(
			"table.row_copy", "generated_table");
		string paste = keyboardActionPrimaryShortcutLabel(
			"table.row_paste", "generated_table");
		string clear = keyboardActionPrimaryShortcutLabel(
			"table.row_selection_clear", "generated_table");
		assert(extendUp.length && extendDown.length && copy.length &&
			paste.length && clear.length);
		return "Click-drag selects rows.\n" ~
			extendUp ~ "/" ~ extendDown ~ " extends selection.\n" ~
			copy ~ " copy; " ~ paste ~ " paste; " ~ clear ~ " clear.";
	}

	private void showProgramRowSelectionHelp() {
		if(!state.displayHelp || UI.statusline is null)
			return;
		UI.statusline.displayContextualSemantic(
			programRowSelectionQuickHelpText(),
			format("program-row-selection:%s",
				cast(int)programTableRowKind()));
	}

	private void cancelProgramRowDrag() {
		rowDrag.clear();
	}

	private void clearProgramRowSelection(bool repaint) {
		cancelProgramRowDrag();
		if(!rowSelection.active)
			return;
		rowSelection.clear();
		if(repaint)
			update();
	}

	private bool programTableDataRowAt(int x, int y,
			out int visibleRow, out int logicalRow) {
		if(!area.overlaps(x, y))
			return false;
		visibleRow = y - area.y - 1;
		if(visibleRow < 0 || visibleRow >= visibleRows)
			return false;
		logicalRow = viewOffset + visibleRow;
		return logicalRow >= 0 && logicalRow < rows;
	}

	private bool moveCursorToTableCell(int x, int y) {
		int rx = x - area.x;
		int ry = y - area.y;
		auto cell = programTableByteCellAt(rx, columns);
		if(!cell.valid)
			return false;
		setCursorOffset(ry - 1);
		setColumn(cell.column);
		initializeInput();
		input.nibble = cell.nibble;
		input.update();
		showByteDescription();
		return true;
	}

	private void setProgramRowDragDirection(
			ProgramTableRowDragAutoScrollDirection direction, int visibleRow) {
		if(rowDrag.direction != direction)
			rowDrag.ticks = 0;
		rowDrag.direction = direction;
		rowDrag.visibleRow = visibleRow;
	}

	private void updateProgramRowDragFromVisibleRow(int visibleRow) {
		auto direction = programTableRowDragAutoScrollDirectionForRow(
			visibleRow, visibleRows);
		setProgramRowDragDirection(direction, visibleRow);
	}

	bool extendProgramRowSelectionAt(int x, int y) {
		int visibleRow, logicalRow;
		if(!supportsProgramRowMouseDrag() ||
				!programTableDataRowAt(x, y, visibleRow, logicalRow))
			return false;
		if(!programTableByteCellAt(x - area.x, columns).valid)
			return false;
		int anchor = rowSelection.active ? rowSelection.anchorRow : row;
		moveCursorToTableCell(x, y);
		rowSelection.select(anchor, row);
		rowDrag.clear();
		rowDrag.commit();
		updateProgramRowDragFromVisibleRow(visibleRow);
		update();
		showProgramRowSelectionHelp();
		return true;
	}

	private bool armProgramRowDragCandidateAt(int x, int y) {
		int visibleRow, logicalRow;
		if(!supportsProgramRowMouseDrag() ||
				!programTableDataRowAt(x, y, visibleRow, logicalRow))
			return false;
		if(!programTableByteCellAt(x - area.x, columns).valid)
			return false;
		rowDrag.armCandidate(row);
		return true;
	}

	private bool updateProgramRowDragAt(int x, int y) {
		if(!rowDrag.isActive)
			return false;
		int visibleRow, logicalRow;
		if(!programTableDataRowAt(x, y, visibleRow, logicalRow)) {
			setProgramRowDragDirection(
				ProgramTableRowDragAutoScrollDirection.none, -1);
			return false;
		}
		updateProgramRowDragFromVisibleRow(visibleRow);
		if(!rowDrag.isCommitted) {
			rowDrag.commit();
			if(logicalRow != row)
				seekRow(logicalRow);
			rowSelection.select(rowDrag.anchorRow, row);
			update();
			showProgramRowSelectionHelp();
			return true;
		}
		if(logicalRow == row)
			return false;
		seekRow(logicalRow);
		rowSelection.select(rowSelection.anchorRow, row);
		update();
		showProgramRowSelectionHelp();
		return true;
	}

	private bool moveProgramRowDragBy(int rowDelta) {
		int targetRow = row + rowDelta;
		if(targetRow < 0 || targetRow >= rows)
			return false;
		seekRow(targetRow);
		rowSelection.select(rowSelection.anchorRow, row);
		update();
		return true;
	}

	private int maxProgramRowDragViewOffset() {
		return rows > visibleRows ? rows - visibleRows : 0;
	}

	private bool placeProgramRowDragAtVisibleRow(int visibleRow) {
		if(visibleRow < 0 || visibleRow >= visibleRows)
			return false;
		int targetRow = viewOffset + visibleRow;
		if(targetRow < 0 || targetRow >= rows)
			return false;
		row = targetRow;
		cursorOffset = visibleRow;
		initializeInput();
		showProgramRowSelectionHelp();
		return row - viewOffset == visibleRow;
	}

	private bool moveProgramRowDragViewportBy(
			ProgramTableRowDragAutoScrollDirection direction) {
		if(!rowDrag.isCommitted)
			return false;
		int visibleRow = rowDrag.visibleRow;
		if(visibleRow < 0 || visibleRow >= visibleRows)
			return false;
		if(programTableRowDragAutoScrollDirectionForRow(
				visibleRow, visibleRows) != direction)
			return false;

		int rowDelta;
		final switch(direction) {
		case ProgramTableRowDragAutoScrollDirection.none:
			return false;
		case ProgramTableRowDragAutoScrollDirection.up:
			rowDelta = -1;
			break;
		case ProgramTableRowDragAutoScrollDirection.down:
			rowDelta = 1;
			break;
		}

		int newViewOffset = clamp(viewOffset + rowDelta,
			0, maxProgramRowDragViewOffset());
		if(newViewOffset == viewOffset)
			return false;
		viewOffset = newViewOffset;
		if(!placeProgramRowDragAtVisibleRow(visibleRow))
			return false;
		rowSelection.select(rowSelection.anchorRow, row);
		update();
		return true;
	}

	private void extendProgramRowSelectionTo(KeyboardActionId actionId) {
		int anchor = rowSelection.active ? rowSelection.anchorRow : row;
		switch(actionId) {
		case KeyboardActionId.generatedTableRowSelectionExtendUp:
			stepRow(-1);
			break;
		case KeyboardActionId.generatedTableRowSelectionExtendDown:
			stepRow(1);
			break;
		case KeyboardActionId.generatedTableRowSelectionExtendPageUp:
			stepRow(-PAGESTEP / 2);
			break;
		case KeyboardActionId.generatedTableRowSelectionExtendPageDown:
			stepRow(PAGESTEP / 2);
			break;
		case KeyboardActionId.generatedTableRowSelectionExtendHome:
			seekRow(0);
			break;
		case KeyboardActionId.generatedTableRowSelectionExtendEnd:
			seekRow(rows - 1);
			break;
		default:
			break;
		}
		rowSelection.select(anchor, row);
		update();
		showProgramRowSelectionHelp();
	}

	private void copyProgramRows() {
		ProgramTableRowRange range;
		if(!programTableRowSelectionRange(rowSelection, range)) {
			UI.statusline.displayOperationFeedback(format(
				"No %s row selection.", programTableRowLabel()));
			return;
		}
		int bpr = programRowBytesPerRow();
		ubyte[] copied;
		copied.length = range.rowCount * bpr;
		foreach(i; 0 .. range.rowCount) {
			readProgramRowBytes(range.start + i,
				copied[i * bpr .. (i + 1) * bpr]);
		}
		programTableRowClipboard.store(programTableRowKind(), range.rowCount,
			bpr, copied);
		UI.statusline.displayOperationFeedback(format(
			"%s selection copied: %d.", programTableRowLabel(),
			range.rowCount));
	}

	private void pasteProgramRows() {
		if(!programTableRowClipboard.hasRowsFor(programTableRowKind())) {
			UI.statusline.displayOperationFeedback(format(
				"No %s row selection copied.", programTableRowLabel()));
			return;
		}
		if(!programTableRowPasteFits(row, programTableRowClipboard.rowCount,
				rows)) {
			UI.statusline.displayOperationFeedback(format(
				"%s row selection does not fit.", programTableRowLabel()));
			return;
		}
		saveState(true);
		int bpr = programTableRowClipboard.bytesPerRow;
		foreach(i; 0 .. programTableRowClipboard.rowCount) {
			writeProgramRowBytes(row + i,
				programTableRowClipboard.bytes[i * bpr .. (i + 1) * bpr]);
		}
		refresh();
		set();
		UI.statusline.displayOperationFeedback(format(
			"%s selection pasted: %d.", programTableRowLabel(),
			programTableRowClipboard.rowCount));
	}

	private bool executeGeneratedTableRowSelectionAction(Keyinfo key) {
		KeyboardActionId actionId;
		if(!resolveGeneratedTableRowSelectionKeyboardAction(key, actionId))
			return false;
		if(!supportsProgramRowSelection())
			return false;
		switch(actionId) {
		case KeyboardActionId.generatedTableRowSelectionExtendUp:
		case KeyboardActionId.generatedTableRowSelectionExtendDown:
		case KeyboardActionId.generatedTableRowSelectionExtendPageUp:
		case KeyboardActionId.generatedTableRowSelectionExtendPageDown:
		case KeyboardActionId.generatedTableRowSelectionExtendHome:
		case KeyboardActionId.generatedTableRowSelectionExtendEnd:
			extendProgramRowSelectionTo(actionId);
			return true;
		case KeyboardActionId.generatedTableRowSelectionClear:
			clearProgramRowSelection(true);
			return true;
		case KeyboardActionId.generatedTableRowCopy:
			copyProgramRows();
			return true;
		case KeyboardActionId.generatedTableRowPaste:
			pasteProgramRows();
			return true;
		default:
			return false;
		}
	}

	void seekColumn(int c) {
		column = c;
	}

	override int keypress(Keyinfo key) {
        /+
		if(key.mods & KMOD_CTRL || key.mods & KMOD_ALT || 
		   key.mods & KMOD_META) return OK;
           +/
		if(executeGeneratedTableRowSelectionAction(key))
			return OK;
		if(rowSelection.active && (key.mods & KMOD_SHIFT) == 0)
			clearProgramRowSelection(true);
		if(key.mods & KMOD_CTRL || key.mods & KMOD_ALT || 
		   key.mods & KMOD_GUI) {
			return OK;
		}

		switch(key.raw) 
		{
		case SDLK_LEFT:
			if(input.step(-1) == WRAP) {
				stepColumn(-1);
			}
			break;
		case SDLK_RIGHT:
			if(input.step(1) == WRAP) {
				stepColumn(1);
			}
			break;
		case SDLK_DOWN:
			stepRow(1);
			break;
		case SDLK_UP:
			stepRow(-1);
			break;
		case SDLK_PAGEUP:
			stepRow(-PAGESTEP / 2);
			break;
		case SDLK_PAGEDOWN:
			stepRow(PAGESTEP / 2);
			break;
		case SDLK_HOME:
			if(cursorOffset > 0)
				setCursorOffset(0);
			else seekRow(0);
			break;
		case SDLK_END:
			if(cursorOffset < visibleRows - 1)
				setCursorOffset(visibleRows - 1);
			else seekTableEnd();
			break;
		case SDLK_h:
			showByteDescription();
			break;
			
		default:
			if(input.keypress(key) == WRAP) {
				stepColumnWrap(1);
			}
			break;
		}
		initializeInput();
		return OK;
	}

	override void clickedAt(int x, int y, int button) {
		if(button == 1 && (SDL_GetModState() & KMOD_SHIFT) != 0 &&
				extendProgramRowSelectionAt(x, y))
			return;
		bool moved = moveCursorToTableCell(x, y);
		if(button == 1 && moved) {
			clearProgramRowSelection(true);
			armProgramRowDragCandidateAt(x, y);
		}
	}

	override bool mouseMotionAt(int x, int y) {
		return updateProgramRowDragAt(x, y);
	}

	override bool mouseButtonUp(int button) {
		if(button != 1 || !rowDrag.isActive)
			return false;
		cancelProgramRowDrag();
		return true;
	}

	override bool advanceGeneratedTableRowDragAutoScroll() {
		if(!supportsProgramRowMouseDrag() || !rowDrag.isCommitted ||
				rowDrag.direction == ProgramTableRowDragAutoScrollDirection.none)
			return false;
		if(!advanceProgramTableRowDragAutoScrollCadence(rowDrag.ticks))
			return false;
		return moveProgramRowDragViewportBy(rowDrag.direction);
	}


protected:

	override final UndoValue createRedoState(UndoValue value) {
		return createState(true);
	}

	override final void undo(UndoValue v) {
		clearProgramRowSelection(false);
		// if array has 1 child, assume to be data for this table
		if(v.tableData.length == 1) {
			this.data[] = v.tableData[0];
		}
		else {
			int idx;
			song.tableIterator((ct.base.Song.Table t) {
					t.data[0..$] = v.tableData[idx++][0..$];
				});
		}
		initializeInput();
	}
	
	bool highlightRow(int row) {
		return false;
	}

	void saveState(bool allTables) {
		auto v = createState(allTables);
		com.session.insertUndo(this, v);
	}

private:

	UndoValue createState(bool allTables) {
		UndoValue v;
		if(allTables) {
			song.tableIterator((ct.base.Song.Table t) {
					v.tableData ~= t.data.dup;
				});
		}
		else v.tableData = [data.dup];
		return v;
	}

}

private class InstrumentPasteUndo : Undoable {
	override UndoValue createRedoState(UndoValue value) {
		return createState(value.subtuneNum);
	}

	override void undo(UndoValue v) {
		restoreState(v);
	}

	static UndoValue createState(int row) {
		UndoValue v;
		v.subtuneNum = row;

		ubyte[] instrumentBytes;
		instrumentBytes.length = 8;
		foreach(i; 0..8) {
			instrumentBytes[i] = song.instrumentTable[row + i * 48];
		}
		v.tableData ~= instrumentBytes;
		v.tableData ~= (cast(ubyte[])song.insLabels[row][]).dup;
		return v;
	}

	private static void restoreState(UndoValue v) {
		int row = v.subtuneNum;
		if(row < 0 || row >= 48 || v.tableData.length != 2 ||
				v.tableData[0].length != 8 ||
				v.tableData[1].length != song.insLabels[row].length)
			return;

		foreach(i, b; v.tableData[0]) {
			song.instrumentTable[row + i * 48] = b;
		}
		song.insLabels[row][] = cast(char[])v.tableData[1][];
		if(mainui !is null)
			mainui.refresh();
	}
}

enum WaveQuickHelpKind {
	none = 0,
	options,
	loopPrevious,
	jumpTarget,
	keepCurrentControl,
	delay,
	waveform,
	flags,
	controlOnly
}

WaveQuickHelpKind waveQuickHelpKind(int column, int nibble, int left,
		int right) {
	if(column < 0 || column > 1 || nibble < 0 || nibble > 1)
		return WaveQuickHelpKind.none;
	left &= 0xff;
	right &= 0xff;
	if(column == 0)
		return WaveQuickHelpKind.options;
	if(left == 0x7e)
		return WaveQuickHelpKind.loopPrevious;
	if(left == 0x7f)
		return WaveQuickHelpKind.jumpTarget;
	if(right == 0x00)
		return WaveQuickHelpKind.keepCurrentControl;
	if(right <= 0x0f)
		return WaveQuickHelpKind.delay;
	if(right <= 0xdf)
		return nibble == 0 ? WaveQuickHelpKind.waveform :
			WaveQuickHelpKind.flags;
	return nibble == 0 ? WaveQuickHelpKind.controlOnly :
		WaveQuickHelpKind.flags;
}

string waveQuickHelpText(WaveQuickHelpKind kind) {
	final switch(kind) {
	case WaveQuickHelpKind.none:
		return "";
	case WaveQuickHelpKind.options:
		return "Wave: $00-$7D rel, $7E loop, $7F jump, $80-$FF abs.";
	case WaveQuickHelpKind.loopPrevious:
		return "Loop previous Wave row; value byte is ignored.";
	case WaveQuickHelpKind.jumpTarget:
		return "Jump target: Wave row $00-$FF.";
	case WaveQuickHelpKind.keepCurrentControl:
		return "Waveform: $00 keeps current control.";
	case WaveQuickHelpKind.delay:
		return "Wave delay: $01-$0F frames; waveform unchanged.";
	case WaveQuickHelpKind.waveform:
		return "Waveform: $1 tri, $2 saw, $4 pulse, $8 noise.";
	case WaveQuickHelpKind.flags:
		return "Flags: $1 gate, $2 sync, $4 ring, $8 test.";
	case WaveQuickHelpKind.controlOnly:
		return "Control-only mode: right nibble sets flags.";
	}
}

enum PulseQuickHelpKind {
	none = 0,
	sweepDuration,
	pulseStep,
	pulseWidth,
	flow
}

PulseQuickHelpKind pulseQuickHelpKind(int column) {
	switch(column) {
	case 0:
		return PulseQuickHelpKind.sweepDuration;
	case 1:
		return PulseQuickHelpKind.pulseStep;
	case 2:
		return PulseQuickHelpKind.pulseWidth;
	case 3:
		return PulseQuickHelpKind.flow;
	default:
		break;
	}
	return PulseQuickHelpKind.none;
}

string pulseQuickHelpText(PulseQuickHelpKind kind) {
	final switch(kind) {
	case PulseQuickHelpKind.none:
		return "";
	case PulseQuickHelpKind.sweepDuration:
		return "Sweep duration: $00-$7F increase, $80-$FF decrease.";
	case PulseQuickHelpKind.pulseStep:
		return "Pulse step: $00 hold, $01-$FF per update.";
	case PulseQuickHelpKind.pulseWidth:
		return "Pulse width: XY sets $0YX0; $FF keeps current.";
	case PulseQuickHelpKind.flow:
		return "Flow: $00 next, $01-$3F jump, $7F stop.";
	}
}

enum FilterQuickHelpKind {
	none = 0,
	typeOptions,
	sweepDuration,
	setupIgnored,
	cutoffStep,
	resonance,
	filterMask,
	cutoffStart,
	flow
}

private bool filterQuickHelpSelectorIsSetup(int filterTypeByte) {
	return (filterTypeByte & 0x80) != 0;
}

FilterQuickHelpKind filterQuickHelpKind(int column, int nibble,
		int filterTypeByte) {
	if(nibble < 0 || nibble > 1)
		return FilterQuickHelpKind.none;
	bool setup = filterQuickHelpSelectorIsSetup(filterTypeByte);
	switch(column) {
	case 0:
		if(nibble == 0)
			return FilterQuickHelpKind.typeOptions;
		return setup ? FilterQuickHelpKind.setupIgnored :
			FilterQuickHelpKind.sweepDuration;
	case 1:
		if(!setup)
			return FilterQuickHelpKind.cutoffStep;
		return nibble == 0 ? FilterQuickHelpKind.resonance :
			FilterQuickHelpKind.filterMask;
	case 2:
		return FilterQuickHelpKind.cutoffStart;
	case 3:
		return FilterQuickHelpKind.flow;
	default:
		break;
	}
	return FilterQuickHelpKind.none;
}

string filterQuickHelpText(FilterQuickHelpKind kind) {
	final switch(kind) {
	case FilterQuickHelpKind.none:
		return "";
	case FilterQuickHelpKind.typeOptions:
		return "Type: $00-$7F sweep; $8x none; $9x low-pass.\n" ~
			"$Ax band-pass; $Bx low+band; $Cx high-pass.\n" ~
			"$Dx low+high; $Ex band+high; $Fx low+band+high.";
	case FilterQuickHelpKind.sweepDuration:
		return "Sweep duration: $00-$7F frames.";
	case FilterQuickHelpKind.setupIgnored:
		return "Setup low nibble ignored; use $x0.";
	case FilterQuickHelpKind.cutoffStep:
		return "Cutoff step: $00 hold, $01-$7F up, $80-$FF down.";
	case FilterQuickHelpKind.resonance:
		return "Resonance: $0 none, $F maximum.";
	case FilterQuickHelpKind.filterMask:
		return "Filter mask: $1 V1, $2 V2, $4 V3, $8 external.";
	case FilterQuickHelpKind.cutoffStart:
		return "Cutoff start: $00-$FE set, $FF keeps current.";
	case FilterQuickHelpKind.flow:
		return "Flow: $00 next, $01-$3F jump, $7F stop.";
	}
}

private enum InstrumentByteDragPhase {
	none,
	candidate,
	committed
}

private struct InstrumentByteDragState {
	InstrumentByteDragPhase phase = InstrumentByteDragPhase.none;
	int instrument = -1;
	int anchorColumn = -1;

	@property bool isActive() const {
		return phase != InstrumentByteDragPhase.none;
	}

	@property bool isCommitted() const {
		return phase == InstrumentByteDragPhase.committed;
	}

	void armCandidate(int selectedInstrument, int anchor) {
		phase = InstrumentByteDragPhase.candidate;
		instrument = selectedInstrument;
		anchorColumn = anchor;
	}

	void commit(int selectedInstrument, int anchor) {
		phase = InstrumentByteDragPhase.committed;
		instrument = selectedInstrument;
		anchorColumn = anchor;
	}

	void clear() {
		phase = InstrumentByteDragPhase.none;
		instrument = -1;
		anchorColumn = -1;
	}
}

class InsValueTable : HexTable {
	private {
		static ubyte[8] instrBuffer;
		static char[32] instrName;
		static bool hasInstrumentCopyBuffer;
		static ubyte[8] instrumentByteBuffer;
		static int instrumentByteBufferCount;
		static InstrumentClipboardKind mostRecentInstrumentClipboard;
		static InstrumentPasteUndo pasteUndo;
		InstrumentByteSelectionState byteSelection;
		int mark = -1;
		int width;
		int instrumentDialogTarget;
		InstrumentPointerTarget pendingPointerPreview;
		int pendingPointerPreviewOffset = -1;
		FileSelectorDialog loadDialog;
		InstrumentSaveFileDialog saveDialog;
		string instrumentDirectory;
		InstrumentByteDragState byteDrag;
	}
	this(Rectangle a) {
		width = com.fb.mode ? 32 : 16;
		super(a, song.instrumentTable, 8, 48);
		loadDialog = new FileSelectorDialog(Rectangle(),
											"Load Instrument",
											&loadCallback);
		saveDialog = new InstrumentSaveFileDialog(Rectangle(),
											&saveCallback);
		instrumentDirectory = initialInstrumentDirectory();
	}

	override void refresh() {
		data = song.instrumentTable; 
		clearByteSelection(false);
	}

	private static void clearDocumentClipboard() {
		instrBuffer[] = ubyte.init;
		instrName[] = char.init;
		hasInstrumentCopyBuffer = false;
		instrumentByteBuffer[] = ubyte.init;
		instrumentByteBufferCount = 0;
		mostRecentInstrumentClipboard = InstrumentClipboardKind.none;
	}

	override int keypress(Keyinfo key) {
		pendingPointerPreview = InstrumentPointerTarget.none;
		pendingPointerPreviewOffset = -1;
		if(key.mods & KMOD_ALT) {
			return OK;
		}
		KeyboardActionId actionId;
		if(resolveInstrumentByteSelectionKeyboardAction(key, actionId)) {
			switch(actionId) {
			case KeyboardActionId.instrumentByteSelectionExtendLeft:
				extendByteSelectionBy(-1);
				break;
			case KeyboardActionId.instrumentByteSelectionExtendRight:
				extendByteSelectionBy(1);
				break;
			default:
				break;
			}
			return OK;
		}
		if(resolveInstrumentTableCommandKeyboardAction(key, actionId)) {
			if(actionId == KeyboardActionId.instrumentPaste) {
				pasteInstrument();
				return OK;
			}
			if(actionId == KeyboardActionId.instrumentDeleteConfirm) {
				confirmDeleteInstrument();
				return OK;
			}
			if(actionId == KeyboardActionId.instrumentSaveDialog) {
				mainui.openContextualSaveDialog();
				return OK;
			}
			if(actionId == KeyboardActionId.instrumentLoadDialog) {
				mainui.openContextualLoadDialog();
				return OK;
			}
			copyInstrument();
			return OK;
		}
		if(key.raw == SDLK_ESCAPE) {
			clearByteSelection(true);
			return OK;
		}
		bool ordinaryNibbleNavigation =
			isOrdinaryInstrumentNibbleNavigationKey(key);
		int oldColumn = column;
		int oldNibble = input.nibble;
		auto oldKind = activeQuickHelpKind();
		if(key.raw == SDLK_LEFT || key.raw == SDLK_RIGHT)
			clearByteSelection(true);
		int oldRow = row;
		int r = super.keypress(key);
		if(row != oldRow)
			clearByteSelection(true);
		if(isDirectInstrumentByteEditKey(key))
			clearByteSelection(true);
		if(r  == WRAP) {
			stepColumn(1);
		}
		if(state.activeInstrument != row)
			UI.activateInstrument(row);
		if(pendingPointerPreview != InstrumentPointerTarget.none &&
				pendingPointerPreviewOffset >= 0)
			UI.previewCommittedInstrumentPointer(pendingPointerPreview,
				data[pendingPointerPreviewOffset]);
		if(ordinaryNibbleNavigation &&
				(column != oldColumn || input.nibble != oldNibble ||
					activeQuickHelpKind() != oldKind))
			showByteDescription();
		if(isDirectInstrumentByteEditKey(key))
			showByteDescription();
		return OK;
	}

	override protected void valueWritePending() {
		pendingPointerPreview = instrumentPointerTargetForColumn(column);
		if(pendingPointerPreview != InstrumentPointerTarget.none)
			pendingPointerPreviewOffset = byteOffset(column);
	}

	private bool isDirectInstrumentByteEditKey(Keyinfo key) {
		if(key.mods & (KMOD_CTRL | KMOD_ALT | KMOD_GUI))
			return false;
		return (key.raw >= SDLK_0 && key.raw <= SDLK_9) ||
			(key.raw >= SDLK_a && key.raw <= SDLK_f);
	}

	private bool isOrdinaryInstrumentNibbleNavigationKey(Keyinfo key) {
		if(key.mods & (KMOD_SHIFT | KMOD_CTRL | KMOD_ALT | KMOD_GUI))
			return false;
		return key.raw == SDLK_LEFT || key.raw == SDLK_RIGHT;
	}

	private void clearByteSelection(bool repaint) {
		byteDrag.clear();
		if(!byteSelection.active)
			return;
		byteSelection.clear();
		if(repaint)
			update();
	}

	private bool instrumentByteCellAt(int x, int y, out int targetInstrument,
			out int byteColumn, out int nibble) {
		targetInstrument = -1;
		byteColumn = -1;
		nibble = -1;
		if(!area.overlaps(x, y))
			return false;
		int visibleRow = y - area.y - 1;
		if(visibleRow < 0 || visibleRow >= visibleRows)
			return false;
		int rx = x - area.x;
		if(rx < 3)
			return false;
		int localColumnX = rx - 3;
		byteColumn = localColumnX / 3;
		nibble = localColumnX - byteColumn * 3;
		if(byteColumn < 0 || byteColumn >= 8 || nibble < 0 || nibble > 1)
			return false;
		targetInstrument = viewOffset + visibleRow;
		if(targetInstrument > 47)
			targetInstrument -= 48;
		return targetInstrument >= 0 && targetInstrument < 48;
	}

	bool instrumentByteClickTargetAt(int x, int y,
			out int targetInstrument) {
		int byteColumn, nibble;
		return instrumentByteCellAt(x, y, targetInstrument, byteColumn,
			nibble);
	}

	private bool instrumentByteColumnAtX(int x, out int byteColumn,
			out int nibble) {
		byteColumn = -1;
		nibble = -1;
		int rx = x - area.x;
		if(rx < 3)
			return false;
		int localColumnX = rx - 3;
		byteColumn = localColumnX / 3;
		nibble = localColumnX - byteColumn * 3;
		return byteColumn >= 0 && byteColumn < 8 && nibble >= 0 &&
			nibble <= 1;
	}

	private void placeInstrumentByteCursor(int targetInstrument,
			int byteColumn, int nibble) {
		seekRow(targetInstrument);
		setColumn(byteColumn);
		initializeInput();
		input.nibble = nibble;
		input.update();
		showByteDescription();
	}

	private void selectInstrumentByteRange(int selectedInstrument,
			int anchorColumn, int endpointColumn) {
		byteSelection.select(selectedInstrument, anchorColumn, endpointColumn);
		update();
		input.update();
		showByteDescription();
	}

	private void extendByteSelectionBy(int delta) {
		InstrumentByteSelectionState nextSelection;
		int targetColumn;
		if(!instrumentByteSelectionExtend(byteSelection, row, column, delta,
				nextSelection, targetColumn))
			return;
		int keepNibble = input.nibble;
		int anchorColumn = nextSelection.anchorColumn;
		setColumn(targetColumn);
		initializeInput();
		input.nibble = keepNibble;
		byteSelection.select(row, anchorColumn, column);
		update();
		input.update();
		showByteDescription();
	}

	private void pasteInstrument() {
		void displayNoWholeInstrumentCopied() {
			UI.statusline.displayOperationFeedback(
				"No instrument copied.");
		}

		final switch(mostRecentInstrumentClipboard) {
		case InstrumentClipboardKind.none:
			displayNoWholeInstrumentCopied();
			return;
		case InstrumentClipboardKind.byteRange:
			pasteInstrumentBytes();
			return;
		case InstrumentClipboardKind.wholeInstrument:
			break;
		}
		if(!hasInstrumentCopyBuffer) {
			displayNoWholeInstrumentCopied();
			return;
		}
		if(pasteUndo is null)
			pasteUndo = new InstrumentPasteUndo();
		com.session.insertUndo(pasteUndo, InstrumentPasteUndo.createState(row));
		foreach(i, ref buf; instrBuffer) {
			data[i * 48 + row] = buf;
		}
		song.insLabels[row][] = instrName[];
		initializeInput();
		UI.statusline.displayOperationFeedback(
			"Instrument pasted.");
	}

	private void copyInstrument() {
		InstrumentByteRange range;
		if(instrumentByteSelectionRange(byteSelection, range)) {
			copyInstrumentByteRangeData(data, range, instrumentByteBuffer,
				instrumentByteBufferCount);
			mostRecentInstrumentClipboard = InstrumentClipboardKind.byteRange;
			UI.statusline.displayOperationFeedback(format(
				"Instrument bytes copied: %d.", instrumentByteBufferCount));
			return;
		}

		foreach(i, ref buf; instrBuffer) {
			buf = data[row + i * 48];
		}
		instrName[0..32] = insName(row)[];
		hasInstrumentCopyBuffer = true;
		mostRecentInstrumentClipboard = InstrumentClipboardKind.wholeInstrument;
		UI.statusline.displayOperationFeedback(
			"Instrument copied.");
	}

	private void pasteInstrumentBytes() {
		int count = instrumentByteBufferCount;
		if(count <= 0 || count > 8) {
			UI.statusline.displayOperationFeedback(
				"No instrument bytes copied.");
			return;
		}
		int targetColumn = column;
		if(!instrumentByteRangePasteFits(targetColumn, count)) {
			UI.statusline.displayOperationFeedback(
				"Instrument byte selection does not fit.");
			return;
		}

		if(pasteUndo is null)
			pasteUndo = new InstrumentPasteUndo();
		com.session.insertUndo(pasteUndo, InstrumentPasteUndo.createState(row));
		writeInstrumentByteRangeData(data, row, targetColumn,
			instrumentByteBuffer[], count);
		initializeInput();
		clearByteSelection(true);
		UI.statusline.displayOperationFeedback(format(
			"Instrument bytes pasted: %d.", count));
	}

	private void confirmDeleteInstrument() {
		void delegate(int) dg = (int param) {
			if(param != 0) return;
			(new Purge(song)).deleteInstrument(state.activeInstrument);
			timelineSeekManager().invalidate("instrument_delete");
		};

		mainui.activateDialog(new ConfirmationDialog("Delete current instrument (no undo) (y/n)? ",
												 dg));
	}

	private string environmentValue(string name) {
		auto value = getenv(name.toStringz);
		return value is null ? "" : fromStringz(value).idup;
	}

	private string sdlPreferenceDirectory() {
		auto prefPath = SDL_GetPrefPath("CheeseCutter".toStringz,
										"CheeseCutter".toStringz);
		if(prefPath is null)
			return "";
		scope(exit) SDL_free(prefPath);
		return to!string(fromStringz(prefPath));
	}

	private string defaultInstrumentPatchDirectory() {
		version(OSX) {
			string home = environmentValue("HOME");
			if(home.length > 0) {
				return buildPath(home, "Documents", "CheeseCutter",
					"Instruments");
			}
		}

		string pref = sdlPreferenceDirectory();
		if(pref.length > 0)
			return buildPath(pref, "instruments");

		string cwd = getcwd();
		if(cwd.length > 0 && cwd != "/")
			return buildPath(cwd, "instruments");

		throw new FileException("Could not find a writable instrument save folder.");
	}

	private string initialInstrumentDirectory() {
		try {
			string dir = defaultInstrumentPatchDirectory();
			if(exists(dir) && isDir(dir))
				return dir;
		}
		catch(FileException) {
		}
		return loadDialog.directory;
	}

	private void openLoadInstrumentDialog() {
		instrumentDialogTarget = row;
		loadDialog.setDirectory(instrumentDirectory);
		mainui.activateDialog(loadDialog);
	}

	private void openSaveInstrumentDialog() {
		string validationMessage(string[] issues) {
			string msg = "Cannot save: ";
			foreach(i, issue; issues) {
				if(i > 0)
					msg ~= "; ";
				msg ~= issue;
			}
			return msg ~ ".";
		}

		instrumentDialogTarget = row;
		int targetInstrument = instrumentDialogTarget;
		auto saveIssues = song.instrumentPatchSaveIssues(targetInstrument);
		if(saveIssues.length > 0) {
			UI.statusline.displayFailure(validationMessage(saveIssues));
			return;
		}

		string fn = fnClean(std.string.stripRight
							(std.conv.to!string(song.insLabels[targetInstrument])));
		if(fn.length == 0)
			fn = "unnamed";
		saveDialog.setDirectory(instrumentDirectory);
		saveDialog.setFilename(fn ~ ".cti");
		mainui.activateDialog(saveDialog);
	}

	private void saveCallback(string selectedFilename) {
		if(selectedFilename.length == 0)
			return;
		string fn = baseName(selectedFilename);
		if(fn != saveDialog.filename || !fnIsSane(fn)) {
			UI.statusline.displayFailure("Illegal characters in filename!");
			return;
		}
		int targetInstrument = instrumentDialogTarget;
		try {
			com.session.song.savePatch(selectedFilename, targetInstrument);
			instrumentDirectory = dirName(selectedFilename);
		}
		catch(UserException e) {
			stderr.writeln(e.toString);
			UI.statusline.displayFailure(e.toString);
			return;
		}
		catch(Exception e) {
			stderr.writeln(e.toString);
			UI.statusline.displayFailure("Could not save instrument: " ~ e.msg);
			return;
		}
		UI.statusline.displayTimedOperationFeedback(format(
			"Instrument save complete: \"%s\".", selectedFilename));
	}

	private void loadCallback(string fn) {
		if(!std.file.exists(fn)) {
			UI.statusline.displayFailure(
				"File does not exist or is not accessible!");
			return;
		}
		if(fn.indexOf(".cti") == -1) {
			UI.statusline.displayFailure(
				"Not loading; possibly not an instrument def file.");
			return;
		}
		string selectedFilename = fn;
		int targetInstrument = instrumentDialogTarget;
		void delegate(int) dg = (int param) {
			if(param != 0) return;
			try {
				song.insertPatch(selectedFilename, targetInstrument);
				instrumentDirectory = dirName(selectedFilename);
				timelineSeekManager().invalidate("instrument_load");
				UI.activateInstrument(targetInstrument);
				mainui.queueTimedOperationFeedbackAfterDialogClose(format(
					"Instrument load complete: \"%s\".", selectedFilename));
			}
			catch(Exception e) {
				stderr.writeln(e.toString);
				UI.statusline.displayFailure(format(
					"Could not load instrument \"%s\": invalid or unreadable data.",
					baseName(selectedFilename)));
			}
		};
		mainui.activateDialogAfterActiveCloses(
			new ConfirmationDialog("Load instrument (no undo) (y/n)? ", dg));
	}

	string insName(int row) {
		assert(row >= 0 && row < 48);
		return format(song.insLabels[row % 48][0..32]);
	}

	override void stepColumn(int n) {
		super.stepColumn(n);
	}

	override void stepColumnWrap(int n) {
		stepColumn(-7);
		adjustView();
	}

	override void activate() {
		super.activate();
	}

	void clearVisibleByteSelection() {
		clearByteSelection(true);
	}

	override void clickedAt(int x, int y, int button) {
		int targetInstrument, byteColumn, nibble;
		if(button != 1 || !instrumentByteCellAt(x, y, targetInstrument,
				byteColumn, nibble)) {
			clearByteSelection(true);
			super.clickedAt(x, y, button);
			return;
		}

		bool shifted = (SDL_GetModState() & KMOD_SHIFT) != 0;
		int previousInstrument = row;
		int previousColumn = column;
		int anchor = byteSelection.active &&
			byteSelection.instrument == previousInstrument ?
			byteSelection.anchorColumn : previousColumn;

		if(shifted && targetInstrument == previousInstrument) {
			byteDrag.commit(targetInstrument, anchor);
			placeInstrumentByteCursor(targetInstrument, byteColumn, nibble);
			selectInstrumentByteRange(targetInstrument, anchor, byteColumn);
			return;
		}

		clearByteSelection(true);
		placeInstrumentByteCursor(targetInstrument, byteColumn, nibble);
		byteDrag.armCandidate(targetInstrument, byteColumn);
	}

	override bool mouseMotionAt(int x, int y) {
		if(!byteDrag.isActive)
			return false;
		int byteColumn, nibble;
		if(!instrumentByteColumnAtX(x, byteColumn, nibble))
			return true;
		if(!byteDrag.isCommitted)
			byteDrag.commit(byteDrag.instrument, byteDrag.anchorColumn);
		placeInstrumentByteCursor(byteDrag.instrument, byteColumn, nibble);
		selectInstrumentByteRange(byteDrag.instrument, byteDrag.anchorColumn,
			byteColumn);
		return true;
	}

	override bool mouseButtonUp(int button) {
		if(button != 1 || !byteDrag.isActive)
			return false;
		bool wasCommitted = byteDrag.isCommitted;
		byteDrag.clear();
		if(!wasCommitted)
			clearByteSelection(true);
		return true;
	}

	override void update() {
		int b = 0;
		int i, j, ofs;
		int myrow = row;
		InstrumentByteRange selectedBytes;
		bool hasSelectedBytes = instrumentByteSelectionRange(byteSelection,
			selectedBytes);

		if(myrow > 48) myrow -= 48;
		screen.fprint(area.x,area.y, "`b1I`01nstruments");
		for(i = 0; i < visibleRows; i++) {
			int p = (i + viewOffset);
			if(p > 47) p -= 48;
			assert(p >= 0 && p < 48);
			
			int c = (state.activeInstrument >= 0 && row == p) ? 15 : 12;
			screen.cprint(area.x,area.y + i + 1, c, 0, format("%02X:", p));
			for(j=0; j<8; j++) {
				ofs = p + j * 48;
				int hl = p == mark ? 13 : 5;
				int bg = 0;
				if(hasSelectedBytes && selectedBytes.instrument == p &&
						j >= selectedBytes.startColumn &&
						j <= selectedBytes.endColumn) {
					hl = 1;
					bg = 6;
				}
				screen.cprint(area.x+3+j*3,area.y + i + 1,hl,bg, format("%02X ", data[ofs]));
			}
			string label = insName(p)[0..width];
			if(paddedStringLength(label, 32) == 0) 
				screen.cprint(area.x + 27, area.y + 1 + i, 11, 0,
						  format("No description" ~ std.array.replicate(" ", width-14)));
			else
				screen.cprint(area.x + 27, area.y + 1 + i, 15, 0,
						  label);
		}
	}

	override void initializeInput() {
		super.set();
		assert(row < 48);
		int ofs = byteOffset(column);
		input.setOutput(data[ofs .. ofs+1]);
	}

	int activeColumn() {
		return column;
	}

	int activeByteValue() {
		int ofs = byteOffset(column);
		if(ofs < 0 || ofs >= data.length)
			return 0;
		return data[ofs];
	}

	private InstrumentQuickHelpKind activeQuickHelpKind() {
		return instrumentQuickHelpKind(column, input.nibble, activeByteValue());
	}

	InstrumentByteSelectionSnapshot instrumentByteSelectionSnapshot() {
		InstrumentByteSelectionSnapshot snapshot;
		snapshot.instrument = row;
		snapshot.byteColumn = column;
		snapshot.nibble = input.nibble;
		snapshot.quickHelpKind = activeQuickHelpKind();
		snapshot.quickHelpText = instrumentQuickHelpText(snapshot.quickHelpKind);
		if(input.cursor !is null) {
			snapshot.inputCursorX = input.cursor.x;
			snapshot.inputCursorY = input.cursor.y;
		}
		snapshot.selectionActive = byteSelection.active;
		if(byteSelection.active) {
			snapshot.selectionAnchor = byteSelection.anchorColumn;
			snapshot.selectionEndpoint = byteSelection.endpointColumn;
		}
		snapshot.dragCandidateActive = byteDrag.phase ==
			InstrumentByteDragPhase.candidate;
		snapshot.dragCommittedActive = byteDrag.phase ==
			InstrumentByteDragPhase.committed;
		if(byteDrag.isActive) {
			snapshot.dragInstrument = byteDrag.instrument;
			snapshot.dragAnchorColumn = byteDrag.anchorColumn;
		}
		return snapshot;
	}

	private int byteOffset(int byteColumn) {
		return byteColumn * rows + row;
	}

	void seekByte(int instrument, int byteColumn) {
		if(instrument < 0) instrument = 0;
		if(instrument > 47) instrument = 47;
		if(byteColumn < 0) byteColumn = 0;
		if(byteColumn >= columns) byteColumn = columns - 1;
		seekRow(instrument);
		setColumn(byteColumn);
		initializeInput();
		showByteDescription();
	}

	override void stepRow(int n) {
		super.stepRow(n);
		clearByteSelection(true);
		UI.activateInstrument(row);
	}

	override void showByteDescription() {
		if(song.ver > 8) {
			auto kind = instrumentQuickHelpKind(column, input.nibble,
				activeByteValue());
			string outstr = instrumentQuickHelpText(kind);
			if(outstr.length)
				UI.statusline.displayContextualSemantic(outstr,
					format("instrument:%s", cast(int)kind));
		}
	}
}

class InsTable : Window, Undoable {
	private {
		DialogString insdesc;
		InsValueTable insinput;
		enum instrumentLabelHelp =
			"Instrument name: edit label.";
	}
	Window active;
	
	this(Rectangle a) {
		super(a);
		insdesc = new DialogString(a, com.fb.mode ? 32 : 16);
		insinput = new InsValueTable(a);
		refresh();
		activateInsValueTable();
	}

	override const ContextHelp contextHelp() { 
		if(song.ver > 8)
			return genPlayerContextHelp("Instrument table", 
										song.instrumentByteDescriptions);
		return ui.help.HELPMAIN;
	}		

	override void refresh() {
		super.refresh();
		insdesc.refresh();
		insinput.refresh();
	}

	@property int row() {
		return insinput.row;
	}

	InstrumentByteSelectionSnapshot instrumentByteSelectionSnapshot() {
		return insinput.instrumentByteSelectionSnapshot();
	}

	bool instrumentSettingsFocused() {
		return active is insinput;
	}

	void openInstrumentLoadDialog() {
		insinput.openLoadInstrumentDialog();
	}

	void openInstrumentSaveDialog() {
		insinput.openSaveInstrumentDialog();
	}

	void stepRow(int n) { insinput.stepRow(n); }
	void seekRow(int r) { insinput.seekRow(r); }
	void resetSongPosition() { insinput.resetSongPosition(); }

	final void clearDocumentClipboard() {
		InsValueTable.clearDocumentClipboard();
	}

	bool activeTablePointer(out InstrumentPointerTarget target,
			out int value, out int instrument, out int byteColumn) {
		target = InstrumentPointerTarget.none;
		value = 0;
		instrument = insinput.row;
		byteColumn = insinput.activeColumn();
		if(active !is insinput)
			return false;
		target = instrumentPointerTargetForColumn(byteColumn);
		if(target == InstrumentPointerTarget.none)
			return false;
		value = insinput.activeByteValue();
		return true;
	}

	void seekByte(int instrument, int byteColumn) {
		activateInsValueTable();
		insinput.seekByte(instrument, byteColumn);
		state.activeInstrument = insinput.row;
	}

	void showCurrentContextualHelp() {
		if(active == insdesc)
			showInstrumentLabelHelp();
		else
			insinput.showByteDescription();
	}

	override void activate() {
		activateInsValueTable();
	}

	override bool allowsF6OriginReturn() {
		return active is insinput;
	}

	override void deactivate() {
		if(active == insdesc) {
			commitInstrumentLabel();
		}
		insinput.clearVisibleByteSelection();
		activateInsValueTable();
		active.update();
		state.allowInstabNavigation = true;
	}
	
	void activateDescInput() {
		insinput.clearVisibleByteSelection();
		update();
		active = insdesc;
		input = insdesc.input;
		input.setCoord(area.x + 9 * 3, 1 + area.y + insinput.cursorOffset);
		insdesc.setString(format(song.insLabels[insinput.row]));
		initializeInput();
		state.allowInstabNavigation = false;
		showInstrumentLabelHelp();
	}

	void activateInsValueTable() {
		active = insinput;
		input = insinput.input;
		active.activate();
		initializeInput();
		state.allowInstabNavigation = true;
	}

	override int keypress(Keyinfo key) {
		if(key.mods & KMOD_ALT) {
			return OK;
		}
		if(key.unicode == SDLK_RETURN || key.unicode == SDLK_TAB) {
			if(active == insinput) {
				activateDescInput();
			}
			else {
				commitInstrumentLabel();
				activateInsValueTable();
			}
			return OK;
		}
		int r;
		r = active.keypress(key);
		return r;
	}

	override void update() {
		active.update();
		if(active == insdesc)
			showInstrumentLabelHelp();
	}

	void initializeInput() {
		if(active == insinput) insinput.initializeInput();
	}
	alias initializeInput set;

	override void clickedAt(int x, int y, int button) {
		if(active == insdesc)
			commitInstrumentLabel();
		int clickedInstrument;
		bool byteCellClick = insinput.instrumentByteClickTargetAt(x, y,
			clickedInstrument);
		if(byteCellClick && clickedInstrument != state.activeInstrument)
			UI.activateInstrument(clickedInstrument);
		insinput.clickedAt(x,y,button);
		if(!byteCellClick && state.activeInstrument != insinput.row)
			UI.activateInstrument(insinput.row);
		if((x - area.x) > 3 + 8 * 3)
			activateDescInput();
	}

	override bool mouseMotionAt(int x, int y) {
		if(active is insinput)
			return insinput.mouseMotionAt(x, y);
		return false;
	}

	override bool mouseButtonUp(int button) {
		if(active is insinput)
			return insinput.mouseButtonUp(button);
		return false;
	}

protected:

	override final UndoValue createRedoState(UndoValue value) {
		return createInstrumentLabelState();
	}

	override final void undo(UndoValue v) {
		restoreInstrumentLabelState(v);
	}

private:

	void showInstrumentLabelHelp() {
		if(!state.displayHelp || UI.statusline is null)
			return;
		if(UI.statusline.counter != 0 &&
		   UI.statusline.message == instrumentLabelHelp)
			return;
		UI.statusline.displayContextual(instrumentLabelHelp);
	}

	void commitInstrumentLabel() {
		string s = insdesc.toString(true);
		int len = cast(int)s.length;
		if(song.insLabels[insinput.row][0..len] == s)
			return;

		com.session.insertUndo(this, createInstrumentLabelState());
		song.insLabels[insinput.row][0..len] = s;
	}

	UndoValue createInstrumentLabelState() {
		UndoValue v;
		foreach(ref label; song.insLabels) {
			v.tableData ~= (cast(ubyte[])label[]).dup;
		}
		return v;
	}

	void restoreInstrumentLabelState(UndoValue v) {
		if(v.tableData.length != song.insLabels.length)
			return;

		foreach(i, bytes; v.tableData) {
			if(bytes.length != song.insLabels[i].length)
				return;
		}
		foreach(i, bytes; v.tableData) {
			song.insLabels[i][] = cast(char[])bytes[];
		}
		insdesc.setString(format(song.insLabels[insinput.row]));
		active.update();
	}
}


class CmdTable : HexTable {
	alias row position;
	
	this(Rectangle a) {
		super(a, song.superTable, 1, 64);
		input = new InputSpecial(song.superTable);
		(cast(InputValue)input).setValueChangedCallback(&valueChangedCallback);
	}

	override void refresh() {
		data = song.superTable;
		super.refresh();
	}

	override void activate() {
		super.activate();
		showByteDescription();
	}

	override bool allowsF6OriginReturn() { return true; }

	override void update() {
		int i;
		if(state.shortTitles)
			screen.fprint(area.x,area.y, "`01Co`b1m`01mand");
		else
			screen.fprint(area.x,area.y,
				"`01Cmd (" ~ TABLE_JUMP_MOD_LABEL ~ "-M)");
		for(i = 0; i < visibleRows; i++) {
			int ofs = (viewOffset + i) & 0x3f;
			screen.fprint(area.x,area.y + i + 1, 
						  format("`0c%02X:`0d%01X-`05%02X %02X", ofs,
								 song.superTable[ofs] & 15,
								 song.superTable[ofs+64],
								 song.superTable[ofs+128]));
		}
	}

	override int keypress(Keyinfo key) {
		if(key.mods & KMOD_ALT) {
			return OK;
		}
		switch(key.raw) {
		case SDLK_LEFT:
			input.step(-1);
			break;
		case SDLK_RIGHT:
			input.step(1);
			break;
		case SDLK_DOWN:
			stepRow(1);
			break;
		case SDLK_UP:
			stepRow(-1);
			break;
		case SDLK_PAGEUP:
			stepRow(-(PAGESTEP/2));
			break;
		case SDLK_PAGEDOWN:
			stepRow((PAGESTEP/2));
			break;
		case SDLK_HOME:
			seekRow(0);
			break;
		case SDLK_END:
			seekTableEnd();
			break;
		default:
			break;
		}
		int r = input.keypress(key);
		song.superTable[position] = input.inarray[0];
		song.superTable[position+64] = cast(ubyte)input.toIntRange(1, 3);
		song.superTable[position+128] = cast(ubyte)input.toIntRange(3, 5);
		if(r == WRAP) {
			stepRow(1);
		}
		showByteDescription();
		return OK;
	}

	override void initializeInput() {
		super.initializeInput();
		input.inarray[0] = song.superTable[position];
		input.inarray[1] = song.superTable[position+64] >> 4;
		input.inarray[2] = song.superTable[position+64] & 15;
		input.inarray[3] = song.superTable[position+128] >> 4;
		input.inarray[4] = song.superTable[position+128] & 15;
	}

	override void clickedAt(int x, int y, int button) {
		int displayOffset = x - (area.x + 3);
		setCursorOffset(y - area.y - 1);
		setColumn(0);
		input.nibble = commandNibbleForDisplayOffset(displayOffset);
		initializeInput();
		showByteDescription();
	}

	override void seekTableEnd() {
		for(int i = 63; i >= 1; i--) {
			if(data[i-1] > 0) {
				seekRow(i);
				return;
			}
		}
	}

	override ContextHelp contextHelp() { 
		if(song.ver > 9)
			return genPlayerContextHelp("Command table", 
										song.cmdDescriptions);
		return ui.help.HELPMAIN;
	}		

	override void showByteDescription() {
		if(!state.displayHelp || UI.statusline is null)
			return;
		UI.statusline.displayContextual(commandHelpText());
	}

	private string commandHelpText() {
		int cmd = song.superTable[position] & 15;
		if(input.nibble == 0)
			return "Command x selects effect type.\n" ~
				"0 up, 1 down, 2 hi-fi vib, 3 detune, 4 ADSR.\n" ~
				"5 lo-fi vib, 6 wave, 7 porta, 8 stop.";
		if(input.nibble < 3)
			return commandFirstParameterHelp(cmd);
		return commandSecondParameterHelp(cmd);
	}

	private static int commandNibbleForDisplayOffset(int displayOffset) {
		if(displayOffset <= 1)
			return 0;
		if(displayOffset == 2)
			return 1;
		if(displayOffset == 3)
			return 2;
		if(displayOffset <= 5)
			return 3;
		return 4;
	}

	private string commandFirstParameterHelp(int cmd) {
		switch(cmd) {
		case 0:
			return "Slide up yy: high byte of signed 16-bit slide speed.";
		case 1:
			return "Slide down yy: high byte of signed 16-bit slide speed.";
		case 2:
			return "Hi-fi vibrato yy: low nibble feel.\n" ~
				"High nibble unused.";
		case 3:
			return "Detune yy: high byte of signed 16-bit detune.";
		case 4:
			return "ADSR yy: attack/decay.";
		case 5:
			return "Lo-fi vibrato yy: speed.";
		case 6:
			return "Set wave yy: unused; zz sets waveform/control.";
		case 7:
			return "Portamento yy: low nibble = high speed digit.\n" ~
				"High nibble unused.";
		case 8:
			return "Stop yy: unused.";
		default:
			return format("Command %X yy: parameter byte 1.", cmd);
		}
	}

	private string commandSecondParameterHelp(int cmd) {
		switch(cmd) {
		case 0:
			return "Slide up zz: low byte of signed 16-bit slide speed.";
		case 1:
			return "Slide down zz: low byte of signed 16-bit slide speed.";
		case 2:
			return "Hi-fi vibrato zz: high nibble speed.\n" ~
				"Low nibble depth divider.";
		case 3:
			return "Detune zz: low byte of signed 16-bit detune.";
		case 4:
			return "ADSR zz: sustain/release.";
		case 5:
			return "Lo-fi vibrato zz: depth.";
		case 6:
			return "Set wave zz: SID waveform/control register.";
		case 7:
			return "Portamento zz: low byte of portamento speed.";
		case 8:
			return "Stop zz: unused.";
		default:
			return format("Command %X zz: parameter byte 2.", cmd);
		}
	}

}

class ChordTable : HexTable {
	this(Rectangle a) {
		super(a, song.chordTable, 1, 128);
	}

	override void refresh() {
		super.refresh();
		data = song.chordTable;
	}

	override void activate() {
		super.activate();
		showByteDescription();
	}

	override bool allowsF6OriginReturn() { return true; }

	override void seekTableEnd() {
		for(int i = 127; i >= 1; i--) {
			if(data[i-1] > 0) {
				seekRow(i);
				return;
			}
		}
	}

	override void update() {
		int i;
		if(state.shortTitles)
			screen.fprint(area.x,area.y, "`01Chor`b1d`01");
		else
			screen.fprint(area.x,area.y, "`01Chd (A-D)");

		for(i = 0; i < visibleRows; i++) {
			int row = (i + viewOffset) & 0x7f;
			string col = "`05";
			if(data[row] >= 0x80) col = "`0d";
			screen.fprint(area.x, area.y + i + 1,
						  format("`0c%02X:%s%02X", row, col, data[row]));
		}

		for(i = 0; i < visibleRows; i++) {
			screen.fprint(area.x + 5, area.y + i + 1, "  ");
		}		

		int[] chordno = getHighestChordIndex();
		
		{
			int ct;
			for(i = 0; i < viewOffset; i++) {
				if(data[i] >= 0x80) ct++;
			}
			bool doPrint = true;
			int row = viewOffset & 127; 
			for(i = 0; i < visibleRows; i++,row++) {
				if(row > 127) {
					row -= 128;
					ct = 0;
					doPrint = true;
				}

				if(doPrint) {
					screen.fprint(area.x + 5, area.y + i + 1, format("`0c%X ", ct));
					doPrint = false;
				}

				if(data[row] >= 0x80) {
					if(ct >= chordno[0]) break;
					ct++;
					doPrint = true;
					if(row >= chordno[1]) {
						doPrint = false;
					}
				}
			}
		}
	}

	override void initializeInput() {
		super.initializeInput();
		input.setOutput(data[row .. row + 1]);
		song.generateChordIndex();
	}

	override ContextHelp contextHelp() {
		return ui.help.HELPCHORDTABLE;
	}

	override int keypress(Keyinfo key) {
		bool handled = executeGeneratedTableRowStructureAction(key);
		if(handled) {
			showByteDescription();
			return OK;
		}
		int r = super.keypress(key);
		showByteDescription();
		return r;
	}

	override void showByteDescription() {
		if(!state.displayHelp || UI.statusline is null)
			return;
		string help = currentByteDescription();
		if(UI.statusline.counter != 0 &&
		   UI.statusline.message == help)
			return;
		UI.statusline.displayContextual(help);
	}

	private string currentByteDescription() {
		return ui.help.chordTableQuickHelp(cast(ubyte)song.speed, data, row);
	}

	override void insertRow() {
		saveState(false);
		ubyte[] tmp = data[row .. $-1].dup;
		foreach(i, c; tmp) {
			int next = c + 1;
			if(/+row > 0  && +/ c >= (0x80 + row) && next < 0x100) {
				tmp[i] = cast(ubyte)next;
			}
		}
		data[row+1 .. $] = tmp;
		data[row] = 0;
		initializeInput();
	}

	override void deleteRow() {
		saveState(false);		
		ubyte[] tmp = data[row + 1 .. $].dup;
		foreach(i, c; tmp) {
			if(c > (0x80 + row) && --c >= 0x80)
				tmp[i] = c;
		}
		data[row .. $ - 1] = tmp;
		data[$-1] = 0;
		initializeInput();
	}

private:

	// returns number of chords and the offset of the last chord
	int[] getHighestChordIndex() {
		foreach_reverse(counter, idx; song.chordIndexTable) {
			if(idx == 0) continue;
			return cast(int[])[counter, idx];
		}
		return [-1, -1];
	}
}

class WaveTable : HexTable {
	this(Rectangle a) {
		super(a, song.waveTable, 2, 256);
	}

	override protected ProgramTableRowKind programTableRowKind() {
		return ProgramTableRowKind.wave;
	}

	override protected void readProgramRowBytes(int sourceRow, ubyte[] dest) {
		dest[0] = data[sourceRow];
		dest[1] = data[sourceRow + 256];
	}

	override protected void writeProgramRowBytes(int targetRow,
			const(ubyte)[] src) {
		data[targetRow] = src[0];
		data[targetRow + 256] = src[1];
	}

	override void refresh() {
		super.refresh();
		data = song.waveTable;
	}

	override void seekTableEnd() {
		for(int i = 255; i >= 1; i--) {
			if(data[i-1] > 0) {
				seekRow(i);
				return;
			}
		}
	}

	void seekCurWave() {
		seekRow(song.instrumentTable[state.activeInstrument +
			INSTRUMENT_WAVE_POINTER_COLUMN * 48]);
	}

	void seekProgramRow(int r) {
		if(r < 0) r = 0;
		if(r > 255) r = 255;
		seekRow(r);
		setColumn(0);
		initializeInput();
		showByteDescription();
	}

	override void deleteRow() {
		saveState(true);
		song.tWave.deleteRow(song, row);
		refresh();
		set();
	}

	override void insertRow() {
		saveState(true);
		song.tWave.insertRow(song, row);
		refresh();
		set();
	}

	override int keypress(Keyinfo key) {
		bool handled = executeGeneratedTableRowStructureAction(key);
		if(handled)
			return OK;
		KeyboardActionId actionId;
		if(resolveWaveTableCommandKeyboardAction(key, actionId)) {
			seekCurWave();
			return OK;
		}
		if((key.mods & KMOD_SHIFT) == 0 && (key.mods & KMOD_CTRL) != 0) {
			switch(key.raw) {
			default: 
				break;
			}
		}
		else switch(key.raw) {
			case '.':
				data[column ? (256 + row) : row] = 0;
				stepColumnWrap(1);
				showByteDescription();
				return OK;
			default:
				break;
			}
		auto oldKind = activeWaveQuickHelpKind();
		int r = super.keypress(key);
		if(activeWaveQuickHelpKind() != oldKind)
			showByteDescription();
		return r;
	}

		override void update() {
			int i;
			int t1, t2;
			if(state.shortTitles)
				screen.fprint(area.x,area.y, "`b1W`01ave");
		else
			screen.fprint(area.x,area.y, "`01Wave (A-W)");
		for(i = 0; i < visibleRows; i++) {
			int row = (i + viewOffset) & 255;
				t1 = data[row];
				t2 = data[row+256];
				int col = (t1 == 0x7e || t1 == 0x7f) ?  0x0d : 0x05;
				if(highlightRow(row)) col = 0x0d;
				screen.fprint(area.x,area.y + i + 1, format("`0c%02X:`%02x%02X %02X", 
															row, col, t1, t2));
				if(programRowIsSelected(row))
					drawProgramRowSelectionText(area.y + i + 1,
						format("%02X %02X", t1, t2));

			}
		}

		override bool highlightRow(int row) {
			return highlightActiveProgram(
				song.instrumentTable[state.activeInstrument + 7 * 48], row);
		}

	override void initializeInput() {
		int offset = column ? (256 + row) : row;
		(cast(InputByte)input).setOutput(data[offset..offset+1]);
		super.set();
	}

	override void stepColumnWrap(int n) {
		stepRow(1);
		adjustView();
	}


	override void showByteDescription() {
		if(song.ver > 9) {
			auto kind = activeWaveQuickHelpKind();
			string outstr = waveQuickHelpText(kind);
			if(outstr.length)
				UI.statusline.displayContextualSemantic(outstr,
					format("wave:%s", cast(int)kind));
		}
	}

	WaveQuickHelpKind activeWaveQuickHelpKind() {
		return waveQuickHelpKind(column, input.nibble, data[row],
			data[row + 256]);
	}

		override ContextHelp contextHelp() { 
			if(song.ver > 9)
				return genPlayerContextHelp("Wave table", 
											song.waveDescriptions);
			return ui.help.HELPMAIN;
			
		}

	private:

		bool highlightActiveProgram(int startFrom, int currentRow) {
			bool[256] visitedRows;
			for(int row = startFrom; row >= 0 && row < 256;) {
				if(visitedRows[row])
					break;
				visitedRows[row] = true;
				if(row == currentRow)
					return true;
				if(data[row] == 0x7e)
					break;
				if(data[row] == 0x7f)
					row = data[row + 256];
				else
					row++;
			}
			return false;
		}
	}

class SweepTable : HexTable { 
	this(Rectangle a, ubyte[] d) {
		super(a, d, 4, 64);
	}

	override int keypress(Keyinfo key) {
		bool handled = executeGeneratedTableRowStructureAction(key);
		if(handled) {
			refresh();
			set();
			return OK;
		}
		return super.keypress(key);
	}
	
	override void update() {
		for(int i = 0; i < visibleRows; i++) {
			int curRow = (i + viewOffset) & 63;
			int p = curRow * 4;
			string col = "`05", col2 = "`05";
			if(data[p+3] > 0) col = "`0d";
			if(data[p+3] > 0x3f && data[p+3] != 0x7f) col = "`0a";
			if(highlightRow(curRow)) { col2 = col = "`0d"; }
			screen.fprint(area.x,area.y + i + 1, 
						  format("`0c%02X:%s%02X %02X %02X %s%02X", 
								 curRow, col2,
								 data[p], data[p+1], data[p+2], col, data[p+3]));
			if(programRowIsSelected(curRow))
				drawProgramRowSelectionText(area.y + i + 1,
					format("%02X %02X %02X %02X",
						data[p], data[p+1], data[p+2], data[p+3]));
		}
	}

	override void initializeInput() {
		InputByte i = cast(InputByte)input;
		int ofs = row * 4 + column;
		i.setOutput(data[ofs..ofs+1]);
		super.initializeInput();
		
	}

	void seekProgramRow(int r) {
		if(r < 0) r = 0;
		if(r > 63) r = 63;
		seekRow(r);
		setColumn(0);
		initializeInput();
		showByteDescription();
	}

	override void seekTableEnd() {
		for(int i = 63; i >= 0; i--) {
			ubyte[] arr = data[i * 3 .. i * 3 + 3];
			bool flag;
			foreach(a; arr) {
				if(a) {
					int row = i + 1;
					if(row > 63) row = 63;
					seekRow(row);
					return;
				}
			}
		}
	}

	protected bool highlightActiveFor(int startFrom, int currentRow) {
		if(startFrom > 0x3f || startFrom == 0) return false;

		if(startFrom == currentRow)
			return true;
		
		bool[0x40] visited;
		for(int row = startFrom; row < 0x40;) {
			if(visited[row]) break;
			visited[row] = true;
			if(row == currentRow) return true;
			int jumpValue = data[row * 4 + 3];
			if(jumpValue > 0x3f && jumpValue != 0x7f) // if illegal, break
				break;
			if(jumpValue == 0x7f)
				break; // if loops or ends, break
			else if(jumpValue == 0) 
				row++;
			else row = jumpValue;
		}
		return false;
	}
}

class PulseTable : SweepTable {
	this(Rectangle a) {
		super(a, song.pulseTable);
	}

	override protected ProgramTableRowKind programTableRowKind() {
		return ProgramTableRowKind.pulse;
	}

	override void refresh() {
		super.refresh();
		data = song.pulseTable;
	}

	override bool allowsF6OriginReturn() { return true; }

	void seekCurPulse() {
		seekProgramRow(song.instrumentTable[state.activeInstrument +
			INSTRUMENT_PULSE_POINTER_COLUMN * 48]);
	}

	override void update() {
		if(state.shortTitles)
			screen.fprint(area.x, area.y, "`b1P`01ulse");
		else
			screen.fprint(area.x, area.y,
				"`01Pulse (" ~ TABLE_JUMP_MOD_LABEL ~ "-P)");
		super.update();
	}

		override void showByteDescription() {
			if(song.ver > 8) {
				auto kind = activePulseQuickHelpKind();
				string outstr = pulseQuickHelpText(kind);
				if(outstr.length)
					UI.statusline.displayContextualSemantic(outstr,
						format("pulse:%s", cast(int)kind));
			}
		}

		PulseQuickHelpKind activePulseQuickHelpKind() {
			return pulseQuickHelpKind(column);
		}

		override ContextHelp contextHelp() { 
			if(song.ver > 8)
			return genPlayerContextHelp("Pulse table", 
										song.pulseDescriptions);
		return ui.help.HELPMAIN;
	}

	override void deleteRow() {
		saveState(true);
		ct.purge.pulseDeleteRow(song, row);
	}

	override void insertRow() {
		saveState(true);
		ct.purge.pulseInsertRow(song, row);
	}

	override bool highlightRow(int row) {
		return highlightActiveFor(song.instrumentTable[state.activeInstrument + 5 * 48], row);
	}
}

class FilterTable : SweepTable {
	this(Rectangle a) {
		super(a, song.filterTable);
		refresh();
	}

	override protected ProgramTableRowKind programTableRowKind() {
		return ProgramTableRowKind.filter;
	}

	override void refresh() {
		super.refresh();
		data = song.filterTable;
	}

	override bool allowsF6OriginReturn() { return true; }

	void seekCurFilter() {
		seekProgramRow(song.instrumentTable[state.activeInstrument +
			INSTRUMENT_FILTER_POINTER_COLUMN * 48]);
	}

	override void update() {
		if(state.shortTitles)
			screen.fprint(area.x, area.y, "`b1F`01ilter");
		else 
			screen.fprint(area.x, area.y,
				"`01Filter (" ~ TABLE_JUMP_MOD_LABEL ~ "-F)");
		super.update();
	}

		override ContextHelp contextHelp() { 
			if(song.ver > 8)
				return genPlayerContextHelp("Filter table", 
											song.filterDescriptions);
			return ui.help.HELPMAIN;
		}		
	
		override int keypress(Keyinfo key) {
			auto oldKind = activeFilterQuickHelpKind();
			int r = super.keypress(key);
			if(activeFilterQuickHelpKind() != oldKind)
				showByteDescription();
			return r;
		}

		override void showByteDescription() {
			if(song.ver > 8) {
				auto kind = activeFilterQuickHelpKind();
				string outstr = filterQuickHelpText(kind);
				if(outstr.length)
					UI.statusline.displayContextualSemantic(outstr,
						format("filter:%s", cast(int)kind));
			}
		}

		FilterQuickHelpKind activeFilterQuickHelpKind() {
			int ofs = row * 4;
			ubyte first = data[ofs];
			return filterQuickHelpKind(column, input.nibble, first);
		}

		override void deleteRow() {
		saveState(true);
		ct.purge.filterDeleteRow(song, row);
	}

	override void insertRow() {
		saveState(true);
		ct.purge.filterInsertRow(song, row);
	}

	override bool highlightRow(int row) {
		return highlightActiveFor(song.instrumentTable[state.activeInstrument + 4 * 48], row);
	}
	
}
