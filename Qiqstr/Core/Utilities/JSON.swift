import Foundation

typealias JSONObject = [String: Any]

enum JSON {
    static func object(_ string: String?) -> JSONObject? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
    }

    static func array(_ string: String?) -> [JSONObject] {
        guard let string, let data = string.data(using: .utf8) else { return [] }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [JSONObject]) ?? []
    }

    static func any(_ string: String?) -> Any? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func string(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String? {
        if let s = self[key] as? String, !s.isEmpty { return s }
        return nil
    }
    func int(_ key: String) -> Int {
        if let n = self[key] as? NSNumber { return n.intValue }
        if let s = self[key] as? String, let n = Int(s) { return n }
        return 0
    }
    func bool(_ key: String) -> Bool { (self[key] as? Bool) ?? ((self[key] as? NSNumber)?.boolValue ?? false) }
    func strings(_ key: String) -> [String] { (self[key] as? [String]) ?? [] }
    func tags(_ key: String = "tags") -> [[String]] { (self[key] as? [[String]]) ?? [] }
}
