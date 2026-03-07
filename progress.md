# 项目目标

iNote2Obsidian 的当前目标是构建一个原生 macOS 菜单栏应用，将 Apple Notes 低侵入、稳定地单向同步到 Obsidian。

## 已确认目标

- 产品形态：原生 macOS 应用（`SwiftUI + AppKit`）
- UI 形态：菜单栏常驻，只提供必要设置和同步过程展示
- 同步方向：单向同步（`Apple Notes -> Obsidian`）
- 优先级：可靠性优先，其次是用户体验
- 发布方式：通过 GitHub Releases 提供安装包
- 暂不包含：Mac App Store 发布

## v1 目标行为

- 用户指定 Obsidian vault 目录后，应用在后台常驻运行
- Apple Notes 的目录结构同步映射到 Obsidian 中
- 备忘录中的文本和图片同步为 Markdown
- 目标笔记文件名按稳定创建时间命名：`yyyyMMdd-HHmmss`
- 同秒冲突时在文件名后追加 `-1`、`-2`
- 同一条 Apple Note 后续修改时覆盖原 Markdown 文件
- Apple Notes 删除后，删除对应的 Obsidian Markdown 和资源
- Apple Notes 文件夹重命名或移动后，Obsidian 对应目录也跟着迁移
- 所有资源统一直接放到 vault 根目录下的 `attachments/`，不创建笔记级二级目录
- 应用内提供 `sync log`，能看到写入、更新、移动、删除和错误

## v1 技术决策

- 运行时：Swift 原生实现
- Notes 访问：`osascript` + JXA
- 状态存储：`SQLite`
- 同步触发：当前实现采用 `1 秒轮询`
- 数据安全：删除需要连续两轮扫描都缺失后才执行，避免误删

## 成功标准

- 1000 条笔记可稳定同步到 Obsidian
- 单条新增、修改、删除在正常情况下可在 1 到 2 秒内完成同步
- 应用连续运行 7 天不出现错乱、重复写入、漏同步、误删

## 本轮已完成

- 删除旧的 Python CLI、`launchd`、脚本和相关测试代码
- 重建 `NativeApp` 为新的原生菜单栏应用方向
- 新实现包含：
  - 菜单栏入口
  - 设置页
  - 同步日志窗口
  - JXA Apple Notes 扫描桥接
  - SQLite 状态存储
  - 增量同步规划与执行
  - 目录迁移、覆盖更新、延迟删除保护
  - Markdown 输出与统一 `attachments/` 资源目录
- `README.md` 与 `README.zh-CN.md` 已同步更新为新方案
- 新增 `MIT` 开源协议，并补充 README 中的项目背景说明
- 在 README 中补充未签名版本的安装说明，明确通过“打开”或“仍要打开”继续运行
- 菜单栏窗口补充 `Quit` 按钮，退出时会先停止同步再终止应用，避免测试实例残留多个菜单栏图标

## 当前状态

- `swift build` 在 `NativeApp/` 下可通过
- 当前实现已能构建新的产品骨架和核心同步流程
- 图片提取目前支持可从 HTML 中解析出的 `data:` 和本地 `file://` 图片来源
- 2026-03-07 真实集成测试结果：
  - 使用目录 `/Volumes/MOVESPEED/Document-External/iNote` 作为验收输出目录
  - Apple Notes 当前有效笔记数为 `275`
  - 首轮全量同步完成：`scanned=275 created=275 errors=0 duration=216.46s`
  - 第二轮重复同步完成：`scanned=275 created=0 updated=0 moved=0 deleted=0 errors=0 duration=42.72s`

## 当前缺口

- 还未完成真实设备上的大规模 1000 条笔记压力验证
- 还未完成登录启动、签名、安装包发布链路
- 还未验证所有 Apple Notes 富文本和附件类型
- 当前命令行 Swift 工具链缺少可用测试模块，因此本轮以 `swift build` 和真实集成测试作为验证

## 下一步

- 在真实 Apple Notes 数据上做端到端联调
- 补强图片/附件兼容性
- 打磨菜单栏状态和错误提示
- 增加发布与安装流程
