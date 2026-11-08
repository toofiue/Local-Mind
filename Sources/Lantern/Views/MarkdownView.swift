import SwiftUI
import LanternKit

/// Renders a reply's Markdown with system text styles.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ForEach(Array(Markdown.parse(text).enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func inline(_ source: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(font(forHeading: level))
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(inline(text))
                .textSelection(.enabled)
        case .list(let items):
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(item.marker ?? "•")
                            .foregroundStyle(.secondary)
                        Text(inline(item.text))
                            .textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(item.level) * Space.lg)
                }
            }
        case .table(let header, let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.sm) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(inline(cell)).fontWeight(.semibold)
                        }
                    }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(inline(cell))
                            }
                        }
                    }
                }
                .textSelection(.enabled)
            }
        case .code(let language, let code, let isClosed):
            CodeBlockView(language: language, code: code, isClosed: isClosed)
        case .quote(let text):
            HStack(spacing: Space.md) {
                Capsule()
                    .fill(.separator)
                    .frame(width: Space.xs)
                Text(inline(text))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Divider()
        }
    }

    private func font(forHeading level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.semibold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String
    let isClosed: Bool
    @State private var didCopy = false

    private var title: String { language.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Code" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isClosed {
                    Button(didCopy ? "Copied" : "Copy") {
                        Clipboard.copy(code)
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: Motion.confirmation)
                            didCopy = false
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityLabel(didCopy ? "Copied" : "Copy \(title) code")
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)

            Divider()

            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(Space.md)
            }
        }
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}
