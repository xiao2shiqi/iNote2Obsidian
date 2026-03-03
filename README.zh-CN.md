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
- 仅支持一个配置文件夹
- 删除策略为 tombstone（不自动删除 Obsidian 文件）
- 优先保证在 macOS 上后台稳定同步

## v1 技术栈

- `Python 3.12`
- `osascript`（JXA/AppleScript）
- `SQLite`
- `launchd`（LaunchAgent）
- Markdown + 资源文件

## 安装

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -e '.[dev]'
```

## 初始化配置

```bash
inote2obsidian init-config --output ./config.yaml
```

然后编辑 `config.yaml`，至少配置：
- `apple_notes.folder_name`
- `obsidian.vault_path`
- `state.db_path`
- `logging.file_path`

## 常用命令

```bash
inote2obsidian doctor --config ./config.yaml
inote2obsidian sync --config ./config.yaml
inote2obsidian status --config ./config.yaml
```

## launchd（每 5 分钟）

```bash
scripts/install_launchd.sh \
  "$PWD/.venv/bin/python" \
  "$PWD/config.yaml" \
  "$PWD/.inote2obsidian/stdout.log" \
  "$PWD/.inote2obsidian/stderr.log" \
  "$HOME/Library/LaunchAgents/com.inote2obsidian.sync.plist"
```

卸载：

```bash
scripts/uninstall_launchd.sh "$HOME/Library/LaunchAgents/com.inote2obsidian.sync.plist"
```

## 说明

- 首次运行可能出现 macOS Automation 授权弹窗，需要允许访问 Notes。
- v1 以可靠性优先，富文本可能降级为普通 Markdown。
- Apple Notes 附件提取在不同环境下可能需要进一步调优。
