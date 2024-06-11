.PHONY: all clean test deploy

all: aastuff

aastuff: aastuff.m
	clang++ -framework Foundation -fmodules -fobjc-arc -L. -lAppleArchive -g $< -o $@
	codesign -f -s - $@

clean:
	rm -f aastuff

test: aastuff
	./aastuff
