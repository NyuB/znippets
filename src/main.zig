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
    /// 0 indexed
    startLine: usize,
    /// 0 indexed
    endLine: usize,
};

const SnippetMap = std.StringHashMap(Snippet);
fn parseSnippets(allocator: std.mem.Allocator, content: String, snippetStart: String, snippetEnd: String) !SnippetMap {
    var result = SnippetMap.init(allocator);
    errdefer result.deinit();
    var start: ?struct {
        lineIndex: usize,
        name: String,
    } = null;
    var lineIndex: usize = 0;
    var lineIterator = std.mem.splitSequence(u8, content, "\n");
    while (lineIterator.next()) |line| : (lineIndex += 1) {
        if (std.mem.startsWith(u8, line, snippetStart)) {
            var name: String = "";
            if (line.len > snippetStart.len + 1) {
                name = line[snippetStart.len + 1 ..];
            }
            start = .{ .lineIndex = lineIndex, .name = name };
        } else if (start != null and std.mem.startsWith(u8, line, snippetEnd)) {
            try result.put(start.?.name, Snippet{ .startLine = start.?.lineIndex, .endLine = lineIndex });
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
    try expectSnippetsEquals(&[_]SnippetAssertItem{}, result);
}

test "Parse one snippet" {
    const source =
        \\// snippet-start X
        \\x = 42
        \\// snippet-end
    ;
    var result = try parseSnippets(std.testing.allocator, source, "// snippet-start", "// snippet-end");
    defer result.deinit();
    try expectSnippetsEquals(&[_]SnippetAssertItem{
        .{ .name = "X", .snippet = Snippet{ .startLine = 0, .endLine = 2 } },
    }, result);
}

test "Parse many snippets" {
    const source =
        \\// snippet-start X
        \\x = 42
        \\// snippet-end
        \\Not a snippet line
        \\// snippet-start Y
        \\y = 0
        \\// snippet-end
    ;
    var result = try parseSnippets(std.testing.allocator, source, "// snippet-start", "// snippet-end");
    defer result.deinit();
    try expectSnippetsEquals(&[_]SnippetAssertItem{
        .{ .name = "X", .snippet = Snippet{ .startLine = 0, .endLine = 2 } },
        .{ .name = "Y", .snippet = Snippet{ .startLine = 4, .endLine = 6 } },
    }, result);
}

test "Ignore dangling starts" {
    const source =
        \\// snippet-start X
        \\// snippet-start Y
        \\y = 0
        \\// snippet-end
    ;
    var result = try parseSnippets(std.testing.allocator, source, "// snippet-start", "// snippet-end");
    defer result.deinit();
    try expectSnippetsEquals(&[_]SnippetAssertItem{
        .{ .name = "Y", .snippet = Snippet{ .startLine = 1, .endLine = 3 } },
    }, result);
}

test "Ignore dangling ends" {
    const source =
        \\// snippet-start Y
        \\y = 0
        \\// snippet-end
        \\// snippet-end
    ;
    var result = try parseSnippets(std.testing.allocator, source, "// snippet-start", "// snippet-end");
    defer result.deinit();
    try expectSnippetsEquals(&[_]SnippetAssertItem{
        .{ .name = "Y", .snippet = Snippet{ .startLine = 0, .endLine = 2 } },
    }, result);
}

const SnippetAssertItem = struct {
    name: String,
    snippet: Snippet,
};

fn expectSnippetsEquals(expected: []const SnippetAssertItem, actual: SnippetMap) !void {
    var expectedMap = SnippetMap.init(std.testing.allocator);
    defer expectedMap.deinit();
    try std.testing.expectEqual(expected.len, actual.count());
    for (expected) |expectedSnippet| {
        try std.testing.expectEqualDeep(expectedSnippet.snippet, actual.get(expectedSnippet.name));
    }
}
