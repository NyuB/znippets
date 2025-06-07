RELEASE_MODE=ReleaseSmall
INSTALL_PREFIX=$(CURDIR)/install

run:
	zig build run -- README.md src
test:
	zig build test
install:
	zig build --prefix $(INSTALL_PREFIX) -Doptimize=$(RELEASE_MODE)

fmt:
	zig fmt src
	zig fmt build.zig
	zig fmt build.zig.zon

