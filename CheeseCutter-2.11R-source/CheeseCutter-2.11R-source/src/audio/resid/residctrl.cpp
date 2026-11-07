/* reSID interface
 *
 * much of the code here is from GOATTRACKER, (c) Cadaver
 */
#define PALCLOCKRATE 985248
#define NTSCCLOCKRATE 1022727

#define NUMSIDREGS 0x19
#define SIDWRITEDELAY 9 // lda $xxxx,x 4 cycles, sta $d400,x 5 cycles

#include <atomic>

#include <resid/sid.h>
#include <resid-fp/sidfp.h>

extern "C" {
		enum {
			SID_OSCILLOSCOPE_VOICES = 3,
			SID_OSCILLOSCOPE_SAMPLES = 1024
	};

		typedef struct
		{
			float distortionrate;
			float distortionpoint;
		float distortioncfthreshold;
		float type3baseresistance;
		float type3offset;
		float type3steepness;
		float type3minimumfetresistance;
		float type4k;
		float type4b;
		float voicenonlinearity;
	} FILTERPARAMS;

	int clockrate;
	int samplerate;
	unsigned char sidreg[NUMSIDREGS];
	const unsigned char sidorder[] = {
        0x0e,0x0f,0x14,0x13,0x10,0x11,0x12,
        0x07,0x08,0x0d,0x0c,0x09,0x0a,0x0b,
        0x00,0x01,0x06,0x05,0x02,0x03,0x04,
        0x16,0x17,0x18,0x15
		};
		SID *sid= 0;
		SIDFP *sidfp = 0;
		int usefp = 0;
		short oscilloscope[SID_OSCILLOSCOPE_VOICES][SID_OSCILLOSCOPE_SAMPLES];
		int oscilloscope_write_index = 0;
		int oscilloscope_sample_count = 0;

		enum SID_RENDER_PHASE {
			SID_RENDER_IDLE,
			SID_RENDER_EXTRA_DELAY,
			SID_RENDER_REGISTER_WRITE,
			SID_RENDER_WRITE_DELAY,
			SID_RENDER_FRAME_DELAY
		};

		typedef struct {
			SID_RENDER_PHASE phase;
			int register_index;
			int phase_cycles_remaining;
			int frame_cycles_remaining;
			int routine_cycles;
			int keyjam_f6_generation;
			unsigned char registers[NUMSIDREGS];
		} SID_RENDER_STATE;

		static SID_RENDER_STATE render_state = {};
		static std::atomic<int> keyjam_f6_generation{0};
		static std::atomic<int> keyjam_f6_control_offset{0};
		static std::atomic<int> keyjam_f6_gate_generation{0};
		static std::atomic<int> keyjam_f6_gate_samples{0};

		void sid_reset_render_state() {
			render_state.phase = SID_RENDER_IDLE;
			render_state.register_index = 0;
			render_state.phase_cycles_remaining = 0;
			render_state.frame_cycles_remaining = 0;
			render_state.routine_cycles = 0;
			render_state.keyjam_f6_generation = 0;
		}

		void sid_keyjam_f6_arm_render_readiness(int generation,
				int control_offset) {
			if(generation <= 0 || control_offset < 0 ||
					control_offset >= NUMSIDREGS) {
				keyjam_f6_generation.store(0, std::memory_order_release);
				keyjam_f6_gate_generation.store(0,
					std::memory_order_release);
				keyjam_f6_gate_samples.store(0,
					std::memory_order_release);
				return;
			}
			keyjam_f6_control_offset.store(control_offset,
				std::memory_order_relaxed);
			keyjam_f6_gate_samples.store(0, std::memory_order_release);
			keyjam_f6_gate_generation.store(0,
				std::memory_order_release);
			keyjam_f6_generation.store(generation,
				std::memory_order_release);
		}

		void sid_keyjam_f6_cancel_render_readiness() {
			keyjam_f6_generation.store(0, std::memory_order_release);
			keyjam_f6_gate_generation.store(0,
				std::memory_order_release);
			keyjam_f6_gate_samples.store(0,
				std::memory_order_release);
		}

		int sid_keyjam_f6_gate_on_samples(int generation) {
			if(generation <= 0 ||
					keyjam_f6_gate_generation.load(
						std::memory_order_acquire) != generation)
				return 0;
			return keyjam_f6_gate_samples.load(
				std::memory_order_acquire);
		}

		void sid_clear_oscilloscope_samples() {
			for (int v = 0; v < SID_OSCILLOSCOPE_VOICES; v++) {
				for (int i = 0; i < SID_OSCILLOSCOPE_SAMPLES; i++) {
					oscilloscope[v][i] = 0;
				}
			}
			oscilloscope_write_index = 0;
			oscilloscope_sample_count = 0;
		}

		void sid_capture_oscilloscope_sample(short v1, short v2, short v3) {
			oscilloscope[0][oscilloscope_write_index] = v1;
			oscilloscope[1][oscilloscope_write_index] = v2;
			oscilloscope[2][oscilloscope_write_index] = v3;
			oscilloscope_write_index++;
			if (oscilloscope_write_index >= SID_OSCILLOSCOPE_SAMPLES) {
				oscilloscope_write_index = 0;
			}
			if (oscilloscope_sample_count < SID_OSCILLOSCOPE_SAMPLES) {
				oscilloscope_sample_count++;
			}
		}

		int sid_get_oscilloscope_sample_capacity() {
			return SID_OSCILLOSCOPE_SAMPLES;
		}

		int sid_copy_oscilloscope_samples(short *dst, int voices, int samples) {
			if (!dst || voices <= 0 || samples <= 0) {
				return 0;
			}

			for (int v = 0; v < voices; v++) {
				for (int i = 0; i < samples; i++) {
					dst[v * samples + i] = 0;
				}
			}

			int copy_voices = voices < SID_OSCILLOSCOPE_VOICES ?
				voices : SID_OSCILLOSCOPE_VOICES;
			int copy_samples = samples < oscilloscope_sample_count ?
				samples : oscilloscope_sample_count;
			int dst_offset = samples - copy_samples;
			int src_start = oscilloscope_write_index - copy_samples;
			while (src_start < 0) {
				src_start += SID_OSCILLOSCOPE_SAMPLES;
			}

			for (int i = 0; i < copy_samples; i++) {
				int src = src_start + i;
				if (src >= SID_OSCILLOSCOPE_SAMPLES) {
					src -= SID_OSCILLOSCOPE_SAMPLES;
				}
				for (int v = 0; v < copy_voices; v++) {
					dst[v * samples + dst_offset + i] = oscilloscope[v][src];
				}
			}

			return copy_samples;
		}

		void sid_close() {
			sid_reset_render_state();
			if(sid) {
				delete sid;
				sid = nullptr;
			}
			if(sidfp) {
				delete sidfp;
				sidfp = nullptr;
			}
		}
	
		void sid_init(int fp, FILTERPARAMS *fparams, int speed, unsigned m, unsigned ntsc, unsigned interpolate, unsigned customclockrate)
		{
			int c;

			usefp = fp;
			sid_reset_render_state();
			sid_clear_oscilloscope_samples();
			
			if (ntsc) clockrate = NTSCCLOCKRATE;
		else clockrate = PALCLOCKRATE;
	
		if (customclockrate)
			clockrate = customclockrate;
	
		samplerate = speed;
	
		if (!sidfp) sidfp = new SIDFP();
		if (!sid) sid = new SID();
		
		if(usefp) {
			switch(interpolate)
			{
			case 0:
				sidfp->set_sampling_parameters(clockrate, SAMPLE_INTERPOLATE, speed);
				break;
			default:
				sidfp->set_sampling_parameters(clockrate, SAMPLE_RESAMPLE_INTERPOLATE, speed);
				break;
			}
			sidfp->reset();
			for (c = 0; c < NUMSIDREGS; c++) {
				sidreg[c] = 0x00;
			}

			if (m == 1)
				sidfp->set_chip_model(MOS8580);
			else
				sidfp->set_chip_model(MOS6581);
			sidfp->get_filter().set_distortion_properties(
                fparams->distortionrate,
                fparams->distortionpoint,
                fparams->distortioncfthreshold);
			sidfp->get_filter().set_type3_properties(
                fparams->type3baseresistance,
                fparams->type3offset,
                fparams->type3steepness,
                fparams->type3minimumfetresistance);
			sidfp->get_filter().set_type4_properties(
                fparams->type4k,
                fparams->type4b);
			sidfp->set_voice_nonlinearity(
                fparams->voicenonlinearity);
			sidfp->enable_filter(true);
		}
		else {
			switch(interpolate)
			{
			case 0:
				sid->set_sampling_parameters(clockrate, SAMPLE_FAST, speed, 20000);
				break;
			default:
				sid->set_sampling_parameters(clockrate, SAMPLE_INTERPOLATE, speed, 20000);
				break;
			}
			sid->reset();
			for (c = 0; c < NUMSIDREGS; c++) {
				sidreg[c] = 0x00;
			}
  
			if (m == 1) {
				sid->set_chip_model(MOS8580);
			}
			else {
				sid->set_chip_model(MOS6581);
			}
		}
	}
  
	unsigned char sid_getorder(unsigned char index) {
		return sidorder[index];
	}
	
	static void sid_prepare_render_phase() {
		if(render_state.register_index >= NUMSIDREGS) {
			render_state.phase = SID_RENDER_FRAME_DELAY;
			render_state.phase_cycles_remaining =
				render_state.frame_cycles_remaining;
			return;
		}

		if(render_state.routine_cycles > 0 &&
				(render_state.register_index == 0 ||
				render_state.register_index == 7 ||
				render_state.register_index == 14)) {
			render_state.phase = SID_RENDER_EXTRA_DELAY;
			render_state.phase_cycles_remaining =
				render_state.routine_cycles;
			return;
		}

		render_state.phase = SID_RENDER_REGISTER_WRITE;
		render_state.phase_cycles_remaining = 0;
	}

	static void sid_begin_render_frame(int samples, const int cyc) {
		render_state.register_index = 0;
		render_state.frame_cycles_remaining =
			clockrate * samples / samplerate;
		render_state.routine_cycles = cyc / 3; // NUMVOICE
		for (int c = 0; c < NUMSIDREGS; c++) {
			render_state.registers[c] = sidreg[c];
		}
		render_state.keyjam_f6_generation = 0;
		int generation = keyjam_f6_generation.load(
			std::memory_order_acquire);
		int control_offset = keyjam_f6_control_offset.load(
			std::memory_order_relaxed);
		if(generation > 0 && control_offset >= 0 &&
				control_offset < NUMSIDREGS &&
				(render_state.registers[control_offset] & 0x01)) {
			int previous_generation =
				keyjam_f6_gate_generation.exchange(generation,
					std::memory_order_acq_rel);
			if(previous_generation != generation)
				keyjam_f6_gate_samples.store(0,
					std::memory_order_release);
			render_state.keyjam_f6_generation = generation;
		}
		sid_prepare_render_phase();
	}

	static int sid_clock_render_phase(short *ptr, int samples,
			bool limit_cycles) {
		if(samples <= 0)
			return 0;
		if(!usefp)
			return sid->clock(render_state.phase_cycles_remaining, ptr, samples);

		int cycles = render_state.phase_cycles_remaining;
		if(limit_cycles) {
			// SIDFP consumes supplied cycles when its output capacity fills.
			long long cycle_capacity =
				static_cast<long long>(samples) * clockrate / samplerate;
			if(cycle_capacity > 0)
				cycle_capacity--;
			if(cycle_capacity < 1)
				cycle_capacity = 1;
			if(cycles > cycle_capacity)
				cycles = static_cast<int>(cycle_capacity);
		}
		int cycles_before = cycles;
		int result = sidfp->clock(cycles, ptr, samples);
		render_state.phase_cycles_remaining -= cycles_before - cycles;
		return result;
	}

	static int sid_renderbuffer_internal(short *ptr, int capacity,
			int frame_samples,
			const int cyc, int *frame_complete, bool limit_cycles) {
		int total = 0;
		if(frame_complete)
			*frame_complete = 0;
		if(capacity < 0 || frame_samples <= 0 || (!ptr && capacity > 0))
			return 0;

		if(render_state.phase == SID_RENDER_IDLE)
			sid_begin_render_frame(frame_samples, cyc);

		while(render_state.phase != SID_RENDER_IDLE) {
			if(render_state.phase == SID_RENDER_REGISTER_WRITE) {
				unsigned char o = sid_getorder(render_state.register_index);
				if(usefp)
					sidfp->write(o, render_state.registers[o]);
				else
					sid->write(o, render_state.registers[o]);
				render_state.phase = SID_RENDER_WRITE_DELAY;
				render_state.phase_cycles_remaining = SIDWRITEDELAY;
			}

			int cycles_before = render_state.phase_cycles_remaining;
			short *output = ptr ? ptr + total : nullptr;
			int produced = sid_clock_render_phase(output,
				capacity - total, limit_cycles);
			if(produced > 0 && render_state.keyjam_f6_generation > 0) {
				int generation = keyjam_f6_generation.load(
					std::memory_order_acquire);
				if(generation == render_state.keyjam_f6_generation &&
						keyjam_f6_gate_generation.load(
							std::memory_order_acquire) ==
						generation)
					keyjam_f6_gate_samples.fetch_add(produced,
						std::memory_order_acq_rel);
			}
			int cycles_consumed = cycles_before -
				render_state.phase_cycles_remaining;
			render_state.frame_cycles_remaining -= cycles_consumed;
			total += produced;

			if(render_state.phase_cycles_remaining == 0) {
				if(render_state.phase == SID_RENDER_EXTRA_DELAY) {
					render_state.phase = SID_RENDER_REGISTER_WRITE;
				}
				else if(render_state.phase == SID_RENDER_WRITE_DELAY) {
					render_state.register_index++;
					sid_prepare_render_phase();
				}
				else {
					sid_reset_render_state();
					if(frame_complete)
						*frame_complete = 1;
				}
			}

			if(produced == 0 && cycles_consumed == 0)
				break;
		}

		return total;
	}

	int sid_renderbuffer(short *ptr, int capacity, int frame_samples,
			const int cyc, int *frame_complete) {
		return sid_renderbuffer_internal(ptr, capacity, frame_samples, cyc,
			frame_complete, true);
	}

	int sid_fillbuffer(short *ptr, int samples, const int cyc) {
		int frame_complete;
		return sid_renderbuffer_internal(ptr, samples, samples, cyc,
			&frame_complete, false);
	}
}
