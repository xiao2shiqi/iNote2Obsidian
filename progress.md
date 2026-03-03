# Progress

## Current Goal
Build an MVP local CLI sync service for Apple Notes -> Obsidian with incremental sync, image support, SQLite state, and launchd scheduling.

## Methods Taken
- Established Python package structure and CLI entrypoints.
- Implemented Apple Notes bridge via `osascript` JXA.
- Implemented parser, markdown transform, writer, and state DB.
- Implemented sync engine orchestration and JSON logs.
- Added launchd template and install/uninstall scripts.

## Completed Steps
- Core modules under `src/inote2obsidian/` created.
- CLI commands `sync/init-config/doctor/status` implemented.
- SQLite schema and tombstone deletion strategy implemented.
- Basic project metadata and env example added.

## Open Issues
- Apple Notes attachment extraction may need environment-specific refinements.
- Add broader integration test coverage on real macOS Notes data.
- Expand documentation for troubleshooting permission prompts.
