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
- Single configured Apple Notes folder
- Tombstone-only deletion handling (do not auto-delete Obsidian files)
- Focus on stability and smooth background sync on macOS

## Technical Stack (v1)

- `Python 3.12`
- `osascript` (JXA/AppleScript)
- `SQLite`
- `launchd` (LaunchAgent)
- Markdown + assets files

## Installation

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
```

## Initialize Config

```bash
inote2obsidian init-config --output ./config.yaml
```

Then edit `config.yaml` and set:
- `apple_notes.folder_name`
- `obsidian.vault_path`
- `state.db_path`
- `logging.file_path`

## Run Commands

```bash
inote2obsidian doctor --config ./config.yaml
inote2obsidian sync --config ./config.yaml
inote2obsidian status --config ./config.yaml
```

## launchd (every 5 minutes)

```bash
scripts/install_launchd.sh \
  "$PWD/.venv/bin/python" \
  "$PWD/config.yaml" \
  "$PWD/.inote2obsidian/stdout.log" \
  "$PWD/.inote2obsidian/stderr.log" \
  "$HOME/Library/LaunchAgents/com.inote2obsidian.sync.plist"
```

Unload/remove:

```bash
scripts/uninstall_launchd.sh "$HOME/Library/LaunchAgents/com.inote2obsidian.sync.plist"
```

## Notes

- On first run, macOS may prompt Automation permission for terminal/Python to access Notes.
- Markdown rendering is reliability-first in v1; rich text can be degraded.
- Attachment extraction from Apple Notes may require environment-specific tuning.
