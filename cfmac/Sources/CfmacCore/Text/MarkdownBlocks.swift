import Foundation

/// The block structure of a Markdown document, enough to lay out legal pages.
/// Inline formatting (links, emphasis) is left in the text for `AttributedString` to parse.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case preformatted(String)
    case rule
}

public enum MarkdownBlocks {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var fence: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = fence {
                    blocks.append(.preformatted(open.joined(separator: "\n")))
                    fence = nil
                } else {
                    flushParagraph()
                    fence = []
                }
                continue
            }
            if fence != nil {
                fence?.append(rawLine)
                continue
            }
            if line.isEmpty {
                flushParagraph()
            } else if let heading = heading(line) {
                flushParagraph()
                blocks.append(heading)
            } else if line == "---" || line == "***" {
                flushParagraph()
                blocks.append(.rule)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if case .bullet(let previous) = blocks.last, paragraph.isEmpty, rawLine.hasPrefix("  ") {
                // Continuation line of a wrapped bullet.
                blocks[blocks.count - 1] = .bullet(previous + " " + line)
            } else {
                paragraph.append(line)
            }
        }
        if let open = fence { blocks.append(.preformatted(open.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)))
    }
}
