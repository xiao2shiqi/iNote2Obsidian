import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Status")
                    .font(.headline)
                Spacer()
                Label(viewModel.status.rawValue, systemImage: viewModel.statusIconName)
                    .foregroundStyle(viewModel.statusColor)
            }

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let run = viewModel.lastRun {
                Text("Last: +\(run.added) ~\(run.updated) -\(run.deleted) !\(run.errors)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Sync Now") {
                viewModel.syncNow()
            }

            Button("Settings") {
                viewModel.openSettingsWindow()
            }

            Button("Check for Updates") {
                viewModel.checkForUpdates()
            }

            Divider()
            Text("Output: \(viewModel.settings.outputRootPath)")
                .font(.caption2)
                .lineLimit(2)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
