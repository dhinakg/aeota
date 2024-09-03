.PHONY: all clean test deploy

SRC_FILES = src/aastuff.m src/aea.m src/args.m src/extract.m src/extract_standalone.m src/utils.m
SRC_FILES_SWIFT =
OBJ_FILES_SWIFT = $(patsubst src/%.swift,obj/%.o,$(SRC_FILES_SWIFT))
HDR_FILES = include/AppleArchivePrivate.h include/OSISAEAExtractor.h \
	include/aea.h include/args.h include/extract.h include/extract_standalone.h include/utils.h $(HDR_SWIFT)

CFLAGS = -fmodules -fobjc-arc -Iinclude -Iobj -Wall -Werror -Wunreachable-code
LDLIBS = -framework Foundation -lAppleArchive
LDFLAGS = -Llib

DEBUG ?= 0
ifeq ($(DEBUG), 1)
	CFLAGS += -g -DDEBUG=1 -O0
endif

HPKE ?= 0
ifeq ($(HPKE), 1)
	CFLAGS += -DHAS_HPKE=1
	SRC_FILES_SWIFT += src/hpke.swift
	HDR_SWIFT = obj/aastuff-Swift.h
endif

all: aastuff aastuff_standalone

obj:
	mkdir -p obj

obj/%.o: src/%.swift | obj
	swiftc -module-name aastuff -parse-as-library -emit-module -emit-module-path obj/$*.swiftmodule -c $< -o $@

$(HDR_SWIFT): $(OBJ_FILES_SWIFT)
	swiftc -module-name aastuff -parse-as-library -emit-objc-header -emit-objc-header-path $@ -emit-module -emit-module-path obj/aastuff.swiftmodule $(subst .o,.swiftmodule,$^)

aastuff: $(SRC_FILES) $(HDR_FILES) $(HDR_SWIFT)
	clang++ $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC_FILES) $(OBJ_FILES_SWIFT) -o $@
	codesign -f -s - $@

aastuff_standalone: $(SRC_FILES) $(OBJ_FILES_SWIFT) $(HDR_FILES) $(HDR_SWIFT)
	clang++ -DAASTUFF_STANDALONE=1 $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC_FILES) $(OBJ_FILES_SWIFT) -o $@
	codesign -f -s - $@

clean:
	rm -rf obj *.dSYM
	rm -f aastuff aastuff_standalone 
