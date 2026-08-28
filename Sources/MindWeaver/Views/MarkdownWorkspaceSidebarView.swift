import SwiftUI

struct MarkdownWorkspaceSidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 10) {
            workspaceHeader

            fileExplorer

                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusSummary)
                    .font(sidebarFont(size: 12))
                    .bold()
                    .foregroundStyle(MWTheme.frostSoft)

                Text(appModel.statusMessage)
                    .font(sidebarFont(size: 11))
                    .foregroundStyle(MWTheme.textMuted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .bottom])
        }
        .font(sidebarFont(size: 13))
        .background { MWTheme.appBackground }
        .navigationSplitViewColumnWidth(min: 280, ideal: 340)
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Markdown Workspace", systemImage: "square.and.pencil")
                .font(sidebarFont(size: 13, weight: .semibold))
                .foregroundStyle(MWTheme.emberHot)

            if let workspace = appModel.markdownWorkspace {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.displayName)
                        .font(sidebarFont(size: 15, weight: .semibold))
                        .foregroundStyle(MWTheme.text)
                        .lineLimit(1)

                    Text(workspace.displayPath)
                        .font(sidebarFont(size: 11, design: .monospaced))
                        .foregroundStyle(MWTheme.textMuted)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }

            HStack {
                Button("Open…") {
                    appModel.openMarkdownWorkspace()
                }

                Button("Default Notes") {
                    appModel.openDefaultNotesWorkspace()
                }
            }
        }
        .padding([.top, .horizontal])
        .mwPanel(cornerRadius: 18)
        .padding(.horizontal, 8)
    }

    private var fileExplorer: some View {
        List {
            OutlineGroup(appModel.markdownFileTree, children: \.children) { node in
                Button {
                    if !node.isFolder {
                        appModel.selectMarkdownFile(node.url)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: node.isFolder ? "folder" : "doc.text")
                            .foregroundStyle(node.isFolder ? MWTheme.frostSoft : MWTheme.textMuted)

                        Text(node.name)
                            .lineLimit(1)

                        if appModel.selectedMarkdownFileURL == node.url && appModel.isMarkdownDirty {
                            Circle()
                                .fill(MWTheme.emberHot)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(node.isFolder)
                .listRowBackground(rowBackground(isSelected: appModel.selectedMarkdownFileURL == node.url))
            }
        }
        .mwScrollBackground()
    }

    private var statusSummary: String {
        let fileCount = countFiles(in: appModel.markdownFileTree)
        let dirty = appModel.isMarkdownDirty ? " • unsaved" : ""
        return "\(fileCount) Markdown file\(fileCount == 1 ? "" : "s")\(dirty)"
    }

    private func countFiles(in nodes: [MarkdownFileNode]) -> Int {
        nodes.reduce(0) { total, node in
            total + (node.isFolder ? countFiles(in: node.children ?? []) : 1)
        }
    }

    private func sidebarFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * appModel.readabilityScale, weight: weight, design: design)
    }

    private func rowBackground(isSelected: Bool) -> Color {
        isSelected ? MWTheme.emberHot.opacity(0.20) : Color.clear
    }
}
