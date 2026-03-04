import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Output") {
                HStack {
                    Text(viewModel.settings.outputRootPath)
                        .font(.caption)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Choose") {
                        viewModel.chooseOutputDirectory()
                    }
                }
            }

            Section("Sync") {
                Picker("Interval", selection: $viewModel.settings.syncInterval) {
                    ForEach(SyncInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .onChange(of: viewModel.settings.syncInterval) { _ in
                    viewModel.saveSettings()
                }

                Toggle("Exclude Recently Deleted", isOn: $viewModel.settings.excludeRecentlyDeleted)
                    .onChange(of: viewModel.settings.excludeRecentlyDeleted) { _ in viewModel.saveSettings() }

                Toggle("Auto Start At Login", isOn: $viewModel.settings.autoStartAtLogin)
                    .onChange(of: viewModel.settings.autoStartAtLogin) { _ in viewModel.saveSettings() }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 320)
    }
}
