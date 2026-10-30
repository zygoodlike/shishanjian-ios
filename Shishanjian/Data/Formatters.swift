import Foundation

enum AppFormatters {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard var value, !value.isEmpty else { return nil }
        // Java Instant 可能带 9 位小数，ISO8601DateFormatter 只稳定支持 3 位
        if let dot = value.firstIndex(of: "."), let z = value.lastIndex(of: "Z") {
            let fraction = value[value.index(after: dot)..<z]
            if fraction.count > 3 {
                let head = value[..<dot]
                let short = String(fraction.prefix(3))
                value = "\(head).\(short)Z"
            }
        }
        return isoWithFraction.date(from: value) ?? isoPlain.date(from: value)
    }

    static func relativeTime(_ value: String?) -> String {
        guard let date = parse(value) else { return "" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "刚刚"
        case ..<3600: return "\(seconds / 60) 分钟前"
        case ..<86400: return "\(seconds / 3600) 小时前"
        case ..<604800: return "\(seconds / 86400) 天前"
        default: return dayFormatter.string(from: date)
        }
    }

    static func clockTime(_ value: String?) -> String {
        guard let date = parse(value) else { return "" }
        return clockFormatter.string(from: date)
    }

    static func dayAndTime(_ value: String?) -> String {
        guard let date = parse(value) else { return "" }
        return dayTimeFormatter.string(from: date)
    }

    static func whenLabel(_ type: String?) -> String {
        switch type {
        case "now": return "现在"
        case "today": return "今天"
        case "week": return "本周"
        case "long": return "长期"
        default: return ""
        }
    }

    static func cardStatusLabel(_ status: Int, fallback: String? = nil) -> String {
        switch status {
        case 0: return "审核中"
        case 1: return "进行中"
        case 2: return "已隐藏"
        case 3: return "已结束"
        case 4: return "待复核"
        case 5: return "已拒绝"
        case 6: return "已删除"
        default: return fallback ?? "未知"
        }
    }

    static func interestStatusLabel(_ status: Int) -> String {
        switch status {
        case 0: return "等待回应"
        case 1: return "已同意"
        case 2: return "已忽略"
        case 3: return "已撤回"
        case 4: return "已失效"
        default: return "未知"
        }
    }
}
