import Foundation

enum TimeFormat {
    static func relative(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "\(max(diff, 0))s" }
        if diff < 3600 { return "\(diff / 60)m" }
        if diff < 86400 { return "\(diff / 3600)h" }
        if diff < 86400 * 7 { return "\(diff / 86400)d" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return f.string(from: date)
    }

    static func full(_ timestamp: Int) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    nonisolated static var now: Int { Int(Date().timeIntervalSince1970) }
}

enum Sats {
    static func format(_ sats: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0", with: "") }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000).replacingOccurrences(of: ".0", with: "") }
        return "\(n)"
    }
}
