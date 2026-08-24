import Foundation

enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case blue
    case yellow
    case orange
    case red
}

struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var dueDate: Date?
    var isCompleted: Bool
    var deletedAt: Date?
    var priority: TaskPriority?
    let createdAt: Date

    init(id: UUID = UUID(), title: String, dueDate: Date? = nil, isCompleted: Bool = false, deletedAt: Date? = nil, priority: TaskPriority = .blue, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.deletedAt = deletedAt
        self.priority = priority
        self.createdAt = createdAt
    }
}
