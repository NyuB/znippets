run:
	zig build run -- README.md
test:
	zig build test

fmt:
	zig fmt src
	zig fmt build.zig
	zig fmt build.zig.zon

