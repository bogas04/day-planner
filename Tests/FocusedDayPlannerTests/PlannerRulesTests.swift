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
}
