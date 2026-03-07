import SwiftUI

@available(macOS 13.0, *)
struct MenuContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iNote2Obsidian")
                .font(.headline)
            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let summary = viewModel.lastRunSummary {
                Text("Last run: \(summary.scannedCount) scanned, \(summary.createdCount) created, \(summary.updatedCount) updated, \(summary.deletedCount) deleted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start") { viewModel.startSyncing() }
                    .disabled(viewModel.runMode == .running)
                Button("Stop") { viewModel.stopSyncing() }
                    .disabled(viewModel.runMode == .stopped)
                Button("Sync Now") { viewModel.syncNow() }
                    .disabled(viewModel.runMode == .stopped)
            }

            Divider()

            HStack {
                Button("Settings") {
                    openWindow(id: "settings")
                }
                Button("Sync Log") {
                    openWindow(id: "sync-log")
                }
                Spacer()
                Button("Quit") {
                    viewModel.quitApplication()
                }
            }

            if !viewModel.logs.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.logs.suffix(8).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 130)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}
