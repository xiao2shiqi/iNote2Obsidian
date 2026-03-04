# iNote2Obsidian

English | [中文](README.zh-CN.md)

## Why This Project

I built this project because I had a real need: continuous, automatic, and low-friction sync from Apple Notes to Obsidian.

After evaluating existing options (official importers, manual export/import, Shortcuts automations, and script-based workflows), I found that most solutions are either one-time migration or semi-automatic, and none provides a mature out-of-the-box always-on sync experience.

So I decided to build one myself and publish it as open source.

## Product Goal (Updated)

Build a **native macOS desktop application** for Apple Notes -> Obsidian sync, with a visual UI and reliable background operation.

## Product Direction

- App form: native macOS app (not a shell script product)
- Sync direction: **Apple Notes -> Obsidian only**
- Priority: reliability first, then UX polish
- Distribution: **GitHub Releases installer package** (not Mac App Store)

## Recommended Tech Stack (Next Stage)

- UI: `SwiftUI` + `AppKit` integration
- Sync core: Swift-native modules
- Notes access: `AppleScript/JXA` bridge
- State store: `SQLite`
- Scheduler/background: `launchd`

## Current Status

The repository currently includes a working CLI sync engine MVP (Python-based) that validates core sync behavior:
- incremental sync
- folder mapping
- markdown + attachment output
- logging + sqlite state

This MVP is the functional base for migration into the native macOS app architecture.

## Distribution Plan

- Build signed macOS installer artifacts via GitHub Actions
- Publish app packages through GitHub Releases
- Provide direct download/install docs in this repository

## Native App Prototype (Current)

A native macOS app prototype has been added under `NativeApp/`.

Build locally:

```bash
cd NativeApp
swift build
```

Run smoke test:

```bash
scripts/native_app_smoke_test.sh
```
