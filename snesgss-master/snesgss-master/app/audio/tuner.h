// The original editor's built-in tuner: a C++ port of John Montgomery's
// Java 5KTuner (CC-BY 2008), as the output monitor used it. Finds the pitch
// by autocorrelation, folds it into one octave and names the nearest note.
#pragma once

#include <vector>

namespace gss {

class Tuner {
public:
	struct Result {
		const char* note = nullptr;  // "A#", or nullptr when no pitch was found
		int cents = 0;               // -50..50 from that note
	};

	// mono holds the left and right samples summed (-65536..65534), oldest
	// first. The original analysed 2048 frames at a time.
	Result analyse(const std::vector<int>& mono, int rate) const;
};

}  // namespace gss
