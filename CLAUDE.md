# Claude Notes

Use [AGENTS.md](/Users/divjot.singh/Developer/FocusedDayPlanner/AGENTS.md) as the primary repository guide.

This repo keeps the detailed architecture, invariants, testing expectations, and feature ownership notes in `AGENTS.md` so there is one source of truth for both humans and coding agents.

If you are making code changes here:

- read `AGENTS.md` first
- prefer extending `PlannerStore`, `AppSettings`, `DailyReminderScheduler`, or `BackgroundAudioController` before adding more logic to `PlannerRootView`
- run `swift test` before finishing when practical
