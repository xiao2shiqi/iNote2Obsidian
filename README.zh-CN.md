# iNote2Obsidian

[English](README.md) | 中文

`iNote2Obsidian` 是一个原生 macOS 菜单栏应用，用于把 Apple Notes 单向同步到 Obsidian。

## 当前产品方向

- 产品形态：基于 `SwiftUI + AppKit` 的原生 macOS 应用
- 同步方向：`Apple Notes -> Obsidian`
- 交互方式：低侵入菜单栏小程序，带设置页和同步日志
- 优先级：可靠性优先，其次是体验
- 发布方式：GitHub Releases

## v1 行为

- 选择 Obsidian vault 目录后，持续在后台同步
- 将 Apple Notes 的目录结构映射到 vault 中
- 导出文本和已支持的内嵌图片为 Markdown
- 笔记文件名使用稳定创建时间：`yyyyMMdd-HHmmss`
- 同一条笔记更新时覆盖原有 Markdown 文件
- Apple Notes 删除后，删除对应的 Markdown 和资源
- Apple Notes 目录重命名或移动后，对应文件一起迁移
- 所有资源统一直接存放在 vault 根目录下的 `attachments/`，不再创建笔记级二级目录
- 在应用内展示同步日志

## 仓库结构

- [NativeApp](/Users/phoenix/Documents/workspace/iNote2Obsidian/NativeApp)：原生 macOS 应用源码
- [progress.md](/Users/phoenix/Documents/workspace/iNote2Obsidian/progress.md)：产品目标与迭代记录的唯一依据
- [AGENTS.md](/Users/phoenix/Documents/workspace/iNote2Obsidian/AGENTS.md)：协作规则

## 构建

```bash
cd NativeApp
swift build
```

## 当前实现说明

- 同步以菜单栏应用形式运行，当前采用 `1 秒轮询`
- Apple Notes 访问方式为 `osascript + JXA`
- 状态存储使用 `SQLite`
- 同步日志会落本地文件，并在应用界面中展示
- 图片提取当前支持 HTML 中可解析为 `data:` 或本地 `file://` 的内嵌图片来源

## 当前缺口

- 还没有签名后的发布安装包
- 还没有登录启动集成
- 富文本在 v1 中有意降级为纯文本 + 图片
- 当前这台机器的命令行 Swift 工具链可以通过 `swift build` 构建，但没有可用的 Swift 测试模块
