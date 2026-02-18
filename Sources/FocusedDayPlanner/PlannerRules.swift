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
}
