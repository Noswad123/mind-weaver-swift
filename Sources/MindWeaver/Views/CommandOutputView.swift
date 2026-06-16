import SwiftUI

struct CommandOutputView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        DisclosureGroup {
            ScrollView {
                Text(appModel.commandOutput.isEmpty ? "No command output yet." : appModel.commandOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MWTheme.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            .frame(maxHeight: 140)
        } label: {
            Text(appModel.statusMessage)
                .font(.caption)
                .foregroundStyle(MWTheme.frostSoft)
        }
        .padding(8)
        .background(MWTheme.bgPanel.opacity(0.72))
    }
}
