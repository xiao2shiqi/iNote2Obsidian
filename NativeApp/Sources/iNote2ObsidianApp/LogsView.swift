import SwiftUI

struct LogsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
