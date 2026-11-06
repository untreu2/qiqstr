import SwiftUI

enum MarkdownInline {
    private static let codeSpan = try! NSRegularExpression(pattern: "`+[^`]*`+")
    private static let mention = try! NSRegularExpression(pattern: #"(?<![\w/\(\[=:])(?:nostr:)?((?:npub1|nprofile1|note1|nevent1|naddr1)[02-9ac-hj-np-z]{20,})"#)
    private static let bareURL = try! NSRegularExpression(pattern: #"(?<![\(<\[\"'=\w/])(https?://[^\s<>\)\]\"']+[^\s<>\)\]\"'.,;:!?])"#)

    static func attributed(_ text: String, name: (String) -> String?) -> AttributedString {
        let prepared = transformOutsideCode(text) { segment in
            autolink(linkMentions(segment, name: name))
        }
        let options = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        var result = (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(text)
        for run in result.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                result[run.range].backgroundColor = AppColors.inputFill
            }
            if let link = run.link {
                if link.scheme == "nostr" {
                    result[run.range].foregroundColor = AppColors.link
                    result[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
                } else {
                    result[run.range].foregroundColor = AppColors.link
                }
            }
        }
        return result
    }

    static func plain(_ text: String) -> String {
        String(attributed(text, name: { _ in nil }).characters)
    }

    private static func transformOutsideCode(_ text: String, _ transform: (String) -> String) -> String {
        let ns = text as NSString
        var output = ""
        var cursor = 0
        for match in codeSpan.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                output += transform(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            output += ns.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { output += transform(ns.substring(from: cursor)) }
        return output
    }

    private static func linkMentions(_ text: String, name: (String) -> String?) -> String {
        guard text.contains("1") else { return text }
        return replace(mention, in: text) { ns, match in
            let entity = ns.substring(with: match.range(at: 1))
            return "[\(escape(label(for: entity, name: name)))](nostr:\(entity))"
        }
    }

    private static func autolink(_ text: String) -> String {
        guard text.contains("http") else { return text }
        return replace(bareURL, in: text) { ns, match in
            "<\(ns.substring(with: match.range(at: 1)))>"
        }
    }

    private static func label(for entity: String, name: (String) -> String?) -> String {
        if entity.hasPrefix("npub1") || entity.hasPrefix("nprofile1") {
            if let pubkey = Nip19.pubkeyHex(from: entity), let value = name(pubkey) { return "@\(value)" }
            return "@\(entity.prefix(12))…"
        }
        if entity.hasPrefix("naddr1") { return L("article") }
        return "\(entity.prefix(12))…"
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, _ make: (NSString, NSTextCheckingResult) -> String) -> String {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var output = ""
        var cursor = 0
        for match in matches {
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += make(ns, match)
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }

    private static func escape(_ text: String) -> String {
        var output = ""
        for char in text {
            if "\\[]()*_`<>#~".contains(char) { output.append("\\") }
            output.append(char)
        }
        return output
    }
}
