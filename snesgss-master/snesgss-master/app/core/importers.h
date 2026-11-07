// Importers and the source WAV exporter, lifted out of the original
// editor's UI handlers. Each one works on in-memory file data so the UI owns
// file dialogs and the core stays free of I/O policy.
#pragma once

#include <string>
#include <vector>

#include "model.h"

namespace gss {

// File > Import WAV into an instrument slot (SpeedButtonImportWavClick).
// file_name is the path the user picked; the instrument is named after it
// (directory and extension stripped), as the original did. On failure the
// instrument is left unchanged. The caller re-encodes the BRR afterwards.
bool import_wav(const std::string& data, const std::string& file_name, Instrument& ins, std::string* error = nullptr);

// Instrument > Extract source wave (MExtractSourceWaveClick).
std::string export_source_wav(const Instrument& ins);

// File > Import XM: as_songs=false imports all orders as one song (Import XM >
// Song); as_songs=true imports each order as its own song, a sound effect
// (Import XM > Sound effects). See ImportXM. A song replaces the song in use
// with the same name (not blank or "untitled"), so importing an XM again
// replaces it; the others go from song_cur on (the app passes
// song_append_slot(); MAX_SONGS if none is free). On failure message holds
// the status text and no song is changed.
//
// With samples, each XM instrument's sample (the one its keymap plays for
// C-4) is also imported, retuned so the XM's C-4 plays on the editor's C-4,
// and the notes keep their written octave. An instrument replaces the one
// with a sample and the same name, taking the XM's sample, loop and volume
// and keeping its envelope, EQ, resample, downsample and ramp settings; the
// others go into the slots after the last one in use. The imported notes are
// renumbered to them; the import fails, changing nothing, if they don't fit. Without, notes go two
// octaves up, as in the original, for samples prepared the SNES GSS way.
// Row speeds follow the XM's ticks per row and BPM (header and Fxx), rounded
// to the driver's 1/160 s steps. Volumes, pan, pitch slides, portamento and
// vibrato convert into the editor's volumes and effects, the order list is
// followed through Bxx/Dxx (a jump back is the loop point), and what has no
// equivalent is listed in info->not_converted.
struct XmImportInfo {
	// 0-based slots, in the XM's order
	std::vector<int> songs;                 // written
	std::vector<int> songs_replaced;        // of those, replacing a song of the same name
	std::vector<int> instruments;           // added, with the XM's samples
	std::vector<int> instruments_replaced;  // replaced, having the same name
	std::string not_converted;   // what the driver can't play, e.g. "arpeggio (12), tremolo (3)"
};
bool import_xm(const std::string& data, Module& m, int song_cur, bool as_songs, bool samples,
               std::string* message = nullptr, XmImportInfo* info = nullptr);

// File > Import MIDI into song_cur (MImportMidiClick); the app passes
// song_append_slot(). The song is cleared first; on an error after that it
// keeps what was imported so far, as the original did.
bool import_midi(const std::string& data, Module& m, int song_cur, std::string* error = nullptr);

// File > Import FamiTracker text export, sub song number subsong (1-based),
// into song_cur (MImportFamiTrackerClick); the app passes song_append_slot().
// The song's name and effect flag are kept; on failure the song is unchanged.
bool import_famitracker_text(const std::string& data, int subsong, Module& m, int song_cur, std::string* error = nullptr);
// The names of a FamiTracker text export's tracks (sub songs), in order;
// "" for one without a name.
std::vector<std::string> famitracker_track_names(const std::string& data);

// File > Import SPC bank (.bnk) into the instrument slots (MImportSPCBankClick).
// Needs all 64 records; on failure no instrument is changed.
bool import_spc_bank(const std::string& data, Module& m, std::string* error = nullptr);

}  // namespace gss
