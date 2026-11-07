#include "spc_player.h"

#include <cstdlib>

#include "Spc_Emu.h"
#include "gme.h"

namespace gss {

void SpcPlayer::EmuDeleter::operator()(Music_Emu* e) const { gme_delete(e); }

SpcPlayer::SpcPlayer(int sample_rate) : rate_(sample_rate) {}

SpcPlayer::~SpcPlayer() = default;

bool SpcPlayer::play(const uint8_t* spc, long size)
{
	Music_Emu* raw = nullptr;
	if (gme_open_data(spc, size, &raw, rate_) || !raw) return false;
	std::unique_ptr<Music_Emu, EmuDeleter> emu(raw);

	gme_ignore_silence(emu.get(), 1);
	if (gme_start_track(emu.get(), 0)) return false;

	{
		std::lock_guard<std::mutex> lock(mutex_);
		emu_.swap(emu);
		frames_ = 0;
		queued_ = nullptr;
		active_ = true;
	}
	return true;  // the old emulator is deleted here, outside the lock
}

void SpcPlayer::stop()
{
	std::unique_ptr<Music_Emu, EmuDeleter> old;
	std::lock_guard<std::mutex> lock(mutex_);
	active_ = false;
	queued_ = nullptr;
	old.swap(emu_);
}

static Snes_Spc& spc_of(Music_Emu* emu) { return static_cast<Spc_Emu*>(emu)->spc(); }  // gme_open_data made an Spc_Emu

void SpcPlayer::queue_patch(Patch f)
{
	std::lock_guard<std::mutex> lock(mutex_);
	queued_ = std::move(f);
}

void SpcPlayer::render(int16_t* out, int frames)
{
	const int samples = frames * 2;
	if (samples <= 0) return;

	{
		std::lock_guard<std::mutex> lock(mutex_);
		if (emu_ && active_) {
			// a queued patch: a frame at a time until it is made
			int done = 0;
			while (queued_ && done < frames) {
				Snes_Spc& spc = spc_of(emu_.get());
				if (queued_(spc.smp_ram(), spc.smp_regs().pc, frames_.load() + done)) {
					queued_ = nullptr;
					break;
				}
				if (gme_play(emu_.get(), 2, out + done * 2)) out[done * 2] = out[done * 2 + 1] = 0;
				++done;
			}
			if (done < frames && gme_play(emu_.get(), (frames - done) * 2, out + done * 2)) {
				for (int i = done * 2; i < samples; ++i) out[i] = 0;
			}
			frames_ += frames;
			last_l_ = out[samples - 2];
			last_r_ = out[samples - 1];
		} else {
			// decay from the last output to zero, as the original mixer did
			const int step = 16;
			for (int i = 0; i < samples; i += 2) {
				if (last_l_ < 0) last_l_ = (last_l_ + step > 0) ? 0 : last_l_ + step;
				if (last_l_ > 0) last_l_ = (last_l_ - step < 0) ? 0 : last_l_ - step;
				if (last_r_ < 0) last_r_ = (last_r_ + step > 0) ? 0 : last_r_ + step;
				if (last_r_ > 0) last_r_ = (last_r_ - step < 0) ? 0 : last_r_ - step;
				out[i] = (int16_t)last_l_;
				out[i + 1] = (int16_t)last_r_;
			}
		}
	}

	{
		std::lock_guard<std::mutex> lock(tap_mutex_);
		for (int i = 0; i < samples; i += 2) {
			tap_[tap_pos_] = ((float)out[i] + (float)out[i + 1]) / 65536.0f;
			tap_pos_ = (tap_pos_ + 1) % TAP_SIZE;
		}
	}

	int pl = 0, pr = 0;
	for (int i = 0; i < samples; i += 2) {
		const int l = std::abs((int)out[i]);
		const int r = std::abs((int)out[i + 1]);
		if (l > pl) pl = l;
		if (r > pr) pr = r;
	}
	peak_l_ = pl;
	peak_r_ = pr;
}

void SpcPlayer::recent_samples(float* out, int count) const
{
	if (count > TAP_SIZE) count = TAP_SIZE;
	std::lock_guard<std::mutex> lock(tap_mutex_);
	int pos = (tap_pos_ - count + TAP_SIZE) % TAP_SIZE;
	for (int i = 0; i < count; ++i) {
		out[i] = tap_[pos];
		pos = (pos + 1) % TAP_SIZE;
	}
}

}  // namespace gss
