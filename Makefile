run:
	zig build run -- README.md src
test:
	zig build test

fmt:
	zig fmt src
	zig fmt build.zig
	zig fmt build.zig.zon

