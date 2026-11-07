// Output monitor tuner tests.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "tuner.h"

static int failures = 0;
#define CHECK(c)                                                                \
	do {                                                                        \
		if (!(c)) {                                                             \
			std::printf("%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #c); \
			++failures;                                                         \
		}                                                                       \
	} while (0)

using namespace gss;

// 2048 frames of a tone with a few harmonics, left + right summed as the
// original fed the tuner
static std::vector<int> tone(double hz, int rate)
{
	std::vector<int> v(2048);
	for (int i = 0; i < 2048; ++i) {
		const double t = 2 * 3.14159265358979 * hz * i / rate;
		v[i] = (int)(2 * 12000 * (std::sin(t) + 0.4 * std::sin(2 * t) + 0.2 * std::sin(3 * t)));
	}
	return v;
}

static bool is(const Tuner::Result& r, const char* note) { return r.note && std::strcmp(r.note, note) == 0; }

int main()
{
	const Tuner tuner;
	const int rate = 44100;

	CHECK(tuner.analyse(std::vector<int>(2048, 0), rate).note == nullptr);  // silence

	Tuner::Result r = tuner.analyse(tone(110.0, rate), rate);
	CHECK(is(r, "A") && std::abs(r.cents) <= 10);

	r = tuner.analyse(tone(220.0, rate), rate);  // an octave up folds to the same note
	CHECK(is(r, "A") && std::abs(r.cents) <= 10);

	r = tuner.analyse(tone(116.54, rate), rate);
	CHECK(is(r, "A#") && std::abs(r.cents) <= 10);

	r = tuner.analyse(tone(113.0, rate), rate);  // about 45 cents sharp of A
	CHECK(is(r, "A") && r.cents >= 30 && r.cents <= 50);

	r = tuner.analyse(tone(110.0, 32000), 32000);  // the output rate is honoured
	CHECK(is(r, "A") && std::abs(r.cents) <= 10);

	if (failures) {
		std::printf("audio_test: %d failure(s)\n", failures);
		return 1;
	}
	std::printf("audio_test: all checks passed\n");
	return 0;
}
