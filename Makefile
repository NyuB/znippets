RELEASE_MODE=ReleaseSmall
INSTALL_PREFIX=$(CURDIR)/install
ZIG=zig

run:
	$(ZIG) build run -- README.md src
test:
	$(ZIG) build test
install:
	$(ZIG) build --prefix $(INSTALL_PREFIX) -Doptimize=$(RELEASE_MODE)

fmt:
	$(ZIG) fmt src
	$(ZIG) fmt build.zig
	$(ZIG) fmt build.zig.zon

