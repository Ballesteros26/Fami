#include "tuner.h"

#include <cfloat>
#include <cmath>
#include <cstdlib>

namespace gss {

namespace {
const double FREQS[] = {174.61, 164.81, 155.56, 146.83, 138.59, 130.81, 123.47, 116.54,
                        110.00, 103.83, 98.00,  92.50,  87.31,  82.41,  77.78};
const char* const NAMES[] = {"F", "E", "D#", "D", "C#", "C", "B", "A#", "A", "G#", "G", "F#", "F", "E", "D#"};
constexpr int COUNT = sizeof(FREQS) / sizeof(FREQS[0]);
}  // namespace

Tuner::Result Tuner::analyse(const std::vector<int>& a, int rate) const
{
	Result r;
	const int len = (int)a.size();
	double prev_diff = 0, prev_dx = 0, max_diff = 0;
	int sample_len = 0;

	// the first dip of the difference function below half its maximum is the period
	for (int i = 0; i < len; ++i) {
		double diff = 0;
		for (int j = 0; j < len; ++j) diff += (i + j < len) ? std::abs(a[j] - a[i + j]) : std::abs(a[j]);

		const double dx = prev_diff - diff;
		if (dx < 0 && prev_dx > 0 && diff < 0.5 * max_diff) {
			sample_len = i - 1;
			break;
		}
		prev_dx = dx;
		prev_diff = diff;
		if (diff > max_diff) max_diff = diff;
	}

	if (sample_len <= 0) return r;

	double frequency = (double)rate / (double)sample_len;
	while (frequency < 82.41) frequency *= 2.0;  // fold into one octave
	while (frequency > 164.81) frequency *= 0.5;

	double min_dist = DBL_MAX;
	int note = -1;
	for (int i = 0; i < COUNT; ++i) {
		const double dist = std::fabs(FREQS[i] - frequency);
		if (dist < min_dist) {
			min_dist = dist;
			note = i;
		}
	}

	// the folded frequency lies within 82.41..164.81, so both neighbours exist
	const double match = FREQS[note];
	if (frequency < match)
		r.cents = (int)(-100 * (frequency - match) / (FREQS[note + 1] - match));
	else
		r.cents = (int)(100 * (frequency - match) / (FREQS[note - 1] - match));
	r.note = NAMES[note];
	return r;
}

}  // namespace gss
