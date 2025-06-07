# Current developments

## Features & changes

- Also include a direct markdown link to the snippet source file to allow navigation from local sources and not only from github/gitlab
- Always use posix path separators, windows or not

# 0.0.1

First usable version

## Features

- Inject code snippets from a codebase into comment-delimited markdown sections

## Known limitations

### Performance
- The entire source folder is scanned at each invocation
- Probably a plethora of performance issues for large source sets

### Ergonomy
- Extensions/Language mapping is not customizable
- Extensions/Snippet markers mapping is not customizable, effectively limiting support to C-style languages
- A single markdown can be expanded per invocation
- A single source folder can be scanned per invocation