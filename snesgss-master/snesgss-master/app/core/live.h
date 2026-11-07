// Live updates of a playing preview: moves the driver running in SPC700 RAM
// from one compile of a song onto a newer one, keeping its place, so edits
// are heard while the song plays.
//
// Each music channel's place is its read pointer, its wait in ticks and the
// reference it may be inside (snes/spc700.asm keeps them in the direct page).
// Walking a channel's data the way the driver reads it gives the tick at
// which it reads each place, so the driver's state gives the song's time.
// That time is mapped by row (a speed edit doesn't make the song jump) onto
// the new compile, and each channel is put at the next place it reads there,
// with the wait until then. A note that is sounding carries on: the change
// is heard from the channel's next event.
#pragma once

#include <cstdint>
#include <unordered_map>
#include <vector>

#include "song.h"

namespace gss {

// Where a channel reads: what the driver keeps in M_PTR, M_REF_LEN and
// M_REF_RET (the return address only means something inside a reference).
struct DriverPlace {
	int ptr = 0;
	int ref_len = 0;
	int ret = 0;
	uint64_t key() const { return (uint64_t)ptr | (uint64_t)ref_len << 16 | (ref_len ? (uint64_t)ret << 24 : 0); }
};

// A channel's data as the driver reads it from its start: the places it
// reads after each wait, with the tick it reads them at.
struct ChannelWalk {
	struct Point {
		double tick;
		DriverPlace place;
	};
	std::vector<Point> points;
	std::unordered_map<uint64_t, int> index;  // place key to point
	int loop_point = 0;     // the first point of the part that repeats
	double loop_ticks = 0;  // its length; 0 if the walk found no loop
	bool sounds = false;    // the channel plays a note somewhere

	// The tick of the driver's state: the point it reads next, less its wait.
	// False if the state isn't one of the walk's places.
	bool time_of(const DriverPlace& place, int wait, double& tick) const;
	// Where the driver should be at tick: the next point read after it, and
	// the wait until then.
	bool place_at(double tick, DriverPlace& place, int& wait) const;
};

ChannelWalk walk_channel(const uint8_t* ram, int start);

// A compile of a song for live updates: its ARAM, its timing and each music
// channel's walk. Made on the UI thread, so a patch only looks things up.
// The compile must be made with Compiler::all_channels, so music channel N
// is the song's channel N.
struct LiveSong {
	std::vector<uint8_t> image;  // 64 KB
	int end = 0;                 // where the music ends; past it is leftovers
	SongTiming timing;
	std::vector<ChannelWalk> walks;

	LiveSong(const uint8_t* aram, int music_end, const SongTiming& t);
	bool valid() const { return timing.valid() && walks.size() == CHANNELS; }
	// Plays the same as o: the same code, samples and music.
	bool same_as(const LiveSong& o) const;
};

// Where the driver waits for its next frame (tick): its main loop and the
// streamer update it calls. With the CPU's program counter there, it holds
// nothing of a channel in its registers, so its RAM can be changed.
struct DriverIdle {
	int loop_lo = 0, loop_hi = 0;  // mainLoop up to the frame's update calls
	int sub_lo = 0, sub_hi = 0;    // updateBRRStreamerPos
	bool contains(int pc) const { return (pc >= loop_lo && pc < loop_hi) || (pc >= sub_lo && pc < sub_hi); }
};
// Found in the driver's code; false if it isn't there.
bool driver_idle(DriverIdle& idle);

// Moves the driver in ram, playing from, onto to: writes to's code, samples
// and music from $0200 up and puts each channel at its place in the new song
// at the same row. A channel that falls silent is keyed off. Sets *tick to
// the song's time in to's timing. False, with ram unchanged, if the driver's
// place can't be found.
bool live_patch(uint8_t* ram, const LiveSong& from, const LiveSong& to, double* tick = nullptr);

}  // namespace gss
