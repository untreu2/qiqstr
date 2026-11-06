import Foundation

enum WalletFormat {
    static func sats(_ value: Int) -> String { Sats.format(abs(value)) }

    static func signed(_ value: Int, incoming: Bool) -> String {
        "\(incoming ? "+" : "-")\(sats(value))"
    }

    static func timestamp(_ ts: Int) -> String {
        guard ts > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return L("yesterday") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        if days < 7 { return L("daysAgo", ["days": days]) }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func truncated(_ text: String, head: Int = 12, tail: Int = 8) -> String {
        guard text.count > head + tail + 3 else { return text }
        return "\(text.prefix(head))…\(text.suffix(tail))"
    }
}
