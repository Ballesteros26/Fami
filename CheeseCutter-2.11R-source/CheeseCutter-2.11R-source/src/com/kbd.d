/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module com.kbd;
import derelict.sdl2.sdl;
import ui.input : Keyinfo;

void translate(ref Keyinfo key) {
	version(OSX)
		translateCommandModifier(key);
}

version(OSX) private void translateCommandModifier(ref Keyinfo key) {
	if(key.mods & KMOD_GUI) {
		// Keep canonical macOS LOOP shortcuts distinct:
		// Command-Option-L is all voices, Shift-Command-Option-L is active voice.
		if(key.key == SDLK_l && (key.mods & KMOD_ALT))
			return;
        switch(key.key) {
        case SDLK_1: key.key = SDLK_KP_1; break;
        case SDLK_2: key.key = SDLK_KP_2; break;
        case SDLK_3: key.key = SDLK_KP_3; break;
        case SDLK_4: key.key = SDLK_KP_4; break;
        case SDLK_5: key.key = SDLK_KP_5; break;
        case SDLK_6: key.key = SDLK_KP_6; break;
        case SDLK_7: key.key = SDLK_KP_7; break;
        case SDLK_8: key.key = SDLK_KP_8; break;
        case SDLK_9: key.key = SDLK_KP_9; break;
		case SDLK_UP: key.mods = KMOD_SHIFT; key.key = SDLK_HOME; break;
		case SDLK_DOWN: key.mods = KMOD_SHIFT; key.key = SDLK_END; break;
        default: // otherwise just translate to ctrl+shift...                                                                       
            key.mods |= KMOD_CTRL | KMOD_SHIFT;
            break;
        }
		key.mods &= ~KMOD_GUI; // meta off
	}
}
