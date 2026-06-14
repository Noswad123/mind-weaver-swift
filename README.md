# Mind Weaver for macOS

Mind Weaver for macOS is a native SwiftUI shell around the Go `mw` engine from
MindWeaver.

The app is intentionally not a rewrite of MindWeaver's core logic. Swift owns
the macOS experience; Go owns note indexing, parsing, validation, projections,
and persistence.

```text
Mind Weaver.app / SwiftUI
  -> runs mw JSON commands
  -> renders native note/projection UI

mw / Go engine
  -> reads Markdown notes
  -> indexes SQLite projections
  -> validates domains
  -> exposes stable JSON commands

Markdown notes + SQLite
  -> notes remain the source of truth
  -> SQLite is a derived projection/cache
```

## Current status

This project is a prototype native shell. It currently provides:

- native SwiftUI window/sidebar/detail layout
- note list backed by `mw query notes --format json`
- Markdown preview for selected notes
- `Open in Neovim` button via `wisp nvim <absolute-path>`
- sidebar modes for notes, todos, and file tree browsing
- domain filters backed by `mw query domains`
- todo list backed by `mw query todos`

The app should not parse MindWeaver domain semantics itself. If the UI needs a
new concept, the preferred path is to add a Go-owned projection/JSON command to
`mw`, then render that projection in Swift.

## Requirements

- macOS
- Swift toolchain / Xcode command line tools
- an up-to-date `mw` binary
- optional: `wisp` and `nvim` for editing notes from the app

Make sure your shell resolves `mw` to the updated local binary:

```bash
which mw
mw query help
```

If `which mw` points to an older Homebrew binary, put `~/.local/bin` first:

```bash
export PATH="$HOME/.local/bin:$PATH"
rehash
```

The expected `mw query help` output includes commands such as:

```text
domains
todos
recipes
projection, projections
ingredients
```

## Build and run

From this repository:

```bash
swift build
swift run MindWeaver
```

`swift run MindWeaver` keeps the terminal occupied while the app is open. Quit
the app with `Cmd-Q` to return to the shell.

To open the package in Xcode:

```bash
open Package.swift
```

## Development workflow

There is no React-style hot reload. For a simple watch/restart loop, install
`entr` and run:

```bash
find Sources Package.swift | entr -r swift run MindWeaver
```

## Engine boundary

The app talks to `mw` through `MWCLIEngine`:

```text
Sources/MindWeaver/Engine/MindWeaverEngine.swift
Sources/MindWeaver/Engine/MWCLIEngine.swift
```

The high-level contract is:

```swift
protocol MindWeaverEngine {
    func listNotes(limit: Int, search: String?) async throws -> [MWNote]
    func listDomains() async throws -> [String]
    func listTodos() async throws -> [MWTodo]
    func getNote(id: String) async throws -> MWNote
    func doctor() async throws -> CommandOutput
    func syncNotes() async throws -> CommandOutput
    func validateNotes() async throws -> CommandOutput
}
```

Future app surfaces should follow this pattern:

1. define a projection in MindWeaver/Go
2. expose it through a stable `mw query ...` JSON command
3. add a small Swift model and render it natively

## Current commands used by the app

```bash
mw query notes --format json --limit 5000
mw query notes --format json --id <id>
mw query domains
mw query todos
mw doctor
mw notes sync
mw notes validate --all
```

## Projection direction

MindWeaver domains are composable traits. Some domains describe structure, and
some describe topic/scope.

Examples:

```yaml
domains: [recipe]
domains: [glossary, aviation]
domains: [vocabulary, japanese]
domains: [protocol, biology, mrna]
domains: [checklist, aviation]
```

For current purposes, `recipe` means culinary recipe, so recipe notes do not
need a redundant `cooking` scope domain.

Longer term, the native app can add UI for projections such as:

```bash
mw query projection recipe
mw query projection vocabulary --scope japanese
mw query projection glossary --scope aviation
mw query projection protocol --scope biology,mrna
```

Only the recipe projection is implemented today.
