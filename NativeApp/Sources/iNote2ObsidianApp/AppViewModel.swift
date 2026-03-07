import AppKit
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var runMode: SyncRunMode
    @Published var status: AppStatus = .idle
    @Published var statusMessage: String = "Stopped"
    @Published var lastRunSummary: SyncRunSummary?
    @Published var logs: [String] = []

    private let settingsStore: AppSettingsStore
    private let logger: AppLogger
    private let stateStore: StateStore
    private let engine: SyncEngine
    private let snapshotProvider: NotesSnapshotProvider
    private var timer: Timer?
    private var isSyncing = false

    init(
        settingsStore: AppSettingsStore? = nil,
        snapshotProvider: NotesSnapshotProvider = AppleNotesBridge(),
        engine: SyncEngine = SyncEngine()
    ) {
        do {
            let store = try settingsStore ?? AppSettingsStore()
            let loadedSettings = store.load()
            self.settingsStore = store
            self.settings = loadedSettings
            self.runMode = loadedSettings.lastRunMode
            let logger = AppLogger(logURL: store.stateDirectory.appendingPathComponent("sync.log"))
            self.logger = logger
            self.stateStore = try StateStore(dbURL: store.stateDirectory.appendingPathComponent("state.sqlite3"))
            self.engine = engine
            self.snapshotProvider = snapshotProvider
            self.logs = logger.readRecentLines()
            logger.onLog = { [weak self] entry in
                Task { @MainActor in
                    guard let self else { return }
                    self.logs.append("[\(Self.timeOnlyFormatter.string(from: entry.timestamp))] \(entry.message)")
                    self.logs = Array(self.logs.suffix(200))
                }
            }
            if runMode == .running {
                startTimer()
                syncNow()
            }
        } catch {
            fatalError("Failed to initialize app: \(error.localizedDescription)")
        }
    }

    var statusBadge: String {
        switch status {
        case .idle: return "Stopped"
        case .syncing: return "Syncing"
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    var statusIconName: String {
        switch status {
        case .idle: return "pause.circle"
        case .syncing: return "arrow.triangle.2.circlepath.circle"
        case .healthy: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    func startSyncing() {
        guard runMode == .stopped else { return }
        runMode = .running
        status = .healthy
        statusMessage = "Watching Apple Notes"
        settings.lastRunMode = .running
        saveSettings()
        startTimer()
        syncNow()
    }

    func stopSyncing() {
        timer?.invalidate()
        timer = nil
        runMode = .stopped
        status = .idle
        statusMessage = "Stopped"
        settings.lastRunMode = .stopped
        saveSettings()
        logger.info("sync stopped")
    }

    func syncNow() {
        guard runMode == .running else { return }
        guard !isSyncing else {
            logger.info("scan skipped: previous run active")
            return
        }
        isSyncing = true
        status = .syncing
        statusMessage = "Scanning Apple Notes"

        let currentSettings = settings
        let logger = logger
        let stateStore = stateStore
        let engine = engine
        let snapshotProvider = snapshotProvider

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let summary = try engine.run(
                    settings: currentSettings,
                    snapshotProvider: snapshotProvider,
                    stateStore: stateStore,
                    logger: logger
                )
                DispatchQueue.main.async {
                    self.lastRunSummary = summary
                    self.status = summary.errorCount == 0 ? .healthy : .warning
                    self.statusMessage = "Scanned \(summary.scannedCount), +\(summary.createdCount) ~\(summary.updatedCount) →\(summary.movedCount) -\(summary.deletedCount)"
                    self.isSyncing = false
                }
            } catch {
                DispatchQueue.main.async {
                    if case .permissionDenied = error as? SyncError {
                        self.status = .warning
                    } else {
                        self.status = .error
                    }
                    self.statusMessage = error.localizedDescription
                    self.logger.error(error.localizedDescription)
                    self.isSyncing = false
                }
            }
        }
    }

    func chooseVaultPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Vault"
        if panel.runModal() == .OK, let url = panel.urls.first {
            settings.vaultPath = url.path
            saveSettings()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.pollIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncNow()
            }
        }
    }

    private func saveSettings() {
        do {
            try settingsStore.save(settings)
        } catch {
            logger.error("failed to save settings: \(error.localizedDescription)")
        }
    }

    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
