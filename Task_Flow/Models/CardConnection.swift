import Foundation
import SwiftData

@Model
final class CardConnection {
    var id: UUID
    var fromColumnID: UUID
    var toColumnID: UUID

    init(fromColumnID: UUID, toColumnID: UUID) {
        self.id = UUID()
        self.fromColumnID = fromColumnID
        self.toColumnID = toColumnID
    }
}
