import Foundation
import SwiftUI

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published var errorMessage: String?
    @Published private(set) var focusAddRequest = 0
    @Published private(set) var resetMemoListRequest = 0

    private let repository: any TaskRepository

    init(repository: any TaskRepository) {
        self.repository = repository
    }

    var activeTasks: [TaskItem] {
        tasks.filter { $0.deletedAt == nil }.sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            switch ($0.dueDate, $1.dueDate) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return $0.createdAt > $1.createdAt
            }
        }
    }

    var deletedTasks: [TaskItem] {
        tasks.filter { $0.deletedAt != nil }.sorted {
            ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
        }
    }

    func load() {
        Task {
            do { tasks = try await repository.load() }
            catch { errorMessage = "读取任务失败：\(error.localizedDescription)" }
        }
    }

    func add(title: String, dueDate: Date?, priority: TaskPriority = .blue, categoryID: String? = nil) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        tasks.append(TaskItem(title: cleaned, dueDate: dueDate, priority: priority, categoryID: categoryID))
        persist()
    }

    func requestAddFocus() {
        focusAddRequest += 1
    }

    func requestMemoListReset() {
        resetMemoListRequest += 1
    }

    func toggle(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted.toggle()
        persist()
    }

    func delete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].deletedAt = .now
        persist()
    }

    func restore(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].deletedAt = nil
        persist()
    }

    func permanentlyDelete(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        persist()
    }

    func emptyTrash() {
        tasks.removeAll { $0.deletedAt != nil }
        persist()
    }

    func updateTitle(_ task: TaskItem, title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].title = cleaned
        persist()
    }

    func updateDueDate(_ task: TaskItem, dueDate: Date?) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].dueDate = dueDate
        persist()
    }

    func updatePriority(_ task: TaskItem, priority: TaskPriority) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].priority = priority
        persist()
    }

    func updateCategory(_ task: TaskItem, categoryID: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].categoryID = categoryID
        persist()
    }

    func addSubtask(to task: TaskItem, title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        if tasks[index].subtasks == nil { tasks[index].subtasks = [] }
        tasks[index].subtasks?.append(SubtaskItem(title: cleaned))
        persist()
    }

    func toggleSubtask(in task: TaskItem, subtask: SubtaskItem) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == task.id }),
              let subtaskIndex = tasks[taskIndex].subtasks?.firstIndex(where: { $0.id == subtask.id }) else { return }
        tasks[taskIndex].subtasks?[subtaskIndex].isCompleted.toggle()
        persist()
    }

    func deleteSubtask(from task: TaskItem, subtask: SubtaskItem) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[taskIndex].subtasks?.removeAll { $0.id == subtask.id }
        persist()
    }

    func updateSubtaskDueDate(in task: TaskItem, subtask: SubtaskItem, dueDate: Date?) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == task.id }),
              let subtaskIndex = tasks[taskIndex].subtasks?.firstIndex(where: { $0.id == subtask.id }) else { return }
        tasks[taskIndex].subtasks?[subtaskIndex].dueDate = dueDate
        persist()
    }

    func updateSubtaskPriority(in task: TaskItem, subtask: SubtaskItem, priority: TaskPriority) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == task.id }),
              let subtaskIndex = tasks[taskIndex].subtasks?.firstIndex(where: { $0.id == subtask.id }) else { return }
        tasks[taskIndex].subtasks?[subtaskIndex].priority = priority
        persist()
    }

    private func persist() {
        let snapshot = tasks
        Task {
            do { try await repository.save(snapshot) }
            catch { errorMessage = "保存任务失败：\(error.localizedDescription)" }
        }
    }
}
