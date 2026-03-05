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

    private let settingsStore: AppSettingsStore
    private let logger: AppLogger
    private let scheduler = Scheduler()
    private let bridge = NotesBridge()
    private let sparkle = SparkleUpdater()
    private let stateStore: StateStore
    private var waveTimer: Timer?
    private var settingsWindow: NSWindow?

    init() {
        do {
            let store = try AppSettingsStore()
            let loaded = store.load()
            self.settingsStore = store
            self.settings = loaded
            self.runMode = loaded.lastRunMode

            let stateDir = store.stateDirectory
            let loggerURL = stateDir.appendingPathComponent("sync.log")
            self.logger = AppLogger(logURL: loggerURL)
            self.stateStore = try StateStore(dbURL: stateDir.appendingPathComponent("state.db"))
            if self.runMode == .running {
                applyScheduling()
            } else {
                status = .idle
                statusMessage = "Stopped"
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
        statusMessage = "Stopped"
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
        statusMessage = "Syncing..."
        startWave()
        let currentSettings = settings
        let bridge = self.bridge
        let logger = self.logger
        let stateStore = self.stateStore

        DispatchQueue.global(qos: .userInitiated).async {
            let engine = SyncEngine(bridge: bridge, logger: logger)
            do {
                let run = try engine.run(settings: currentSettings, stateStore: stateStore)
                DispatchQueue.main.async {
                    self.lastRun = run
                    self.status = run.status
                    self.statusMessage = "Added \(run.added), Updated \(run.updated), Errors \(run.errors)"
                    self.syncHealth = .ok
                    self.lastErrorSummary = nil
                    self.stopWave()
                }
            } catch let err as SyncError {
                DispatchQueue.main.async {
                    switch err {
                    case .permissionDenied:
                        self.status = .failedPermission
                        self.syncHealth = .warning
                        self.lastErrorSummary = "需要授予 Notes 自动化权限"
                        self.statusMessage = "Permission required: allow Notes automation in System Settings."
                    default:
                        self.status = .failedRuntime
                        self.syncHealth = .warning
                        self.lastErrorSummary = "同步失败：\(err)"
                        self.statusMessage = "Sync failed: \(err)"
                    }
                    self.stopWave()
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .failedRuntime
                    self.syncHealth = .warning
                    self.lastErrorSummary = "同步失败：\(error.localizedDescription)"
                    self.statusMessage = "Sync failed"
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
            statusMessage = "Failed to save settings"
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
            return "Stopped"
        case .green:
            if status == .syncing { return "Syncing" }
            return "Running"
        case .yellow:
            return "Warning"
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
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        window.title = "iNote2Obsidian Settings"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    func focusMainWindowFromMenuBar() {
        openSettingsWindow()
    }

    func openSettingsWindowSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.openSettingsWindow()
        }
    }
}
