# iNote2Obsidian

English | [中文](README.zh-CN.md)

`iNote2Obsidian` is a native macOS menu bar app for one-way sync from Apple Notes to Obsidian.

## Background

This project exists to solve a practical sync problem for people who actively use both Apple Notes and Obsidian.

- It is built for Apple Notes + Obsidian users who want a stable bridge between the two ecosystems.
- It lets users stay on Apple Notes on mobile while using Obsidian and desktop Office workflows for knowledge management on macOS.
- It breaks part of the Apple Notes data silo by exporting notes and attachments into a user-controlled directory.
- It makes Apple Notes content easier to turn into larger documents, archives, and AI-ready context with both text and assets available outside the Notes app.

## Current Product Direction

- Form factor: native macOS app built with `SwiftUI + AppKit`
- Sync direction: `Apple Notes -> Obsidian`
- Interaction model: low-intrusion menu bar utility with settings and sync log
- Priority: reliability first, UX second
- Distribution: GitHub Releases

## v1 Behavior

- Choose an Obsidian vault folder, then run continuous background sync
- Mirror Apple Notes folder structure into the vault
- Export text and supported inline images into Markdown
- Name notes by stable creation timestamp: `yyyyMMdd-HHmmss`
- Reuse the same Markdown file when a note is updated
- Delete the mirrored Markdown and assets when the source note is deleted
- Move mirrored files when Apple Notes folders are renamed or moved
- Store all note assets directly under the shared vault root folder: `attachments/`
- Show sync activity in an in-app sync log

## Repository Layout

- [NativeApp](/Users/phoenix/Documents/workspace/iNote2Obsidian/NativeApp): native macOS app source
- [progress.md](/Users/phoenix/Documents/workspace/iNote2Obsidian/progress.md): product source of truth and iteration log
- [AGENTS.md](/Users/phoenix/Documents/workspace/iNote2Obsidian/AGENTS.md): collaboration rules
- [LICENSE](/Users/phoenix/Documents/workspace/iNote2Obsidian/LICENSE): MIT license

## Build

```bash
cd NativeApp
swift build
```

## Current Implementation Notes

- Sync is implemented as a menu bar app with 1-second polling
- Apple Notes access uses `osascript` + JXA
- State is stored in `SQLite`
- Sync log is written locally and shown in the app UI
- Image extraction currently supports inline HTML image sources that resolve to `data:` URLs or local `file://` URLs

## Known Gaps

- No signed release packaging yet
- No login-item installation yet
- Rich text conversion is intentionally reduced to plain text + images in v1
- Command-line toolchain on this machine can build the app with `swift build`, but does not provide a working Swift test module

## License

This project is released under the MIT License.
