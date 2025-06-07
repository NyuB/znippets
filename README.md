# Znippet

[Markdown-snippet](https://github.com/SimonCropp/MarkdownSnippets) but cross-platform without dotnet requirements

## Usage

```shell
$> Znippets README.md src
```
Run Znippets on README.md, looking for snippets in the src/ folder (recursively)

For example, the following snippet was expanded with the above command:

<!-- snippet-start fileExtension -->
<a id='snippet-fileExtension'></a>
```zig
fn fileExtension(fileName: String) String {
    var it = std.mem.splitBackwardsSequence(u8, fileName, ".");
    const res = it.next() orelse return "";
    if (it.next() == null) return ""; // if there is no dot return empty
    return res;
}
```
<sup><a href='/src\main.zig#L113-L120' title='Snippet source file'>snippet source</a> | <a href='#snippet-fileExtension' title='Start of snippet'>anchor</a></sup>
<!-- snippet-end -->
