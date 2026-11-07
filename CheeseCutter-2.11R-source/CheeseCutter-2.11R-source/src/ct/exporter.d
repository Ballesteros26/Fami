/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module ct.exporter;

import com.util;
import ct.base;
import ct.build;
import ct.purge;
import std.string;

enum ExportFormat { PRG, SID }

struct ExportOptions {
	int relocAddress = 0x1000;
	int zpAddress = 0xfb;
	int defaultTune = 1;
	int singleSubtune = 0;
	bool skipPurge = false;
	bool verbose = false;
}

class ValidateException : Exception {
	this(string msg) {
		super(msg);
	}

	override string toString() {
		return "Validation error: " ~ msg;
	}
}

private void validateOptions(ExportOptions options) {
	if(options.relocAddress < 0x200 || options.relocAddress > 0xf900)
		throw new UserException("Relocation address must be in range $0200-$f900.");
	if(options.zpAddress != 0 &&
			(options.zpAddress < 2 || options.zpAddress > 0xfe))
		throw new UserException("Zero-page address must be in range $02-$fe.");
	if(options.singleSubtune < 0 || options.singleSubtune > SUBTUNE_MAX)
		throw new UserException(format("Single subtune must be 0 or in range 1-%d.", SUBTUNE_MAX));
	if(options.defaultTune < 1 || options.defaultTune > SUBTUNE_MAX)
		throw new UserException(format("Default subtune must be in range 1-%d.", SUBTUNE_MAX));
}

void validateSong(Song song) {
	for(int i = 0; i < song.numInstr; i++) {
		int waveptr = song.wavetablePointer(i);
		int pulseptr = song.pulsetablePointer(i);
		int filtptr = song.filtertablePointer(i);
		if(!song.tWave.isValid(waveptr)) {
			throw new ValidateException(format("instrument %d is not valid (wavetable does not wrap).", i));
		}

		if(!song.tPulse.isValid(pulseptr)) {
			throw new ValidateException(format("pulse %d is not valid.", pulseptr));
		}

		if(!song.tFilter.isValid(filtptr)) {
			throw new ValidateException(format("filter %d is not valid.", filtptr));
		}

		song.seqIterator((int seqno, Sequence s, Element e) {
			if(e.cmd.value >= 0x80 && e.cmd.value <= 0x9f) {
				int idx = song.chordIndexTable[e.cmd.value & 0x1f];
				for(int i = idx; i < 128; i++) {
					if(song.chordTable[i] >= 0x80) return;
				}
				throw new ValidateException(format("sequence $%02x has an 8x command pointing to a chord program without an end marker.", seqno));
			}
		});
	}
}

private Song prepareExportSong(Song source, ExportOptions options) {
	Song prepared = new Song();
	prepared.openData(source.fileData(), "<export>");

	if(options.singleSubtune >= 1) {
		int selected = options.singleSubtune - 1;
		for(int i = 0; i < SUBTUNE_MAX; i++) {
			if(i != selected)
				prepared.subtunes.clear(i);
		}
		prepared.subtunes.swap(0, selected);
	}

	if(!options.skipPurge)
		(new Purge(prepared, options.verbose)).purgeAll();

	validateSong(prepared);
	return prepared;
}

ubyte[] exportSong(Song source, ExportFormat exportFormat,
		ExportOptions options) {
	validateOptions(options);
	Song prepared = prepareExportSong(source, options);
	int defaultTune = options.singleSubtune >= 1 ? 1 : options.defaultTune;
	return doBuild(prepared, options.relocAddress, options.zpAddress,
		exportFormat == ExportFormat.SID, defaultTune, options.verbose);
}
