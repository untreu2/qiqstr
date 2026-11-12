import Foundation
import SwiftUI

enum TimeFormat {
    static func relative(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let diff = max(Int(Date().timeIntervalSince(date)), 0)
        let locale = AppLanguage.locale
        guard diff < 86400 * 7 else {
            let f = DateFormatter()
            f.locale = locale
            f.setLocalizedDateFormatFromTemplate(Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMMd" : "yMMMd")
            return f.string(from: date)
        }
        let unit: NSCalendar.Unit = diff < 60 ? .second : diff < 3600 ? .minute : diff < 86400 ? .hour : .day
        return durationFormatter(unit, locale: locale).string(from: TimeInterval(diff)) ?? ""
    }

    private static var durationFormatters: [String: DateComponentsFormatter] = [:]

    private static func durationFormatter(_ unit: NSCalendar.Unit, locale: Locale) -> DateComponentsFormatter {
        let key = "\(locale.identifier)-\(unit.rawValue)"
        if let cached = durationFormatters[key] { return cached }
        var calendar = Calendar.current
        calendar.locale = locale
        let f = DateComponentsFormatter()
        f.calendar = calendar
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 1
        f.allowedUnits = unit
        durationFormatters[key] = f
        return f
    }

    static func full(_ timestamp: Int) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    nonisolated static var now: Int { Int(Date().timeIntervalSince1970) }
}

struct RelativeTimeText: View {
    let timestamp: Int
    var prefix = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Text(prefix + TimeFormat.relative(timestamp))
        }
    }
}

enum Sats {
    static func format(_ sats: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = AppLanguage.locale
        return f.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0", with: "") }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000).replacingOccurrences(of: ".0", with: "") }
        return "\(n)"
    }
}
