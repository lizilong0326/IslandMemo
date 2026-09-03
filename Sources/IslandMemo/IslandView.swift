import SwiftUI

private enum MemoSection: String, CaseIterable, Identifiable {
    case tasks = "任务"
    case trash = "回收站"
    var id: Self { self }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case memo = "备忘录"
    case clipboard = "复制记录"
    case home = "首页"
    case links = "链接"
    case recordings = "录制"
    case credentials = "密钥"
    case music = "音乐"
    case pomodoro = "番茄钟"
    case recorder = "快速录音"
    case windows = "当前窗口"
    case mirror = "镜子"
    case note = "随笔记"
    case commands = "常用指令"
    case clock = "时钟"
    case calendar = "日历"
    case completions = "AI 任务"
    case settings = "设置"
    var id: Self { self }

    var systemImage: String {
        switch self {
        case .memo: return "checklist"
        case .clipboard: return "doc.on.clipboard"
        case .home: return "square.grid.2x2"
        case .links: return "link"
        case .recordings: return "waveform"
        case .credentials: return "key"
        case .music: return "music.note"
        case .pomodoro: return "timer"
        case .recorder: return "record.circle"
        case .windows: return "macwindow"
        case .mirror: return "camera"
        case .note: return "pencil.line"
        case .commands: return "command"
        case .clock: return "clock"
        case .calendar: return "calendar"
        case .completions: return "sparkles"
        case .settings: return "gearshape"
        }
    }

    var feature: AppSettingsStore.Feature {
        switch self {
        case .memo: return .memo
        case .clipboard: return .clipboard
        case .home: return .home
        case .links: return .links
        case .recordings: return .recordings
        case .credentials: return .credentials
        case .music: return .music
        case .pomodoro: return .pomodoro
        case .recorder: return .recorder
        case .windows: return .windows
        case .mirror: return .mirror
        case .note: return .note
        case .commands: return .commands
        case .clock: return .clock
        case .calendar: return .calendar
        case .completions: return .completions
        case .settings: return .settings
        }
    }

    init(feature: AppSettingsStore.Feature) {
        switch feature {
        case .memo: self = .memo
        case .clipboard: self = .clipboard
        case .home: self = .home
        case .links: self = .links
        case .recordings: self = .recordings
        case .credentials: self = .credentials
        case .music: self = .music
        case .pomodoro: self = .pomodoro
        case .recorder: self = .recorder
        case .windows: self = .windows
        case .mirror: self = .mirror
        case .note: self = .note
        case .commands: self = .commands
        case .clock: self = .clock
        case .calendar: self = .calendar
        case .completions: self = .completions
        case .settings: self = .settings
        }
    }
}

private enum TaskCompletionFilter: String, CaseIterable, Identifiable {
    case incomplete = "未完成"
    case completed = "已完成"
    var id: Self { self }
}

struct IslandView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var clipboardStore: ClipboardStore
    @ObservedObject var linksStore: LinksStore
    @ObservedObject var commandsStore: CommandsStore
    @ObservedObject var pomodoroStore: PomodoroStore
    @ObservedObject var recordingsStore: RecordingStore
    @ObservedObject var credentialsStore: CredentialsStore
    @ObservedObject var musicService: MusicService
    @ObservedObject var windowListService: WindowListService
    @ObservedObject var notifyServer: AgentNotifyServer
    @ObservedObject var codexStatusStore: CodexStatusStore
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var panelMetrics: PanelMetrics
    let onOpenDisplaySettings: () -> Void
    @State private var title = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(3600)
    @State private var showsNewTaskDateEditor = false
    @State private var newTaskPriority: TaskPriority = .blue
    @State private var showsPriorityPicker = false
    @State private var newTaskCategoryID: String?
    @State private var showsCategoryPicker = false
    @State private var showsEmptyTrashConfirmation = false
    @State private var section: MemoSection = .tasks
    @State private var selectedTab: AppTab = .memo
    @State private var completionFilter: TaskCompletionFilter = .incomplete
    @FocusState private var titleFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            BottomRoundedRectangle(radius: IslandTheme.radiusPanel)
                .fill(IslandTheme.background)
            // 底沿渐变描边，对齐参考项目的标志性边缘光。
            BottomRoundedRectangle(radius: IslandTheme.radiusPanel)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.35),
                            IslandTheme.accentBlue.opacity(0.22),
                            IslandTheme.accentGreen.opacity(0.28),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )

            VStack(spacing: IslandTheme.s3) {
                topbar
                    .frame(height: IslandTheme.topbarHeight)

                switch selectedTab {
                case .memo:
                    if section == .tasks {
                        if appSettings.memoCompletedEnabled { completionTabBar }
                        if completionFilter == .incomplete { addTaskArea }
                    }
                    content
                case .clipboard:
                    ClipboardHistoryView(store: clipboardStore, settings: appSettings)
                case .home:
                    HomeView(
                        tasks: store,
                        clipboard: clipboardStore,
                        links: linksStore,
                        credentials: credentialsStore,
                        pomodoro: pomodoroStore,
                        music: musicService,
                        windows: windowListService,
                        commands: commandsStore,
                        recordings: recordingsStore,
                        notifyServer: notifyServer,
                        codexStatus: codexStatusStore,
                        panelMetrics: panelMetrics,
                        settings: appSettings
                    )
                case .links:
                    LinksView(store: linksStore, settings: appSettings)
                case .recordings:
                    RecordingsView(store: recordingsStore)
                case .credentials:
                    CredentialsView(store: credentialsStore, settings: appSettings)
                case .music: standaloneModule(.music)
                case .pomodoro: standaloneModule(.pomodoro)
                case .recorder: standaloneModule(.recorder)
                case .windows: standaloneModule(.windows)
                case .mirror: standaloneModule(.mirror)
                case .note: standaloneModule(.note)
                case .commands: standaloneModule(.commands)
                case .clock: standaloneModule(.clock)
                case .calendar: standaloneModule(.calendar)
                case .completions: standaloneModule(.completions)
                case .settings:
                    EmptyView()
                }
            }
            .padding(.horizontal, IslandTheme.s6)
            .padding(.top, panelMetrics.topInset)
            .padding(.bottom, IslandTheme.s4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .tint(IslandTheme.accentBlue)
        .onAppear {
            if !visibleTabs.contains(selectedTab), let first = visibleTabs.first {
                selectedTab = first
            }
        }
        .onChange(of: store.focusAddRequest) { _ in
            if appSettings.workspacePlacement(for: .memo) == .tab {
                selectedTab = .memo
                section = .tasks
                completionFilter = .incomplete
                DispatchQueue.main.async { titleFocused = true }
            } else if appSettings.workspacePlacement(for: .memo) == .home {
                selectedTab = .home
            } else if let first = visibleTabs.first {
                selectedTab = first
            }
        }
        .onChange(of: store.resetMemoListRequest) { _ in
            completionFilter = .incomplete
        }
        .onChange(of: appSettings.enabledFeatures) { _ in
            if !visibleTabs.contains(selectedTab), let first = visibleTabs.first { selectedTab = first }
        }
        .onChange(of: appSettings.featureOrder) { _ in
            if !visibleTabs.contains(selectedTab), let first = visibleTabs.first { selectedTab = first }
        }
        .onChange(of: appSettings.memoCompletedEnabled) { enabled in
            if !enabled { completionFilter = .incomplete }
        }
        .onChange(of: appSettings.memoTrashEnabled) { enabled in
            if !enabled { section = .tasks }
        }
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func standaloneModule(_ module: AppSettingsStore.HomeModule) -> some View {
        HomeView(
            tasks: store,
            clipboard: clipboardStore,
            links: linksStore,
            credentials: credentialsStore,
            pomodoro: pomodoroStore,
            music: musicService,
            windows: windowListService,
            commands: commandsStore,
            recordings: recordingsStore,
            notifyServer: notifyServer,
            codexStatus: codexStatusStore,
            panelMetrics: panelMetrics,
            settings: appSettings,
            standaloneModule: module
        )
    }

    // MARK: - 顶栏（对齐参考项目：左侧胶囊 Tabs，中央留刘海安全区，右侧图标按钮）

    private var topbar: some View {
        HStack(spacing: IslandTheme.s3) {
            capsuleTabs
            if selectedTab == .memo {
                memoSectionButtons
            }
            utilityIcon(systemImage: "gearshape", active: false, help: "打开设置") {
                onOpenDisplaySettings()
            }
        }
    }

    private var capsuleTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: IslandTheme.s1) {
                ForEach(visibleTabs) { tab in
                    capsuleTabButton(tab)
                }
            }
            .padding(3)
        }
        .scrollIndicators(.never)
        .background(IslandTheme.surface1, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func capsuleTabButton(_ tab: AppTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { selectedTab = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selectedTab == tab ? IslandTheme.text1 : IslandTheme.text3)
            .background(selectedTab == tab ? IslandTheme.surface2 : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var memoSectionButtons: some View {
        HStack(spacing: 6) {
            utilityIcon(systemImage: "checklist", active: section == .tasks, help: "任务列表") {
                section = .tasks
            }
            if appSettings.memoTrashEnabled {
                utilityIcon(systemImage: "trash", active: section == .trash, help: "回收站") {
                    section = .trash
                }
            }
        }
    }

    private func utilityIcon(systemImage: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(active ? IslandTheme.text1 : IslandTheme.text3)
                .frame(width: 30, height: 30)
                .background(active ? IslandTheme.surface2 : IslandTheme.surface1)
                .clipShape(RoundedRectangle(cornerRadius: IslandTheme.radiusInput))
                .overlay(
                    RoundedRectangle(cornerRadius: IslandTheme.radiusInput)
                        .stroke(IslandTheme.hairlineSoft, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var visibleTabs: [AppTab] {
        appSettings.orderedVisibleFeatures
            .filter { $0 != .settings }
            .map { AppTab(feature: $0) }
    }

    private var completionTabBar: some View {
        HStack(spacing: 28) {
            ForEach(TaskCompletionFilter.allCases) { filter in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { completionFilter = filter }
                } label: {
                    VStack(spacing: 4) {
                        Text(filter.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(completionFilter == filter ? .white : .white.opacity(0.45))
                        Capsule()
                            .fill(completionFilter == filter ? Color.blue : Color.clear)
                            .frame(width: 34, height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: -10)
    }

    private var addTaskArea: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
            TextField("新建任务", text: $title)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit(addTask)
            if appSettings.memoCategoriesEnabled, !appSettings.memoCategories.isEmpty {
                Button { showsCategoryPicker.toggle() } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: selectedNewTaskCategory.colorHex))
                            .frame(width: 9, height: 9)
                        Text(selectedNewTaskCategory.name)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(IslandTheme.text2)
                }
                .buttonStyle(.plain)
                .help("选择任务分类")
                .popover(isPresented: $showsCategoryPicker, arrowEdge: .bottom) {
                    CategoryPickerPopover(
                        selection: Binding(
                            get: { selectedNewTaskCategory.id },
                            set: { newTaskCategoryID = $0 }
                        ),
                        settings: appSettings,
                        onSelect: { showsCategoryPicker = false }
                    )
                }
            }
            if appSettings.memoDueDatesEnabled {
                Button {
                    dueDate = hasDueDate ? dueDate : .now.addingTimeInterval(3600)
                    showsNewTaskDateEditor.toggle()
                } label: {
                    Image(systemName: hasDueDate ? "clock.fill" : "clock")
                        .foregroundStyle(hasDueDate ? Color.blue : Color.white.opacity(0.62))
                }
                .buttonStyle(.borderless)
                .help("设置结束时间")
                .popover(isPresented: $showsNewTaskDateEditor, arrowEdge: .bottom) {
                    DueDatePickerPopover(
                        selection: $dueDate,
                        showsClear: hasDueDate,
                        onClear: {
                            hasDueDate = false
                            showsNewTaskDateEditor = false
                        },
                        onSave: {
                            hasDueDate = true
                            showsNewTaskDateEditor = false
                        }
                    )
                }
            }

            if appSettings.memoPrioritiesEnabled {
                Button {
                    showsPriorityPicker.toggle()
                } label: {
                    Circle().fill(appSettings.priorityColor(for: newTaskPriority)).frame(width: 11, height: 11)
                }
                .buttonStyle(.plain)
                .help("任务等级")
                .popover(isPresented: $showsPriorityPicker, arrowEdge: .bottom) {
                    PriorityPickerPopover(selection: $newTaskPriority, settings: appSettings) {
                        showsPriorityPicker = false
                    }
                }
            }

            Button(action: addTask) {
                Image(systemName: "plus")
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .clipShape(Circle())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("添加任务")
        }
        .padding(12)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder
    private var content: some View {
        let items = section == .tasks ? visibleTasks : store.deletedTasks
        if items.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: section == .tasks ? "checklist" : "trash")
                    .font(.system(size: 30)).foregroundStyle(.white.opacity(0.25))
                Text(section == .tasks
                     ? (completionFilter == .incomplete ? "还没有未完成任务" : "还没有已完成任务")
                     : "回收站是空的")
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            if section == .trash {
                VStack(spacing: 10) {
                    HStack {
                        Text("已删除任务")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.46))
                        Spacer()
                        Button("全部删除", role: .destructive) {
                            showsEmptyTrashConfirmation = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .padding(.horizontal, 4)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(items) { task in
                                TaskRow(task: task, isTrash: true, store: store, settings: appSettings)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .alert("彻底删除全部任务？", isPresented: $showsEmptyTrashConfirmation) {
                    Button("取消", role: .cancel) {}
                    Button("全部删除", role: .destructive) { store.emptyTrash() }
                } message: {
                    Text("该操作无法撤销。")
                }
            } else {
                if appSettings.memoCategoriesEnabled, !appSettings.memoCategories.isEmpty {
                    memoCategoryBoard
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(taskGroups(for: visibleTasks)) { group in
                                taskGroupView(group)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    private func taskGroups(for tasks: [TaskItem]) -> [TaskGroup] {
        if !appSettings.memoDueDatesEnabled {
            return tasks.isEmpty ? [] : [TaskGroup(title: "任务", tasks: tasks)]
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) ?? tomorrow

        let definitions: [(String, (TaskItem) -> Bool)] = [
            ("已逾期", { task in task.dueDate.map { $0 < today } ?? false }),
            ("今天", { task in task.dueDate.map { calendar.isDate($0, inSameDayAs: today) } ?? false }),
            ("明天", { task in task.dueDate.map { calendar.isDate($0, inSameDayAs: tomorrow) } ?? false }),
            ("未来", { task in task.dueDate.map { $0 >= dayAfterTomorrow } ?? false }),
            ("未设置时间", { $0.dueDate == nil })
        ]

        return definitions.compactMap { title, matches in
            let matching = tasks.filter(matches)
            return matching.isEmpty ? nil : TaskGroup(title: title, tasks: matching)
        }
    }

    private func taskGroupView(_ group: TaskGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(group.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.leading, 4)
            ForEach(group.tasks) { task in
                TaskRow(task: task, isTrash: false, store: store, settings: appSettings)
            }
        }
    }

    private var memoCategoryBoard: some View {
        GeometryReader { geometry in
            let categories = appSettings.memoCategories
            let placements = MemoCategoryLayoutEngine.resolve(categories: categories)
            let gap: CGFloat = 8
            let cellWidth = (geometry.size.width - gap * 11) / 12
            let cellHeight = (geometry.size.height - gap * 3) / 4

            ZStack(alignment: .topLeading) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    if placements.indices.contains(index) {
                        let placement = placements[index]
                        let width = cellWidth * CGFloat(placement.span.columns) + gap * CGFloat(placement.span.columns - 1)
                        let height = cellHeight * CGFloat(placement.span.rows) + gap * CGFloat(placement.span.rows - 1)
                        memoCategoryCard(category)
                            .frame(width: width, height: height)
                            .offset(
                                x: CGFloat(placement.column) * (cellWidth + gap),
                                y: CGFloat(placement.row) * (cellHeight + gap)
                            )
                    }
                }
            }
        }
    }

    private func memoCategoryCard(_ category: MemoCategory) -> some View {
        let firstID = appSettings.memoCategories.first?.id
        let categoryTasks = visibleTasks.filter { ($0.categoryID ?? firstID) == category.id }
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(category.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IslandTheme.text1)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(categoryTasks.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(IslandTheme.text4)
            }
            if categoryTasks.isEmpty {
                Text("暂无任务")
                    .font(.caption2)
                    .foregroundStyle(IslandTheme.text4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(taskGroups(for: categoryTasks)) { group in
                            taskGroupView(group)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(10)
        .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(hex: category.colorHex).opacity(0.2), lineWidth: 1)
        )
    }

    private var visibleTasks: [TaskItem] {
        store.activeTasks.filter { task in
            completionFilter == .completed ? task.isCompleted : !task.isCompleted
        }
    }

    private func addTask() {
        store.add(
            title: title,
            dueDate: appSettings.memoDueDatesEnabled && hasDueDate ? dueDate : nil,
            priority: appSettings.memoPrioritiesEnabled ? newTaskPriority : .blue,
            categoryID: appSettings.memoCategoriesEnabled ? selectedNewTaskCategory.id : nil
        )
        title = ""
        hasDueDate = false
        dueDate = .now.addingTimeInterval(3600)
        newTaskPriority = .blue
        titleFocused = true
    }

    private var selectedNewTaskCategory: MemoCategory {
        appSettings.memoCategories.first(where: { $0.id == newTaskCategoryID })
            ?? appSettings.memoCategories.first
            ?? MemoCategory(name: "未分类", colorHex: "#0A84FF")
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let isTrash: Bool
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettingsStore
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var showsDateEditor = false
    @State private var showsPriorityEditor = false
    @State private var showsCategoryEditor = false
    @State private var showsPermanentDeleteConfirmation = false
    @State private var draftDate = Date().addingTimeInterval(3600)
    @State private var isSubtaskListExpanded = false
    @State private var newSubtaskTitle = ""
    @FocusState private var editFocused: Bool
    @FocusState private var subtaskFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
            if !isTrash {
                Button { store.toggle(task) } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? .green : .white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 3) {
                if isEditing && !isTrash {
                    TextField("任务名称", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .focused($editFocused)
                        .onSubmit(saveTitle)
                        .onExitCommand(perform: cancelEditing)
                } else {
                    Text(task.title)
                        .strikethrough(task.isCompleted && !isTrash)
                        .foregroundStyle(task.isCompleted || isTrash ? .white.opacity(0.42) : .white)
                        .lineLimit(2)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2, perform: beginEditing)
                }
                if settings.memoDueDatesEnabled, let due = task.dueDate {
                    Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(due < .now && !task.isCompleted ? .red : .white.opacity(0.45))
                }
                if settings.memoSubtasksEnabled,
                   !isTrash, let subtasks = task.subtasks, !subtasks.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { isSubtaskListExpanded.toggle() }
                    } label: {
                        Label(
                            "\(subtasks.filter(\.isCompleted).count)/\(subtasks.count)",
                            systemImage: "list.bullet"
                        )
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 8)

            if isTrash {
                Button { store.restore(task) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).help("恢复任务")
                Button(role: .destructive) {
                    showsPermanentDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("彻底删除")
            } else if isHovered || showsDateEditor || showsPriorityEditor || showsCategoryEditor {
                if settings.memoSubtasksEnabled {
                Button {
                    let willExpand = !isSubtaskListExpanded
                    withAnimation(.easeInOut(duration: 0.16)) { isSubtaskListExpanded = willExpand }
                    if willExpand { DispatchQueue.main.async { subtaskFocused = true } }
                } label: {
                    Image(systemName: isSubtaskListExpanded ? "chevron.up" : "list.bullet.indent")
                }
                .buttonStyle(.borderless)
                .help(isSubtaskListExpanded ? "收起子任务" : "添加或管理子任务")
                }

                if settings.memoCategoriesEnabled, settings.memoCategories.count > 1 {
                Button { showsCategoryEditor.toggle() } label: {
                    Circle()
                        .fill(Color(hex: currentCategory.colorHex))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("修改任务分类")
                .popover(isPresented: $showsCategoryEditor, arrowEdge: .trailing) {
                    CategoryPickerPopover(
                        selection: Binding(
                            get: { currentCategory.id },
                            set: { store.updateCategory(task, categoryID: $0) }
                        ),
                        settings: settings,
                        onSelect: { showsCategoryEditor = false }
                    )
                }
                }

                if settings.memoPrioritiesEnabled {
                Button {
                    showsPriorityEditor.toggle()
                } label: {
                    Circle()
                        .fill(settings.priorityColor(for: task.priority ?? .blue))
                        .frame(width: 10, height: 10)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("修改任务等级")
                .popover(isPresented: $showsPriorityEditor, arrowEdge: .trailing) {
                    PriorityPickerPopover(
                        selection: Binding(
                            get: { task.priority ?? .blue },
                            set: { store.updatePriority(task, priority: $0) }
                        ),
                        settings: settings,
                        onSelect: { showsPriorityEditor = false }
                    )
                }
                }

                if settings.memoDueDatesEnabled {
                Button {
                    draftDate = task.dueDate ?? .now.addingTimeInterval(3600)
                    showsDateEditor.toggle()
                } label: {
                    Image(systemName: task.dueDate == nil ? "clock" : "clock.fill")
                }
                .buttonStyle(.borderless)
                .help("修改结束时间")
                .popover(isPresented: $showsDateEditor, arrowEdge: .trailing) { dateEditor }
                }

                Button(role: .destructive) { store.delete(task) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("移到回收站")
            } else {
                if settings.memoPrioritiesEnabled {
                HStack(spacing: 6) {
                    Circle()
                        .fill(settings.priorityColor(for: task.priority ?? .blue))
                        .frame(width: 8, height: 8)
                    Text(settings.priorityName(for: task.priority ?? .blue))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                }
            }
            }

            if settings.memoSubtasksEnabled && isSubtaskListExpanded && !isTrash {
                subtaskList
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(isHovered ? 0.13 : 0.07)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .alert("彻底删除这个任务？", isPresented: $showsPermanentDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("彻底删除", role: .destructive) { store.permanentlyDelete(task) }
        } message: {
            Text("该操作无法撤销。")
        }
    }

    private var currentCategory: MemoCategory {
        settings.memoCategories.first(where: { $0.id == task.categoryID })
            ?? settings.memoCategories.first
            ?? MemoCategory(name: "未分类", colorHex: "#0A84FF")
    }

    private var subtaskList: some View {
        VStack(spacing: 8) {
            Divider().overlay(.white.opacity(0.08))

            ForEach(task.subtasks ?? []) { subtask in
                SubtaskRow(task: task, subtask: subtask, store: store, settings: settings)
                    .padding(.leading, 28)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(.blue)
                TextField("添加子任务", text: $newSubtaskTitle)
                    .textFieldStyle(.plain)
                    .focused($subtaskFocused)
                    .onSubmit(addSubtask)
                Button(action: addSubtask) {
                    Image(systemName: "arrow.up.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.leading, 28)
            .padding(.vertical, 5)
        }
    }

    private func addSubtask() {
        store.addSubtask(to: task, title: newSubtaskTitle)
        newSubtaskTitle = ""
        subtaskFocused = true
    }

    private var dateEditor: some View {
        DueDatePickerPopover(
            selection: $draftDate,
            showsClear: task.dueDate != nil,
            onClear: {
                    store.updateDueDate(task, dueDate: nil)
                    showsDateEditor = false
            },
            onSave: {
                    store.updateDueDate(task, dueDate: draftDate)
                    showsDateEditor = false
            }
        )
    }

    private func beginEditing() {
        guard !isTrash else { return }
        editedTitle = task.title
        isEditing = true
        editFocused = true
    }

    private func saveTitle() {
        store.updateTitle(task, title: editedTitle)
        isEditing = false
    }

    private func cancelEditing() {
        editedTitle = task.title
        isEditing = false
    }
}

private struct SubtaskRow: View {
    let task: TaskItem
    let subtask: SubtaskItem
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettingsStore

    @State private var isHovered = false
    @State private var showsDateEditor = false
    @State private var showsPriorityEditor = false
    @State private var draftDate = Date().addingTimeInterval(3600)

    var body: some View {
        HStack(spacing: 9) {
            Button { store.toggleSubtask(in: task, subtask: subtask) } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isCompleted ? .green : .white.opacity(0.45))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(subtask.title)
                    .font(.callout)
                    .strikethrough(subtask.isCompleted)
                    .foregroundStyle(subtask.isCompleted ? .white.opacity(0.4) : .white.opacity(0.86))
                if settings.memoDueDatesEnabled, let dueDate = subtask.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(dueDate < .now && !subtask.isCompleted ? .red : .white.opacity(0.42))
                }
            }
            Spacer()

            if isHovered || showsDateEditor || showsPriorityEditor {
                if settings.memoPrioritiesEnabled {
                Button { showsPriorityEditor.toggle() } label: {
                    Circle()
                        .fill(settings.priorityColor(for: subtask.priority ?? .blue))
                        .frame(width: 9, height: 9)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("修改子任务等级")
                .popover(isPresented: $showsPriorityEditor, arrowEdge: .trailing) {
                    PriorityPickerPopover(
                        selection: Binding(
                            get: { subtask.priority ?? .blue },
                            set: { store.updateSubtaskPriority(in: task, subtask: subtask, priority: $0) }
                        ),
                        settings: settings,
                        onSelect: { showsPriorityEditor = false }
                    )
                }
                }

                if settings.memoDueDatesEnabled {
                Button {
                    draftDate = subtask.dueDate ?? .now.addingTimeInterval(3600)
                    showsDateEditor.toggle()
                } label: {
                    Image(systemName: subtask.dueDate == nil ? "clock" : "clock.fill")
                }
                .buttonStyle(.borderless)
                .help("修改子任务结束时间")
                .popover(isPresented: $showsDateEditor, arrowEdge: .trailing) {
                    DueDatePickerPopover(
                        selection: $draftDate,
                        showsClear: subtask.dueDate != nil,
                        onClear: {
                            store.updateSubtaskDueDate(in: task, subtask: subtask, dueDate: nil)
                            showsDateEditor = false
                        },
                        onSave: {
                            store.updateSubtaskDueDate(in: task, subtask: subtask, dueDate: draftDate)
                            showsDateEditor = false
                        }
                    )
                }
                }

                Button(role: .destructive) {
                    store.deleteSubtask(from: task, subtask: subtask)
                } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("删除子任务")
            } else {
                if settings.memoPrioritiesEnabled {
                HStack(spacing: 5) {
                    Circle().fill(settings.priorityColor(for: subtask.priority ?? .blue)).frame(width: 7, height: 7)
                    Text(settings.priorityName(for: subtask.priority ?? .blue))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

private struct TaskGroup: Identifiable {
    let title: String
    let tasks: [TaskItem]
    var id: String { title }
}

private struct PriorityPickerPopover: View {
    @Binding var selection: TaskPriority
    @ObservedObject var settings: AppSettingsStore
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button {
                    selection = priority
                    onSelect()
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(settings.priorityColor(for: priority)).frame(width: 11, height: 11)
                        Text(settings.priorityName(for: priority))
                        Spacer()
                        if selection == priority {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 150)
    }
}

private struct CategoryPickerPopover: View {
    @Binding var selection: String
    @ObservedObject var settings: AppSettingsStore
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(settings.memoCategories) { category in
                Button {
                    selection = category.id
                    onSelect()
                } label: {
                    HStack(spacing: 9) {
                        Circle().fill(Color(hex: category.colorHex)).frame(width: 10, height: 10)
                        Text(category.name).lineLimit(1)
                        Spacer()
                        if selection == category.id {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 180)
    }
}

private struct DueDatePickerPopover: View {
    @Binding var selection: Date
    let showsClear: Bool
    let onClear: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("结束时间").font(.headline)

            HStack(spacing: 8) {
                presetButton("今天 18:00", date: todayAt(hour: 18))
                presetButton("明天 09:00", date: tomorrowAt(hour: 9))
                presetButton("一周后", date: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
            }

            WideCalendarPicker(selection: $selection)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Text("时间").foregroundStyle(.secondary)
                Picker("小时", selection: hourBinding) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 72)
                Text(":").foregroundStyle(.secondary)
                Picker("分钟", selection: minuteBinding) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 72)
                Spacer()
            }

            HStack {
                if showsClear {
                    Button("清除时间", role: .destructive, action: onClear)
                }
                Spacer()
                Button("保存", action: onSave).buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 410)
    }

    private func presetButton(_ title: String, date: Date) -> some View {
        Button(title) { selection = date }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: selection) },
            set: { hour in
                selection = Calendar.current.date(bySettingHour: hour, minute: minuteBinding.wrappedValue, second: 0, of: selection) ?? selection
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: selection) },
            set: { minute in
                selection = Calendar.current.date(bySettingHour: hourBinding.wrappedValue, minute: minute, second: 0, of: selection) ?? selection
            }
        )
    }

    private func todayAt(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
    }

    private func tomorrowAt(hour: Int) -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

private struct WideCalendarPicker: View {
    @Binding var selection: Date
    @State private var displayedMonth: Date
    private let calendar = Calendar.current
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    init(selection: Binding<Date>) {
        _selection = selection
        let components = Calendar.current.dateComponents([.year, .month], from: selection.wrappedValue)
        _displayedMonth = State(initialValue: Calendar.current.date(from: components) ?? .now)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(monthTitle).font(.headline)
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Button { displayedMonth = startOfMonth(.now) } label: { Circle().frame(width: 7, height: 7) }
                    .buttonStyle(.borderless).help("回到今天")
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0..<cellCount, id: \.self) { index in
                    if let date = dateForCell(index) {
                        Button { select(date) } label: {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .foregroundStyle(calendar.isDate(date, inSameDayAs: selection) ? .white : .primary)
                                .background {
                                    if calendar.isDate(date, inSameDayAs: selection) {
                                        RoundedRectangle(cornerRadius: 7).fill(.blue)
                                    } else if calendar.isDateInToday(date) {
                                        RoundedRectangle(cornerRadius: 7).stroke(.blue.opacity(0.8), lineWidth: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: selection) { newValue in
            displayedMonth = startOfMonth(newValue)
        }
    }

    private var monthTitle: String {
        let values = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(values.year ?? 0)年 \(values.month ?? 0)月"
    }

    private var leadingEmptyDays: Int {
        max(0, calendar.component(.weekday, from: displayedMonth) - 1)
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    }

    private var cellCount: Int {
        Int(ceil(Double(leadingEmptyDays + daysInMonth) / 7.0)) * 7
    }

    private func dateForCell(_ index: Int) -> Date? {
        let day = index - leadingEmptyDays + 1
        guard day >= 1, day <= daysInMonth else { return nil }
        return calendar.date(byAdding: .day, value: day - 1, to: displayedMonth)
    }

    private func select(_ date: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: selection)
        selection = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
    }

    private func moveMonth(_ offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

private struct BottomRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
