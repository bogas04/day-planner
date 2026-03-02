import Foundation
import Testing
@testable import FocusedDayPlanner

struct PlannerRulesTests {
    @Test
    func nextPriorityCyclesHighMediumLow() {
        #expect(PlannerRules.nextPriority(manualTodoCount: 0) == .high)
        #expect(PlannerRules.nextPriority(manualTodoCount: 1) == .medium)
        #expect(PlannerRules.nextPriority(manualTodoCount: 2) == .low)
        #expect(PlannerRules.nextPriority(manualTodoCount: 3) == .high)
    }

    @Test
    func assignedPrioritiesReturnsSequence() {
        let assigned = PlannerRules.assignedPriorities(forNewTodoCount: 5)
        #expect(assigned == [.high, .medium, .low, .high, .medium])
    }

    @Test
    func nextCarryForwardDateSkipsWeekendWhenEnabled() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let friday = try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 6
        )))

        let result = PlannerRules.nextCarryForwardDate(
            after: friday,
            calendar: calendar,
            ignoreWeekends: true
        )

        let components = calendar.dateComponents([.year, .month, .day], from: result)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 9)
    }

    @Test
    func nextCarryForwardDateKeepsWeekendWhenDisabled() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let friday = try #require(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 6
        )))

        let result = PlannerRules.nextCarryForwardDate(
            after: friday,
            calendar: calendar,
            ignoreWeekends: false
        )

        let components = calendar.dateComponents([.year, .month, .day], from: result)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 7)
    }
}
