import Foundation

enum Priority: String, CaseIterable, Codable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

enum TodoSource: String, Codable {
    case manual
    case rollover
}

enum PlannerRules {
    static let priorityCycle: [Priority] = [.high, .medium, .low]

    static func nextPriority(manualTodoCount: Int) -> Priority {
        let safeCount = max(0, manualTodoCount)
        return priorityCycle[safeCount % priorityCycle.count]
    }

    static func assignedPriorities(forNewTodoCount count: Int) -> [Priority] {
        guard count > 0 else { return [] }
        return (0..<count).map { nextPriority(manualTodoCount: $0) }
    }

    static func nextCarryForwardDate(
        after baseDate: Date,
        calendar: Calendar = .current,
        ignoreWeekends: Bool
    ) -> Date {
        var nextDate = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        guard ignoreWeekends else { return nextDate }

        var attempts = 0
        while isSaturdayOrSunday(nextDate, calendar: calendar), attempts < 7 {
            let shifted = calendar.date(byAdding: .day, value: 1, to: nextDate) ?? nextDate
            guard shifted != nextDate else { break }
            nextDate = shifted
            attempts += 1
        }

        return nextDate
    }

    private static func isSaturdayOrSunday(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }
}
