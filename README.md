# iNote2Obsidian

English | [中文](#中文)

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

## 中文

## 项目目标

做一个稳定、低感知的同步工具，把 Apple 备忘录中的日记同步到 Obsidian 指定目录，包含：
- 文字内容
- 图片/附件

## v1 范围

- 同步方向：**仅 Apple Notes -> Obsidian**
- 不回写 Apple Notes
- 优先保证在 macOS 上后台稳定同步

## v1 形态

- 本地 CLI 同步引擎
- `launchd`（LaunchAgent）定时后台执行

相比先做 Obsidian 插件或桌面 GUI，这个方案更稳定、对应用生命周期依赖更小。

## v1 技术栈

- `Python 3.12`：同步核心逻辑
- `osascript`（JXA/AppleScript）：读取 Apple Notes
- `SQLite`：同步状态与增量索引
- `launchd`：后台调度
- Markdown + 资源文件：写入 Obsidian 仓库

## v1 质量标准

- 稳定优先
- 富文本样式可在必要时降级为 Markdown
- 图片同步必须成功
- 必须具备增量同步与可观测日志
