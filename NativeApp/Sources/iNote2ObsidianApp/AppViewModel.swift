import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var runMode: SyncRunMode
    @Published var syncHealth: SyncHealth = .ok
    @Published var status: SyncStatus = .idle
    @Published var lastRun: SyncRunStats?
    @Published var statusMessage: String = "Stopped"
    @Published var lastErrorSummary: String?
    @Published var wavePhase: CGFloat = 0
    @Published var syncRoundsCompleted: Int = 0
    @Published var totalInCurrentRun: Int = 0
    @Published var scannedInCurrentRun: Int = 0
    @Published var syncedInCurrentRun: Int = 0
    @Published var pendingInCurrentRun: Int = 0
    @Published var isPendingCountAvailable: Bool = false
    @Published var pendingQueuePreview: [String] = []
    @Published var recentlySyncedFiles: [String] = []
    @Published var logLines: [String] = []

    private let settingsStore: AppSettingsStore
    private let logger: AppLogger
    private let scheduler = Scheduler()
    private let bridge = NotesBridge()
    private let sparkle = SparkleUpdater()
    private let stateStore: StateStore
    private var waveTimer: Timer?
    private var settingsWindow: NSWindow?
    private var lastScannedHeartbeatCount: Int = -1

    init() {
        do {
            let store = try AppSettingsStore()
            let loaded = store.load()
            self.settingsStore = store
            self.settings = loaded
            self.runMode = loaded.lastRunMode
            self.syncRoundsCompleted = loaded.totalSyncRounds

            let stateDir = store.stateDirectory
            let loggerURL = stateDir.appendingPathComponent("sync.log")
            self.logger = AppLogger(logURL: loggerURL)
            self.stateStore = try StateStore(dbURL: stateDir.appendingPathComponent("state.db"))
            if self.runMode == .running {
                applyScheduling()
                statusMessage = t(.statusRunning)
            } else {
                status = .idle
                statusMessage = t(.messageStopped)
                scheduler.stop()
            }
            openSettingsWindowSoon()
        } catch {
            fatalError("Failed to initialize app state: \(error)")
        }
    }

    func startSyncing() {
        guard runMode == .stopped else { return }
        runMode = .running
        syncHealth = .ok
        lastErrorSummary = nil
        settings.lastRunMode = .running
        saveSettings()
        applyScheduling()
        syncNow()
    }

    func stopSyncing() {
        guard runMode == .running else { return }
        scheduler.stop()
        runMode = .stopped
        status = .idle
        syncHealth = .ok
        statusMessage = t(.messageStopped)
        stopWave()
        settings.lastRunMode = .stopped
        saveSettings()
    }

    var canStart: Bool { runMode == .stopped }
    var canStop: Bool { runMode == .running }
    var isSyncingAnimationVisible: Bool { status == .syncing && runMode == .running }

    var lampState: SyncLampState {
        switch runMode {
        case .stopped:
            return .red
        case .running:
            switch syncHealth {
            case .ok: return .green
            case .warning: return .yellow
            }
        }
    }

    func syncNow() {
        guard runMode == .running else { return }
        guard status != .syncing else { return }
        status = .syncing
        statusMessage = t(.messageSyncing)
        resetRealtimeRunState()
        appendLog("Sync started")
        startWave()
        let currentSettings = settings
        let bridge = self.bridge
        let logger = self.logger
        let stateStore = self.stateStore

        DispatchQueue.global(qos: .userInitiated).async {
            let engine = SyncEngine(bridge: bridge, logger: logger)
            do {
                let run = try engine.run(
                    settings: currentSettings,
                    stateStore: stateStore,
                    progress: { progress in
                        DispatchQueue.main.async {
                            self.applyProgress(progress)
                        }
                    }
                )
                DispatchQueue.main.async {
                    self.lastRun = run
                    self.status = run.status
                    self.statusMessage = self.format(.messageRunResult, "\(run.added)", "\(run.updated)", "\(run.errors)")
                    self.syncHealth = .ok
                    self.lastErrorSummary = nil
                    self.syncRoundsCompleted += 1
                    self.settings.totalSyncRounds = self.syncRoundsCompleted
                    self.saveSettings()
                    self.appendLog("Sync finished: +\(run.added) ~\(run.updated) !\(run.errors)")
                    self.stopWave()
                }
            } catch let err as SyncError {
                DispatchQueue.main.async {
                    switch err {
                    case .permissionDenied:
                        self.status = .failedPermission
                        self.syncHealth = .warning
                        self.lastErrorSummary = self.t(.messagePermissionRequired)
                        self.statusMessage = self.t(.messagePermissionRequired)
                        self.appendLog("Permission error: Notes automation not granted")
                        self.presentPermissionAlert()
                    case .bridgeFailed(let detail) where detail.localizedCaseInsensitiveContains("heartbeat timeout"):
                        self.status = .failedRuntime
                        self.syncHealth = .warning
                        self.lastErrorSummary = self.t(.messageBridgeHeartbeatTimeout)
                        self.statusMessage = self.t(.messageBridgeHeartbeatTimeout)
                        self.appendLog("Bridge timeout: \(detail)")
                    default:
                        self.status = .failedRuntime
                        self.syncHealth = .warning
                        self.lastErrorSummary = "\(self.t(.messageSyncFailedWithDetailPrefix))\(err)"
                        self.statusMessage = "\(self.t(.messageSyncFailedWithDetailPrefix)) \(err)"
                        self.appendLog("Sync failed: \(err)")
                    }
                    self.stopWave()
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .failedRuntime
                    self.syncHealth = .warning
                    self.lastErrorSummary = "\(self.t(.messageSyncFailedWithDetailPrefix))\(error.localizedDescription)"
                    self.statusMessage = self.t(.messageSyncFailed)
                    self.appendLog("Sync failed: \(error.localizedDescription)")
                    self.stopWave()
                }
            }
        }
    }

    func saveSettings() {
        do {
            try settingsStore.save(settings)
            if runMode == .running {
                applyScheduling()
            }
        } catch {
            statusMessage = t(.messageFailedToSaveSettings)
        }
    }

    func applyLanguageImmediately() {
        settingsWindow?.title = t(.settingsWindowTitle)
        switch status {
        case .idle:
            statusMessage = runMode == .running ? t(.statusRunning) : t(.messageStopped)
        case .syncing:
            statusMessage = t(.messageSyncing)
        case .success:
            if let run = lastRun {
                statusMessage = format(.messageRunResult, "\(run.added)", "\(run.updated)", "\(run.errors)")
            } else {
                statusMessage = t(.messageSyncCompleted)
            }
        case .failedPermission:
            statusMessage = t(.messagePermissionRequired)
            lastErrorSummary = t(.messagePermissionRequired)
        case .failedRuntime:
            if let existingError = lastErrorSummary, !existingError.isEmpty {
                let detail = existingError
                    .replacingOccurrences(of: "Sync failed: ", with: "")
                    .replacingOccurrences(of: "同步失败：", with: "")
                lastErrorSummary = "\(t(.messageSyncFailedWithDetailPrefix))\(detail)"
            }
            if statusMessage.contains(t(.messageSyncFailed)) || statusMessage.lowercased().contains("sync failed") {
                statusMessage = t(.messageSyncFailed)
            }
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.urls.first {
            settings.outputRootPath = url.path
            saveSettings()
        }
    }

    var statusIconName: String {
        if status == .syncing && runMode == .running {
            return "arrow.triangle.2.circlepath"
        }
        switch lampState {
        case .red:
            return "circle.fill"
        case .green:
            return "checkmark.circle.fill"
        case .yellow:
            return "exclamationmark.triangle.fill"
        }
    }

    var statusText: String {
        switch lampState {
        case .red:
            return t(.statusStopped)
        case .green:
            if status == .syncing { return t(.statusSyncing) }
            return t(.statusRunning)
        case .yellow:
            return t(.statusWarning)
        }
    }

    var lampColor: Color {
        switch lampState {
        case .red:
            return .red
        case .green:
            return .green
        case .yellow:
            return .yellow
        }
    }

    var statusColor: Color {
        if status == .syncing && runMode == .running {
            return .blue
        }
        return lampColor
    }

    var statusBadge: String {
        switch lampState {
        case .yellow:
            return "!"
        default:
            return ""
        }
    }

    var shouldPulseMenuIcon: Bool {
        status == .syncing && runMode == .running
    }

    var pendingDisplayValue: String {
        isPendingCountAvailable ? "\(pendingInCurrentRun)" : "--"
    }

    var primaryMetricTitle: String {
        isPendingCountAvailable ? t(.synced) : t(.scanned)
    }

    var primaryMetricValue: String {
        isPendingCountAvailable ? "\(syncedInCurrentRun)" : "\(scannedInCurrentRun)"
    }

    var managedOutputRootPath: String {
        settings.managedOutputRootPath
    }

    var realtimeDetailMessage: String {
        if status == .syncing && !isPendingCountAvailable {
            return t(.messageScanningRealtime)
        }
        return statusMessage
    }

    private func applyScheduling() {
        scheduler.configure(interval: settings.syncInterval) { [weak self] in
            DispatchQueue.main.async {
                self?.syncNow()
            }
        }
    }

    private func startWave() {
        waveTimer?.invalidate()
        waveTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.wavePhase += 0.18
                if self.wavePhase > .pi * 2 { self.wavePhase = 0 }
            }
        }
    }

    private func stopWave() {
        waveTimer?.invalidate()
        waveTimer = nil
        wavePhase = 0
    }

    func checkForUpdates() {
        sparkle.checkForUpdates()
    }

    func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])

        if let window = settingsWindow {
            window.title = t(.settingsWindowTitle)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
            return
        }

        let rootView = SettingsView(viewModel: self)
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = t(.settingsWindowTitle)
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        settingsWindow = window
    }

    func focusMainWindowFromMenuBar() {
        openSettingsWindow()
    }

    private func openSettingsWindowSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.openSettingsWindow()
        }
    }

    private func resetRealtimeRunState() {
        totalInCurrentRun = 0
        scannedInCurrentRun = 0
        syncedInCurrentRun = 0
        pendingInCurrentRun = 0
        isPendingCountAvailable = false
        pendingQueuePreview = []
        recentlySyncedFiles = []
        lastScannedHeartbeatCount = -1
    }

    private func applyProgress(_ progress: SyncProgress) {
        totalInCurrentRun = progress.total
        scannedInCurrentRun = progress.scanned
        syncedInCurrentRun = progress.synced
        pendingInCurrentRun = progress.pending
        isPendingCountAvailable = progress.totalKnown

        switch progress.stage {
        case .fetching:
            if let message = progress.message, message.hasPrefix("SCANNED:") {
                let countText = String(message.dropFirst("SCANNED:".count))
                if let count = Int(countText) {
                    statusMessage = format(.messageScannedNotes, "\(count)")
                    if count != lastScannedHeartbeatCount {
                        appendLog("Scanned \(count) notes...")
                        lastScannedHeartbeatCount = count
                    }
                } else {
                    statusMessage = t(.messageFetchingNotesStreaming)
                }
            } else {
                statusMessage = progress.message ?? t(.messageFetchingNotesStreaming)
                appendLog(progress.message ?? "Fetching notes (streaming)...")
            }
        case .queueReady:
            pendingQueuePreview = progress.queuePreview
            statusMessage = "\(t(.messageQueueReady)) \(progress.total)"
            appendLog("Queue prepared: \(progress.total) notes")
        case .noteProcessed:
            if let file = progress.outputFile {
                prependRecentFile(file)
            }
            if let event = progress.eventType {
                let label: String
                switch event {
                case .added: label = "added"
                case .updated: label = "updated"
                case .skipped: label = "skipped"
                case .failed: label = "failed"
                }
                let note = progress.currentNote ?? "Unknown"
                let totalLabel = progress.totalKnown ? "\(progress.total)" : "?"
                let progressLabel = progress.totalKnown ? "\(progress.synced)/\(totalLabel)" : "scan \(progress.scanned)"
                appendLog("[\(progressLabel)] \(label): \(note)")
            }
        case .completed:
            statusMessage = t(.messageSyncCompleted)
            appendLog("Run completed")
        }
    }

    var localizer: AppLocalizer {
        AppLocalizer(language: settings.language)
    }

    func t(_ key: L10nKey) -> String {
        localizer.text(key)
    }

    func format(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: "en_US_POSIX"), arguments: args)
    }

    func localizedIntervalDisplayName(_ interval: SyncInterval) -> String {
        switch interval {
        case .fiveMinutes:
            return t(.intervalFiveMinutes)
        case .fifteenMinutes:
            return t(.intervalFifteenMinutes)
        case .thirtyMinutes:
            return t(.intervalThirtyMinutes)
        case .sixtyMinutes:
            return t(.intervalSixtyMinutes)
        case .oneEightyMinutes:
            return t(.intervalOneEightyMinutes)
        case .off:
            return t(.intervalOff)
        }
    }

    private func prependRecentFile(_ path: String) {
        recentlySyncedFiles.insert(path, at: 0)
        if recentlySyncedFiles.count > 50 {
            recentlySyncedFiles.removeLast(recentlySyncedFiles.count - 50)
        }
    }

    private func appendLog(_ line: String) {
        let time = DateFormatter.logTimestamp.string(from: Date())
        logLines.append("[\(time)] \(line)")
        if logLines.count > 300 {
            logLines.removeFirst(logLines.count - 300)
        }
    }

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = t(.permissionAlertTitle)
        alert.informativeText = t(.permissionAlertBody)
        alert.addButton(withTitle: t(.permissionAlertPrimaryButton))
        alert.addButton(withTitle: t(.permissionAlertSecondaryButton))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
