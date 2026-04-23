import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum DetailMode {
    case day
    case todos
    case calendar
    case stats
    case journal
    case soundMixer
    case settings
}

private enum WellnessBreakTimeEdge {
    case start
    case end
}

private enum StatsTimeframe: String, CaseIterable, Identifiable {
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }

    var singularLabel: String {
        switch self {
        case .weekly:
            return "week"
        case .monthly:
            return "month"
        }
    }

    var pluralLabel: String {
        switch self {
        case .weekly:
            return "weeks"
        case .monthly:
            return "months"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .weekly:
            return .weekOfYear
        case .monthly:
            return .month
        }
    }
}

struct PlannerRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var uiScaleController: UIScaleController
    @EnvironmentObject private var backgroundAudioController: BackgroundAudioController
    @StateObject private var wellnessBreakOverlayController = WellnessBreakOverlayController.shared
    @StateObject private var reminderScheduler = DailyReminderScheduler.shared
    @Query(sort: \DayPlan.dateKey, order: .reverse) private var dayPlans: [DayPlan]
    @AppStorage(AppSettings.notificationsEnabledKey) private var notificationsEnabled = true
    @AppStorage(AppSettings.todoReminderIntervalMinutesKey)
    private var todoReminderIntervalMinutes = AppSettings.defaultTodoReminderIntervalMinutes
    @AppStorage(AppSettings.todoReminderMessageKey)
    private var todoReminderMessage = AppSettings.defaultTodoReminderMessage
    @AppStorage(AppSettings.emptyDayReminderMessageKey)
    private var emptyDayReminderMessage = AppSettings.defaultEmptyDayReminderMessage
    @AppStorage(AppSettings.wellnessBreakRemindersEnabledKey) private var wellnessBreakRemindersEnabled = false
    @AppStorage(AppSettings.wellnessBreakIntervalMinutesKey)
    private var wellnessBreakIntervalMinutes = AppSettings.defaultWellnessBreakIntervalMinutes
    @AppStorage(AppSettings.wellnessBreakMessageKey)
    private var wellnessBreakMessage = AppSettings.defaultWellnessBreakMessage
    @AppStorage(AppSettings.wellnessBreakStartMinutesKey)
    private var wellnessBreakStartMinutes = AppSettings.defaultWellnessBreakStartMinutes
    @AppStorage(AppSettings.wellnessBreakEndMinutesKey)
    private var wellnessBreakEndMinutes = AppSettings.defaultWellnessBreakEndMinutes
    @AppStorage(AppSettings.skipCarryForwardConfirmKey) private var skipCarryForwardConfirm = false
    @AppStorage(AppSettings.ignoreCarryForwardWeekendsKey) private var ignoreCarryForwardWeekends = true
    @AppStorage(AppSettings.themeTintRedKey) private var themeTintRed = 0.86
    @AppStorage(AppSettings.themeTintGreenKey) private var themeTintGreen = 0.76
    @AppStorage(AppSettings.themeTintBlueKey) private var themeTintBlue = 0.60
    @AppStorage(AppSettings.themeTintOpacityKey) private var themeTintOpacity = 0.10
    @AppStorage(AppSettings.backgroundAudioEnabledKey) private var backgroundAudioEnabled = true
    @AppStorage(AppSettings.backgroundAudioAutoResumeKey) private var backgroundAudioAutoResume = false
    @AppStorage(AppSettings.developerModeEnabledKey) private var developerModeEnabled = false

    @State private var selectedDateKey: String?
    @State private var detailMode: DetailMode = .day
    @State private var todoInput = ""
    @State private var editingLinkedTodos: Set<PersistentIdentifier> = []
    @State private var plannerStore: PlannerStore?

    @State private var showingDateEditor = false
    @State private var dateEditorValue: Date = .now
    @State private var dateChangeError: String?
    @State private var showingDeleteDayConfirmation = false
    @State private var calendarDeleteDayKey: String?
    @State private var showingDeleteAllDataConfirmation = false
    @State private var showingDeleteTodoConfirmation = false
    @State private var pendingDeleteTodoID: PersistentIdentifier?
    @State private var pendingDeletePlanDateKey: String?
    @State private var showingCarryForwardConfirmation = false
    @State private var carryForwardDontAskAgain = false
    @State private var pendingCarryTodoID: PersistentIdentifier?
    @State private var pendingCarryPlanDateKey: String?
    @State private var dataTransferMessage: String?
    @State private var notificationDebugMessage = "Permission state will appear here after a check."
    @State private var isCheckingNotificationStatus = false
    @State private var draggedTodoToken: String?
    @State private var decorativeImageCycleOffset = 0
    @State private var decorativeImageBloomColor = Color.accentColor.opacity(0.35)
    @State private var decorativeImageCandidates: [URL] = []
    @State private var currentDecorativeImage: NSImage?
    @State private var currentDecorativeImagePath: String?
    @State private var decorativeImageColorCache: [String: Color] = [:]
    @State private var imagePanelFraction: CGFloat = 0.33
    @State private var imagePanelDragStartFraction: CGFloat?
    @State private var reflectionPlaceholderIndex = 0
    @State private var hoveredInlineEditTodoID: PersistentIdentifier?
    @State private var imageDividerHoverCursorActive = false
    @FocusState private var focusedLinkedTodoID: PersistentIdentifier?

    @State private var calendarMonth: Date = Date()
    @State private var journalPage = 0
    @State private var statsTimeframe: StatsTimeframe = .weekly
    @State private var weeklyRatingsOffset = 0
    @State private var monthlyRatingsOffset = 0
    @State private var journalDateRange: DateInterval?
    @State private var pendingDeleteMixSlotNumber: Int?

    private let historyLimit = 10
    private let journalPageSize = 10
    private let calendar = Calendar.current
    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    private static let shortMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL yyyy"
        return formatter
    }()
    private let reflectionPrompts = [
        "What felt meaningful today, even in a small way?",
        "What are you proud of from today?",
        "What gave you energy today, and what drained it?",
        "Which moment would you like to remember from today?",
        "What did you learn about yourself today?",
        "What went better than you expected?",
        "If you could replay one part of today, what would you change?",
        "What helped you stay focused today?",
        "What is one gentle improvement for tomorrow?",
        "What are you grateful for from today?"
    ]

    private var store: PlannerStore {
        if let plannerStore {
            return plannerStore
        }

        let store = PlannerStore(context: modelContext)
        DispatchQueue.main.async {
            if self.plannerStore == nil {
                self.plannerStore = store
            }
        }
        return store
    }

    private var todayKey: String {
        store.todayKey()
    }

    private var selectedPlan: DayPlan? {
        guard let selectedDateKey else { return nil }
        return dayPlans.first { $0.dateKey == selectedDateKey }
    }

    private var recentPlans: [DayPlan] {
        Array(dayPlans.prefix(historyLimit))
    }

    private var currentTitle: String {
        switch detailMode {
        case .todos:
            return "All Todos"
        case .calendar:
            return "Calendar"
        case .stats:
            return "Stats"
        case .journal:
            return "Journal"
        case .soundMixer:
            return "Sound Mixer"
        case .settings:
            return "Settings"
        case .day:
            guard let selectedDateKey else { return "Today" }
            return selectedDateKey == todayKey ? "Today" : "Day"
        }
    }

    private var planMap: [String: DayPlan] {
        Dictionary(uniqueKeysWithValues: dayPlans.map { ($0.dateKey, $0) })
    }

    private var themeTintColor: Color {
        Color(
            red: min(max(themeTintRed, 0), 1),
            green: min(max(themeTintGreen, 0), 1),
            blue: min(max(themeTintBlue, 0), 1),
            opacity: min(max(themeTintOpacity, 0), 1)
        )
    }

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String
        let buildNumber = info?["CFBundleVersion"] as? String

        switch (shortVersion, buildNumber) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (short?, _):
            return short
        case let (_, build?):
            return build
        default:
            return "Development"
        }
    }

    private func scaledFont(_ baseSize: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: uiScaleController.scaledMetric(baseSize), weight: weight)
    }

    private var decorativeImage: NSImage? {
        currentDecorativeImage
    }

    private var currentDecorativeImageURL: URL? {
        let candidates = decorativeImageCandidates
        guard !candidates.isEmpty else { return nil }

        let selectedKey = selectedDateKey ?? todayKey
        let dayOfMonth = store.date(from: selectedKey).map { calendar.component(.day, from: $0) } ?? 1
        let baseIndex = max(0, dayOfMonth - 1) % candidates.count
        let resolvedIndex = (baseIndex + decorativeImageCycleOffset) % candidates.count
        return candidates[resolvedIndex]
    }

    private var sidebarImagesDirectoryURL: URL? {
        PersistenceController.decorativeImagesDirectoryURL()
    }

    private var sidebarImagesDirectoryLabel: String {
        sidebarImagesDirectoryURL?.lastPathComponent ?? "Sidebar Images"
    }

    private var soundMixerColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 160), spacing: 14), count: 2)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .dynamicTypeSize(uiScaleController.dynamicTypeSize)
        .controlSize(uiScaleController.controlSize)
        .navigationTitle(currentTitle)
        .alert("Unable to change date", isPresented: Binding(
            get: { dateChangeError != nil },
            set: { if !$0 { dateChangeError = nil } }
        )) {
            Button("OK", role: .cancel) { dateChangeError = nil }
        } message: {
            Text(dateChangeError ?? "")
        }
        .alert("Data Transfer", isPresented: Binding(
            get: { dataTransferMessage != nil },
            set: { if !$0 { dataTransferMessage = nil } }
        )) {
            Button("OK", role: .cancel) { dataTransferMessage = nil }
        } message: {
            Text(dataTransferMessage ?? "")
        }
        .confirmationDialog(
            "Delete this saved mix?",
            isPresented: Binding(
                get: { pendingDeleteMixSlotNumber != nil },
                set: { if !$0 { pendingDeleteMixSlotNumber = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Mix", role: .destructive) {
                if let slotNumber = pendingDeleteMixSlotNumber {
                    backgroundAudioController.deleteMix(slotNumber: slotNumber)
                }
                pendingDeleteMixSlotNumber = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteMixSlotNumber = nil
            }
        } message: {
            Text("This saved mix will be removed permanently.")
        }
        .confirmationDialog(
            "Delete this day?",
            isPresented: Binding(
                get: { calendarDeleteDayKey != nil },
                set: { if !$0 { calendarDeleteDayKey = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Day", role: .destructive) {
                if let key = calendarDeleteDayKey, let plan = planMap[key] {
                    let targetKey = store.deleteDay(plan)
                    selectedDateKey = targetKey
                    detailMode = .calendar
                }
                calendarDeleteDayKey = nil
            }
            Button("Cancel", role: .cancel) {
                calendarDeleteDayKey = nil
            }
        } message: {
            Text("The day and rating will be removed. Todos from this day are kept and moved to another day.")
        }
        .confirmationDialog(
            "Delete this day?",
            isPresented: $showingDeleteDayConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Day", role: .destructive) {
                if let plan = selectedPlan {
                    let targetKey = store.deleteDay(plan)
                    selectedDateKey = targetKey
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The day and rating will be removed. Todos from this day are kept and moved to another day.")
        }
        .confirmationDialog(
            "Delete this todo?",
            isPresented: $showingDeleteTodoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Todo", role: .destructive) {
                executePendingTodoDelete()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTodoID = nil
                pendingDeletePlanDateKey = nil
            }
        } message: {
            Text("This task will be removed permanently.")
        }
        .sheet(isPresented: $showingCarryForwardConfirmation) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Carry this task to next day?")
                    .font(.headline)
                Text("This moves the selected task to the next day and marks it as Carry. The next day is created if needed.")
                    .foregroundStyle(.secondary)
                Toggle("Don't notify again", isOn: $carryForwardDontAskAgain)
                    .toggleStyle(.checkbox)
                HStack {
                    Button("Cancel") {
                        showingCarryForwardConfirmation = false
                        pendingCarryTodoID = nil
                        pendingCarryPlanDateKey = nil
                    }
                    Spacer()
                    Button("Carry Forward") {
                        if carryForwardDontAskAgain {
                            skipCarryForwardConfirm = true
                        }
                        executePendingCarryForward()
                    }
                    .buttonStyle(ReadableProminentButtonStyle())
                }
            }
            .padding(16)
            .frame(width: 420)
        }
        .onAppear {
            handleViewAppear()
        }
        .onChange(of: selectedDateKey) { _, _ in
            decorativeImageCycleOffset = 0
            reflectionPlaceholderIndex = (reflectionPlaceholderIndex + 1) % reflectionPrompts.count
            refreshDecorativeImagePresentation()
        }
        .onChange(of: decorativeImageCycleOffset) { _, _ in
            refreshDecorativeImagePresentation()
        }
        .onChange(of: notificationsEnabled) { _, _ in
            refreshWellnessBreakOverlaySchedule()
        }
        .onChange(of: wellnessBreakRemindersEnabled) { _, _ in
            refreshWellnessBreakOverlaySchedule()
        }
        .onChange(of: todoReminderIntervalMinutes) { _, _ in
            if notificationsEnabled {
                store.refreshTodayNotifications()
            }
        }
        .onChange(of: todoReminderMessage) { _, _ in
            if notificationsEnabled {
                store.refreshTodayNotifications()
            }
        }
        .onChange(of: emptyDayReminderMessage) { _, _ in
            if notificationsEnabled {
                store.refreshTodayNotifications()
            }
        }
        .onChange(of: wellnessBreakIntervalMinutes) { _, _ in
            refreshWellnessBreakOverlaySchedule()
        }
        .onChange(of: wellnessBreakMessage) { _, _ in
            refreshWellnessBreakOverlaySchedule()
            if notificationsEnabled && wellnessBreakRemindersEnabled {
                store.refreshTodayNotifications()
            }
        }
        .onChange(of: wellnessBreakStartMinutes) { _, _ in
            let sanitized = AppSettings.sanitizeWellnessWorkHours(
                startMinutes: wellnessBreakStartMinutes,
                endMinutes: wellnessBreakEndMinutes
            )
            wellnessBreakStartMinutes = sanitized.startMinutes
            wellnessBreakEndMinutes = sanitized.endMinutes
            refreshWellnessBreakOverlaySchedule()
            if notificationsEnabled && wellnessBreakRemindersEnabled {
                store.refreshTodayNotifications()
            }
        }
        .onChange(of: wellnessBreakEndMinutes) { _, _ in
            let sanitized = AppSettings.sanitizeWellnessWorkHours(
                startMinutes: wellnessBreakStartMinutes,
                endMinutes: wellnessBreakEndMinutes
            )
            wellnessBreakStartMinutes = sanitized.startMinutes
            wellnessBreakEndMinutes = sanitized.endMinutes
            refreshWellnessBreakOverlaySchedule()
            if notificationsEnabled && wellnessBreakRemindersEnabled {
                store.refreshTodayNotifications()
            }
        }
        .onChange(of: ignoreCarryForwardWeekends) { _, _ in
            refreshWellnessBreakOverlaySchedule()
            if notificationsEnabled && wellnessBreakRemindersEnabled {
                store.refreshTodayNotifications()
            }
        }
        .onChange(of: dayPlans.count) { _, _ in
            clampJournalPage()
            clampWeeklyRatingsOffset()
            clampMonthlyRatingsOffset()
        }
    }

    private func refreshWellnessBreakOverlaySchedule() {
        let sanitizedHours = AppSettings.sanitizeWellnessWorkHours(
            startMinutes: wellnessBreakStartMinutes,
            endMinutes: wellnessBreakEndMinutes
        )
        WellnessBreakOverlayController.shared.configure(
            isEnabled: notificationsEnabled && wellnessBreakRemindersEnabled,
            intervalMinutes: AppSettings.normalizeWellnessBreakIntervalMinutes(wellnessBreakIntervalMinutes),
            message: AppSettings.normalizeWellnessBreakMessage(wellnessBreakMessage),
            workdayStartMinutes: sanitizedHours.startMinutes,
            workdayEndMinutes: sanitizedHours.endMinutes,
            skipWeekends: ignoreCarryForwardWeekends
        )
    }

    private func loadDecorativeImageCandidateURLs() -> [URL] {
        let fileManager = FileManager.default

        var candidates: [URL] = []
        if let customFolderURL = sidebarImagesDirectoryURL,
           let enumerator = fileManager.enumerator(
                at: customFolderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
           ) {
            for case let fileURL as URL in enumerator where isDecorativeImageFile(fileURL.lastPathComponent) {
                candidates.append(fileURL)
            }
        }

        if let resourceURL = Bundle.main.resourceURL,
           let resourceFiles = try? fileManager.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
           ) {
            candidates += resourceFiles.filter { isDecorativeImageFile($0.lastPathComponent) }
        }

        let localAssetsURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("assets", isDirectory: true)
        if let enumerator = fileManager.enumerator(
            at: localAssetsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator where isDecorativeImageFile(fileURL.lastPathComponent) {
                candidates.append(fileURL)
            }
        }

        var seenPaths = Set<String>()
        let unique = candidates.filter { seenPaths.insert($0.path).inserted }
        return unique.sorted(by: decorativeImageSort)
    }

    private func reloadDecorativeImageCandidatesIfNeeded(force: Bool = false) {
        if force {
            PersistenceController.prepareDecorativeImagesDirectoryIfNeeded()
        }

        guard force || decorativeImageCandidates.isEmpty else { return }
        decorativeImageCandidates = loadDecorativeImageCandidateURLs()
    }

    private func isDecorativeImageFile(_ fileName: String) -> Bool {
        let lowercased = fileName.lowercased()
        return lowercased.hasPrefix("image-") && lowercased.hasSuffix(".png")
    }

    private func decorativeImageSort(lhs: URL, rhs: URL) -> Bool {
        let lhsName = lhs.lastPathComponent
        let rhsName = rhs.lastPathComponent

        let lhsNumber = decorativeImageNumber(from: lhsName)
        let rhsNumber = decorativeImageNumber(from: rhsName)

        switch (lhsNumber, rhsNumber) {
        case let (left?, right?):
            if left != right { return left < right }
            return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
        }
    }

    private func decorativeImageNumber(from fileName: String) -> Int? {
        let lowercased = fileName.lowercased()
        guard lowercased.hasPrefix("image-"), lowercased.hasSuffix(".png") else {
            return nil
        }

        let start = lowercased.index(lowercased.startIndex, offsetBy: "image-".count)
        let end = lowercased.index(lowercased.endIndex, offsetBy: -".png".count)
        let rawNumber = lowercased[start..<end]
        return Int(rawNumber)
    }

    private func handleViewAppear() {
        calendarMonth = monthStart(for: .now)
        reflectionPlaceholderIndex = (reflectionPlaceholderIndex + 1) % reflectionPrompts.count

        let resolvedTodayKey = todayKey
        let dayPlanKeys = dayPlans.map(\.dateKey)
        let hasTodayPlan = dayPlanKeys.contains(resolvedTodayKey)

        if selectedDateKey == nil {
            selectedDateKey = hasTodayPlan ? resolvedTodayKey : dayPlans.first?.dateKey
        }

        if let key = selectedDateKey, let date = store.date(from: key) {
            calendarMonth = monthStart(for: date)
        }

        reloadDecorativeImageCandidatesIfNeeded()
        refreshDecorativeImagePresentation()
        refreshWellnessBreakOverlaySchedule()
        store.refreshTodayNotifications()

        if !backgroundAudioEnabled {
            backgroundAudioController.pause()
        } else {
            backgroundAudioController.loadLibraryIfNeeded()
        }
    }

    private func refreshDecorativeImagePresentation() {
        guard let imageURL = currentDecorativeImageURL else {
            currentDecorativeImage = nil
            currentDecorativeImagePath = nil
            decorativeImageBloomColor = Color.accentColor.opacity(0.35)
            return
        }

        if currentDecorativeImagePath != imageURL.path {
            currentDecorativeImage = NSImage(contentsOf: imageURL)
            currentDecorativeImagePath = imageURL.path
        }

        if let cachedColor = decorativeImageColorCache[imageURL.path] {
            decorativeImageBloomColor = cachedColor
            return
        }

        guard let image = currentDecorativeImage, let dominant = dominantColor(for: image) else {
            decorativeImageBloomColor = Color.accentColor.opacity(0.35)
            return
        }

        let color = Color(
            red: dominant.red,
            green: dominant.green,
            blue: dominant.blue,
            opacity: 0.45
        )
        decorativeImageColorCache[imageURL.path] = color
        decorativeImageBloomColor = color
    }

    private func dominantColor(for image: NSImage) -> (red: Double, green: Double, blue: Double)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let xStep = max(1, width / 64)
        let yStep = max(1, height / 64)

        var buckets: [Int: (count: Int, red: Double, green: Double, blue: Double)] = [:]

        for y in stride(from: 0, to: height, by: yStep) {
            for x in stride(from: 0, to: width, by: xStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.alphaComponent < 0.1 {
                    continue
                }

                let r = Double(color.redComponent)
                let g = Double(color.greenComponent)
                let b = Double(color.blueComponent)
                let rBin = Int(r * 15)
                let gBin = Int(g * 15)
                let bBin = Int(b * 15)
                let key = (rBin << 8) | (gBin << 4) | bBin

                let existing = buckets[key] ?? (count: 0, red: 0, green: 0, blue: 0)
                buckets[key] = (
                    count: existing.count + 1,
                    red: existing.red + r,
                    green: existing.green + g,
                    blue: existing.blue + b
                )
            }
        }

        guard let bucket = buckets.max(by: { $0.value.count < $1.value.count })?.value,
              bucket.count > 0 else {
            return nil
        }

        let count = Double(bucket.count)
        return (
            red: bucket.red / count,
            green: bucket.green / count,
            blue: bucket.blue / count
        )
    }

    private var sidebar: some View {
        GeometryReader { geometry in
            let totalHeight = max(geometry.size.height, 1)
            let separatorHeight: CGFloat = 14
            let minImageHeight: CGFloat = 120
            let maxImageHeight = max(minImageHeight, totalHeight * 0.65)
            let imageHeight = min(max(totalHeight * imagePanelFraction, minImageHeight), maxImageHeight)

            VStack(spacing: 0) {
                List(selection: $selectedDateKey) {
                    Section {
                        Button {
                            detailMode = .day
                            selectedDateKey = todayKey
                            store.ensureDayPlan(for: todayKey)
                        } label: {
                            sidebarNavigationRow(
                                title: "Today",
                                systemImage: "calendar",
                                isSelected: detailMode == .day && selectedDateKey == todayKey
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            detailMode = .todos
                        } label: {
                            sidebarNavigationRow(
                                title: "All Todos",
                                systemImage: "checklist",
                                isSelected: detailMode == .todos
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            detailMode = .calendar
                            if let selectedPlan,
                               let date = store.date(from: selectedPlan.dateKey) {
                                calendarMonth = monthStart(for: date)
                            } else {
                                calendarMonth = monthStart(for: .now)
                            }
                        } label: {
                            sidebarNavigationRow(
                                title: "Calendar",
                                systemImage: "calendar.day.timeline.leading",
                                isSelected: detailMode == .calendar
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            detailMode = .stats
                        } label: {
                            sidebarNavigationRow(
                                title: "Stats",
                                systemImage: "chart.bar",
                                isSelected: detailMode == .stats
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            detailMode = .journal
                            clampJournalPage()
                        } label: {
                            sidebarNavigationRow(
                                title: "Journal",
                                systemImage: "book.closed",
                                isSelected: detailMode == .journal
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            detailMode = .soundMixer
                        } label: {
                            sidebarNavigationRow(
                                title: "Sound Mixer",
                                systemImage: "speaker.wave.3",
                                isSelected: detailMode == .soundMixer
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            detailMode = .settings
                        } label: {
                            sidebarNavigationRow(
                                title: "Settings",
                                systemImage: "gearshape",
                                isSelected: detailMode == .settings
                            )
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("Planner")
                            .font(scaledFont(13, weight: .semibold))
                    }

                    Section {
                        ForEach(recentPlans) { plan in
                            Button {
                                detailMode = .day
                                selectedDateKey = plan.dateKey
                            } label: {
                                historyRow(for: plan)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(selectedDateKey == plan.dateKey && detailMode == .day ? Color.accentColor.opacity(0.16) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .onDrop(
                                of: [UTType.text.identifier],
                                delegate: TodoDayMoveDropDelegate(
                                    targetPlan: plan,
                                    dayPlans: dayPlans,
                                    store: store,
                                    draggedToken: $draggedTodoToken,
                                    tokenForTodo: todoDragToken(_:)
                                )
                            )
                            .contextMenu {
                                Button(role: .destructive) {
                                    calendarDeleteDayKey = plan.dateKey
                                } label: {
                                    Label("Delete Day", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("History")
                            .font(scaledFont(13, weight: .semibold))
                    }
                }
                .listStyle(.sidebar)
                .environment(\.defaultMinListRowHeight, uiScaleController.scaledMetric(34))

                if let decorativeImage {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: uiScaleController.scaledMetric(separatorHeight))
                        .overlay(alignment: .center) {
                            Divider()
                                .overlay(Color.primary.opacity(0.22))
                        }
                        .overlay(alignment: .center) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(
                                    width: uiScaleController.scaledMetric(44),
                                    height: uiScaleController.scaledMetric(4)
                                )
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if imagePanelDragStartFraction == nil {
                                        imagePanelDragStartFraction = imagePanelFraction
                                    }
                                    let start = imagePanelDragStartFraction ?? imagePanelFraction
                                    let updated = start - (value.translation.height / totalHeight)
                                    imagePanelFraction = min(max(updated, 0.18), 0.65)
                                }
                                .onEnded { _ in
                                    imagePanelDragStartFraction = nil
                                }
                        )
                        .onHover { hovering in
                            updateImageDividerCursor(hovering: hovering)
                        }
                        .onDisappear {
                            updateImageDividerCursor(hovering: false)
                        }

                    Button {
                        let count = decorativeImageCandidates.count
                        guard count > 1 else { return }
                        decorativeImageCycleOffset = (decorativeImageCycleOffset + 1) % count
                    } label: {
                        ZStack {
                            Circle()
                                .fill(decorativeImageBloomColor)
                                .frame(
                                    width: uiScaleController.scaledMetric(176),
                                    height: uiScaleController.scaledMetric(176)
                                )
                                .blur(radius: uiScaleController.scaledMetric(28))
                                .opacity(0.22)
                                .offset(y: uiScaleController.scaledMetric(10))
                                .allowsHitTesting(false)

                            Image(nsImage: decorativeImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                .opacity(0.92)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight)
                    .padding(.horizontal, uiScaleController.scaledMetric(8))
                    .padding(.bottom, uiScaleController.scaledMetric(10))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func historyRow(for plan: DayPlan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(shortDayLabel(for: plan.dateKey))
                    .font(scaledFont(17, weight: .semibold))
                Text(summaryText(for: plan))
                    .font(scaledFont(14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(plan.dayRating.map { "\($0)/10" } ?? "-")
                .font(scaledFont(14))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, uiScaleController.scaledMetric(7))
        .padding(.horizontal, uiScaleController.scaledMetric(6))
    }

    private func sidebarNavigationRow(title: String, systemImage: String, isSelected: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(scaledFont(16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, uiScaleController.scaledMetric(7))
            .padding(.horizontal, uiScaleController.scaledMetric(6))
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
    }

    @ViewBuilder
    private var detail: some View {
        switch detailMode {
        case .day:
            if let plan = selectedPlan {
                dayView(plan: plan)
            } else {
                ContentUnavailableView("No day selected", systemImage: "calendar.badge.exclamationmark")
            }
        case .todos:
            allTodosView
        case .calendar:
            calendarGridView
        case .stats:
            statsView
        case .journal:
            journalView
        case .soundMixer:
            soundMixerView
        case .settings:
            settingsView
        }
    }

    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Settings")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("A calmer, better-aligned space for planner preferences.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsSectionHeader(
                            title: "General",
                            description: "Carry-forward behavior and app defaults."
                        )

                        settingsDivider()

                        settingsToggleRow(
                            title: "Ignore Weekends",
                            description: "Carry unfinished tasks to the next workday instead of Saturday or Sunday.",
                            isOn: $ignoreCarryForwardWeekends
                        )

                        settingsDivider()

                        settingsToggleRow(
                            title: "Skip Confirmation",
                            description: "Move a task forward immediately without showing the carry-forward confirmation sheet.",
                            isOn: $skipCarryForwardConfirm
                        )

                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsSectionHeader(
                            title: "Planner Notifications",
                            description: "Todo-focused reminders in macOS Notification Center."
                        )

                        settingsDivider()

                        settingsToggleRow(
                            title: "Todo Reminders",
                            description: "Planner nudges for unfinished todos and empty days.",
                            isOn: Binding(
                                get: { notificationsEnabled },
                                set: { newValue in
                                    notificationsEnabled = newValue
                                    if newValue {
                                        store.refreshTodayNotifications()
                                    } else {
                                        DailyReminderScheduler.shared.clearPendingNotifications()
                                    }
                                }
                            )
                        )

                        settingsDivider()

                        VStack(alignment: .leading, spacing: 14) {
                            settingsControlRow(
                                title: "Reminder Interval",
                                description: "Choose how often unfinished todos should nudge you between 11:00 and 17:00."
                            ) {
                                Stepper(
                                    value: Binding(
                                        get: {
                                            AppSettings.normalizeTodoReminderIntervalMinutes(todoReminderIntervalMinutes)
                                        },
                                        set: { newValue in
                                            todoReminderIntervalMinutes = AppSettings.normalizeTodoReminderIntervalMinutes(newValue)
                                            if notificationsEnabled {
                                                store.refreshTodayNotifications()
                                            }
                                        }
                                    ),
                                    in: AppSettings.minimumTodoReminderIntervalMinutes...AppSettings.maximumTodoReminderIntervalMinutes,
                                    step: AppSettings.todoReminderIntervalStepMinutes
                                ) {
                                    Text("\(AppSettings.normalizeTodoReminderIntervalMinutes(todoReminderIntervalMinutes)) min")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .frame(minWidth: 88, alignment: .trailing)
                                }
                            }
                            .disabled(!notificationsEnabled)

                            settingsControlRow(
                                title: "Pending Todo Message",
                                description: "Use `{count}` anywhere to show the number of unfinished todos."
                            ) {
                                TextField(
                                    "You still have {count} todo(s) left. Pick one and keep going.",
                                    text: Binding(
                                        get: { AppSettings.normalizeTodoReminderMessage(todoReminderMessage) },
                                        set: { todoReminderMessage = $0 }
                                    ),
                                    axis: .vertical
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(2...4)
                                .frame(width: 320)
                            }
                            .disabled(!notificationsEnabled)

                            settingsControlRow(
                                title: "Empty Day Message",
                                description: "Shown when today has no todos yet."
                            ) {
                                TextField(
                                    "What would you like to work on today?",
                                    text: Binding(
                                        get: { AppSettings.normalizeEmptyDayReminderMessage(emptyDayReminderMessage) },
                                        set: { emptyDayReminderMessage = $0 }
                                    ),
                                    axis: .vertical
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(2...4)
                                .frame(width: 320)
                            }
                            .disabled(!notificationsEnabled)
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 18)
                        .padding(.horizontal, 18)

                        if developerModeEnabled {
                            settingsDivider()

                            settingsControlRow(
                                title: "Test Delivery",
                                description: isCheckingNotificationStatus
                                    ? "Checking current notification state..."
                                    : "Test a reminder and inspect the macOS permission state."
                            ) {
                                HStack(spacing: 10) {
                                    Button("Remind Now") {
                                        isCheckingNotificationStatus = true
                                        notificationDebugMessage = "Checking notification permission and scheduling a test reminder..."
                                        Task {
                                            let snapshot = await DailyReminderScheduler.shared.sendTestNotification()
                                            await MainActor.run {
                                                notificationDebugMessage = snapshot.summary
                                                isCheckingNotificationStatus = false
                                            }
                                        }
                                    }
                                    .buttonStyle(ReadableProminentButtonStyle())
                                    .disabled(!notificationsEnabled || isCheckingNotificationStatus)

                                    Button("Check Permission") {
                                        isCheckingNotificationStatus = true
                                        notificationDebugMessage = "Reading current notification settings..."
                                        Task {
                                            let snapshot = await DailyReminderScheduler.shared.permissionDebugSnapshot()
                                            await MainActor.run {
                                                notificationDebugMessage = snapshot.summary
                                                isCheckingNotificationStatus = false
                                            }
                                        }
                                    }
                                    .buttonStyle(ReadableSecondaryButtonStyle())
                                    .disabled(isCheckingNotificationStatus)
                                }
                            }

                            Text(notificationDebugMessage)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                                )
                                .padding(.horizontal, 18)
                                .padding(.top, 18)

                            settingsDivider()

                            wellnessDiagnosticsPanel
                        }
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsSectionHeader(
                            title: "Wellness Breaks",
                            description: "Fullscreen break overlays and optional break reminders."
                        )

                        settingsDivider()

                        VStack(alignment: .leading, spacing: 14) {
                            settingsToggleRow(
                                title: "Wellness Break",
                                description: "Repeat reminders to stand up, stretch, exercise, or rest your eyes.",
                                isOn: Binding(
                                    get: { wellnessBreakRemindersEnabled },
                                    set: { newValue in
                                        wellnessBreakRemindersEnabled = newValue
                                        if notificationsEnabled {
                                            store.refreshTodayNotifications()
                                        }
                                    }
                                )
                            )
                            .disabled(!notificationsEnabled)

                            settingsControlRow(
                                title: "Break Interval",
                                description: "Choose how often the wellness reminder should appear."
                            ) {
                                Stepper(
                                    value: Binding(
                                        get: {
                                            AppSettings.normalizeWellnessBreakIntervalMinutes(wellnessBreakIntervalMinutes)
                                        },
                                        set: { newValue in
                                            wellnessBreakIntervalMinutes = AppSettings.normalizeWellnessBreakIntervalMinutes(newValue)
                                            if notificationsEnabled && wellnessBreakRemindersEnabled {
                                                store.refreshTodayNotifications()
                                            }
                                        }
                                    ),
                                    in: AppSettings.minimumWellnessBreakIntervalMinutes...AppSettings.maximumWellnessBreakIntervalMinutes,
                                    step: AppSettings.wellnessBreakIntervalStepMinutes
                                ) {
                                    Text("\(AppSettings.normalizeWellnessBreakIntervalMinutes(wellnessBreakIntervalMinutes)) min")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .frame(minWidth: 88, alignment: .trailing)
                                }
                            }
                            .disabled(!notificationsEnabled || !wellnessBreakRemindersEnabled)

                            settingsControlRow(
                                title: "Work Hours",
                                description: ignoreCarryForwardWeekends
                                    ? "Wellness reminders run only during this window on weekdays."
                                    : "Wellness reminders run only during this window each day."
                            ) {
                                HStack(spacing: 12) {
                                    DatePicker(
                                        "Start",
                                        selection: wellnessBreakTimeBinding(for: .start),
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                    .datePickerStyle(.field)
                                    .frame(width: 110)

                                    Text("to")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)

                                    DatePicker(
                                        "End",
                                        selection: wellnessBreakTimeBinding(for: .end),
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                    .datePickerStyle(.field)
                                    .frame(width: 110)
                                }
                            }
                            .disabled(!notificationsEnabled || !wellnessBreakRemindersEnabled)

                            settingsControlRow(
                                title: "Reminder Message",
                                description: "Write the prompt you want to see during each wellness break."
                            ) {
                                TextField(
                                    "Remind me to stretch my neck and look far away",
                                    text: Binding(
                                        get: { AppSettings.normalizeWellnessBreakMessage(wellnessBreakMessage) },
                                        set: { wellnessBreakMessage = $0 }
                                    ),
                                    axis: .vertical
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(2...4)
                                .frame(width: 320)
                            }
                            .disabled(!notificationsEnabled || !wellnessBreakRemindersEnabled)
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 18)
                        .padding(.horizontal, 18)
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsSectionHeader(
                            title: "Visuals",
                            description: "Adjust readability and the app’s overall look."
                        )

                        settingsDivider()

                        settingsControlRow(
                            title: "UI Scale",
                            description: "Use Command-Plus, Command-Minus, or Command-0 anywhere in the app."
                        ) {
                            HStack(spacing: 10) {
                                Button {
                                    uiScaleController.zoomOut()
                                } label: {
                                    Label("Smaller", systemImage: "minus")
                                }

                                Button {
                                    uiScaleController.zoomIn()
                                } label: {
                                    Label("Larger", systemImage: "plus")
                                }

                                Text("\(Int((uiScaleController.scale * 100).rounded()))%")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .frame(width: 58, alignment: .trailing)

                                Button("Reset") {
                                    uiScaleController.reset()
                                }
                                .disabled(uiScaleController.isDefaultScale)
                            }
                        }

                        settingsDivider()

                        settingsControlRow(
                            title: "Theme Tint",
                            description: "A soft accent wash for translucent cards and panels."
                        ) {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(themeTintColor)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                                    )

                                ColorPicker(
                                    "Shade Color",
                                    selection: Binding(
                                        get: { themeTintColor },
                                        set: { newValue in
                                            guard let color = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                                            var red: CGFloat = 0
                                            var green: CGFloat = 0
                                            var blue: CGFloat = 0
                                            var alpha: CGFloat = 0
                                            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                                            themeTintRed = Double(red)
                                            themeTintGreen = Double(green)
                                            themeTintBlue = Double(blue)
                                            themeTintOpacity = Double(alpha)
                                        }
                                    ),
                                    supportsOpacity: true
                                )
                                .labelsHidden()
                            }
                        }

                        settingsDivider()

                        settingsControlRow(
                            title: "Sidebar Images",
                            description: "Open the app-managed folder and drag transparent PNGs into it. Best results come from artwork with the main subject centered and generous empty space around it."
                        ) {
                            HStack(spacing: 10) {
                                Text(sidebarImagesDirectoryLabel)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(minWidth: 120, alignment: .trailing)

                                Button("Open Folder") {
                                    if let sidebarImagesDirectoryURL {
                                        PersistenceController.prepareDecorativeImagesDirectoryIfNeeded()
                                        NSWorkspace.shared.open(sidebarImagesDirectoryURL)
                                        reloadDecorativeImageCandidatesIfNeeded(force: true)
                                        decorativeImageCycleOffset = 0
                                        refreshDecorativeImagePresentation()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsSectionHeader(
                            title: "Background Audio",
                            description: "Keep audio behavior, cache access, and launch preferences here."
                        )

                        settingsDivider()

                        settingsToggleRow(
                            title: "Enable Background Audio",
                            description: "Keep the mini player and library ready without autoplaying on launch.",
                            isOn: Binding(
                                get: { backgroundAudioEnabled },
                                set: { newValue in
                                    backgroundAudioEnabled = newValue
                                    if !newValue {
                                        backgroundAudioController.pause()
                                    }
                                }
                            )
                        )

                        settingsDivider()

                        settingsToggleRow(
                            title: "Auto Resume",
                            description: "Load the mixer state on launch without automatically turning tiles back on.",
                            isOn: $backgroundAudioAutoResume
                        )

                        settingsDivider()

                        settingsControlRow(
                            title: "Master Volume",
                            description: "Adjust the overall level across all active sound-effect tiles."
                        ) {
                            HStack(spacing: 12) {
                                Slider(
                                    value: Binding(
                                        get: { backgroundAudioController.masterVolume },
                                        set: { backgroundAudioController.setMasterVolume($0) }
                                    ),
                                    in: 0...1
                                )
                                .frame(width: 180)

                                Text("\(Int((backgroundAudioController.masterVolume * 100).rounded()))%")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }

                        settingsDivider()

                        settingsControlRow(
                            title: "Cache Folder",
                            description: "Open the local cache for downloaded Pixabay sound effects or force a metadata refresh."
                        ) {
                            HStack(spacing: 10) {
                                Button("Open Cache") {
                                    backgroundAudioController.openEffectsCacheFolder()
                                }
                                .buttonStyle(.bordered)

                                Button("Refresh") {
                                    backgroundAudioController.loadLibrary()
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        settingsDivider()

                        settingsControlRow(
                            title: "Saved Mixes JSON",
                            description: "Export your five saved mix slots as a portable JSON file."
                        ) {
                            Button("Export Saved Mixes") {
                                exportSavedMixesJSON()
                            }
                            .buttonStyle(.bordered)
                        }

                        settingsDivider()

                        settingsControlRow(
                            title: "Open Mixer",
                            description: "Go to the dedicated sidebar page for tiles, balancing, and live playback."
                        ) {
                            Button("Open Sound Mixer") {
                                detailMode = .soundMixer
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if developerModeEnabled {
                            settingsDivider()

                            Text(backgroundAudioController.statusMessage)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                                )
                                .padding(.horizontal, 18)
                                .padding(.top, 18)
                        }
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsSectionHeader(
                            title: "About",
                            description: "Version info, developer tools, and quick links."
                        )

                        settingsDivider()

                        settingsValueRow(
                            title: "Version",
                            description: "Current app version and build number.",
                            value: appVersionDisplay
                        )

                        settingsDivider()

                        settingsToggleRow(
                            title: "Developer Mode",
                            description: "Show logs, diagnostics, and internal debugging tools in Settings.",
                            isOn: $developerModeEnabled
                        )

                        settingsDivider()

                        settingsControlRow(
                            title: "GitHub",
                            description: "Open the developer profile in your browser."
                        ) {
                            if let githubURL = URL(string: "https://github.com/bogas04") {
                                Link(
                                    "github.com/bogas04",
                                    destination: githubURL
                                )
                                .buttonStyle(.bordered)
                            } else {
                                Text("GitHub link unavailable")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsSectionHeader(
                            title: "Storage",
                            description: "Import, export, inspect, or clear local planner data."
                        )

                        settingsDivider()

                        settingsControlRow(
                            title: "Data Tools",
                            description: "Export a snapshot, import one, or inspect the local storage folder."
                        ) {
                            HStack(spacing: 10) {
                                Button("Export") {
                                    exportDataJSON()
                                }
                                .buttonStyle(.bordered)

                                Button("Import") {
                                    importDataJSON()
                                }
                                .buttonStyle(.bordered)
                                .help("Import replaces all current days, todos, and links.")

                                Button("Open Folder") {
                                    if let directory = PersistenceController.storeDirectoryURL() {
                                        NSWorkspace.shared.open(directory)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if developerModeEnabled {
                            settingsDivider()

                            settingsControlRow(
                                title: "Logs",
                                description: "Open Console or export recent unified logs for Focused Day Planner."
                            ) {
                                HStack(spacing: 10) {
                                    Button("Open Console") {
                                        AppLogAccess.openConsoleApp()
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Export Recent Logs") {
                                        exportRecentLogs()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        settingsDivider()

                        settingsControlRow(
                            title: "Danger Zone",
                            description: "Remove all days, ratings, todos, and local planner history from this Mac."
                        ) {
                            Button("Delete All Data", role: .destructive) {
                                showingDeleteAllDataConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .confirmationDialog(
            "Delete all data?",
            isPresented: $showingDeleteAllDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Data", role: .destructive) {
                store.deleteAllData()
                selectedDateKey = nil
                detailMode = .settings
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all days, ratings, and todos from local storage.")
        }
    }

    private func settingsSectionHeader(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(description)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func settingsDivider() -> some View {
        Divider()
            .padding(.horizontal, 18)
    }

    private func settingsToggleRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(description)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func settingsValueRow(title: String, description: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(description)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func settingsControlRow<Control: View>(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(description)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            control()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func wellnessBreakTimeBinding(for edge: WellnessBreakTimeEdge) -> Binding<Date> {
        Binding(
            get: {
                let minutes = edge == .start ? wellnessBreakStartMinutes : wellnessBreakEndMinutes
                return timeOnlyDate(for: minutes)
            },
            set: { newDate in
                let minutes = minutesSinceStartOfDay(for: newDate)
                let sanitized: (startMinutes: Int, endMinutes: Int)
                switch edge {
                case .start:
                    sanitized = AppSettings.sanitizeWellnessWorkHours(
                        startMinutes: minutes,
                        endMinutes: wellnessBreakEndMinutes
                    )
                case .end:
                    sanitized = AppSettings.sanitizeWellnessWorkHours(
                        startMinutes: wellnessBreakStartMinutes,
                        endMinutes: minutes
                    )
                }
                wellnessBreakStartMinutes = sanitized.startMinutes
                wellnessBreakEndMinutes = sanitized.endMinutes
            }
        )
    }

    private func timeOnlyDate(for minutes: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0
        return calendar.date(from: components) ?? .now
    }

    private func minutesSinceStartOfDay(for date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private var wellnessDiagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Status")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text(wellnessBreakOverlayController.timerIsActive ? "Timer Active" : "Timer Inactive")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(wellnessBreakOverlayController.timerIsActive ? .green : .secondary)
            }

            diagnosticsRow(
                label: "Next Break",
                value: nextBreakStatusText()
            )
            diagnosticsRow(
                label: "Last Overlay",
                value: timestampText(for: wellnessBreakOverlayController.lastOverlayShownAt)
            )
            diagnosticsRow(
                label: "Notification Status",
                value: reminderScheduler.lastNotificationStatus
            )
            diagnosticsRow(
                label: "Updated",
                value: timestampText(for: reminderScheduler.lastNotificationUpdatedAt)
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func diagnosticsRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func nextBreakStatusText() -> String {
        guard wellnessBreakOverlayController.timerIsActive else { return "Disabled" }
        guard let nextTriggerDate = wellnessBreakOverlayController.nextTriggerDate else { return "Waiting for schedule" }
        return timeText(for: nextTriggerDate)
    }

    private func timestampText(for date: Date?) -> String {
        guard let date else { return "Never" }
        return timeText(for: date)
    }

    private func timeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private var soundMixerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sound Mixer")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Build a custom background mix from looping sound-effect tiles.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        settingsSectionHeader(
                            title: "Live Mix",
                            description: "Click a tile to balance active sounds evenly. Drag across a tile to set its exact level."
                        )

                        settingsDivider()

                        settingsControlRow(
                            title: "Playback",
                            description: backgroundAudioController.isPlaying
                                ? "Your current mix is playing."
                                : "Resume the mix without losing the tile percentages."
                        ) {
                            HStack(spacing: 10) {
                                Button(backgroundAudioController.isPlaying ? "Pause Mix" : "Resume Mix") {
                                    if backgroundAudioEnabled {
                                        backgroundAudioController.togglePlayback()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!backgroundAudioEnabled || backgroundAudioController.activeSoundCount == 0)

                                if backgroundAudioController.isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                }

                                Text("\(backgroundAudioController.activeSoundCount) active")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                            }
                        }

                        settingsDivider()

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Saved Mixes")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))

                            Button(backgroundAudioController.nextMixName.map { "Save As \($0)" } ?? "5 Mixes Saved") {
                                backgroundAudioController.saveCurrentMixAsNextSlot()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!backgroundAudioController.canSaveNewMix)

                            if !backgroundAudioController.savedMixes.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(backgroundAudioController.savedMixes) { mix in
                                            savedMixCard(for: mix)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)

                        settingsDivider()

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Sound Tiles")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))

                            LazyVGrid(columns: soundMixerColumns, spacing: 14) {
                                ForEach(backgroundAudioController.soundEffects) { effect in
                                    soundMixerTile(for: effect)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)

                        settingsDivider()

                        Text(backgroundAudioController.statusMessage)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                            )
                            .padding(.horizontal, 18)
                            .padding(.top, 18)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            backgroundAudioController.loadLibraryIfNeeded()
        }
    }

    private func savedMixCard(for mix: SavedSoundMix) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)

            Text("Mix \(mix.slotNumber)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Button {
                pendingDeleteMixSlotNumber = mix.slotNumber
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 132, height: 68)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            backgroundAudioController.loadMix(from: mix.slotNumber)
        }
    }

    private func soundMixerTile(for effect: SoundEffectDefinition) -> some View {
        let level = backgroundAudioController.mixLevel(for: effect.id)

        return GeometryReader { proxy in
            let fillWidth = proxy.size.width * level

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(level > 0 ? 0.22 : 0.08))
                    .frame(width: max(fillWidth, level > 0 ? 16 : 0))

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(level > 0 ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.2), lineWidth: level > 0 ? 1.5 : 1)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(effect.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text(effect.subtitle)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text("\(Int((level * 100).rounded()))%")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(level > 0 ? Color.accentColor : .secondary)
                    }

                    Spacer(minLength: 0)

                    HStack {
                        Text("Click to balance")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Drag to mix")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dragDistance = abs(value.translation.width) + abs(value.translation.height)
                        guard dragDistance > 4 else { return }
                        let proportion = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        backgroundAudioController.setMixLevel(for: effect.id, value: proportion)
                    }
                    .onEnded { value in
                        let dragDistance = abs(value.translation.width) + abs(value.translation.height)
                        if dragDistance <= 4 {
                            backgroundAudioController.toggleSoundEffect(effect.id)
                        } else {
                            let proportion = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                            backgroundAudioController.setMixLevel(for: effect.id, value: proportion)
                        }
                    }
            )
        }
        .frame(height: 132)
    }

    private func exportSavedMixesJSON() {
        let panel = NSSavePanel()
        panel.title = "Export Saved Mixes"
        panel.nameFieldStringValue = "focused-day-planner-mixes.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try backgroundAudioController.exportSavedMixesJSON(to: url)
            dataTransferMessage = "Saved mixes exported:\n\(url.path)"
        } catch {
            dataTransferMessage = "Saved mix export failed: \(error.localizedDescription)"
        }
    }

    private var statsView: some View {
        let ratedValues = dayPlans.compactMap(\.dayRating)
        let overallRating: Double? = ratedValues.isEmpty
            ? nil
            : Double(ratedValues.reduce(0) { $0 + $1 }) / Double(ratedValues.count)
        let selectedOffset = statsSelectedOffset
        let currentDonePerDay = averageDonePerDay(for: statsTimeframe, offsetFromCurrent: 0)
        let previousDonePerDay = averageDonePerDay(for: statsTimeframe, offsetFromCurrent: -1)
        let selectedSummary = ratingSummary(for: statsTimeframe, offsetFromCurrent: selectedOffset)
        let currentRating = averageRating(for: statsTimeframe, offsetFromCurrent: 0)
        let previousRating = averageRating(for: statsTimeframe, offsetFromCurrent: -1)
        let ratingChangeText = ratingChangeText(current: currentRating, previous: previousRating)
        let trendSummaries = ratingTrendSummaries(for: statsTimeframe, limit: 8)
        let periodTitle = statsTimeframe.title
        let periodLabel = statsTimeframe.singularLabel
        let currentPeriodTitle = statsTimeframe == .weekly ? "This Week" : "This Month"
        let previousPeriodTitle = statsTimeframe == .weekly ? "Previous Week" : "Previous Month"

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Stats")
                            .font(.largeTitle)
                            .fontWeight(.semibold)

                        HStack {
                            Text("Overall Rating")
                                .font(.title3)
                            Spacer()
                            Text(overallRating.map { String(format: "%.1f/10", $0) } ?? "-")
                                .font(.title3.weight(.semibold))
                        }

                        Picker("Stats Timeframe", selection: $statsTimeframe) {
                            ForEach(StatsTimeframe.allCases) { timeframe in
                                Text(timeframe.title).tag(timeframe)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(currentPeriodTitle)'s Rating")
                                .font(.title3)
                            Spacer()
                            Text(currentRating.map { String(format: "%.1f/10", $0) } ?? "-")
                                .font(.title3.weight(.semibold))
                            if let ratingChangeText {
                                Text("(\(ratingChangeText) from last \(periodLabel))")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(ratingChangeText.hasPrefix("+") ? .green : .secondary)
                            }
                        }

                        HStack {
                            Text("Todos Done/Day (\(currentPeriodTitle))")
                                .font(.title3)
                            Spacer()
                            Text(String(format: "%.1f", currentDonePerDay))
                                .font(.title3.weight(.semibold))
                        }

                        HStack {
                            Text("Todos Done/Day (\(previousPeriodTitle))")
                                .font(.title3)
                            Spacer()
                            Text(String(format: "%.1f", previousDonePerDay))
                                .font(.title3.weight(.semibold))
                        }
                    }
                }

                sectionCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("\(periodTitle) Ratings")
                                .font(.title2.weight(.semibold))
                            Spacer()
                            Button("Previous") {
                                adjustStatsOffset(by: -1)
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedOffset <= earliestRatedOffset(for: statsTimeframe))

                            Button("Next") {
                                adjustStatsOffset(by: 1)
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedOffset >= 0)
                        }

                        Text(selectedSummary.map { intervalRangeLabel(for: $0.interval, timeframe: statsTimeframe) } ?? "No ratings yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        HStack(alignment: .firstTextBaseline) {
                            Text(selectedSummary?.averageRating.map { String(format: "%.1f/10", $0) } ?? "-")
                                .font(.system(size: 34, weight: .semibold))
                            Spacer()
                            Text(selectedSummary.map { "\($0.ratedDaysCount) rated day\($0.ratedDaysCount == 1 ? "" : "s")" } ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if trendSummaries.isEmpty {
                            Text("Add ratings to start seeing your \(periodLabel)-by-\(periodLabel) trend.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Recent Trend")
                                    .font(.headline)

                                ForEach(trendSummaries) { summary in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(intervalShortLabel(for: summary.interval, timeframe: statsTimeframe))
                                                .font(.subheadline.weight(.medium))
                                            Spacer()
                                            Text(summary.averageRating.map { String(format: "%.1f", $0) } ?? "-")
                                                .font(.subheadline.monospacedDigit())
                                                .foregroundStyle(summary.offset == selectedOffset ? .primary : .secondary)
                                        }

                                        GeometryReader { proxy in
                                            let value = CGFloat((summary.averageRating ?? 0) / 10.0)
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color.secondary.opacity(0.12))
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(summary.offset == selectedOffset ? Color.accentColor : Color.accentColor.opacity(0.45))
                                                    .frame(width: proxy.size.width * value)
                                            }
                                        }
                                        .frame(height: 10)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        openJournal(for: summary.interval)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var journalView: some View {
        let entries = filteredJournalEntries
        let totalDays = entries.count
        let startIndex = min(journalPage * journalPageSize, totalDays)
        let endIndex = min(startIndex + journalPageSize, totalDays)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Journal")
                            .font(scaledFont(32, weight: .semibold))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Read daily reflections with ratings, without switching into the todo view.")
                                .font(scaledFont(14))
                                .foregroundStyle(.secondary)
                            if let journalDateRange {
                                Text("Showing notes for \(journalRangeLabel(for: journalDateRange))")
                                    .font(scaledFont(14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Text(totalDays == 0
                                 ? "No days yet"
                                 : "Showing \(startIndex + 1)-\(endIndex) of \(totalDays)")
                                .font(scaledFont(14))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Previous") {
                                journalPage = max(journalPage - 1, 0)
                            }
                            .disabled(journalPage == 0)
                            .buttonStyle(.bordered)

                            Text("Page \(journalPage + 1) of \(journalPageCount)")
                                .font(scaledFont(14))
                                .foregroundStyle(.secondary)

                            Button("Next") {
                                journalPage = min(journalPage + 1, max(0, journalPageCount - 1))
                            }
                            .disabled(journalPage >= journalPageCount - 1 || totalDays == 0)
                            .buttonStyle(.bordered)

                            if journalDateRange != nil {
                                Button("Show All") {
                                    journalDateRange = nil
                                    journalPage = 0
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                if entries.isEmpty {
                    ContentUnavailableView("No journal entries yet", systemImage: "book.closed")
                } else {
                    ForEach(journalEntries) { plan in
                        journalDayCard(for: plan)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var journalPageCount: Int {
        max(1, Int(ceil(Double(filteredJournalEntries.count) / Double(journalPageSize))))
    }

    private var filteredJournalEntries: [DayPlan] {
        guard let journalDateRange else { return dayPlans }
        return dayPlans.filter { plan in
            guard let date = store.date(from: plan.dateKey) else { return false }
            return journalDateRange.contains(date)
        }
    }

    private var journalEntries: [DayPlan] {
        let source = filteredJournalEntries
        let start = journalPage * journalPageSize
        guard start < source.count else { return [] }
        let end = min(start + journalPageSize, source.count)
        return Array(source[start..<end])
    }

    private func clampJournalPage() {
        let maxPage = max(0, journalPageCount - 1)
        journalPage = min(max(journalPage, 0), maxPage)
    }

    private func openJournal(for interval: DateInterval) {
        journalDateRange = interval
        journalPage = 0
        detailMode = .journal
        switch statsTimeframe {
        case .weekly:
            weeklyRatingsOffset = offset(for: interval, timeframe: .weekly)
        case .monthly:
            monthlyRatingsOffset = offset(for: interval, timeframe: .monthly)
        }
    }

    private func journalDayCard(for plan: DayPlan) -> some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedDayLabel(for: plan.dateKey))
                        .font(scaledFont(20, weight: .semibold))
                    Spacer()
                    Text("Rating: \(plan.dayRating.map { "\($0)/10" } ?? "-")")
                        .font(scaledFont(14))
                        .foregroundStyle(.secondary)
                    Button("Open Day") {
                        selectedDateKey = plan.dateKey
                        detailMode = .day
                    }
                    .buttonStyle(.bordered)
                }

                Text("Reflection")
                    .font(scaledFont(14, weight: .semibold))
                Text(journalReflectionText(for: plan))
                    .font(scaledFont(16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func journalReflectionText(for plan: DayPlan) -> String {
        let text = (plan.reflection ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No reflection recorded for this day." : text
    }

    private func dayView(plan: DayPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(for: plan)
                todoSection(for: plan)
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func header(for plan: DayPlan) -> some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 18) {
                Button {
                    dateEditorValue = store.date(from: plan.dateKey) ?? .now
                    showingDateEditor = true
                } label: {
                    HStack(spacing: 8) {
                        Text(formattedDayLabel(for: plan.dateKey))
                            .font(.system(size: uiScaleController.scaledMetric(38), weight: .semibold))
                        Image(systemName: "pencil")
                            .font(.title2)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingDateEditor) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Change Day")
                            .font(.headline)
                        DatePicker("Date", selection: $dateEditorValue, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                        HStack {
                            Button("Cancel") {
                                showingDateEditor = false
                            }
                            Spacer()
                            Button("Save") {
                                let newKey = store.dateKey(for: dateEditorValue)
                                let success = store.updateDayDate(plan, to: newKey)
                                if success {
                                    selectedDateKey = newKey
                                    showingDateEditor = false
                                } else {
                                    dateChangeError = "A day for \(newKey) already exists."
                                    showingDateEditor = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14)
                    .frame(width: 320)
                }

                HStack(spacing: 12) {
                    Text("Day Rating")
                        .font(scaledFont(20, weight: .medium))

                    StarRatingView(rating: Binding(
                        get: { plan.dayRating },
                        set: { newValue in
                            store.updateDayRating(newValue, for: plan)
                        }
                    ), scale: uiScaleController.scale)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Reflection")
                        .font(scaledFont(20, weight: .medium))
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: Binding(
                            get: { plan.reflection ?? "" },
                            set: { newValue in
                                store.updateDayReflection(newValue, for: plan)
                            }
                        ))
                        .font(scaledFont(16))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(
                            minHeight: uiScaleController.scaledMetric(78),
                            maxHeight: uiScaleController.scaledMetric(78)
                        )

                        if (plan.reflection ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(reflectionPrompts[reflectionPlaceholderIndex])
                                .font(scaledFont(16))
                                .foregroundStyle(.secondary)
                                .padding(.leading, uiScaleController.scaledMetric(6))
                                .padding(.top, uiScaleController.scaledMetric(1))
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(uiScaleController.scaledMetric(10))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                }

                let pendingCount = plan.todos.filter { !$0.isDone }.count
                if pendingCount > 0 {
                    HStack(spacing: 8) {
                        Button("Carry Forward") {
                            let nextKey = store.carryPendingTodosToNextDay(
                                from: plan,
                                ignoreWeekends: ignoreCarryForwardWeekends
                            )
                            selectedDateKey = nextKey
                            detailMode = .day
                        }
                        .buttonStyle(ReadableProminentButtonStyle())

                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .help("Moves all pending tasks to the next day. If the next day doesn't exist, it is created automatically. Moved tasks are marked as Carry.")
                    }
                }
            }
        }
    }

    private func todoSection(for plan: DayPlan) -> some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Type a task and press Enter", text: $todoInput)
                    .textFieldStyle(.plain)
                    .font(scaledFont(20))
                    .padding(.horizontal, uiScaleController.scaledMetric(14))
                    .padding(.vertical, uiScaleController.scaledMetric(12))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
                    )
                    .onSubmit {
                        store.addTodo(title: todoInput, to: plan)
                        todoInput = ""
                    }

                let todos = store.sortedTodos(for: plan)
                if !todos.isEmpty {
                    LazyVStack(spacing: 10) {
                        ForEach(todos) { todo in
                                todoRow(
                                    todo: todo,
                                    plan: plan,
                                    showDayActions: true
                                )
                                .padding(10)
                                .onDrop(
                                    of: [UTType.text.identifier],
                                    delegate: TodoReorderDropDelegate(
                                        target: todo,
                                        plan: plan,
                                        store: store,
                                        draggedToken: $draggedTodoToken,
                                        tokenForTodo: todoDragToken(_:)
                                    )
                                )
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    )
                }
            }
        }
    }

    private func todoRow(
        todo: TodoItem,
        plan: DayPlan,
        showDayActions: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                todo.isDone.toggle()
                store.touchTodo(todo)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: uiScaleController.scaledMetric(24), weight: .semibold))
                    .foregroundStyle(todo.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            todoContent(todo: todo)

            Text(todo.source == .rollover ? "Carry" : "New")
                .font(scaledFont(14))
                .foregroundStyle(.secondary)

            if showDayActions {
                Button {
                    requestCarryForward(todo: todo, in: plan)
                } label: {
                    Image(systemName: "arrow.right.circle")
                }
                .buttonStyle(.borderless)
                .help("Carry this task to next day")

                Image(systemName: "circle.grid.2x2.fill")
                    .foregroundStyle(.secondary)
                    .help("Drag to reorder")
                    .onDrag {
                        let token = todoDragToken(todo)
                        draggedTodoToken = token
                        return NSItemProvider(object: NSString(string: token))
                    }
            }

            Button(role: .destructive) {
                requestDeleteTodo(todo: todo, in: plan)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: uiScaleController.scaledMetric(44))
    }

    private func requestCarryForward(todo: TodoItem, in plan: DayPlan) {
        if skipCarryForwardConfirm {
            _ = store.carryTodoToNextDay(
                todo,
                from: plan,
                ignoreWeekends: ignoreCarryForwardWeekends
            )
            return
        }
        carryForwardDontAskAgain = skipCarryForwardConfirm
        pendingCarryTodoID = todo.persistentModelID
        pendingCarryPlanDateKey = plan.dateKey
        showingCarryForwardConfirmation = true
    }

    private func requestDeleteTodo(todo: TodoItem, in plan: DayPlan) {
        pendingDeleteTodoID = todo.persistentModelID
        pendingDeletePlanDateKey = plan.dateKey
        showingDeleteTodoConfirmation = true
    }

    private func executePendingTodoDelete() {
        defer {
            showingDeleteTodoConfirmation = false
            pendingDeleteTodoID = nil
            pendingDeletePlanDateKey = nil
        }

        guard let dayKey = pendingDeletePlanDateKey,
              let todoID = pendingDeleteTodoID,
              let plan = store.fetchDayPlan(for: dayKey),
              let todo = plan.todos.first(where: { $0.persistentModelID == todoID }) else {
            return
        }

        store.deleteTodo(todo, from: plan)
    }

    private func executePendingCarryForward() {
        defer {
            showingCarryForwardConfirmation = false
            pendingCarryTodoID = nil
            pendingCarryPlanDateKey = nil
        }

        guard let dayKey = pendingCarryPlanDateKey,
              let todoID = pendingCarryTodoID,
              let plan = store.fetchDayPlan(for: dayKey),
              let todo = plan.todos.first(where: { $0.persistentModelID == todoID }) else {
            return
        }

        _ = store.carryTodoToNextDay(
            todo,
            from: plan,
            ignoreWeekends: ignoreCarryForwardWeekends
        )
    }

    private func todoDragToken(_ todo: TodoItem) -> String {
        "\(todo.persistentModelID)"
    }

    @ViewBuilder
    private func todoContent(todo: TodoItem) -> some View {
        let parsedLink = TodoTextFormatter.parseFirstURL(from: todo.title)

        if let parsed = parsedLink, !editingLinkedTodos.contains(todo.persistentModelID) {
            HStack(spacing: 0) {
                Button {
                    NSWorkspace.shared.open(parsed.url)
                } label: {
                    Text(formattedTodoText(from: parsed))
                        .font(scaledFont(20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, uiScaleController.scaledMetric(12))
                .padding(.vertical, uiScaleController.scaledMetric(10))

                Button {
                    beginLinkedTodoEdit(todoID: todo.persistentModelID)
                } label: {
                    Text("Edit")
                        .font(scaledFont(14, weight: .semibold))
                }
                .buttonStyle(InlineEditButtonStyle(
                    isHovered: hoveredInlineEditTodoID == todo.persistentModelID
                ))
                .onHover { hovering in
                    hoveredInlineEditTodoID = hovering ? todo.persistentModelID : nil
                }
                .help("Edit linked todo")
                .padding(.trailing, uiScaleController.scaledMetric(10))
            }
            .padding(.vertical, uiScaleController.scaledMetric(4))
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if parsedLink != nil {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: Binding(
                    get: { todo.title },
                    set: { newValue in
                        todo.title = newValue
                        store.touchTodo(todo)
                    }
                ))
                .font(scaledFont(20))
                .frame(minHeight: uiScaleController.scaledMetric(78))
                .padding(uiScaleController.scaledMetric(8))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                )
                .focused($focusedLinkedTodoID, equals: todo.persistentModelID)

                HStack {
                    Spacer()
                    Button("Done") {
                        editingLinkedTodos.remove(todo.persistentModelID)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("Task", text: Binding(
                get: { todo.title },
                set: { newValue in
                    todo.title = newValue
                    store.touchTodo(todo)
                }
            ))
            .textFieldStyle(.plain)
            .font(scaledFont(20))
            .padding(.horizontal, uiScaleController.scaledMetric(12))
            .padding(.vertical, uiScaleController.scaledMetric(10))
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func beginLinkedTodoEdit(todoID: PersistentIdentifier) {
        editingLinkedTodos.insert(todoID)
        DispatchQueue.main.async {
            focusedLinkedTodoID = todoID
        }
    }

    private func updateImageDividerCursor(hovering: Bool) {
        if hovering && !imageDividerHoverCursorActive {
            imageDividerHoverCursorActive = true
            NSCursor.resizeLeftRight.push()
        } else if !hovering && imageDividerHoverCursorActive {
            imageDividerHoverCursorActive = false
            NSCursor.pop()
        }
    }

    private var allTodosView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("All Todos")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                if dayPlans.isEmpty {
                    ContentUnavailableView("No todos yet", systemImage: "checklist")
                } else {
                    ForEach(dayPlans) { plan in
                        allTodosDayCard(for: plan)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func allTodosDayCard(for plan: DayPlan) -> some View {
        let todos = store.sortedTodos(for: plan)
        let total = todos.count
        let done = todos.filter(\.isDone).count

        return sectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDayLabel(for: plan.dateKey))
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("\(done)/\(total) done")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Day") {
                        detailMode = .day
                        selectedDateKey = plan.dateKey
                    }
                    .buttonStyle(.bordered)
                }

                if todos.isEmpty {
                    Text("No todos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(todos) { todo in
                            todoRow(
                                todo: todo,
                                plan: plan,
                                showDayActions: false
                            )
                            .onDrag {
                                let token = todoDragToken(todo)
                                draggedTodoToken = token
                                return NSItemProvider(object: NSString(string: token))
                            }
                        }
                    }
                }
            }
        }
        .onDrop(
            of: [UTType.text.identifier],
            delegate: TodoDayMoveDropDelegate(
                targetPlan: plan,
                dayPlans: dayPlans,
                store: store,
                draggedToken: $draggedTodoToken,
                tokenForTodo: todoDragToken(_:)
            )
        )
    }

    private var calendarGridView: some View {
        let weekdayHeaders = weekdayLabels()
        let gridDates = monthGridDates(for: calendarMonth)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        calendarMonth = monthOffset(from: calendarMonth, by: -1)
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Text(monthTitle(for: calendarMonth))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        calendarMonth = monthOffset(from: calendarMonth, by: 1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120), spacing: 12), count: 7), spacing: 12) {
                    ForEach(weekdayHeaders, id: \.self) { weekday in
                        Text(weekday)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(gridDates.indices, id: \.self) { index in
                        if let date = gridDates[index] {
                            let key = store.dateKey(for: date)
                            let plan = planMap[key]
                            Button {
                                store.ensureDayPlan(for: key)
                                selectedDateKey = key
                                detailMode = .day
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(dayNumber(from: date))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Rating: \(plan?.dayRating.map(String.init) ?? "-")/10")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    let total = plan?.todos.count ?? 0
                                    let done = plan?.todos.filter(\.isDone).count ?? 0
                                    Text("\(done)/\(total) done")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(plan != nil ? Color.accentColor.opacity(0.10) : Color(nsColor: .quaternaryLabelColor).opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if plan != nil {
                                    Button(role: .destructive) {
                                        calendarDeleteDayKey = key
                                    } label: {
                                        Label("Delete Day", systemImage: "trash")
                                    }
                                }
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.clear)
                                .frame(minHeight: 92)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func exportDataJSON() {
        let panel = NSSavePanel()
        panel.title = "Export Planner Data"
        panel.nameFieldStringValue = "focused-day-planner-\(todayKey).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try store.exportSnapshotJSON()
            try data.write(to: url, options: .atomic)
            dataTransferMessage = "Export complete:\n\(url.path)"
        } catch {
            dataTransferMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importDataJSON() {
        let panel = NSOpenPanel()
        panel.title = "Import Planner Data"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let importedDayCount = try store.importSnapshotJSON(data)
            selectedDateKey = store.latestDayKey()
            detailMode = .day
            dataTransferMessage = "Import complete: \(importedDayCount) day(s) loaded."
        } catch {
            dataTransferMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func exportRecentLogs() {
        do {
            let url = try AppLogAccess.exportRecentLogs()
            NSWorkspace.shared.activateFileViewerSelecting([url])
            dataTransferMessage = "Recent app logs exported:\n\(url.path)"
        } catch {
            dataTransferMessage = "Log export failed: \(error.localizedDescription)"
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(themeTintColor)
                    .allowsHitTesting(false)
            )
    }

    private func formattedTodoText(from parsed: ParsedTodoLink) -> String {
        if parsed.isLinear, let issueID = parsed.linearIssueID {
            let parts = [parsed.textBeforeURL, issueID, parsed.linearDescription ?? ""]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return parts.joined(separator: " ")
        }

        let parts = [parsed.textBeforeURL, parsed.url.absoluteString, parsed.textAfterURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    private func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func monthOffset(from date: Date, by months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: monthStart(for: date)) ?? date
    }

    private func monthGridDates(for month: Date) -> [Date?] {
        let start = monthStart(for: month)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: start)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7

        var dates: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: start) {
                dates.append(date)
            }
        }
        while dates.count % 7 != 0 {
            dates.append(nil)
        }
        return dates
    }

    private func weekdayLabels() -> [String] {
        Self.monthTitleFormatter.locale = Locale.current
        let symbols = Self.monthTitleFormatter.shortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func monthTitle(for date: Date) -> String {
        Self.monthTitleFormatter.string(from: date)
    }

    private func dayNumber(from date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func formattedDayLabel(for dateKey: String) -> String {
        guard let date = store.date(from: dateKey) else {
            return dateKey
        }
        return Self.fullDayFormatter.string(from: date)
    }

    private func shortDayLabel(for dateKey: String) -> String {
        guard let date = store.date(from: dateKey) else {
            return dateKey
        }
        return Self.shortDayFormatter.string(from: date)
    }

    private var statsSelectedOffset: Int {
        switch statsTimeframe {
        case .weekly:
            return weeklyRatingsOffset
        case .monthly:
            return monthlyRatingsOffset
        }
    }

    private func adjustStatsOffset(by delta: Int) {
        switch statsTimeframe {
        case .weekly:
            weeklyRatingsOffset += delta
        case .monthly:
            monthlyRatingsOffset += delta
        }
    }

    private func averageDonePerDay(for timeframe: StatsTimeframe, offsetFromCurrent offset: Int) -> Double {
        guard let interval = interval(for: timeframe, offsetFromCurrent: offset) else {
            return 0
        }

        let totalDone = dayPlans.reduce(into: 0) { partialResult, plan in
            guard let date = store.date(from: plan.dateKey), interval.contains(date) else { return }
            partialResult += plan.todos.filter(\.isDone).count
        }
        let dayCount = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
        return Double(totalDone) / Double(dayCount)
    }

    private func interval(for timeframe: StatsTimeframe, offsetFromCurrent offset: Int) -> DateInterval? {
        let component = timeframe.calendarComponent
        guard let currentInterval = calendar.dateInterval(of: component, for: .now),
              let start = calendar.date(byAdding: component, value: offset, to: currentInterval.start) else {
            return nil
        }
        return calendar.dateInterval(of: component, for: start)
    }

    private func averageRating(for timeframe: StatsTimeframe, offsetFromCurrent offset: Int) -> Double? {
        ratingSummary(for: timeframe, offsetFromCurrent: offset)?.averageRating
    }

    private func ratingSummary(for timeframe: StatsTimeframe, offsetFromCurrent offset: Int) -> PeriodRatingSummary? {
        guard let interval = interval(for: timeframe, offsetFromCurrent: offset) else { return nil }
        let ratings = dayPlans.compactMap { plan -> Int? in
            guard let rating = plan.dayRating,
                  let date = store.date(from: plan.dateKey),
                  interval.contains(date) else {
                return nil
            }
            return rating
        }

        let averageRating = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
        return PeriodRatingSummary(
            offset: offset,
            interval: interval,
            averageRating: averageRating,
            ratedDaysCount: ratings.count
        )
    }

    private func earliestRatedOffset(for timeframe: StatsTimeframe) -> Int {
        let component = timeframe.calendarComponent
        guard let currentStart = interval(for: timeframe, offsetFromCurrent: 0)?.start else {
            return 0
        }

        let offsets = dayPlans.compactMap { plan -> Int? in
            guard plan.dayRating != nil,
                  let date = store.date(from: plan.dateKey),
                  let periodStart = calendar.dateInterval(of: component, for: date)?.start else {
                return nil
            }
            switch timeframe {
            case .weekly:
                return calendar.dateComponents([.weekOfYear], from: currentStart, to: periodStart).weekOfYear
            case .monthly:
                return calendar.dateComponents([.month], from: currentStart, to: periodStart).month
            }
        }

        return min(offsets.min() ?? 0, 0)
    }

    private func ratingTrendSummaries(for timeframe: StatsTimeframe, limit: Int) -> [PeriodRatingSummary] {
        guard limit > 0 else { return [] }
        let startOffset = max(earliestRatedOffset(for: timeframe), -(limit - 1))
        return (startOffset...0).compactMap { ratingSummary(for: timeframe, offsetFromCurrent: $0) }
    }

    private func offset(for dateInterval: DateInterval, timeframe: StatsTimeframe) -> Int {
        guard let currentStart = interval(for: timeframe, offsetFromCurrent: 0)?.start else {
            return 0
        }
        switch timeframe {
        case .weekly:
            return calendar.dateComponents([.weekOfYear], from: currentStart, to: dateInterval.start).weekOfYear ?? 0
        case .monthly:
            return calendar.dateComponents([.month], from: currentStart, to: dateInterval.start).month ?? 0
        }
    }

    private func ratingChangeText(current: Double?, previous: Double?) -> String? {
        guard let current, let previous, previous != 0 else { return nil }
        let delta = ((current - previous) / previous) * 100
        return String(format: "%+.0f%%", delta)
    }

    private func intervalRangeLabel(for interval: DateInterval, timeframe: StatsTimeframe) -> String {
        switch timeframe {
        case .weekly:
            return weekRangeLabel(for: interval)
        case .monthly:
            return Self.shortMonthFormatter.string(from: interval.start)
        }
    }

    private func weekRangeLabel(for interval: DateInterval) -> String {
        let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(Self.shortDayFormatter.string(from: interval.start)) - \(Self.shortDayFormatter.string(from: endDate))"
    }

    private func intervalShortLabel(for interval: DateInterval, timeframe: StatsTimeframe) -> String {
        switch timeframe {
        case .weekly:
            return Self.shortDayFormatter.string(from: interval.start)
        case .monthly:
            return Self.shortMonthFormatter.string(from: interval.start)
        }
    }

    private func journalRangeLabel(for interval: DateInterval) -> String {
        if let monthInterval = calendar.dateInterval(of: .month, for: interval.start),
           calendar.isDate(monthInterval.start, inSameDayAs: interval.start),
           calendar.isDate(monthInterval.end.addingTimeInterval(-1), inSameDayAs: interval.end.addingTimeInterval(-1)) {
            return intervalRangeLabel(for: interval, timeframe: .monthly)
        }
        return intervalRangeLabel(for: interval, timeframe: .weekly)
    }

    private func clampWeeklyRatingsOffset() {
        weeklyRatingsOffset = min(max(weeklyRatingsOffset, earliestRatedOffset(for: .weekly)), 0)
    }

    private func clampMonthlyRatingsOffset() {
        monthlyRatingsOffset = min(max(monthlyRatingsOffset, earliestRatedOffset(for: .monthly)), 0)
    }

    private func summaryText(for plan: DayPlan) -> String {
        let total = plan.todos.count
        let done = plan.todos.filter(\.isDone).count
        return "\(done)/\(total) done"
    }
}

private struct PeriodRatingSummary: Identifiable {
    let offset: Int
    let interval: DateInterval
    let averageRating: Double?
    let ratedDaysCount: Int

    var id: Int { offset }
}

private struct StarRatingView: View {
    @Binding var rating: Int?
    let scale: Double

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...10, id: \.self) { value in
                Button {
                    rating = value
                } label: {
                    Image(systemName: (rating ?? 0) >= value ? "star.fill" : "star")
                        .font(.system(size: 20 * scale))
                        .foregroundStyle((rating ?? 0) >= value ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help("Rate \(value)/10")
            }

            Button("Clear") {
                rating = nil
            }
            .buttonStyle(.borderless)
            .font(.system(size: 14 * scale))
        }
    }
}

private struct TodoReorderDropDelegate: DropDelegate {
    let target: TodoItem
    let plan: DayPlan
    let store: PlannerStore
    @Binding var draggedToken: String?
    let tokenForTodo: (TodoItem) -> String

    func dropEntered(info: DropInfo) {
        _ = info
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedToken = nil }
        guard let draggedToken else { return false }

        let todos = store.sortedTodos(for: plan)
        guard let sourceTodo = todos.first(where: { tokenForTodo($0) == draggedToken }),
              let toIndex = todos.firstIndex(where: { $0.persistentModelID == target.persistentModelID }) else {
            return false
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            store.moveTodo(sourceTodo, in: plan, to: toIndex)
        }
        return true
    }
}

private struct InlineEditButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let foreground = isPressed ? Color.accentColor.opacity(0.95) : Color.accentColor
        let backgroundOpacity: CGFloat = isPressed ? 0.45 : (isHovered ? 0.30 : 0.20)
        let borderOpacity: CGFloat = isPressed ? 0.55 : (isHovered ? 0.45 : 0.30)

        return configuration.label
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(backgroundOpacity))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.accentColor.opacity(borderOpacity), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct TodoDayMoveDropDelegate: DropDelegate {
    let targetPlan: DayPlan
    let dayPlans: [DayPlan]
    let store: PlannerStore
    @Binding var draggedToken: String?
    let tokenForTodo: (TodoItem) -> String

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { draggedToken = nil }
        guard let draggedToken else { return false }

        for sourcePlan in dayPlans {
            guard let todo = sourcePlan.todos.first(where: { tokenForTodo($0) == draggedToken }) else {
                continue
            }
            store.moveTodo(todo, from: sourcePlan, to: targetPlan)
            return true
        }

        return false
    }
}
