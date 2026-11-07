//this file generated with SNES GSS tool

#define SOUND_EFFECTS_ALL	3

#define MUSIC_ALL	11

//sound effect aliases

enum {
	SFX_TEST1=0,
	SFX_SLIDES=1,
	SFX_TEST_VOLUME=2
};

//sound effect names

const char* const soundEffectsNames[SOUND_EFFECTS_ALL]={
	"TEST1",	//0
	"SLIDES",	//1
	"TEST VOLUME"	//2
};

//music effect aliases

enum {
	MUS_PLAYROW=0,
	MUS_JOINING_MATCHING_SAMPLE_DATA=1,
	MUS_DETUNE_TEST_2=2,
	MUS_MODULATION_TEST=3,
	MUS_PORTAMENTO_TEST=4,
	MUS_SINGLE_ROW=5,
	MUS_TEST_DESYNC_ONE=6,
	MUS_TEST_DESYNC_TWO=7,
	MUS_DETUNE_TEST=8,
	MUS_SHORT_LOOP=9,
	MUS_SPEED_CHANGE=10
};

//music names

const char* const musicNames[MUSIC_ALL]={
	"PLAYROW",	//0
	"JOINING MATCHING SAMPLE DATA",	//1
	"DETUNE TEST 2",	//2
	"MODULATION TEST",	//3
	"PORTAMENTO TEST",	//4
	"SINGLE ROW",	//5
	"TEST DESYNC ONE",	//6
	"TEST DESYNC TWO",	//7
	"DETUNE TEST",	//8
	"SHORT_LOOP",	//9
	"SPEED CHANGE"	//10
};

extern const unsigned char spc700_code_1[];
extern const unsigned char spc700_code_2[];
extern const unsigned char music_1_data[];
extern const unsigned char music_2_data[];
extern const unsigned char music_3_data[];
extern const unsigned char music_4_data[];
extern const unsigned char music_5_data[];
extern const unsigned char music_6_data[];
extern const unsigned char music_7_data[];
extern const unsigned char music_8_data[];
extern const unsigned char music_9_data[];
extern const unsigned char music_10_data[];
extern const unsigned char music_11_data[];

const unsigned char* const musicData[MUSIC_ALL]={
	music_1_data,
	music_2_data,
	music_3_data,
	music_4_data,
	music_5_data,
	music_6_data,
	music_7_data,
	music_8_data,
	music_9_data,
	music_10_data,
	music_11_data
};
