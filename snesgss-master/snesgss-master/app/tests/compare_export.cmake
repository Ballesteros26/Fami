# Exports PROJECT with SNESGSS into OUT and compares every file with GOLDEN.
# EMULATOR runs the program when it was cross-compiled (wine).
file(REMOVE_RECURSE ${OUT})
file(MAKE_DIRECTORY ${OUT})

execute_process(COMMAND ${EMULATOR} ${SNESGSS} ${PROJECT} -e ${OUT} RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
	message(FATAL_ERROR "snesgss export failed (${rc})")
endif()

file(GLOB expected RELATIVE ${GOLDEN} ${GOLDEN}/*)
file(GLOB actual RELATIVE ${OUT} ${OUT}/*)
list(SORT expected)
list(SORT actual)
if(NOT expected STREQUAL actual)
	message(FATAL_ERROR "file list differs\n expected: ${expected}\n actual:   ${actual}")
endif()

set(failed "")
foreach(f ${expected})
	execute_process(COMMAND ${CMAKE_COMMAND} -E compare_files ${GOLDEN}/${f} ${OUT}/${f} RESULT_VARIABLE diff)
	if(NOT diff EQUAL 0)
		list(APPEND failed ${f})
	endif()
endforeach()

if(failed)
	message(FATAL_ERROR "differs from golden: ${failed}")
endif()
