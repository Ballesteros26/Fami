PREFIX ?= /usr/local
DESTDIR ?=
EXAMPLESDIR ?= $(PREFIX)/share/examples/ccutter
VERSION := $(shell cat VERSION 2>/dev/null || echo "unknown")
DLIBS=-L-ldl -L-lstdc++ -L-lSDL2
DFLAGS=-d-version=DerelictSDL2_Static -I./src -J. -J./src/c64 -J./src/font
CFLAGS=-O2 -std=c99
CXXFLAGS=-O2 -I./src
RESOURCE_OBJS ?=
COMPILE.d = $(DC) $(DFLAGS) -c
DC=ldc2
ACME ?= acme
TARGET=ccutter
ICON_SOURCE=icons/cc2048.png
ICON_SCRIPT=scripts/generate_desktop_icons.py
ICON_OUTPUT_ROOT=build/desktop-icons
SOURCE_RELEASE_SCRIPT=scripts/create_source_release.py
SOURCE_RELEASE_OUTPUT=build/release

include Makefile.objects.mk

.PHONY: install release dist clean dclean tar desktop-icons linux-icons windows-icon source-release linux-build-kit verify-source-release verify-linux-build-kit

%.o: %.d
	$(DC) $(DFLAGS) -c -of=$@ $<

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c -o $@ $<

all: ct2util $(TARGET)

desktop-icons:
	python3 $(ICON_SCRIPT) --source $(ICON_SOURCE) --output $(ICON_OUTPUT_ROOT) --platform all --verify

linux-icons:
	python3 $(ICON_SCRIPT) --source $(ICON_SOURCE) --output $(ICON_OUTPUT_ROOT) --platform linux --verify

windows-icon:
	python3 $(ICON_SCRIPT) --source $(ICON_SOURCE) --output $(ICON_OUTPUT_ROOT) --platform windows --verify

source-release:
	python3 $(SOURCE_RELEASE_SCRIPT) --project-root . --output $(SOURCE_RELEASE_OUTPUT) --kind source

linux-build-kit:
	python3 $(SOURCE_RELEASE_SCRIPT) --project-root . --output $(SOURCE_RELEASE_OUTPUT) --kind linux-build-kit

verify-source-release:
	python3 $(SOURCE_RELEASE_SCRIPT) --project-root . --output $(SOURCE_RELEASE_OUTPUT) --kind verify-source

verify-linux-build-kit:
	python3 $(SOURCE_RELEASE_SCRIPT) --project-root . --output $(SOURCE_RELEASE_OUTPUT) --kind verify-linux-kit

$(TARGET): $(C64OBJS) $(OBJS) $(CXX_OBJS) $(RESOURCE_OBJS)
	$(DC) -of=$@ $(OBJS) $(CXX_OBJS) $(RESOURCE_OBJS) $(DLIBS)

ct: $(C64OBJS) $(CTOBJS)

ct2util: $(C64OBJS) $(UTILOBJS)
	$(DC) -of=$@ $(UTILOBJS)

c64: $(C64OBJS)

install: all
	strip ccutter
	strip ct2util
	install -D -m 755 ccutter $(DESTDIR)$(PREFIX)/bin/ccutter
	install -D -m 755 ct2util $(DESTDIR)$(PREFIX)/bin/ct2util
	install -d $(DESTDIR)$(EXAMPLESDIR)/example_tunes
	cp -r tunes/* $(DESTDIR)$(EXAMPLESDIR)/example_tunes/

# release version with additional optimizations
release: DFLAGS += -frelease -fno-bounds-check
release: all
	strip ccutter
	strip ct2util

# tarred release
dist:	release
	tar --transform 's,^\.,cheesecutter-$(VERSION),' -czf cheesecutter-$(VERSION)-linux-x86.tar.gz $(DIST_FILES)

clean: 
	rm -f *.o *~ resid/*.o resid-fp/*.o ccutter ct2util \
		$(C64OBJS) $(OBJS) $(CTOBJS) $(CXX_OBJS) $(UTILOBJS) $(C_OBJS)
	rm -rf $(ICON_OUTPUT_ROOT) $(SOURCE_RELEASE_OUTPUT)

dclean: clean
	rm -f cheesecutter-$(VERSION)-linux-x86.tar.gz

# tarred source from master
tar:
	git archive master --prefix=cheesecutter-$(VERSION)/ | bzip2 > cheesecutter-$(VERSION)-src.tar.bz2
# --------------------------------------------------------------------------------

src/c64/player.bin: src/c64/player_v4.acme
	$(ACME) -f cbm -Wno-old-for --outfile $@ $<

src/ct/base.o: src/c64/player.bin
src/ui/ui.o: src/ui/help.o
src/com/fb.o src/ct2util.o: VERSION src/com/appversion.d
