# Current developments

## Features & changes

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