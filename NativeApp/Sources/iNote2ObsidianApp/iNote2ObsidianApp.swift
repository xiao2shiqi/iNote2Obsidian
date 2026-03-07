import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct iNote2ObsidianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra(viewModel.statusBadge, systemImage: viewModel.statusIconName) {
            MenuContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(viewModel: viewModel)
                .frame(width: 520, height: 220)
        }

        Window("Sync Log", id: "sync-log") {
            LogsView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 420)
        }
    }
}
