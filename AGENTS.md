# AGENTS.md

## Product Intent

iNote2Obsidian is a macOS-first sync project to copy diary notes from Apple Notes into Obsidian with minimal user friction.

## Confirmed Decisions

- Sync direction is one-way: **Apple Notes -> Obsidian**
- v1 focuses on reliability before UI polish
- v1 form factor is a local CLI-based sync service + `launchd` scheduler

## Technical Baseline (v1)

- Runtime: `Python 3.12`
- Apple Notes access: `osascript` (JXA/AppleScript)
- State store: `SQLite`
- Scheduler: macOS `launchd` (LaunchAgent)
- Output: Markdown notes + image/asset files in Obsidian vault

## Quality Requirements

- Must support incremental sync
- Must provide clear logs for success/failure diagnosis
- Rich text may be downgraded to Markdown in v1
- Image synchronization is mandatory

## Out of Scope (v1)

- Two-way sync
- Write-back from Obsidian to Apple Notes
- Full-fidelity rich text parity
- Desktop GUI as initial delivery

## Collaboration Rule for Future Sessions

When discussing product scope, use Socratic questioning to clarify assumptions, constraints, tradeoffs, and measurable success criteria before implementation.

## Git Workflow Rule

After each code or documentation change, commit the change and push to the remote repository.

## README Sync Rule

`README.md` is the default English document and `README.zh-CN.md` is the Chinese document.
When updating `README.md`, sync equivalent changes to `README.zh-CN.md` in the same update.
