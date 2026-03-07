# iNote2Obsidian

English | [中文](README.zh-CN.md)

`iNote2Obsidian` is a native macOS menu bar app for one-way sync from Apple Notes to Obsidian.

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
- Store note assets under a shared vault root folder: `attachments/`
- Show sync activity in an in-app sync log

## Repository Layout

- [NativeApp](/Users/phoenix/Documents/workspace/iNote2Obsidian/NativeApp): native macOS app source
- [progress.md](/Users/phoenix/Documents/workspace/iNote2Obsidian/progress.md): product source of truth and iteration log
- [AGENTS.md](/Users/phoenix/Documents/workspace/iNote2Obsidian/AGENTS.md): collaboration rules

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
