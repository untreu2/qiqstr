import Foundation
import SwiftUI

enum TimeFormat {
    static func relative(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let seconds = Date().timeIntervalSince(date)
        let diff = seconds.isFinite ? Int(min(max(seconds, 0), 86400 * 365 * 10_000)) : 0
        let locale = AppLanguage.locale
        guard diff < 86400 * 7 else {
            let f = DateFormatter()
            f.locale = locale
            f.setLocalizedDateFormatFromTemplate(Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) ? "MMMd" : "yMMMd")
            return f.string(from: date)
        }
        let unit: Duration.UnitsFormatStyle.Unit = diff < 60 ? .seconds : diff < 3600 ? .minutes : diff < 86400 ? .hours : .days
        let width: Duration.UnitsFormatStyle.UnitWidth = locale.language.languageCode == .english ? .narrow : .abbreviated
        return Duration.seconds(diff).formatted(.units(allowed: [unit], width: width, maximumUnitCount: 1, fractionalPart: .hide(rounded: .down)).locale(locale))
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
