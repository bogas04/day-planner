# FocusedDayPlanner

FocusedDayPlanner is a native macOS planner built with SwiftUI and SwiftData for people who want a calm daily workspace instead of a cluttered task app.

![FocusedDayPlanner screenshot](.github/screenshot.png)

## What’s New In 1.1
- dedicated **Sound Mixer** page with mixable ambient sound-effect tiles
- pause/resume that preserves your exact custom sound mix
- sidebar page highlighting for planner destinations
- menu bar launcher for quick reopen access
- wellness-break overlays and reminder controls
- UI zoom controls for better readability on different displays
- refreshed settings layout and richer app polish

## Core Experience
- **Today** for focused day planning
- **All Todos** for a cross-day view of every task
- **Calendar** for navigating daily summaries month by month
- **Stats** for completion and rating trends
- **Journal** for reflection history
- **Sound Mixer** for blending rain, wind, waves, leaves, thunderstorm, and restaurant ambience
- **Settings** for reminders, appearance, storage, and audio configuration

## Features
- day-based todo planning with reorderable tasks
- carry-forward workflow for unfinished work
- day rating and written reflection
- sidebar history of recent days
- local-first data storage with JSON import/export
- hourly todo reminders when work is still pending
- optional wellness reminders every 10 to 180 minutes
- dedicated sound mixer with click-to-balance and drag-to-set levels
- sound-effect cache folder access from Settings
- menu bar entry to reopen the planner quickly
- adjustable UI scale with keyboard shortcuts
- theme tint customization and decorative sidebar artwork

## Sound Mixer
The Sound Mixer is a dedicated sidebar page for building a background ambience mix while you work.

- click a sound tile to activate it and rebalance all active tiles evenly
- drag across a tile to set that tile anywhere from `0%` to `100%`
- pause and resume without losing your current mix
- use the toolbar mini-player for quick playback and master volume control
- built-in effects currently include:
  - walking on leaves
  - whistling wind
  - thunderstorm
  - leaves rustling
  - calming rain
  - soothing ocean waves
  - busy restaurant ambience

## Notifications
The app requests notification permission for planner reminders.

- pending todos trigger hourly reminders from `11:00` through `17:00`
- empty days can prompt you to add work for the day
- completed days do not trigger hourly todo reminders
- wellness reminders can repeat on your chosen interval
- test and permission-check actions are available in Settings

## Requirements
- macOS 14+
- Xcode or Swift toolchain with the `swift` CLI available

## Run
```bash
cd ~/Developer/FocusedDayPlanner
swift run
```

## Build
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

## Package As A macOS App
```bash
cd ~/Developer/FocusedDayPlanner
./scripts/package-app.sh
```

This creates:
- `~/Developer/FocusedDayPlanner/dist/FocusedDayPlanner.app`

Non-interactive build:
```bash
cd ~/Developer/FocusedDayPlanner
./scripts/package-app.sh --no-install
```

Create a DMG:
```bash
cd ~/Developer/FocusedDayPlanner
./scripts/create-dmg.sh
```

This creates:
- `~/Developer/FocusedDayPlanner/dist/FocusedDayPlanner-<version>-<build>.dmg`

## Data And Storage
- planner data is stored locally via SwiftData
- default store location:
  - `~/Library/Application Support/FocusedDayPlanner/FocusedDayPlanner.store`
- store metadata file:
  - `~/Library/Application Support/FocusedDayPlanner/StoreMetadata.json`
- sound-effect cache location:
  - `~/Library/Application Support/FocusedDayPlanner/AudioLibrary/Curated/`

## Project Structure
- `Sources/FocusedDayPlanner/FocusedDayPlannerApp.swift` - app entry, window setup, menu bar integration
- `Sources/FocusedDayPlanner/PlannerRootView.swift` - main navigation and primary UI
- `Sources/FocusedDayPlanner/PlannerStore.swift` - persistence operations and planner business logic
- `Sources/FocusedDayPlanner/BackgroundAudioController.swift` - sound mixer state, caching, and playback
- `Sources/FocusedDayPlanner/DailyReminderScheduler.swift` - reminder scheduling
- `Sources/FocusedDayPlanner/PersistenceController.swift` - store location and migrations
- `scripts/package-app.sh` - app bundling
- `scripts/create-dmg.sh` - DMG packaging

## Versioning And Releases
- marketing version comes from `VERSION`
- build number defaults to `git rev-list --count HEAD`
- tagged releases using `v*` can be used by CI packaging workflows

## Repository Notes
- this app is local-first by design
- import replaces existing planner content with the imported snapshot
- future schema migrations should be added in `PersistenceController.applyMigration(toVersion:storeDirectory:)`
