import SwiftUI

private enum MemoSection: String, CaseIterable, Identifiable {
    case tasks = "任务"
    case trash = "回收站"
    var id: Self { self }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case memo = "备忘录"
    case clipboard = "复制记录"
    var id: Self { self }
}

private enum TaskCompletionFilter: String, CaseIterable, Identifiable {
    case incomplete = "未完成"
    case completed = "已完成"
    var id: Self { self }
}

struct IslandView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var clipboardStore: ClipboardStore
    @State private var title = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(3600)
    @State private var showsNewTaskDateEditor = false
    @State private var newTaskPriority: TaskPriority = .blue
    @State private var showsPriorityPicker = false
    @State private var showsEmptyTrashConfirmation = false
    @State private var section: MemoSection = .tasks
    @State private var selectedTab: AppTab = .memo
    @State private var completionFilter: TaskCompletionFilter = .incomplete
    @FocusState private var titleFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            BottomRoundedRectangle(radius: 28)
                .fill(Color.black.opacity(0.92))

            VStack(spacing: 16) {
                if selectedTab == .memo {
                    if section == .tasks {
                        completionTabBar
                        if completionFilter == .incomplete { addTaskArea }
                    }
                    content
                } else {
                    ClipboardHistoryView(store: clipboardStore)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 70)
            .padding(.top, 74)
            .frame(maxHeight: .infinity, alignment: .top)

            header
                .padding(.horizontal, 20)
                .padding(.top, 12)

            VStack {
                Spacer()
                bottomTabBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 444, height: 524)
        .preferredColorScheme(.dark)
        .onChange(of: store.focusAddRequest) { _ in
            selectedTab = .memo
            section = .tasks
            completionFilter = .incomplete
            DispatchQueue.main.async { titleFocused = true }
        }
        .onChange(of: store.resetMemoListRequest) { _ in
            completionFilter = .incomplete
        }
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(selectedTab.rawValue).font(.title2.bold())
            Spacer()
            if selectedTab == .memo {
                Button { section = .tasks } label: {
                    Image(systemName: "checklist")
                        .foregroundStyle(section == .tasks ? .blue : .white.opacity(0.55))
                }
                .buttonStyle(.borderless)
                .help("任务列表")
                Button { section = .trash } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(section == .trash ? .blue : .white.opacity(0.55))
                }
                .buttonStyle(.borderless)
                .help("回收站")
            }
        }
    }

    private var bottomTabBar: some View {
        HStack(spacing: 6) {
            tabButton(.memo, systemImage: "checklist")
            tabButton(.clipboard, systemImage: "doc.on.clipboard")
        }
        .padding(5)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
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

    private func tabButton(_ tab: AppTab, systemImage: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab }
        } label: {
            Label(tab.rawValue, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.48))
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(selectedTab == tab ? Color.blue.opacity(0.8) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var addTaskArea: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
            TextField("新建任务", text: $title)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit(addTask)
            Button {
                dueDate = hasDueDate ? dueDate : .now.addingTimeInterval(3600)
                showsNewTaskDateEditor.toggle()
            } label: {
                Image(systemName: hasDueDate ? "clock.fill" : "clock")
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

            Button {
                showsPriorityPicker.toggle()
            } label: {
                Circle().fill(newTaskPriority.color).frame(width: 11, height: 11)
            }
            .buttonStyle(.plain)
            .help("任务等级")
            .popover(isPresented: $showsPriorityPicker, arrowEdge: .bottom) {
                PriorityPickerPopover(selection: $newTaskPriority) {
                    showsPriorityPicker = false
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
                                TaskRow(task: task, isTrash: true, store: store)
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
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(taskGroups) { group in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.46))
                                    .padding(.leading, 4)
                                ForEach(group.tasks) { task in
                                    TaskRow(task: task, isTrash: false, store: store)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var taskGroups: [TaskGroup] {
        let tasks = visibleTasks
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

    private var visibleTasks: [TaskItem] {
        store.activeTasks.filter { task in
            completionFilter == .completed ? task.isCompleted : !task.isCompleted
        }
    }

    private func addTask() {
        store.add(title: title, dueDate: hasDueDate ? dueDate : nil, priority: newTaskPriority)
        title = ""
        hasDueDate = false
        dueDate = .now.addingTimeInterval(3600)
        newTaskPriority = .blue
        titleFocused = true
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let isTrash: Bool
    @ObservedObject var store: TaskStore
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var showsDateEditor = false
    @State private var showsPriorityEditor = false
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
                if let due = task.dueDate {
                    Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(due < .now && !task.isCompleted ? .red : .white.opacity(0.45))
                }
                if !isTrash, let subtasks = task.subtasks, !subtasks.isEmpty {
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
            } else if isHovered || showsDateEditor || showsPriorityEditor {
                Button {
                    let willExpand = !isSubtaskListExpanded
                    withAnimation(.easeInOut(duration: 0.16)) { isSubtaskListExpanded = willExpand }
                    if willExpand { DispatchQueue.main.async { subtaskFocused = true } }
                } label: {
                    Image(systemName: isSubtaskListExpanded ? "chevron.up" : "list.bullet.indent")
                }
                .buttonStyle(.borderless)
                .help(isSubtaskListExpanded ? "收起子任务" : "添加或管理子任务")

                Button {
                    showsPriorityEditor.toggle()
                } label: {
                    Circle()
                        .fill((task.priority ?? .blue).color)
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
                        onSelect: { showsPriorityEditor = false }
                    )
                }

                Button {
                    draftDate = task.dueDate ?? .now.addingTimeInterval(3600)
                    showsDateEditor.toggle()
                } label: {
                    Image(systemName: task.dueDate == nil ? "clock" : "clock.fill")
                }
                .buttonStyle(.borderless)
                .help("修改结束时间")
                .popover(isPresented: $showsDateEditor, arrowEdge: .trailing) { dateEditor }

                Button(role: .destructive) { store.delete(task) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("移到回收站")
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill((task.priority ?? .blue).color)
                        .frame(width: 8, height: 8)
                    Text((task.priority ?? .blue).title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            }

            if isSubtaskListExpanded && !isTrash {
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

    private var subtaskList: some View {
        VStack(spacing: 8) {
            Divider().overlay(.white.opacity(0.08))

            ForEach(task.subtasks ?? []) { subtask in
                SubtaskRow(task: task, subtask: subtask, store: store)
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
                if let dueDate = subtask.dueDate {
                    Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(dueDate < .now && !subtask.isCompleted ? .red : .white.opacity(0.42))
                }
            }
            Spacer()

            if isHovered || showsDateEditor || showsPriorityEditor {
                Button { showsPriorityEditor.toggle() } label: {
                    Circle()
                        .fill((subtask.priority ?? .blue).color)
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
                        onSelect: { showsPriorityEditor = false }
                    )
                }

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

                Button(role: .destructive) {
                    store.deleteSubtask(from: task, subtask: subtask)
                } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("删除子任务")
            } else {
                HStack(spacing: 5) {
                    Circle().fill((subtask.priority ?? .blue).color).frame(width: 7, height: 7)
                    Text((subtask.priority ?? .blue).title)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
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

private extension TaskPriority {
    var title: String {
        switch self {
        case .blue: "普通"
        case .yellow: "一般"
        case .orange: "重要"
        case .red: "紧急"
        }
    }

    var color: Color {
        switch self {
        case .blue: .blue
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        }
    }
}

private struct PriorityPickerPopover: View {
    @Binding var selection: TaskPriority
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button {
                    selection = priority
                    onSelect()
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(priority.color).frame(width: 11, height: 11)
                        Text(priority.title)
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
