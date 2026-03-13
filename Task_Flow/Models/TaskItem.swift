import Foundation
import SwiftData

enum TaskPriority: String, Codable, CaseIterable {
    case urgent = "Urgent"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var color: String {
        switch self {
        case .urgent: return "red"
        case .high: return "orange"
        case .medium: return "yellow"
        case .low: return "green"
        }
    }

    var icon: String {
        switch self {
        case .urgent: return "circle.fill"
        case .high: return "circle.bottomhalf.filled"
        case .medium: return "circle.lefthalf.filled"
        case .low: return "circle"
        }
    }
}

@Model
final class TaskItem {
    var id: UUID
    var title: String
    var taskDescription: String
    var priority: TaskPriority
    var dueDate: Date?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var order: Int

    var column: BoardColumn?

    var subtasks: [SubTask]

    init(
        title: String,
        taskDescription: String = "",
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        tags: [String] = [],
        order: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.taskDescription = taskDescription
        self.priority = priority
        self.dueDate = dueDate
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
        self.order = order
        self.subtasks = []
    }
}

@Model
final class SubTask {
    var id: UUID
    var title: String
    var isCompleted: Bool

    var parentTask: TaskItem?

    init(title: String, isCompleted: Bool = false) {
        self.id = UUID()
        self.title = title
        self.isCompleted = isCompleted
    }
}
