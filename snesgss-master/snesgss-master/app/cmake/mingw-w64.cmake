# Cross-compile the Windows build on Linux with MinGW-w64:
#
#   cmake -S app -B app/build-windows -DCMAKE_TOOLCHAIN_FILE=app/cmake/mingw-w64.cmake
#
# Uses the posix thread model (g++-mingw-w64-x86-64-posix on Debian/Ubuntu),
# since the editor needs std::mutex. MINGW_PREFIX picks another toolchain.
# Tests run under Wine.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(MINGW_PREFIX x86_64-w64-mingw32- CACHE STRING "MinGW-w64 tool prefix")
set(CMAKE_C_COMPILER ${MINGW_PREFIX}gcc-posix)
set(CMAKE_CXX_COMPILER ${MINGW_PREFIX}g++-posix)
set(CMAKE_RC_COMPILER ${MINGW_PREFIX}windres)

set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

find_program(WINE_EXECUTABLE wine)
if(WINE_EXECUTABLE)
	set(CMAKE_CROSSCOMPILING_EMULATOR ${WINE_EXECUTABLE})
endif()
