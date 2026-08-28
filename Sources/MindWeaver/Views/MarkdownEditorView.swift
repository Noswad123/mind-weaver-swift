import AppKit
import SwiftUI

struct MarkdownEditorView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if appModel.selectedMarkdownFileURL == nil {
                emptyState
            } else {
                documentHeader

                Divider()

                editorBody
            }

            Divider()

            CommandOutputView()
        }
        .background { MWTheme.appBackground }
    }

    private var documentHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(appModel.selectedMarkdownFileName)
                        .font(readableFont(size: 21, weight: .bold))
                        .foregroundStyle(MWTheme.emberHot)

                    if appModel.isMarkdownDirty {
                        Text("Unsaved")
                            .font(readableFont(size: 11, weight: .semibold))
                            .foregroundStyle(MWTheme.bgVoid)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(MWTheme.emberHot, in: Capsule())
                    }
                }

                Text(appModel.selectedMarkdownDisplayPath)
                    .font(readableFont(size: 12, design: .monospaced))
                    .foregroundStyle(MWTheme.textMuted)
                    .textSelection(.enabled)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Picker("View", selection: $appModel.markdownEditorDisplayMode) {
                    ForEach(MarkdownEditorDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .help("Toggle editor focus with ⌘E, toggle rendered Markdown focus with ⌘M")

                Text("⌘S sidebar • ⌘E editor • ⌘M preview")
                    .font(readableFont(size: 10))
                    .foregroundStyle(MWTheme.textMuted)
            }

            Button("Save") {
                appModel.saveMarkdownDocument()
            }
            .disabled(!appModel.canSaveMarkdownDocument)

            Button("Reveal in Finder") {
                revealSelectedFile()
            }
        }
        .padding()
    }

    @ViewBuilder
    private var editorBody: some View {
        switch appModel.markdownEditorDisplayMode {
        case .source:
            sourceEditor
        case .preview:
            MarkdownPreview(markdown: appModel.markdownEditorText)
                .environmentObject(appModel)
        case .split:
            HSplitView {
                sourceEditor
                    .frame(minWidth: 320)

                MarkdownPreview(markdown: appModel.markdownEditorText)
                    .environmentObject(appModel)
                    .frame(minWidth: 320)
            }
        }
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Source")
                .font(readableFont(size: 12, weight: .semibold))
                .foregroundStyle(MWTheme.frostSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MWTheme.bgPanel2.opacity(0.80))

            TextEditor(text: $appModel.markdownEditorText)
                .font(.system(size: 14 * appModel.readabilityScale, design: .monospaced))
                .foregroundStyle(MWTheme.text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(MWTheme.panelFill)
        }
        .background(MWTheme.panelFill)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            AnimatedBrainLogo(isAnimating: false, size: 96)

            Text("Open a Markdown file or folder to start editing.")
                .font(readableFont(size: 15))
                .foregroundStyle(MWTheme.textMuted)

            Button("Open Markdown File or Folder…") {
                appModel.openMarkdownWorkspace()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func revealSelectedFile() {
        guard let url = appModel.selectedMarkdownFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func readableFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * appModel.readabilityScale, weight: weight, design: design)
    }
}
