import Foundation

enum L10nKey: Hashable, CaseIterable {
    case appSubtitle
    case lastRunPrefix
    case statusStopped
    case statusSyncing
    case statusRunning
    case statusWarning

    case controls
    case startSync
    case stopSync
    case recentError

    case realtimePanel
    case rounds
    case total
    case processed
    case pending
    case recentlySynced
    case waitingQueue
    case noFilesYet
    case noQueuedItems
    case logs
    case noLogsYet

    case outputDirectory
    case chooseDirectory
    case syncOptions
    case interval
    case excludeRecentlyDeleted
    case autoStartAtLogin
    case language

    case intervalFiveMinutes
    case intervalFifteenMinutes
    case intervalThirtyMinutes
    case intervalSixtyMinutes
    case intervalOneEightyMinutes
    case intervalOff

    case menuOpenMainWindow
    case menuStart
    case menuStop
    case menuCheckUpdates
    case menuOutputPath
    case menuQuit

    case settingsWindowTitle

    case messageStopped
    case messageSyncing
    case messagePermissionRequired
    case messageSyncFailed
    case messageSyncFailedWithDetailPrefix
    case messageFailedToSaveSettings
    case messageFetchingNotes
    case messageQueueReady
    case messageSyncCompleted
    case messageRunResult
    case permissionAlertTitle
    case permissionAlertBody
    case permissionAlertPrimaryButton
    case permissionAlertSecondaryButton
}

struct AppLocalizer {
    let language: AppLanguage

    func text(_ key: L10nKey) -> String {
        if let text = AppLocalizer.translations[language]?[key] {
            return text
        }
        return AppLocalizer.translations[.english]?[key] ?? ""
    }

    private static let translations: [AppLanguage: [L10nKey: String]] = [
        .english: [
            .appSubtitle: "Local Apple Notes to Obsidian sync",
            .lastRunPrefix: "Last",
            .statusStopped: "Stopped",
            .statusSyncing: "Syncing",
            .statusRunning: "Running",
            .statusWarning: "Warning",

            .controls: "Controls",
            .startSync: "Start Sync",
            .stopSync: "Stop Sync",
            .recentError: "Recent Error",

            .realtimePanel: "Realtime",
            .rounds: "Rounds",
            .total: "Total",
            .processed: "Processed",
            .pending: "Pending",
            .recentlySynced: "Recently Synced",
            .waitingQueue: "Waiting Queue",
            .noFilesYet: "No files yet",
            .noQueuedItems: "No queued items",
            .logs: "Logs",
            .noLogsYet: "No logs yet",

            .outputDirectory: "Output Directory",
            .chooseDirectory: "Choose Directory",
            .syncOptions: "Sync Options",
            .interval: "Interval",
            .excludeRecentlyDeleted: "Exclude Recently Deleted",
            .autoStartAtLogin: "Auto Start At Login",
            .language: "Language",

            .intervalFiveMinutes: "Every 5 minutes",
            .intervalFifteenMinutes: "Every 15 minutes",
            .intervalThirtyMinutes: "Every 30 minutes",
            .intervalSixtyMinutes: "Every 60 minutes",
            .intervalOneEightyMinutes: "Every 180 minutes",
            .intervalOff: "Off",

            .menuOpenMainWindow: "Open Main Window",
            .menuStart: "Start",
            .menuStop: "Stop",
            .menuCheckUpdates: "Check for Updates",
            .menuOutputPath: "Output Path",
            .menuQuit: "Quit",

            .settingsWindowTitle: "iNote2Obsidian Settings",

            .messageStopped: "Stopped",
            .messageSyncing: "Syncing...",
            .messagePermissionRequired: "Permission required: allow Notes automation in System Settings.",
            .messageSyncFailed: "Sync failed",
            .messageSyncFailedWithDetailPrefix: "Sync failed:",
            .messageFailedToSaveSettings: "Failed to save settings",
            .messageFetchingNotes: "Fetching notes...",
            .messageQueueReady: "Queue ready:",
            .messageSyncCompleted: "Sync completed",
            .messageRunResult: "Added %@, Updated %@, Errors %@",
            .permissionAlertTitle: "Automation Permission Required",
            .permissionAlertBody: "Please allow iNote2Obsidian to control Apple Notes in System Settings > Privacy & Security > Automation.",
            .permissionAlertPrimaryButton: "Open Settings",
            .permissionAlertSecondaryButton: "Later"
        ],
        .simplifiedChinese: [
            .appSubtitle: "Apple Notes 到 Obsidian 的本地同步",
            .lastRunPrefix: "上次",
            .statusStopped: "已停止",
            .statusSyncing: "同步中",
            .statusRunning: "运行中",
            .statusWarning: "警告",

            .controls: "控制",
            .startSync: "开始同步",
            .stopSync: "停止同步",
            .recentError: "最近错误",

            .realtimePanel: "实时面板",
            .rounds: "轮次",
            .total: "总量",
            .processed: "已处理",
            .pending: "待处理",
            .recentlySynced: "最近同步",
            .waitingQueue: "等待队列",
            .noFilesYet: "暂无文件",
            .noQueuedItems: "暂无排队项",
            .logs: "日志",
            .noLogsYet: "暂无日志",

            .outputDirectory: "输出目录",
            .chooseDirectory: "选择目录",
            .syncOptions: "同步选项",
            .interval: "间隔",
            .excludeRecentlyDeleted: "排除 Recently Deleted",
            .autoStartAtLogin: "登录后自动启动",
            .language: "语言",

            .intervalFiveMinutes: "每 5 分钟",
            .intervalFifteenMinutes: "每 15 分钟",
            .intervalThirtyMinutes: "每 30 分钟",
            .intervalSixtyMinutes: "每 60 分钟",
            .intervalOneEightyMinutes: "每 180 分钟",
            .intervalOff: "关闭",

            .menuOpenMainWindow: "打开主界面",
            .menuStart: "开始",
            .menuStop: "结束",
            .menuCheckUpdates: "检查更新",
            .menuOutputPath: "输出路径",
            .menuQuit: "退出",

            .settingsWindowTitle: "iNote2Obsidian 设置",

            .messageStopped: "已停止",
            .messageSyncing: "同步中...",
            .messagePermissionRequired: "需要授予 Notes 自动化权限，请在系统设置中允许。",
            .messageSyncFailed: "同步失败",
            .messageSyncFailedWithDetailPrefix: "同步失败：",
            .messageFailedToSaveSettings: "保存设置失败",
            .messageFetchingNotes: "正在读取笔记...",
            .messageQueueReady: "队列已就绪：",
            .messageSyncCompleted: "同步完成",
            .messageRunResult: "新增 %@，更新 %@，错误 %@",
            .permissionAlertTitle: "需要自动化权限",
            .permissionAlertBody: "请在「系统设置 > 隐私与安全性 > 自动化」中允许 iNote2Obsidian 控制 Apple Notes。",
            .permissionAlertPrimaryButton: "打开设置",
            .permissionAlertSecondaryButton: "稍后"
        ]
    ]
}
