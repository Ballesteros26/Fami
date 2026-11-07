# Golden export tests: snesgss -e must reproduce the original snesgss.exe
# export byte for byte. They need the editor target (SNESGSS_BUILD_APP). Regenerate goldens with tools/make_golden.sh (needs Wine).

set(GOLDEN_DIR ${CMAKE_CURRENT_SOURCE_DIR}/golden)

file(GLOB GOLDEN_PROJECTS ${SNESGSS_ROOT}/test_projects/*.gsm)
if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/coverage.gsm)
	list(APPEND GOLDEN_PROJECTS ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/coverage.gsm)
endif()

if(NOT TARGET snesgss)
	set(GOLDEN_PROJECTS "")
	message(STATUS "SNESGSS_BUILD_APP is off: skipping the golden export and round trip tests")
endif()

foreach(gsm ${GOLDEN_PROJECTS})
	get_filename_component(name ${gsm} NAME_WE)
	if(NOT IS_DIRECTORY ${GOLDEN_DIR}/${name})
		continue()
	endif()

	add_test(NAME export_${name}
		COMMAND ${CMAKE_COMMAND}
			-DSNESGSS=$<TARGET_FILE:snesgss>
			-DEMULATOR=${CMAKE_CROSSCOMPILING_EMULATOR}
			-DPROJECT=${gsm}
			-DGOLDEN=${GOLDEN_DIR}/${name}
			-DOUT=${CMAKE_CURRENT_BINARY_DIR}/export/${name}
			-P ${CMAKE_CURRENT_SOURCE_DIR}/compare_export.cmake)

	add_test(NAME roundtrip_${name}
		COMMAND ${CMAKE_COMMAND}
			-DSNESGSS=$<TARGET_FILE:snesgss>
			-DEMULATOR=${CMAKE_CROSSCOMPILING_EMULATOR}
			-DPROJECT=${gsm}
			-DOUT=${CMAKE_CURRENT_BINARY_DIR}/roundtrip/${name}.gsm
			-P ${CMAKE_CURRENT_SOURCE_DIR}/compare_roundtrip.cmake)
endforeach()

add_executable(import_test import_test.cpp)
target_link_libraries(import_test PRIVATE gsscore)
add_test(NAME importers COMMAND import_test)

add_executable(editor_test editor_test.cpp)
target_link_libraries(editor_test PRIVATE gsscore)
add_test(NAME song_editor COMMAND editor_test ${SNESGSS_ROOT}/test_projects/test_features.gsm)

add_executable(audio_test audio_test.cpp)
target_link_libraries(audio_test PRIVATE gssaudio)
add_test(NAME tuner COMMAND audio_test)

add_executable(live_test live_test.cpp)
target_link_libraries(live_test PRIVATE gsscore gssaudio)
add_test(NAME live_update COMMAND live_test)
