/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module audio.callback;
import derelict.sdl2.sdl;
import audio.player;
import com.session;
import com.cpu;
import ct.base;
static import audio.timer, audio.audio;

__gshared private int frameCallCounter, totalFrameCallCounter; // for multispeed
__gshared private Exception playbackStatus = null;
__gshared int cyclesPerFrame;
__gshared int linesPerFrame, maxCycles, maxLines, maxCycleFrame;
__gshared auto avgsPerFrame = new int[](20);

struct CallbackSnapshot {
	int frameCallCounter, totalFrameCallCounter;
	int cyclesPerFrame;
	int maxCycles;
}

CallbackSnapshot snapshot() {
	return CallbackSnapshot(frameCallCounter, totalFrameCallCounter,
		cyclesPerFrame, maxCycles);
}

void restore(CallbackSnapshot state) {
	frameCallCounter = state.frameCallCounter;
	totalFrameCallCounter = state.totalFrameCallCounter;
	cyclesPerFrame = state.cyclesPerFrame;
	maxCycles = state.maxCycles;
}

Exception getException() {
	Exception ex = playbackStatus;
	playbackStatus = null;
	return ex;
}

void reset() {
	maxCycles = 0;
	cyclesPerFrame = 0;
	frameCallCounter = 0;
	totalFrameCallCounter = 0;
}
// called each frame from soundbuffer callback
extern(C) __gshared void audio_frame() nothrow {
	switch(audio.player.getPlaystatus()) {
	case Status.Play:
		audio.timer.tick();
		cpuCall(frameCallCounter > 0 ? 0x1006 : 0x1003, false);
		break;
	case Status.Keyjam:
		address call = 0x100c;
		song.cpu.regs.x = 0;
		if(song.ver > 7) {
			call = song.offsets[Offsets.Submplayplay];
		}
		cpuCall(call,false);
		break;
	default:
		return;
	}

	frameCallCounter++;
	totalFrameCallCounter++;
	if(frameCallCounter >= audio.audio.multiplier) {
		frameCallCounter = 0;
		frameDone();
	}

	syncSidRegisters();
}

void syncSidRegisters() nothrow {
	for(int i = 0; i < 0x19; i++) {
		sidreg[i] = song.sidbuf[i];
	}
}

private void frameDone() nothrow {
	static int[5] avgs;
	int totalCycles;
	auto playerFrameCounter = song.data[song.offsets[2]];
	static int[][] _avgsPerFrame = new int[][](20,5);

	
	if(cyclesPerFrame > maxCycles) {
		maxCycles = cyclesPerFrame;
		maxCycleFrame = song.data[song.offsets[2]];
	}


	foreach(idx, ref avg; avgs) {
		if(idx == avgs.length - 1) {
			avg = cyclesPerFrame;
		}
		else avg = avgs[idx+1];
		totalCycles += avg;
	}


	int[] _avgPerFrame = _avgsPerFrame[playerFrameCounter];
	import std.stdio;
	_avgPerFrame[0 .. $-1] = _avgPerFrame[1 .. $].dup;
	_avgPerFrame[$-1] = cyclesPerFrame;

	int avg;
	foreach(i; 0 .. 5) {
		avg += _avgPerFrame[i];
	}
	avg /= 5;
	avgsPerFrame[playerFrameCounter] = avg / 10;
	

	import std.math : ceil;
	maxLines = cast(int)ceil(maxCycles / 63.0);
	
	cyclesPerFrame = 0;
	linesPerFrame = cast(int)(totalCycles / avgs.length / 63);

	audio.timer.tickFullFrame();
}

void cpuCall(ushort pc, bool lockAudio) nothrow {
	if(lockAudio) SDL_LockAudio();
	try {
		int i = song.cpu.execute(pc, false);
		if(muted[0]) song.sidbuf[0..7] = 0;
		if(muted[1]) song.sidbuf[7..14] = 0;
		if(muted[2]) song.sidbuf[14..21] = 0;
		cyclesPerFrame += i; 
	}
	catch(Exception e) {
		playbackStatus = e;
		stop(); // < TODO: player.d should check if playback is in error state and stop by itself
	}
	finally {
		if(lockAudio) SDL_UnlockAudio();
	}
}

extern(C) {
	__gshared extern char[0x19] sidreg;
}
