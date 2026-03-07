import SwiftUI

private enum AppTypography {
    static let hero = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 13, weight: .regular, design: .default)
    static let bodyStrong = Font.system(size: 13, weight: .medium, design: .default)
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    static let metric = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
}

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroSection
                    actionSection
                    if let error = viewModel.lastErrorSummary, viewModel.lampState == .yellow {
                        errorSection(error)
                    }
                    realtimeSection
                    outputSection
                    syncOptionsSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("iNote2Obsidian")
                    .font(AppTypography.hero)
                Text(viewModel.t(.appSubtitle))
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                statusPill
                if let run = viewModel.lastRun {
                    Text("\(viewModel.t(.lastRunPrefix)): +\(run.added)  ~\(run.updated)  !\(run.errors)")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 18)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.statusColor)
                .frame(width: 10, height: 10)
            Text(viewModel.statusText)
                .font(AppTypography.bodyStrong)
            if viewModel.status == .syncing {
                ProgressView()
                    .scaleEffect(0.55)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(viewModel.statusColor.opacity(0.14), in: Capsule())
        .overlay(
            Capsule().stroke(viewModel.statusColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.t(.controls))
                .font(AppTypography.title)

            HStack(spacing: 10) {
                Button {
                    viewModel.startSyncing()
                } label: {
                    Label(viewModel.t(.startSync), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(!viewModel.canStart)

                Button {
                    viewModel.stopSyncing()
                } label: {
                    Label(viewModel.t(.stopSync), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStop)
            }

            Text(viewModel.statusMessage)
                .font(AppTypography.body)
                .foregroundStyle(.secondary)

            if viewModel.isSyncingAnimationVisible {
                WaveSyncView(phase: viewModel.wavePhase)
                    .frame(height: 42)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    private func errorSection(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.t(.recentError))
                    .font(AppTypography.bodyStrong)
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.yellow.opacity(0.4), lineWidth: 1)
        )
    }

    private var realtimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.t(.realtimePanel))
                .font(AppTypography.title)

            HStack(spacing: 10) {
                statCard(title: viewModel.t(.appleNotes), value: viewModel.appleNotesDisplayValue)
                statCard(title: viewModel.t(.matched), value: viewModel.matchedDisplayValue)
                statCard(title: viewModel.t(.pending), value: viewModel.pendingDisplayValue)
            }

            Text(viewModel.realtimeDetailMessage)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    private func statCard(title: String, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
            if let detail {
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.t(.outputDirectory))
                .font(AppTypography.title)

            HStack(spacing: 8) {
                Text(viewModel.settings.outputRootPath)
                    .font(AppTypography.body)
                    .textSelection(.enabled)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Button(viewModel.t(.chooseDirectory)) {
                    viewModel.chooseOutputDirectory()
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(viewModel.format(.managedOutputLocation, viewModel.managedOutputRootPath))
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    private var syncOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.t(.syncOptions))
                .font(AppTypography.title)

            HStack {
                Text(viewModel.t(.interval))
                    .font(AppTypography.body)
                Spacer()
                Picker("Interval", selection: $viewModel.settings.syncInterval) {
                    ForEach(SyncInterval.allCases) { interval in
                        Text(viewModel.localizedIntervalDisplayName(interval)).tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: viewModel.settings.syncInterval) { _ in
                    viewModel.saveSettings()
                }
            }

            Toggle(viewModel.t(.excludeRecentlyDeleted), isOn: $viewModel.settings.excludeRecentlyDeleted)
                .font(AppTypography.body)
                .onChange(of: viewModel.settings.excludeRecentlyDeleted) { _ in
                    viewModel.saveSettings()
                }

            Toggle(viewModel.t(.autoStartAtLogin), isOn: $viewModel.settings.autoStartAtLogin)
                .font(AppTypography.body)
                .onChange(of: viewModel.settings.autoStartAtLogin) { _ in
                    viewModel.saveSettings()
                }

            HStack {
                Text(viewModel.t(.language))
                    .font(AppTypography.body)
                Spacer()
                Picker("Language", selection: $viewModel.settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: viewModel.settings.language) { _ in
                    viewModel.saveSettings()
                    viewModel.applyLanguageImmediately()
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
    }
}

struct WaveSyncView: View {
    let phase: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let midY = size.height * 0.5
            path.move(to: CGPoint(x: 0, y: midY))
            let amplitude: CGFloat = 6
            let wavelength = max(size.width / 1.8, 90)

            stride(from: CGFloat(0), through: size.width, by: 2).forEach { x in
                let y = midY + sin((x / wavelength) * .pi * 2 + phase) * amplitude
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(Color.accentColor), lineWidth: 2)
        }
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
