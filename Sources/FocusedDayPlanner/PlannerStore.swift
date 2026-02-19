import Foundation
import SwiftData

@MainActor
final class PlannerStore: ObservableObject {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func todayKey(now: Date = .now) -> String {
        dateKey(for: now)
    }

    func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func date(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    func ensureDayPlan(for dateKey: String, now: Date = .now) {
        if fetchDayPlan(for: dateKey) != nil {
            return
        }

        let newPlan = DayPlan(dateKey: dateKey, createdAt: now, updatedAt: now)
        context.insert(newPlan)

        if dateKey == todayKey(now: now), let previousPlan = mostRecentPlan(before: dateKey) {
            rolloverUnfinishedTodos(from: previousPlan, to: newPlan, now: now)
        }

        save()
    }

    func createNextDay(after dateKey: String?) -> String {
        let baseDate = dateKey.flatMap { date(from: $0) } ?? .now
        let nextDate = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? .now
        let key = self.dateKey(for: nextDate)
        ensureDayPlan(for: key)
        return key
    }

    @discardableResult
    func carryPendingTodosToNextDay(from dayPlan: DayPlan, now: Date = .now) -> String {
        let baseDate = date(from: dayPlan.dateKey) ?? now
        let nextDate = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? now
        let nextKey = dateKey(for: nextDate)
        ensureDayPlan(for: nextKey, now: now)

        guard let destination = fetchDayPlan(for: nextKey) else { return nextKey }

        var nextSort = (destination.todos.map(\.sortOrder).max() ?? -1) + 1
        let pending = dayPlan.todos
            .filter { !$0.isDone }
            .sorted { $0.sortOrder < $1.sortOrder }

        for todo in pending {
            todo.dayPlan = destination
            todo.source = .rollover
            todo.sortOrder = nextSort
            todo.updatedAt = now
            nextSort += 1
        }

        normalizeTodoSortOrder(for: dayPlan, now: now)
        destination.updatedAt = now
        dayPlan.updatedAt = now
        save()
        return nextKey
    }

    func fetchDayPlan(for dateKey: String) -> DayPlan? {
        let descriptor = FetchDescriptor<DayPlan>(
            predicate: #Predicate<DayPlan> { plan in
                plan.dateKey == dateKey
            }
        )
        return try? context.fetch(descriptor).first
    }

    func mostRecentPlan(before dateKey: String) -> DayPlan? {
        var descriptor = FetchDescriptor<DayPlan>(
            predicate: #Predicate<DayPlan> { plan in
                plan.dateKey < dateKey
            }
        )
        descriptor.sortBy = [SortDescriptor(\DayPlan.dateKey, order: .reverse)]
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func rolloverUnfinishedTodos(from previous: DayPlan, to current: DayPlan, now: Date) {
        let unfinished = previous.todos
            .filter { !$0.isDone }
            .sorted { $0.sortOrder < $1.sortOrder }

        for (index, sourceTodo) in unfinished.enumerated() {
            let todo = TodoItem(
                title: sourceTodo.title,
                priority: .high,
                isDone: false,
                sortOrder: index,
                source: .rollover,
                createdAt: now,
                updatedAt: now,
                dayPlan: current
            )
            context.insert(todo)
            current.todos.append(todo)
        }

        current.updatedAt = now
    }

    func addTodo(title: String, to dayPlan: DayPlan, now: Date = .now) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let manualCount = dayPlan.todos.filter { $0.source == .manual }.count
        let priority = PlannerRules.nextPriority(manualTodoCount: manualCount)
        let sortOrder = (dayPlan.todos.map(\.sortOrder).max() ?? -1) + 1

        let todo = TodoItem(
            title: trimmed,
            priority: priority,
            isDone: false,
            sortOrder: sortOrder,
            source: .manual,
            createdAt: now,
            updatedAt: now,
            dayPlan: dayPlan
        )
        context.insert(todo)
        dayPlan.todos.append(todo)
        dayPlan.updatedAt = now
        save()
    }

    func refreshTodayNotifications(now: Date = .now) {
        let today = todayKey(now: now)
        let todayPlan = fetchDayPlan(for: today)
        let total = todayPlan?.todos.count ?? 0
        let pending = todayPlan?.todos.filter { !$0.isDone }.count ?? 0
        Task { @MainActor in
            DailyReminderScheduler.shared.refresh(totalTodos: total, pendingTodos: pending, now: now)
        }
    }

    func deleteTodo(_ todo: TodoItem, from dayPlan: DayPlan, now: Date = .now) {
        dayPlan.todos.removeAll { $0.persistentModelID == todo.persistentModelID }
        context.delete(todo)
        normalizeTodoSortOrder(for: dayPlan, now: now)
        dayPlan.updatedAt = now
        save()
    }

    func moveTodos(indices: IndexSet, newOffset: Int, for dayPlan: DayPlan, now: Date = .now) {
        var sorted = sortedTodos(for: dayPlan)
        sorted.move(fromOffsets: indices, toOffset: newOffset)
        for (index, todo) in sorted.enumerated() {
            todo.sortOrder = index
            todo.updatedAt = now
        }
        dayPlan.updatedAt = now
        save()
    }

    func moveTodo(_ todo: TodoItem, in dayPlan: DayPlan, delta: Int, now: Date = .now) {
        var sorted = sortedTodos(for: dayPlan)
        guard let currentIndex = sorted.firstIndex(where: { $0.persistentModelID == todo.persistentModelID }) else {
            return
        }

        let targetIndex = max(0, min(sorted.count - 1, currentIndex + delta))
        guard targetIndex != currentIndex else { return }

        let moving = sorted.remove(at: currentIndex)
        sorted.insert(moving, at: targetIndex)
        for (index, item) in sorted.enumerated() {
            item.sortOrder = index
            item.updatedAt = now
        }
        dayPlan.updatedAt = now
        save()
    }

    func moveTodo(_ todo: TodoItem, in dayPlan: DayPlan, to targetIndex: Int, now: Date = .now) {
        var sorted = sortedTodos(for: dayPlan)
        guard let currentIndex = sorted.firstIndex(where: { $0.persistentModelID == todo.persistentModelID }) else {
            return
        }

        let clampedTarget = max(0, min(sorted.count - 1, targetIndex))
        guard clampedTarget != currentIndex else { return }

        let moving = sorted.remove(at: currentIndex)
        sorted.insert(moving, at: clampedTarget)
        for (index, item) in sorted.enumerated() {
            item.sortOrder = index
            item.updatedAt = now
        }
        dayPlan.updatedAt = now
        save()
    }

    func moveTodo(_ todo: TodoItem, from sourcePlan: DayPlan, to destinationPlan: DayPlan, now: Date = .now) {
        guard sourcePlan.persistentModelID != destinationPlan.persistentModelID else { return }

        let nextSort = (destinationPlan.todos.map(\.sortOrder).max() ?? -1) + 1
        todo.dayPlan = destinationPlan
        todo.sortOrder = nextSort
        todo.updatedAt = now

        normalizeTodoSortOrder(for: sourcePlan, now: now)
        destinationPlan.updatedAt = now
        sourcePlan.updatedAt = now
        save()
    }

    func sortedTodos(for dayPlan: DayPlan) -> [TodoItem] {
        dayPlan.todos.sorted { $0.sortOrder < $1.sortOrder }
    }

    func updateDayRating(_ rating: Int?, for dayPlan: DayPlan, now: Date = .now) {
        if let rating, !(1...10).contains(rating) {
            return
        }
        dayPlan.dayRating = rating
        dayPlan.updatedAt = now
        save()
    }

    @discardableResult
    func updateDayDate(_ dayPlan: DayPlan, to newDateKey: String, now: Date = .now) -> Bool {
        let trimmed = newDateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != dayPlan.dateKey else { return true }
        if fetchDayPlan(for: trimmed) != nil {
            return false
        }
        dayPlan.dateKey = trimmed
        dayPlan.updatedAt = now
        save()
        return true
    }

    @discardableResult
    func deleteDay(_ dayPlan: DayPlan, now: Date = .now) -> String? {
        let sourceKey = dayPlan.dateKey
        var descriptor = FetchDescriptor<DayPlan>()
        descriptor.sortBy = [SortDescriptor(\DayPlan.dateKey, order: .reverse)]
        let others = (try? context.fetch(descriptor))?.filter { $0.dateKey != sourceKey } ?? []
        let destination = others.first { $0.dateKey == todayKey(now: now) } ?? others.first

        let todosToMove = dayPlan.todos.sorted { $0.sortOrder < $1.sortOrder }
        if let destination {
            var nextSort = (destination.todos.map(\.sortOrder).max() ?? -1) + 1
            for todo in todosToMove {
                todo.dayPlan = destination
                todo.sortOrder = nextSort
                todo.updatedAt = now
                nextSort += 1
            }
            destination.updatedAt = now
        } else {
            // Allow deleting the final day while preserving todo records.
            for todo in todosToMove {
                todo.dayPlan = nil
                todo.updatedAt = now
            }
        }

        context.delete(dayPlan)
        save()
        return destination?.dateKey
    }

    func touchTodo(_ todo: TodoItem, now: Date = .now) {
        todo.updatedAt = now
        todo.dayPlan?.updatedAt = now
        save()
    }

    @discardableResult
    func carryTodoToNextDay(_ todo: TodoItem, from dayPlan: DayPlan, now: Date = .now) -> String {
        let baseDate = date(from: dayPlan.dateKey) ?? now
        let nextDate = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? now
        let nextKey = dateKey(for: nextDate)
        ensureDayPlan(for: nextKey, now: now)

        guard let destination = fetchDayPlan(for: nextKey) else { return nextKey }
        let nextSort = (destination.todos.map(\.sortOrder).max() ?? -1) + 1

        todo.dayPlan = destination
        todo.source = .rollover
        todo.isDone = false
        todo.sortOrder = nextSort
        todo.updatedAt = now

        normalizeTodoSortOrder(for: dayPlan, now: now)
        destination.updatedAt = now
        dayPlan.updatedAt = now
        save()
        return nextKey
    }

    func deleteAllData(now: Date = .now) {
        let todoDescriptor = FetchDescriptor<TodoItem>()
        let linkDescriptor = FetchDescriptor<LinearLink>()
        let dayDescriptor = FetchDescriptor<DayPlan>()

        (try? context.fetch(todoDescriptor))?.forEach { context.delete($0) }
        (try? context.fetch(linkDescriptor))?.forEach { context.delete($0) }
        (try? context.fetch(dayDescriptor))?.forEach { context.delete($0) }

        save()
    }

    func addLinearLink(url: String, to dayPlan: DayPlan, now: Date = .now) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }

        let sortOrder = (dayPlan.linearLinks.map(\.sortOrder).max() ?? -1) + 1
        let link = LinearLink(
            url: trimmed,
            displayText: parsed.host ?? trimmed,
            sortOrder: sortOrder,
            createdAt: now,
            updatedAt: now,
            dayPlan: dayPlan
        )
        context.insert(link)
        dayPlan.linearLinks.append(link)
        dayPlan.updatedAt = now
        save()
        return true
    }

    func deleteLinearLink(_ link: LinearLink, from dayPlan: DayPlan, now: Date = .now) {
        dayPlan.linearLinks.removeAll { $0.persistentModelID == link.persistentModelID }
        context.delete(link)
        normalizeLinkSortOrder(for: dayPlan, now: now)
        dayPlan.updatedAt = now
        save()
    }

    func sortedLinearLinks(for dayPlan: DayPlan) -> [LinearLink] {
        dayPlan.linearLinks.sorted { $0.sortOrder < $1.sortOrder }
    }

    func touchLinearLink(_ link: LinearLink, in dayPlan: DayPlan, now: Date = .now) {
        link.updatedAt = now
        dayPlan.updatedAt = now
        save()
    }

    private func normalizeTodoSortOrder(for dayPlan: DayPlan, now: Date) {
        for (index, todo) in sortedTodos(for: dayPlan).enumerated() {
            todo.sortOrder = index
            todo.updatedAt = now
        }
    }

    private func normalizeLinkSortOrder(for dayPlan: DayPlan, now: Date) {
        for (index, link) in sortedLinearLinks(for: dayPlan).enumerated() {
            link.sortOrder = index
            link.updatedAt = now
        }
    }

    func save() {
        do {
            try context.save()
            refreshTodayNotifications()
        } catch {
            assertionFailure("Failed to save planner data: \(error)")
        }
    }
}
