import SwiftUI

@main
struct iNote2ObsidianApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("iNote2Obsidian Settings", id: "main") {
            SettingsView(viewModel: viewModel)
        }
        .defaultSize(width: 700, height: 520)

        MenuBarExtra(viewModel.statusBadge, systemImage: viewModel.statusIconName) {
            MenuContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
