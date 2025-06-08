# Znippet

[Markdown-snippet](https://github.com/SimonCropp/MarkdownSnippets) but cross-platform without dotnet requirements

## Usage

Define where to look for snippets in a [znippets.json](znippets.json) file (folders are scanned recursively)

```
{
    "snippetFiles": [
        "Makefile"
    ],
    "snippetFolders": [
        "src"
    ]
}
```

Then invoke Znippets, passing the markdowns to format as arguments

```shell
$> Znippets README.md
```

It will expand all snippet sections in the markdown with the actual content from your sources.

For example, the following snippet was expanded with the above command:

<!-- snippet-start fileExtension -->
<a id='snippet-fileExtension'></a>
```zig
fn fileExtension(fileName: String) String {
    var it = std.mem.splitBackwardsSequence(u8, fileName, ".");
    return it.next() orelse "";
}
```
<sup>[source file](src/main.zig) | </sup>
<sup><a href='/src/main.zig#L128-L133' title='Snippet source'>source (github)</a> | <a href='#snippet-fileExtension' title='Start of snippet'>anchor</a></sup>
<!-- snippet-end -->

### Enforcing valid snippets

Znippets only updates the markdown in place and does not enforce that they were well formatted. One way to do it, e.g. in ci, is to run znippets then check that it did not modify the markdown:

<!-- snippet-start git-diff-exit-code -->
<a id='snippet-git-diff-exit-code'></a>
```
	$(INSTALL_PREFIX)/bin/Znippets README.md src
	git diff --exit-code README.md
```
<sup>[source file](Makefile) | </sup>
<sup><a href='/Makefile#L38-L41' title='Snippet source'>source (github)</a> | <a href='#snippet-git-diff-exit-code' title='Start of snippet'>anchor</a></sup>
<!-- snippet-end -->
