# FocusedDayPlanner

A native macOS SwiftUI app for daily planning:
- day-based todo lists
- day rating (1-10)
- reflection notes
- history, all-todos, calendar, and stats views
- menu bar launcher
- hourly reminder notifications (11am-5pm when pending todos exist)
- JSON import/export
- subtle theme tint customization

![FocusedDayPlanner screenshot](.github/screenshot.png)

## App Terminology (UI -> Internal)
Use these exact names when prompting changes.

| User-facing label/location | Internal term in code | Notes |
|---|---|---|
| Sidebar section **Planner** | Sidebar `Section("Planner")` in `PlannerRootView` | Navigation entry group |
| Sidebar section **History** | Sidebar `Section("History")` in `PlannerRootView` | Recent day list (`recentPlans`) |
| **Today** | `DetailMode.day` + `todayKey` | Opens today’s day plan |
| **All Todos** | `DetailMode.todos`, `allTodosView` | Cross-day grouped todo view |
| **Calendar** | `DetailMode.calendar`, `calendarGridView` | Month grid with day summaries |
| **Stats** | `DetailMode.stats`, `statsView` | Overall rating + weekly done/day comparison |
| **Settings** | `DetailMode.settings`, `settingsView` | Notifications, theme tint, data actions |
| Day detail screen | `dayView(plan:)` | Header + todo section for one day |
| Day header card | `header(for:)` | Date, rating, reflection, carry-forward |
| Day todos card | `todoSection(for:)` | Input + reorderable per-day todo list |
| All-todos day card | `allTodosDayCard(for:)` | A day block inside all-todos view |

## Data Import/Export
- Export button: **Settings -> Export Data (JSON)**
- Import button: **Settings -> Import Data (JSON)**
- Import behavior: replaces all existing day/todo/link data with imported snapshot
- Snapshot schema fields include:
  - `schemaVersion`, `exportedAt`
  - `days[]`: `dateKey`, `dayRating`, `reflection`, timestamps
  - `todos[]`: title, priority/source raw values, done state, sort order, timestamps
  - `linearLinks[]`: url, displayText, sort order, timestamps
- Dates are encoded as ISO-8601.

## Requirements
- macOS 14+
- Xcode / Swift toolchain with `swift` CLI available

## Run (Debug)
```bash
cd ~/Developer/FocusedDayPlanner
swift run
```

## Build
Debug build:
```bash
cd ~/Developer/FocusedDayPlanner
swift build
```

Release build:
```bash
cd ~/Developer/FocusedDayPlanner
swift build -c release
```

## Test
```bash
cd ~/Developer/FocusedDayPlanner
swift test
```

## Package as macOS App
Use the packaging script:
```bash
cd ~/Developer/FocusedDayPlanner
./scripts/package-app.sh
```

This creates:
- `~/Developer/FocusedDayPlanner/dist/FocusedDayPlanner.app`

Non-interactive bundle build (for CI):
```bash
cd ~/Developer/FocusedDayPlanner
./scripts/package-app.sh --no-install
```

Build a DMG after packaging:
```bash
cd ~/Developer/FocusedDayPlanner
./scripts/create-dmg.sh
```

This creates:
- `~/Developer/FocusedDayPlanner/dist/FocusedDayPlanner-<version>-<build>.dmg`

Install to Applications:
```bash
cp -R ~/Developer/FocusedDayPlanner/dist/FocusedDayPlanner.app /Applications/
```

## Add to Login Items
1. Open **System Settings**
2. Go to **General -> Login Items**
3. Under **Open at Login**, click `+`
4. Select `/Applications/FocusedDayPlanner.app`

## Notifications Behavior
The app requests notification permission.

- If today has pending todos: notifies hourly at 11:00, 12:00, ..., 17:00
  - Message: `You have x todos left, let's do it!`
- If today has zero todos total: notifies at 11:00 only
  - Message: `What would you like to work on today?`
- If todos exist but all are done: no hourly reminders

## Project Structure
- `Sources/FocusedDayPlanner/FocusedDayPlannerApp.swift` - app entry, menu bar, app setup
- `Sources/FocusedDayPlanner/PlannerRootView.swift` - main UI and navigation
- `Sources/FocusedDayPlanner/PlannerStore.swift` - persistence operations and business logic
- `Sources/FocusedDayPlanner/DailyReminderScheduler.swift` - notification scheduling
- `Sources/FocusedDayPlanner/TodoTextFormatter.swift` - todo URL/Linear formatting
- `Sources/FocusedDayPlanner/AppIconProvider.swift` - generated app/menu icons
- `scripts/package-app.sh` - app bundling script
- `scripts/create-dmg.sh` - DMG packaging script
- `.github/workflows/release-dmg.yml` - CI/CD build + release artifact upload

## Notes
- Data is stored locally via SwiftData.
- Persistent store path:
  - `~/Library/Application Support/FocusedDayPlanner/FocusedDayPlanner.store`
- Store metadata/version file:
  - `~/Library/Application Support/FocusedDayPlanner/StoreMetadata.json`
- Schema/version migrations:
  - Startup uses `PersistenceController` to read schema version metadata and run migration hooks before opening the store.
  - Add future migrations in `applyMigration(toVersion:storeDirectory:)` in `Sources/FocusedDayPlanner/PersistenceController.swift`.
- If you change app identifiers in packaging, update `CFBundleIdentifier` in `scripts/package-app.sh`.
- App versioning:
  - Marketing version comes from `VERSION` (or `MARKETING_VERSION` env var in CI).
  - Build number defaults to git commit count (`git rev-list --count HEAD`) and is used as `CFBundleVersion`.
  - On tagged CI releases (`v*`), tag value is used as marketing version and the `.dmg` is attached to the GitHub Release.
