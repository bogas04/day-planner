import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum DetailMode {
    case day
    case todos
    case calendar
    case stats
    case settings
}

struct PlannerRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayPlan.dateKey, order: .reverse) private var dayPlans: [DayPlan]
    @AppStorage(AppSettings.notificationsEnabledKey) private var notificationsEnabled = true
    @AppStorage(AppSettings.skipCarryForwardConfirmKey) private var skipCarryForwardConfirm = false
    @AppStorage(AppSettings.themeTintRedKey) private var themeTintRed = 0.86
    @AppStorage(AppSettings.themeTintGreenKey) private var themeTintGreen = 0.76
    @AppStorage(AppSettings.themeTintBlueKey) private var themeTintBlue = 0.60
    @AppStorage(AppSettings.themeTintOpacityKey) private var themeTintOpacity = 0.10

    @State private var selectedDateKey: String?
    @State private var detailMode: DetailMode = .day
    @State private var todoInput = ""
    @State private var editingLinkedTodos: Set<PersistentIdentifier> = []

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
    @State private var draggedTodoToken: String?
    @State private var decorativeImageCycleOffset = 0
    @State private var decorativeImageBloomColor = Color.accentColor.opacity(0.35)
    @State private var imagePanelFraction: CGFloat = 0.33
    @State private var imagePanelDragStartFraction: CGFloat?
    @State private var reflectionPlaceholderIndex = 0
    @State private var hoveredInlineEditTodoID: PersistentIdentifier?
    @State private var imageDividerHoverCursorActive = false
    @FocusState private var focusedLinkedTodoID: PersistentIdentifier?

    @State private var calendarMonth: Date = Date()

    private let historyLimit = 10
    private let calendar = Calendar.current
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
        PlannerStore(context: modelContext)
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

    private var decorativeImage: NSImage? {
        guard let imageURL = currentDecorativeImageURL,
              let image = NSImage(contentsOf: imageURL) else {
            return nil
        }
        return image
    }

    private var currentDecorativeImageURL: URL? {
        let candidates = decorativeImageCandidateURLs()
        guard !candidates.isEmpty else { return nil }

        let selectedKey = selectedDateKey ?? todayKey
        let dayOfMonth = store.date(from: selectedKey).map { calendar.component(.day, from: $0) } ?? 1
        let baseIndex = max(0, dayOfMonth - 1) % candidates.count
        let resolvedIndex = (baseIndex + decorativeImageCycleOffset) % candidates.count
        return candidates[resolvedIndex]
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle(currentTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selectedDateKey = store.createNextDay(after: selectedDateKey)
                    detailMode = .day
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create next day")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showingDeleteDayConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(detailMode != .day || selectedPlan == nil)
                .help("Delete selected day")
            }
        }
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
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 420)
        }
        .onAppear {
            calendarMonth = monthStart(for: .now)
            reflectionPlaceholderIndex = (reflectionPlaceholderIndex + 1) % reflectionPrompts.count
            if selectedDateKey == nil {
                if dayPlans.contains(where: { $0.dateKey == todayKey }) {
                    selectedDateKey = todayKey
                } else {
                    selectedDateKey = dayPlans.first?.dateKey
                }
            }
            if let key = selectedDateKey {
                if let date = store.date(from: key) {
                    calendarMonth = monthStart(for: date)
                }
            }
            refreshDecorativeImageBloomColor()
            store.refreshTodayNotifications()
        }
        .onChange(of: selectedDateKey) { _, _ in
            decorativeImageCycleOffset = 0
            reflectionPlaceholderIndex = (reflectionPlaceholderIndex + 1) % reflectionPrompts.count
            refreshDecorativeImageBloomColor()
        }
        .onChange(of: decorativeImageCycleOffset) { _, _ in
            refreshDecorativeImageBloomColor()
        }
    }

    private func decorativeImageCandidateURLs() -> [URL] {
        let fileManager = FileManager.default

        var candidates: [URL] = []
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

    private func refreshDecorativeImageBloomColor() {
        guard let image = decorativeImage, let dominant = dominantColor(for: image) else {
            decorativeImageBloomColor = Color.accentColor.opacity(0.35)
            return
        }

        decorativeImageBloomColor = Color(
            red: dominant.red,
            green: dominant.green,
            blue: dominant.blue,
            opacity: 0.45
        )
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
                    Section("Planner") {
                        Button {
                            detailMode = .day
                            selectedDateKey = todayKey
                            store.ensureDayPlan(for: todayKey)
                        } label: {
                            Label("Today", systemImage: "calendar")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                    Button {
                        detailMode = .todos
                    } label: {
                        Label("All Todos", systemImage: "checklist")
                            .font(.title3)
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
                            Label("Calendar", systemImage: "calendar.day.timeline.leading")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        Button {
                            detailMode = .stats
                        } label: {
                            Label("Stats", systemImage: "chart.bar")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        Button {
                            detailMode = .settings
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }

                    Section("History") {
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
                    }
                }
                .listStyle(.sidebar)

                if let decorativeImage {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: separatorHeight)
                        .overlay(alignment: .center) {
                            Divider()
                                .overlay(Color.primary.opacity(0.22))
                        }
                        .overlay(alignment: .center) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(width: 44, height: 4)
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
                        let count = decorativeImageCandidateURLs().count
                        guard count > 1 else { return }
                        decorativeImageCycleOffset = (decorativeImageCycleOffset + 1) % count
                    } label: {
                        ZStack {
                            Circle()
                                .fill(decorativeImageBloomColor)
                                .frame(width: 176, height: 176)
                                .blur(radius: 28)
                                .opacity(0.22)
                                .offset(y: 10)
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
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func historyRow(for plan: DayPlan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(shortDayLabel(for: plan.dateKey))
                    .font(.headline)
                Text(summaryText(for: plan))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(plan.dayRating.map { "\($0)/10" } ?? "-")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
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
        case .settings:
            settingsView
        }
    }

    private var settingsView: some View {
        ScrollView {
            sectionCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Toggle(isOn: Binding(
                        get: { notificationsEnabled },
                        set: { newValue in
                            notificationsEnabled = newValue
                            if newValue {
                                store.refreshTodayNotifications()
                            } else {
                                DailyReminderScheduler.shared.clearPendingNotifications()
                            }
                        }
                    )) {
                        Text("Enable Notifications")
                            .font(.title3)
                    }
                    .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Theme Tint")
                            .font(.title3)
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

                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(themeTintColor)
                                .frame(width: 42, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                                )
                            Text("Subtle tint for translucent cards")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Open Storage Directory") {
                        if let directory = PersistenceController.storeDirectoryURL() {
                            NSWorkspace.shared.open(directory)
                        }
                    }
                    .buttonStyle(.bordered)

                    HStack(spacing: 10) {
                        Button("Export Data (JSON)") {
                            exportDataJSON()
                        }
                        .buttonStyle(.bordered)

                        Button("Import Data (JSON)") {
                            importDataJSON()
                        }
                        .buttonStyle(.bordered)
                        .help("Import replaces all current days, todos, and links.")
                    }

                    Divider()

                    Button("Delete All Data", role: .destructive) {
                        showingDeleteAllDataConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
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

    private var statsView: some View {
        let ratedValues = dayPlans.compactMap(\.dayRating)
        let overallRating: Double? = ratedValues.isEmpty
            ? nil
            : Double(ratedValues.reduce(0) { $0 + $1 }) / Double(ratedValues.count)
        let thisWeekDonePerDay = averageDonePerDay(weekOffsetFromCurrent: 0)
        let previousWeekDonePerDay = averageDonePerDay(weekOffsetFromCurrent: -1)

        return ScrollView {
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

                    HStack {
                        Text("Todos Done/Day (This Week)")
                            .font(.title3)
                        Spacer()
                        Text(String(format: "%.1f", thisWeekDonePerDay))
                            .font(.title3.weight(.semibold))
                    }

                    HStack {
                        Text("Todos Done/Day (Previous Week)")
                            .font(.title3)
                        Spacer()
                        Text(String(format: "%.1f", previousWeekDonePerDay))
                            .font(.title3.weight(.semibold))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
                            .font(.system(size: 38, weight: .semibold))
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
                        .font(.title3)
                        .fontWeight(.medium)

                    StarRatingView(rating: Binding(
                        get: { plan.dayRating },
                        set: { newValue in
                            store.updateDayRating(newValue, for: plan)
                        }
                    ))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Reflection")
                        .font(.title3)
                        .fontWeight(.medium)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: Binding(
                            get: { plan.reflection ?? "" },
                            set: { newValue in
                                store.updateDayReflection(newValue, for: plan)
                            }
                        ))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 78, maxHeight: 78)

                        if (plan.reflection ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(reflectionPrompts[reflectionPlaceholderIndex])
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 6)
                                .padding(.top, 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                }

                let pendingCount = plan.todos.filter { !$0.isDone }.count
                if pendingCount > 0 {
                    HStack(spacing: 8) {
                        Button("Carry Forward") {
                            let nextKey = store.carryPendingTodosToNextDay(from: plan)
                            selectedDateKey = nextKey
                            detailMode = .day
                        }
                        .buttonStyle(.borderedProminent)

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
                    .font(.title3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
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
                                        tokenForTodo: todoDragToken(_:),
                                        onMove: { source, target, dayPlan in
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                store.moveTodo(source, in: dayPlan, to: target)
                                            }
                                        }
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
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(todo.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            todoContent(todo: todo)

            Text(todo.source == .rollover ? "Carry" : "New")
                .font(.subheadline)
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
        .frame(minHeight: 44)
    }

    private func requestCarryForward(todo: TodoItem, in plan: DayPlan) {
        if skipCarryForwardConfirm {
            _ = store.carryTodoToNextDay(todo, from: plan)
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

        _ = store.carryTodoToNextDay(todo, from: plan)
    }

    private func todoDragToken(_ todo: TodoItem) -> String {
        "\(todo.persistentModelID)"
    }

    @ViewBuilder
    private func todoContent(todo: TodoItem) -> some View {
        if let parsed = TodoTextFormatter.parseFirstURL(from: todo.title), !editingLinkedTodos.contains(todo.persistentModelID) {
            HStack(spacing: 0) {
                Button {
                    NSWorkspace.shared.open(parsed.url)
                } label: {
                    Text(formattedTodoText(from: parsed))
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Button {
                    beginLinkedTodoEdit(todoID: todo.persistentModelID)
                } label: {
                    Text("Edit")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(InlineEditButtonStyle(
                    isHovered: hoveredInlineEditTodoID == todo.persistentModelID
                ))
                .onHover { hovering in
                    hoveredInlineEditTodoID = hovering ? todo.persistentModelID : nil
                }
                .help("Edit linked todo")
                .padding(.trailing, 10)
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if TodoTextFormatter.parseFirstURL(from: todo.title) != nil {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: Binding(
                    get: { todo.title },
                    set: { newValue in
                        todo.title = newValue
                        store.touchTodo(todo)
                    }
                ))
                .font(.title3)
                .frame(minHeight: 78)
                .padding(8)
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
            .font(.title3)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
        ScrollView {
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
                    ForEach(weekdayLabels(), id: \.self) { weekday in
                        Text(weekday)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(monthGridDates(for: calendarMonth).indices, id: \.self) { index in
                        if let date = monthGridDates(for: calendarMonth)[index] {
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
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    private func dayNumber(from date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func formattedDayLabel(for dateKey: String) -> String {
        guard let date = store.date(from: dateKey) else {
            return dateKey
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func shortDayLabel(for dateKey: String) -> String {
        guard let date = store.date(from: dateKey) else {
            return dateKey
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func averageDonePerDay(weekOffsetFromCurrent offset: Int) -> Double {
        guard let thisWeekInterval = calendar.dateInterval(of: .weekOfYear, for: .now),
              let start = calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeekInterval.start),
              let end = calendar.date(byAdding: .day, value: 7, to: start) else {
            return 0
        }

        let totalDone = dayPlans.reduce(into: 0) { partialResult, plan in
            guard let date = store.date(from: plan.dateKey), date >= start, date < end else { return }
            partialResult += plan.todos.filter(\.isDone).count
        }
        return Double(totalDone) / 7.0
    }

    private func summaryText(for plan: DayPlan) -> String {
        let total = plan.todos.count
        let done = plan.todos.filter(\.isDone).count
        return "\(done)/\(total) done"
    }
}

private struct StarRatingView: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...10, id: \.self) { value in
                Button {
                    rating = value
                } label: {
                    Image(systemName: (rating ?? 0) >= value ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle((rating ?? 0) >= value ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help("Rate \(value)/10")
            }

            Button("Clear") {
                rating = nil
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
    }
}

private struct TodoReorderDropDelegate: DropDelegate {
    let target: TodoItem
    let plan: DayPlan
    let store: PlannerStore
    @Binding var draggedToken: String?
    let tokenForTodo: (TodoItem) -> String
    let onMove: (TodoItem, Int, DayPlan) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedToken else { return }

        let todos = store.sortedTodos(for: plan)
        guard let sourceTodo = todos.first(where: { tokenForTodo($0) == draggedToken }),
              let fromIndex = todos.firstIndex(where: { $0.persistentModelID == sourceTodo.persistentModelID }),
              let toIndex = todos.firstIndex(where: { $0.persistentModelID == target.persistentModelID }),
              fromIndex != toIndex else {
            return
        }

        onMove(sourceTodo, toIndex, plan)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedToken = nil
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
