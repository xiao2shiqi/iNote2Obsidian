import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection
            actionSection
            outputSection
            footerSection
        }
        .padding(12)
        .frame(width: 340)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("iNote2Obsidian")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Label(viewModel.statusText, systemImage: viewModel.statusIconName)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(viewModel.statusColor)
            }

            Text(viewModel.statusMessage)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(.secondary)

            if let run = viewModel.lastRun {
                Text("上次：+\(run.added) ~\(run.updated) -\(run.deleted) !\(run.errors)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                viewModel.focusMainWindowFromMenuBar()
            } label: {
                Label("打开主界面", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 8) {
                Button {
                    viewModel.startSyncing()
                } label: {
                    Label("开始", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(!viewModel.canStart)

                Button {
                    viewModel.stopSyncing()
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStop)
            }

            Button {
                viewModel.checkForUpdates()
            } label: {
                Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("输出路径")
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(.secondary)
            Text(viewModel.settings.outputRootPath)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var footerSection: some View {
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium, design: .default))
        .foregroundStyle(.secondary)
    }
}
