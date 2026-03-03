# iNote2Obsidian

[English](README.md) | 中文

## 为什么做这个项目

我做这个项目的原因很直接：我有把 Apple 备忘录持续、自动、无感同步到 Obsidian 的真实需求。

我调研并尝试过很多现有方案（官方导入、手动导出导入、快捷指令、脚本定时任务等），但它们大多是一次性迁移或半自动流程，缺少一个成熟、开箱即用、可持续运行的同步工具。

所以我决定自己实现，并以开源方式提供出来。

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
