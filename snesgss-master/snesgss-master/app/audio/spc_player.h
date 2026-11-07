// Plays compiled .spc images through Game_Music_Emu's SPC emulator.
//
// render() is called from the audio thread; everything else from the UI
// thread. The emulator is swapped under a mutex, so starting a new song
// never races the audio callback (the original editor spin-waited).
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <vector>

struct Music_Emu;

namespace gss {

class SpcPlayer {
public:
	explicit SpcPlayer(int sample_rate = 44100);
	~SpcPlayer();

	SpcPlayer(const SpcPlayer&) = delete;
	SpcPlayer& operator=(const SpcPlayer&) = delete;

	int sample_rate() const { return rate_; }

	// Starts playing an .spc image. Returns false (and keeps playing what
	// was playing) if the emulator rejects it.
	bool play(const uint8_t* spc, long size);
	void stop();
	bool playing() const { return active_.load(); }

	// Frames rendered since play() started the song, for following it.
	long long frames_played() const { return frames_.load(); }

	// A change to the SPC700's RAM, made from render() between two samples:
	// f gets the RAM, the CPU's program counter and the frames rendered so
	// far, and returns false to be offered the next sample instead (so it can
	// wait for the driver to idle). The emulator steps a sample at a time
	// meanwhile, which needs the native rate, 32000. Replaces one not yet
	// made; play() and stop() drop it.
	using Patch = std::function<bool(uint8_t* ram, int pc, long long frames)>;
	void queue_patch(Patch f);

	// Interleaved stereo, frames * 2 samples. Outputs silence when stopped,
	// fading out from the last sample to avoid a click.
	void render(int16_t* out, int frames);

	// Peak levels of the last render, 0..32768, for meters.
	int peak_left() const { return peak_l_.load(); }
	int peak_right() const { return peak_r_.load(); }

	// The most recent output mixed to mono, -1..1, oldest first, for
	// visualisations. count is at most TAP_SIZE.
	static constexpr int TAP_SIZE = 4096;
	void recent_samples(float* out, int count) const;

private:
	struct EmuDeleter {
		void operator()(Music_Emu* e) const;
	};

	int rate_;
	std::mutex mutex_;
	std::unique_ptr<Music_Emu, EmuDeleter> emu_;
	std::atomic<bool> active_{false};
	std::atomic<int> peak_l_{0}, peak_r_{0};
	std::atomic<long long> frames_{0};
	Patch queued_;
	int last_l_ = 0, last_r_ = 0;

	mutable std::mutex tap_mutex_;  // separate from mutex_, so the UI never waits on the emulator
	std::vector<float> tap_ = std::vector<float>(TAP_SIZE, 0.0f);
	int tap_pos_ = 0;
};

}  // namespace gss
