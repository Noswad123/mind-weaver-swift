# Mind Weaver for macOS

Mind Weaver for macOS is a native SwiftUI shell around the Go `mw` engine from
MindWeaver.

The app is intentionally not a rewrite of MindWeaver's core logic. Swift owns
the macOS experience; Go owns note indexing, parsing, validation, projections,
todo mutation, graph data, and persistence.

```text
Mind Weaver.app / SwiftUI
  -> runs mw JSON commands
  -> renders native note/projection/graph UI

mw / Go engine
  -> reads Markdown notes
  -> indexes SQLite projections
  -> validates domains
  -> mutates source-backed todos
  -> exposes stable JSON commands

Markdown notes + SQLite
  -> notes remain the source of truth
  -> SQLite is a derived projection/cache
```

## Current status

This project is a prototype native macOS shell. It currently provides:

- native SwiftUI `NavigationSplitView` layout
- startup dashboard overlay with Mind Weaver artwork
- note list backed by `mw query notes --format json`
- formatted Markdown preview for selected notes
- clickable internal Markdown links and Obsidian-style wikilinks
- `Open in Neovim` via `wisp nvim <absolute-path>`
- `Reveal in Finder`
- sidebar modes for Notes, Todos, File Tree, and Graph
- domain filters backed by `mw query domains`
- source-backed todo list and inspector backed by `mw query todos`
- todo completion and metadata edits through `mw todos ...` commands
- real note graph backed by `mw query graph`
- graph domain coloring and client-side domain node filtering
- graph zoom/pan/fit, node dragging, graph focus, and connected-node sidebar
- animated magical memory-loom logo that changes color during app work and graph layout
- tabbed Settings window with a Keyboard Shortcuts tab

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

## App icon

For the Xcode macOS app target, generate the app icon from a square 1024×1024
PNG source image:

```bash
scripts/generate-macos-appicon.sh path/to/brain-mage-hat-1024.png
```

The script writes the required icon sizes and `Contents.json` to:

```text
MindWeaver/MindWeaver/Assets.xcassets/AppIcon.appiconset
```

Suggested source artwork: a stylized luminous brain wearing a purple mage hat,
with subtle golden memory-thread or loom glow, no text, centered on a dark
indigo background.

## Development workflow

There is no React-style hot reload. For a simple watch/restart loop, install
`entr` and run:

```bash
find Sources Package.swift | entr -r swift run MindWeaver
```

The app bundles resources through SwiftPM:

```text
Sources/MindWeaver/Resources/mind-weaver.png
```

That image is used by the startup dashboard.

## Dashboard

The app starts on a dashboard overlay. The dashboard uses the Mind Weaver artwork
as its background and presents:

- 5 recently viewed notes
- 5 highest-priority incomplete tasks

The lists straddle the central Mind Weaver artwork. Selecting a recent note or
priority task dismisses the dashboard and enters the relevant app mode.

Dashboard behavior:

- `Cmd-D` opens or closes the dashboard.
- The titlebar memory-loom logo also opens or closes the dashboard.
- Dismissal rolls/moves the dashboard upward with a fade.
- The window toolbar is hidden while the dashboard is visible.

## Notes

Notes are loaded through:

```bash
mw query notes --format json --limit 5000
mw query notes --format json --id <id>
```

The detail view provides:

- formatted Markdown preview
- source path display
- `Open in Neovim`
- `Reveal in Finder`
- clickable internal links

Supported preview links:

- `[[note-id]]`
- `[[note-id|Label]]`
- `[[note-id#Heading]]`
- `[Label](relative/path.md)`
- `[Label](note-id)`
- `[Label](note-title-or-basename)`

External links such as `https://...`, `mailto:...`, and `tel:...` use system
handling. Internal note links resolve against note `id`, `uid`, `title`, full
path, relative path from the current note, basename, and basename without `.md`.

## Todos

Todos are source-backed task-index projections. Swift does not edit Markdown
todo lines directly; it calls `mw` commands.

Todo features:

- todo list backed by `mw query todos`
- independent todo selection
- completion toggle through `mw todos toggle --id <todo-id>`
- inspector for title, area, priority, energy, weight override, due, start,
  estimate, and raw metadata
- bulk metadata edits for selected todos
- source note navigation from the todo inspector
- dashboard shows the 5 highest-priority incomplete tasks

Task status colors:

- Inbox: gray
- Next: blue
- Waiting: yellow
- Blocked: red
- Done: green

## File tree

The File Tree sidebar mode renders the loaded notes as a native outline tree.
Selecting a file opens the note preview.

## Domains and filters

Domains are loaded through:

```bash
mw query domains
```

Domain filter chips use deterministic pseudo-random colors. When multiple
domains are selected, selected chips use the average RGB value of those domain
colors.

Filtering behavior differs by surface:

- Notes/Todos: selected domains narrow visible note-derived results.
- Graph: selected domains filter graph nodes using OR semantics; edges remain
  visible only when both endpoints are still visible.

## Graph

The Graph mode is backed by:

```bash
mw query graph --depth <n> --limit <n>
```

Graph features:

- Canvas-based renderer for performance
- real graph nodes and edges from the Go backend
- node labels use frontmatter/note UID labels from `mw`
- missing/unknown labels render red as `unknown`
- deterministic domain colors for graph nodes
- multi-domain nodes use the graph-wide most popular domain color
- selected node highlighted gold
- connected nodes highlighted cyan
- selected/connected edges highlighted white
- connected-node count in the graph sidebar
- graph focus is separate from note selection
- click black space to clear graph focus and selection
- graph sidebar sections for Selected, Connected, and Results
- Enter Selected Node from the graph sidebar
- Fit button zooms to rendered node bounds

Layout behavior:

- topology-aware radial BFS seed layout
- large hubs are placed first
- child/subtree counts allocate angular sectors
- background actor solves force layout off the main actor
- staged quick/refined solve for faster perceived response
- soft parent/child orbit constraints keep children near hubs
- hub/body repulsion reduces dense cluster overlap
- circular boundary constraint avoids rectangular edge artifacts
- curved edges fan outward for a more organic visual style

Graph interactions:

- `Cmd` + scroll: zoom around pointer
- pinch: zoom around hover position
- `Cmd` + drag: pan graph
- drag node: move node
- click node: focus/select node
- click empty graph space: clear focus/selection

## Settings

Settings are organized into tabs:

- Engine: resolved `mw` binary, source, executable status, doctor
- Development: rebuild/delete local `~/.local/bin/mw`
- Notes: notes directory
- Shortcuts: keyboard shortcut reference
- Output: last command output

The Settings gear uses a retained AppKit fallback window because `Cmd-,` routing
can be unreliable when launched via `swift run`.

## Keyboard shortcuts

Global shortcuts:

| Shortcut | Action |
| --- | --- |
| `Cmd-D` | Open/close dashboard |
| `Cmd-S` | Toggle sidebar open/closed |
| `Cmd-R` | Refresh notes |
| `Shift-Cmd-S` | Run `mw notes sync` |
| `Cmd-,` | Open Settings |

Graph shortcuts/interactions:

| Shortcut / gesture | Action |
| --- | --- |
| `Return` | Enter selected graph node from sidebar |
| `Cmd` + scroll | Zoom around pointer |
| Pinch | Zoom around hover position |
| `Cmd` + drag | Pan graph |
| Drag node | Move graph node |

## Engine boundary

The app talks to `mw` through `MWCLIEngine`:

```text
Sources/MindWeaver/Engine/MindWeaverEngine.swift
Sources/MindWeaver/Engine/MWCLIEngine.swift
```

The high-level contract is:

```swift
protocol MindWeaverEngine {
    func binaryStatus() async -> MWBinaryStatus
    func listNotes(limit: Int, search: String?) async throws -> [MWNote]
    func listDomains() async throws -> [String]
    func listTodos() async throws -> [MWTodo]
    func queryGraph(search: String?, domain: String?, depth: Int, limit: Int) async throws -> MWGraph
    func toggleTodo(id: String) async throws -> CommandOutput
    func updateTodos(ids: [String], patch: MWTodoUpdatePatch) async throws -> CommandOutput
    func getNote(id: String) async throws -> MWNote
    func doctor() async throws -> CommandOutput
    func syncNotes() async throws -> CommandOutput
    func validateNotes() async throws -> CommandOutput
    func rebuildLocalBinary() async throws -> CommandOutput
    func deleteLocalBinary() async throws -> CommandOutput
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
mw query graph --depth <depth> --limit <limit>
mw todos toggle --id <todo-id>
mw todos update --id <todo-id> ...
mw doctor
mw notes sync
mw notes validate --all
tsync --only mw
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

Only the recipe projection has dedicated projection support today.
