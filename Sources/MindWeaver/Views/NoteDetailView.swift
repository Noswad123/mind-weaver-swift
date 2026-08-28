import AppKit
import SwiftUI

struct NoteDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let note = appModel.selectedNote {
                noteHeader(note)

                Divider()

                MarkdownPreview(note: note)
            } else {
                emptyState
            }

            Divider()

            CommandOutputView()
        }
        .background { MWTheme.appBackground }
    }

    private func noteHeader(_ note: MWNote) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(readableFont(size: 21, weight: .bold))
                    .bold()
                    .foregroundStyle(MWTheme.emberHot)

                Text(note.displayPath)
                    .font(readableFont(size: 12))
                    .foregroundStyle(MWTheme.textMuted)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Open Externally") {
                appModel.openExternally(note)
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
            AnimatedBrainLogo(isAnimating: appModel.isWorking, size: 96)

            Text("A native SwiftUI shell around the Go mw engine.")
                .font(readableFont(size: 14))
                .foregroundStyle(MWTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func readableFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * appModel.readabilityScale, weight: weight, design: design)
    }

    private func reveal(_ note: MWNote) {
        guard let fileURL = appModel.resolvedFileURL(for: note) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

}

struct MarkdownPreview: View {
    @EnvironmentObject private var appModel: AppModel

    var note: MWNote?
    var markdown: String

    init(note: MWNote) {
        self.note = note
        self.markdown = note.content
    }

    init(markdown: String) {
        self.note = nil
        self.markdown = markdown
    }

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(markdown)
    }

    var body: some View {
        ScrollView {
            if markdown.isEmpty {
                Text("Markdown preview will appear here when mw returns note content.")
                    .font(markdownFont(size: 14))
                    .foregroundStyle(MWTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .font(markdownFont(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
        .background {
            ZStack {
                MWTheme.appBackground
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(MWTheme.panelFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(MWTheme.emberHot.opacity(0.28), lineWidth: 1)
                    }
                    .padding(12)
            }
        }
        .foregroundStyle(MWTheme.text)
        .tint(MWTheme.frostSoft)
        .environment(\.openURL, OpenURLAction { url in
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let target = components.queryItems?.first(where: { $0.name == "target" })?.value else {
                return .systemAction
            }

            if url.scheme == "mindweaver-note", let note {
                return appModel.openNoteLink(target: target, from: note) ? .handled : .discarded
            }

            if url.scheme == "mindweaver-markdown" {
                return appModel.openMarkdownLink(target: target) ? .handled : .discarded
            }

            return .systemAction
        })
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(font(forHeadingLevel: level))
                .bold(level <= 3)
                .foregroundStyle(MWTheme.emberHot)
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 8 : 4)

        case .bullet(let level, let text):
            listItem(marker: "•", text: text, level: level)

        case .numberedListItem(let level, let number, let text):
            listItem(marker: "\(number).", text: text, level: level)

        case .task(let level, let isDone, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isDone ? MWTheme.emberHot : MWTheme.frostSoft)
                inlineText(text)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? MWTheme.textMuted : MWTheme.text)
                    .textSelection(.enabled)
            }
            .font(markdownFont(size: 14))
            .padding(.leading, CGFloat(level) * 18)

        case .paragraph(let text):
            inlineText(text)
                .font(markdownFont(size: 14))
                .lineSpacing(4 * appModel.readabilityScale)
                .textSelection(.enabled)

        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 0) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(markdownFont(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MWTheme.frostSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MWTheme.bgPanel2.opacity(0.72))
                }

                Text(text)
                    .font(markdownFont(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MWTheme.frostSoft.opacity(0.20), lineWidth: 1)
            }

        case .quote(let text):
            inlineText(text)
                .font(markdownFont(size: 14))
                .italic()
                .foregroundStyle(MWTheme.textMuted)
                .textSelection(.enabled)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(MWTheme.emberHot.opacity(0.45))
                        .frame(width: 3)
                }

        case .horizontalRule:
            Rectangle()
                .fill(MWTheme.frostSoft.opacity(0.28))
                .frame(height: 1)
                .padding(.vertical, 8)
        }
    }

    private func listItem(marker: String, text: String, level: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(markdownFont(size: 14, weight: .semibold))
                .foregroundStyle(MWTheme.frostSoft)
                .frame(minWidth: marker == "•" ? 10 : 24, alignment: .trailing)
            inlineText(text)
                .textSelection(.enabled)
        }
        .font(markdownFont(size: 14))
        .padding(.leading, CGFloat(level) * 18)
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1: markdownFont(size: 34)
        case 2: markdownFont(size: 21)
        case 3: markdownFont(size: 17)
        default: markdownFont(size: 14, weight: .semibold)
        }
    }

    private func markdownFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * appModel.readabilityScale, weight: weight, design: design)
    }

    private func inlineText(_ text: String) -> MarkdownInlineText {
        MarkdownInlineText(text: text, urlBuilder: inlineURL(target:isWikiLink:))
    }

    private func inlineURL(target: String, isWikiLink: Bool) -> URL? {
        if !isWikiLink,
           let external = URL(string: target),
           let scheme = external.scheme,
           ["http", "https", "mailto", "tel"].contains(scheme.lowercased()) {
            return external
        }

        if note == nil {
            var components = URLComponents()
            components.scheme = "mindweaver-markdown"
            components.host = "open"
            components.queryItems = [URLQueryItem(name: "target", value: target)]
            return components.url
        }

        var components = URLComponents()
        components.scheme = "mindweaver-note"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "target", value: target)]
        return components.url
    }
}

private struct MarkdownInlineText: View {
    var text: String
    var urlBuilder: (String, Bool) -> URL?

    @State private var pushedPointerCursor = false

    private var inlines: [MarkdownInline] {
        MarkdownInline.parse(text)
    }

    private var hasLinks: Bool {
        inlines.contains { $0.target != nil }
    }

    private var attributedText: AttributedString {
        inlines.reduce(into: AttributedString()) { output, inline in
            var piece = AttributedString(inline.label)
            if inline.isCode {
                piece.inlinePresentationIntent = .code
            }
            if let target = inline.target,
               let url = urlBuilder(target, inline.isWikiLink) {
                piece.link = url
            }
            output.append(piece)
        }
    }

    var body: some View {
        Text(attributedText)
            .onHover { hovering in
                guard hasLinks else { return }
                if hovering, !pushedPointerCursor {
                    NSCursor.pointingHand.push()
                    pushedPointerCursor = true
                } else if !hovering, pushedPointerCursor {
                    NSCursor.pop()
                    pushedPointerCursor = false
                }
            }
            .onDisappear {
                if pushedPointerCursor {
                    NSCursor.pop()
                    pushedPointerCursor = false
                }
            }
    }
}

private struct MarkdownInline: Hashable {
    var label: String
    var target: String?
    var isWikiLink: Bool
    var isCode: Bool

    static func text(_ value: String) -> MarkdownInline {
        MarkdownInline(label: value, target: nil, isWikiLink: false, isCode: false)
    }

    static func code(_ value: String) -> MarkdownInline {
        MarkdownInline(label: value, target: nil, isWikiLink: false, isCode: true)
    }

    static func link(label: String, target: String, isWikiLink: Bool) -> MarkdownInline {
        MarkdownInline(label: label, target: target, isWikiLink: isWikiLink, isCode: false)
    }

    static func parse(_ text: String) -> [MarkdownInline] {
        var output: [MarkdownInline] = []
        var index = text.startIndex
        var plainStart = index

        func flushPlain(upTo end: String.Index) {
            guard plainStart < end else { return }
            output.append(.text(String(text[plainStart..<end])))
        }

        while index < text.endIndex {
            if text[index] == "`",
               let close = text[text.index(after: index)...].firstIndex(of: "`") {
                flushPlain(upTo: index)
                let codeStart = text.index(after: index)
                output.append(.code(String(text[codeStart..<close])))
                index = text.index(after: close)
                plainStart = index
                continue
            }

            if text[index...].hasPrefix("[["),
               let close = text[index...].range(of: "]]") {
                flushPlain(upTo: index)
                let contentStart = text.index(index, offsetBy: 2)
                let raw = String(text[contentStart..<close.lowerBound])
                let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let target = String(parts.first ?? "")
                let label = parts.count > 1 ? String(parts[1]) : target
                output.append(.link(label: label.isEmpty ? target : label, target: target, isWikiLink: true))
                index = close.upperBound
                plainStart = index
                continue
            }

            if text[index] == "[",
               (index == text.startIndex || text[text.index(before: index)] != "!"),
               let labelClose = text[index...].firstIndex(of: "]"),
               labelClose < text.index(before: text.endIndex) {
                let afterLabel = text.index(after: labelClose)
                if text[afterLabel] == "(",
                   let targetClose = text[afterLabel...].firstIndex(of: ")") {
                    flushPlain(upTo: index)
                    let labelStart = text.index(after: index)
                    let targetStart = text.index(after: afterLabel)
                    let label = String(text[labelStart..<labelClose])
                    let target = String(text[targetStart..<targetClose])
                    output.append(.link(label: label.isEmpty ? target : label, target: target, isWikiLink: false))
                    index = text.index(after: targetClose)
                    plainStart = index
                    continue
                }
            }

            index = text.index(after: index)
        }

        flushPlain(upTo: text.endIndex)
        return output
    }
}

enum MarkdownBlock: Hashable {
    case heading(level: Int, text: String)
    case bullet(level: Int, text: String)
    case numberedListItem(level: Int, number: Int, text: String)
    case task(level: Int, isDone: Bool, text: String)
    case paragraph(String)
    case code(language: String?, text: String)
    case quote(String)
    case horizontalRule

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = stripFrontmatter(markdown).components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var inCodeBlock = false
        var codeLanguage: String?

        func flushParagraph() {
            let text = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        func flushCode() {
            blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n")))
            codeLines.removeAll()
            codeLanguage = nil
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
                    let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    codeLanguage = language.isEmpty ? nil : language
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

            if let numberedListItem = parseNumberedListItem(line) {
                flushParagraph()
                blocks.append(numberedListItem)
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(.horizontalRule)
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

        if let task = parseTaskText(text, level: level) {
            return task
        }

        return .bullet(level: level, text: text)
    }

    private static func parseNumberedListItem(_ line: String) -> MarkdownBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: ".") else { return nil }

        let numberPart = trimmed[..<dot]
        guard !numberPart.isEmpty, numberPart.allSatisfy(\.isNumber), let number = Int(numberPart) else { return nil }

        let afterDot = trimmed.index(after: dot)
        guard afterDot < trimmed.endIndex, trimmed[afterDot] == " " else { return nil }

        let leadingSpaces = line.prefix { $0 == " " || $0 == "\t" }.count
        let level = max(0, leadingSpaces / 2)
        let textStart = trimmed.index(after: afterDot)
        let text = String(trimmed[textStart...]).trimmingCharacters(in: .whitespaces)

        if let task = parseTaskText(text, level: level) {
            return task
        }

        return .numberedListItem(level: level, number: number, text: text)
    }

    private static func parseTaskText(_ text: String, level: Int) -> MarkdownBlock? {
        let lower = text.lowercased()
        if lower.hasPrefix("[ ] ") {
            return .task(level: level, isDone: false, text: String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces))
        }
        if lower.hasPrefix("[x] ") {
            return .task(level: level, isDone: true, text: String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let compact = trimmed.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" }
            || compact.allSatisfy { $0 == "*" }
            || compact.allSatisfy { $0 == "_" }
    }
}
