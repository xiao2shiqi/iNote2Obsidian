# iNote2Obsidian

English | [中文](README.zh-CN.md)

## Why This Project

I built this project because I had a real need: continuous, automatic, and low-friction sync from Apple Notes to Obsidian.

After evaluating existing options (official importers, manual export/import, Shortcuts automations, and script-based workflows), I found that most solutions are either one-time migration or semi-automatic, and none provides a mature out-of-the-box always-on sync experience.

So I decided to build one myself and publish it as open source.

## Project Goal

Build a reliable and low-friction sync tool that copies diary notes from Apple Notes to a target folder in Obsidian, including:
- Note text
- Embedded images/attachments

## Scope (v1)

- Sync direction: **Apple Notes -> Obsidian only**
- No write-back to Apple Notes
- Focus on stability and smooth background sync on macOS

## Preferred v1 Shape

- Local CLI sync engine
- macOS `launchd` (LaunchAgent) scheduled background runs

This is preferred over starting with an Obsidian plugin or desktop GUI, because it is more stable and less dependent on app lifecycle.

## Technical Stack (v1)

- `Python 3.12`: sync engine
- `osascript` (JXA/AppleScript): read Apple Notes data
- `SQLite`: sync state/index (incremental sync, dedup, hashes)
- `launchd`: background scheduling
- Markdown + assets files: output format for Obsidian vault

## v1 Quality Bar

- Stability first
- Rich text formatting may be downgraded to Markdown when needed
- Image sync is required
- Incremental sync and observable logs are required
