import Foundation
import SwiftData
import Testing
@testable import FocusedDayPlanner

@Suite(.serialized)
struct PlannerStoreCarryForwardTests {
    @Test
    @MainActor
    func carryPendingTodosDoesNotDuplicateWhenDestinationIsCreatedToday() throws {
        let calendar = makeUTCCalendar()
        let container = try makeInMemoryContainer()
        let store = PlannerStore(context: container.mainContext, calendar: calendar)

        let previousDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 3)))
        let previousKey = store.dateKey(for: previousDate)

        store.ensureDayPlan(for: previousKey, now: previousDate)
        let previousPlan = try #require(store.fetchDayPlan(for: previousKey))
        store.addTodo(title: "Task A", to: previousPlan, now: previousDate)
        store.addTodo(title: "Task B", to: previousPlan, now: previousDate)

        let destinationKey = store.carryPendingTodosToNextDay(from: previousPlan, now: now, ignoreWeekends: false)
        let destination = try #require(store.fetchDayPlan(for: destinationKey))

        #expect(destination.todos.count == 2)
        #expect(destination.todos.allSatisfy { $0.source == .rollover })
    }

    @Test
    @MainActor
    func carrySingleTodoDoesNotDuplicateWhenDestinationIsCreatedToday() throws {
        let calendar = makeUTCCalendar()
        let container = try makeInMemoryContainer()
        let store = PlannerStore(context: container.mainContext, calendar: calendar)

        let previousDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 3)))
        let previousKey = store.dateKey(for: previousDate)

        store.ensureDayPlan(for: previousKey, now: previousDate)
        let previousPlan = try #require(store.fetchDayPlan(for: previousKey))
        store.addTodo(title: "Task A", to: previousPlan, now: previousDate)

        let todo = try #require(previousPlan.todos.first)
        let destinationKey = store.carryTodoToNextDay(todo, from: previousPlan, now: now, ignoreWeekends: false)
        let destination = try #require(store.fetchDayPlan(for: destinationKey))

        #expect(destination.todos.count == 1)
        #expect(destination.todos.first?.title == "Task A")
        #expect(destination.todos.first?.source == .rollover)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([DayPlan.self, TodoItem.self, LinearLink.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
