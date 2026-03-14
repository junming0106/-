import Foundation
import SwiftData

@Model
final class BoardColumn {
    var id: UUID
    var title: String
    var order: Int
    var colorName: String
    var wipLimit: Int
    var iconName: String
    var positionX: Double
    var positionY: Double

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.column)
    var tasks: [TaskItem]

    var workspace: Workspace?

    init(
        title: String,
        order: Int,
        colorName: String = "blue",
        wipLimit: Int = 0,
        iconName: String = "list.bullet",
        positionX: Double = 0,
        positionY: Double = 0
    ) {
        self.id = UUID()
        self.title = title
        self.order = order
        self.colorName = colorName
        self.wipLimit = wipLimit
        self.iconName = iconName
        self.positionX = positionX
        self.positionY = positionY
        self.tasks = []
    }

    var sortedTasks: [TaskItem] {
        tasks.sorted { $0.order < $1.order }
    }

    var color: ColorOption {
        ColorOption(rawValue: colorName) ?? .blue
    }
}

enum ColorOption: String, CaseIterable {
    case blue, purple, green, orange, red, pink, teal, indigo

    var displayName: String { rawValue.capitalized }
}
