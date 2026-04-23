# FocusedDayPlanner Working Notes

This file is for future agents and new humans who need to make changes quickly without re-learning the app from scratch.

## What This App Is

- Native macOS SwiftUI app built as a Swift Package.
- Main target: `Sources/FocusedDayPlanner`
- Tests: `Tests/FocusedDayPlannerTests`
- Entry point: [FocusedDayPlannerApp.swift](Sources/FocusedDayPlanner/FocusedDayPlannerApp.swift)

Run and verify with:

```bash
swift build
swift test
swift run
```

## Mental Model

The codebase is organized around a few central owners:

- `PlannerRootView.swift`: the main shell and almost all user-facing screens.
- `PlannerStore.swift`: planner business logic and SwiftData writes.
- `Models.swift`: SwiftData models for days, todos, and links.
- `PersistenceController.swift`: store location, bootstrapping, and future migrations.
- `DailyReminderScheduler.swift`: local notification scheduling and wellness reminder integration.
- `BackgroundAudioController.swift`: sound mixer state, saved mixes, imports, downloads, and playback.
- `AppSettings.swift`: `UserDefaults` keys, defaults, and normalization helpers.
- `PlannerRules.swift`: small policy helpers that should stay deterministic and easy to test.

When adding behavior, prefer putting domain logic in `PlannerStore`, `PlannerRules`, `DailyReminderScheduler`, `BackgroundAudioController`, or `AppSettings` instead of expanding `PlannerRootView` more than necessary.

## Important Data Invariants

### Planner data

- `DayPlan.dateKey` is unique and uses `yyyy-MM-dd`.
- `TodoItem.sortOrder` is the ordering source of truth within a day.
- `LinearLink.sortOrder` is the ordering source of truth for links within a day.
- `TodoItem.source` distinguishes manual tasks from rollover tasks.

If you move or delete todos/links, keep sort order normalized. The helper methods in [PlannerStore.swift](Sources/FocusedDayPlanner/PlannerStore.swift) already do this; reuse them.

### Save behavior

- Immediate writes use `save(refreshNotifications:)`.
- Typing-style edits use `scheduleSave(refreshNotifications:)` to debounce disk writes.
- Notification refreshes are tied to planner saves, so changing save paths can affect reminder behavior.

If a change affects todo counts, day creation, carry-forward behavior, or notification settings, double-check whether `refreshNotifications` should be `true`.

## Where To Make Changes

### Add or change planner behavior

Start in [PlannerStore.swift](Sources/FocusedDayPlanner/PlannerStore.swift).

- Add todos: `addTodo`
- Carry forward: `carryPendingTodosToNextDay`, `carryTodoToNextDay`
- Import/export: `exportSnapshotJSON`, `importSnapshotJSON`
- Link handling: `addLinearLink`, `deleteLinearLink`
- Notification refresh trigger: `refreshTodayNotifications`

Notes:

- New manual todos are inserted at the top of the day.
- Manual todo priority cycles through `high -> medium -> low` via `PlannerRules.nextPriority`.
- Carry-forward intentionally marks moved todos as `.rollover`.
- Import replaces all current planner content.

### Add or change UI

Start in [PlannerRootView.swift](Sources/FocusedDayPlanner/PlannerRootView.swift).

- This file is the app shell plus most screens.
- Before adding more inline logic here, look for an existing controller/store/helper to extend instead.
- If a feature needs new persisted settings, add them to `AppSettings` first and keep the UI bound to those helpers.

### Add or change persistence/schema

Start in [PersistenceController.swift](Sources/FocusedDayPlanner/PersistenceController.swift).

- Bump `currentSchemaVersion` when a real migration is needed.
- Add migration steps in `applyMigration(toVersion:storeDirectory:)`.
- Keep legacy import/bootstrap logic working unless intentionally removing backward compatibility.

Storage locations already used by the app:

- SwiftData store: `~/Library/Application Support/FocusedDayPlanner/FocusedDayPlanner.store`
- Store metadata: `~/Library/Application Support/FocusedDayPlanner/StoreMetadata.json`
- Sidebar images: `~/Library/Application Support/FocusedDayPlanner/Sidebar Images/`
- Audio library: `~/Library/Application Support/FocusedDayPlanner/AudioLibrary/`

### Add or change reminders

Start in [DailyReminderScheduler.swift](Sources/FocusedDayPlanner/DailyReminderScheduler.swift).

- Reminder scheduling is a side effect of planner state plus `AppSettings`.
- The scheduler does nothing in unsupported environments, so CLI tests will not exercise full notification delivery.
- Wellness overlay behavior is coordinated here through `WellnessBreakOverlayController.shared.configure(...)`.

When changing reminder policy:

- keep `ReminderScheduleState` comparisons accurate so refresh deduping still works
- update `AppSettings` normalization if you add new inputs
- verify both empty-day and pending-todo flows

### Add or change sound mixer behavior

Start in [BackgroundAudioController.swift](Sources/FocusedDayPlanner/BackgroundAudioController.swift).

- `soundEffectsCatalog` is the curated built-in effect list.
- Mixed effect levels live in `soundEffectLevels`.
- Saved mixes persist to `SavedMixes.json` under the audio library root.
- User-imported audio goes in the `User/` subdirectory.

Important behavior:

- Clicking a sound tile toggles/rebalances active effects.
- Dragging sets an explicit level.
- Master volume is stored in `AppSettings`.
- File imports use deterministic de-duplication naming.

## Settings Pattern

All persisted preferences should go through [AppSettings.swift](Sources/FocusedDayPlanner/AppSettings.swift).

Preferred pattern:

1. Add the key constant.
2. Add a default.
3. Add normalization/sanitization helpers if user input can drift out of range.
4. Expose a computed static property.
5. Bind UI with `@AppStorage` or read/write via the helper.

This keeps ranges and defaults centralized instead of scattering clamping logic across views.

## Tests To Extend

Current coverage is small but useful:

- [PlannerRulesTests.swift](Tests/FocusedDayPlannerTests/PlannerRulesTests.swift): deterministic policy helpers.
- [PlannerStoreCarryForwardTests.swift](Tests/FocusedDayPlannerTests/PlannerStoreCarryForwardTests.swift): top insertion and carry-forward edge cases.
- [BackgroundAudioControllerTests.swift](Tests/FocusedDayPlannerTests/BackgroundAudioControllerTests.swift): audio normalization and import behavior.

Add tests when changing:

- priority rules
- carry-forward or date rollover
- import/export formats
- audio file scanning or duplicate naming
- any normalization logic in `AppSettings`

If you fix a bug in `PlannerStore`, add or update a store test first when practical.

## Known Sharp Edges

- `PlannerRootView.swift` is large. Prefer extracting helpers/controllers before adding more cross-cutting logic.
- Save timing matters. Debounced saves are intentional for text editing; immediate saves are intentional for structural changes.
- Notification behavior is easy to accidentally desync if planner mutations skip `refreshTodayNotifications`.
- Schema/version changes need both SwiftData model thinking and file-based metadata migration thinking.
- Some functionality behaves differently when run via `swift run` versus a packaged `.app`, especially notification support.

## Suggested Workflow For Future Changes

1. Identify whether the change is UI-only, planner-state, settings, reminders, audio, or persistence.
2. Make the logic change in the owner file first.
3. Keep `PlannerRootView` focused on presentation and wiring.
4. Add or update tests in the closest existing test file.
5. Run `swift test` at minimum before finishing.

## If You Are Starting Fresh

Read these files in order:

1. [README.md](README.md)
2. [FocusedDayPlannerApp.swift](Sources/FocusedDayPlanner/FocusedDayPlannerApp.swift)
3. [PlannerRootView.swift](Sources/FocusedDayPlanner/PlannerRootView.swift)
4. [PlannerStore.swift](Sources/FocusedDayPlanner/PlannerStore.swift)
5. [AppSettings.swift](Sources/FocusedDayPlanner/AppSettings.swift)
6. [PersistenceController.swift](Sources/FocusedDayPlanner/PersistenceController.swift)

That path gets you from app startup to view composition to real business logic quickly.
