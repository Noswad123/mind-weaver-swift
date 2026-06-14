import SwiftUI

struct CommandOutputView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        DisclosureGroup {
            ScrollView {
                Text(appModel.commandOutput.isEmpty ? "No command output yet." : appModel.commandOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .frame(maxHeight: 140)
        } label: {
            Text(appModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }
}
