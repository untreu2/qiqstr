import Foundation

enum SettingsICU {
    static func format(_ key: String, _ args: [String: Int]) -> String {
        var text = Localizer.shared.string(key)
        for (name, value) in args {
            text = resolvePlurals(in: text, name: name, value: value)
        }
        for (name, value) in args {
            text = text.replacingOccurrences(of: "{\(name)}", with: "\(value)")
        }
        return text
    }

    private static func resolvePlurals(in text: String, name: String, value: Int) -> String {
        var result = text
        let marker = "{\(name), plural,"
        while let start = result.range(of: marker) {
            let chars = Array(result[start.upperBound...])
            var index = 0
            var branches: [String: String] = [:]
            var closing: Int?
            while index < chars.count {
                while index < chars.count, chars[index].isWhitespace { index += 1 }
                guard index < chars.count else { break }
                if chars[index] == "}" { closing = index; break }
                var selector = ""
                while index < chars.count, chars[index] != "{", !chars[index].isWhitespace {
                    selector.append(chars[index]); index += 1
                }
                while index < chars.count, chars[index].isWhitespace { index += 1 }
                guard index < chars.count, chars[index] == "{" else { break }
                var depth = 0
                var body = ""
                while index < chars.count {
                    let c = chars[index]
                    if c == "{" { depth += 1; if depth == 1 { index += 1; continue } }
                    if c == "}" { depth -= 1; if depth == 0 { index += 1; break } }
                    body.append(c)
                    index += 1
                }
                branches[selector] = body
            }
            guard let closing else { break }
            let chosen = branches["=\(value)"] ?? (value == 1 ? branches["one"] : nil) ?? branches["other"] ?? ""
            let replacement = chosen.replacingOccurrences(of: "#", with: "\(value)")
            let endIndex = result.index(start.upperBound, offsetBy: closing + 1)
            result.replaceSubrange(start.lowerBound..<endIndex, with: replacement)
        }
        return result
    }
}
