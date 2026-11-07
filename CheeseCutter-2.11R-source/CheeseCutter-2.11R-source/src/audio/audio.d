/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module audio.audio;
import derelict.sdl2.sdl;
import audio.resid.filter;
import audio.player;
import audio.callback;
import std.stdio;
import core.stdc.stdlib;
import core.stdc.string;
import std.conv;
import std.format : format;
import std.string : fromStringz;

enum MIXBUF_MUL = 2;
enum OSCILLOSCOPE_VOICES = 3;
enum OSCILLOSCOPE_SAMPLES = 1024;

struct AudioRequest {
	int sampleRate;
	int bufferSamples;
}

struct AudioLiveConfiguration {
	bool available;
	int sampleRate;
	int bufferSamples;
	int format;
	int channels;
}

enum AudioRestartStatus {
	rejected,
	applied,
	rolledBack,
	audioUnavailable
}

struct AudioRestartResult {
	AudioRestartStatus status;
	string message;
}

enum AudioRequest DEFAULT_AUDIO_REQUEST = AudioRequest(48_000, 128);
private immutable AudioRequest[] SUPPORTED_AUDIO_REQUESTS = [
	AudioRequest(44_100, 32),
	AudioRequest(44_100, 64),
	AudioRequest(44_100, 128),
	AudioRequest(44_100, 256),
	AudioRequest(44_100, 512),
	AudioRequest(44_100, 1_024),
	AudioRequest(44_100, 2_048),
	AudioRequest(44_100, 4_096),
	AudioRequest(48_000, 32),
	AudioRequest(48_000, 64),
	AudioRequest(48_000, 128),
	AudioRequest(48_000, 256),
	AudioRequest(48_000, 512),
	AudioRequest(48_000, 1_024),
	AudioRequest(48_000, 2_048),
	AudioRequest(48_000, 4_096),
	AudioRequest(96_000, 2_048),
	AudioRequest(96_000, 4_096),
];

private AudioRequest startupRequested = DEFAULT_AUDIO_REQUEST;
private AudioRequest currentRequested = DEFAULT_AUDIO_REQUEST;
private AudioRequest pendingRequested = DEFAULT_AUDIO_REQUEST;
private AudioLiveConfiguration currentLive;
private bool startupConfigured;

__gshared SDL_AudioSpec audiospec;
__gshared bool audioInited = false;
__gshared int framerate = 50;
__gshared int multiplier;
__gshared private int baseFrameRate = 50;
__gshared private int bufferUsed;
__gshared private int callbackInterval;
__gshared private int bufferCapacitySamples;
__gshared private bool renderActive;
__gshared short* mixbuf = null;

AudioRequest startupAudioRequest() {
	return startupRequested;
}

AudioRequest currentAudioRequest() {
	return currentRequested;
}

AudioRequest pendingAudioRequest() {
	return pendingRequested;
}

AudioLiveConfiguration liveAudioConfiguration() {
	return currentLive;
}

void configureStartupAudioRequest(AudioRequest request) {
	assert(!audioInited && !startupConfigured);
	startupRequested = request;
	currentRequested = request;
	pendingRequested = request;
	startupConfigured = true;
}

void beginPendingAudioConfiguration() {
	pendingRequested = currentRequested;
}

bool audioSettingsCombinationSupported(AudioRequest request) {
	foreach(supported; SUPPORTED_AUDIO_REQUESTS)
		if(request == supported)
			return true;
	return false;
}

bool validateAudioRequest(AudioRequest request, int frameRate,
		out string error) {
	if(request.sampleRate <= 0 || request.bufferSamples <= 0 ||
			request.bufferSamples > 0xffff || frameRate <= 0) {
		error = "Invalid audio sample rate or callback-buffer size.";
		return false;
	}
	if(!audioSettingsCombinationSupported(request)) {
		error = "Unsupported sample-rate and callback-buffer combination.";
		return false;
	}
	error = null;
	return true;
}

void stepPendingSampleRate(int direction) {
	int[] rates;
	foreach(request; SUPPORTED_AUDIO_REQUESTS)
		if(rates.length == 0 || rates[$ - 1] != request.sampleRate)
			rates ~= request.sampleRate;

	int current = -1;
	foreach(i, rate; rates) {
		if(rate == pendingRequested.sampleRate) {
			current = cast(int)i;
			break;
		}
	}
	if(current < 0)
		current = 1;
	else
		current = wrapIndex(current + (direction < 0 ? -1 : 1),
			cast(int)rates.length);
	int nextRate = rates[current];
	foreach(request; SUPPORTED_AUDIO_REQUESTS) {
		if(request.sampleRate == nextRate &&
				request.bufferSamples == pendingRequested.bufferSamples) {
			pendingRequested = request;
			return;
		}
	}
	foreach(request; SUPPORTED_AUDIO_REQUESTS) {
		if(request.sampleRate == nextRate) {
			pendingRequested = request;
			return;
		}
	}
}

void stepPendingBufferSize(int direction) {
	int count;
	int current = -1;
	foreach(request; SUPPORTED_AUDIO_REQUESTS) {
		if(request.sampleRate != pendingRequested.sampleRate)
			continue;
		if(request.bufferSamples == pendingRequested.bufferSamples)
			current = count;
		count++;
	}
	if(count == 0) {
		pendingRequested = DEFAULT_AUDIO_REQUEST;
		return;
	}
	int target = current < 0 ? 0 :
		wrapIndex(current + (direction < 0 ? -1 : 1), count);
	int index;
	foreach(request; SUPPORTED_AUDIO_REQUESTS) {
		if(request.sampleRate != pendingRequested.sampleRate)
			continue;
		if(index++ == target) {
			pendingRequested = request;
			return;
		}
	}
}

double audioCallbackDurationMilliseconds(AudioRequest request) {
	if(request.sampleRate <= 0)
		return 0.0;
	return cast(double)request.bufferSamples * 1_000.0 / request.sampleRate;
}

string currentAudioBackendName() {
	auto driver = SDL_GetCurrentAudioDriver();
	return driver is null ? "Unavailable" : fromStringz(driver).idup;
}

string currentAudioDeviceName() {
	return currentLive.available ? "System Default" : "Unavailable";
}

string audioFormatName(int formatValue) {
	switch(formatValue) {
	case AUDIO_S16LSB:
		return "Signed 16-bit little-endian";
	default:
		return format("SDL format $%04X", formatValue & 0xffff);
	}
}

string audioChannelName(int channels) {
	switch(channels) {
	case 1:
		return "Mono";
	case 2:
		return "Stereo";
	default:
		return format("%d channels", channels);
	}
}

private int wrapIndex(int value, int length) {
	if(value < 0)
		return length - 1;
	if(value >= length)
		return 0;
	return value;
}

extern(C) {
	extern __gshared char[0x19] sidreg;
	extern __gshared void sid_init(int, Filterparams*, int, int, int, int, int) nothrow;
	extern __gshared int sid_fillbuffer(short*, int, int) nothrow;
	extern __gshared int sid_renderbuffer(short*, int, int, int, int*) nothrow;
	extern __gshared void sid_reset_render_state() nothrow;
	extern __gshared void sid_close();
	extern __gshared int sid_get_oscilloscope_sample_capacity() nothrow;
	extern __gshared int sid_copy_oscilloscope_samples(short*, int, int) nothrow;
	extern __gshared void sid_clear_oscilloscope_samples() nothrow;
	__gshared void function() nothrow callback;

	int audio_init(int frameRate, void function() nothrow cb) {
		if(audioInited)
			return 0;
		string error;
		if(!openAudioDevice(currentRequested, frameRate, cb, error)) {
			writeln(error);
			return -1;
		}
		pendingRequested = currentRequested;
		return 0;
	}

	AudioRestartResult restartPendingAudioDevice(int frameRate,
			void function() nothrow cb) {
		AudioRequest requested = pendingRequested;
		string validationError;
		if(!validateAudioRequest(requested, frameRate, validationError))
			return AudioRestartResult(AudioRestartStatus.rejected,
				validationError);

		AudioRequest previousRequest = currentRequested;
		closeAudioDevice();

		string applyError;
		if(openAudioDevice(requested, frameRate, cb, applyError)) {
			currentRequested = requested;
			pendingRequested = requested;
			return AudioRestartResult(AudioRestartStatus.applied,
				format("Audio restarted: %d Hz, %d samples live.",
					currentLive.sampleRate, currentLive.bufferSamples));
		}

		string rollbackError;
		if(openAudioDevice(previousRequest, frameRate, cb, rollbackError)) {
			currentRequested = previousRequest;
			pendingRequested = previousRequest;
			return AudioRestartResult(AudioRestartStatus.rolledBack,
				format("Audio change failed: %s Previous settings restored.",
					applyError));
		}

		pendingRequested = previousRequest;
		return AudioRestartResult(AudioRestartStatus.audioUnavailable,
			format("Audio change failed: %s Rollback failed: %s",
				applyError, rollbackError));
	}

	private bool openAudioDevice(AudioRequest request, int frameRate,
			void function() nothrow cb, out string error) {
		SDL_AudioSpec requested = SDL_AudioSpec.init;
		if(!validateAudioRequest(request, frameRate, error))
			return false;

		requested.freq = request.sampleRate;
		requested.format = AUDIO_S16LSB;
		requested.channels = 1;
		requested.samples = cast(ushort)request.bufferSamples;
		requested.callback = &audio_callback_2;
		requested.userdata = null;

		if(SDL_OpenAudio(&requested, null) < 0) {
			error = "Could not open audio: " ~ fromStringz(SDL_GetError()).idup;
			clearClosedDeviceState();
			return false;
		}
		// The callback produces only the requested S16 mono format. Let SDL
		// convert that fixed application format to the native device format.
		audiospec = requested;

		if(audiospec.format != AUDIO_S16LSB || audiospec.channels != 1 ||
				audiospec.freq <= 0 || !audioSettingsCombinationSupported(
				AudioRequest(audiospec.freq, audiospec.samples))) {
			error = format("Invalid live audio format: %d Hz, format $%04X, " ~
				"%d channel(s), %d samples.", audiospec.freq,
				audiospec.format & 0xffff, audiospec.channels,
				audiospec.samples);
			SDL_CloseAudio();
			clearClosedDeviceState();
			return false;
		}

		bufferCapacitySamples = cast(int)audiospec.samples * MIXBUF_MUL;
		mixbuf = cast(short*)malloc(bufferCapacitySamples * short.sizeof);
		if(mixbuf is null) {
			error = "Could not allocate the audio callback buffer.";
			SDL_CloseAudio();
			clearClosedDeviceState();
			return false;
		}
		memset(mixbuf, 0, bufferCapacitySamples * short.sizeof);

		callback = cb;
		baseFrameRate = frameRate;
		if(multiplier < 1 || multiplier > 16)
			multiplier = 1;
		recalculateFrameSchedule();
		reset();
		currentLive = AudioLiveConfiguration(true, audiospec.freq,
			audiospec.samples, audiospec.format, audiospec.channels);
		audioInited = true;
		error = null;
		return true;
	}

	private void closeAudioDevice() {
		if(audioInited)
			SDL_CloseAudio();
		if(mixbuf !is null)
			free(mixbuf);
		clearClosedDeviceState();
	}

	private void clearClosedDeviceState() {
		mixbuf = null;
		audioInited = false;
		callback = null;
		bufferUsed = 0;
		callbackInterval = 0;
		bufferCapacitySamples = 0;
		renderActive = false;
		sid_reset_render_state();
		audiospec = SDL_AudioSpec.init;
		currentLive = AudioLiveConfiguration.init;
	}

	void audio_close() {
		closeAudioDevice();
		sid_close();
	}

	void reset() nothrow {
		bufferUsed = 0;
		renderActive = false;
		if(mixbuf !is null && bufferCapacitySamples > 0)
			memset(mixbuf, 0, bufferCapacitySamples * short.sizeof);
		sid_reset_render_state();
		sid_clear_oscilloscope_samples();
	}

	void setCallMultiplier(int m) {
		if(m < 1 || m > 16)
			return;
		if(!audioInited) {
			multiplier = m;
			return;
		}
		SDL_LockAudio();
		multiplier = m;
		recalculateFrameSchedule();
		reset();
		SDL_UnlockAudio();
	}

	package(audio) void setBaseFrameRate(int frameRate) {
		assert(frameRate == 50 || frameRate == 60);
		baseFrameRate = frameRate;
		recalculateFrameSchedule();
	}

	private void recalculateFrameSchedule() {
		framerate = baseFrameRate * multiplier;
		callbackInterval = audiospec.freq > 0 ? audiospec.freq / framerate : 0;
		if(audiospec.freq > 0 && callbackInterval < 1)
			callbackInterval = 1;
	}

	__gshared void audio_callback_2(void* data, ubyte* stream, int len) nothrow {
		int samplesRequested = cast(int)(len / short.sizeof);
		int t;
		if(!audio.player.isPlaying() || mixbuf is null ||
				callbackInterval <= 0) {
			if(renderActive)
				reset();
			memset(stream, 0, len);
			return;
		}
		renderActive = true;
		while(bufferUsed < samplesRequested) {
			int frameComplete;
			int capacity = bufferCapacitySamples - bufferUsed;
			if(capacity <= 0)
				break;
			t = sid_renderbuffer(mixbuf + bufferUsed, capacity,
				callbackInterval, cyclesPerFrame, &frameComplete);
			bufferUsed += t;
			if(frameComplete)
				(*callback)();
			if(t == 0 && !frameComplete)
				break;
		}

		int copySamples = bufferUsed < samplesRequested ?
			bufferUsed : samplesRequested;
		if(copySamples > 0)
			memcpy(stream, cast(ubyte*)mixbuf,
				copySamples * short.sizeof);
		if(copySamples < samplesRequested)
			memset(stream + copySamples * short.sizeof, 0,
				(samplesRequested - copySamples) * short.sizeof);
		bufferUsed -= copySamples;
		if(bufferUsed > 0)
			memmove(mixbuf, mixbuf + copySamples,
				bufferUsed * short.sizeof);
	}

	int oscilloscopeSampleCapacity() {
		return sid_get_oscilloscope_sample_capacity();
	}

	int copyOscilloscopeSamples(short[] dst, int samples) {
		if(samples <= 0 || dst.length < OSCILLOSCOPE_VOICES * samples)
			return 0;

		SDL_LockAudio();
		scope(exit) SDL_UnlockAudio();
		return sid_copy_oscilloscope_samples(dst.ptr, OSCILLOSCOPE_VOICES,
			samples);
	}
}
