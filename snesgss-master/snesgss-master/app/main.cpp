// Entry point. Uses SDL's callback main loop, which also suits a future
// Emscripten build.
//
//   snesgss [project.gsm]   open the editor
//   snesgss project.gsm -e  and the other command line modes, see command_line.h
#define SDL_MAIN_USE_CALLBACKS 1
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include "app.h"
#include "command_line.h"
#include "imgui.h"
#include "imgui_impl_sdl3.h"
#include "imgui_impl_sdlrenderer3.h"

namespace {

struct State {
	SDL_Window* window = nullptr;
	SDL_Renderer* renderer = nullptr;
	gss::App* app = nullptr;
};

}  // namespace

SDL_AppResult SDL_AppInit(void** appstate, int argc, char** argv)
{
	if (gss::is_command_line(argc, argv)) return gss::run_command_line(argc, argv) == 0 ? SDL_APP_SUCCESS : SDL_APP_FAILURE;

	SDL_SetAppMetadata("SNES GSS", "1.51", "org.snesgss.editor");

	if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO)) {
		SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "SNES GSS", SDL_GetError(), nullptr);
		return SDL_APP_FAILURE;
	}

	State* st = new State;
	*appstate = st;

	const float scale = SDL_GetDisplayContentScale(SDL_GetPrimaryDisplay());
	st->window = SDL_CreateWindow("SNES GSS", (int)(1280 * (scale > 0 ? scale : 1)), (int)(800 * (scale > 0 ? scale : 1)),
	                              SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIDDEN | SDL_WINDOW_HIGH_PIXEL_DENSITY);
	if (!st->window) {
		SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "SNES GSS", SDL_GetError(), nullptr);
		return SDL_APP_FAILURE;
	}
	st->renderer = SDL_CreateRenderer(st->window, nullptr);
	if (!st->renderer) {
		SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "SNES GSS", SDL_GetError(), st->window);
		return SDL_APP_FAILURE;
	}
	SDL_SetRenderVSync(st->renderer, 1);
	SDL_SetWindowPosition(st->window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
	SDL_ShowWindow(st->window);

	IMGUI_CHECKVERSION();
	ImGui::CreateContext();

	st->app = new gss::App;
	if (!st->app->init(st->window, st->renderer, argc, argv)) return SDL_APP_FAILURE;

	return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppEvent(void* appstate, SDL_Event* event)
{
	State* st = static_cast<State*>(appstate);
	st->app->event(*event);
	return st->app->quit_requested() ? SDL_APP_SUCCESS : SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppIterate(void* appstate)
{
	State* st = static_cast<State*>(appstate);
	if (SDL_GetWindowFlags(st->window) & SDL_WINDOW_MINIMIZED) {
		SDL_Delay(10);
		return SDL_APP_CONTINUE;
	}
	st->app->frame();
	return st->app->quit_requested() ? SDL_APP_SUCCESS : SDL_APP_CONTINUE;
}

void SDL_AppQuit(void* appstate, SDL_AppResult)
{
	State* st = static_cast<State*>(appstate);
	if (!st) return;
	delete st->app;
	if (ImGui::GetCurrentContext()) {
		ImGui_ImplSDLRenderer3_Shutdown();
		ImGui_ImplSDL3_Shutdown();
		ImGui::DestroyContext();
	}
	if (st->renderer) SDL_DestroyRenderer(st->renderer);
	if (st->window) SDL_DestroyWindow(st->window);
	delete st;
}
