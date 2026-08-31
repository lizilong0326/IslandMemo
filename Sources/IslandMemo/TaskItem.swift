import Foundation

enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case blue
    case yellow
    case orange
    case red
}

struct SubtaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var priority: TaskPriority?
    let createdAt: Date

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, dueDate: Date? = nil, priority: TaskPriority = .blue, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.priority = priority
        self.createdAt = createdAt
    }
}

struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var dueDate: Date?
    var isCompleted: Bool
    var deletedAt: Date?
    var priority: TaskPriority?
    var subtasks: [SubtaskItem]?
    let createdAt: Date

    init(id: UUID = UUID(), title: String, dueDate: Date? = nil, isCompleted: Bool = false, deletedAt: Date? = nil, priority: TaskPriority = .blue, subtasks: [SubtaskItem] = [], createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.deletedAt = deletedAt
        self.priority = priority
        self.subtasks = subtasks
        self.createdAt = createdAt
    }
}
