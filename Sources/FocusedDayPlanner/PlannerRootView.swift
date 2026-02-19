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
    @State private var showingCarryForwardConfirmation = false
    @State private var carryForwardDontAskAgain = false
    @State private var pendingCarryTodoID: PersistentIdentifier?
    @State private var pendingCarryPlanDateKey: String?
    @State private var draggedTodoToken: String?
    @State private var reflectionPlaceholderIndex = 0

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
            return "Todos"
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

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .padding(28)
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
            store.refreshTodayNotifications()
        }
        .onChange(of: selectedDateKey) { _, _ in
            reflectionPlaceholderIndex = (reflectionPlaceholderIndex + 1) % reflectionPrompts.count
        }
    }

    private var sidebar: some View {
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
                    Label("Todos", systemImage: "checklist")
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
                }
            }
        }
        .listStyle(.sidebar)
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

                    Button("Open Storage Directory") {
                        if let directory = PersistenceController.storeDirectoryURL() {
                            NSWorkspace.shared.open(directory)
                        }
                    }
                    .buttonStyle(.bordered)

                    Divider()

                    Button("Delete All Data", role: .destructive) {
                        showingDeleteAllDataConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
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
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
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

            Picker("", selection: Binding(
                get: { todo.priority },
                set: { newValue in
                    todo.priority = newValue
                    store.touchTodo(todo)
                }
            )) {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 230)

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
                store.deleteTodo(todo, from: plan)
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
            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(parsed.url)
                } label: {
                    Text(formattedTodoText(from: parsed))
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.8))
                )

                Button {
                    editingLinkedTodos.insert(todo.persistentModelID)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit linked todo")
            }
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

    private var allTodosView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Todos")
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
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
