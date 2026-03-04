# Progress

## Project Goal
Deliver a macOS-first, local, reliable sync service that continuously syncs Apple Notes to Obsidian with minimal friction.

### v1 Target
- One-way sync only: Apple Notes -> Obsidian
- Reliability first (CLI + launchd), no GUI
- Incremental sync with clear logs
- Image sync is required
- Markdown output can be fidelity-reduced if needed

## Current Implementation Status

### What is implemented
- Python CLI app with commands:
  - `sync`
  - `init-config`
  - `doctor`
  - `status`
- Apple Notes data fetch via `osascript` (JXA)
- Incremental sync engine with SQLite state tables:
  - `notes_state`
  - `assets_state`
  - `sync_runs`
- Tombstone delete strategy (mark deleted in DB, do not delete target markdown)
- Markdown writer with YAML frontmatter
- JSON line logging for diagnostics
- `launchd` template and install/uninstall scripts

### Folder and file behavior (current)
- Supports full sync (`folder_name: "*"`) and single-folder sync (`folder_name: "Notes"`)
- Output preserves Apple Notes folder hierarchy
- For each synced note folder, attachments are placed in same-level `_attachments/` directory
- Markdown image links use relative paths, e.g.:
  - `![](_attachments/<note_id>/<image_file>)`

### Image handling (current)
- Extracts inline images from Apple Notes HTML body (`data:image/...;base64,...`)
- Writes extracted binaries to attachment files
- Keeps markdown-image references pointing to written files

## Methods Used
- Runtime: Python
- Notes access: JXA via `osascript`
- State/index: SQLite
- Scheduling: macOS `launchd`
- Transform pipeline:
  1. fetch notes
  2. normalize/parse
  3. render markdown
  4. write markdown + attachments atomically
  5. update state and run statistics

## Verified Results (local run)
- Target vault path used:
  - `/Users/phoenix/Library/Mobile Documents/com~apple~CloudDocs/note_repository/iNote`
- After cleanup and resync of `Notes` folder:
  - sync status: success
  - added notes: 274
  - errors: 0
- Output shape confirmed:
  - `.../iNote/Notes/*.md`
  - `.../iNote/Notes/_attachments/...`

## Key Decisions Captured
- English README is default: `README.md`
- Chinese README: `README.zh-CN.md`
- README EN updates should be mirrored to ZH in the same change
- Every code/doc change must be committed and pushed
- When context gets high, summarize handoff into `progress.md`

## Remaining Gaps / Next Iterations
- Improve non-inline attachment extraction (beyond base64 inline images) where Notes/JXA exposes accessible references
- Add stronger path sanitization and collision handling across all folder/name edge cases
- Add integration tests on real-world Notes datasets (nested folders, many images, special characters)
- Add launchd “production setup” guide with troubleshooting for Automation permission prompts
- Add optional cleanup utility for legacy/old output layouts

## Suggested Next Concrete Tasks
1. Add integration test fixtures for nested folder mapping and attachment references
2. Implement `sync --dry-run` to preview adds/updates/deletes without writing
3. Add `cleanup-legacy-output` command for one-time migration from old path layouts
4. Ship a default launchd setup script tied to your current `Notes`-only config
