// The SPC700 sound driver, assembled from snes/spc700.asm.
//
// The first two bytes are a little-endian length header used by sneslib;
// the code itself loads at DRIVER_ADDRESS ($0200).
#pragma once

namespace gss {

extern const unsigned int spc700_size;
extern const unsigned char spc700_data[];

}  // namespace gss
