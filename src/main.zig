//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const String = []const u8;

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // Don't forget to flush!
}

pub const Snippet = struct {
    start: usize,
    end: usize,
};

const SnippetList = std.ArrayList(Snippet);
fn parseSnippets(allocator: std.mem.Allocator, content: String, snippetStart: String, snippetEnd: String) !SnippetList {
    var result = SnippetList.init(allocator);
    errdefer result.deinit();
    var start: ?usize = null;
    var lineIndex: usize = 0;
    var lineIterator = std.mem.splitSequence(u8, content, "\n");
    while (lineIterator.next()) |line| : (lineIndex += 1) {
        if (std.mem.startsWith(u8, line, snippetStart)) {
            start = lineIndex;
        } else if (start != null and std.mem.startsWith(u8, line, snippetEnd)) {
            try result.append(.{ .start = start.?, .end = lineIndex });
            start = null;
        }
    }
    return result;
}

test "Parse zero snippet" {
    const source =
        \\x = 42
    ;
    var result = try parseSnippets(std.testing.allocator, source, "// snippet-start", "snippet-end");
    defer result.deinit();
    try std.testing.expectEqualDeep(&[_]Snippet{}, result.items);
}

test "Parse one snippet" {
    const source =
        \\// snippet-start
        \\x = 42
        \\// snippet-end
    ;
    var result = try parseSnippets(std.testing.allocator, source, "// snippet-start", "// snippet-end");
    defer result.deinit();
    try std.testing.expectEqualDeep(&[_]Snippet{
        .{ .start = 0, .end = 2 },
    }, result.items);
}

test "Parse many snippets" {
    const source =
        \\// snippet-start
        \\x = 42
        \\// snippet-end
        \\Not a snippet line
        \\// snippet-start
        \\y = 0
        \\// snippet-end
    ;
    var result = try parseSnippets(std.testing.allocator, source, "// snippet-start", "// snippet-end");
    defer result.deinit();
    try std.testing.expectEqualDeep(&[_]Snippet{
        .{ .start = 0, .end = 2 },
        .{ .start = 4, .end = 6 },
    }, result.items);
}

test "Ignore dangling starts" {
    const source =
        \\// snippet-start
        \\// snippet-start
        \\y = 0
        \\// snippet-end
    ;
    var result = try parseSnippets(std.testing.allocator, source, "// snippet-start", "// snippet-end");
    defer result.deinit();
    try std.testing.expectEqualDeep(&[_]Snippet{
        .{ .start = 1, .end = 3 },
    }, result.items);
}

test "Ignore dangling ends" {
    const source =
        \\// snippet-start
        \\y = 0
        \\// snippet-end
        \\// snippet-end
    ;
    var result = try parseSnippets(std.testing.allocator, source, "// snippet-start", "// snippet-end");
    defer result.deinit();
    try std.testing.expectEqualDeep(&[_]Snippet{
        .{ .start = 0, .end = 2 },
    }, result.items);
}
