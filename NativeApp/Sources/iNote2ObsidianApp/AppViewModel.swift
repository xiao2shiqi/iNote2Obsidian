import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var status: SyncStatus = .idle
    @Published var lastRun: SyncRunStats?
    @Published var statusMessage: String = "Idle"
    @Published var rotationDegrees: Double = 0

    private let settingsStore: AppSettingsStore
    private let logger: AppLogger
    private let scheduler = Scheduler()
    private let bridge = NotesBridge()
    private let sparkle = SparkleUpdater()
    private let stateStore: StateStore
    private var spinTimer: Timer?
    private var settingsWindow: NSWindow?

    init() {
        do {
            let store = try AppSettingsStore()
            self.settingsStore = store
            self.settings = store.load()

            let stateDir = store.stateDirectory
            let loggerURL = stateDir.appendingPathComponent("sync.log")
            self.logger = AppLogger(logURL: loggerURL)
            self.stateStore = try StateStore(dbURL: stateDir.appendingPathComponent("state.db"))
            applyScheduling()
        } catch {
            fatalError("Failed to initialize app state: \(error)")
        }
    }

    func syncNow() {
        guard status != .syncing else { return }
        status = .syncing
        statusMessage = "Syncing..."
        startSpin()
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
                    self.stopSpin()
                }
            } catch let err as SyncError {
                DispatchQueue.main.async {
                    switch err {
                    case .permissionDenied:
                        self.status = .failedPermission
                        self.statusMessage = "Permission required: allow Notes automation in System Settings."
                    default:
                        self.status = .failedRuntime
                        self.statusMessage = "Sync failed: \(err)"
                    }
                    self.stopSpin()
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .failedRuntime
                    self.statusMessage = "Sync failed"
                    self.stopSpin()
                }
            }
        }
    }

    func saveSettings() {
        do {
            try settingsStore.save(settings)
            applyScheduling()
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
        switch status {
        case .failedPermission, .failedRuntime:
            return "exclamationmark.triangle.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .idle:
            return "circle.fill"
        }
    }

    var statusColor: Color {
        switch status {
        case .failedPermission, .failedRuntime: return .red
        case .syncing: return .blue
        case .success: return .green
        case .idle: return .gray
        }
    }

    var statusBadge: String {
        switch status {
        case .failedPermission, .failedRuntime:
            return "!"
        default:
            return ""
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
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

    private func applyScheduling() {
        scheduler.configure(interval: settings.syncInterval) { [weak self] in
            DispatchQueue.main.async {
                self?.syncNow()
            }
        }
    }

    private func startSpin() {
        spinTimer?.invalidate()
        spinTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.rotationDegrees = (self.rotationDegrees + 18).truncatingRemainder(dividingBy: 360)
            }
        }
    }

    private func stopSpin() {
        spinTimer?.invalidate()
        spinTimer = nil
        rotationDegrees = 0
    }
}
