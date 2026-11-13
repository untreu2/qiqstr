import Foundation

enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String, code: String)
    case quote([MarkdownBlock])
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case image(url: String, alt: String, link: String?)
    case table(header: [String], rows: [[String]])
    case nostr(String)
    case rule
}

struct MarkdownListItem: Hashable, Sendable {
    var checked: Bool?
    var blocks: [MarkdownBlock]
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\t", with: "    ")
        return parseBlocks(normalized.components(separatedBy: "\n"))
    }

    static func pubkeys(in text: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "(?:npub1|nprofile1)[02-9ac-hj-np-z]{20,}")
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern?.matches(in: text, range: range) ?? []
        return Array(Set(matches.compactMap { Range($0.range, in: text).flatMap { Nip19.pubkeyHex(from: String(text[$0])) } }))
    }

    private static let maxDepth = 8

    private static func parseBlocks(_ lines: [String], depth: Int = 0) -> [MarkdownBlock] {
        guard depth < maxDepth else { return paragraphBlocks(lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) }
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(contentsOf: paragraphBlocks(paragraph))
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flush()
                i += 1
                continue
            }

            if let fence = fenceMarker(trimmed) {
                flush()
                let language = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                let indent = leadingSpaces(line)
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence), candidate.allSatisfy({ $0 == fence.first }) { i += 1; break }
                    code.append(dedent(lines[i], by: indent))
                    i += 1
                }
                blocks.append(.code(language: language, code: code.joined(separator: "\n")))
                continue
            }

            if let heading = atxHeading(trimmed) {
                flush()
                blocks.append(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            if !paragraph.isEmpty, trimmed.count >= 2, trimmed.allSatisfy({ $0 == "=" }) {
                blocks.append(.heading(level: 1, text: paragraph.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")))
                paragraph = []
                i += 1
                continue
            }

            if !paragraph.isEmpty, trimmed.count >= 2, trimmed.allSatisfy({ $0 == "-" }) {
                blocks.append(.heading(level: 2, text: paragraph.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")))
                paragraph = []
                i += 1
                continue
            }

            if isRule(trimmed) {
                flush()
                blocks.append(.rule)
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flush()
                var inner: [String] = []
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(">") {
                        var stripped = String(candidate.dropFirst())
                        if stripped.hasPrefix(" ") { stripped.removeFirst() }
                        inner.append(stripped)
                    } else if !candidate.isEmpty, !(inner.last ?? "").trimmingCharacters(in: .whitespaces).isEmpty, !startsBlock(lines[i]) {
                        inner.append(candidate)
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.quote(parseBlocks(inner, depth: depth + 1)))
                continue
            }

            if let marker = listMarker(line), paragraph.isEmpty || !marker.ordered || marker.number == 1 {
                flush()
                let (list, next) = parseList(lines, from: i, marker: marker, depth: depth)
                blocks.append(list)
                i = next
                continue
            }

            if paragraph.isEmpty, i + 1 < lines.count, trimmed.contains("|"), isTableSeparator(lines[i + 1]) {
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !rowLine.isEmpty, rowLine.contains("|") else { break }
                    var cells = tableCells(rowLine)
                    if cells.count < header.count { cells += Array(repeating: "", count: header.count - cells.count) }
                    rows.append(Array(cells.prefix(header.count)))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            if paragraph.isEmpty, leadingSpaces(line) >= 4 {
                var code: [String] = []
                while i < lines.count {
                    let candidate = lines[i]
                    if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                        code.append("")
                    } else if leadingSpaces(candidate) >= 4 {
                        code.append(dedent(candidate, by: 4))
                    } else {
                        break
                    }
                    i += 1
                }
                while code.last?.isEmpty == true { code.removeLast() }
                blocks.append(.code(language: "", code: code.joined(separator: "\n")))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flush()
        return blocks
    }

    private struct ListMarker {
        var ordered: Bool
        var number: Int
        var indent: Int
        var contentOffset: Int
        var content: String
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        let indent = leadingSpaces(line)
        let rest = line.dropFirst(indent)
        guard let first = rest.first else { return nil }
        if "-*+".contains(first) {
            let after = rest.dropFirst()
            guard after.isEmpty || after.first == " " else { return nil }
            let spaces = min(4, after.prefix(while: { $0 == " " }).count)
            return ListMarker(ordered: false, number: 1, indent: indent, contentOffset: indent + 1 + max(1, spaces), content: String(after.drop(while: { $0 == " " })))
        }
        let digits = rest.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let after = rest.dropFirst(digits.count)
        guard let delimiter = after.first, delimiter == "." || delimiter == ")" else { return nil }
        let tail = after.dropFirst()
        guard tail.isEmpty || tail.first == " " else { return nil }
        let spaces = min(4, tail.prefix(while: { $0 == " " }).count)
        return ListMarker(ordered: true, number: Int(digits) ?? 1, indent: indent, contentOffset: indent + digits.count + 1 + max(1, spaces), content: String(tail.drop(while: { $0 == " " })))
    }

    private static func parseList(_ lines: [String], from start: Int, marker first: ListMarker, depth: Int) -> (MarkdownBlock, Int) {
        var items: [MarkdownListItem] = []
        var current: [String] = []
        var contentOffset = first.contentOffset
        var i = start
        var previousBlank = false
        var started = false

        func finishItem() {
            guard started else { return }
            var linesForItem = current
            var checked: Bool?
            if let head = linesForItem.first {
                let lower = head.lowercased()
                if lower.hasPrefix("[ ] ") || lower == "[ ]" { checked = false; linesForItem[0] = String(head.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                else if lower.hasPrefix("[x] ") || lower == "[x]" { checked = true; linesForItem[0] = String(head.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            }
            items.append(MarkdownListItem(checked: checked, blocks: parseBlocks(linesForItem, depth: depth + 1)))
            current = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                var j = i + 1
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                guard j < lines.count else { break }
                let nextLine = lines[j]
                let continues = leadingSpaces(nextLine) >= contentOffset || (listMarker(nextLine).map { $0.ordered == first.ordered && $0.indent < contentOffset } ?? false)
                guard continues else { break }
                current.append("")
                previousBlank = true
                i += 1
                continue
            }
            if let marker = listMarker(line), marker.indent < contentOffset, !isRule(trimmed) {
                guard marker.ordered == first.ordered, marker.indent <= first.indent + 3 else { break }
                finishItem()
                started = true
                contentOffset = marker.contentOffset
                current = [marker.content]
                previousBlank = false
                i += 1
                continue
            }
            if leadingSpaces(line) >= contentOffset {
                current.append(dedent(line, by: contentOffset))
            } else if !previousBlank, !startsBlock(line) {
                current.append(trimmed)
            } else {
                break
            }
            previousBlank = false
            i += 1
        }
        finishItem()
        return (.list(ordered: first.ordered, start: first.number, items: items), i)
    }

    private static func paragraphBlocks(_ lines: [String]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var text = ""
        func flushText() {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { blocks.append(.paragraph(cleaned)) }
            text = ""
        }
        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let entity = standaloneEntity(trimmed) {
                flushText()
                blocks.append(.nostr(entity))
                continue
            }
            if isImageURL(trimmed) {
                flushText()
                blocks.append(.image(url: trimmed, alt: "", link: nil))
                continue
            }
            var segments = splitImages(trimmed)
            if segments.count == 1, case .text = segments[0] {
                let hardBreak = raw.hasSuffix("  ") || raw.hasSuffix("\\")
                var piece = trimmed
                if piece.hasSuffix("\\") { piece.removeLast() }
                if !text.isEmpty, !text.hasSuffix("\n") { text += " " }
                text += piece
                if hardBreak, index < lines.count - 1 { text += "\n" }
                continue
            }
            for segment in segments {
                switch segment {
                case .text(let value):
                    if !text.isEmpty, !text.hasSuffix("\n") { text += " " }
                    text += value
                case .image(let url, let alt, let link):
                    flushText()
                    blocks.append(.image(url: url, alt: alt, link: link))
                }
            }
            segments.removeAll()
        }
        flushText()
        return blocks
    }

    private enum Segment { case text(String), image(String, String, String?) }

    private static let linkedImage = try! NSRegularExpression(pattern: #"\[!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)\]\(\s*([^)\s]+)\s*\)"#)
    private static let image = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)"#)

    private static func splitImages(_ text: String) -> [Segment] {
        guard text.contains("![") else { return [.text(text)] }
        let ns = text as NSString
        var matches: [(NSRange, Segment)] = []
        for m in linkedImage.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            matches.append((m.range, .image(ns.substring(with: m.range(at: 2)), ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 3)))))
        }
        for m in image.matches(in: text, range: NSRange(location: 0, length: ns.length)) where !matches.contains(where: { NSIntersectionRange($0.0, m.range).length > 0 }) {
            matches.append((m.range, .image(ns.substring(with: m.range(at: 2)), ns.substring(with: m.range(at: 1)), nil)))
        }
        guard !matches.isEmpty else { return [.text(text)] }
        matches.sort { $0.0.location < $1.0.location }
        var segments: [Segment] = []
        var cursor = 0
        for (range, segment) in matches {
            if range.location > cursor {
                let piece = ns.substring(with: NSRange(location: cursor, length: range.location - cursor)).trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { segments.append(.text(piece)) }
            }
            segments.append(segment)
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            let piece = ns.substring(from: cursor).trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty { segments.append(.text(piece)) }
        }
        return segments
    }

    private static let entityPattern = try! NSRegularExpression(pattern: "^(?:nostr:)?((?:note1|nevent1|naddr1|npub1|nprofile1)[02-9ac-hj-np-z]{20,})$")

    private static func standaloneEntity(_ text: String) -> String? {
        let ns = text as NSString
        guard let match = entityPattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    static func isImageURL(_ text: String) -> Bool {
        guard text.hasPrefix("http"), !text.contains(" "), let url = URL(string: text) else { return false }
        return ["jpg", "jpeg", "png", "gif", "webp", "avif", "heic"].contains(url.pathExtension.lowercased())
    }

    private static func fenceMarker(_ trimmed: String) -> String? {
        for char in ["`", "~"] {
            let run = trimmed.prefix(while: { String($0) == char })
            if run.count >= 3 {
                if char == "`", trimmed.dropFirst(run.count).contains("`") { return nil }
                return String(run)
            }
        }
        return nil
    }

    private static func atxHeading(_ trimmed: String) -> (level: Int, text: String)? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (hashes, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        let cells = tableCells(trimmed)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.allSatisfy { "-:".contains($0) } && c.contains("-")
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var row = line
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func startsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return fenceMarker(trimmed) != nil || atxHeading(trimmed) != nil || isRule(trimmed) || trimmed.hasPrefix(">") || listMarker(line) != nil
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    private static func dedent(_ line: String, by count: Int) -> String {
        String(line.dropFirst(min(count, leadingSpaces(line))))
    }
}
