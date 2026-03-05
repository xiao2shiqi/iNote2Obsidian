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
            realtimeSection
            outputSection
            syncOptionsSection
        }
        .padding(20)
        .frame(width: 700, height: 520)
    }

    private var realtimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Realtime")
                .font(.headline)

            HStack(spacing: 14) {
                statChip(title: "Rounds", value: "\(viewModel.syncRoundsCompleted)")
                statChip(title: "Total", value: "\(viewModel.totalInCurrentRun)")
                statChip(title: "Processed", value: "\(viewModel.processedInCurrentRun)")
                statChip(title: "Pending", value: "\(viewModel.pendingInCurrentRun)")
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recently Synced")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.recentlySyncedFiles.prefix(12), id: \.self) { file in
                                Text(file)
                                    .font(.caption2.monospaced())
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            if viewModel.recentlySyncedFiles.isEmpty {
                                Text("No files yet")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 110)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Waiting Queue")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.pendingQueuePreview.prefix(12), id: \.self) { item in
                                Text(item)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            if viewModel.pendingQueuePreview.isEmpty {
                                Text("No queued items")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 110)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Logs")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(viewModel.logLines.suffix(80), id: \.self) { line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        if viewModel.logLines.isEmpty {
                            Text("No logs yet")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 130)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
