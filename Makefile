.PHONY: all clean test deploy

SRC_FILES = src/aastuff.m src/extract.m src/extract_standalone.m
HDR_FILES = include/AppleArchivePrivate.h include/extract.h include/extract_standalone.h

CFLAGS = -fmodules -fobjc-arc -Iinclude -Wall -Werror
LDLIBS = -framework Foundation -lAppleArchive
LDFLAGS = -Llib

DEBUG ?= 0
ifeq ($(DEBUG), 1)
	CFLAGS += -g -DDEBUG=1 -O0
endif

all: aastuff aastuff_standalone

aastuff: $(SRC_FILES) $(HDRS_FILES)
	clang++ $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC_FILES) -o $@
	codesign -f -s - $@

aastuff_standalone: $(SRC_FILES) $(HDRS_FILES)
	clang++ -DAASTUFF_STANDALONE=1 $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC_FILES) -o $@
	codesign -f -s - $@

clean:
	rm -f aastuff aastuff_standalone
