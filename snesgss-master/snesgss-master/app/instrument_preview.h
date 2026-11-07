// Instrument drawing shared by the instrument editor and the inspector.
#pragma once

#include <string>

#include "imgui.h"
#include "model.h"

namespace gss {

// Waveform and envelope preview filling size at the cursor, as the original
// RenderADSR() drew it.
void draw_instrument_preview(const Instrument& ins, ImVec2 size);

// The "Source: ..." and "BRR: ..." lines the original instrument page showed.
void instrument_info(const Instrument& ins, std::string& source, std::string& brr);

}  // namespace gss
