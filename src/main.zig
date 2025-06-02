const std = @import("std");
const String = []const u8;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 2) return;

    const mdFile = args[1];

    const mdContent = try readFile(allocator, mdFile);
    defer allocator.free(mdContent);

    const mdSnippets = try parseMarkdownSnippets(allocator, mdContent);
    defer mdSnippets.deinit();

    try stdout.print("Found {d} snippets in {s}:\n", .{ mdSnippets.items.len, mdFile });
    for (mdSnippets.items) |snippet| {
        try stdout.print("\t{s} ({d} - {d})\n", .{ snippet.name, snippet.startLine + 1, snippet.endLine + 1 });
    }

    try bw.flush(); // Don't forget to flush!
}

pub const Snippet = struct {
    /// 0 indexed
    startLine: usize,
    /// 0 indexed
    endLine: usize,

    const Map = std.StringHashMap(Snippet);
};

pub const MarkdownSnippet = struct {
    name: String,
    /// 0 indexed
    startLine: usize,
    /// 0 indexed
    endLine: usize,

    const List = std.ArrayList(MarkdownSnippet);
    const openStartMarker = "<!-- snippet-start ";
    const closeStartMarker = " -->";
    const endMarker = "<!-- snippet-end -->";
};

fn readFile(allocator: std.mem.Allocator, file: String) !String {
    var openFile = try std.fs.cwd().openFile(file, .{});
    defer openFile.close();
    const stats = try openFile.stat();
    const result = try allocator.alloc(u8, stats.size);
    _ = try openFile.readAll(result);
    return result;
}

fn parseSnippets(allocator: std.mem.Allocator, content: String, snippetStart: String, snippetEnd: String) !Snippet.Map {
    var result = Snippet.Map.init(allocator);
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

fn parseMarkdownSnippets(allocator: std.mem.Allocator, content: String) !MarkdownSnippet.List {
    var result = MarkdownSnippet.List.init(allocator);
    errdefer result.deinit();
    var start: ?struct {
        lineIndex: usize,
        name: String,
    } = null;
    var lineIndex: usize = 0;
    var lineIterator = std.mem.splitSequence(u8, content, "\n");
    while (lineIterator.next()) |line| : (lineIndex += 1) {
        if (std.mem.startsWith(u8, line, MarkdownSnippet.openStartMarker) and std.mem.endsWith(u8, line, MarkdownSnippet.closeStartMarker)) {
            const name = line[MarkdownSnippet.openStartMarker.len .. line.len - MarkdownSnippet.closeStartMarker.len];
            start = .{ .lineIndex = lineIndex, .name = name };
        } else if (start != null and std.mem.eql(u8, MarkdownSnippet.endMarker, line)) {
            try result.append(MarkdownSnippet{ .name = start.?.name, .startLine = start.?.lineIndex, .endLine = lineIndex });
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

test "Parse zero markdown snippet" {
    const source =
        \\x = 42
    ;
    var result = try parseMarkdownSnippets(std.testing.allocator, source);
    defer result.deinit();
    try std.testing.expectEqualDeep(&[_]MarkdownSnippet{}, result.items);
}

test "Parse one markdown snippet" {
    const source =
        \\<!-- snippet-start X -->
        \\x = 42
        \\<!-- snippet-end -->
    ;
    var result = try parseMarkdownSnippets(std.testing.allocator, source);
    defer result.deinit();
    try std.testing.expectEqualDeep(&[_]MarkdownSnippet{
        .{ .name = "X", .startLine = 0, .endLine = 2 },
    }, result.items);
}

test "Parse many markdown snippets" {
    const source =
        \\<!-- snippet-start X -->
        \\x = 42
        \\<!-- snippet-end -->
        \\Not a snippet line
        \\<!-- snippet-start Y -->
        \\y = 0
        \\<!-- snippet-end -->
    ;
    var result = try parseMarkdownSnippets(std.testing.allocator, source);
    defer result.deinit();
    try std.testing.expectEqualDeep(&[_]MarkdownSnippet{
        .{ .name = "X", .startLine = 0, .endLine = 2 },
        .{ .name = "Y", .startLine = 4, .endLine = 6 },
    }, result.items);
}

const SnippetAssertItem = struct {
    name: String,
    snippet: Snippet,
};

fn expectSnippetsEquals(expected: []const SnippetAssertItem, actual: Snippet.Map) !void {
    var expectedMap = Snippet.Map.init(std.testing.allocator);
    defer expectedMap.deinit();
    try std.testing.expectEqual(expected.len, actual.count());
    for (expected) |expectedSnippet| {
        try std.testing.expectEqualDeep(expectedSnippet.snippet, actual.get(expectedSnippet.name));
    }
}
