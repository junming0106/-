import Foundation
import SwiftData
import SwiftUI

@Model
final class CardConnection {
    var id: UUID
    var fromColumnID: UUID
    var toColumnID: UUID
    var colorName: String

    var board: Board?

    init(fromColumnID: UUID, toColumnID: UUID, colorName: String = "gray") {
        self.id = UUID()
        self.fromColumnID = fromColumnID
        self.toColumnID = toColumnID
        self.colorName = colorName
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
        case "yellow": return .yellow
        case "white": return .white
        default: return Color(red: 0.45, green: 0.47, blue: 0.50) // space gray
        }
    }

    static let colorOptions = ["gray", "blue", "purple", "green", "orange", "red", "pink", "teal", "indigo", "yellow", "white"]
}
