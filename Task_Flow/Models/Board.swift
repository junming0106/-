import Foundation
import SwiftData
import SwiftUI

@Model
final class Board {
    var id: UUID
    var name: String
    var iconName: String
    var colorName: String
    var createdAt: Date
    var order: Int

    @Relationship(deleteRule: .cascade, inverse: \BoardColumn.board)
    var columns: [BoardColumn]

    @Relationship(deleteRule: .cascade, inverse: \Workspace.board)
    var workspaces: [Workspace]

    @Relationship(deleteRule: .cascade, inverse: \CardConnection.board)
    var connections: [CardConnection]

    init(
        name: String = "New Board",
        iconName: String = "rectangle.split.3x1",
        colorName: String = "blue",
        order: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.colorName = colorName
        self.createdAt = Date()
        self.order = order
        self.columns = []
        self.workspaces = []
        self.connections = []
    }

    var displayColor: Color {
        switch colorName {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .blue
        }
    }

    static let iconOptions = [
        "rectangle.split.3x1", "list.bullet.rectangle", "square.grid.2x2",
        "folder", "tray.full", "archivebox",
        "star", "heart", "bolt",
        "lightbulb", "flag", "tag",
        "person.2", "gear", "cube",
        "doc.text", "book", "graduationcap",
    ]
}
