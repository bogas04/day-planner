# FocusedDayPlanner

A native macOS SwiftUI app for daily planning:
- day-based todo lists
- day rating (1-10)
- history and calendar day views
- menu bar launcher
- hourly reminder notifications (11am-5pm when pending todos exist)

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
