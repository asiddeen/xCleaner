import Foundation

public enum ByteFormatting {
    public static func string(from bytes: Int64) -> String {
        let clamped = max(0, bytes)
        let units = ["B", "KB", "MB", "GB", "TB"]
        if clamped < 1000 {
            return "\(clamped) B"
        }
        var value = Double(clamped)
        var unitIndex = 0
        while value >= 999.5 && unitIndex < units.count - 1 {
            value /= 1000.0
            unitIndex += 1
        }
        if value >= 100 || unitIndex <= 1 {
            return String(format: "%.0f %@", value, units[unitIndex])
        } else if value >= 10 {
            return String(format: "%.1f %@", value, units[unitIndex])
        } else {
            return String(format: "%.2f %@", value, units[unitIndex])
        }
    }

    public static func daysBetween(_ earlier: Date?, and now: Date = Date()) -> Int? {
        guard let earlier else { return nil }
        let seconds = max(0, now.timeIntervalSince(earlier))
        return Int(seconds / 86_400.0)
    }

    public static func relativeAge(from date: Date?, now: Date = Date()) -> String {
        guard let days = daysBetween(date, and: now) else { return "Unknown date" }
        if days == 0 { return "Today" }
        if days == 1 { return "1d ago" }
        if days < 30 { return "\(days)d ago" }
        if days < 365 {
            let months = days / 30
            return "\(months)mo ago"
        }
        let years = Double(days) / 365.0
        return String(format: "%.1fyr ago", years)
    }
}
