import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            statusSection
            controlSection
            if let error = viewModel.lastErrorSummary, viewModel.lampState == .yellow {
                errorSection(error)
            }
            outputSection
            syncOptionsSection
        }
        .padding(20)
        .frame(width: 700, height: 520)
    }

    private var statusSection: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(viewModel.lampColor)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text("状态：\(viewModel.statusText)")
                    .font(.headline)
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let run = viewModel.lastRun {
                Text("上次：+\(run.added) ~\(run.updated) !\(run.errors)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("开始") {
                    viewModel.startSyncing()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStart)

                Button("结束") {
                    viewModel.stopSyncing()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStop)
            }

            if viewModel.isSyncingAnimationVisible {
                WaveSyncView(phase: viewModel.wavePhase)
                    .frame(height: 52)
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近错误")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)
            HStack {
                Text(viewModel.settings.outputRootPath)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button("Choose") {
                    viewModel.chooseOutputDirectory()
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var syncOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync")
                .font(.headline)
            HStack {
                Text("Interval")
                Spacer()
                Picker("Interval", selection: $viewModel.settings.syncInterval) {
                    ForEach(SyncInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: viewModel.settings.syncInterval) { _ in
                    viewModel.saveSettings()
                }
            }
            Toggle("Exclude Recently Deleted", isOn: $viewModel.settings.excludeRecentlyDeleted)
                .onChange(of: viewModel.settings.excludeRecentlyDeleted) { _ in viewModel.saveSettings() }
            Toggle("Auto Start At Login", isOn: $viewModel.settings.autoStartAtLogin)
                .onChange(of: viewModel.settings.autoStartAtLogin) { _ in viewModel.saveSettings() }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct WaveSyncView: View {
    let phase: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let midY = size.height * 0.5
            path.move(to: CGPoint(x: 0, y: midY))
            let amplitude: CGFloat = 8
            let wavelength = max(size.width / 1.5, 80)

            stride(from: CGFloat(0), through: size.width, by: 2).forEach { x in
                let y = midY + sin((x / wavelength) * .pi * 2 + phase) * amplitude
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(.blue), lineWidth: 2)
        }
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
