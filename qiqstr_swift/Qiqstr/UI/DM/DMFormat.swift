import Foundation

enum DMFormat {
    static var locale: Locale {
        if let code = UserDefaults.standard.string(forKey: "app_language") { return Locale(identifier: code) }
        return .current
    }

    static func listTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time(date) }
        if calendar.isDateInYesterday(date) { return L("yesterday") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        if days < 7 { return L("daysAgo", ["days": max(days, 1)]) }
        return date.formatted(.dateTime.day().month(.defaultDigits).year().locale(locale))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    static func daySeparator(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("today") }
        if calendar.isDateInYesterday(date) { return L("yesterday") }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        }
        return date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    static func preview(_ message: DMMessage) -> (icon: String?, text: String) {
        guard message.isFile else { return (nil, message.content.replacingOccurrences(of: "\n", with: " ")) }
        let file = message.file
        if file?.isImage == true { return ("photo", L("dmPhoto")) }
        if file?.isVideo == true { return ("video", L("dmVideo")) }
        return ("paperclip", L("dmAttachment"))
    }
}
