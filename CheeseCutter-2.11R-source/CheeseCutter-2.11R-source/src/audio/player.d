/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module audio.player;
import com.cpu;
import com.session;
private import ct.base;
import audio.timer;
import audio.callback;
import audio.audio;
import audio.resid.filter;
import seq.sequencer;
import ui.ui;
import derelict.sdl2.sdl;
import std.stdio;
import std.datetime.stopwatch : StopWatch;

enum Status { Stop, Play, Keyjam };
shared private int playstatus;
shared int[3] muted;
int usefp = 1, sidtype, interpolate = 1, badline, ntsc;
__gshared Filterparams curfp;

struct VoiceMuteLockTestSnapshot {
	int lockEntries;
	int unlocks;
	int depth;
	int maxDepth;
	int nestedEntries;
	int ownerCalls;
	int ownerCallsWithoutLock;
}

private __gshared bool voiceMuteLockTestEnabled;
private __gshared VoiceMuteLockTestSnapshot voiceMuteLockTestState;
int curfp6581 = 0, curfp8580 = 0;

extern(C) {
	void sid_keyjam_f6_arm_render_readiness(int generation,
		int controlOffset) nothrow;
	void sid_keyjam_f6_cancel_render_readiness() nothrow;
	int sid_keyjam_f6_gate_on_samples(int generation) nothrow;
}

enum KEYJAM_F6_RELEASE_READY_SAMPLES = 128;
enum KEYJAM_F6_RELEASE_FAILSAFE_FRAMES = 4;

private struct KeyjamF6AuditionState {
	int generation;
	int voice;
	bool preparedNoteOn;
	bool pendingRelease;
	int pendingReleaseGeneration;
	bool keyupSeen;
	bool releaseSent;
	long failsafeDeadline;
}

__gshared private KeyjamF6AuditionState keyjamF6Audition;
__gshared private int keyjamF6NextGeneration;

private long keyjamF6Counter() nothrow {
	return cast(long)SDL_GetPerformanceCounter();
}

private long keyjamF6Frequency() nothrow {
	auto frequency = cast(long)SDL_GetPerformanceFrequency();
	return frequency > 0 ? frequency : 1;
}

private long keyjamF6FailsafeTicks() nothrow {
	long framesPerSecond = ntsc ? 60 : 50;
	return keyjamF6Frequency() * KEYJAM_F6_RELEASE_FAILSAFE_FRAMES /
		framesPerSecond;
}

private int keyjamF6ControlOffset(int voice) nothrow {
	if(voice < 0)
		voice = 0;
	if(voice > 2)
		voice = 2;
	return voice * 7 + 4;
}

private void cancelF6AuditionState() nothrow {
	keyjamF6Audition = KeyjamF6AuditionState();
	sid_keyjam_f6_cancel_render_readiness();
}

void cancelF6AuditionRelease() nothrow {
	cancelF6AuditionState();
}

void cancelF6AuditionForInputLoss() nothrow {
	if(playstatus == Status.Keyjam) {
		stop();
		return;
	}
	cancelF6AuditionState();
}

bool keyjamF6ReleasePolicyShouldRelease(bool pendingRelease,
		bool releaseSent, int pendingReleaseGeneration,
		int currentGeneration, int gateOnSamples, long now,
		long failsafeDeadline) pure nothrow {
	if(!pendingRelease || releaseSent ||
			pendingReleaseGeneration <= 0 ||
			pendingReleaseGeneration != currentGeneration)
		return false;
	if(gateOnSamples >= KEYJAM_F6_RELEASE_READY_SAMPLES)
		return true;
	return failsafeDeadline > 0 && now >= failsafeDeadline;
}

void prepareF6AuditionNoteOn(int voice) nothrow {
	if(voice < 0)
		voice = 0;
	if(voice > 2)
		voice = 2;
	keyjamF6Audition.preparedNoteOn = true;
	keyjamF6Audition.voice = voice;
}

void cancelPreparedF6AuditionNoteOn() nothrow {
	keyjamF6Audition.preparedNoteOn = false;
}

int currentF6AuditionGeneration() nothrow {
	return keyjamF6Audition.generation;
}

private void startPreparedF6AuditionLocked(int voice) nothrow {
	int generation = ++keyjamF6NextGeneration;
	keyjamF6Audition.generation = generation;
	keyjamF6Audition.voice = voice;
	keyjamF6Audition.pendingRelease = false;
	keyjamF6Audition.pendingReleaseGeneration = 0;
	keyjamF6Audition.keyupSeen = false;
	keyjamF6Audition.releaseSent = false;
	keyjamF6Audition.failsafeDeadline = 0;
	keyjamF6Audition.preparedNoteOn = false;
	sid_keyjam_f6_arm_render_readiness(generation,
		keyjamF6ControlOffset(voice));
}

void requestF6AuditionRelease(int generation) nothrow {
	if(generation <= 0 || generation != keyjamF6Audition.generation ||
			keyjamF6Audition.releaseSent)
		return;
	keyjamF6Audition.pendingRelease = true;
	keyjamF6Audition.pendingReleaseGeneration = generation;
	keyjamF6Audition.keyupSeen = true;
	keyjamF6Audition.failsafeDeadline =
		keyjamF6Counter() + keyjamF6FailsafeTicks();
}

private bool f6AuditionReleaseReady(long now) nothrow {
	int samples = sid_keyjam_f6_gate_on_samples(
		keyjamF6Audition.pendingReleaseGeneration);
	return keyjamF6ReleasePolicyShouldRelease(
		keyjamF6Audition.pendingRelease,
		keyjamF6Audition.releaseSent,
		keyjamF6Audition.pendingReleaseGeneration,
		keyjamF6Audition.generation, samples, now,
		keyjamF6Audition.failsafeDeadline);
}

void serviceF6AuditionRelease() {
	long now = keyjamF6Counter();
	if(!f6AuditionReleaseReady(now))
		return;
	keyjamF6Audition.releaseSent = true;
	keyjamF6Audition.pendingRelease = false;
	auto release = Element([0x00,
		cast(ubyte)(0xc0 + state.activeInstrument), 1]);
	playNoteForVoice(release, keyjamF6Audition.voice);
	cancelF6AuditionState();
}

int getPlaystatus() nothrow {
	return playstatus;
}

bool isPlaying() nothrow {  
	return playstatus == Status.Play || playstatus == Status.Keyjam;
}

bool keyjamEnabled() nothrow {
	return playstatus == Status.Keyjam;
}

void init() {
	if(audio_init(ntsc ? 60 : 50, &audio_frame) < 0) {
		throw new Error("Could not init audio.");
	}
	SDL_LockAudio();
	initSidRenderer();
	SDL_UnlockAudio();
}

private void initSidRenderer() {
	auto live = liveAudioConfiguration();
	if(!live.available)
		return;
	curfp = sidtype ? FP8580[curfp8580] : FP6581[curfp6581];
	sid_init(usefp, &curfp, live.sampleRate, sidtype, ntsc, interpolate, 0);
}

AudioRestartResult applyPendingAudioConfiguration() {
	int frameRate = ntsc ? 60 : 50;
	string validationError;
	if(!validateAudioRequest(pendingAudioRequest(), frameRate, validationError))
		return AudioRestartResult(AudioRestartStatus.rejected, validationError);

	SDL_PauseAudio(1);
	if(audio.audio.audioInited)
		SDL_LockAudio();
	stop();
	syncSidRegisters();
	if(audio.audio.audioInited)
		SDL_UnlockAudio();

	auto result = restartPendingAudioDevice(frameRate, &audio_frame);
	if(liveAudioConfiguration().available) {
		SDL_LockAudio();
		initSidRenderer();
		audio.callback.reset();
		audio.audio.reset();
		SDL_UnlockAudio();
		SDL_PauseAudio(0);
	}
	return result;
}

bool setPlaybackTiming(bool useNtsc) {
	int requestedMode = useNtsc ? 1 : 0;
	if(ntsc == requestedMode)
		return false;

	bool audioWasInited = audio.audio.audioInited;
	if(audioWasInited) {
		SDL_PauseAudio(1);
		SDL_LockAudio();
	}
	scope(exit) {
		if(audioWasInited) {
			SDL_UnlockAudio();
			SDL_PauseAudio(0);
		}
	}

	stop();
	syncSidRegisters();
	ntsc = requestedMode;
	audio.audio.setBaseFrameRate(ntsc ? 60 : 50);
	initSidRenderer();
	audio.callback.reset();
	audio.audio.reset();
	return true;
}

void setSidModel(int v) {
	assert(v == 0 || v == 1);
	if(sidtype == v) return;
	cancelF6AuditionState();
	sidtype = v;
	init();
}

void toggleSIDModel() {
	setSidModel(sidtype ^ 1);
}

void playNote(Element emt) {
	playNoteForVoice(emt, seq.sequencer.activeVoiceNum);
}

private void playNoteForVoice(Element emt, int v) {
	if(v < 0)
		v = 0;
	if(v > 2)
		v = 2;
	bool preparedF6NoteOn = keyjamF6Audition.preparedNoteOn;
	keyjamF6Audition.preparedNoteOn = false;
	if(playstatus == Status.Play) {
		if(preparedF6NoteOn)
			cancelF6AuditionState();
		return;
	}

	// no audio reset if already inited
	if(playstatus != Status.Keyjam) {
		audio.callback.reset();
		audio.audio.reset();
	}

	playstatus = Status.Stop;

	song.setVoicon([v == 0 ? 0 : 1, v == 1 ? 0 : 1, v == 2 ? 0 : 1]);
	muteSID(1,1,1);
	song.cpu.reset();
	song.cpu.regs.a = emt.note.value;
	song.cpu.regs.x = cast(ubyte)v;
	song.cpu.regs.y = emt.instr.value;
	if(song.ver > 8) 
		song.memspace[song.offsets[Offsets.SHTRANS] + v] = 0;
	ushort call = 0x1009;
	if(song.ver > 7) {
		call = song.offsets[Offsets.Subnoteplay];
	}
	SDL_LockAudio();
	scope(exit) SDL_UnlockAudio();
	cpuCall(call, false);
	syncSidRegisters();
	if(preparedF6NoteOn)
		startPreparedF6AuditionLocked(v);
	playstatus = Status.Keyjam;
}

void playRow(Voice[] voices) {
	if(playstatus == Status.Play) return;
	int[] trk, seq;
	foreach(v; voices) {
		auto r = v.activeRow;
		trk ~= r.trkOffset;
		seq ~= r.seqOffset;
	}
	SDL_PauseAudio(1);
	if(SDL_GetAudioStatus() == SDL_AUDIO_PLAYING)
		std.stdio.writefln("Audio thread not finished!");
	SDL_Delay(20);
	stop();

	initPlayOffset(trk, seq);

	song.cpu.reset();

	cpuCall(0x1003,true);
	cpuCall(0x1003,true);
	cpuCall(0x1003,true);

	playstatus = Status.Keyjam;

	SDL_PauseAudio(0);
}


void start(int[] trk, int[] seq) {
	SDL_PauseAudio(1);
	if(SDL_GetAudioStatus() == SDL_AUDIO_PLAYING)
		std.stdio.writefln("Audio thread not finished!");
	SDL_Delay(20);
	stop();
	initPlayOffset(trk,seq);
	audio.timer.start();
	audio.callback.reset();
	audio.audio.reset();
	playstatus = Status.Play;
	SDL_PauseAudio(0);
}

void start() {
	start([0, 0, 0], [0, 0, 0]);
}

void stop() nothrow {
	cancelF6AuditionState();
	playstatus = Status.Stop;
	muteSID(1,1,1);
}

void toggleVoice(int v) {
	if(v > 2 || v < 0) return;
	bool deviceLocked = enterVoiceMuteAudioLock();
	scope(exit) leaveVoiceMuteAudioLock(deviceLocked);
	int[3] next = [muted[0], muted[1], muted[2]];
	next[v] ^= 1;
	applyVoiceMuteStateLocked(next[0], next[1], next[2]);
}

void setVoicon(int v1, int v2, int v3) {
	bool deviceLocked = enterVoiceMuteAudioLock();
	scope(exit) leaveVoiceMuteAudioLock(deviceLocked);
	applyVoiceMuteStateLocked(v1, v2, v3);
}

void setVoicon(int[] m) {
	bool deviceLocked = enterVoiceMuteAudioLock();
	scope(exit) leaveVoiceMuteAudioLock(deviceLocked);
	applyVoiceMuteStateLocked(m[0], m[1], m[2]);
}

void setVoicon(shared int[] m) {
	bool deviceLocked = enterVoiceMuteAudioLock();
	scope(exit) leaveVoiceMuteAudioLock(deviceLocked);
	applyVoiceMuteStateLocked(m[0], m[1], m[2]);
}

private bool enterVoiceMuteAudioLock() {
	bool deviceLocked = audio.audio.audioInited;
	if(deviceLocked)
		SDL_LockAudio();
	if(voiceMuteLockTestEnabled) {
		voiceMuteLockTestState.lockEntries++;
		voiceMuteLockTestState.depth++;
		if(voiceMuteLockTestState.depth > voiceMuteLockTestState.maxDepth)
			voiceMuteLockTestState.maxDepth = voiceMuteLockTestState.depth;
		if(voiceMuteLockTestState.depth > 1)
			voiceMuteLockTestState.nestedEntries++;
	}
	return deviceLocked;
}

private void leaveVoiceMuteAudioLock(bool deviceLocked) {
	if(voiceMuteLockTestEnabled) {
		voiceMuteLockTestState.unlocks++;
		voiceMuteLockTestState.depth--;
	}
	if(deviceLocked)
		SDL_UnlockAudio();
}

// Caller must hold the audio-device lock, or run while no device exists.
private void applyVoiceMuteStateLocked(int v1, int v2, int v3) {
	if(voiceMuteLockTestEnabled) {
		voiceMuteLockTestState.ownerCalls++;
		if(voiceMuteLockTestState.depth <= 0)
			voiceMuteLockTestState.ownerCallsWithoutLock++;
	}
	muted[0] = v1;
	muted[1] = v2;
	muted[2] = v3;
	song.setVoicon(muted);
	muteSID(muted[0], muted[1], muted[2]);
}

void resetVoiceMuteLockTestState(bool enabled = true) nothrow {
	voiceMuteLockTestState = VoiceMuteLockTestSnapshot();
	voiceMuteLockTestEnabled = enabled;
}

VoiceMuteLockTestSnapshot voiceMuteLockTestSnapshot() nothrow {
	return voiceMuteLockTestState;
}

void initFP() {
	init();
	song.fppres = sidtype ? curfp8580 : curfp6581;
}

void nextFP() {
    if (usefp) {
        if (sidtype) {
            ++curfp8580;
            curfp8580 %= FP8580.length;
        } else {
            ++curfp6581;
            curfp6581 %= FP6581.length;
        }

        initFP();
    }
}


void setFP(int fp) {
    if (usefp) {
        if (sidtype) {
			curfp8580 = cast(int)(fp % FP8580.length);
        } else {
			curfp6581 = cast(int)(fp % FP6581.length);
        }
        initFP();
    }
}


void prevFP() {
    if (usefp) {
        if (sidtype) {
            --curfp8580;
            if (curfp8580 < 0) curfp8580 = cast(int)(FP8580.length-1);
        } else {
            --curfp6581;
            if (curfp6581 < 0) curfp6581 = cast(int)(FP6581.length-1);
        }

        initFP();
    }
}

void fastForward(int val) {
	int step = val * 16;
	SDL_LockAudio();
	for(int i = 0 ; i < step; i++) {
		audio_frame();
	}
	SDL_UnlockAudio();
}

private struct CpuRegsSnapshot {
	ubyte a, x, y, st, sp;
	address pc;
}

private CpuRegsSnapshot captureCpuRegs() {
	auto regs = song.cpu.regs;
	return CpuRegsSnapshot(regs.a, regs.x, regs.y, regs.st, regs.sp,
		regs.pc);
}

private void restoreCpuRegs(CpuRegsSnapshot regs) {
	song.cpu.regs.a = regs.a;
	song.cpu.regs.x = regs.x;
	song.cpu.regs.y = regs.y;
	song.cpu.regs.st = regs.st;
	song.cpu.regs.sp = regs.sp;
	song.cpu.regs.pc = regs.pc;
}

struct PlaybackCheckpoint {
	ubyte[65536] memory;
	CpuRegsSnapshot regs;
	int playstatus;
	ubyte voiceMuteMask;
	TimerSnapshot timer;
	CallbackSnapshot callback;
	PosDataTable fplayPos;
	int globalRow;
	int[3] trk;
	int[3] seq;
}

private enum CHECKPOINT_SEEK_INTERVAL = 512;

private PlaybackCheckpoint[] audibleSeekCheckpoints;
private Song audibleSeekCheckpointSong;
private int audibleSeekCheckpointSubtune = -1;

private ubyte currentVoiceMuteMask(int v1, int v2, int v3)
		pure nothrow @safe {
	return cast(ubyte)((v1 != 0 ? 1 : 0) |
		(v2 != 0 ? 2 : 0) |
		(v3 != 0 ? 4 : 0));
}

private ubyte currentVoiceMuteMask() nothrow {
	return currentVoiceMuteMask(muted[0], muted[1], muted[2]);
}

private bool playbackCheckpointMatchesCurrentVoiceMuteMask(
		ref const(PlaybackCheckpoint) checkpoint) nothrow {
	return checkpoint.voiceMuteMask == currentVoiceMuteMask();
}

private bool audibleSeekCheckpointsMatchCurrentVoiceMuteMask() nothrow {
	foreach(ref checkpoint; audibleSeekCheckpoints) {
		if(!playbackCheckpointMatchesCurrentVoiceMuteMask(checkpoint))
			return false;
	}
	return true;
}

private PlaybackCheckpoint capturePlaybackCheckpoint(int globalRow,
		int[3] trk, int[3] seq) {
	PlaybackCheckpoint checkpoint;
	checkpoint.memory[] = song.data[];
	checkpoint.regs = captureCpuRegs();
	checkpoint.playstatus = playstatus;
	checkpoint.voiceMuteMask = currentVoiceMuteMask();
	checkpoint.timer = audio.timer.snapshot();
	checkpoint.callback = audio.callback.snapshot();
	checkpoint.fplayPos = fplayPos !is null ? fplayPos.dup() : null;
	checkpoint.globalRow = globalRow;
	checkpoint.trk = trk;
	checkpoint.seq = seq;
	return checkpoint;
}

private void resetAudibleCheckpointSeekCache(string reason) {
	audibleSeekCheckpoints.length = 0;
	audibleSeekCheckpointSong = song;
	audibleSeekCheckpointSubtune = song !is null ? song.subtune : -1;
}

void resetAudibleCheckpointSeekSession(string reason) {
	resetAudibleCheckpointSeekCache(reason);
}

private void ensureAudibleCheckpointSeekSession() {
	if(song is null)
		return;
	if(audibleSeekCheckpointSong !is song ||
			audibleSeekCheckpointSubtune != song.subtune) {
		resetAudibleCheckpointSeekCache("song_or_subtune_changed");
		return;
	}
	if(!audibleSeekCheckpointsMatchCurrentVoiceMuteMask())
		resetAudibleCheckpointSeekCache("voice_mute_changed");
}

private void restorePlaybackCheckpoint(ref PlaybackCheckpoint checkpoint) {
	song.data[] = checkpoint.memory[];
	restoreCpuRegs(checkpoint.regs);
	playstatus = checkpoint.playstatus;
	audio.timer.restore(checkpoint.timer);
	audio.callback.restore(checkpoint.callback);
	if(checkpoint.fplayPos !is null && fplayPos !is null)
		fplayPos.copyFrom(checkpoint.fplayPos);
	applyVoiceMuteStateLocked(muted[0], muted[1], muted[2]);
	syncSidRegisters();
}

private struct SilentPrerollResult {
	int rows, frames;
	int[3] trk, seq;
	bool success;
	long ms;
}

private SilentPrerollResult silentPrerollRows(int startRow, int targetRow,
		int[3] startTrk, int[3] startSeq) {
	enum MAX_PREROLL_FRAMES = 250_000;
	SilentPrerollResult result;
	result.rows = startRow;
	result.trk = startTrk;
	result.seq = startSeq;

	StopWatch sw;
	sw.start();
	while(result.frames < MAX_PREROLL_FRAMES && result.rows < targetRow) {
		audio_frame();
		result.frames++;
		int rowTicks = audio.timer.readRowTick();
		if(rowTicks <= 0)
			continue;
		advancePrerollSimPositions(result.trk, result.seq, rowTicks);
		result.rows += rowTicks;
	}
	sw.stop();
	result.ms = sw.peek.total!"msecs";
	result.success = result.rows >= targetRow;
	return result;
}

private bool buildAudibleCheckpointSeekCacheTo(int targetRow,
		out long buildMs) {
	if(targetRow < 0 || song is null)
		return false;
	ensureAudibleCheckpointSeekSession();

	StopWatch sw;
	sw.start();
	if(audibleSeekCheckpoints.length == 0) {
		stop();
		initPlayOffset([0, 0, 0], [0, 0, 0]);
		audio.timer.start();
		audio.callback.reset();
		audio.audio.reset();
		playstatus = Status.Play;
		audio.timer.readRowTick();

		int[3] trk = [0, 0, 0];
		int[3] seq = [0, 0, 0];
		auto checkpoint = capturePlaybackCheckpoint(0, trk, seq);
		audibleSeekCheckpoints ~= checkpoint;
	}
	else {
		auto last = audibleSeekCheckpoints[$ - 1];
		restorePlaybackCheckpoint(last);
	}

	while(audibleSeekCheckpoints[$ - 1].globalRow + CHECKPOINT_SEEK_INTERVAL
			<= targetRow) {
		auto last = audibleSeekCheckpoints[$ - 1];
		int nextRow = last.globalRow + CHECKPOINT_SEEK_INTERVAL;
		auto result = silentPrerollRows(last.globalRow, nextRow, last.trk,
			last.seq);
		if(!result.success) {
			sw.stop();
			buildMs = sw.peek.total!"msecs";
			return false;
		}
		auto checkpoint = capturePlaybackCheckpoint(result.rows, result.trk,
			result.seq);
		audibleSeekCheckpoints ~= checkpoint;
	}
	sw.stop();
	buildMs = sw.peek.total!"msecs";
	return true;
}

private bool nearestAudibleCheckpoint(int targetRow,
		out PlaybackCheckpoint selected) {
	bool found;
	foreach(checkpoint; audibleSeekCheckpoints) {
		if(!playbackCheckpointMatchesCurrentVoiceMuteMask(checkpoint))
			continue;
		if(checkpoint.globalRow > targetRow)
			break;
		selected = checkpoint;
		found = true;
	}
	return found;
}

int audibleCheckpointSeekTo(int targetRow, int[] targetTrk,
		int[] targetSeq, bool force = false, bool allowThrottle = true,
		string inputKind = "programmatic") {
	if(song is null || targetRow < 0 || targetTrk.length < 3 ||
			targetSeq.length < 3) {
		return 0;
	}

	SDL_PauseAudio(1);
	SDL_LockAudio();
	bool success;
	scope(exit) {
		if(success)
			audio.audio.reset();
		SDL_UnlockAudio();
		SDL_PauseAudio(0);
	}

	long buildMs;
	if(!buildAudibleCheckpointSeekCacheTo(targetRow, buildMs)) {
		return 0;
	}

	PlaybackCheckpoint checkpoint;
	if(!nearestAudibleCheckpoint(targetRow, checkpoint))
		return 0;
	restorePlaybackCheckpoint(checkpoint);
	auto preroll = silentPrerollRows(checkpoint.globalRow, targetRow,
		checkpoint.trk, checkpoint.seq);
	success = preroll.success;
	if(!success) {
		return 0;
	}

	playstatus = Status.Play;
	return 1;
}

struct VoiceMuteCheckpointTestSnapshot {
	ubyte currentMask;
	size_t checkpointCount;
	bool allCheckpointsMatchCurrentMask;
}

VoiceMuteCheckpointTestSnapshot voiceMuteCheckpointTestSnapshot() nothrow {
	return VoiceMuteCheckpointTestSnapshot(currentVoiceMuteMask(),
		audibleSeekCheckpoints.length,
		audibleSeekCheckpointsMatchCurrentVoiceMuteMask());
}

private void advancePrerollSimPositions(ref int[3] trk, ref int[3] seq,
		int steps) {
	foreach(voice; 0 .. 3)
		advancePrerollSimVoice(cast(int)voice, trk[voice], seq[voice],
			steps);
}

private void advancePrerollSimVoice(int voice, ref int trk, ref int seq,
		int steps) {
	if(voice < 0 || voice >= cast(int)song.tracks.length)
		return;
	auto tracks = song.tracks[voice];
	if(tracks.trackLength <= 0)
		return;

	foreach(_; 0 .. steps) {
		seq++;
		while(true) {
			if(trk < 0)
				trk = 0;
			if(trk >= tracks.trackLength)
				trk = tracks.trackLength - 1;
			auto track = tracks[trk];
			int rows = track.trans >= 0xf0 ? 1 : song.sequence(track).rows;
			if(seq < rows)
				break;
			seq -= rows;
			trk++;
			if(trk >= tracks.trackLength)
				trk = 0;
			track = tracks[trk];
			if(track.trans >= 0xf0) {
				if(song.ver >= 6)
					trk = tracks.wrapOffset;
				else
					trk = 0;
				seq = 0;
				break;
			}
		}
	}
}

void setMultiplier(int m) {
	if(m < 1 || m > 16) return;
	
	song.multiplier = m;
	audio.audio.setCallMultiplier(m);
}

void decMultiplier() {
	setMultiplier(song.multiplier - 1);
}

void incMultiplier() {
	setMultiplier(song.multiplier + 1);
}

private void initPlayOffset(int[] t, int[] s) {
	void out16b(int offs, int value) {
		song.buffer[offs] = value & 255;
		song.buffer[offs + 1] = (value >> 8) & 255;
	}
	address off1 = cast(ushort)(song.offsets[Offsets.Track1] + t[0] * 2);
	address off2 = cast(ushort)(song.offsets[Offsets.Track2] + t[1] * 2);
	address off3 = cast(ushort)(song.offsets[Offsets.Track3] + t[2] * 2);
	int tpoin2 = song.offsets[Offsets.Songsets];
	int tpoin = song.offsets[Offsets.TRACKLO];
	song.cpu.reset();
	if(song.ver >= 6) {
		song.buffer[tpoin] = off1 & 255;
		song.buffer[tpoin+1] = off2 & 255;
		song.buffer[tpoin+2] = off3 & 255;
		song.buffer[tpoin+3] = off1 >> 8;
		song.buffer[tpoin+4] = off2 >> 8;
		song.buffer[tpoin+5] = off3 >> 8;
		out16b(tpoin2, song.offsets[Offsets.Track1]);
		out16b(tpoin2+2, song.offsets[Offsets.Track2]);
		out16b(tpoin2+4, song.offsets[Offsets.Track3]);
	}
 	else {
		out16b(tpoin2, off1);
		out16b(tpoin2+2, off2);
		out16b(tpoin2+4, off3);
	}
	cpuCall(0x1000,false);
 	int seqcnt = song.offsets[Offsets.NEWSEQ];
	ubyte newseq0 = cast(ubyte)(s[0] * 4 + 1);
	ubyte newseq1 = cast(ubyte)(s[1] * 4 + 1);
	ubyte newseq2 = cast(ubyte)(s[2] * 4 + 1);
	song.buffer[seqcnt] = newseq0;
	song.buffer[seqcnt+1] = newseq1;
	song.buffer[seqcnt+2] = newseq2;
	setVoicon(muted);

	SDL_PauseAudio(0);
}

private void muteSID(int v1, int v2, int v3 ) nothrow {
	setSidVoiceMuteBit(4, v1);
	setSidVoiceMuteBit(7 + 4, v2);
	setSidVoiceMuteBit(14 + 4, v3);
}

private void setSidVoiceMuteBit(int sidControlOffset, int muted) nothrow {
	if(muted)
		song.sidbuf[sidControlOffset] =
			cast(ubyte)(song.sidbuf[sidControlOffset] | 0x08);
	else
		song.sidbuf[sidControlOffset] =
			cast(ubyte)(song.sidbuf[sidControlOffset] & 0xf7);
}
