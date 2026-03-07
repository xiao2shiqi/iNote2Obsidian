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
- Added smoke test script `scripts/native_app_smoke_test.sh` and verified:
  - app builds
  - app process launches and stays alive for 3 seconds
- Interaction model upgraded:
  - app opens settings window automatically on startup
  - start/stop controls added with mutual disable logic
  - traffic-light status model added (`red/green/yellow`)
  - yellow state shows last sync error summary
  - syncing wave animation added in settings window
  - menu bar entry retained and can focus the main settings window
- Added realtime monitoring panel in settings window:
  - initially included total/processed/pending counters, recent files, waiting queue, sync rounds, and runtime logs
- Addressed UX feedback:
  - realtime panel now shows explicit "Fetching notes" stage before queue is available
  - Notes bridge now has timeout guard to avoid indefinite hanging
  - settings window activation behavior strengthened (`orderFrontRegardless` + app activate)
  - app launch flow updated: main settings window is now explicitly created at startup
  - menu bar "open main" now directly focuses or creates the same native window instance
- macOS visual refresh iteration completed:
  - Rebuilt `SettingsView` into a layered glass-card layout with stronger hierarchy and spacing
  - Introduced unified typography tokens (SF-based scale for hero/title/body/caption/mono)
  - Added semantic status pill + progress indicator for clearer runtime state visibility
  - Reworked action controls, output path card, sync options, and realtime dashboard sections
  - Reworked menu bar panel with matching visual language and better action grouping
  - Preserved existing sync behavior and view model bindings (UI-only redesign)
- Sync architecture updated again for Apple Notes stability:
  - bridge now streams lightweight note headers first
  - note body fetch is deferred and executed per missing note only
  - target directory presence is determined by markdown `source_note_id`
  - current workaround uses plain-text body export for targeted note content extraction
- Realtime UI simplified again:
  - settings screen realtime panel now shows only `processed` and `pending`
  - removed recent files, waiting queue, and log blocks from the main settings surface
- Verified local sync target for current validation:
  - `/Users/phoenix/Library/Mobile Documents/iCloud~md~obsidian/Documents/life-diary/apple-Notes`
  - Apple Notes count: 275
  - Exported markdown count: 275
  - Missing: 0
  - Extra: 0
  - Duplicate `source_note_id`: 0

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

## Iteration Note (2026-03-05)
- Goal:
  - Improve current UI aesthetics and typography to align closer with a modern macOS desktop feel.
- Approach:
  - Keep all sync logic unchanged in `AppViewModel` and redesign only SwiftUI presentation layers.
  - Use system materials, SF typography hierarchy, and semantic spacing for readability.
- Completed:
  - Updated `NativeApp/Sources/iNote2ObsidianApp/SettingsView.swift`
  - Updated `NativeApp/Sources/iNote2ObsidianApp/MenuContentView.swift`
  - Added a reusable glass-card style modifier and centralized font scale in settings view.
- Remaining:
  - Verify visual details on different macOS appearance/accessibility settings.
  - Add snapshot/UI tests for critical state combinations (idle/syncing/warning/failure).

## Iteration Note (2026-03-05, Localization)
- Goal:
  - Add manual language switching with English default and Simplified Chinese option in NativeApp.
- Approach:
  - Introduce a centralized localizer with key-based translation mapping.
  - Extend settings schema with a persisted language field and backward-compatible decoding.
  - Keep sync logic unchanged and localize UI/status messaging only.
- Completed:
  - Added `AppLanguage` and `AppSettings.language` with legacy JSON fallback to `.english`.
  - Added `AppLocalizer.swift` with `L10nKey` and English/Simplified Chinese dictionaries.
  - Localized `SettingsView` and `MenuContentView`, including a new language picker in Sync Options.
  - Localized status/runtime messages in `AppViewModel` and wired immediate in-app language refresh.
  - Added new unit test file `AppLocalizationTests.swift` for legacy decode fallback and localization key coverage.
  - Verified `swift build` and `scripts/native_app_smoke_test.sh` pass.
- Remaining:
  - Run unit tests via the project’s preferred Xcode test pipeline (CLI `swift test` in this environment lacks test framework module resolution for current setup).

## Iteration Note (2026-03-05, Permission UX)
- Goal:
  - Improve failure diagnostics for Apple Notes automation permission denial.
- Approach:
  - Keep sync logic unchanged and add a UI-level alert path on `permissionDenied`.
- Completed:
  - Added permission alert presentation in `AppViewModel` when `SyncError.permissionDenied` occurs.
  - Added localized alert title/body/button strings in `AppLocalizer` (English + Simplified Chinese).
  - Added deep-link opening to macOS Automation settings pane from alert action.
  - Verified `swift build` and `scripts/native_app_smoke_test.sh` pass.
- Remaining:
  - Improve fetch-stage hang diagnostics (distinguish true permission errors vs long-running/blocked JXA fetch).

## Iteration Note (2026-03-05, Streaming Sync + Exists-Skip)
- Goal:
  - Avoid fetch-stage stalls by moving to streaming note retrieval and apply the policy: if target already has the note, skip writing.
- Approach:
  - Replace bridge bulk JSON return with JSONL-style stream events (`NOTE/HEARTBEAT/DONE`) from a single `osascript` process.
  - Build a local markdown index by `source_note_id` before sync starts.
  - Process each note immediately on arrival, using `source_note_id` existence check for skip behavior.
- Completed:
  - Added streaming bridge API in `NotesBridge` with heartbeat timeout enforcement (30s without heartbeat fails).
  - Added `ExistingNoteIndex` scanner to map `source_note_id -> markdown relative path` (duplicate IDs choose newer mtime).
  - Refactored `SyncEngine` to stream-process notes and enforce `exists => skip` policy.
  - Added UI progress integration for streaming scanned counts (`SCANNED:n`).
  - Added localized messages for streaming fetch and heartbeat timeout handling.
  - Added `ExistingNoteIndexTests.swift` test file for source ID extraction and duplicate selection rule.
  - Verified `swift build` and `scripts/native_app_smoke_test.sh` pass.
- Remaining:
  - Wire a runnable SwiftPM/Xcode test target for NativeApp tests (current package setup reports no test target).

## Iteration Note (2026-03-06, Streaming Parser Hotfix)
- Goal:
  - Fix the zero-note issue after streaming sync rollout.
- Root Cause:
  - In `osascript -l JavaScript`, `console.log` output is emitted to `stderr` instead of `stdout`.
  - The streaming parser initially consumed events from stdout only, causing all NOTE/HEARTBEAT/DONE lines to be missed.
- Completed:
  - Updated `NotesBridge` parser to consume event lines from both stdout and stderr.
  - Added independent stream buffers for stdout and stderr event parsing to avoid line corruption.
  - Preserved non-event stderr lines as error diagnostics.
  - Verified `swift build` and `scripts/native_app_smoke_test.sh` pass.

## Iteration Note (2026-03-07, Header-First Sync Stabilization)
- Goal:
  - Avoid full-run blockage when specific Apple Notes records hang during rich body retrieval.
- Approach:
  - Stream only note headers during the first pass.
  - Fetch note detail lazily for notes that do not already exist in the target directory.
  - Fall back to plain-text body export for the current stable path.
- Completed:
  - Added `SourceNoteHeader` to model the lightweight bridge payload.
  - Refactored `NotesBridge` into `streamNoteHeaders(...)` plus targeted `fetchNoteDetails(...)`.
  - Switched bridge time fields from fragile ISO strings to epoch milliseconds.
  - Revalidated export into `/Users/phoenix/Library/Mobile Documents/iCloud~md~obsidian/Documents/life-diary/apple-Notes`.
  - Compared Apple Notes IDs with exported markdown `source_note_id` values and confirmed `275 = 275`.
  - Repaired one previously missing note (`ICNote/p730`) and backfilled its markdown + SQLite state entry.
- Remaining:
  - Restore attachment/rich-body export on top of the stabilized header-first flow without reintroducing bridge hangs.

## Iteration Note (2026-03-07, Realtime UI Simplification)
- Goal:
  - Reduce settings-screen noise and keep only the progress numbers the user actually needs during sync.
- Approach:
  - Remove detailed runtime surfaces from the main window and keep only processed/pending counters.
- Completed:
  - Simplified `SettingsView` realtime panel to two cards: synced and pending.
  - Removed rounds/total counters, recent files, waiting queue, and log list from the main settings panel.
  - Verified `swift build` and `scripts/native_app_smoke_test.sh` pass after the UI simplification.

## Iteration Note (2026-03-07, Current Planning Handoff)
- Current State:
  - NativeApp currently uses a stabilized header-first sync path: stream note headers first, fetch details only for notes missing from the target directory, and skip existing notes by `source_note_id`.
  - The verified local target is `/Users/phoenix/Library/Mobile Documents/iCloud~md~obsidian/Documents/life-diary/apple-Notes`.
  - Latest manual verification confirmed Apple Notes count and exported markdown count are aligned at `275 = 275`, with no missing, extra, or duplicate `source_note_id` entries.
  - The settings window realtime panel has been intentionally reduced to only two numbers: synced and pending.
- Known Tradeoff:
  - The current stable bridge path prioritizes reliability and uses a plain-text-oriented detail export path; richer body/attachment restoration still needs a safer follow-up design.
- Next Session Starting Point:
  - Treat the current export path and simplified UI as the stable baseline.
  - Begin the next planning round from the remaining product/architecture tradeoffs rather than from sync correctness debugging.

## Iteration Note (2026-03-07, Realtime Pending-State Clarification)
- Goal:
  - Avoid misleading `Processed 0 / Pending 0` display while the app is still scanning Apple Notes and has not calculated the remaining count yet.
- Approach:
  - Keep the simplified two-card realtime panel, but distinguish the scan stage from the queue-ready stage.
- Completed:
  - Added explicit pending-state tracking in `AppViewModel`.
  - Updated the pending card to show `--` plus a `Calculating...` hint until the queue size is known.
  - Added a realtime detail message that explains when Apple Notes is still being scanned and the remaining count is not ready yet.
  - Verified `swift build` and `scripts/native_app_smoke_test.sh` pass.

## Iteration Note (2026-03-07, Single-Pass Sync Throughput Refactor)
- Goal:
  - Remove the `O(n^2)` sync behavior caused by header streaming followed by per-note full Apple Notes re-traversal.
- Approach:
  - Replace the header-first path with a single `osascript` process that streams complete note payloads in one pass.
  - Restrict sync indexing and writes to a fixed managed subdirectory `apple-Notes` under the user-selected vault root.
  - Separate realtime progress semantics into `scanned`, `synced`, and `pending`.
- Completed:
  - Replaced `streamNoteHeaders(...) + fetchNoteDetails(...)` with a single-pass `streamNotes(...)` bridge.
  - Updated JXA payload emission to output note metadata plus `body_plain` in the same traversal, keeping `body_html` optional and empty in the current stable path.
  - Changed `AppSettings.outputRootPath` semantics to vault root and added derived managed output path `apple-Notes`.
  - Updated `SyncEngine` to read/write/index only inside the managed `apple-Notes` directory, avoiding recursive scans across the whole Obsidian vault.
  - Updated the settings UI to show the selected vault root and the effective managed output path.
  - Updated realtime progress UI and view model logic so scan stage shows `Scanned`, while known-total stage shows `Synced` and accurate `Pending`.
  - Verified `swift build` and `scripts/native_app_smoke_test.sh` pass.
- Remaining:
  - Validate perceived speed improvement against a real Apple Notes library and restore richer body/attachment export later without losing the single-pass performance profile.

## Iteration Note (2026-03-07, Stop-Sync Cancellation Fix)
- Goal:
  - Make the `Stop Sync` control actually stop the in-flight sync run instead of only changing UI state.
- Approach:
  - Add a shared cancellation controller from `AppViewModel` down into `SyncEngine` and `NotesBridge`.
  - Terminate the active `osascript` bridge process when cancellation is requested and suppress stale completion callbacks from cancelled runs.
- Completed:
  - Added `SyncCancellationController` and `SyncError.cancelled`.
  - Updated `AppViewModel.stopSyncing()` to cancel the active run, stop the animation, and avoid showing stale success/failure results after a cancelled run exits.
  - Updated `SyncEngine` to check cancellation during note processing and before tombstone cleanup.
  - Updated `NotesBridge.streamNotes(...)` to terminate the running bridge process when cancellation is requested.
  - Verified `swift build` and `scripts/native_app_smoke_test.sh` pass.
