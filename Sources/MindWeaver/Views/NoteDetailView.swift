import AppKit
import SwiftUI

struct NoteDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let note = appModel.selectedNote {
                noteHeader(note)

                Divider()

                MarkdownPreview(markdown: note.content)
            } else {
                emptyState
            }

            Divider()

            CommandOutputView()
        }
    }

    private func noteHeader(_ note: MWNote) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.title2)
                    .bold()

                Text(note.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Open in Neovim") {
                openInNeovim(note)
            }
            .disabled(appModel.resolvedFileURL(for: note) == nil)

            Button("Reveal in Finder") {
                reveal(note)
            }
            .disabled(appModel.resolvedFileURL(for: note) == nil)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text("Mind Weaver")
                .font(.title2)
                .bold()

            Text("A native SwiftUI shell around the Go mw engine.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reveal(_ note: MWNote) {
        guard let fileURL = appModel.resolvedFileURL(for: note) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func openInNeovim(_ note: MWNote) {
        guard let fileURL = appModel.resolvedFileURL(for: note) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["wisp", "nvim", fileURL.path]

        do {
            try process.run()
        } catch {
            NSSound.beep()
        }
    }
}

struct MarkdownPreview: View {
    var markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(markdown)
    }

    var body: some View {
        ScrollView {
            if markdown.isEmpty {
                Text("Markdown preview will appear here when mw returns note content.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(font(forHeadingLevel: level))
                .bold(level <= 3)
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 8 : 4)

        case .bullet(let level, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(text)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(level) * 18)

        case .paragraph(let text):
            Text(text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)

        case .code(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

        case .quote(let text):
            Text(text)
                .italic()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 3)
                }
        }
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1: .largeTitle
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }
}

enum MarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case bullet(level: Int, text: String)
    case paragraph(String)
    case code(String)
    case quote(String)

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = stripFrontmatter(markdown).components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var inCodeBlock = false

        func flushParagraph() {
            let text = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        func flushCode() {
            blocks.append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                if inCodeBlock {
                    flushCode()
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let bullet = parseBullet(line) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }

            paragraphLines.append(trimmed)
        }

        flushParagraph()
        if inCodeBlock || !codeLines.isEmpty {
            flushCode()
        }

        return blocks
    }

    private static func stripFrontmatter(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return markdown }

        for index in lines.indices.dropFirst() {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                return lines.dropFirst(index + 1).joined(separator: "\n")
            }
        }

        return markdown
    }

    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        var level = 0
        for character in trimmed {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }

        guard level > 0, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " else { return nil }
        return .heading(level: level, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func parseBullet(_ line: String) -> MarkdownBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return nil }

        let leadingSpaces = line.prefix { $0 == " " || $0 == "\t" }.count
        let level = max(0, leadingSpaces / 2)
        let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return .bullet(level: level, text: text)
    }
}
