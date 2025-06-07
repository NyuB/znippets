const std = @import("std");
const String = []const u8;
const StringIterator = std.mem.SplitIterator(u8, .sequence);

const Errors = error{
    FileNotFound,
    InvalidUsage,
    SnippetNotFound,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 3) {
        try stdout.print("Usage: {s} <md_file> <snippet_folder>\n", .{args[0]});
        try bw.flush();
        return Errors.InvalidUsage;
    }

    const mdFile = args[1];

    const mdContent = try readFile(allocator, mdFile);
    defer allocator.free(mdContent);

    const mdSnippets = try parseMarkdownSnippets(allocator, mdContent);
    defer mdSnippets.deinit();

    var snippets = FileSnippets.init(allocator);
    defer snippets.deinit();

    var markersByExtension = MarkersByExtension.init(allocator);
    defer markersByExtension.deinit();
    try markersByExtension.put("txt", SnippetMarkers{ .start = "Start:", .end = "End:" });

    try snippets.scan(args[2], markersByExtension);

    var writer = try FileWriter.init(mdFile);
    defer writer.deinit();

    try expandSnippets(mdContent, mdSnippets, &writer, snippets);
}

pub const Snippet = struct {
    /// 0 indexed
    startLine: usize,
    /// 0 indexed
    endLine: usize,

    const Map = struct {
        _map: std.StringHashMapUnmanaged(Snippet),
        arena: std.heap.ArenaAllocator,
        fn init(allocator: std.mem.Allocator) Map {
            return Map{ ._map = std.StringHashMapUnmanaged(Snippet){}, .arena = std.heap.ArenaAllocator.init(allocator) };
        }

        fn get(self: Map, snippetName: String) ?Snippet {
            return self._map.get(snippetName);
        }

        fn contains(self: Map, snippetName: String) bool {
            return self._map.contains(snippetName);
        }

        fn put(self: *Map, snippetName: String, snippet: Snippet) !void {
            const copy = try self.arena.allocator().alloc(u8, snippetName.len);
            std.mem.copyForwards(u8, copy, snippetName);
            try self._map.put(self.arena.allocator(), copy, snippet);
        }

        fn deinit(self: *Map) void {
            self.arena.deinit();
        }

        fn count(self: Map) usize {
            return self._map.count();
        }
    };
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
    const codeFence = "```";

    /// .{ snippetName }
    const headerAnchorFmt = "<a id='snippet-{s}'></a>";

    /// .{ file, startLine, endLine, snippetName }
    const footerReferencesFmt = "<sup><a href='/{s}#L{d}-L{d}' title='Snippet source file'>snippet source</a> | <a href='#snippet-{s}' title='Start of snippet'>anchor</a></sup>";
};

fn readFile(allocator: std.mem.Allocator, file: String) !String {
    var openFile = try std.fs.cwd().openFile(file, .{});
    defer openFile.close();
    const stats = try openFile.stat();
    const result = try allocator.alloc(u8, stats.size);
    _ = try openFile.readAll(result);
    return result;
}

fn fileExtension(fileName: String) String {
    var it = std.mem.splitBackwardsSequence(u8, fileName, ".");
    return it.next() orelse "";
}

fn lines(content: String) StringIterator {
    return std.mem.splitSequence(u8, content, "\n");
}

const LineRangeIterator = struct {
    start: usize,
    /// Inclusive
    end: usize,
    current: usize,
    _iterator: StringIterator,

    fn init(start: usize, end: usize, content: String) LineRangeIterator {
        return LineRangeIterator{ .start = start, .end = end, .current = 0, ._iterator = lines(content) };
    }

    fn next(self: *LineRangeIterator) ?String {
        if (self.current > self.end) return null;
        while (self.current < self.start) {
            self.current += 1;
            _ = self._iterator.next();
        }
        self.current += 1;
        return self._iterator.next();
    }
};

fn expandSnippets(content: String, mdSnippets: MarkdownSnippet.List, writer: anytype, snippets: anytype) !void {
    var lineIndex: usize = 0;
    var lineIterator = lines(content);
    for (mdSnippets.items) |mdSnippet| {
        while (lineIndex <= mdSnippet.startLine) { // Include snippet start
            try writer.writeLine(lineIterator.next() orelse return);
            lineIndex += 1;
        }
        try writer.writeFormattedLine(MarkdownSnippet.headerAnchorFmt, .{mdSnippet.name});
        try writer.writeLine(MarkdownSnippet.codeFence);

        while (lineIndex < mdSnippet.endLine) { // Skip previous content
            lineIndex += 1;
            _ = lineIterator.next();
        }
        var snippet = try snippets.get(mdSnippet.name);
        defer snippet.deinit();
        var snippetLineIterator = snippet.lineIterator();
        while (snippetLineIterator.next()) |snippetLine| {
            try writer.writeLine(snippetLine);
        }

        // Write snippet end
        try writer.writeLine(MarkdownSnippet.codeFence);
        try writer.writeFormattedLine(MarkdownSnippet.footerReferencesFmt, .{ snippet.info.file, snippet.info.snippet.startLine + 1, snippet.info.snippet.endLine + 1, mdSnippet.name });
        try writer.writeLine(lineIterator.next() orelse return);
        lineIndex += 1;
    }
    while (lineIterator.next()) |line| {
        try writer.writeLine(line);
    }
}

const InMemoryWriter = struct {
    lines: std.ArrayList(String),
    allocator: std.mem.Allocator,
    fn init(allocator: std.mem.Allocator) InMemoryWriter {
        return .{ .lines = std.ArrayList(String).init(allocator), .allocator = allocator };
    }

    fn deinit(self: *InMemoryWriter) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit();
    }

    fn writeLine(self: *InMemoryWriter, line: String) !void {
        const copy = try self.allocator.alloc(u8, line.len);
        std.mem.copyForwards(u8, copy, line);
        try self.lines.append(copy);
    }

    fn writeFormattedLine(self: *InMemoryWriter, comptime fmt: String, fmtArgs: anytype) !void {
        const formatted = try std.fmt.allocPrint(self.allocator, fmt, fmtArgs);
        try self.lines.append(formatted);
    }
};

const FileWriter = struct {
    file: std.fs.File,
    first: bool = true,

    fn init(fileName: String) !FileWriter {
        const file = try std.fs.cwd().createFile(fileName, .{});
        return FileWriter{ .file = file };
    }

    fn writeLine(self: *FileWriter, line: String) !void {
        if (!self.first)
            try self.file.writeAll("\n");
        self.first = false;
        try self.file.writeAll(line);
    }

    fn deinit(self: *FileWriter) void {
        self.file.close();
    }

    fn writeFormattedLine(self: *FileWriter, comptime fmt: String, fmtArgs: anytype) !void {
        if (!self.first)
            try self.file.writeAll("\n");
        self.first = false;
        try self.file.writer().print(fmt, fmtArgs);
    }
};

const SnippetMarkers = struct {
    start: String,
    end: String,

    const default = SnippetMarkers{ .start = "// snippet-start", .end = "// snippet-end" };
};

const MarkersByExtension = std.StringHashMap(SnippetMarkers);

const FullSnippetInfo = struct {
    file: String,
    snippet: Snippet,
};

const FileSnippets = struct {
    const Result = struct {
        info: FullSnippetInfo,
        content: String,
        start: usize,
        /// Inclusive
        end: usize,
        deallocate: ?std.mem.Allocator,

        fn init(deallocate: std.mem.Allocator, content: String, info: FullSnippetInfo) Result {
            return Result{ .content = content, .info = info, .start = info.snippet.startLine + 1, .end = info.snippet.endLine - 1, .deallocate = deallocate };
        }

        fn deinit(self: *Result) void {
            if (self.deallocate) |deallocator| deallocator.free(self.content);
        }

        fn lineIterator(self: Result) LineRangeIterator {
            return LineRangeIterator.init(self.start, self.end, self.content);
        }
    };

    const SnippetsByFile = std.StringHashMap(Snippet.Map);

    snippetsByFile: SnippetsByFile,
    allocator: std.mem.Allocator,
    scanAllocator: std.heap.ArenaAllocator,

    fn init(allocator: std.mem.Allocator) FileSnippets {
        return FileSnippets{ .snippetsByFile = SnippetsByFile.init(allocator), .allocator = allocator, .scanAllocator = std.heap.ArenaAllocator.init(allocator) };
    }

    fn scan(self: *FileSnippets, folder: String, markersByExtension: MarkersByExtension) !void {
        var dir = try std.fs.cwd().openDir(folder, std.fs.Dir.OpenDirOptions{ .iterate = true });
        defer dir.close();
        var it = dir.iterateAssumeFirstIteration();
        while (try it.next()) |entry| {
            if (entry.kind == .file) {
                const fullPathToFile = try std.fs.path.join(self.scanAllocator.allocator(), &[_]String{ folder, entry.name });
                const content = try readFile(self.allocator, fullPathToFile);
                std.debug.print("Scanning file {s}, read {d} bytes\n", .{ entry.name, content.len });
                defer self.allocator.free(content);
                const markers = markersByExtension.get(fileExtension(entry.name)) orelse SnippetMarkers.default;
                const snippets = try parseSnippets(self.scanAllocator.allocator(), content, markers.start, markers.end);
                std.debug.print("\tFound {d} snippets\n", .{snippets.count()});
                if (snippets.count() > 0) {
                    var debugIt = snippets._map.keyIterator();
                    while (debugIt.next()) |snippetName| {
                        std.debug.print("\t{s}\n", .{snippetName.*});
                        std.debug.print("\t{d} bytes long (if there is 1 more character, it may very well be a \\r ...\n", .{snippetName.*.len});
                    }
                    try self.put(fullPathToFile, snippets);
                }
            } else if (entry.kind == .directory) {
                const concatenated = try std.fs.path.join(self.allocator, &[_]String{ folder, entry.name });
                defer self.allocator.free(concatenated);
                try self.scan(concatenated, markersByExtension);
            } else {
                std.debug.print("Unknown entry kind: {any} for entry {s}\n", .{ entry.kind, entry.name });
            }
        }
    }

    fn put(self: *FileSnippets, fileName: String, snippets: Snippet.Map) !void {
        try self.snippetsByFile.put(fileName, snippets);
    }

    fn get(self: FileSnippets, snippetName: String) !Result {
        const info = self.getSnippetInfo(snippetName) orelse {
            std.debug.print("Could not find snippet {s}\n", .{snippetName});
            return Errors.SnippetNotFound;
        };
        const content = try readFile(self.allocator, info.file);
        return Result.init(self.allocator, content, info);
    }

    fn getSnippetInfo(self: FileSnippets, snippetName: String) ?FullSnippetInfo {
        var fileNames = self.snippetsByFile.keyIterator();
        while (fileNames.next()) |fileName| {
            const snippetMap = self.snippetsByFile.get(fileName.*).?;
            if (snippetMap.contains(snippetName)) {
                return FullSnippetInfo{ .file = fileName.*, .snippet = snippetMap.get(snippetName).? };
            }
        }
        return null;
    }

    fn deinit(self: *FileSnippets) void {
        self.snippetsByFile.deinit();
        self.scanAllocator.deinit();
    }
};

fn parseSnippets(allocator: std.mem.Allocator, content: String, snippetStart: String, snippetEnd: String) !Snippet.Map {
    var result = Snippet.Map.init(allocator);
    errdefer result.deinit();
    var start: ?struct {
        lineIndex: usize,
        name: String,
    } = null;
    var lineIndex: usize = 0;
    var lineIterator = lines(content);
    while (lineIterator.next()) |line| : (lineIndex += 1) {
        std.debug.print("\tReading line {s}\n", .{line});
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
    var lineIterator = lines(content);
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

test "Expand zero snippet" {
    const source =
        \\Prologue
        \\Epilogue
    ;
    const mdSnippets = try parseMarkdownSnippets(std.testing.allocator, source);
    defer mdSnippets.deinit();

    var testSnippets = TestSnippets.init(std.testing.allocator);
    defer testSnippets.deinit();

    var testWriter = InMemoryWriter.init(std.testing.allocator);
    defer testWriter.deinit();

    try expandSnippets(source, mdSnippets, &testWriter, testSnippets);
    try std.testing.expectEqualDeep(&[_]String{
        "Prologue",
        "Epilogue",
    }, testWriter.lines.items);
}

test "Expand one snippet" {
    const source =
        \\Prologue
        \\<!-- snippet-start X -->
        \\x = 42
        \\<!-- snippet-end -->
        \\Epilogue
    ;
    const mdSnippets = try parseMarkdownSnippets(std.testing.allocator, source);
    defer mdSnippets.deinit();

    var testSnippets = TestSnippets.init(std.testing.allocator);
    defer testSnippets.deinit();
    try testSnippets.put("X", "Expanded\nsnippet");

    var testWriter = InMemoryWriter.init(std.testing.allocator);
    defer testWriter.deinit();

    try expandSnippets(source, mdSnippets, &testWriter, testSnippets);
    try expectLinesEquals(&[_]String{
        "Prologue",
        "<!-- snippet-start X -->",
        "<a id='snippet-X'></a>",
        "```",
        "Expanded",
        "snippet",
        "```",
        "<sup><a href='/<in-memory-for-tests>#L1-L1' title='Snippet source file'>snippet source</a> | <a href='#snippet-X' title='Start of snippet'>anchor</a></sup>",
        "<!-- snippet-end -->",
        "Epilogue",
    }, testWriter.lines.items);
}

test "Expand many snippets" {
    const source =
        \\Prologue
        \\<!-- snippet-start X -->
        \\<a id='snippet-X'></a>
        \\```
        \\x = 42
        \\```
        \\<!-- snippet-end -->
        \\Interlude
        \\<!-- snippet-start Y -->
        \\<a id='snippet-Y'></a>
        \\```
        \\YYY
        \\yyy
        \\yYy
        \\```
        \\<!-- snippet-end -->
        \\Epilogue
    ;
    const mdSnippets = try parseMarkdownSnippets(std.testing.allocator, source);
    defer mdSnippets.deinit();

    var testSnippets = TestSnippets.init(std.testing.allocator);
    defer testSnippets.deinit();
    try testSnippets.put("X", "Expanded\nX");
    try testSnippets.put("Y", "Expanded Y");

    var testWriter = InMemoryWriter.init(std.testing.allocator);
    defer testWriter.deinit();

    try expandSnippets(source, mdSnippets, &testWriter, testSnippets);
    try expectLinesEquals(&[_]String{
        "Prologue",
        "<!-- snippet-start X -->",
        "<a id='snippet-X'></a>",
        "```",
        "Expanded",
        "X",
        "```",
        "<sup><a href='/<in-memory-for-tests>#L1-L1' title='Snippet source file'>snippet source</a> | <a href='#snippet-X' title='Start of snippet'>anchor</a></sup>",
        "<!-- snippet-end -->",
        "Interlude",
        "<!-- snippet-start Y -->",
        "<a id='snippet-Y'></a>",
        "```",
        "Expanded Y",
        "```",
        "<sup><a href='/<in-memory-for-tests>#L1-L1' title='Snippet source file'>snippet source</a> | <a href='#snippet-Y' title='Start of snippet'>anchor</a></sup>",
        "<!-- snippet-end -->",
        "Epilogue",
    }, testWriter.lines.items);
}

test "Expand from file" {
    const source =
        \\<!-- snippet-start X -->
        \\<!-- snippet-end -->
    ;
    const mdSnippets = try parseMarkdownSnippets(std.testing.allocator, source);
    defer mdSnippets.deinit();

    var fileSnippets = FileSnippets.init(std.testing.allocator);
    defer fileSnippets.deinit();

    var markersByExtension = MarkersByExtension.init(std.testing.allocator);
    defer markersByExtension.deinit();
    try markersByExtension.put("txt", SnippetMarkers{ .start = "Start:", .end = "End:" });

    try fileSnippets.scan(adaptOsSeparator("src{[sep]c}test"), markersByExtension);

    var writer = InMemoryWriter.init(std.testing.allocator);
    defer writer.deinit();

    try expandSnippets(source, mdSnippets, &writer, fileSnippets);

    try expectLinesEquals(&[_]String{
        "<!-- snippet-start X -->",
        "<a id='snippet-X'></a>",
        "```",
        "Expanded #1",
        "Expanded #2",
        "```",
        adaptOsSeparator("<sup><a href='/src{[sep]c}test{[sep]c}snippet.txt#L1-L4' title='Snippet source file'>snippet source</a> | <a href='#snippet-X' title='Start of snippet'>anchor</a></sup>"),
        "<!-- snippet-end -->",
    }, writer.lines.items);
}

test "Expand from multiple files" {
    const source =
        \\<!-- snippet-start X -->
        \\<!-- snippet-end -->
        \\<!-- snippet-start Y -->
        \\<!-- snippet-end -->
    ;
    const mdSnippets = try parseMarkdownSnippets(std.testing.allocator, source);
    defer mdSnippets.deinit();

    var fileSnippets = FileSnippets.init(std.testing.allocator);
    defer fileSnippets.deinit();

    var markersByExtension = MarkersByExtension.init(std.testing.allocator);
    defer markersByExtension.deinit();
    try markersByExtension.put("txt", SnippetMarkers{ .start = "Start:", .end = "End:" });

    try fileSnippets.scan("src/test", markersByExtension);

    var writer = InMemoryWriter.init(std.testing.allocator);
    defer writer.deinit();

    try expandSnippets(source, mdSnippets, &writer, fileSnippets);

    try expectLinesEquals(&[_]String{
        "<!-- snippet-start X -->",
        "<a id='snippet-X'></a>",
        "```",
        "Expanded #1",
        "Expanded #2",
        "```",
        adaptOsSeparator("<sup><a href='/src/test{[sep]c}snippet.txt#L1-L4' title='Snippet source file'>snippet source</a> | <a href='#snippet-X' title='Start of snippet'>anchor</a></sup>"),
        "<!-- snippet-end -->",
        "<!-- snippet-start Y -->",
        "<a id='snippet-Y'></a>",
        "```",
        "Nested #1",
        "Nested #2",
        "```",
        adaptOsSeparator("<sup><a href='/src/test{[sep]c}nested{[sep]c}snippet.txt#L1-L4' title='Snippet source file'>snippet source</a> | <a href='#snippet-Y' title='Start of snippet'>anchor</a></sup>"),
        "<!-- snippet-end -->",
    }, writer.lines.items);
}

test "Expand to file" {
    const source =
        \\<!-- snippet-start X -->
        \\<!-- snippet-end -->
    ;
    const mdSnippets = try parseMarkdownSnippets(std.testing.allocator, source);
    defer mdSnippets.deinit();

    var testSnippets = TestSnippets.init(std.testing.allocator);
    defer testSnippets.deinit();
    try testSnippets.put("X", "Expanded\nsnippet");

    var writer = try FileWriter.init("src/test/expanded.md");
    defer writer.deinit();
    defer {
        std.fs.cwd().deleteFile("src/test/expanded.md") catch unreachable;
    }

    try expandSnippets(source, mdSnippets, &writer, testSnippets);
    const expanded = try readFile(std.testing.allocator, "src/test/expanded.md");
    defer std.testing.allocator.free(expanded);

    try std.testing.expectEqualStrings(
        \\<!-- snippet-start X -->
        \\<a id='snippet-X'></a>
        \\```
        \\Expanded
        \\snippet
        \\```
        \\<sup><a href='/<in-memory-for-tests>#L1-L1' title='Snippet source file'>snippet source</a> | <a href='#snippet-X' title='Start of snippet'>anchor</a></sup>
        \\<!-- snippet-end -->
    , expanded);
}

test "Exclude snippet-less files from scan" {
    var fileSnippets = FileSnippets.init(std.testing.allocator);
    defer fileSnippets.deinit();

    try fileSnippets.scan("src/test", MarkersByExtension.init(std.testing.allocator));
    try std.testing.expectEqual(@as(?Snippet.Map, null), fileSnippets.snippetsByFile.get("src/test/no-snippet.txt"));
}

const TestSnippets = struct {
    const Result = struct {
        content: String,
        /// TODO inject actual test info
        info: FullSnippetInfo = .{ .file = "<in-memory-for-tests>", .snippet = .{ .startLine = 0, .endLine = 0 } },

        fn lineIterator(self: Result) StringIterator {
            return lines(self.content);
        }

        fn deinit(_: *Result) void {
            return;
        }
    };

    snippets: std.StringHashMap(String),
    fn init(allocator: std.mem.Allocator) TestSnippets {
        return .{ .snippets = std.StringHashMap(String).init(allocator) };
    }

    fn deinit(self: *TestSnippets) void {
        self.snippets.deinit();
    }

    fn put(self: *TestSnippets, name: String, snippet: String) !void {
        try self.snippets.put(name, snippet);
    }

    fn get(self: TestSnippets, name: String) !Result {
        const snippet = self.snippets.get(name) orelse "";
        return Result{ .content = snippet };
    }
};

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

fn expectLinesEquals(expected: []const String, actual: []const String) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, 0..) |expectedLine, i| {
        try std.testing.expectEqualStrings(expectedLine, actual[i]);
    }
}

fn adaptOsSeparator(comptime s: String) String {
    return std.fmt.comptimePrint(s, .{ .sep = std.fs.path.sep });
}
