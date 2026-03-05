import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("状态")
                    .font(.headline)
                Spacer()
                Label(viewModel.statusText, systemImage: viewModel.statusIconName)
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

            Button("打开主界面") {
                viewModel.focusMainWindowFromMenuBar()
            }

            Button("开始") {
                viewModel.startSyncing()
            }
            .disabled(!viewModel.canStart)

            Button("结束") {
                viewModel.stopSyncing()
            }
            .disabled(!viewModel.canStop)

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
