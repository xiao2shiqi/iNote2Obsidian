# Progress

## Current Product Goal (Updated)
Build iNote2Obsidian as a **native macOS desktop application** (visual app) for Apple Notes -> Obsidian sync.

### Strategic Direction
- Product form: native macOS app (SwiftUI + AppKit)
- Sync direction: one-way (Apple Notes -> Obsidian)
- Priorities: reliability first, UX second
- Distribution: GitHub Releases installer package
- Not in scope: Mac App Store distribution for now

## Methodology (Continuous Iteration)
This project uses `progress.md` as the continuity document.
Each iteration must update:
- current goal
- methods used
- implemented progress
- open issues and next actions

## What Is Already Implemented (Baseline)
A working CLI MVP exists and is used as the migration baseline.

### Implemented capabilities
- CLI commands: `sync`, `init-config`, `doctor`, `status`
- Apple Notes fetch via `osascript` (JXA)
- Incremental sync with SQLite (`notes_state`, `assets_state`, `sync_runs`)
- Markdown output with frontmatter
- Attachment extraction for inline base64 images
- Folder mapping and `_attachments` co-located directory strategy
- JSON-line logs
- launchd template and install/uninstall scripts

### Current naming and output behavior
- Single-folder sync (`Notes`) and all-folder sync (`*`) supported
- For `Notes` sync, output shape is:
  - `.../iNote/Notes/*.md`
  - `.../iNote/Notes/_attachments/...`
- Markdown filename is timestamp-based (`yyyy-mm-dd hh-mm-ss.md`) using Notes creation timestamp
- Collision handling is in place for same-second filename conflicts

## Verified Local Results (Latest)
- Target path:
  - `/Users/phoenix/Library/Mobile Documents/com~apple~CloudDocs/note_repository/iNote`
- After cleanup + resync (`folder_name: "Notes"`):
  - status: success
  - added: 274
  - errors: 0
- Attachments are preserved and referenced with relative paths

## Current Tech State

### Baseline engine (existing)
- Python + JXA + SQLite + launchd

### Next-stage target stack (native app)
- UI: SwiftUI + AppKit
- Sync core: Swift-native modules (migrate from Python)
- Notes bridge: AppleScript/JXA invocation from Swift
- State store: SQLite
- Background scheduling: launchd

## Native App Implementation Progress (Latest)
- Added a new Swift native app workspace under `NativeApp/`.
- Implemented menu bar app shell with:
  - status icon states (`idle/syncing/success/failed_permission/failed_runtime`)
  - dropdown panel (`Sync Now`, `Settings`, status summary)
  - settings screen (output path, interval, filters, auto-start flag)
- Implemented Swift sync pipeline modules:
  - JXA Notes bridge with recursive folder traversal and `Recently Deleted` exclusion
  - inline image extraction from HTML data URIs
  - markdown renderer with timestamp naming and collision suffix strategy
  - centralized `attachments/` output
  - SQLite state store and incremental sync/tombstone behavior
- Implemented scheduler and sync orchestration with silent failure status handling.
- Added Sparkle updater integration placeholder hook for release wiring.
- Verified the native app target builds successfully with `swift build`.

## Migration Plan (MVP -> Native App)
1. Create macOS app shell (settings, sync status, logs view)
2. Port config/state model from Python to Swift
3. Port sync pipeline (fetch/parse/render/write/state update)
4. Reuse existing behavior contract (folder mapping, attachments, incremental sync)
5. Add menu bar operation and launchd management from UI
6. Add packaging/signing/notarization and GitHub Releases pipeline

## Open Issues / Risks
- Non-inline attachment extraction still needs stronger coverage
- Some Apple Notes/JXA objects can be unstable; bridge needs defensive handling
- Need robust migration strategy from CLI config/state to app-managed config/state
- Need end-to-end app tests for permission prompts and background reliability

## Next Concrete Tasks
1. Scaffold Xcode project (`SwiftUI` app + basic settings window)
2. Define app config schema (vault path, folder selection, schedule, logs)
3. Implement Swift wrapper for existing Notes bridge calls
4. Implement sync run dashboard (last run, added/updated/errors)
5. Set up GitHub Actions for macOS app build artifacts
