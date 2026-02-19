import Foundation
import SwiftData

@Model
final class DayPlan {
    @Attribute(.unique) var dateKey: String
    var dayRating: Int?
    var reflection: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TodoItem.dayPlan) var todos: [TodoItem]
    @Relationship(deleteRule: .cascade, inverse: \LinearLink.dayPlan) var linearLinks: [LinearLink]

    init(dateKey: String, dayRating: Int? = nil, reflection: String? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.dateKey = dateKey
        self.dayRating = dayRating
        self.reflection = reflection
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.todos = []
        self.linearLinks = []
    }
}

@Model
final class TodoItem {
    var title: String
    var priorityRaw: String
    var isDone: Bool
    var sortOrder: Int
    var sourceRaw: String
    var createdAt: Date
    var updatedAt: Date

    var dayPlan: DayPlan?

    init(
        title: String,
        priority: Priority,
        isDone: Bool = false,
        sortOrder: Int,
        source: TodoSource,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        dayPlan: DayPlan? = nil
    ) {
        self.title = title
        self.priorityRaw = priority.rawValue
        self.isDone = isDone
        self.sortOrder = sortOrder
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dayPlan = dayPlan
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var source: TodoSource {
        get { TodoSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class LinearLink {
    var url: String
    var displayText: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var dayPlan: DayPlan?

    init(
        url: String,
        displayText: String,
        sortOrder: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        dayPlan: DayPlan? = nil
    ) {
        self.url = url
        self.displayText = displayText
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dayPlan = dayPlan
    }
}
