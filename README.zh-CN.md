# iNote2Obsidian

[English](README.md) | 中文

## 为什么做这个项目

我做这个项目的原因很直接：我有把 Apple 备忘录持续、自动、无感同步到 Obsidian 的真实需求。

我调研并尝试过很多现有方案（官方导入、手动导出导入、快捷指令、脚本定时任务等），但它们大多是一次性迁移或半自动流程，缺少一个成熟、开箱即用、可持续运行的同步工具。

所以我决定自己实现，并以开源方式提供出来。

## 项目目标（已更新）

开发一个 **macOS 原生桌面应用**，把 Apple Notes 稳定同步到 Obsidian，并提供可视化界面与可靠后台能力。

## 产品方向

- 形态：原生 macOS App（不是脚本产品）
- 同步方向：**仅 Apple Notes -> Obsidian**
- 优先级：可靠性优先，其次是交互体验
- 分发方式：**通过 GitHub Releases 提供安装包**（不走 Mac App Store）

## 下一阶段推荐技术栈

- UI：`SwiftUI` + `AppKit` 集成
- 同步核心：Swift 原生模块
- Notes 访问：`AppleScript/JXA` 桥接
- 状态存储：`SQLite`
- 后台调度：`launchd`

## 当前状态

当前仓库已具备可运行的 CLI 同步 MVP（Python 实现），已验证核心能力：
- 增量同步
- 目录映射
- Markdown + 附件输出
- 日志与 SQLite 状态管理

这个 MVP 将作为后续迁移到原生 macOS App 架构的功能基线。

## 分发规划

- 使用 GitHub Actions 构建 macOS 安装产物
- 通过 GitHub Releases 发布版本
- 在仓库中提供直接下载安装说明
