# Writes a .cpp defining a byte array with the contents of INPUT.
#   cmake -DINPUT=file -DOUTPUT=out.cpp -DSYMBOL=name -P embed_file.cmake
file(READ ${INPUT} hex HEX)
string(LENGTH "${hex}" len)
math(EXPR size "${len} / 2")
string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," bytes "${hex}")
string(REGEX REPLACE "(0x[0-9a-f][0-9a-f],){32}" "\\0\n" bytes "${bytes}")
file(WRITE ${OUTPUT} "// Generated from ${INPUT}\n#include <cstddef>\nextern const unsigned char ${SYMBOL}[] = {\n${bytes}\n};\nextern const size_t ${SYMBOL}_size = ${size};\n")
