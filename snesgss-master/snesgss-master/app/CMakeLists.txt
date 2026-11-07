cmake_minimum_required(VERSION 3.16)

# The oldest macOS supported; must be set before project(). Intel builds go
# back to 10.15 (Catalina, std::filesystem's floor); Apple Silicon starts at 11.
if(CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64")
	set(SNESGSS_MACOS_MIN "10.15")
else()
	set(SNESGSS_MACOS_MIN "11.0")
endif()
set(CMAKE_OSX_DEPLOYMENT_TARGET "${SNESGSS_MACOS_MIN}" CACHE STRING "Oldest macOS the build runs on")

project(snesgss VERSION 1.51 LANGUAGES C CXX)

# This file lives in app/ with all the code it builds; the repository root
# holds the test projects. Configure with: cmake -S app -B app/build
get_filename_component(SNESGSS_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/.. ABSOLUTE)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(SNESGSS_BUILD_APP "Build the SDL3 + Dear ImGui editor" ON)
option(SNESGSS_BUILD_TESTS "Build the tests" ON)

if(MINGW)
	# One self-contained .exe: the MinGW C, C++ and thread runtimes are linked
	# in, so it needs only DLLs that ship with Windows.
	add_link_options(-static -static-libgcc -static-libstdc++)
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
	set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Byte-identical exports depend on plain IEEE double/float arithmetic in the
# BRR encoder: no fused multiply-add, no fast-math reassociation.
if(MSVC)
	set(SNESGSS_FP_FLAGS /fp:precise)
	set(SNESGSS_WARNINGS /W3)
else()
	set(SNESGSS_FP_FLAGS -ffp-contract=off -fno-fast-math)
	set(SNESGSS_WARNINGS -Wall -Wextra)
endif()

add_library(gsscore STATIC
	core/brr.cpp
	core/compiler.cpp
	core/config.cpp
	core/driver.cpp
	core/export.cpp
	core/gsm_io.cpp
	core/importers.cpp
	core/live.cpp
	core/song.cpp
	core/song_editor.cpp
)
target_include_directories(gsscore PUBLIC core)
target_compile_options(gsscore PRIVATE ${SNESGSS_WARNINGS} ${SNESGSS_FP_FLAGS})

# Game_Music_Emu 0.6.0, SPC emulator only (LGPL 2.1, see third_party/gme)
file(GLOB GME_SOURCES third_party/gme/*.cpp)
add_library(gme STATIC ${GME_SOURCES})
target_include_directories(gme PUBLIC third_party/gme)
if(NOT MSVC)
	target_compile_options(gme PRIVATE -w)
endif()

add_library(gssaudio STATIC audio/spc_player.cpp audio/tuner.cpp)
target_include_directories(gssaudio PUBLIC audio)
target_link_libraries(gssaudio PUBLIC gme)
target_compile_options(gssaudio PRIVATE ${SNESGSS_WARNINGS})

if(SNESGSS_BUILD_APP)
	include(FetchContent)

	# Point these at local checkouts to build offline.
	set(SNESGSS_SDL_DIR "" CACHE PATH "Local SDL3 source tree (optional)")
	set(SNESGSS_IMGUI_DIR "" CACHE PATH "Local Dear ImGui source tree (optional)")
	option(SNESGSS_USE_SYSTEM_SDL "Use an installed SDL3 instead of building it" OFF)

	if(SNESGSS_USE_SYSTEM_SDL)
		find_package(SDL3 REQUIRED CONFIG)
	else()
		set(SDL_SHARED OFF CACHE BOOL "" FORCE)
		set(SDL_STATIC ON CACHE BOOL "" FORCE)
		set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
		set(SDL_X11_XTEST OFF CACHE BOOL "" FORCE)  # not needed, avoids a libxtst-dev dependency
		if(SNESGSS_SDL_DIR)
			add_subdirectory(${SNESGSS_SDL_DIR} ${CMAKE_BINARY_DIR}/_deps/sdl-build EXCLUDE_FROM_ALL)
		else()
			FetchContent_Declare(sdl3
				GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
				GIT_TAG release-3.4.16
				GIT_SHALLOW TRUE
				EXCLUDE_FROM_ALL)
			FetchContent_MakeAvailable(sdl3)
		endif()
	endif()

	if(SNESGSS_IMGUI_DIR)
		set(imgui_SOURCE_DIR ${SNESGSS_IMGUI_DIR})
	else()
		FetchContent_Declare(imgui
			GIT_REPOSITORY https://github.com/ocornut/imgui.git
			GIT_TAG v1.92.9b
			GIT_SHALLOW TRUE)
		FetchContent_MakeAvailable(imgui)
	endif()

	add_library(imgui STATIC
		${imgui_SOURCE_DIR}/imgui.cpp
		${imgui_SOURCE_DIR}/imgui_draw.cpp
		${imgui_SOURCE_DIR}/imgui_tables.cpp
		${imgui_SOURCE_DIR}/imgui_widgets.cpp
		${imgui_SOURCE_DIR}/backends/imgui_impl_sdl3.cpp
		${imgui_SOURCE_DIR}/backends/imgui_impl_sdlrenderer3.cpp)
	target_include_directories(imgui PUBLIC ${imgui_SOURCE_DIR} ${imgui_SOURCE_DIR}/backends)
	target_link_libraries(imgui PUBLIC SDL3::SDL3)

	# Fonts shipped with Dear ImGui: Cousine (pattern, monospace) and Roboto
	# (interface), both Apache License 2.0.
	set(FONT_SOURCES "")
	foreach(font Cousine-Regular Roboto-Medium)
		string(REPLACE "-" "_" symbol "font_${font}")
		string(TOLOWER ${symbol} symbol)
		set(out ${CMAKE_BINARY_DIR}/generated/${symbol}.cpp)
		add_custom_command(OUTPUT ${out}
			COMMAND ${CMAKE_COMMAND} -DINPUT=${imgui_SOURCE_DIR}/misc/fonts/${font}.ttf -DOUTPUT=${out} -DSYMBOL=${symbol}
				-P ${PROJECT_SOURCE_DIR}/cmake/embed_file.cmake
			DEPENDS ${imgui_SOURCE_DIR}/misc/fonts/${font}.ttf ${PROJECT_SOURCE_DIR}/cmake/embed_file.cmake
			VERBATIM)
		list(APPEND FONT_SOURCES ${out})
	endforeach()

	file(GLOB APP_SOURCES CONFIGURE_DEPENDS *.cpp)
	if(WIN32)
		enable_language(RC)
		list(APPEND APP_SOURCES snesgss.rc)  # icon and version information
	endif()
	add_executable(snesgss WIN32 MACOSX_BUNDLE ${APP_SOURCES} ${FONT_SOURCES})
	target_include_directories(snesgss PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
	target_link_libraries(snesgss PRIVATE gsscore gssaudio imgui SDL3::SDL3)
	target_compile_options(snesgss PRIVATE ${SNESGSS_WARNINGS})
	set_target_properties(snesgss PROPERTIES
		OUTPUT_NAME snesgss
		MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/cmake/Info.plist.in
		MACOSX_BUNDLE_BUNDLE_NAME "SNES GSS"
		MACOSX_BUNDLE_GUI_IDENTIFIER org.snesgss.editor
		MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
		MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION})
endif()

if(SNESGSS_BUILD_TESTS)
	enable_testing()
	add_subdirectory(tests)
endif()
