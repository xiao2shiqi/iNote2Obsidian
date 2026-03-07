import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            LabeledContent("Obsidian Vault") {
                HStack {
                    Text(viewModel.settings.vaultPath)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(2)
                    Button("Choose…") {
                        viewModel.chooseVaultPath()
                    }
                }
            }

            LabeledContent("Attachments Folder") {
                Text(viewModel.settings.attachmentsFolderName)
            }

            LabeledContent("Realtime Polling") {
                Text("\(Int(viewModel.settings.pollIntervalSeconds)) second")
            }

            LabeledContent("Current Mode") {
                Text(viewModel.runMode == .running ? "Running" : "Stopped")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
