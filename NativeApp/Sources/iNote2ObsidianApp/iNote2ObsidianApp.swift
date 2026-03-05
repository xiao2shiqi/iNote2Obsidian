import SwiftUI

@main
struct iNote2ObsidianApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra(viewModel.statusBadge, systemImage: viewModel.statusIconName) {
            MenuContentView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
